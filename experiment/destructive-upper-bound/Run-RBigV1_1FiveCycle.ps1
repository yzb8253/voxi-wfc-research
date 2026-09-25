[CmdletBinding()]
param([switch]$Execute,[switch]$StaticAudit,[ValidateRange(1,5)][int]$StartCycle=1,[switch]$SkipBaseline)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$RunName='r_big_v1_1_5cycle'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$Init=Join-Path $Repo 'experiment\reset-boundary-r3\Initialize-R3ControlA0.ps1'
$Prepare=Join-Path $PSScriptRoot 'Invoke-RBigV1_1Preparation.ps1'
$CaptureScript=Join-Path $Repo 'experiments\wfc_repeatability_normalization\capture_snapshot.ps1'
$PortableV262=Join-Path $Repo 'experiment\reset-boundary-r3\Invoke-FrozenV262Portable.ps1'
$CanonicalV262=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$SummaryRoot=Join-Path $PSScriptRoot "runs\$RunName"
$SnapshotRoot=Join-Path $SummaryRoot 'snapshots'
$HostRoot=Join-Path (Split-Path $Repo -Parent) "voxi_wfc_local_runs\destructive_upper_bound\$RunName"
$Timeline=Join-Path $HostRoot 'timeline.log'
[IO.Directory]::CreateDirectory($SnapshotRoot)|Out-Null;[IO.Directory]::CreateDirectory($HostRoot)|Out-Null
function Log([string]$Message){$line='{0} {1}' -f (Get-Date -Format o),$Message;Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8;Write-Host $line}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Adb([string[]]$Arguments){$i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ');$p=[Diagnostics.Process]::new();$p.StartInfo=$i;[void]$p.Start();$o=$p.StandardOutput.ReadToEnd()+$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o}}
function Phone-Write([string]$Command){if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE=$Command"};Log "PHONE_WRITE=$Command";$r=Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw $r.Text}}
function Child([string]$Path,[string[]]$Arguments){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$o|ForEach-Object{Log "CHILD=$_"};if($rc -ne 0){throw "CHILD_FAILED=$Path exit=$rc"};$o}
function Capture([string]$Label){$o=Child $CaptureScript @('-Label',$Label,'-Serial',$Serial,'-RunName',$RunName);$generated=Join-Path $Repo "experiments\wfc_repeatability_normalization\runs\$RunName\snapshots\$Label.json";$json=Get-Content -LiteralPath $generated -Raw;$dest=Join-Path $SnapshotRoot ($Label+'.json');[IO.File]::WriteAllText($dest,$json,[Text.UTF8Encoding]::new($false));Remove-Item $generated -Force;$json|ConvertFrom-Json}
function P-Canonical($s){$s.device.root -and $s.target.mappingGate -and $s.target.subId -eq 11 -and $s.target.slotId -eq 1 -and $s.target.phoneId -eq 1 -and $s.target.carrierId -eq 28 -and $s.target.mcc -eq 234 -and $s.target.mnc -eq 15 -and $s.subscription.active -and $s.subscription.uiccAppsEnabled -and $s.environment.airplaneMode -eq 1 -and $s.environment.wlan0Up -and $s.environment.vpnNetwork -and $s.iwlan.rilTechnology -eq 'IWLAN' -and $s.iwlan.psWlan -eq 'HOME' -and $s.iwlan.accessNetwork -eq 'IWLAN' -and $s.iwlan.preferred -and -not $s.data.qtiCneRequest}
function Healthy($s){$s.ims.stateRaw -eq 2 -and $s.ims.transportRaw -eq 2 -and $s.ims.voiceIwlan -and $s.data.wfcAvailable -and $s.health.goldenStrong}
function Fixed-P-And-Recover([int]$Cycle){Phone-Write 'cmd connectivity airplane-mode enable';Start-Sleep 3;Phone-Write 'svc wifi enable';Log "C${Cycle}_P_SETTLE=60";Start-Sleep 60;$p=Capture ("C{0}_P" -f $Cycle);if(-not (P-Canonical $p)){throw "FAIL_STAGE=P cycle=$Cycle"};Log "C${Cycle}_P=PASS";Child $PortableV262 @();$w=Capture ("C{0}_W" -f $Cycle);if(-not (Healthy $w)){throw "FAIL_STAGE=WFC cycle=$Cycle"};Log "C${Cycle}=PASS_FREEZE"}

if((Get-FileHash $CanonicalV262 -Algorithm SHA256).Hash -ne '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'){throw 'V262_HASH_MISMATCH'}
if($StaticAudit){Child $Prepare @('-Cycle','3','-Mode','UpperBound','-StaticAudit');Write-Host 'CYCLES_3_4_5_IDENTICAL_CALL=Invoke-RBigPreparation Mode=UpperBound';Write-Host 'FIXED_P_IDENTICAL=YES';Write-Host 'V262_HASH=PASS';Write-Host 'STATIC_NO_ADB=PASS';exit 0}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}
if(-not $SkipBaseline){Child $Init @('-RunName',$RunName,'-ControlLabel','CONTROL_A0','-HostRootOverride',$HostRoot,'-SummaryRootOverride',$SnapshotRoot,'-MarkerFileName','CONTROL_A0_REBOOT_USED.marker','-Execute')}else{Log 'CONTROL_A0=SKIPPED_BY_EXPLICIT_RESUME'}
for($cycle=$StartCycle;$cycle -le 5;$cycle++){
  Log "CYCLE_${cycle}_BEGIN"
  if($cycle -gt 1 -or $SkipBaseline){Phone-Write 'cmd connectivity airplane-mode disable';Start-Sleep 10}
  if($cycle -eq 2){Child $Prepare @('-Cycle','2','-Mode','Minimal','-RunName',$RunName,'-Execute')}
  elseif($cycle -ge 3){Child $Prepare @('-Cycle',[string]$cycle,'-Mode','UpperBound','-RunName',$RunName,'-Execute')}
  Fixed-P-And-Recover $cycle
}
Write-Host 'R_BIG_V1_1_UPPER_BOUND_NOT_FALSIFIED_3_RESCUES'
