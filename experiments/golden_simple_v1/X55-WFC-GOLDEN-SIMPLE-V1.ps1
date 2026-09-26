[CmdletBinding()]
param([string]$Serial='fd0ff892')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Base=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run'
$Preflight=Join-Path $Base 'repeatability_preflight.ps1'
$UiccHelper=Join-Path $PSScriptRoot 'uicc_apps_single_sim_prime.ps1'
$CneProjection=Join-Path $Repo 'experiments\wfc_repeatability_normalization\lightweight_profiling\current_cne_projection_v12h_r2.ps1'
$Contract=Join-Path $PSScriptRoot 'golden_simple_contract.ps1'
$WfcCtl='/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$LogDir=Join-Path $PSScriptRoot 'Golden-Simple-Logs'
$LogFile=Join-Path $LogDir ('GOLDEN-SIMPLE-V1-{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$ExpectedDevice='cas'
$ExpectedAndroid='13'
$ExpectedBuild='V816.0.4.0.TJJCNXM'
$ExpectedFingerprint='Xiaomi/cas/cas:13/TKQ1.221114.001/V816.0.4.0.TJJCNXM:user/release-keys'
$SimPowerTransaction=182
$CneFreshWaitMax=45
$WfcWaitMax=45
$PReadyMax=45

. $CneProjection
. $Contract

$script:PhoneWrites=New-Object System.Collections.Generic.List[string]
$script:SimMayBeOff=$false
$script:FinalResult='NOT_COMPLETED'
$script:NormalizationUsed='NO'
$script:LegacyResidue='NO'
$script:A0Ready='NO'
$script:UiccFalseSent='NO'
$script:F8Confirmed='NO'
$script:F8LatencyMs='UNOBSERVABLE'
$script:UiccTrueSent='NO'
$script:UiccReinsert='NO'
$script:UiccReinsertLatencyMs='UNOBSERVABLE'
$script:CneBaseline='UNOBSERVABLE'
$script:FreshCne='null'
$script:CneTriggerLatencyMs='UNOBSERVABLE'
$script:ImsRegistered='NO'
$script:ImsTransport='UNKNOWN'
$script:AirplaneOnTime='NOT_EXECUTED'
$script:PReadyTime='NOT_REACHED'
$script:SimCycleCount=0
$script:SimOffHoldMs='NOT_EXECUTED'
$script:SimOnTime='NOT_EXECUTED'
$script:PostSimFreshCne='null'
$script:PostSimIms='NO'
$script:WfcHealthy='NO'
$script:Total=[Diagnostics.Stopwatch]::StartNew()
$script:UiccTrueAt=$null
$script:TypedDisableReturn='NOT_EXECUTED';$script:TypedEnableReturn='NOT_EXECUTED';$script:TypedEmergency='NO'

New-Item -ItemType Directory -Force -Path $LogDir|Out-Null

function Log([string]$Message){$line='[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss.fff'),$Message;Write-Host $line;Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
    $i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true
    $i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
    $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})-join ' ')
    $p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'Unable to start adb.exe'}
    $o=$p.StandardOutput.ReadToEnd();$e=$p.StandardError.ReadToEnd();$p.WaitForExit()
    [pscustomobject]@{ExitCode=$p.ExitCode;Text=($o+$e).Trim()}
}
function RootResult([string]$Command){Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))}
function Root([string]$Command){$r=RootResult $Command;if($r.ExitCode -ne 0){throw "ADB/root command failed: $Command`n$($r.Text)"};$r.Text.Trim()}
function Add-PhoneWrite([string]$Name){$script:PhoneWrites.Add($Name);Log ("PHONE_WRITE={0}" -f $Name)}
function Get-StatusJson {
    $r=RootResult "$WfcCtl status-json";Require ($r.ExitCode -eq 0) 'wfcctl status-json failed'
    $line=@($r.Text -split "\r?\n"|Where-Object{$_.Trim().StartsWith('{')})|Select-Object -Last 1
    Require (-not [string]::IsNullOrWhiteSpace($line)) 'wfcctl status-json returned no JSON'
    $line|ConvertFrom-Json
}
function Get-StatusText {
    $r=RootResult "$WfcCtl status";Require (-not [string]::IsNullOrWhiteSpace($r.Text)) 'wfcctl status returned no text';$r.Text
}
function Get-CurrentCne {
    $r=RootResult 'dumpsys connectivity';Require ($r.ExitCode -eq 0 -and $r.Text) 'connectivity current table unavailable'
    $p=Get-CurrentCneProjection -ConnectivityText $r.Text -SubId 11
    Require ([bool]$p.valid) 'connectivity current-table boundary missing; fail closed'
    [pscustomobject]@{Request=$p.requestId;Satisfied=$p.satisfiedId}
}
function Assert-Mapping {
    $isub=Root 'dumpsys isub'
    $simState=Root 'getprop gsm.sim.state'
    Require (Test-GoldenSimpleSlot0Absent -IsubText $isub -SimState $simState) 'slot0 physical ABSENT gate failed'
    Require (Test-GoldenSimpleVoxiEnabled -IsubText $isub) 'VOXI subId11/slot1 enabled gate failed'
}
function Assert-Platform {
    Require (Test-Path -LiteralPath $Adb) "adb.exe missing: $Adb"
    foreach($path in @($Preflight,$UiccHelper,$CneProjection,$Contract)){Require (Test-Path -LiteralPath $path) "required file missing: $path"}
    $devices=Invoke-Adb @('devices');Require ($devices.Text -match "(?m)^$([regex]::Escape($Serial))\s+device\s*$") 'target ADB device is not online'
    Require ((Root 'id') -match 'uid=0\(root\)') 'root unavailable'
    Require ((Root 'getprop ro.product.device') -eq $ExpectedDevice) 'device mismatch'
    Require ((Root 'getprop ro.build.version.release') -eq $ExpectedAndroid) 'Android mismatch'
    Require ((Root 'getprop ro.build.version.incremental') -eq $ExpectedBuild) 'ROM build mismatch'
    Require ((Root 'getprop ro.build.fingerprint') -eq $ExpectedFingerprint) 'ROM fingerprint mismatch'
    Require ((Root 'settings get global airplane_mode_on') -eq '0') 'ENTRY must be airplane OFF'
    Assert-Mapping
}
function Ensure-WifiAndNetwork {
    $wifi=(Root 'settings get global wifi_on').Trim()
    if($wifi -eq '0'){
        $r=RootResult 'svc wifi enable';Require ($r.ExitCode -eq 0) 'Wi-Fi enable failed';Add-PhoneWrite 'SVC_WIFI_ENABLE'
        for($i=0;$i -lt 20;$i++){Start-Sleep -Milliseconds 500;if((Root 'settings get global wifi_on').Trim() -ne '0'){break}}
    }
    Require ((Root 'settings get global wifi_on').Trim() -ne '0') 'Wi-Fi is not enabled'
    $networkReady=$false
    for($i=0;$i -lt 30;$i++){
        $wlan=RootResult 'ip link show wlan0';$tun=RootResult 'ip link show tun0';$routes=RootResult 'ip route show table all';$conn=RootResult 'dumpsys connectivity'
        $networkReady=($wlan.ExitCode -eq 0 -and $wlan.Text -match '<[^>]*UP' -and
            $tun.ExitCode -eq 0 -and $tun.Text -match '<[^>]*UP' -and
            (Test-GoldenSimpleTun0DefaultRoute -RouteText $routes.Text) -and
            $conn.Text -match 'VPN CONNECTED' -and $conn.Text -match 'Transports:\s*WIFI\|VPN')
        if($networkReady){break}
        Start-Sleep -Seconds 1
    }
    Require $networkReady 'Wi-Fi/VPN/TUN prerequisites did not become ready within 30s'
    Log 'NETWORK_PREREQUISITES=PASS wifi=READY vpn_tun=READY'
}
function Invoke-Preflight {
    Write-Host '[1/6] Cleaning previous state / preparing clean A0'
    $lines=New-Object System.Collections.Generic.List[string]
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Preflight -Serial $Serial -ApplyNormalization 2>&1 | ForEach-Object {$v=[string]$_;$lines.Add($v);Log ("PREFLIGHT $v")}
    $rc=$LASTEXITCODE;Require ($rc -eq 0) "legacy preflight failed exit=$rc"
    $text=$lines -join "`n"
    if($text -match 'PREFLIGHT_RESULT=A0_NORMALIZED'){$script:NormalizationUsed='YES';$script:LegacyResidue='YES';Add-PhoneWrite 'LEGACY_RESIDUE_NORMALIZATION_EXISTING_AUDITED_SUBFLOW'}
    elseif($text -match 'PREFLIGHT_RESULT=A0_READY'){$script:NormalizationUsed='NO';$script:LegacyResidue='NO'}
    else{throw 'preflight did not produce clean airplane-OFF A0'}
    Require ((Root 'settings get global airplane_mode_on') -eq '0') 'preflight exited outside airplane-OFF A0'
    Assert-Mapping
    $script:A0Ready='YES';Log 'A0_READY=YES'
}
function Invoke-UiccPrime {
    Write-Host '[2/6] Rebuilding audited UICC lifecycle'
    $lines=New-Object System.Collections.Generic.List[string]
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $UiccHelper -Serial $Serial 2>&1 | ForEach-Object {
        $v=[string]$_;$lines.Add($v);Log ("UICC $v")
        if($v -match '^TYPED_HELPER_DEPLOYED='){Add-PhoneWrite 'ADB_PUSH_TYPED_ISUB_HELPER_JAR'}
        if($v -match '^TYPED_DISABLE_RETURN=(.*)$'){$script:TypedDisableReturn=$Matches[1]}
        if($v -match '^TYPED_ENABLE_RETURN=(.*)$'){$script:TypedEnableReturn=$Matches[1]}
        if($v -match '^TYPED_EMERGENCY_ENABLE=YES'){$script:TypedEmergency='YES'}
        if($v -match '^UICC_APPS_FALSE_CALL='){$script:UiccFalseSent='YES';Add-PhoneWrite 'TYPED_ISUB_FALSE_SUB11'}
        if($v -match '^UICC_F8_CONFIRMED_AFTER_MS=(\d+)'){$script:F8Confirmed='YES';$script:F8LatencyMs=[int64]$Matches[1]}
        if($v -match '^UICC_APPS_TRUE_CALL='){$script:UiccTrueSent='YES';$script:UiccTrueAt=Get-Date;Add-PhoneWrite 'TYPED_ISUB_TRUE_SUB11'}
        if($v -match '^UICC_REINSERT_CONFIRMED_AFTER_MS=(\d+)'){$script:UiccReinsert='YES';$script:UiccReinsertLatencyMs=[int64]$Matches[1]}
        if($v -match '^\[UICC GUARD\]') {Add-PhoneWrite 'TYPED_ISUB_TRUE_SUB11_EMERGENCY'}
    }
    $rc=$LASTEXITCODE;Require ($rc -eq 0) "audited UICC helper failed exit=$rc"
    Require ($script:UiccFalseSent -eq 'YES' -and $script:F8Confirmed -eq 'YES' -and $script:UiccTrueSent -eq 'YES' -and $script:UiccReinsert -eq 'YES') 'UICC lifecycle evidence incomplete'
    Assert-Mapping
}
function Set-AirplaneOn {
    if((Root 'settings get global airplane_mode_on') -ne '1'){
        $r=RootResult 'cmd connectivity airplane-mode enable';Require ($r.ExitCode -eq 0) 'airplane ON command failed';Add-PhoneWrite 'AIRPLANE_MODE_ENABLE'
    }
    for($i=0;$i -lt 20;$i++){if((Root 'settings get global airplane_mode_on') -eq '1'){break};Start-Sleep -Milliseconds 500}
    Require ((Root 'settings get global airplane_mode_on') -eq '1') 'airplane mode did not become ON'
    $script:AirplaneOnTime=(Get-Date).ToString('o');Log ("AIRPLANE_ON_TIME={0}" -f $script:AirplaneOnTime)
}
function Wait-PReady {
    Write-Host '[3/6] Entering airplane/Wi-Fi WFC environment'
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while($sw.Elapsed.TotalSeconds -lt $PReadyMax){
        $status=Get-StatusJson
        if(Test-GoldenSimplePPredecessor -Status $status){Assert-Mapping;$script:PReadyTime=(Get-Date).ToString('o');Log ("P_READY_TIME={0} latency_ms={1}" -f $script:PReadyTime,$sw.ElapsedMilliseconds);return}
        Start-Sleep -Seconds 1
    }
    throw 'P predecessor did not become ready within 45s'
}
function Observe-CneAndWfc {
    param([AllowNull()][object]$Baseline,[int]$CneSeconds,[int]$HealthSeconds,[string]$Phase)
    $fresh=$null;$cneSw=[Diagnostics.Stopwatch]::StartNew()
    while($cneSw.Elapsed.TotalSeconds -lt $CneSeconds){
        $cne=Get-CurrentCne;$status=Get-StatusJson
        $req=if($null -eq $cne.Request){'null'}else{[string]$cne.Request};$sat=if($null -eq $cne.Satisfied){'null'}else{[string]$cne.Satisfied}
        Log ("CNE_WAIT phase={0} elapsed={1}s request={2} satisfied={3}" -f $Phase,[int]$cneSw.Elapsed.TotalSeconds,$req,$sat)
        if(Test-GoldenSimpleFreshCne -Baseline $Baseline -Current $cne.Request){
            $fresh=$cne.Request
            if($Phase -eq 'POST_SIM'){$script:PostSimFreshCne=[string]$fresh}else{$script:FreshCne=[string]$fresh}
            if($script:FreshCne -eq 'null'){$script:FreshCne=[string]$fresh}
            if($script:CneTriggerLatencyMs -eq 'UNOBSERVABLE'){
                if($script:UiccTrueAt){$script:CneTriggerLatencyMs=[int64]((Get-Date)-$script:UiccTrueAt).TotalMilliseconds}else{$script:CneTriggerLatencyMs=$cneSw.ElapsedMilliseconds}
            }
            Log ("CNE_READY phase={0} request={1} phase_latency_ms={2} uicc_true_latency_ms={3}" -f $Phase,$fresh,$cneSw.ElapsedMilliseconds,$script:CneTriggerLatencyMs);break
        }
        Start-Sleep -Seconds 1
    }
    if($null -eq $fresh){return $false}
    Write-Host ("[OK] Fresh CNE request {0} detected" -f $fresh)
    Write-Host '[5/6] Waiting for IMS / WFC'
    $healthSw=[Diagnostics.Stopwatch]::StartNew()
    while($healthSw.Elapsed.TotalSeconds -lt $HealthSeconds){
        $text=Get-StatusText
        if($text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$'){$script:ImsRegistered='YES';$script:ImsTransport=if($text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$'){'WLAN'}else{'OTHER'}}
        if(Test-GoldenSimpleStrictHealthText -Text $text){$script:WfcHealthy='YES';if($Phase -eq 'POST_SIM'){$script:PostSimIms='YES'};Log 'IMS_READY=YES transport=WLAN';Log 'WFC_READY=YES';return $true}
        Start-Sleep -Seconds 1
    }
    $false
}
function Invoke-OneSimCycle {
    Write-Host '[4/6] Cycling SIM2 once'
    Assert-Mapping
    $script:SimCycleCount=1
    $off=RootResult "service call phone $SimPowerTransaction i32 1 i32 0";Require ($off.ExitCode -eq 0) 'SIM2 POWER OFF failed'
    $script:SimMayBeOff=$true;Add-PhoneWrite 'SIM2_POWER_OFF_SLOT1'
    $hold=[Diagnostics.Stopwatch]::StartNew();Start-Sleep -Seconds 3;$hold.Stop();$script:SimOffHoldMs=$hold.ElapsedMilliseconds
    $on=RootResult "service call phone $SimPowerTransaction i32 1 i32 1";Require ($on.ExitCode -eq 0) 'SIM2 POWER ON failed'
    $script:SimMayBeOff=$false;$script:SimOnTime=(Get-Date).ToString('o');Add-PhoneWrite 'SIM2_POWER_ON_SLOT1'
    Log ("SIM_OFF_HOLD_MS={0}" -f $script:SimOffHoldMs);Log ("SIM_ON_TIME={0}" -f $script:SimOnTime)
}
function Write-Summary {
    if($script:Total.IsRunning){$script:Total.Stop()}
    Log ("ENTRY_AIRPLANE=OFF");Log ("LEGACY_RESIDUE={0}" -f $script:LegacyResidue);Log ("NORMALIZATION_USED={0}" -f $script:NormalizationUsed);Log ("A0_READY={0}" -f $script:A0Ready)
    Log ("UICC_FALSE_SENT={0}" -f $script:UiccFalseSent);Log ("F8_CONFIRMED={0}" -f $script:F8Confirmed);Log ("F8_LATENCY_MS={0}" -f $script:F8LatencyMs)
    Log ("UICC_TRUE_SENT={0}" -f $script:UiccTrueSent);Log ("UICC_REINSERT_CONFIRMED={0}" -f $script:UiccReinsert);Log ("UICC_REINSERT_LATENCY_MS={0}" -f $script:UiccReinsertLatencyMs)
    Log 'UICC_WRITE_TRANSPORT=TYPED_ISUB_APP_PROCESS';Log ("TYPED_DISABLE_RETURN={0}" -f $script:TypedDisableReturn);Log ("TYPED_ENABLE_RETURN={0}" -f $script:TypedEnableReturn);Log ("TYPED_EMERGENCY_ENABLE={0}" -f $script:TypedEmergency)
    Log ("CNE_BASELINE_REQUEST={0}" -f $script:CneBaseline);Log ("FRESH_CNE_REQUEST={0}" -f $script:FreshCne);Log ("CNE_TRIGGER_LATENCY_MS={0}" -f $script:CneTriggerLatencyMs)
    Log ("IMS_REGISTERED={0}" -f $script:ImsRegistered);Log ("IMS_TRANSPORT={0}" -f $script:ImsTransport);Log ("AIRPLANE_ON_TIME={0}" -f $script:AirplaneOnTime);Log ("P_READY_TIME={0}" -f $script:PReadyTime)
    Log ("SIM_CYCLE_COUNT={0}" -f $script:SimCycleCount);Log ("SIM_OFF_HOLD_MS={0}" -f $script:SimOffHoldMs);Log ("SIM_ON_TIME={0}" -f $script:SimOnTime)
    Log ("POST_SIM_FRESH_CNE={0}" -f $script:PostSimFreshCne);Log ("POST_SIM_IMS={0}" -f $script:PostSimIms);Log ("WFC_HEALTHY={0}" -f $script:WfcHealthy)
    Log ("TOTAL_END_TO_END_MS={0}" -f $script:Total.ElapsedMilliseconds);Log ("FINAL_RESULT={0}" -f $script:FinalResult)
    Log ("PHONE_WRITE_COUNT={0}" -f $script:PhoneWrites.Count);Log ("PHONE_WRITE_LIST={0}" -f $(if($script:PhoneWrites.Count){$script:PhoneWrites -join ','}else{'NONE'}))
}

try {
    Log 'MODE=GOLDEN_SIMPLE_V1'
    Assert-Platform
    Ensure-WifiAndNetwork
    Invoke-Preflight
    $before=Get-CurrentCne;$script:CneBaseline=if($null -eq $before.Request){'null'}else{[string]$before.Request};Log ("CNE_BASELINE_REQUEST={0}" -f $script:CneBaseline)
    Invoke-UiccPrime
    Set-AirplaneOn
    Ensure-WifiAndNetwork
    Wait-PReady
    Write-Host '[4/6] Observing natural fresh CNE / WFC before SIM cycle'
    if(Observe-CneAndWfc -Baseline $before.Request -CneSeconds $CneFreshWaitMax -HealthSeconds $WfcWaitMax -Phase 'POST_UICC_NATURAL'){
        $script:FinalResult='SUCCESS_NATURAL_AFTER_UICC';Write-Host '[SUCCESS] CNE -> IMS -> WFC complete';return
    }
    $preSim=Get-CurrentCne
    Invoke-OneSimCycle
    if(Observe-CneAndWfc -Baseline $preSim.Request -CneSeconds $CneFreshWaitMax -HealthSeconds $WfcWaitMax -Phase 'POST_SIM'){
        $script:FinalResult='SUCCESS_AFTER_ONE_SIM_CYCLE';Write-Host '[SUCCESS] CNE -> IMS -> WFC complete';return
    }
    $script:FinalResult='FAILED_NO_COMPLETE_CNE_IMS_WFC_CHAIN';throw 'fresh CNE -> strict IMS/WFC chain did not complete'
}
catch {
    if($script:FinalResult -eq 'NOT_COMPLETED'){$script:FinalResult='ERROR_FAIL_CLOSED'}
    Log ("ERROR={0}" -f $_.Exception.Message);Write-Host ("[FAIL] {0}" -f $_.Exception.Message) -ForegroundColor Red
}
finally {
    if($script:SimMayBeOff){
        Log 'SIM_GUARD sending one emergency POWER ON';[void](RootResult "service call phone $SimPowerTransaction i32 1 i32 1");$script:SimMayBeOff=$false;Add-PhoneWrite 'SIM2_POWER_ON_EMERGENCY_GUARD'
    }
    Write-Summary
}

if($script:FinalResult -like 'SUCCESS*'){exit 0}else{exit 1}
