# X55-VOXI-PassiveMonitor-v1.2.ps1
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
$DeepLookbackLines = 10000

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
$LatestDeep = Join-Path $SessionDir 'latest-deep.txt'
$DeepEventsLog = Join-Path $SessionDir 'deep-events.log'

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
    # During a PHYSICAL SIM removal the same valid report can legitimately show:
    #   slot=-1 / Subscription: INACTIVE / UICC Apps: UNKNOWN / Failure class: F8
    # That is an observation, not a monitor error. Accept any structurally valid report.
    $r = Invoke-AdbResult -Arguments @(
        '-s',$Serial,'shell',"su -c '$WfcCtl status'"
    )

    if ($r.Text -match 'VOXI WFC Recovery' -and
        $r.Text -match '(?m)^VOXI:' -and
        $r.Text -match '(?m)^CORE HEALTH:') {
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

function Get-LogcatLineTime {
    param([string]$Line)

    $m = [regex]::Match(
        $Line,
        '^(?<md>\d{2}-\d{2})\s+(?<tm>\d{2}:\d{2}:\d{2}\.\d{3})'
    )

    if (-not $m.Success) { return $null }

    try {
        $year = (Get-Date).Year
        return [datetime]::ParseExact(
            ('{0}-{1} {2}' -f $year,$m.Groups['md'].Value,$m.Groups['tm'].Value),
            'yyyy-MM-dd HH:mm:ss.fff',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        return $null
    }
}

function Get-DeepLogState {
    param([datetime]$EpochStart)

    $result = [ordered]@{
        Mode19 = 'NONE'
        Mode19Status = ''
        Mode19Registered = ''
        Mode19RestrictCause = ''
        Mode19Raw = ''
        RatRequested = '0'
        RatRequestedRaw = ''
        StartDataCall = '0'
        StartDataCallRaw = ''
        QualifiedNetworks = '0'
        QualifiedNetworksRaw = ''
        QualifiedHome = '0'
        IWlanProxy = '0'
        IWlanProxyRaw = ''
        LastMarkerTime = ''
    }

    if (-not (Test-Path $LogcatFile)) {
        return [pscustomobject]$result
    }

    try {
        $tail = Get-Content -LiteralPath $LogcatFile -Tail $DeepLookbackLines -ErrorAction Stop

        foreach ($line in $tail) {
            $lineTime = Get-LogcatLineTime -Line $line
            if ($null -eq $lineTime) { continue }
            if ($lineTime -lt $EpochStart.AddSeconds(-1)) { continue }

            $matched = $false

            if ($line -match 'networkMode\s*=\s*19') {
                $statusVal = ''
                $registeredVal = ''
                $restrictVal = ''

                $m = [regex]::Match($line,'status\s*=\s*(-?\d+)')
                if ($m.Success) { $statusVal = $m.Groups[1].Value }

                $m = [regex]::Match($line,'registered\s*=\s*(-?\d+)')
                if ($m.Success) { $registeredVal = $m.Groups[1].Value }

                $m = [regex]::Match($line,'restrictCause\s*=\s*(-?\d+)')
                if ($m.Success) { $restrictVal = $m.Groups[1].Value }

                $result.Mode19Status = $statusVal
                $result.Mode19Registered = $registeredVal
                $result.Mode19RestrictCause = $restrictVal
                $result.Mode19Raw = $line

                if ($statusVal -eq '2' -and $registeredVal -eq '1') {
                    $result.Mode19 = '2_1'
                }
                elseif ($statusVal -eq '0' -and $registeredVal -eq '2') {
                    $result.Mode19 = '0_2'
                }
                else {
                    $result.Mode19 = 'OTHER'
                }

                $matched = $true
            }

            if ($line -match 'RatRequested') {
                $result.RatRequested = '1'
                $result.RatRequestedRaw = $line
                $matched = $true
            }

            if ($line -match 'StartDataCall') {
                $result.StartDataCall = '1'
                $result.StartDataCallRaw = $line
                $matched = $true
            }

            if ($line -match 'qualifiedNetworksChangeIndication|qualifiedNetworks') {
                $result.QualifiedNetworks = '1'
                $result.QualifiedNetworksRaw = $line

                if ($line -match 'HOME|IWLAN') {
                    $result.QualifiedHome = '1'
                }

                $matched = $true
            }

            if ($line -match 'IWlanProxy') {
                $result.IWlanProxy = '1'
                $result.IWlanProxyRaw = $line
                $matched = $true
            }

            if ($matched) {
                $result.LastMarkerTime = $lineTime.ToString('HH:mm:ss.fff')
            }
        }

        $dump = @(
            ('EpochStart={0}' -f $EpochStart.ToString('yyyy-MM-dd HH:mm:ss.fff'))
            ('Mode19={0} status={1} registered={2} restrictCause={3}' -f
                $result.Mode19,$result.Mode19Status,$result.Mode19Registered,$result.Mode19RestrictCause)
            ('RatRequested={0}' -f $result.RatRequested)
            ('StartDataCall={0}' -f $result.StartDataCall)
            ('QualifiedNetworks={0} QualifiedHome={1}' -f
                $result.QualifiedNetworks,$result.QualifiedHome)
            ('IWlanProxy={0}' -f $result.IWlanProxy)
            ('LastMarkerTime={0}' -f $result.LastMarkerTime)
            ''
            '[Mode19Raw]'
            $result.Mode19Raw
            ''
            '[RatRequestedRaw]'
            $result.RatRequestedRaw
            ''
            '[StartDataCallRaw]'
            $result.StartDataCallRaw
            ''
            '[QualifiedNetworksRaw]'
            $result.QualifiedNetworksRaw
            ''
            '[IWlanProxyRaw]'
            $result.IWlanProxyRaw
        ) -join "`r`n"

        Save-Text $LatestDeep $dump
        return [pscustomobject]$result
    }
    catch {
        return [pscustomobject]$result
    }
}

function Parse-State {
    param(
        [string]$Status,
        [string]$Slot1,
        [object]$Deep,
        [object]$Wifi,
        [object]$Location,
        [string]$Airplane,
        [string]$Vpn,
        [string]$Anywhere
    )

    # Physical SIM / subscription state from wfcctl.
    $simSlot = 'UNKNOWN'
    $subscription = 'UNKNOWN'
    $uiccApps = 'UNKNOWN'

    $m = [regex]::Match($Status,'(?m)^VOXI:\s+slot=([^\s]+)')
    if ($m.Success) { $simSlot = $m.Groups[1].Value.Trim() }

    $m = [regex]::Match($Status,'(?m)^Subscription:\s+([^\r\n]+)')
    if ($m.Success) { $subscription = $m.Groups[1].Value.Trim() }

    $m = [regex]::Match($Status,'(?m)^UICC Apps:\s+([^\r\n]+)')
    if ($m.Success) { $uiccApps = $m.Groups[1].Value.Trim() }

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

    $mode19 = $Deep.Mode19
    $mode19Status = $Deep.Mode19Status
    $mode19Registered = $Deep.Mode19Registered
    $mode19RestrictCause = $Deep.Mode19RestrictCause
    $ratRequested = $Deep.RatRequested
    $startDataCall = $Deep.StartDataCall
    $qualified = $Deep.QualifiedNetworks
    $qualifiedHome = $Deep.QualifiedHome
    $iwlanProxy = $Deep.IWlanProxy

    # Experimental deep fingerprint stage.
    # IMPORTANT: Mode19 2_1 is an empirical fingerprint only; it is NOT final SIP IMS registration.
    $deepStage = 'NONE'
    if ($wfc -eq '1' -and $ims -eq '1') {
        $deepStage = 'WFC'
    }
    elseif ($epdg -eq '1' -or $xfrm -eq '1') {
        $deepStage = 'TUNNEL'
    }
    elseif ($requestState -eq 'PRESENT') {
        $deepStage = 'CNE_REQUEST'
    }
    elseif ($startDataCall -eq '1') {
        $deepStage = 'DATA_CALL'
    }
    elseif ($ratRequested -eq '1') {
        $deepStage = 'RAT_REQUEST'
    }
    elseif ($mode19 -eq '2_1') {
        $deepStage = 'M19_2_1'
    }
    elseif ($mode19 -ne 'NONE') {
        $deepStage = 'M19_OTHER'
    }
    elseif ($qualified -eq '1') {
        $deepStage = 'QUALIFIED'
    }
    elseif ($iwlanHome -eq '1') {
        $deepStage = 'IWLAN_HOME'
    }

    # Deep experiment classification.
    # PRE-P1  = cellular LTE + IWLAN HOME, but no DATA service on IWLAN yet.
    # P1-F    = HOME + DATAIWLAN, but no deeper trigger in this epoch.
    # P1-CAND = P1 plus the empirical Mode19 2_1 fingerprint.
    # P1-S    = P1 plus RatRequested or StartDataCall; strongest pre-CNE candidate.
    # P2      = qti.cne request exists, but tunnel/IMS is not yet up.
    $class = 'UNKNOWN'

    if ($subscription -eq 'INACTIVE' -or $simSlot -eq '-1') {
        $class = 'SIM_ABSENT'
    }
    elseif ($ims -eq '1' -and $wfc -eq '1') {
        $class = 'HEALTHY'
    }
    elseif ($iwlanHome -eq '1' -and $requestState -eq 'PRESENT' -and
            $epdg -eq '0' -and $xfrm -eq '0' -and $ims -eq '0') {
        $class = 'P2'
    }
    elseif ($iwlanHome -eq '1' -and $dataIwlan -eq '1' -and
            $requestState -eq 'NULL' -and $ims -eq '0' -and
            ($ratRequested -eq '1' -or $startDataCall -eq '1')) {
        $class = 'P1-S'
    }
    elseif ($iwlanHome -eq '1' -and $dataIwlan -eq '1' -and
            $requestState -eq 'NULL' -and $ims -eq '0' -and
            $mode19 -eq '2_1') {
        $class = 'P1-CAND'
    }
    elseif ($iwlanHome -eq '1' -and $dataIwlan -eq '1' -and
            $requestState -eq 'NULL' -and $ims -eq '0') {
        $class = 'P1-F'
    }
    elseif ($cellLte -eq '1' -and $iwlanHome -eq '1' -and
            $dataIwlan -eq '0' -and $ims -eq '0') {
        $class = 'PRE-P1'
    }
    elseif ($iwlanHome -eq '0' -and $requestState -eq 'NULL' -and $ims -eq '0') {
        $class = 'P0'
    }

    [pscustomobject]@{
        Time = Stamp
        Class = $class
        SimSlot = $simSlot
        Subscription = $subscription
        UiccApps = $uiccApps
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
        Mode19Status = $mode19Status
        Mode19Registered = $mode19Registered
        Mode19RestrictCause = $mode19RestrictCause
        DeepStage = $deepStage
        RatRequested = $ratRequested
        StartDataCall = $startDataCall
        QualifiedNetworks = $qualified
        QualifiedHome = $qualifiedHome
        IWlanProxy = $iwlanProxy
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
        $S.SimSlot,
        $S.Subscription,
        $S.UiccApps,
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
        $S.Mode19Status,
        $S.Mode19Registered,
        $S.Mode19RestrictCause,
        $S.DeepStage,
        $S.RatRequested,
        $S.StartDataCall,
        $S.QualifiedNetworks,
        $S.QualifiedHome,
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
        '[{0}] {1,-10} STAGE={2,-11} SIM={3}/{4} AIR={5} WIFI={6}/{7} LTE={8} HOME={9} DATAIWLAN={10} PREF={11} CNE={12}/{13} REQ={14} M19={15}({16}/{17}/{18}) RAT={19} DC={20} QNET={21} ePDG={22} XFRM={23} IMS={24} WFC={25}' -f
        (Get-Date -Format 'HH:mm:ss'),
        $S.Class,
        $S.DeepStage,
        $S.SimSlot,
        $S.Subscription,
        $S.Airplane,
        $S.WifiEnabled,
        $S.WifiConnected,
        $S.CellLte,
        $S.IwlanHome,
        $S.DataIwlan,
        $S.Preferred,
        $S.CneRegistered,
        $S.CneActive,
        $S.RequestState,
        $S.Mode19,
        $S.Mode19Status,
        $S.Mode19Registered,
        $S.Mode19RestrictCause,
        $S.RatRequested,
        $S.StartDataCall,
        $S.QualifiedNetworks,
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
    elseif ($S.Class -eq 'P1-CAND' -or $S.Class -eq 'P1-S' -or $S.Class -eq 'P2') {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($S.Class -eq 'P1-F' -or $S.Class -eq 'PRE-P1') {
        Write-Host $line -ForegroundColor DarkCyan
    }
    elseif ($S.Class -eq 'SIM_ABSENT') {
        Write-Host $line -ForegroundColor DarkYellow
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
$lastQualifiedNetworks = '0'
$lastClass = ''
$lastAirplane = ''
$lastSimSlot = ''
$deepEpochStart = Get-Date

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' X55 + VOXI WFC PASSIVE MONITOR v1.2'
    Write-Host '============================================================'
    Write-Host 'READ ONLY: no airplane/Wi-Fi/VPN/location/SIM/X55 changes'
    Write-Host 'Operate the phone manually.'
    Write-Host 'Deep labels: PRE-P1 / P1-F / P1-CAND / P1-S / P2 / HEALTHY'
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
        try {
            $status = Get-WfcStatus
            $slot1 = Get-Slot1ServiceState
            $airplane = Get-AirplaneState
            $wifi = Get-WifiState
            $location = Get-LocationState
            $anywhere = Get-AnywhereProcessState
            $vpn = Get-VpnState

            # New cellular baseline = new deep-marker epoch.
            if ($lastAirplane -eq 'ON' -and $airplane -eq 'OFF') {
                $deepEpochStart = Get-Date
                Log-Event ('DEEP EPOCH RESET: airplane OFF at ' + $deepEpochStart.ToString('HH:mm:ss.fff'))
            }

            # Physical/software SIM removal is also a new epoch boundary.
            $statusShowsSimAbsent = (
                $status -match '(?m)^VOXI:\s+slot=-1' -or
                $status -match '(?m)^Subscription:\s+INACTIVE'
            )

            if ($statusShowsSimAbsent -and $lastSimSlot -ne '-1') {
                $deepEpochStart = Get-Date
                Log-Event ('DEEP EPOCH RESET: SIM absent at ' + $deepEpochStart.ToString('HH:mm:ss.fff'))
            }

            $deep = Get-DeepLogState -EpochStart $deepEpochStart
    
            Save-Text $LatestStatus $status
            Save-Text $LatestSlot1 $slot1
    
            $s = Parse-State `
                -Status $status `
                -Slot1 $slot1 `
                -Deep $deep `
                -Wifi $wifi `
                -Location $location `
                -Airplane $airplane `
                -Vpn $vpn `
                -Anywhere $anywhere
    
            Append-Timeline $s
    
            $signature = Get-StateSignature $s
            $changed = ($signature -ne $lastSignature)
    
            $newDeepMarker = (
                ($s.Mode19 -ne $lastMode19) -or
                ($s.RatRequested -eq '1' -and $lastRatRequested -eq '0') -or
                ($s.StartDataCall -eq '1' -and $lastStartDataCall -eq '0') -or
                ($s.QualifiedNetworks -eq '1' -and $lastQualifiedNetworks -eq '0')
            )

            $newInterestingClass = (
                ($s.Class -eq 'PRE-P1' -or
                 $s.Class -eq 'P1-F' -or
                 $s.Class -eq 'P1-CAND' -or
                 $s.Class -eq 'P1-S' -or
                 $s.Class -eq 'P2' -or
                 $s.Class -eq 'HEALTHY' -or
                 $s.Class -eq 'SIM_ABSENT') -and
                $s.Class -ne $lastClass
            )

            $heartbeatDue = (((Get-Date) - $lastHeartbeat).TotalSeconds -ge $HeartbeatSec)
    
            if ($changed -or $heartbeatDue -or $newDeepMarker -or $newInterestingClass) {
                Show-StateLine -S $s -Important:($newDeepMarker -or $newInterestingClass)
    
                if ($newInterestingClass) {
                    Log-Event (
                        'STATE -> {0}; STAGE={1} SIM={2}/{3} HOME={4} DATAIWLAN={5} PREF={6} CNE={7} REQ={8} M19={9}({10}/{11}/{12}) RAT={13} DC={14} QNET={15} ePDG={16} XFRM={17} IMS={18} WFC={19}' -f
                        $s.Class,$s.DeepStage,$s.SimSlot,$s.Subscription,$s.IwlanHome,
                        $s.DataIwlan,$s.Preferred,$s.CneRegistered,$s.RequestState,
                        $s.Mode19,$s.Mode19Status,$s.Mode19Registered,$s.Mode19RestrictCause,
                        $s.RatRequested,$s.StartDataCall,$s.QualifiedNetworks,
                        $s.Epdg,$s.Xfrm,$s.Ims,$s.Wfc
                    )

                    try { [console]::Beep(1000,180) } catch {}
                }
    
                if ($newDeepMarker) {
                    Log-Event (
                        'DEEP MARKER: STAGE={0} M19={1} status={2} registered={3} restrictCause={4} RatRequested={5} StartDataCall={6} QNET={7}' -f
                        $s.DeepStage,$s.Mode19,$s.Mode19Status,$s.Mode19Registered,
                        $s.Mode19RestrictCause,$s.RatRequested,$s.StartDataCall,$s.QualifiedNetworks
                    )

                    $rawDeep = @(
                        ('[{0}] STAGE={1}' -f (Stamp),$s.DeepStage)
                        ('Mode19Raw: ' + $deep.Mode19Raw)
                        ('RatRequestedRaw: ' + $deep.RatRequestedRaw)
                        ('StartDataCallRaw: ' + $deep.StartDataCallRaw)
                        ('QualifiedNetworksRaw: ' + $deep.QualifiedNetworksRaw)
                        ('IWlanProxyRaw: ' + $deep.IWlanProxyRaw)
                        ''
                    ) -join "`r`n"

                    try {
                        Add-Content -LiteralPath $DeepEventsLog -Value $rawDeep -Encoding UTF8
                    } catch {}

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
            $lastQualifiedNetworks = $s.QualifiedNetworks
            $lastClass = $s.Class
            $lastAirplane = $s.Airplane
            $lastSimSlot = $s.SimSlot
    
        }
        catch {
            # Physical SIM removal/reinsert can produce short-lived telephony states.
            # A bad single sample must never stop the passive monitor.
            Log-Event ('SAMPLE WARNING: ' + $_.Exception.Message)
        }

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
