# X55-VOXI-PassiveMonitor-v1.0.ps1
# Passive / read-only monitor for Xiaomi 10 (cas) + VOXI slot2 WFC experiments.
#
# This script DOES NOT change:
# - airplane mode
# - Wi-Fi
# - VPN / FlClash
# - Android system location
# - Anywhere
# - SIM power
# - X55 modem state
#
# You operate the phone manually. This script only reads state and records a timeline.

$ErrorActionPreference = 'Stop'

# ---------------- CONFIG ----------------
$Serial = 'fd0ff892'
$Adb = 'C:\Users\ZJH\Desktop\platform-tools\adb.exe'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'

$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'

$SampleEverySec = 2
$HeartbeatSec = 10

$Desktop = Join-Path $env:USERPROFILE 'Desktop'
$BaseDir = Join-Path $Desktop 'WFC-PassiveMonitor'
$SessionDir = Join-Path $BaseDir (Get-Date -Format 'yyyyMMdd_HHmmss')
$TimelineCsv = Join-Path $SessionDir 'timeline.csv'
$EventsLog = Join-Path $SessionDir 'events.log'
$LogcatFile = Join-Path $SessionDir 'adb-logcat.txt'
$LogcatErr = Join-Path $SessionDir 'adb-logcat-error.txt'
$LatestStatus = Join-Path $SessionDir 'latest-wfc-status.txt'
$LatestSlot1 = Join-Path $SessionDir 'latest-slot1.txt'
$LatestLocation = Join-Path $SessionDir 'latest-location.txt'

New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null

# ---------------- HELPERS ----------------
function Stamp {
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
}

function Log-Event {
    param([string]$Text)
    $line = '[{0}] {1}' -f (Stamp), $Text
    Write-Host $line
    try { Add-Content -LiteralPath $EventsLog -Value $line -Encoding UTF8 } catch {}
}

function Save-Text {
    param(
        [string]$Path,
        [AllowEmptyString()][string]$Text
    )
    try {
        [System.IO.File]::WriteAllText(
            $Path,
            $Text,
            (New-Object System.Text.UTF8Encoding($false))
        )
    } catch {}
}

function ConvertTo-WindowsCommandLineArg {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashCount = 0

    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $slashCount++
            continue
        }

        if ($ch -eq '"') {
            if ($slashCount -gt 0) {
                [void]$sb.Append(('\' * ($slashCount * 2)))
                $slashCount = 0
            }
            [void]$sb.Append('\"')
            continue
        }

        if ($slashCount -gt 0) {
            [void]$sb.Append(('\' * $slashCount))
            $slashCount = 0
        }

        [void]$sb.Append($ch)
    }

    if ($slashCount -gt 0) {
        [void]$sb.Append(('\' * ($slashCount * 2)))
    }

    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-AdbResult {
    param(
        [Parameter(Mandatory=$true)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $quoted = @()
    foreach ($arg in $Arguments) {
        $quoted += (ConvertTo-WindowsCommandLineArg -Value $arg)
    }
    $psi.Arguments = ($quoted -join ' ')

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        if (-not $proc.Start()) { throw 'Failed to start adb.exe' }

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $proc.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $parts += $stdout.TrimEnd("`r","`n")
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            $parts += $stderr.TrimEnd("`r","`n")
        }

        [pscustomobject]@{
            Code = $proc.ExitCode
            Text = (($parts -join [Environment]::NewLine).Trim())
        }
    }
    finally {
        if ($null -ne $proc) { $proc.Dispose() }
    }
}

function Invoke-Adb {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $r = Invoke-AdbResult -Arguments (@('-s',$Serial) + $Arguments)
    if ($r.Code -ne 0) {
        throw ('ADB failed ({0}): {1}`r`n{2}' -f $r.Code,($Arguments -join ' '),$r.Text)
    }
    return $r.Text
}

function Invoke-RootRead {
    param([Parameter(Mandatory=$true)][string]$Command)

    $r = Invoke-AdbResult -Arguments @(
        '-s',$Serial,'shell',"su -c '$Command'"
    )

    if ($r.Code -ne 0) {
        throw ('ROOT read failed ({0}): {1}`r`n{2}' -f $r.Code,$Command,$r.Text)
    }

    return $r.Text
}

function Get-WfcStatus {
    # wfcctl intentionally returns non-zero classification codes when WFC is unhealthy.
    # A valid status report is accepted regardless of its exit code.
    $r = Invoke-AdbResult -Arguments @(
        '-s',$Serial,'shell',"su -c '$WfcCtl status'"
    )

    if ($r.Text -match 'VOXI WFC Recovery' -and
        $r.Text -match 'VOXI:\s+slot=1' -and
        $r.Text -match 'CORE HEALTH:') {
        return $r.Text
    }

    throw ('wfcctl returned no valid report. ExitCode={0}`r`n{1}' -f $r.Code,$r.Text)
}

function Get-Slot1ServiceState {
    $t = Invoke-Adb @('shell','dumpsys','telephony.registry')
    $lines = @(
        $t -split "`r?`n" |
        Where-Object { $_ -match '^\s+mServiceState=' }
    )

    if ($lines.Count -ge 2) { return $lines[1].Trim() }
    if ($lines.Count -eq 1) { return $lines[0].Trim() }
    return ''
}

function Get-AirplaneState {
    try {
        $x = (Invoke-Adb @('shell','settings','get','global','airplane_mode_on')).Trim()
        if ($x -eq '1') { return 'ON' }
        if ($x -eq '0') { return 'OFF' }
        return $x
    } catch { return 'UNKNOWN' }
}

function Get-WifiState {
    try {
        $t = Invoke-Adb @('shell','cmd','wifi','status')
        $enabled = if ($t -match 'Wifi is enabled') { 'ON' } else { 'OFF' }
        $connected = if ($t -match 'Wifi is connected to') { 'YES' } else { 'NO' }
        $ssid = ''
        $m = [regex]::Match($t,'Wifi is connected to\s+"([^"]+)"')
        if ($m.Success) { $ssid = $m.Groups[1].Value }

        return [pscustomobject]@{
            Enabled = $enabled
            Connected = $connected
            Ssid = $ssid
        }
    } catch {
        return [pscustomobject]@{
            Enabled = 'UNKNOWN'
            Connected = 'UNKNOWN'
            Ssid = ''
        }
    }
}

function Get-LocationState {
    try {
        $enabled = (Invoke-Adb @('shell','cmd','location','is-location-enabled')).Trim()
        $mode = (Invoke-Adb @('shell','settings','get','secure','location_mode')).Trim()

        $dump = Invoke-Adb @('shell','dumpsys','location')
        Save-Text $LatestLocation $dump

        $mock = 'NONE'
        if ($dump -match 'com\.cxorz\.anywhere') {
            if ($dump -match '(?i)mock') {
                $mock = 'ANYWHERE_SEEN'
            } else {
                $mock = 'ANYWHERE_PROCESS_REF'
            }
        } elseif ($dump -match '(?i)mock') {
            $mock = 'OTHER_MOCK_SEEN'
        }

        return [pscustomobject]@{
            Enabled = $enabled
            Mode = $mode
            Mock = $mock
        }
    } catch {
        return [pscustomobject]@{
            Enabled = 'UNKNOWN'
            Mode = 'UNKNOWN'
            Mock = 'UNKNOWN'
        }
    }
}

function Get-AnywhereProcessState {
    try {
        $r = Invoke-AdbResult -Arguments @(
            '-s',$Serial,'shell','pidof','com.cxorz.anywhere'
        )
        if (-not [string]::IsNullOrWhiteSpace($r.Text)) { return 'RUNNING' }
        if ($r.Code -eq 0 -or $r.Code -eq 1) { return 'NOT_RUNNING' }
        return 'UNKNOWN'
    } catch {
        return 'UNKNOWN'
    }
}

function Get-VpnState {
    try {
        $t = Invoke-Adb @('shell','dumpsys','connectivity')

        if ($t -match 'VPN CONNECTED' -and $t -match 'sessionId=FlClash') {
            return 'FLCLASH_CONNECTED'
        }
        if ($t -match 'VPN CONNECTED') {
            return 'VPN_CONNECTED'
        }
        if ($t -match 'sessionId=FlClash') {
            return 'FLCLASH_SEEN_NOT_CONNECTED'
        }
        return 'NOT_CONNECTED'
    } catch {
        return 'UNKNOWN'
    }
}

function Get-RecentKeyLog {
    if (-not (Test-Path $LogcatFile)) { return '' }

    try {
        $tail = Get-Content -LiteralPath $LogcatFile -Tail 1500 -ErrorAction Stop
        $keep = @()

        foreach ($line in $tail) {
            if ($line -match 'networkMode=19|RatRequested|StartDataCall|qualifiedNetworks|registrationState=HOME|NOT_REG_OR_SEARCHING|IWlanProxy|SIM_STATE_CHANGED|state=LOADED|state=ABSENT|UICC|ePDG') {
                $keep += $line
            }
        }

        return ($keep -join "`r`n")
    } catch {
        return ''
    }
}

function Parse-State {
    param(
        [string]$Status,
        [string]$Slot1,
        [string]$KeyLog,
        [object]$Wifi,
        [object]$Location,
        [string]$Airplane,
        [string]$Vpn,
        [string]$Anywhere
    )

    $iwlanHome = if ($Slot1 -match 'transportType=WLAN registrationState=HOME') { '1' } else { '0' }
    $iwlanDataService = if ($Slot1 -match 'transportType=WLAN registrationState=HOME[^\}]*availableServices=\[DATA\]') { '1' } else { '0' }
    $preferred = if ($Slot1 -match 'mIsIwlanPreferred=true') { '1' } else { '0' }
    $dataIwlan = if ($Slot1 -match 'getRilDataRadioTechnology=18\(IWLAN\)') { '1' } else { '0' }
    $cellLte = if ($Slot1 -match 'mDataRegState=0\(IN_SERVICE\)' -and $Slot1 -match 'getRilDataRadioTechnology=14\(LTE\)') { '1' } else { '0' }

    $ims = if ($Status -match '(?m)^IMS:\s+REGISTERED') { '1' } else { '0' }
    $wfc = if ($Status -match '(?m)^WFC:\s+AVAILABLE') { '1' } else { '0' }
    $transport = 'UNKNOWN'
    $m = [regex]::Match($Status,'(?m)^Transport:\s+([^\r\n]+)')
    if ($m.Success) { $transport = $m.Groups[1].Value.Trim() }

    $cneReg = 'UNKNOWN'
    $cneActive = 'UNKNOWN'
    $request = 'null'

    $m = [regex]::Match(
        $Status,
        'qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)\s+request=([^\s]+)'
    )

    if ($m.Success) {
        $cneReg = $m.Groups[1].Value
        $cneActive = $m.Groups[2].Value
        $request = $m.Groups[3].Value
    }

    $requestState = if ($request -ne 'null' -and $request -ne '') { 'PRESENT' } else { 'NULL' }

    $epdg = if ($Status -match 'ePDG UDP/4500:\s+PRESENT') { '1' } else { '0' }
    $xfrm = if ($Status -match 'XFRM:\s+PRESENT') { '1' } else { '0' }
    $mmtel = if ($Status -match 'MMTEL:\s+READY') { '1' } else { '0' }

    $mode19 = 'NONE'
    $modeLines = @($KeyLog -split "`r?`n" | Where-Object { $_ -match 'networkMode=19' })
    if ($modeLines.Count -gt 0) {
        $lastMode = $modeLines[$modeLines.Count - 1]
        if ($lastMode -match 'status=2' -and $lastMode -match 'registered=1') {
            $mode19 = '2_1'
        }
        elseif ($lastMode -match 'status=0' -and $lastMode -match 'registered=2') {
            $mode19 = '0_2'
        }
        else {
            $mode19 = 'OTHER'
        }
    }

    $ratRequested = if ($KeyLog -match 'RatRequested') { '1' } else { '0' }
    $startDataCall = if ($KeyLog -match 'StartDataCall') { '1' } else { '0' }
    $qualified = if ($KeyLog -match 'qualifiedNetworks') { '1' } else { '0' }

    # Coarse state classification.
    # IMPORTANT: P1 does NOT require mIsIwlanPreferred=true.
    # We want to catch HOME+[DATA] as early as possible.
    $class = 'UNKNOWN'

    if ($ims -eq '1' -and $wfc -eq '1') {
        $class = 'HEALTHY'
    }
    elseif ($iwlanHome -eq '1' -and $requestState -eq 'PRESENT' -and $epdg -eq '0' -and $xfrm -eq '0' -and $ims -eq '0') {
        $class = 'P2'
    }
    elseif ($iwlanHome -eq '1' -and $dataIwlan -eq '1' -and $requestState -eq 'NULL' -and $ims -eq '0') {
        $class = 'P1'
    }
    elseif ($iwlanHome -eq '0' -and $requestState -eq 'NULL' -and $ims -eq '0') {
        $class = 'P0'
    }

    [pscustomobject]@{
        Time = Stamp
        Class = $class
        Airplane = $Airplane
        WifiEnabled = $Wifi.Enabled
        WifiConnected = $Wifi.Connected
        WifiSsid = $Wifi.Ssid
        LocationEnabled = $Location.Enabled
        LocationMode = $Location.Mode
        Mock = $Location.Mock
        Anywhere = $Anywhere
        Vpn = $Vpn
        CellLte = $cellLte
        IwlanHome = $iwlanHome
        IwlanDataService = $iwlanDataService
        DataIwlan = $dataIwlan
        Preferred = $preferred
        CneRegistered = $cneReg
        CneActive = $cneActive
        RequestState = $requestState
        RequestId = $request
        Mode19 = $mode19
        RatRequested = $ratRequested
        StartDataCall = $startDataCall
        QualifiedNetworks = $qualified
        Epdg = $epdg
        Xfrm = $xfrm
        Mmtel = $mmtel
        Ims = $ims
        Transport = $transport
        Wfc = $wfc
    }
}

function Append-Timeline {
    param([object]$State)

    if (Test-Path $TimelineCsv) {
        $State | Export-Csv -LiteralPath $TimelineCsv -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $State | Export-Csv -LiteralPath $TimelineCsv -NoTypeInformation -Encoding UTF8
    }
}

function Get-StateSignature {
    param([object]$S)

    return @(
        $S.Class,
        $S.Airplane,
        $S.WifiEnabled,
        $S.WifiConnected,
        $S.LocationEnabled,
        $S.Mock,
        $S.Anywhere,
        $S.Vpn,
        $S.CellLte,
        $S.IwlanHome,
        $S.DataIwlan,
        $S.Preferred,
        $S.CneRegistered,
        $S.RequestState,
        $S.Mode19,
        $S.RatRequested,
        $S.StartDataCall,
        $S.Epdg,
        $S.Xfrm,
        $S.Ims,
        $S.Wfc
    ) -join '|'
}

function Show-StateLine {
    param(
        [object]$S,
        [switch]$Important
    )

    $line = (
        '[{0}] {1,-7} AIR={2} WIFI={3}/{4} LOC={5} MOCK={6} VPN={7} LTE={8} HOME={9} DATAIWLAN={10} PREF={11} CNE={12}/{13} REQ={14} M19={15} RATREQ={16} STARTDC={17} ePDG={18} XFRM={19} IMS={20} WFC={21}' -f
        (Get-Date -Format 'HH:mm:ss'),
        $S.Class,
        $S.Airplane,
        $S.WifiEnabled,
        $S.WifiConnected,
        $S.LocationEnabled,
        $S.Mock,
        $S.Vpn,
        $S.CellLte,
        $S.IwlanHome,
        $S.DataIwlan,
        $S.Preferred,
        $S.CneRegistered,
        $S.CneActive,
        $S.RequestState,
        $S.Mode19,
        $S.RatRequested,
        $S.StartDataCall,
        $S.Epdg,
        $S.Xfrm,
        $S.Ims,
        $S.Wfc
    )

    if ($Important) {
        Write-Host $line -ForegroundColor Yellow
    }
    elseif ($S.Class -eq 'HEALTHY') {
        Write-Host $line -ForegroundColor Green
    }
    elseif ($S.Class -eq 'P1' -or $S.Class -eq 'P2') {
        Write-Host $line -ForegroundColor Cyan
    }
    else {
        Write-Host $line
    }
}

function Start-LogcatCapture {
    $args = @(
        '-s',$Serial,
        'logcat',
        '-b','all',
        '-v','threadtime',
        '-T','1'
    )

    return Start-Process `
        -FilePath $Adb `
        -ArgumentList $args `
        -RedirectStandardOutput $LogcatFile `
        -RedirectStandardError $LogcatErr `
        -PassThru `
        -WindowStyle Hidden
}

# ---------------- MAIN ----------------
$logcatProc = $null
$lastSignature = ''
$lastHeartbeat = Get-Date
$lastMode19 = 'NONE'
$lastRatRequested = '0'
$lastStartDataCall = '0'
$lastClass = ''

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' X55 + VOXI WFC PASSIVE MONITOR v1.0'
    Write-Host '============================================================'
    Write-Host 'READ ONLY: no airplane/Wi-Fi/VPN/location/SIM/X55 changes'
    Write-Host 'Operate the phone manually.'
    Write-Host 'Press Ctrl+C to stop.'
    Write-Host '============================================================'
    Write-Host ''

    if (-not (Test-Path $Adb)) {
        throw ('ADB not found: ' + $Adb)
    }

    $state = Invoke-Adb @('get-state')
    if ($state -notmatch 'device') {
        throw ('Device ' + $Serial + ' is not connected/authorized.')
    }

    $root = Invoke-RootRead 'id'
    if ($root -notmatch 'uid=0') {
        throw 'Magisk root is not available.'
    }

    $device = (Invoke-Adb @('shell','getprop','ro.product.device')).Trim()
    $android = (Invoke-Adb @('shell','getprop','ro.build.version.release')).Trim()
    $build = (Invoke-Adb @('shell','getprop','ro.build.version.incremental')).Trim()

    if ($device -ne $ExpectedDevice -or
        $android -ne $ExpectedAndroid -or
        $build -ne $ExpectedBuild) {
        throw ('Safety check failed. DEVICE={0} ANDROID={1} BUILD={2}' -f $device,$android,$build)
    }

    Write-Host ('DEVICE={0} ANDROID={1} BUILD={2}' -f $device,$android,$build)
    Write-Host ('SESSION={0}' -f $SessionDir)
    Write-Host ''

    Log-Event 'PASSIVE MONITOR START'
    Log-Event 'No phone/network settings will be changed by this monitor.'

    $logcatProc = Start-LogcatCapture
    Start-Sleep -Seconds 1

    while ($true) {
        $status = Get-WfcStatus
        $slot1 = Get-Slot1ServiceState
        $airplane = Get-AirplaneState
        $wifi = Get-WifiState
        $location = Get-LocationState
        $anywhere = Get-AnywhereProcessState
        $vpn = Get-VpnState
        $keyLog = Get-RecentKeyLog

        Save-Text $LatestStatus $status
        Save-Text $LatestSlot1 $slot1

        $s = Parse-State `
            -Status $status `
            -Slot1 $slot1 `
            -KeyLog $keyLog `
            -Wifi $wifi `
            -Location $location `
            -Airplane $airplane `
            -Vpn $vpn `
            -Anywhere $anywhere

        Append-Timeline $s

        $signature = Get-StateSignature $s
        $changed = ($signature -ne $lastSignature)

        $newDeepMarker = (
            ($s.Mode19 -ne 'NONE' -and $lastMode19 -eq 'NONE') -or
            ($s.RatRequested -eq '1' -and $lastRatRequested -eq '0') -or
            ($s.StartDataCall -eq '1' -and $lastStartDataCall -eq '0')
        )

        $newInterestingClass = (
            ($s.Class -eq 'P1' -or $s.Class -eq 'P2' -or $s.Class -eq 'HEALTHY') -and
            $s.Class -ne $lastClass
        )

        $heartbeatDue = (((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSec)

        if ($changed -or $heartbeatDue -or $newDeepMarker -or $newInterestingClass) {
            Show-StateLine -S $s -Important:($newDeepMarker -or $newInterestingClass)

            if ($newInterestingClass) {
                Log-Event (
                    'STATE -> {0}; HOME={1} DATAIWLAN={2} PREF={3} CNE={4} REQ={5} ePDG={6} XFRM={7} IMS={8} WFC={9}' -f
                    $s.Class,$s.IwlanHome,$s.DataIwlan,$s.Preferred,$s.CneRegistered,
                    $s.RequestState,$s.Epdg,$s.Xfrm,$s.Ims,$s.Wfc
                )

                try { [console]::Beep(1000,180) } catch {}
            }

            if ($newDeepMarker) {
                Log-Event (
                    'DEEP MARKER: M19={0} RatRequested={1} StartDataCall={2}' -f
                    $s.Mode19,$s.RatRequested,$s.StartDataCall
                )

                try { [console]::Beep(1400,220) } catch {}
            }

            if ($s.Class -eq 'HEALTHY' -and $lastClass -ne 'HEALTHY') {
                Log-Event '*** WFC HEALTHY DETECTED ***'
                try {
                    [console]::Beep(1200,250)
                    Start-Sleep -Milliseconds 100
                    [console]::Beep(1500,250)
                } catch {}
            }

            $lastHeartbeat = Get-Date
        }

        $lastSignature = $signature
        $lastMode19 = $s.Mode19
        $lastRatRequested = $s.RatRequested
        $lastStartDataCall = $s.StartDataCall
        $lastClass = $s.Class

        Start-Sleep -Seconds $SampleEverySec
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    # Normal Ctrl+C path.
}
catch {
    Write-Host ''
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkYellow
    }

    Log-Event ('ERROR: ' + $_.Exception.ToString())
}
finally {
    if ($null -ne $logcatProc) {
        try {
            if (-not $logcatProc.HasExited) {
                Stop-Process -Id $logcatProc.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }

    Log-Event 'PASSIVE MONITOR STOP'
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' Monitor stopped.'
    Write-Host (' Session folder: {0}' -f $SessionDir)
    Write-Host ' Send the whole session folder ZIP for analysis.'
    Write-Host '============================================================'
    Write-Host ''
}
