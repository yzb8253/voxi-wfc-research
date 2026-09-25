[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [int]$ASettleSeconds = 60,
    [int]$PSettleSeconds = 60,
    [ValidateRange(1,3)][int]$MaxRecoveryAttempts = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Preflight = Join-Path $PSScriptRoot 'repeatability_preflight.ps1'
$Recovery = Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$LogDir = Join-Path $PSScriptRoot 'Stable-Logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ('X55-WFC-STABLE-{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'
$ExpectedFingerprint = 'Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'

function Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Quote-Sh([string]$Value) {
    $single = [string][char]39
    $double = [string][char]34
    $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}

function Invoke-Adb([string[]]$Arguments) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Adb
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Arguments = (@($Arguments | ForEach-Object {
        if($_ -match '[\s"]') { '"' + $_.Replace('"','\"') + '"' } else { $_ }
    }) -join ' ')

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if(-not $process.Start()) { throw 'Unable to start adb.exe' }

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Text = (($stdout + $stderr).Trim())
    }
}

function RootResult([string]$Command) {
    Invoke-Adb @('-s',$Serial,'shell',('su -c ' + (Quote-Sh $Command)))
}

function Root([string]$Command) {
    $r = RootResult $Command
    if($r.ExitCode -ne 0) {
        throw "ADB/root command failed: $Command`n$($r.Text)"
    }
    $r.Text.Trim()
}

function Require([bool]$Condition,[string]$Message) {
    if(-not $Condition) { throw $Message }
}

function Get-AirplaneMode {
    (Root 'settings get global airplane_mode_on').Trim()
}

function Set-AirplaneMode([bool]$Enabled) {
    $expected = if($Enabled) { '1' } else { '0' }
    if((Get-AirplaneMode) -eq $expected) {
        Log ("AIRPLANE already {0}" -f $(if($Enabled){'ON'}else{'OFF'}))
        return
    }

    $action = if($Enabled) { 'enable' } else { 'disable' }
    Log ("AIRPLANE auto -> {0}" -f $action)
    $r = RootResult ("cmd connectivity airplane-mode {0}" -f $action)
    if($r.Text) { Log ("AIRPLANE_CMD: " + $r.Text) }
    Start-Sleep -Seconds 3

    if((Get-AirplaneMode) -ne $expected) {
        Write-Host ''
        Write-Host ("[MANUAL FALLBACK] Please turn airplane mode {0} on the phone, then press Enter." -f $(if($Enabled){'ON'}else{'OFF'})) -ForegroundColor Yellow
        [void](Read-Host)
    }

    Require ((Get-AirplaneMode) -eq $expected) ("Airplane mode failed to become {0}." -f $expected)
}

function Ensure-WifiOn {
    [void](RootResult 'svc wifi enable')
    Start-Sleep -Seconds 3
    $wifi = (Root 'settings get global wifi_on').Trim()

    if($wifi -eq '0') {
        Write-Host ''
        Write-Host '[MANUAL FALLBACK] Please turn Wi-Fi ON on the phone, then press Enter.' -ForegroundColor Yellow
        [void](Read-Host)
        $wifi = (Root 'settings get global wifi_on').Trim()
    }

    Require ($wifi -ne '0') 'Wi-Fi is still disabled.'
    Log ("WIFI_SETTING={0}" -f $wifi)
}

function Get-WfcStatusText {
    $r = RootResult "$WfcCtl status"
    # The validated v2.6.2 core treats wfcctl status as a probe and parses
    # its text even when the helper returns a non-zero process exit code.
    # Do the same here: fail only when the expected status body is missing.
    Require (-not [string]::IsNullOrWhiteSpace($r.Text)) 'wfcctl status returned no output.'
    Require ($r.Text -match '(?m)^IMS:\s+' -and $r.Text -match '(?m)^WFC:\s+') 'wfcctl status output is incomplete.'
    $r.Text
}

function Get-WfcStatusJson {
    $r = RootResult "$WfcCtl status-json"
    Require ($r.ExitCode -eq 0) 'wfcctl status-json failed.'
    $line = @($r.Text -split "\r?\n" | Where-Object { $_.Trim().StartsWith('{') }) | Select-Object -Last 1
    Require (-not [string]::IsNullOrWhiteSpace($line)) 'wfcctl status-json did not return JSON.'
    $line | ConvertFrom-Json
}

function Test-WfcHealthy {
    $text = Get-WfcStatusText
    ($text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$') -and
    ($text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$') -and
    ($text -match '(?m)^VOICE/IWLAN:\s+AVAILABLE\s*$') -and
    ($text -match '(?m)^WFC:\s+AVAILABLE\s*$')
}

function Get-CneSnapshot {
    $text = Get-WfcStatusText
    $registered = 'UNKNOWN'
    $active = 'UNKNOWN'
    $request = 'null'
    $satisfied = 'null'

    if($text -match 'qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)\s+request=([^\s]+)\s+satisfied=([^\s]+)') {
        $registered = $Matches[1]
        $active = $Matches[2]
        $request = $Matches[3]
        $satisfied = $Matches[4]
    }

    [pscustomobject]@{
        Registered = $registered
        Active = $active
        Request = $request
        Satisfied = $satisfied
    }
}

function Assert-PlatformAndTarget {
    Require (Test-Path -LiteralPath $Adb) ("adb.exe not found: {0}" -f $Adb)
    Require (Test-Path -LiteralPath $Preflight) ("preflight missing: {0}" -f $Preflight)
    Require (Test-Path -LiteralPath $Recovery) ("v2.6.2 recovery missing: {0}" -f $Recovery)

    $devices = Invoke-Adb @('devices')
    Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") ("ADB target not online: {0}" -f $Serial)
    Require ((Root 'id') -match 'uid=0\(root\)') 'Root access unavailable.'

    $device = Root 'getprop ro.product.device'
    $android = Root 'getprop ro.build.version.release'
    $build = Root 'getprop ro.build.version.incremental'
    $fingerprint = Root 'getprop ro.build.fingerprint'

    Require ($device -eq $ExpectedDevice) ("Unexpected device: {0}" -f $device)
    Require ($android -eq $ExpectedAndroid) ("Unexpected Android version: {0}" -f $android)
    Require ($build -eq $ExpectedBuild) ("Unexpected ROM build: {0}" -f $build)
    Require ($fingerprint -eq $ExpectedFingerprint) 'Unexpected ROM fingerprint.'

    $status = Get-WfcStatusJson
    Require ($status.target.mappingGate) 'VOXI mapping gate failed.'
    Require ($status.target.subId -eq 11) 'VOXI subId changed.'
    Require ($status.target.slotId -eq 1) 'VOXI slotId changed.'
    Require ($status.target.phoneId -eq 1) 'VOXI phoneId changed.'
    Require ($status.target.carrierId -eq 28) 'VOXI carrierId changed.'
    Require ($status.target.mcc -eq 234 -and $status.target.mnc -eq 15) 'VOXI MCC/MNC changed.'
    Require ($status.subscription.active) 'VOXI subscription is not active.'
    Require ($status.subscription.areUiccApplicationsEnabled) 'VOXI UICC applications are not enabled.'

    Log 'SAFETY_GATE=PASS cas/Android13/validated ROM, VOXI slot1/sub11/23415'
}

function Invoke-PreflightNormalization {
    Require ((Get-AirplaneMode) -eq '0') 'Normalization is only allowed with airplane mode OFF.'

    Log 'PREFLIGHT_APPLY_NORMALIZATION=START'

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Preflight + '" -Serial ' + $Serial + ' -ApplyNormalization'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    if(-not $proc.Start()) { throw 'Unable to start repeatability preflight.' }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $rc = $proc.ExitCode
    $proc.Dispose()

    $text = (($stdout + [Environment]::NewLine + $stderr).Trim())
    if($text) { Write-Host $text }

    Require ($rc -eq 0) ("Preflight normalization failed with exit code {0}." -f $rc)
    Require ($text -match 'PREFLIGHT_RESULT=(A0_READY|A0_NORMALIZED)') 'Preflight did not confirm A0_READY/A0_NORMALIZED.'
    Log ("PREFLIGHT_APPLY_NORMALIZATION=PASS result={0}" -f $Matches[1])
}

function Prepare-A0 {
    Log 'A0_PREP=START'
    Require ((Get-AirplaneMode) -eq '0') 'Entry/normalization requires airplane mode OFF.'
    Ensure-WifiOn
    Log ("A_SETTLE={0}s" -f $ASettleSeconds)
    Start-Sleep -Seconds $ASettleSeconds
    Invoke-PreflightNormalization

    Require ((Get-AirplaneMode) -eq '0') 'A0 verification failed: airplane mode is not OFF.'
    $cne = Get-CneSnapshot
    Log ("A0_CNE registered={0} active={1} request={2} satisfied={3}" -f $cne.Registered,$cne.Active,$cne.Request,$cne.Satisfied)
    Require ($cne.Request -eq 'null') ("A0 is native-clean but qti.cne request is still active: {0}" -f $cne.Request)
    Log 'A0_PREP=PASS request=null'
}

function Prepare-P {
    Log 'P_PREP=START'
    Set-AirplaneMode $true
    Ensure-WifiOn
    Log ("P_SETTLE={0}s" -f $PSettleSeconds)
    Start-Sleep -Seconds $PSettleSeconds

    if(Test-WfcHealthy) {
        Log 'P_PREP=ALREADY_HEALTHY'
        return $true
    }

    $cne = Get-CneSnapshot
    Log ("P_CNE registered={0} active={1} request={2} satisfied={3}" -f $cne.Registered,$cne.Active,$cne.Request,$cne.Satisfied)

    if($cne.Request -ne 'null') {
        Write-Host ("[CNE GATE] Existing request {0} detected before v2.6.2. Core recovery is blocked; return to A0 and normalize instead." -f $cne.Request) -ForegroundColor Yellow
        Log ("P_CNE_GATE=BLOCK_EXISTING_REQUEST request={0}" -f $cne.Request)
        return $false
    }

    Log 'P_CNE_GATE=PASS request=null'
    return $true
}

function Invoke-V262Core {
    Log 'V262_CORE=START'

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Recovery + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    if(-not $proc.Start()) { throw 'Unable to start v2.6.2 core.' }

    # Feed one newline now; the v2.6.2 final Read-Host consumes it after it finishes.
    $proc.StandardInput.WriteLine('')
    $proc.StandardInput.Flush()
    $proc.WaitForExit()
    $rc = $proc.ExitCode
    $proc.Dispose()

    Log ("V262_CORE=EXIT code={0}" -f $rc)
    $rc
}

Log '============================================================'
Log 'X55 WFC STABLE WRAPPER v1 started'
Log ("Serial={0} MaxRecoveryAttempts={1}" -f $Serial,$MaxRecoveryAttempts)
Log 'Core recovery file is the unchanged proven v2.6.2 freeze-on-success script.'
Log '============================================================'

try {
    Assert-PlatformAndTarget

    $entryAirplane = Get-AirplaneMode
    Require ($entryAirplane -eq '0') 'USER ENTRY GATE: start the stable script with airplane mode OFF.'
    Log 'ENTRY_GATE=PASS airplane=OFF'

    for($attempt = 1; $attempt -le $MaxRecoveryAttempts; $attempt++) {
        Write-Host ''
        Write-Host '============================================================'
        Write-Host (" STABLE RECOVERY ATTEMPT {0}/{1}" -f $attempt,$MaxRecoveryAttempts)
        Write-Host '============================================================'
        Log ("ATTEMPT={0} START" -f $attempt)

        Prepare-A0

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} HEALTHY_IN_A_UNEXPECTED_BUT_ACCEPTED" -f $attempt)
            Write-Host '[OK] WFC became healthy before P entry. Leaving state untouched.' -ForegroundColor Green
            exit 0
        }

        $pGate = Prepare-P

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} HEALTHY_BEFORE_CORE" -f $attempt)
            Write-Host '[OK] WFC became healthy before the core recovery. Leaving airplane mode ON and state untouched.' -ForegroundColor Green
            exit 0
        }

        if(-not $pGate) {
            if($attempt -lt $MaxRecoveryAttempts) {
                Log 'BOUNDED_RETRY=P_CNE_GATE_DIRTY_RETURN_TO_A'
                Set-AirplaneMode $false
                continue
            }
            throw 'P CNE gate remained dirty on the final bounded attempt; v2.6.2 was not executed.'
        }

        $coreRc = Invoke-V262Core

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} SUCCESS coreExit={1}" -f $attempt,$coreRc)
            Log 'FINAL=WFC_HEALTHY_FREEZE'
            Write-Host ''
            Write-Host '[OK] STABLE WRAPPER RESULT: WFC HEALTHY. Frozen healthy state is preserved.' -ForegroundColor Green
            exit 0
        }

        $afterCne = Get-CneSnapshot
        Log ("ATTEMPT={0} FAILED coreExit={1} cneRequest={2} satisfied={3}" -f $attempt,$coreRc,$afterCne.Request,$afterCne.Satisfied)

        if($attempt -lt $MaxRecoveryAttempts) {
            Write-Host ''
            Write-Host '[RETRY] WFC is not healthy. Returning to airplane-OFF A state, applying the proven normalization, then retrying from a fresh P state.' -ForegroundColor Yellow
            Log 'BOUNDED_RETRY=RETURN_TO_A0'
            Set-AirplaneMode $false
            continue
        }
    }

    Write-Host ''
    Write-Host '[FINAL RECOVERY] Attempts exhausted. Restoring a clean airplane-OFF A0 state if possible.' -ForegroundColor Yellow
    try {
        Set-AirplaneMode $false
        Prepare-A0
        Log 'FINAL_SAFE_A0_RESTORE=PASS'
    }
    catch {
        Log ("FINAL_SAFE_A0_RESTORE=FAIL {0}" -f $_.Exception.Message)
    }

    Log 'FINAL=WFC_NOT_RECOVERED'
    Write-Host '[FAIL] WFC was not recovered within the bounded attempts.' -ForegroundColor Red
    exit 20
}
catch {
    Log ("FATAL={0}" -f $_.Exception.Message)
    Write-Host ''
    Write-Host ('[STOP] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No further automatic recovery action will be attempted.' -ForegroundColor Yellow
    exit 30
}
