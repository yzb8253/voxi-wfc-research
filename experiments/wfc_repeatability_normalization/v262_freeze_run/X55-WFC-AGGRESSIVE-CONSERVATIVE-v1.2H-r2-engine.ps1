[CmdletBinding()]
param(
    [string]$Serial = 'fd0ff892',
    [ValidateRange(1,3)][int]$MaxRecoveryAttempts = 2,
    [ValidateSet('V12H')][string]$A0PreflightMode = 'V12H'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Preflight = Join-Path $PSScriptRoot 'repeatability_preflight.ps1'
$LightCollector = Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\capture_lightweight_state_v12h_r2.ps1'
$LightClassifier = Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\classify_lightweight_state_v12h_r1.ps1'
$CurrentCneProjection = Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\current_cne_projection_v12h_r2.ps1'
$UiccDeepFallback = Join-Path $PSScriptRoot 'uicc_apps_deep_fallback.ps1'
$SplitPreparer = Join-Path $PSScriptRoot 'prepare_frozen_residue_split_v12h_r1.ps1'
$Recovery = Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.2-fast-holder-exp.ps1'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
. $CurrentCneProjection
$LogDir = Join-Path $PSScriptRoot 'Aggressive-Conservative-Logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$VariantLabel = 'v1.2H'
$LogFile = Join-Path $LogDir ('X55-WFC-AGGRESSIVE-CONSERVATIVE-{0}-{1}.log' -f $VariantLabel,(Get-Date -Format 'yyyyMMdd_HHmmss'))

$ExpectedDevice = 'cas'
$ExpectedAndroid = '13'
$ExpectedBuild = 'V816.0.4.0.TJJCNXM'
$ExpectedFingerprint = 'Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$ASettleMinSeconds=5
$ASettleMaxSeconds=20
$PSettleMinSeconds=5
$PSettleMaxSeconds=20
$script:LightFastCount=0
$script:FullFallbackCount=0
$script:AttemptUsed=0
$script:WfcResult='NOT_COMPLETED'
$script:FrozenResidueFastCount=0
$script:FrozenSplitFastCount=0
$script:PerMgrStartCount=0
$script:ALightMs=0
$script:PostNormalizationLightMs=0
$script:FirstFullMs=0
$script:SecondFullMs=0
$script:A0TotalMs=0
$script:PTotalMs=0
$script:CoreTotalMs=0
$script:EntryHolderImpl='UNKNOWN'

function Assert-ScriptSyntax {
    $files = @(
        $Preflight,
        (Join-Path $PSScriptRoot 'normalize_a1_native_owner.ps1'),
        (Join-Path $PSScriptRoot 'normalize_a1_qcrild2_reacquire.ps1'),
        $UiccDeepFallback,
        $SplitPreparer,
        $CurrentCneProjection,
        (Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\holder_identity_v12h_r1.ps1'),
        $Recovery,
        (Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\capture_lightweight_state.ps1'),
        (Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\classify_lightweight_state.ps1'),
        (Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\invoke_shadow_comparison.ps1')
    )

    foreach($file in $files) {
        Require (Test-Path -LiteralPath $file) ("Required script missing: {0}" -f $file)
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file,
            [ref]$tokens,
            [ref]$errors
        )
        if($errors.Count -gt 0) {
            $detail = @($errors | ForEach-Object {
                "line {0}: {1}" -f $_.Extent.StartLineNumber,$_.Message
            }) -join '; '
            throw ("SCRIPT_SYNTAX_FAIL: {0}: {1}" -f (Split-Path $file -Leaf),$detail)
        }
    }

    Log 'SCRIPT_SYNTAX_GATE=PASS'
}

function Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

function Write-Timing([string]$Name,[Diagnostics.Stopwatch]$Stopwatch) {
    $Stopwatch.Stop()
    Log ("TIMING name={0} ms={1}" -f $Name,$Stopwatch.ElapsedMilliseconds)
}
function Record-FullTiming([int64]$Milliseconds) {
    if($script:FirstFullMs -eq 0){$script:FirstFullMs=$Milliseconds;Log ("FIRST_FULL_MS={0}" -f $Milliseconds)}
    elseif($script:SecondFullMs -eq 0){$script:SecondFullMs=$Milliseconds;Log ("SECOND_FULL_MS={0}" -f $Milliseconds)}
}

function Write-TotalTiming {
    if($null -ne $script:WrapperTotal -and $script:WrapperTotal.IsRunning) {
        Write-Timing wrapper_total $script:WrapperTotal
        Log ("TOTAL_END_TO_END_MS={0}" -f $script:WrapperTotal.ElapsedMilliseconds)
        Log ("TOTAL_RECOVERY_MS={0}" -f $script:WrapperTotal.ElapsedMilliseconds)
        Log ("ATTEMPT_USED={0}" -f $script:AttemptUsed)
        Log ("WFC_RESULT={0}" -f $script:WfcResult)
        Log ("LIGHT_FAST_COUNT={0}" -f $script:LightFastCount)
        Log ("FULL_FALLBACK_COUNT={0}" -f $script:FullFallbackCount)
        Log ("A_LIGHT_MS={0}" -f $script:ALightMs)
        Log ("FROZEN_RESIDUE_FAST_COUNT={0}" -f $script:FrozenResidueFastCount)
        Log ("FROZEN_SPLIT_FAST_COUNT={0}" -f $script:FrozenSplitFastCount)
        Log ("PER_MGR_START_COUNT={0}" -f $script:PerMgrStartCount)
        Log ("POST_NORMALIZATION_LIGHT_MS={0}" -f $script:PostNormalizationLightMs)
        Log ("FIRST_FULL_MS={0}" -f $script:FirstFullMs)
        Log ("SECOND_FULL_MS={0}" -f $script:SecondFullMs)
        Log ("A0_TOTAL_MS={0}" -f $script:A0TotalMs)
        Log ("P_TOTAL_MS={0}" -f $script:PTotalMs)
        Log ("CORE_TOTAL_MS={0}" -f $script:CoreTotalMs)
        Log ("ENTRY_HOLDER_IMPL={0}" -f $script:EntryHolderImpl)
    }
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
    $timer = [Diagnostics.Stopwatch]::StartNew()
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
    Write-Timing ensure_wifi_on $timer
}

function Get-WfcStatusText {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $r = RootResult "$WfcCtl status"
    # The validated v2.6.2 core treats wfcctl status as a probe and parses
    # its text even when the helper returns a non-zero process exit code.
    # Do the same here: fail only when the expected status body is missing.
    Require (-not [string]::IsNullOrWhiteSpace($r.Text)) 'wfcctl status returned no output.'
    Require ($r.Text -match '(?m)^IMS:\s+' -and $r.Text -match '(?m)^WFC:\s+') 'wfcctl status output is incomplete.'
    Write-Timing wfc_status_text $timer
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

function Get-CurrentCneSnapshot {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $raw=RootResult 'dumpsys connectivity'
    Require ($raw.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($raw.Text)) 'current CNE connectivity dump unavailable.'
    $current=Get-CurrentCneProjection -ConnectivityText $raw.Text -SubId 11
    Require ($current.valid) 'current CNE table boundary missing; fail closed.'
    $probe=Get-WfcStatusJson
    $probeRequest=$probe.connectivity.qtiCneRequestId
    $probeSatisfied=$probe.connectivity.qtiCneSatisfiedRequestId
    $stale=(-not (Test-NullableCneEqual $current.requestId $probeRequest) -or -not (Test-NullableCneEqual $current.satisfiedId $probeSatisfied))
    if($stale){Log ("STALE_PROBE_DIAGNOSTIC=1 CURRENT_CNE_REQUEST={0} CURRENT_CNE_SATISFIED={1} PROBE_REPORTED_REQUEST={2} PROBE_REPORTED_SATISFIED={3}" -f $current.requestId,$current.satisfiedId,$probeRequest,$probeSatisfied)}
    $result = [pscustomobject]@{
        Request = if($null -eq $current.requestId){'null'}else{[string]$current.requestId}
        Satisfied = if($null -eq $current.satisfiedId){'null'}else{[string]$current.satisfiedId}
        ProbeReportedRequest = if($null -eq $probeRequest){'null'}else{[string]$probeRequest}
        ProbeReportedSatisfied = if($null -eq $probeSatisfied){'null'}else{[string]$probeSatisfied}
        StaleProbe = $stale
        Source = 'CONNECTIVITY_CURRENT_TABLE'
    }
    Write-Timing current_cne_snapshot $timer
    $result
}

function Assert-PlatformAndTarget {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Require (Test-Path -LiteralPath $Adb) ("adb.exe not found: {0}" -f $Adb)
    Require (Test-Path -LiteralPath $Preflight) ("preflight missing: {0}" -f $Preflight)
    Require (Test-Path -LiteralPath $UiccDeepFallback) ("UICC deep fallback missing: {0}" -f $UiccDeepFallback)
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
    Write-Timing platform_target_safety_gate $timer
}


function Get-LightPhaseObservation([string]$Phase) {
    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $path=Join-Path $LogDir ("light_{0}_{1}.json" -f $Phase.ToLowerInvariant(),$stamp)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LightCollector -Serial $Serial -OutputPath $path | Out-Host
    $collectorRc=$LASTEXITCODE
    $timer.Stop()
    if($collectorRc -ne 0 -or -not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='COLLECTOR_RUNTIME';Classification='UNKNOWN';ElapsedMs=$timer.ElapsedMilliseconds}
    }
    try {
        $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        $classified=((& $LightClassifier -InputPath $path -OutputFormat Json)|ConvertFrom-Json)
        $script:LastLightPath=$path
        if($script:EntryHolderImpl -eq 'UNKNOWN' -and $state.holder.processExists -and $classified.holderImplementation -in @('FAST','OLD')){$script:EntryHolderImpl=[string]$classified.holderImplementation}
    }
    catch {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='JSON_OR_CLASSIFIER_RUNTIME';Classification='UNKNOWN';ElapsedMs=$timer.ElapsedMilliseconds}
    }
    $structural=@($classified.errors|Where-Object{$_ -match '^(missing:|schema:|capture:)'})
    if(-not $state.capture.complete -or @($state.capture.errors).Count -ne 0 -or $structural.Count -ne 0) {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='STRUCTURAL_UNCERTAINTY';Classification=$classified.classification;ElapsedMs=$timer.ElapsedMilliseconds}
    }
    if($null -ne $state.cne.requestId -or $null -ne $state.cne.satisfiedId) {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='ACTIVE_CNE_UNPROVEN';Classification=$classified.classification;ElapsedMs=$timer.ElapsedMilliseconds}
    }
    if($classified.classification -eq 'UNKNOWN') {
        $residue=($state.holder.processExists -or @($classified.errors|Where-Object{$_ -match '^(native:|holder:|identity:)'}).Count -ne 0)
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$residue;Reason=$(if($residue){'RESIDUE_OR_IDENTITY_UNCERTAINTY'}else{'UNKNOWN'});Classification='UNKNOWN';ElapsedMs=$timer.ElapsedMilliseconds}
    }
    if($classified.classification -eq 'FROZEN_SPLIT_RESIDUE') {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='FROZEN_SPLIT_RESIDUE';Classification='FROZEN_SPLIT_RESIDUE';ElapsedMs=$timer.ElapsedMilliseconds}
    }
    if($classified.classification -eq 'FROZEN_RESIDUE') {
        return [pscustomobject]@{Accepted=$false;ImmediateFallback=$true;Reason='FROZEN_RESIDUE';Classification='FROZEN_RESIDUE';ElapsedMs=$timer.ElapsedMilliseconds}
    }
    $allowed=if($Phase -eq 'A'){@('A0_READY','HEALTHY_FREEZE')}else{@('P0_READY','HEALTHY_FREEZE')}
    [pscustomobject]@{Accepted=($allowed -contains [string]$classified.classification);ImmediateFallback=$false;Reason=$(if($allowed -contains [string]$classified.classification){'CLEAR_VALIDATED_STATE'}else{'PHASE_CLASS_MISMATCH'});Classification=$classified.classification;ElapsedMs=$timer.ElapsedMilliseconds}
}

function Wait-DynamicPhase([string]$Phase,[int]$MinSeconds,[int]$MaxSeconds) {
    $waited=0
    $last=$null
    while($waited -lt $MaxSeconds) {
        $step=if($waited -eq 0){$MinSeconds}else{[Math]::Min(5,$MaxSeconds-$waited)}
        Start-Sleep -Seconds $step
        $waited+=$step
        $last=Get-LightPhaseObservation $Phase
        if($Phase -eq 'A'){$script:ALightMs+=[int64]$last.ElapsedMs}
        if($last.Accepted -or $last.ImmediateFallback){break}
    }
    $actual=$waited
    Log ("{0}_SETTLE_MIN={1}" -f $Phase,$MinSeconds)
    Log ("{0}_SETTLE_ACTUAL={1}" -f $Phase,$actual)
    Log ("{0}_SETTLE_MAX={1}" -f $Phase,$MaxSeconds)
    [pscustomobject]@{Observation=$last;ActualSeconds=$actual}
}

function Invoke-FullPPreflight {
    $fullTimer=[Diagnostics.Stopwatch]::StartNew()
    $script:FullFallbackCount++
    Log 'SNAPSHOT_MODE=FULL_FALLBACK'
    $savedEap=$ErrorActionPreference
    try {$ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Preflight -Serial $Serial 2>&1;$rc=$LASTEXITCODE}
    finally {$ErrorActionPreference=$savedEap}
    foreach($line in @($output)){Write-Host $line}
    $text=(@($output|ForEach-Object{[string]$_}) -join [Environment]::NewLine)
    Require ($rc -eq 0) ("P full fallback failed exit={0}" -f $rc)
    Require ($text -match 'PREFLIGHT_RESULT=(P0_READY|HEALTHY_FREEZE_ZERO_WRITE)') 'P full fallback did not confirm P0/healthy'
    $fullTimer.Stop();Record-FullTiming $fullTimer.ElapsedMilliseconds
}


function Invoke-PreflightNormalization {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $fullTimer = [Diagnostics.Stopwatch]::StartNew()
    Require ((Get-AirplaneMode) -eq '0') 'Normalization is only allowed with airplane mode OFF.'

    Log 'PREFLIGHT_APPLY_NORMALIZATION=START'

    # repeatability_preflight intentionally allows its first normalization path
    # to fail and then falls back to qcrild2 reacquire. With the wrapper's
    # global ErrorActionPreference=Stop, child stderr must not terminate the
    # wrapper before that fallback completes.
    $savedEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Preflight -Serial $Serial -ApplyNormalization 2>&1
        $rc = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedEap
    }

    foreach($line in @($output)) { Write-Host $line }
    $text = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)

    Require ($rc -eq 0) ("Preflight normalization failed with exit code {0}." -f $rc)
    Require ($text -match 'PREFLIGHT_RESULT=(A0_READY|A0_NORMALIZED)') 'Preflight did not confirm A0_READY/A0_NORMALIZED.'
    Log ("PREFLIGHT_APPLY_NORMALIZATION=PASS result={0}" -f $Matches[1])
    $fullTimer.Stop();Record-FullTiming $fullTimer.ElapsedMilliseconds
    Write-Timing preflight_normalization_total $timer
}

function Invoke-ReadOnlyFullA0Verification {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $fullTimer = [Diagnostics.Stopwatch]::StartNew()
    Log 'POST_NORMALIZATION_FULL_FALLBACK=START'
    $savedEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Preflight -Serial $Serial 2>&1
        $rc = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedEap
    }
    foreach($line in @($output)) { Write-Host $line }
    $text = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    Require ($rc -eq 0 -and $text -match 'PREFLIGHT_RESULT=A0_READY') 'Read-only full fallback did not confirm A0_READY.'
    Log 'POST_NORMALIZATION_FULL_FALLBACK=PASS'
    $fullTimer.Stop();Record-FullTiming $fullTimer.ElapsedMilliseconds
    Write-Timing post_normalization_full_fallback $timer
}

function Invoke-V12HFrozenNormalization {
    param([object]$InitialObservation)

    Require ($A0PreflightMode -eq 'V12H') 'v1.2H frozen path selected outside v1.2H mode.'
    Require ($null -ne $InitialObservation -and @('FROZEN_RESIDUE','FROZEN_SPLIT_RESIDUE') -contains [string]$InitialObservation.Classification) 'v1.2H frozen path requires an exact lightweight residue fingerprint.'
    Require ((Get-AirplaneMode) -eq '0') 'Frozen normalization is only allowed with airplane mode OFF.'

    if($InitialObservation.Classification -eq 'FROZEN_RESIDUE') {
        Require (-not [string]::IsNullOrWhiteSpace([string]$script:LastLightPath)) 'exact lightweight observation path unavailable.'
        Log 'FROZEN_RESIDUE_TRANSITION=START action=ONE_CTL_START_VENDOR_PER_MGR'
        $savedEap=$ErrorActionPreference
        try {$ErrorActionPreference='Continue';$prepareOutput=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SplitPreparer -Serial $Serial -ObservationPath $script:LastLightPath -TimeoutSeconds 15 2>&1;$prepareRc=$LASTEXITCODE}
        finally {$ErrorActionPreference=$savedEap}
        foreach($line in @($prepareOutput)){Log ([string]$line)}
        $prepareText=@($prepareOutput|ForEach-Object{[string]$_})-join [Environment]::NewLine
        if($prepareText -match 'PER_MGR_START_COUNT=([01])'){$script:PerMgrStartCount+=[int]$Matches[1]}
        if($prepareRc -eq 40) {
            Log 'FROZEN_RESIDUE_TRANSITION=PRECHECK_DRIFT_FULL_FALLBACK'
            $script:FullFallbackCount++;Invoke-PreflightNormalization;return
        }
        Require ($prepareRc -eq 0 -and $prepareText -match 'SPLIT_GATE_RESULT=FROZEN_SPLIT_READY') 'controlled per_mgr start did not form strict split; STOP with no further writes.'
        $script:FrozenResidueFastCount++
        Log 'FROZEN_RESIDUE_TRANSITION=PASS FROZEN_SPLIT_READY'
    }
    else {
        $script:FrozenSplitFastCount++
        Log 'FROZEN_SPLIT_ENTRY=PASS no_per_mgr_start_required'
    }

    $reacquire=Join-Path $PSScriptRoot 'normalize_a1_qcrild2_reacquire.ps1'
    $timer=[Diagnostics.Stopwatch]::StartNew();Log 'QCRILD2_REACQUIRE=START action=EXISTING_QCRILD2_REACQUIRE_ONLY'
    $savedEap=$ErrorActionPreference
    try {$ErrorActionPreference='Continue';$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $reacquire -Serial $Serial 2>&1;$rc=$LASTEXITCODE}
    finally {$ErrorActionPreference=$savedEap}
    foreach($line in @($output)){Log ([string]$line)}
    $timer.Stop();Log ("QCRILD2_REACQUIRE_MS={0}" -f $timer.ElapsedMilliseconds)
    $text=@($output|ForEach-Object{[string]$_})-join [Environment]::NewLine
    if($text -match 'TIMING name=qcrild2_holder_exit_latency ms=(\d+)'){Log ("HOLDER_TERM_TO_MAIN_GONE_MS={0}" -f $Matches[1])}
    if($text -match 'TIMING name=qcrild2_owner_none_latency ms=(\d+)'){Log ("HOLDER_TERM_TO_OWNER_NONE_MS={0}" -f $Matches[1])}
    Require ($rc -eq 0) ("existing qcrild2 reacquire failed with exit code {0}; STOP with no fallback writes." -f $rc)

    $post=Get-LightPhaseObservation 'A';$script:PostNormalizationLightMs+=[int64]$post.ElapsedMs
    Log ("POST_NORMALIZATION_LIGHT classification={0} reason={1} ms={2}" -f $post.Classification,$post.Reason,$post.ElapsedMs)
    if($post.Accepted -and $post.Classification -eq 'A0_READY'){$script:LightFastCount++;Log 'POST_NORMALIZATION_LIGHT=PASS A0_READY';return}

    # The mutation has completed. A non-canonical light result authorizes only
    # one read-only full verification; it never authorizes normalization again.
    $script:FullFallbackCount++;Invoke-ReadOnlyFullA0Verification
}

function Prepare-A0 {
    $a0Timer=[Diagnostics.Stopwatch]::StartNew()
    Log 'A0_PREP=START'
    Require ((Get-AirplaneMode) -eq '0') 'Entry/normalization requires airplane mode OFF.'
    Ensure-WifiOn
    $dynamic=Wait-DynamicPhase -Phase 'A' -MinSeconds $ASettleMinSeconds -MaxSeconds $ASettleMaxSeconds
    if($null -ne $dynamic.Observation -and $dynamic.Observation.Accepted) {
        $script:LightFastCount++
        Log 'SNAPSHOT_MODE=LIGHT_FAST_PATH'
        Log ("LIGHT_CLASSIFICATION={0}" -f $dynamic.Observation.Classification)
    }
    elseif($null -ne $dynamic.Observation -and @('FROZEN_RESIDUE','FROZEN_SPLIT_RESIDUE') -contains [string]$dynamic.Observation.Classification) {
        Log ("SNAPSHOT_MODE=LIGHT_{0}_FAST_PATH" -f $dynamic.Observation.Classification)
        Log ("LIGHT_CLASSIFICATION={0}" -f $dynamic.Observation.Classification)
        Invoke-V12HFrozenNormalization -InitialObservation $dynamic.Observation
    }
    else {
        $reason=if($null -eq $dynamic.Observation){'NO_CLEAR_LIGHT_STATE_BY_MAX'}else{$dynamic.Observation.Reason}
        Log 'SNAPSHOT_MODE=FULL_FALLBACK'
        Log ("FALLBACK_REASON={0}" -f $reason)
        $script:FullFallbackCount++
        Invoke-PreflightNormalization
    }

    Require ((Get-AirplaneMode) -eq '0') 'A0 verification failed: airplane mode is not OFF.'
    $cne = Get-CurrentCneSnapshot
    Log ("A0_CNE source={0} request={1} satisfied={2}" -f $cne.Source,$cne.Request,$cne.Satisfied)
    Log ("A0_CNE_PROBE_DIAGNOSTIC request={0} satisfied={1} stale={2}" -f $cne.ProbeReportedRequest,$cne.ProbeReportedSatisfied,$cne.StaleProbe)
    if($cne.Request -eq 'null') {Log 'A0_PREP=PASS cneRequest=null'}
    else {Log ("A0_PREP=PASS cneRequest={0} (allowed in airplane-OFF A state)" -f $cne.Request)}
    $a0Timer.Stop();$script:A0TotalMs+=$a0Timer.ElapsedMilliseconds;Log ("A0_TOTAL_MS={0}" -f $a0Timer.ElapsedMilliseconds)
}

function Prepare-P {
    $pTimer=[Diagnostics.Stopwatch]::StartNew()
    Log 'P_PREP=START'
    $airplaneTimer = [Diagnostics.Stopwatch]::StartNew()
    Set-AirplaneMode $true
    Write-Timing airplane_off_to_on $airplaneTimer
    Ensure-WifiOn
    $dynamic=Wait-DynamicPhase -Phase 'P' -MinSeconds $PSettleMinSeconds -MaxSeconds $PSettleMaxSeconds
    if($null -ne $dynamic.Observation -and $dynamic.Observation.Accepted) {
        $script:LightFastCount++
        Log 'SNAPSHOT_MODE=LIGHT_FAST_PATH'
        Log ("LIGHT_CLASSIFICATION={0}" -f $dynamic.Observation.Classification)
    }
    else {
        $reason=if($null -eq $dynamic.Observation){'NO_CLEAR_LIGHT_STATE_BY_MAX'}else{$dynamic.Observation.Reason}
        Log ("FALLBACK_REASON={0}" -f $reason)
        Invoke-FullPPreflight
    }

    if(Test-WfcHealthy) {$pTimer.Stop();$script:PTotalMs+=$pTimer.ElapsedMilliseconds;Log ("P_TOTAL_MS={0}" -f $pTimer.ElapsedMilliseconds);Log 'P_PREP=ALREADY_HEALTHY';return $true}
    $cne = Get-CurrentCneSnapshot
    Log ("P_CNE source={0} request={1} satisfied={2}" -f $cne.Source,$cne.Request,$cne.Satisfied)
    Log ("P_CNE_PROBE_DIAGNOSTIC request={0} satisfied={1} stale={2}" -f $cne.ProbeReportedRequest,$cne.ProbeReportedSatisfied,$cne.StaleProbe)
    if($cne.Request -ne 'null') {
        Write-Host ("[CNE GATE] Existing request {0} detected before v2.6.2. Core recovery is blocked; return to A0 and normalize instead." -f $cne.Request) -ForegroundColor Yellow
        Log ("P_CNE_GATE=BLOCK_EXISTING_REQUEST request={0}" -f $cne.Request)
        $pTimer.Stop();$script:PTotalMs+=$pTimer.ElapsedMilliseconds;Log ("P_TOTAL_MS={0}" -f $pTimer.ElapsedMilliseconds);return $false
    }
    Log 'P_CNE_GATE=PASS request=null'
    $pTimer.Stop();$script:PTotalMs+=$pTimer.ElapsedMilliseconds;Log ("P_TOTAL_MS={0}" -f $pTimer.ElapsedMilliseconds)
    return $true
}

function Invoke-V262Core {
    Log 'V262_CORE=START'
    $timer = [Diagnostics.Stopwatch]::StartNew()

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    # The proven v2.6.2 core ends with Read-Host for manual runs.
    # Run it non-interactively so that final pause cannot deadlock this wrapper.
    # All phone-side recovery/cleanup work happens before that final prompt.
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Recovery + '" -NoPause'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardInput = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    if(-not $proc.Start()) { throw 'Unable to start v2.6.2 core.' }

    $proc.WaitForExit()
    $rc = $proc.ExitCode
    $proc.Dispose()

    Log ("V262_CORE=EXIT code={0}" -f $rc)
    Write-Timing v262_core_total $timer
    $script:CoreTotalMs+=$timer.ElapsedMilliseconds
    Log ("CORE_TOTAL_MS={0}" -f $timer.ElapsedMilliseconds)
    $rc
}

function Invoke-UiccDeepFallback {
    Require ((Get-AirplaneMode) -eq '0') 'UICC deep fallback requires clean airplane-OFF A state.'
    Log 'UICC_DEEP_FALLBACK=START'

    $savedEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $UiccDeepFallback -Serial $Serial 2>&1
        $rc = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedEap
    }

    foreach($line in @($output)) { Write-Host $line }
    $text = (@($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)

    Require ($rc -eq 0) ("UICC deep fallback failed with exit code {0}." -f $rc)
    Require ($text -match 'UICC_DEEP_FALLBACK=PASS') 'UICC deep fallback did not confirm PASS.'
    Log 'UICC_DEEP_FALLBACK=PASS'
}

$script:WrapperTotal = [Diagnostics.Stopwatch]::StartNew()
Log '============================================================'
Log 'MODE=AGGRESSIVE_CONSERVATIVE_V1_2H_R2'
Log 'HOLDER_IMPL=FAST'
Log 'X55 WFC AGGRESSIVE CONSERVATIVE v1.2H-r2 started'
Log ("Serial={0} MaxRecoveryAttempts={1}" -f $Serial,$MaxRecoveryAttempts)
Log 'PON_SETTLE=10s SIM_OFF_HOLD=3s SIM_WINDOW=30s_sleep_budget_plus_probe_runtime'
Log 'Core recovery is the isolated v2.6.2 FAST-holder experiment copy; all non-holder core behavior is unchanged.'
Log '============================================================'

try {
    $syntaxTimer = [Diagnostics.Stopwatch]::StartNew()
    Assert-ScriptSyntax
    Write-Timing syntax_gate $syntaxTimer
    Assert-PlatformAndTarget

    $entryAirplane = Get-AirplaneMode
    Require ($entryAirplane -eq '0') 'USER ENTRY GATE: start the stable script with airplane mode OFF.'
    Log 'ENTRY_GATE=PASS airplane=OFF'
    $noCneFailureCount = 0

    for($attempt = 1; $attempt -le $MaxRecoveryAttempts; $attempt++) {
        Write-Host ''
        Write-Host '============================================================'
        Write-Host (" STABLE RECOVERY ATTEMPT {0}/{1}" -f $attempt,$MaxRecoveryAttempts)
        Write-Host '============================================================'
        $script:AttemptUsed=$attempt
        Log ("ATTEMPT={0} START" -f $attempt)

        Prepare-A0

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} HEALTHY_IN_A_UNEXPECTED_BUT_ACCEPTED" -f $attempt)
            $script:WfcResult='HEALTHY'
            Write-Host '[OK] WFC became healthy before P entry. Leaving state untouched.' -ForegroundColor Green
            Write-TotalTiming
            exit 0
        }

        $pGate = Prepare-P

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} HEALTHY_BEFORE_CORE" -f $attempt)
            $script:WfcResult='HEALTHY'
            Write-Host '[OK] WFC became healthy before the core recovery. Leaving airplane mode ON and state untouched.' -ForegroundColor Green
            Write-TotalTiming
            exit 0
        }

        if(-not $pGate) {
            Log 'P_CNE_GATE_DIRTY_RETURN_TO_A'
            Set-AirplaneMode $false
            if($attempt -lt $MaxRecoveryAttempts) {
                Log 'BOUNDED_RETRY=P_CNE_GATE_DIRTY'
                continue
            }
            Log 'FINAL_ATTEMPT_BLOCKED_BY_DIRTY_P_CNE'
            break
        }

        $coreStartedAt = Get-Date
        $coreRc = Invoke-V262Core

        if(Test-WfcHealthy) {
            Log ("ATTEMPT={0} SUCCESS coreExit={1}" -f $attempt,$coreRc)
            Log 'FINAL=WFC_HEALTHY_FREEZE'
            $script:WfcResult='HEALTHY'
            Write-Host ''
            Write-Host '[OK] STABLE WRAPPER RESULT: WFC HEALTHY. Frozen healthy state is preserved.' -ForegroundColor Green
            Write-TotalTiming
            exit 0
        }

        $afterCne = Get-CurrentCneSnapshot
        $coreFreshness = if($afterCne.Request -eq 'null'){'NO_CNE_REQUEST'}else{'CURRENT_CNE_REQUEST'}
        if($coreFreshness -eq 'NO_CNE_REQUEST') { $noCneFailureCount++ }
        Log ("ATTEMPT={0} FAILED coreExit={1} cneRequest={2} satisfied={3} coreFreshness={4} noCneCount={5}" -f $attempt,$coreRc,$afterCne.Request,$afterCne.Satisfied,$coreFreshness,$noCneFailureCount)

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
    $safeA0Restored = $false
    try {
        Set-AirplaneMode $false
        Prepare-A0
        $safeA0Restored = $true
        Log 'FINAL_SAFE_A0_RESTORE=PASS'
    }
    catch {
        Log ("FINAL_SAFE_A0_RESTORE=FAIL {0}" -f $_.Exception.Message)
    }

    if($safeA0Restored -and $noCneFailureCount -eq $MaxRecoveryAttempts -and $noCneFailureCount -ge 2) {
        Write-Host ''
        Write-Host '============================================================'
        Write-Host ' DEEP FALLBACK: VOXI UICC APPS SOFTWARE REMOVE / INSERT'
        Write-Host '============================================================'
        Write-Host '[DEEP] Both normal attempts ended in NO_CNE_REQUEST. The original two-attempt recovery is complete and unchanged.' -ForegroundColor Yellow
        Write-Host '[DEEP] Applying one guarded UICC Apps false -> true cycle to VOXI subId11 only.'
        Log ("DEEP_FALLBACK_TRIGGER=PASS noCneCount={0}" -f $noCneFailureCount)

        Invoke-UiccDeepFallback

        # The UICC lifecycle itself may restore IMS/WFC while airplane is OFF.
        # Either way, rebuild the desired final P state and then use the same
        # unchanged v2.6.2 core once more if WFC is still unhealthy.
        if(Test-WfcHealthy) {
            Log 'DEEP_UICC_RESULT=HEALTHY_IN_A'
        }
        else {
            Prepare-A0
        }

        $deepPGate = Prepare-P

        if(Test-WfcHealthy) {
            Log 'DEEP_FALLBACK=SUCCESS_BEFORE_CORE'
            Log 'FINAL=WFC_HEALTHY_FREEZE'
            $script:WfcResult='HEALTHY'
            Write-Host '[OK] DEEP FALLBACK RESULT: WFC HEALTHY after UICC lifecycle.' -ForegroundColor Green
            Write-TotalTiming
            exit 0
        }

        if($deepPGate) {
            $deepCoreStartedAt = Get-Date
            $deepCoreRc = Invoke-V262Core

            if(Test-WfcHealthy) {
                Log ("DEEP_FALLBACK=SUCCESS_AFTER_CORE coreExit={0}" -f $deepCoreRc)
                Log 'FINAL=WFC_HEALTHY_FREEZE'
            $script:WfcResult='HEALTHY'
                Write-Host '[OK] DEEP FALLBACK RESULT: WFC HEALTHY after one final unchanged v2.6.2 cycle.' -ForegroundColor Green
                Write-TotalTiming
                exit 0
            }

            $deepAfterCne=Get-CurrentCneSnapshot
            $deepFreshness=if($deepAfterCne.Request -eq 'null'){'NO_CNE_REQUEST'}else{'CURRENT_CNE_REQUEST'}
            Log ("DEEP_FALLBACK=FAILED coreExit={0} coreFreshness={1}" -f $deepCoreRc,$deepFreshness)
        }
        else {
            Log 'DEEP_FALLBACK=BLOCKED_BY_DIRTY_P_CNE'
        }

        Write-Host '[DEEP] UICC fallback did not recover WFC. Restoring airplane-OFF A0.' -ForegroundColor Yellow
        try {
            Set-AirplaneMode $false
            Prepare-A0
            Log 'DEEP_FINAL_SAFE_A0_RESTORE=PASS'
        }
        catch {
            Log ("DEEP_FINAL_SAFE_A0_RESTORE=FAIL {0}" -f $_.Exception.Message)
        }
    }

    $script:WfcResult='NOT_RECOVERED'
    Log 'FINAL=WFC_NOT_RECOVERED'
    Write-Host '[FAIL] WFC was not recovered within the bounded attempts and guarded deep fallback.' -ForegroundColor Red
    Write-TotalTiming
    exit 20
}
catch {
    $script:WfcResult='ABORTED'
    Log ("FATAL={0}" -f $_.Exception.Message)
    Write-Host ''
    Write-Host ('[STOP] ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No further automatic recovery action will be attempted.' -ForegroundColor Yellow
    Write-TotalTiming
    exit 30
}
