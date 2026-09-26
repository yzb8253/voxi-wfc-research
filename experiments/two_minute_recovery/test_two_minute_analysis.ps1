Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Classifier=Join-Path $PSScriptRoot 'early_fail_classifier.ps1'
$Parser=Join-Path $PSScriptRoot 'analyze_recovery_logs.ps1'
foreach($file in @($Classifier,$Parser)){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors);if(@($errors).Count){throw "PS5.1 parse failure: $file"}}
. $Classifier

$base=@{TargetMappingValid=$true;SubscriptionActive=$true;UiccEnabled=$true;Qcrild2Stable=$true;NativeStateStable=$true;MmtelReady=$true;CneRegistered='NO';CneActive='NO';CurrentRequest=$null;CurrentSatisfied=$null;ImsState='NOT_REGISTERED';Transport='UNKNOWN';VoiceIwlan=$false;WfcAvailable=$false;ImsNetworkAgent=$false;Epdg4500=$false;Xfrm=$false}
$tests=@(
    @{Name='dead_at_10s_is_not_killed';Args=@{ElapsedMs=10000};Want='INSUFFICIENT_EVIDENCE'},
    @{Name='dead_at_20s_is_suspected_only';Args=@{ElapsedMs=20000;ConsecutiveDeadSamples=2;DeadSpanMs=10000};Want='NO_CNE_SUSPECTED'},
    @{Name='dead_at_30s_without_history_is_not_confirmed';Args=@{ElapsedMs=30000};Want='INSUFFICIENT_EVIDENCE'},
    @{Name='dead_at_30s_with_three_samples_is_confirmed_candidate';Args=@{ElapsedMs=30000;ConsecutiveDeadSamples=3;DeadSpanMs=10000};Want='NO_CNE_CONFIRMED'},
    @{Name='request_at_20s_is_progress';Args=@{ElapsedMs=20000;CurrentRequest=262};Want='RECOVERY_PROGRESSING'},
    @{Name='xfrm_at_20s_is_progress';Args=@{ElapsedMs=20000;Xfrm=$true};Want='RECOVERY_PROGRESSING'},
    @{Name='mapping_error_fails_closed';Args=@{ElapsedMs=30000;TargetMappingValid=$false;ConsecutiveDeadSamples=3;DeadSpanMs=10000};Want='INSUFFICIENT_EVIDENCE'},
    @{Name='qcrild_unknown_fails_closed';Args=@{ElapsedMs=30000;Qcrild2Stable=$false;ConsecutiveDeadSamples=3;DeadSpanMs=10000};Want='INSUFFICIENT_EVIDENCE'}
)
$pass=0
foreach($test in $tests){$args=@{};foreach($k in $base.Keys){$args[$k]=$base[$k]};foreach($k in $test.Args.Keys){$args[$k]=$test.Args[$k]};$got=Get-WfcRecoveryProgressClassification @args;if($got -ne $test.Want){throw "$($test.Name): got=$got want=$($test.Want)"};$pass++;Write-Host "PASS $($test.Name)"}

$forbidden='\badb(\.exe)?\b|service call|setprop|settings put|ctl\.(start|stop|restart)|kill\s|reboot'
foreach($file in @($Classifier,$Parser)){if((Get-Content -LiteralPath $file -Raw) -match $forbidden){throw "Phone-write primitive present in offline tool: $file"}}

$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('voxi-two-minute-'+[guid]::NewGuid().ToString('N'))
try {
    foreach($dir in 'Holder-AB-Logs','X55-Logs','Aggressive-Conservative-Logs'){[IO.Directory]::CreateDirectory((Join-Path $fixtureRoot $dir))|Out-Null}
    $core=@'
[10:00:00.000] X55 + VOXI WFC one-click recovery started fixture
[10:00:01.000] PRE_SHUTDOWN_CRASH_COUNT=0
[10:00:05.000] X55 OFFLINE; CRASH_COUNT before=0 after=0 delta=0
[10:00:05.001] TIMING name=core_x55_offline ms=4000
[10:00:10.000] TEMP_HOLDER_PID=123
[10:00:11.000] X55 ONLINE; CRASH_COUNT=0 stable_from_offline=PASS
[10:00:11.001] TIMING name=core_holder_start_to_x55_online ms=5000
[10:00:11.100] TIMING name=core_pon_success ms=100
[10:00:20.100] TIMING name=core_sim2_power_off_request ms=100
[10:00:23.100] TIMING name=core_sim2_off_hold ms=3000
[10:00:23.200] TIMING name=core_sim2_power_on_request ms=100
[10:00:23.201] SIM cycle 1: single POWER ON sent; duplicate POWER ON disabled
[10:00:25.201] SIM2 lifecycle snapshot: after_power_on_1
ABSENT,READY
IMS: NOT_REGISTERED (raw 0)
Transport: UNKNOWN_-1 (raw -1)
VOICE/IWLAN: UNAVAILABLE
WFC: UNAVAILABLE
IMS NetworkAgent: MISSING (id null)
qti.cne: registered=NO active=NO request=null satisfied=null
ePDG UDP/4500: MISSING
XFRM: MISSING
MMTEL: READY
[10:00:33.201] HEALTH after_sim_cycle_1_1: ims=False transportWlan=False voiceIwlan=False wfc=False
IMS: REGISTERED (raw 2)
Transport: WLAN (raw 2)
VOICE/IWLAN: AVAILABLE
WFC: AVAILABLE
IMS NetworkAgent: PRESENT (id 103)
qti.cne: registered=YES active=YES request=262 satisfied=262
ePDG UDP/4500: PRESENT
XFRM: PRESENT
MMTEL: READY
[10:00:39.201] HEALTH after_sim_cycle_1_2: ims=True transportWlan=True voiceIwlan=True wfc=True
[10:00:40.000] TIMING name=core_total ms=40000
'@
    $ab=@'
MODE=HOLDER_AB_R2
AB_VARIANT=FAST
[10:00:00.000] AB_VARIANT=FAST
[10:00:40.000] CORE_ATTEMPT_RESULT=SUCCESS
[10:00:40.001] RECOVERY_RESULT=SIM_CYCLE_1_SUCCESS
[10:00:40.002] PRE_SHUTDOWN_CRASH_COUNT=0
[10:00:40.003] CORE_TOTAL_MS=40000
[10:00:40.004] TOTAL_RECOVERY_MS=50000
[10:00:40.005] CORE_LOG=C:\fixture\X55-Logs\X55-WFC-fixture.log
'@
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'X55-Logs\X55-WFC-fixture.log'),$core)
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'Holder-AB-Logs\X55-WFC-AB-FAST-20260926_100000.log'),$ab)
    $parsed=@(& $Parser -RunRoot $fixtureRoot -PassThru)
    if($parsed.Count -ne 1 -or $parsed[0].Variant -ne 'FAST' -or $parsed[0].FirstCneRegisteredMs -ne 16000 -or $parsed[0].WfcHealthyMs -ne 16000 -or $parsed[0].UiccReadyUpperBoundMs -ne 2000){throw 'Offline timeline parser fixture failed.'}
    Write-Host 'TIMELINE_PARSER_FIXTURES=1/1 PASS'
}
finally {if(Test-Path -LiteralPath $fixtureRoot){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}}

Write-Host ("EARLY_FAIL_FIXTURES={0}/{0} PASS" -f $pass)
Write-Host 'OFFLINE_ONLY=YES'
Write-Host 'PHONE_WRITES=0'
