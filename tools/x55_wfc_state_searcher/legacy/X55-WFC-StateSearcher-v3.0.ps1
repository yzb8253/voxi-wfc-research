# X55-WFC-StateSearcher-v3.0.ps1
# VOXI / Xiaomi 10 (cas) state search + learned recovery wrapper.
# It does NOT change Android location, Anywhere, or VPN state.
# It DOES control airplane mode and Wi-Fi. After airplane mode ON it always re-enables Wi-Fi.
# Existing v2.5 recovery script is launched as a child process only for candidate fingerprints.

$ErrorActionPreference = "Stop"

# ---------------- CONFIG ----------------
$ADB = "C:\Users\ZJH\Desktop\platform-tools\adb.exe"
$SERIAL = "fd0ff892"
$WFCCTL = "/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh"
$V25 = "C:\Users\ZJH\Desktop\X55-WFC-OneClick.ps1"

$MaxRounds = 12
$CellularWaitSec = 90
$WifiWaitSec = 45
$VpnReturnWaitSec = 20
$PollutionObserveSec = 30
$RecoveryTimeoutSec = 115
$InterRoundPauseSec = 5

$RootDir = "C:\Users\ZJH\Desktop\WFC-StateSearch-v3"
$HistoryCsv = Join-Path $RootDir "fingerprint-history.csv"
$MainLog = Join-Path $RootDir "v3-main.log"

# ---------------- BASIC HELPERS ----------------
New-Item -ItemType Directory -Force -Path $RootDir | Out-Null

function Stamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
}

function Log([string]$Text) {
    $line = "[{0}] {1}" -f (Stamp), $Text
    Write-Host $line
    try { Add-Content -LiteralPath $MainLog -Value $line -Encoding UTF8 } catch {}
}

function Invoke-Adb([string[]]$Args) {
    $out = & $ADB -s $SERIAL @Args 2>&1
    return (($out | Out-String).Trim())
}

function Root-Cmd([string]$Cmd) {
    return Invoke-Adb @("shell","su","-c",$Cmd)
}

function Save-Text([string]$Path, [string]$Text) {
    try {
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
    } catch {
        Log "WARN: could not write $Path : $($_.Exception.Message)"
    }
}

function Get-WfcStatus {
    return Root-Cmd "$WFCCTL status"
}

function Test-WfcHealthy([string]$StatusText) {
    if ($StatusText -match "IMS:\s+REGISTERED" -and
        $StatusText -match "Transport:\s+WLAN" -and
        $StatusText -match "WFC:\s+AVAILABLE") {
        return $true
    }
    return $false
}

function Get-Slot1ServiceState {
    $t = Invoke-Adb @("shell","dumpsys","telephony.registry")
    $lines = @($t -split "`r?`n" | Where-Object { $_ -match "^\s*mServiceState=" })
    if ($lines.Count -ge 2) { return $lines[1].Trim() }
    if ($lines.Count -eq 1) { return $lines[0].Trim() }
    return ""
}

function Get-LocationMode {
    $x = Invoke-Adb @("shell","settings","get","secure","location_mode")
    if ([string]::IsNullOrWhiteSpace($x)) { return "UNKNOWN" }
    return $x.Trim()
}

function Get-AnywhereState {
    $pid = Invoke-Adb @("shell","pidof","com.cxorz.anywhere")
    if ([string]::IsNullOrWhiteSpace($pid)) { return "NOT_RUNNING" }
    return "RUNNING"
}

function Get-VpnState {
    $t = Invoke-Adb @("shell","dumpsys","connectivity")
    if ($t -match "VPN CONNECTED" -or $t -match "Transports:\s*[^\r\n]*VPN") {
        if ($t -match "sessionId=FlClash" -or $t -match "com\.follow\.clash") {
            return "CONNECTED_FLCLASH"
        }
        return "CONNECTED"
    }
    return "NOT_CONNECTED"
}

function Test-WifiConnected {
    $t = Invoke-Adb @("shell","cmd","wifi","status")
    return ($t -match "Wifi is connected to")
}

function Wait-WifiConnected([int]$TimeoutSec) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        if (Test-WifiConnected) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Test-CellularReady {
    $op = Invoke-Adb @("shell","getprop","gsm.operator.numeric")
    $rat = Invoke-Adb @("shell","getprop","gsm.network.type")
    $s = Get-Slot1ServiceState
    $okOp = ($op -match "46000")
    $okRat = ($rat -match "LTE")
    $okVoice = ($s -match "mVoiceRegState=0\(IN_SERVICE\)")
    $okData = ($s -match "mDataRegState=0\(IN_SERVICE\)")
    $okWwanLte = ($s -match "getRilDataRadioTechnology=14\(LTE\)")
    return ($okOp -and $okRat -and $okVoice -and $okData -and $okWwanLte)
}

function Wait-CellularReady([int]$TimeoutSec) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        if (Test-CellularReady) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Get-KeyLogText {
    $raw = Invoke-Adb @("logcat","-d","-b","all","-v","threadtime")
    $keep = @()
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -match "networkMode=19|RatRequested|StartDataCall|qualifiedNetworks|registrationState=HOME|NOT_REG_OR_SEARCHING|IWlanProxy") {
            $keep += $line
        }
    }
    return ($keep -join "`r`n")
}

function Parse-Fingerprint([string]$Status, [string]$Slot1, [string]$KeyLog) {
    $home = if ($Slot1 -match "transportType=WLAN registrationState=HOME") { "1" } else { "0" }
    $dataSvc = if ($Slot1 -match "transportType=WLAN registrationState=HOME[^\}]*availableServices=\[DATA\]") { "1" } else { "0" }
    $preferred = if ($Slot1 -match "mIsIwlanPreferred=true") { "1" } else { "0" }
    $dataIwlan = if ($Slot1 -match "getRilDataRadioTechnology=18\(IWLAN\)") { "1" } else { "0" }

    $voiceState = "NA"
    $dataState = "NA"
    $dataRat = "NA"
    $m = [regex]::Match($Slot1, "mVoiceRegState=(\d+)\(([^)]+)\)")
    if ($m.Success) { $voiceState = $m.Groups[2].Value }
    $m = [regex]::Match($Slot1, "mDataRegState=(\d+)\(([^)]+)\)")
    if ($m.Success) { $dataState = $m.Groups[2].Value }
    $m = [regex]::Match($Slot1, "getRilDataRadioTechnology=(\d+)\(([^)]+)\)")
    if ($m.Success) { $dataRat = $m.Groups[2].Value }

    $cneReg = "UNKNOWN"
    $cneActive = "UNKNOWN"
    $req = "null"
    $m = [regex]::Match($Status, "qti\.cne:\s+registered=([A-Z]+)\s+active=([A-Z]+)\s+request=([^\s]+)")
    if ($m.Success) {
        $cneReg = $m.Groups[1].Value
        $cneActive = $m.Groups[2].Value
        $req = $m.Groups[3].Value
    }
    $reqState = if ($req -ne "null" -and $req -ne "") { "PRESENT" } else { "NULL" }

    $epdg = if ($Status -match "ePDG UDP/4500:\s+PRESENT") { "1" } else { "0" }
    $xfrm = if ($Status -match "XFRM:\s+PRESENT") { "1" } else { "0" }
    $mmtel = if ($Status -match "MMTEL:\s+READY") { "1" } else { "0" }
    $ims = if ($Status -match "IMS:\s+REGISTERED") { "1" } else { "0" }
    $wfc = if ($Status -match "WFC:\s+AVAILABLE") { "1" } else { "0" }

    $mode19 = "NONE"
    $modeLines = @($KeyLog -split "`r?`n" | Where-Object { $_ -match "networkMode=19" })
    if ($modeLines.Count -gt 0) {
        $lastMode = $modeLines[$modeLines.Count - 1]
        if ($lastMode -match "status=2" -and $lastMode -match "registered=1") {
            $mode19 = "GOOD_2_1"
        } elseif ($lastMode -match "status=0" -and $lastMode -match "registered=2") {
            $mode19 = "BAD_0_2"
        } else {
            $mode19 = "OTHER"
        }
    }

    $ratRequested = if ($KeyLog -match "RatRequested") { "1" } else { "0" }
    $startDataCall = if ($KeyLog -match "StartDataCall") { "1" } else { "0" }
    $qualified = if ($KeyLog -match "qualifiedNetworks") { "1" } else { "0" }

    $class = "UNKNOWN"
    if ($wfc -eq "1" -and $ims -eq "1") {
        $class = "HEALTHY"
    } elseif ($home -eq "1" -and $reqState -eq "PRESENT" -and $epdg -eq "0" -and $xfrm -eq "0" -and $ims -eq "0") {
        $class = "P2"
    } elseif ($home -eq "1" -and $dataIwlan -eq "1" -and $preferred -eq "1" -and $reqState -eq "NULL") {
        $class = "P1"
    } elseif ($home -eq "0" -and $reqState -eq "NULL" -and $ims -eq "0") {
        $class = "P0"
    }

    $fp = @(
        "CLASS=$class",
        "HOME=$home",
        "DATASVC=$dataSvc",
        "PREF=$preferred",
        "DIWLAN=$dataIwlan",
        "VOICE=$voiceState",
        "DATA=$dataState",
        "RAT=$dataRat",
        "CNE=$cneReg",
        "ACTIVE=$cneActive",
        "REQ=$reqState",
        "M19=$mode19",
        "RATREQ=$ratRequested",
        "STARTDC=$startDataCall",
        "QUAL=$qualified",
        "EPDG=$epdg",
        "XFRM=$xfrm",
        "MMTEL=$mmtel"
    ) -join ";"

    return [pscustomobject]@{
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

function Get-HistoryDecision([string]$Fingerprint, [string]$Class) {
    if ($Class -eq "P0") {
        return [pscustomobject]@{ Action="SKIP"; Reason="P0 known low-value state" }
    }
    if ($Class -eq "HEALTHY") {
        return [pscustomobject]@{ Action="DONE"; Reason="WFC already healthy" }
    }

    if (Test-Path $HistoryCsv) {
        try {
            $rows = @(Import-Csv -LiteralPath $HistoryCsv | Where-Object { $_.Fingerprint -eq $Fingerprint })
            $succ = @($rows | Where-Object { $_.RecoveryResult -eq "SUCCESS" }).Count
            $fail = @($rows | Where-Object { $_.RecoveryResult -eq "FAIL" }).Count
            if ($succ -gt 0) {
                return [pscustomobject]@{ Action="RECOVER"; Reason="Fingerprint has prior SUCCESS" }
            }
            if ($fail -gt 0) {
                return [pscustomobject]@{ Action="SKIP"; Reason="Same fingerprint already failed in history" }
            }
        } catch {
            Log "WARN: history read failed: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{ Action="RECOVER"; Reason="New candidate fingerprint: one learning attempt" }
}

function Append-History(
    [int]$Round,
    [object]$Fp,
    [string]$RecoveryResult,
    [string]$LocationMode,
    [string]$VpnState,
    [string]$AnywhereState
) {
    $obj = [pscustomobject]@{
        Time = Stamp
        Round = $Round
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
    } else {
        $obj | Export-Csv -LiteralPath $HistoryCsv -NoTypeInformation -Encoding UTF8
    }
}

function Run-V25-And-Watch([int]$Round, [string]$RoundDir) {
    Log "Round $Round: launching existing v2.5 recovery script."
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$V25`""
    $p = Start-Process -FilePath "powershell.exe" -ArgumentList $arg -PassThru

    $start = Get-Date
    $success = $false
    while (((Get-Date) - $start).TotalSeconds -lt $RecoveryTimeoutSec) {
        Start-Sleep -Seconds 5
        $status = Get-WfcStatus
        Save-Text (Join-Path $RoundDir "recovery-watch-latest-status.txt") $status
        if (Test-WfcHealthy $status) {
            $success = $true
            break
        }
    }

    try {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    return $success
}

# ---------------- STARTUP CHECKS ----------------
Write-Host ""
Write-Host "============================================================"
Write-Host " X55 + VOXI WFC STATE SEARCHER v3.0"
Write-Host "============================================================"
Write-Host "Auto controls : AIRPLANE + WIFI"
Write-Host "Read-only     : LOCATION + ANYWHERE + VPN"
Write-Host "Important     : after AIRPLANE ON, WIFI is always re-enabled"
Write-Host "Recovery      : existing v2.5 script"
Write-Host "============================================================"
Write-Host ""

if (-not (Test-Path $ADB)) {
    Write-Host "[ERROR] ADB not found: $ADB"
    Read-Host "Press Enter to close"
    exit 1
}
if (-not (Test-Path $V25)) {
    Write-Host "[ERROR] v2.5 script not found: $V25"
    Read-Host "Press Enter to close"
    exit 1
}

$state = Invoke-Adb @("get-state")
if ($state -notmatch "device") {
    Write-Host "[ERROR] Device $SERIAL is not connected."
    Invoke-Adb @("devices")
    Read-Host "Press Enter to close"
    exit 1
}
$rootCheck = Root-Cmd "id"
if ($rootCheck -notmatch "uid=0") {
    Write-Host "[ERROR] Magisk root not available."
    Read-Host "Press Enter to close"
    exit 1
}

$device = Invoke-Adb @("shell","getprop","ro.product.device")
$android = Invoke-Adb @("shell","getprop","ro.build.version.release")
$build = Invoke-Adb @("shell","getprop","ro.build.display.id")
if ($device.Trim() -ne "cas" -or $android.Trim() -ne "13" -or $build.Trim() -ne "V816.0.4.0.TJJCNXM") {
    Write-Host "[ERROR] Safety gate failed."
    Write-Host "DEVICE=$device"
    Write-Host "ANDROID=$android"
    Write-Host "BUILD=$build"
    Read-Host "Press Enter to close"
    exit 1
}

$initialLocation = Get-LocationMode
$initialVpn = Get-VpnState
$initialAnywhere = Get-AnywhereState

Log "Startup location_mode=$initialLocation vpn=$initialVpn anywhere=$initialAnywhere"
Log "v3 will NOT toggle location, Anywhere, or VPN."

# If already healthy, stop.
$initialStatus = Get-WfcStatus
if (Test-WfcHealthy $initialStatus) {
    Log "WFC is already healthy. Nothing to do."
    Write-Host $initialStatus
    Read-Host "Press Enter to close"
    exit 0
}

# ---------------- SEARCH LOOP ----------------
for ($round = 1; $round -le $MaxRounds; $round++) {
    $roundDir = Join-Path $RootDir ("Round-{0:D2}-{1}" -f $round, (Get-Date).ToString("yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $roundDir | Out-Null

    Log "------------------------------------------------------------"
    Log "Round $round/$MaxRounds START"

    # Keep the current external variables as fixed as practical.
    $locBefore = Get-LocationMode
    $vpnBefore = Get-VpnState
    $anyBefore = Get-AnywhereState
    Log "External state before cycle: location_mode=$locBefore vpn=$vpnBefore anywhere=$anyBefore"

    # Clean cellular baseline.
    Log "Round $round: airplane OFF."
    Root-Cmd "cmd connectivity airplane-mode disable" | Out-Null
    Start-Sleep -Seconds 2

    # Wi-Fi OFF during cellular attach makes the baseline deterministic.
    Log "Round $round: Wi-Fi OFF during cellular baseline."
    Root-Cmd "svc wifi disable" | Out-Null

    Log "Round $round: waiting for VOXI roaming cellular baseline (46000/LTE/IN_SERVICE)."
    if (-not (Wait-CellularReady $CellularWaitSec)) {
        Log "Round $round: cellular baseline timeout. Saving diagnostics and moving on."
        Save-Text (Join-Path $roundDir "cellular-timeout-registry.txt") (Invoke-Adb @("shell","dumpsys","telephony.registry"))
        Save-Text (Join-Path $roundDir "cellular-timeout-props.txt") ((Invoke-Adb @("shell","getprop","gsm.operator.numeric")) + "`r`n" + (Invoke-Adb @("shell","getprop","gsm.network.type")))
        Start-Sleep -Seconds $InterRoundPauseSec
        continue
    }

    Save-Text (Join-Path $roundDir "cellular-baseline-slot1.txt") (Get-Slot1ServiceState)
    Log "Round $round: cellular baseline confirmed."

    # Clear logs immediately before the transition we want to study.
    Invoke-Adb @("logcat","-b","all","-c") | Out-Null

    Log "Round $round: airplane ON."
    Root-Cmd "cmd connectivity airplane-mode enable" | Out-Null

    # User confirmed airplane mode on this ROM disconnects Wi-Fi.
    Start-Sleep -Seconds 2
    Log "Round $round: re-enabling Wi-Fi after airplane ON."
    Root-Cmd "svc wifi enable" | Out-Null

    if (-not (Wait-WifiConnected $WifiWaitSec)) {
        Log "Round $round: Wi-Fi did not reconnect in time."
        Save-Text (Join-Path $roundDir "wifi-status.txt") (Invoke-Adb @("shell","cmd","wifi","status"))
        Start-Sleep -Seconds $InterRoundPauseSec
        continue
    }
    Log "Round $round: Wi-Fi connected."

    # If VPN was connected before the cycle, give it a chance to auto-return.
    if ($vpnBefore -match "^CONNECTED") {
        $vpnStart = Get-Date
        $vpnReturned = $false
        while (((Get-Date) - $vpnStart).TotalSeconds -lt $VpnReturnWaitSec) {
            $v = Get-VpnState
            if ($v -match "^CONNECTED") {
                $vpnReturned = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        if ($vpnReturned) {
            Log "Round $round: VPN auto-returned."
        } else {
            Log "Round $round: VPN did not auto-return within $VpnReturnWaitSec sec; v3 did not force it."
        }
    }

    # Observe without changing anything.
    $sampleTimes = @(5,10,15,20,30)
    $lastMark = 0
    foreach ($mark in $sampleTimes) {
        $sleepFor = $mark - $lastMark
        if ($sleepFor -gt 0) { Start-Sleep -Seconds $sleepFor }
        $lastMark = $mark

        $s = Get-WfcStatus
        $slot = Get-Slot1ServiceState
        Save-Text (Join-Path $roundDir ("status-T{0}.txt" -f $mark)) $s
        Save-Text (Join-Path $roundDir ("slot1-T{0}.txt" -f $mark)) $slot

        if (Test-WfcHealthy $s) {
            Log "Round $round: WFC became healthy naturally at T+$mark sec."
            $keys = Get-KeyLogText
            Save-Text (Join-Path $roundDir "keylog.txt") $keys
            $fp = Parse-Fingerprint $s $slot $keys
            Append-History $round $fp "NATURAL_SUCCESS" (Get-LocationMode) (Get-VpnState) (Get-AnywhereState)
            Write-Host ""
            Write-Host "============================================================"
            Write-Host " WFC SUCCESS - no v2.5 required"
            Write-Host "============================================================"
            Write-Host "Round: $round"
            Write-Host "Logs : $roundDir"
            Read-Host "Press Enter to close"
            exit 0
        }
    }

    $preStatus = Get-WfcStatus
    $preSlot = Get-Slot1ServiceState
    $keyLog = Get-KeyLogText

    Save-Text (Join-Path $roundDir "PRE-V25-status.txt") $preStatus
    Save-Text (Join-Path $roundDir "PRE-V25-slot1.txt") $preSlot
    Save-Text (Join-Path $roundDir "PRE-V25-keylog.txt") $keyLog
    Save-Text (Join-Path $roundDir "PRE-V25-full-logcat.txt") (Invoke-Adb @("logcat","-d","-b","all","-v","threadtime"))

    $fp = Parse-Fingerprint $preStatus $preSlot $keyLog
    $locNow = Get-LocationMode
    $vpnNow = Get-VpnState
    $anyNow = Get-AnywhereState

    Log "Round $round: class=$($fp.Class)"
    Log "Round $round: fingerprint=$($fp.Fingerprint)"
    Log "Round $round: external location_mode=$locNow vpn=$vpnNow anywhere=$anyNow"

    if ($fp.Class -eq "HEALTHY") {
        Append-History $round $fp "NATURAL_SUCCESS" $locNow $vpnNow $anyNow
        Log "Round $round: WFC already healthy."
        Write-Host $preStatus
        Read-Host "Press Enter to close"
        exit 0
    }

    $decision = Get-HistoryDecision $fp.Fingerprint $fp.Class
    Log "Round $round: decision=$($decision.Action) reason=$($decision.Reason)"

    if ($decision.Action -eq "SKIP") {
        Append-History $round $fp "SKIPPED" $locNow $vpnNow $anyNow
        Start-Sleep -Seconds $InterRoundPauseSec
        continue
    }

    if ($decision.Action -eq "RECOVER") {
        Append-History $round $fp "ATTEMPTING" $locNow $vpnNow $anyNow

        $ok = Run-V25-And-Watch $round $roundDir
        $postStatus = Get-WfcStatus
        Save-Text (Join-Path $roundDir "POST-V25-status.txt") $postStatus

        if ($ok -or (Test-WfcHealthy $postStatus)) {
            Log "Round $round: v2.5 RECOVERY SUCCESS."
            Append-History $round $fp "SUCCESS" $locNow $vpnNow $anyNow
            Write-Host ""
            Write-Host "============================================================"
            Write-Host " V3 FOUND A RECOVERABLE POLLUTED STATE"
            Write-Host "============================================================"
            Write-Host "Round      : $round"
            Write-Host "Class      : $($fp.Class)"
            Write-Host "Mode19     : $($fp.Mode19)"
            Write-Host "Fingerprint: $($fp.Fingerprint)"
            Write-Host "Logs       : $roundDir"
            Write-Host ""
            Write-Host $postStatus
            Read-Host "Press Enter to close"
            exit 0
        } else {
            Log "Round $round: v2.5 recovery FAIL."
            Append-History $round $fp "FAIL" $locNow $vpnNow $anyNow
        }
    }

    Start-Sleep -Seconds $InterRoundPauseSec
}

Write-Host ""
Write-Host "============================================================"
Write-Host " SEARCH FINISHED - NO RECOVERABLE STATE FOUND"
Write-Host "============================================================"
Write-Host "Rounds : $MaxRounds"
Write-Host "History: $HistoryCsv"
Write-Host "Log    : $MainLog"
Write-Host ""
Write-Host "The history file is intentionally persistent, so later runs can"
Write-Host "skip fingerprints that already failed and prefer fingerprints"
Write-Host "that previously succeeded."
Write-Host ""
Read-Host "Press Enter to close"
