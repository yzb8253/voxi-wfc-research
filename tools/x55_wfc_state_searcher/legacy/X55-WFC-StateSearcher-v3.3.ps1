# X55-WFC-StateSearcher-v3.3.ps1
# Fixed launcher/root-command handling based on the user's validated v2.5 script.
# Tested design target: Windows PowerShell 5.1 + Xiaomi 10 (cas) + Android 13.
#
# AUTO:
#   - airplane mode OFF/ON
#   - Wi-Fi enable after airplane mode ON
#   - state sampling
#   - candidate classification
#   - calls the existing X55-WFC-OneClick.ps1 (v2.5) for candidate states
#
# READ-ONLY / NOT CHANGED:
#   - Android system location
#   - Anywhere
#   - VPN / FlClash
#
# Important: on this phone airplane mode ON disconnects Wi-Fi, so this script
# explicitly re-enables Wi-Fi after every airplane-mode ON transition.

$ErrorActionPreference = 'Stop'

# ---------------- CONFIG ----------------
$Serial = 'fd0ff892'
$Adb = 'C:\Users\ZJH\Desktop\platform-tools\adb.exe'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'

# EXACT safety gate copied from the user's validated v2.5 script.
$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'
$ExpectedFingerprint = 'Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'

$Desktop = Join-Path $env:USERPROFILE 'Desktop'
$RootDir = Join-Path $Desktop 'WFC-StateSearch-v3'
$HistoryCsv = Join-Path $RootDir 'fingerprint-history.csv'
$MainLog = Join-Path $RootDir 'v3-main.log'
$CrashLog = Join-Path $RootDir 'v3-crash.log'

# Prefer a v2.5 file placed beside this v3.1 script. Fall back to Desktop.
$V25Candidates = @(
    (Join-Path $PSScriptRoot 'X55-WFC-OneClick.ps1'),
    (Join-Path $Desktop 'X55-WFC-OneClick.ps1')
)

$MaxRounds = 12
$CellularWaitSec = 90
$WifiWaitSec = 45
$VpnReturnWaitSec = 20
$RecoveryWatchSec = 115
$InterRoundPauseSec = 5

# Alternate Wi-Fi baseline between rounds to search two formation paths.
# Odd rounds: Wi-Fi ON during cellular baseline.
# Even rounds: Wi-Fi OFF during cellular baseline, then ON after airplane mode.
$AlternateBaselineWifi = $true

# ---------------- LOGGING ----------------
New-Item -ItemType Directory -Force -Path $RootDir | Out-Null

function Stamp {
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
}

function Log {
    param([string]$Text)
    $line = '[{0}] {1}' -f (Stamp), $Text
    Write-Host $line
    try {
        Add-Content -LiteralPath $MainLog -Value $line -Encoding UTF8
    } catch {}
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
    } catch {
        Log ('WARN: write failed: {0} :: {1}' -f $Path, $_.Exception.Message)
    }
}

# ---------------- ROBUST PROCESS / ADB HELPERS ----------------
# These quoting rules intentionally follow the user's validated v2.5 script.

function ConvertTo-WindowsCommandLineArg {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

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
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [switch]$Quiet
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
        if (-not $proc.Start()) {
            throw 'Failed to start adb.exe'
        }

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()

        $proc.WaitForExit()

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $code = $proc.ExitCode

        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $parts += $stdout.TrimEnd("`r","`n")
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            $parts += $stderr.TrimEnd("`r","`n")
        }

        $text = ($parts -join [Environment]::NewLine)

        if (-not $Quiet -and $text) {
            Write-Host $text
        }

        [pscustomobject]@{
            Code = $code
            Text = $text.Trim()
        }
    }
    finally {
        if ($null -ne $proc) {
            $proc.Dispose()
        }
    }
}

function Invoke-Adb {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $r = Invoke-AdbResult -Arguments (@('-s', $Serial) + $Arguments) -Quiet
    if ($r.Code -ne 0) {
        throw ('ADB failed ({0}): adb {1}`r`n{2}' -f $r.Code, ($Arguments -join ' '), $r.Text)
    }
    return $r.Text
}

function Invoke-Root {
    param([Parameter(Mandatory=$true)][string]$Command)

    # CRITICAL: exactly like validated v2.5, "su -c '...'" is ONE adb shell argument.
    $r = Invoke-AdbResult -Arguments @('-s', $Serial, 'shell', "su -c '$Command'") -Quiet
    if ($r.Code -ne 0) {
        throw ('ROOT ADB failed ({0}): {1}`r`n{2}' -f $r.Code, $Command, $r.Text)
    }
    return $r.Text
}

# ---------------- STATE READERS ----------------

function Get-WfcStatus {
    # IMPORTANT:
    # wfcctl.sh intentionally returns non-zero classification codes for unhealthy
    # states (for example F1 can return 30) while still printing a perfectly valid
    # status report. v2.5 also parses the TEXT and does not treat that exit code as
    # an ADB transport/root failure.
    #
    # Therefore do NOT call strict Invoke-Root here. Accept the report whenever
    # the expected VOXI status header/body is present, regardless of wfcctl exit code.
    $r = Invoke-AdbResult -Arguments @(
        '-s', $Serial,
        'shell',
        "su -c '$WfcCtl status'"
    ) -Quiet

    if ($r.Text -match 'VOXI WFC Recovery' -and
        $r.Text -match 'VOXI:\s+slot=1' -and
        $r.Text -match 'CORE HEALTH:') {
        return $r.Text
    }

    throw ('wfcctl status did not return a valid report. ExitCode={0}`r`n{1}' -f $r.Code,$r.Text)
}

function Test-WfcHealthy {
    param([AllowEmptyString()][string]$StatusText)

    if ($StatusText -match '(?m)^IMS:\s+REGISTERED' -and
        $StatusText -match '(?m)^Transport:\s+WLAN' -and
        $StatusText -match '(?m)^WFC:\s+AVAILABLE') {
        return $true
    }
    return $false
}

function Get-Slot1ServiceState {
    $t = Invoke-Adb @('shell','dumpsys','telephony.registry')
    $lines = @(
        $t -split "`r?`n" |
        Where-Object { $_ -match '^\s+mServiceState=' }
    )

    if ($lines.Count -ge 2) {
        return $lines[1].Trim()
    }
    if ($lines.Count -eq 1) {
        return $lines[0].Trim()
    }
    return ''
}

function Get-LocationMode {
    try {
        $x = Invoke-Adb @('shell','settings','get','secure','location_mode')
        if ([string]::IsNullOrWhiteSpace($x)) { return 'UNKNOWN' }
        return $x.Trim()
    } catch {
        return 'UNKNOWN'
    }
}

function Get-AnywhereState {
    # pidof normally returns exit code 1 when a process is simply not running.
    # That is a valid NOT_RUNNING result, not an ADB failure.
    try {
        $r = Invoke-AdbResult -Arguments @(
            '-s', $Serial,
            'shell',
            'pidof',
            'com.cxorz.anywhere'
        ) -Quiet

        if (-not [string]::IsNullOrWhiteSpace($r.Text)) {
            return 'RUNNING'
        }

        if ($r.Code -eq 0 -or $r.Code -eq 1) {
            return 'NOT_RUNNING'
        }

        return 'UNKNOWN'
    } catch {
        return 'UNKNOWN'
    }
}

function Get-VpnState {
    try {
        $t = Invoke-Adb @('shell','dumpsys','connectivity')
        if ($t -match 'com\.follow\.clash' -and $t -match 'VPN') {
            return 'CONNECTED_FLCLASH'
        }
        if ($t -match 'Transports:\s*[^\r\n]*VPN' -or $t -match 'VPN CONNECTED') {
            return 'CONNECTED'
        }
        return 'NOT_CONNECTED'
    } catch {
        return 'UNKNOWN'
    }
}

function Test-WifiConnected {
    try {
        $t = Invoke-Adb @('shell','cmd','wifi','status')
        return ($t -match 'Wifi is connected to')
    } catch {
        return $false
    }
}

function Wait-WifiConnected {
    param([int]$TimeoutSec)

    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        if (Test-WifiConnected) {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Test-CellularReady {
    try {
        $op = Invoke-Adb @('shell','getprop','gsm.operator.numeric')
        $rat = Invoke-Adb @('shell','getprop','gsm.network.type')
        $s = Get-Slot1ServiceState

        $okOp = ($op -match '46000')
        $okRat = ($rat -match 'LTE')
        $okVoice = ($s -match 'mVoiceRegState=0\(IN_SERVICE\)')
        $okData = ($s -match 'mDataRegState=0\(IN_SERVICE\)')
        $okWwanLte = ($s -match 'getRilDataRadioTechnology=14\(LTE\)')

        return ($okOp -and $okRat -and $okVoice -and $okData -and $okWwanLte)
    } catch {
        return $false
    }
}

function Wait-CellularReady {
    param([int]$TimeoutSec)

    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        if (Test-CellularReady) {
            return $true
        }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Get-KeyLogText {
    $raw = Invoke-Adb @('logcat','-d','-b','all','-v','threadtime')
    $keep = @()

    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match 'networkMode=19|RatRequested|StartDataCall|qualifiedNetworks|registrationState=HOME|NOT_REG_OR_SEARCHING|IWlanProxy') {
            $keep += $line
        }
    }

    return ($keep -join "`r`n")
}

# ---------------- FINGERPRINT ----------------

function Parse-Fingerprint {
    param(
        [AllowEmptyString()][string]$Status,
        [AllowEmptyString()][string]$Slot1,
        [AllowEmptyString()][string]$KeyLog
    )

    $home = if ($Slot1 -match 'transportType=WLAN registrationState=HOME') { '1' } else { '0' }
    $dataSvc = if ($Slot1 -match 'transportType=WLAN registrationState=HOME[^\}]*availableServices=\[DATA\]') { '1' } else { '0' }
    $preferred = if ($Slot1 -match 'mIsIwlanPreferred=true') { '1' } else { '0' }
    $dataIwlan = if ($Slot1 -match 'getRilDataRadioTechnology=18\(IWLAN\)') { '1' } else { '0' }

    $voiceState = 'NA'
    $dataState = 'NA'
    $dataRat = 'NA'

    $m = [regex]::Match($Slot1, 'mVoiceRegState=(\d+)\(([^)]+)\)')
    if ($m.Success) { $voiceState = $m.Groups[2].Value }

    $m = [regex]::Match($Slot1, 'mDataRegState=(\d+)\(([^)]+)\)')
    if ($m.Success) { $dataState = $m.Groups[2].Value }

    $m = [regex]::Match($Slot1, 'getRilDataRadioTechnology=(\d+)\(([^)]+)\)')
    if ($m.Success) { $dataRat = $m.Groups[2].Value }

    $cneReg = 'UNKNOWN'
    $cneActive = 'UNKNOWN'
    $req = 'null'

    $m = [regex]::Match(
        $Status,
        'qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)\s+request=([^\s]+)'
    )
    if ($m.Success) {
        $cneReg = $m.Groups[1].Value
        $cneActive = $m.Groups[2].Value
        $req = $m.Groups[3].Value
    }

    $reqState = if ($req -ne 'null' -and $req -ne '') { 'PRESENT' } else { 'NULL' }

    $epdg = if ($Status -match 'ePDG UDP/4500:\s+PRESENT') { '1' } else { '0' }
    $xfrm = if ($Status -match 'XFRM:\s+PRESENT') { '1' } else { '0' }
    $mmtel = if ($Status -match 'MMTEL:\s+READY') { '1' } else { '0' }
    $ims = if ($Status -match '(?m)^IMS:\s+REGISTERED') { '1' } else { '0' }
    $wfc = if ($Status -match '(?m)^WFC:\s+AVAILABLE') { '1' } else { '0' }

    $mode19 = 'NONE'
    $modeLines = @(
        $KeyLog -split "`r?`n" |
        Where-Object { $_ -match 'networkMode=19' }
    )

    if ($modeLines.Count -gt 0) {
        $lastMode = $modeLines[$modeLines.Count - 1]
        if ($lastMode -match 'status=2' -and $lastMode -match 'registered=1') {
            $mode19 = 'GOOD_2_1'
        }
        elseif ($lastMode -match 'status=0' -and $lastMode -match 'registered=2') {
            $mode19 = 'BAD_0_2'
        }
        else {
            $mode19 = 'OTHER'
        }
    }

    $ratRequested = if ($KeyLog -match 'RatRequested') { '1' } else { '0' }
    $startDataCall = if ($KeyLog -match 'StartDataCall') { '1' } else { '0' }
    $qualified = if ($KeyLog -match 'qualifiedNetworks') { '1' } else { '0' }

    $class = 'UNKNOWN'

    if ($wfc -eq '1' -and $ims -eq '1') {
        $class = 'HEALTHY'
    }
    elseif ($home -eq '1' -and $reqState -eq 'PRESENT' -and $epdg -eq '0' -and $xfrm -eq '0' -and $ims -eq '0') {
        $class = 'P2'
    }
    elseif ($home -eq '1' -and $dataIwlan -eq '1' -and $preferred -eq '1' -and $reqState -eq 'NULL') {
        $class = 'P1'
    }
    elseif ($home -eq '0' -and $reqState -eq 'NULL' -and $ims -eq '0') {
        $class = 'P0'
    }

    $fp = @(
        ('CLASS=' + $class),
        ('HOME=' + $home),
        ('DATASVC=' + $dataSvc),
        ('PREF=' + $preferred),
        ('DIWLAN=' + $dataIwlan),
        ('VOICE=' + $voiceState),
        ('DATA=' + $dataState),
        ('RAT=' + $dataRat),
        ('CNE=' + $cneReg),
        ('ACTIVE=' + $cneActive),
        ('REQ=' + $reqState),
        ('M19=' + $mode19),
        ('RATREQ=' + $ratRequested),
        ('STARTDC=' + $startDataCall),
        ('QUAL=' + $qualified),
        ('EPDG=' + $epdg),
        ('XFRM=' + $xfrm),
        ('MMTEL=' + $mmtel)
    ) -join ';'

    [pscustomobject]@{
        Class = $class
        Fingerprint = $fp
        Home = $home
        DataService = $dataSvc
        Preferred = $preferred
        DataIwlan = $dataIwlan
        VoiceState = $voiceState
        DataState = $dataState
        DataRat = $dataRat
        CneRegistered = $cneReg
        CneActive = $cneActive
        RequestState = $reqState
        Mode19 = $mode19
        RatRequested = $ratRequested
        StartDataCall = $startDataCall
        QualifiedNetworks = $qualified
        Epdg = $epdg
        Xfrm = $xfrm
        Mmtel = $mmtel
        Ims = $ims
        Wfc = $wfc
    }
}

function Get-HistoryDecision {
    param(
        [string]$Fingerprint,
        [string]$Class
    )

    if ($Class -eq 'P0') {
        return [pscustomobject]@{
            Action = 'SKIP'
            Reason = 'P0: known low-value state'
        }
    }

    if ($Class -eq 'HEALTHY') {
        return [pscustomobject]@{
            Action = 'DONE'
            Reason = 'WFC already healthy'
        }
    }

    if (Test-Path $HistoryCsv) {
        try {
            $rows = @(
                Import-Csv -LiteralPath $HistoryCsv |
                Where-Object { $_.Fingerprint -eq $Fingerprint }
            )

            $succ = @($rows | Where-Object { $_.RecoveryResult -eq 'SUCCESS' }).Count
            $fail = @($rows | Where-Object { $_.RecoveryResult -eq 'FAIL' }).Count

            if ($succ -gt 0) {
                return [pscustomobject]@{
                    Action = 'RECOVER'
                    Reason = 'This exact fingerprint has a prior SUCCESS'
                }
            }

            if ($fail -gt 0) {
                return [pscustomobject]@{
                    Action = 'SKIP'
                    Reason = 'This exact fingerprint already failed'
                }
            }
        }
        catch {
            Log ('WARN: history read failed: ' + $_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        Action = 'RECOVER'
        Reason = 'New candidate fingerprint: perform one learning attempt'
    }
}

function Append-History {
    param(
        [int]$Round,
        [object]$Fp,
        [string]$RecoveryResult,
        [string]$Scenario,
        [string]$LocationMode,
        [string]$VpnState,
        [string]$AnywhereState
    )

    $obj = [pscustomobject]@{
        Time = Stamp
        Round = $Round
        Scenario = $Scenario
        Class = $Fp.Class
        RecoveryResult = $RecoveryResult
        LocationMode = $LocationMode
        VpnState = $VpnState
        AnywhereState = $AnywhereState
        Mode19 = $Fp.Mode19
        Home = $Fp.Home
        DataService = $Fp.DataService
        Preferred = $Fp.Preferred
        DataIwlan = $Fp.DataIwlan
        VoiceState = $Fp.VoiceState
        DataState = $Fp.DataState
        DataRat = $Fp.DataRat
        CneRegistered = $Fp.CneRegistered
        CneActive = $Fp.CneActive
        RequestState = $Fp.RequestState
        RatRequested = $Fp.RatRequested
        StartDataCall = $Fp.StartDataCall
        QualifiedNetworks = $Fp.QualifiedNetworks
        Epdg = $Fp.Epdg
        Xfrm = $Fp.Xfrm
        Mmtel = $Fp.Mmtel
        Fingerprint = $Fp.Fingerprint
    }

    if (Test-Path $HistoryCsv) {
        $obj | Export-Csv -LiteralPath $HistoryCsv -NoTypeInformation -Append -Encoding UTF8
    }
    else {
        $obj | Export-Csv -LiteralPath $HistoryCsv -NoTypeInformation -Encoding UTF8
    }
}

# ---------------- V2.5 WRAPPER ----------------

function Resolve-V25Path {
    foreach ($candidate in $V25Candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }
    return $null
}

function Run-V25-And-Watch {
    param(
        [int]$Round,
        [string]$RoundDir,
        [string]$V25Path
    )

    Log ('Round {0}: launching v2.5: {1}' -f $Round, $V25Path)

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy','Bypass',
        '-File', ('"{0}"' -f $V25Path)
    )

    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -PassThru

    $start = Get-Date
    $success = $false

    while (((Get-Date) - $start).TotalSeconds -lt $RecoveryWatchSec) {
        Start-Sleep -Seconds 5

        try {
            $status = Get-WfcStatus
            Save-Text (Join-Path $RoundDir 'recovery-watch-latest-status.txt') $status

            if (Test-WfcHealthy $status) {
                $success = $true
                break
            }
        }
        catch {
            Log ('Round {0}: status watch warning: {1}' -f $Round, $_.Exception.Message)
        }

        if ($p.HasExited) {
            # v2.5 may exit with 0 success, 20 expected failure, or 1 error.
            if (-not $success) {
                try {
                    $status2 = Get-WfcStatus
                    Save-Text (Join-Path $RoundDir 'recovery-after-child-exit-status.txt') $status2
                    if (Test-WfcHealthy $status2) {
                        $success = $true
                    }
                } catch {}
            }
            break
        }
    }

    # The user's v2.5 intentionally pauses with Read-Host at the end.
    # Close only the v2.5 PowerShell console after v3 has captured the result.
    try {
        if ($null -ne $p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    return $success
}

# ---------------- MAIN ----------------

function Main {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' X55 + VOXI WFC STATE SEARCHER v3.3'
    Write-Host '============================================================'
    Write-Host 'AUTO       : airplane mode + Wi-Fi'
    Write-Host 'READ ONLY  : location + Anywhere + VPN'
    Write-Host 'IMPORTANT  : airplane ON -> wait 2 sec -> Wi-Fi ON'
    Write-Host 'RECOVERY   : existing validated v2.5 script'
    Write-Host '============================================================'
    Write-Host ''

    if (-not (Test-Path $Adb)) {
        throw ('ADB not found: ' + $Adb)
    }

    $v25 = Resolve-V25Path
    if ([string]::IsNullOrWhiteSpace($v25)) {
        throw ('v2.5 not found. Put X55-WFC-OneClick.ps1 beside v3.1 or on Desktop.')
    }

    $state = Invoke-Adb @('get-state')
    if ($state -notmatch 'device') {
        throw ('Device ' + $Serial + ' is not connected/authorized.')
    }

    $root = Invoke-Root 'id'
    if ($root -notmatch 'uid=0') {
        throw 'Magisk root is not available.'
    }

    # IMPORTANT: use the SAME Android properties as the validated v2.5 script.
    # ro.build.display.id on this ROM is "TKQ1.221114.001 test-keys" and is NOT
    # the ROM incremental version, so it must not be used as the safety build ID.
    $device = (Invoke-Adb @('shell','getprop','ro.product.device')).Trim()
    $android = (Invoke-Adb @('shell','getprop','ro.build.version.release')).Trim()
    $build = (Invoke-Adb @('shell','getprop','ro.build.version.incremental')).Trim()
    $fingerprint = (Invoke-Adb @('shell','getprop','ro.build.fingerprint')).Trim()

    Write-Host ('DEVICE=' + $device)
    Write-Host ('ANDROID=' + $android)
    Write-Host ('BUILD=' + $build)
    Write-Host ('FINGERPRINT=' + $fingerprint)

    if ($device -ne $ExpectedDevice) {
        throw ('Safety gate failed: device. Expected {0}, got {1}' -f $ExpectedDevice,$device)
    }
    if ($android -ne $ExpectedAndroid) {
        throw ('Safety gate failed: Android. Expected {0}, got {1}' -f $ExpectedAndroid,$android)
    }
    if ($build -ne $ExpectedBuild) {
        throw ('Safety gate failed: ROM build. Expected {0}, got {1}' -f $ExpectedBuild,$build)
    }
    if ($fingerprint -ne $ExpectedFingerprint) {
        throw ('Safety gate failed: fingerprint. Expected {0}, got {1}' -f $ExpectedFingerprint,$fingerprint)
    }

    $initialLocation = Get-LocationMode
    $initialVpn = Get-VpnState
    $initialAnywhere = Get-AnywhereState

    Log ('Startup: location_mode={0} vpn={1} anywhere={2}' -f $initialLocation,$initialVpn,$initialAnywhere)
    Log ('v2.5 path: ' + $v25)
    Log 'v3.3 will NOT toggle location, Anywhere, or VPN.'

    $initialStatus = Get-WfcStatus
    if (Test-WfcHealthy $initialStatus) {
        Log 'WFC already healthy. Stop.'
        Write-Host $initialStatus
        return 0
    }

    for ($round = 1; $round -le $MaxRounds; $round++) {
        $roundDir = Join-Path $RootDir (
            'Round-{0:D2}-{1}' -f $round, (Get-Date).ToString('yyyyMMdd-HHmmss')
        )
        New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

        $scenario = 'BASE_WIFI_ON'
        if ($AlternateBaselineWifi -and ($round % 2 -eq 0)) {
            $scenario = 'BASE_WIFI_OFF'
        }

        Log '------------------------------------------------------------'
        Log ('Round {0}/{1} START scenario={2}' -f $round,$MaxRounds,$scenario)

        $locBefore = Get-LocationMode
        $vpnBefore = Get-VpnState
        $anyBefore = Get-AnywhereState

        Log ('External before cycle: location_mode={0} vpn={1} anywhere={2}' -f $locBefore,$vpnBefore,$anyBefore)

        Log ('Round {0}: airplane OFF' -f $round)
        [void](Invoke-Root 'cmd connectivity airplane-mode disable')
        Start-Sleep -Seconds 2

        if ($scenario -eq 'BASE_WIFI_ON') {
            Log ('Round {0}: Wi-Fi ON during cellular baseline' -f $round)
            [void](Invoke-Root 'svc wifi enable')
            [void](Wait-WifiConnected 20)
        }
        else {
            Log ('Round {0}: Wi-Fi OFF during cellular baseline' -f $round)
            [void](Invoke-Root 'svc wifi disable')
        }

        Log ('Round {0}: waiting for VOXI 46000/LTE/IN_SERVICE' -f $round)

        if (-not (Wait-CellularReady $CellularWaitSec)) {
            Log ('Round {0}: cellular baseline TIMEOUT' -f $round)

            Save-Text (
                (Join-Path $roundDir 'cellular-timeout-registry.txt')
            ) (
                Invoke-Adb @('shell','dumpsys','telephony.registry')
            )

            Start-Sleep -Seconds $InterRoundPauseSec
            continue
        }

        Log ('Round {0}: cellular baseline confirmed' -f $round)
        Save-Text (Join-Path $roundDir 'cellular-baseline-slot1.txt') (Get-Slot1ServiceState)

        # Clear logs immediately before the transition being classified.
        [void](Invoke-Adb @('logcat','-b','all','-c'))

        Log ('Round {0}: airplane ON' -f $round)
        [void](Invoke-Root 'cmd connectivity airplane-mode enable')

        # User-confirmed ROM behavior: airplane mode disconnects Wi-Fi.
        Start-Sleep -Seconds 2

        Log ('Round {0}: Wi-Fi ON after airplane ON' -f $round)
        [void](Invoke-Root 'svc wifi enable')

        if (-not (Wait-WifiConnected $WifiWaitSec)) {
            Log ('Round {0}: Wi-Fi reconnect TIMEOUT' -f $round)
            Save-Text (
                (Join-Path $roundDir 'wifi-status.txt')
            ) (
                Invoke-Adb @('shell','cmd','wifi','status')
            )

            Start-Sleep -Seconds $InterRoundPauseSec
            continue
        }

        Log ('Round {0}: Wi-Fi connected' -f $round)

        # VPN is intentionally read-only. If it was connected, wait for auto-return only.
        if ($vpnBefore -match '^CONNECTED') {
            $vpnStart = Get-Date
            $vpnReturned = $false

            while (((Get-Date) - $vpnStart).TotalSeconds -lt $VpnReturnWaitSec) {
                $v = Get-VpnState

                if ($v -match '^CONNECTED') {
                    $vpnReturned = $true
                    break
                }

                Start-Sleep -Seconds 2
            }

            if ($vpnReturned) {
                Log ('Round {0}: VPN auto-returned' -f $round)
            }
            else {
                Log ('Round {0}: VPN did NOT auto-return; v3.3 did not force it' -f $round)
            }
        }

        # Passive observations: no more state changes here.
        $sampleTimes = @(5,10,15,20,30)
        $lastMark = 0
        $naturalSuccess = $false

        foreach ($mark in $sampleTimes) {
            $sleepFor = $mark - $lastMark

            if ($sleepFor -gt 0) {
                Start-Sleep -Seconds $sleepFor
            }

            $lastMark = $mark

            $s = Get-WfcStatus
            $slot = Get-Slot1ServiceState

            Save-Text (Join-Path $roundDir ('status-T{0}.txt' -f $mark)) $s
            Save-Text (Join-Path $roundDir ('slot1-T{0}.txt' -f $mark)) $slot

            if (Test-WfcHealthy $s) {
                $naturalSuccess = $true

                $keysNatural = Get-KeyLogText
                $fpNatural = Parse-Fingerprint $s $slot $keysNatural

                Save-Text (Join-Path $roundDir 'keylog-natural-success.txt') $keysNatural

                Append-History `
                    -Round $round `
                    -Fp $fpNatural `
                    -RecoveryResult 'NATURAL_SUCCESS' `
                    -Scenario $scenario `
                    -LocationMode (Get-LocationMode) `
                    -VpnState (Get-VpnState) `
                    -AnywhereState (Get-AnywhereState)

                Log ('Round {0}: WFC natural SUCCESS at T+{1}s' -f $round,$mark)

                Write-Host ''
                Write-Host '============================================================'
                Write-Host ' WFC SUCCESS - no v2.5 required'
                Write-Host '============================================================'
                Write-Host ('Round: {0}' -f $round)
                Write-Host ('Logs : {0}' -f $roundDir)

                return 0
            }
        }

        if ($naturalSuccess) {
            return 0
        }

        $preStatus = Get-WfcStatus
        $preSlot = Get-Slot1ServiceState
        $keyLog = Get-KeyLogText

        Save-Text (Join-Path $roundDir 'PRE-V25-status.txt') $preStatus
        Save-Text (Join-Path $roundDir 'PRE-V25-slot1.txt') $preSlot
        Save-Text (Join-Path $roundDir 'PRE-V25-keylog.txt') $keyLog

        # Full log is useful for later manual comparison.
        try {
            Save-Text (
                (Join-Path $roundDir 'PRE-V25-full-logcat.txt')
            ) (
                Invoke-Adb @('logcat','-d','-b','all','-v','threadtime')
            )
        }
        catch {
            Log ('Round {0}: full logcat save warning: {1}' -f $round,$_.Exception.Message)
        }

        $fp = Parse-Fingerprint $preStatus $preSlot $keyLog

        $locNow = Get-LocationMode
        $vpnNow = Get-VpnState
        $anyNow = Get-AnywhereState

        Log ('Round {0}: class={1}' -f $round,$fp.Class)
        Log ('Round {0}: fingerprint={1}' -f $round,$fp.Fingerprint)
        Log ('Round {0}: external location_mode={1} vpn={2} anywhere={3}' -f $round,$locNow,$vpnNow,$anyNow)

        if ($fp.Class -eq 'HEALTHY') {
            Append-History `
                -Round $round `
                -Fp $fp `
                -RecoveryResult 'NATURAL_SUCCESS' `
                -Scenario $scenario `
                -LocationMode $locNow `
                -VpnState $vpnNow `
                -AnywhereState $anyNow

            return 0
        }

        $decision = Get-HistoryDecision -Fingerprint $fp.Fingerprint -Class $fp.Class

        Log ('Round {0}: decision={1} reason={2}' -f $round,$decision.Action,$decision.Reason)

        if ($decision.Action -eq 'SKIP') {
            Append-History `
                -Round $round `
                -Fp $fp `
                -RecoveryResult 'SKIPPED' `
                -Scenario $scenario `
                -LocationMode $locNow `
                -VpnState $vpnNow `
                -AnywhereState $anyNow

            Start-Sleep -Seconds $InterRoundPauseSec
            continue
        }

        if ($decision.Action -eq 'RECOVER') {
            Append-History `
                -Round $round `
                -Fp $fp `
                -RecoveryResult 'ATTEMPTING' `
                -Scenario $scenario `
                -LocationMode $locNow `
                -VpnState $vpnNow `
                -AnywhereState $anyNow

            $ok = Run-V25-And-Watch -Round $round -RoundDir $roundDir -V25Path $v25

            $postStatus = ''
            try {
                $postStatus = Get-WfcStatus
                Save-Text (Join-Path $roundDir 'POST-V25-status.txt') $postStatus
            }
            catch {
                Log ('Round {0}: post-v2.5 status read failed: {1}' -f $round,$_.Exception.Message)
            }

            if ($ok -or (Test-WfcHealthy $postStatus)) {
                Log ('Round {0}: v2.5 RECOVERY SUCCESS' -f $round)

                Append-History `
                    -Round $round `
                    -Fp $fp `
                    -RecoveryResult 'SUCCESS' `
                    -Scenario $scenario `
                    -LocationMode $locNow `
                    -VpnState $vpnNow `
                    -AnywhereState $anyNow

                Write-Host ''
                Write-Host '============================================================'
                Write-Host ' V3.3 FOUND A RECOVERABLE POLLUTED STATE'
                Write-Host '============================================================'
                Write-Host ('Round       : {0}' -f $round)
                Write-Host ('Scenario    : {0}' -f $scenario)
                Write-Host ('Class       : {0}' -f $fp.Class)
                Write-Host ('Mode19      : {0}' -f $fp.Mode19)
                Write-Host ('Fingerprint : {0}' -f $fp.Fingerprint)
                Write-Host ('Logs        : {0}' -f $roundDir)
                Write-Host ''
                Write-Host $postStatus

                return 0
            }
            else {
                Log ('Round {0}: v2.5 recovery FAIL' -f $round)

                Append-History `
                    -Round $round `
                    -Fp $fp `
                    -RecoveryResult 'FAIL' `
                    -Scenario $scenario `
                    -LocationMode $locNow `
                    -VpnState $vpnNow `
                    -AnywhereState $anyNow
            }
        }

        Start-Sleep -Seconds $InterRoundPauseSec
    }

    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' SEARCH FINISHED - NO RECOVERABLE STATE FOUND'
    Write-Host '============================================================'
    Write-Host ('Rounds : {0}' -f $MaxRounds)
    Write-Host ('History: {0}' -f $HistoryCsv)
    Write-Host ('Log    : {0}' -f $MainLog)

    return 20
}

# ---------------- TOP-LEVEL CRASH GUARD ----------------

$exitCode = 1

try {
    $exitCode = Main
}
catch {
    $msg = $_.Exception.ToString()
    $pos = ''

    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        $pos = $_.InvocationInfo.PositionMessage
    }

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host ' V3.3 ERROR - WINDOW WILL NOT AUTO-CLOSE' -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow

    if ($pos) {
        Write-Host $pos -ForegroundColor DarkYellow
    }

    try {
        Add-Content -LiteralPath $CrashLog -Value (
            '[{0}] {1}{2}{3}' -f (Stamp), $msg, [Environment]::NewLine, $pos
        ) -Encoding UTF8
    } catch {}

    $exitCode = 1
}

exit $exitCode
