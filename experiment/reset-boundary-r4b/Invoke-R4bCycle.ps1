[CmdletBinding()]
param([ValidateRange(1,3)][int]$Cycle=1,[switch]$Execute,[switch]$StaticAudit,[string]$RunName='r4b_3cycle_v1')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RunRoot=Join-Path $PSScriptRoot ("runs\{0}" -f $RunName)
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$R3=Join-Path $Repo 'experiment\reset-boundary-r3\Prepare-R3Cycle.ps1'
$Producer=Join-Path $Repo 'experiment\reset-boundary-r4a\Invoke-Qcrild2ColdEpoch.ps1'
$Provider=Join-Path $PSScriptRoot 'Invoke-QtiDataServicesColdEpoch.ps1'
$NativePublication=Join-Path $PSScriptRoot 'Wait-NativePublicationReady.ps1'
$PostR3Query=Join-Path $PSScriptRoot 'Assert-PostR3NaturalQuery.ps1'
$Observer=Join-Path $PSScriptRoot 'Capture-R4bTimeline.ps1'
$Pipeline=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v263_state_machine\X55-WFC-OneClick-v2.6.3-repeatable-state-machine.ps1'
[IO.Directory]::CreateDirectory($RunRoot)|Out-Null
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null
function Run([string]$Path,[string[]]$Arguments){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$o|ForEach-Object{Write-Host $_};if($rc -ne 0){throw "CHILD_FAILED=$Path exit=$rc"}}
function Observe([string]$Phase){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Observer -Cycle $Cycle -Phase $Phase -RunName $RunName 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$o|ForEach-Object{Write-Host $_};if($rc -ne 0){Write-Host "OBSERVATION_UNAVAILABLE phase=$Phase exit=$rc"}}

if($StaticAudit){
  Run $R3 @('-StaticAudit')
  Run $Producer @('-StaticAudit')
  Run $Provider @('-StaticAudit')
  Run $NativePublication @('-StaticAudit')
  Run $PostR3Query @('-StaticAudit')
  $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($Observer,[ref]$tokens,[ref]$errors);if($errors.Count){throw "OBSERVER_PARSE_FAIL=$($errors|Out-String)"}
  $hash=(Get-FileHash (Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1') -Algorithm SHA256).Hash
  if($hash -ne '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'){throw "V262_HASH_MISMATCH=$hash"}
  Write-Host 'R4B_ORDER=R0_NATIVE_READY>QCRILD2_COLD_EPOCH>PRODUCER_READY>QTIDATASERVICES_COLD_EPOCH>NATIVE_PUBLICATION_READY>R3>POST_R3_QUERY_READY>A_READY>P>V262'
  Write-Host 'STATE_MACHINE_STATIC_AUDIT=PASS'
  Write-Host 'PHONE_WRITES=0'
  exit 0
}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}
$common=@('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName,'-SummaryRootOverride',$RunRoot,'-HostRootOverride',$HostRoot)
Run $R3 ($common+@('-StopAfterR0','-LabelPrefix','R4B_R0'))
Run $Producer @('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName)
Run $Provider @('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName)
Run $NativePublication @('-Cycle',[string]$Cycle,'-RunName',$RunName)
Run $R3 ($common+@('-LabelPrefix','R4B'))
Run $PostR3Query @('-Cycle',[string]$Cycle,'-RunName',$RunName)
Observe 'POST_R3'
try{Run $Pipeline @('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName)}catch{Observe 'POST_PIPELINE';throw}
Observe 'POST_PIPELINE'
Write-Host "R4B_CYCLE=$Cycle"
Write-Host 'R4B_CYCLE_RESULT=PASS'
