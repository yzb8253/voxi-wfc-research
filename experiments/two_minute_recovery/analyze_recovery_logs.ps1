[CmdletBinding()]
param(
    [string]$RunRoot='',
    [string]$OutputCsv='',
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($RunRoot)){$RunRoot=Join-Path $PSScriptRoot '..\wfc_repeatability_normalization\v262_freeze_run'}

function Last-Match([string]$Text,[string]$Pattern,[string]$Default='UNKNOWN') {
    $m=@([regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Multiline))
    if($m.Count -eq 0){return $Default}
    $m[$m.Count-1].Groups[1].Value
}

function First-Match([string]$Text,[string]$Pattern,[string]$Default='UNKNOWN') {
    $m=[regex]::Match($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Multiline)
    if(-not $m.Success){return $Default}
    $m.Groups[1].Value
}

function Parse-Clock([string]$Date,[string]$Line) {
    if($Line -notmatch '^\[(\d{2}:\d{2}:\d{2}\.\d{3})\]'){return $null}
    [datetime]::ParseExact("$Date $($Matches[1])",'yyyyMMdd HH:mm:ss.fff',[Globalization.CultureInfo]::InvariantCulture)
}

function Millis-From([datetime]$Origin,[object]$Point) {
    if($null -eq $Point){return 'UNOBSERVABLE'}
    [math]::Round(([datetime]$Point-$Origin).TotalMilliseconds)
}

function Get-ProbeTimeline([string[]]$Lines,[string]$Date,[datetime]$SimOn) {
    $ims='UNKNOWN';$transport='UNKNOWN';$voice='UNKNOWN';$wfc='UNKNOWN'
    $cneRegistered='UNKNOWN';$cneActive='UNKNOWN';$request='UNKNOWN';$satisfied='UNKNOWN'
    $agent='UNKNOWN';$epdg='UNKNOWN';$xfrm='UNKNOWN';$mmtel='UNKNOWN'
    $samples=New-Object 'System.Collections.Generic.List[object]'
    foreach($line in $Lines) {
        if($line -match '^IMS:\s+(.+)$'){$ims=$Matches[1].Trim()}
        elseif($line -match '^Transport:\s+(.+)$'){$transport=$Matches[1].Trim()}
        elseif($line -match '^VOICE/IWLAN:\s+(.+)$'){$voice=$Matches[1].Trim()}
        elseif($line -match '^WFC:\s+(.+)$'){$wfc=$Matches[1].Trim()}
        elseif($line -match '^IMS NetworkAgent:\s+(.+)$'){$agent=$Matches[1].Trim()}
        elseif($line -match '^qti\.cne:\s+registered=(\S+)\s+active=(\S+)\s+request=(\S+)\s+satisfied=(\S+)'){
            $cneRegistered=$Matches[1];$cneActive=$Matches[2];$request=$Matches[3];$satisfied=$Matches[4]
        }
        elseif($line -match '^ePDG UDP/4500:\s+(.+)$'){$epdg=$Matches[1].Trim()}
        elseif($line -match '^XFRM:\s+(.+)$'){$xfrm=$Matches[1].Trim()}
        elseif($line -match '^MMTEL:\s+(.+)$'){$mmtel=$Matches[1].Trim()}
        elseif($line -match 'HEALTH after_sim_cycle_1_\d+:'){
            $t=Parse-Clock $Date $line
            if($null -ne $t -and $t -ge $SimOn){
                $samples.Add([pscustomobject]@{Time=$t;ElapsedMs=[math]::Round(($t-$SimOn).TotalMilliseconds);Ims=$ims;Transport=$transport;VoiceIwlan=$voice;Wfc=$wfc;CneRegistered=$cneRegistered;CneActive=$cneActive;Request=$request;Satisfied=$satisfied;Agent=$agent;Epdg=$epdg;Xfrm=$xfrm;Mmtel=$mmtel})
            }
        }
    }
    $samples.ToArray()
}

$abDir=Join-Path $RunRoot 'Holder-AB-Logs'
$x55Dir=Join-Path $RunRoot 'X55-Logs'
$aggressiveDir=Join-Path $RunRoot 'Aggressive-Conservative-Logs'
$inventory=[pscustomobject]@{
    HolderAbLogs=@(Get-ChildItem -LiteralPath $abDir -Filter '*.log' -File -ErrorAction SilentlyContinue).Count
    X55Logs=@(Get-ChildItem -LiteralPath $x55Dir -Filter '*.log' -File -ErrorAction SilentlyContinue).Count
    AggressiveFiles=@(Get-ChildItem -LiteralPath $aggressiveDir -File -ErrorAction SilentlyContinue).Count
}

$rows=New-Object 'System.Collections.Generic.List[object]'
foreach($abFile in @(Get-ChildItem -LiteralPath $abDir -Filter 'X55-WFC-AB-*.log' -File -ErrorAction SilentlyContinue|Sort-Object Name)) {
    $abText=Get-Content -LiteralPath $abFile.FullName -Raw
    $variant=Last-Match $abText '(?m)^AB_VARIANT=(OLD|FAST)$'
    $date=if($abFile.Name -match '(\d{8})_\d{6}'){$Matches[1]}else{throw "Date missing: $($abFile.Name)"}
    $coreLeaf=Last-Match $abText 'CORE_LOG=.*[\\/]([^\\/\r\n]+\.log)'
    $coreFile=Join-Path $x55Dir $coreLeaf
    if(-not (Test-Path -LiteralPath $coreFile)){continue}
    $coreText=Get-Content -LiteralPath $coreFile -Raw
    $coreLines=@(Get-Content -LiteralPath $coreFile)
    $simOnLine=@($coreLines|Where-Object{$_ -match 'SIM cycle 1: single POWER ON sent'}|Select-Object -First 1)
    if($simOnLine.Count -ne 1){continue}
    $simOn=Parse-Clock $date $simOnLine[0]
    $probes=@(Get-ProbeTimeline $coreLines $date $simOn)
    $firstCne=@($probes|Where-Object{$_.CneRegistered -eq 'YES' -or $_.Request -notin @('null','UNKNOWN')}|Select-Object -First 1)
    $firstIms=@($probes|Where-Object{$_.Ims -match '^REGISTERED'}|Select-Object -First 1)
    $firstIwlan=@($probes|Where-Object{$_.Transport -match '^WLAN' -or $_.VoiceIwlan -eq 'AVAILABLE'}|Select-Object -First 1)
    $firstWfc=@($probes|Where-Object{$_.Wfc -eq 'AVAILABLE'}|Select-Object -First 1)
    $afterPowerOnLine=@($coreLines|Where-Object{$_ -match 'SIM2 lifecycle snapshot: after_power_on_1'}|Select-Object -First 1)
    $uiccUpper=if($afterPowerOnLine.Count -eq 1 -and $coreText -match 'ABSENT,READY') {Parse-Clock $date $afterPowerOnLine[0]} else {$null}
    $cleanupStartLine=@($coreLines|Where-Object{$_ -match 'CLEANUP_START'}|Select-Object -First 1)
    $cleanupEndLine=@($coreLines|Where-Object{$_ -match 'CLEANUP_RESULT='}|Select-Object -Last 1)
    $cleanupMs='NOT_EXECUTED'
    if($cleanupStartLine.Count -eq 1 -and $cleanupEndLine.Count -eq 1){
        $cs=Parse-Clock $date $cleanupStartLine[0];$ce=Parse-Clock $date $cleanupEndLine[0]
        if($null -ne $cs -and $null -ne $ce){$cleanupMs=[math]::Round(($ce-$cs).TotalMilliseconds)}
    }
    $rows.Add([pscustomobject]@{
        Variant=$variant
        StartTime=First-Match $abText '^\[(\d{2}:\d{2}:\d{2}\.\d{3})\] AB_VARIANT='
        Result=Last-Match $abText '(?m)^\[[^]]+\] RECOVERY_RESULT=(\S+)'
        FailureClass=Last-Match $abText '(?m)^\[[^]]+\] FAILURE_CLASS=(\S+)' 'NONE'
        InitialCrashCount=Last-Match $abText '(?m)^\[[^]]+\] PRE_SHUTDOWN_CRASH_COUNT=(\S+)'
        X55OfflineMs=Last-Match $coreText 'TIMING name=core_x55_offline ms=(\d+)'
        HolderOnlineMs=Last-Match $coreText 'TIMING name=core_holder_start_to_x55_online ms=(\d+)'
        PonSuccessMs=Last-Match $coreText 'TIMING name=core_pon_success ms=(\d+)'
        SimOffRequestMs=Last-Match $coreText 'TIMING name=core_sim2_power_off_request ms=(\d+)'
        SimOffHoldMs=Last-Match $coreText 'TIMING name=core_sim2_off_hold ms=(\d+)'
        SimOnRequestMs=Last-Match $coreText 'TIMING name=core_sim2_power_on_request ms=(\d+)'
        UiccReadyUpperBoundMs=Millis-From $simOn $uiccUpper
        FirstCneRegisteredMs=if($firstCne.Count){$firstCne[0].ElapsedMs}else{'UNOBSERVABLE'}
        FirstCneRequest=if($firstCne.Count){$firstCne[0].Request}else{'UNOBSERVABLE'}
        FirstImsRegisteredMs=if($firstIms.Count){$firstIms[0].ElapsedMs}else{'UNOBSERVABLE'}
        FirstIwlanAvailableMs=if($firstIwlan.Count){$firstIwlan[0].ElapsedMs}else{'UNOBSERVABLE'}
        WfcHealthyMs=if($firstWfc.Count){$firstWfc[0].ElapsedMs}else{'UNOBSERVABLE'}
        CoreTotalMs=Last-Match $abText 'CORE_TOTAL_MS=(\d+)'
        WrapperTotalMs=Last-Match $abText 'TOTAL_RECOVERY_MS=(\d+)'
        CleanupMs=$cleanupMs
        ProbeCount=$probes.Count
        Qcrild2PostSim='UNOBSERVABLE'
        OwnerPostSim='UNOBSERVABLE'
    })
}

Write-Host ("INVENTORY HolderAB={0} X55={1} Aggressive={2}" -f $inventory.HolderAbLogs,$inventory.X55Logs,$inventory.AggressiveFiles)
Write-Host ("CORRELATED_AB_SAMPLES={0}" -f $rows.Count)
$result=$rows.ToArray()
if(-not [string]::IsNullOrWhiteSpace($OutputCsv)){$result|Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8}
if($PassThru){$result}else{$result|Format-Table -AutoSize}
