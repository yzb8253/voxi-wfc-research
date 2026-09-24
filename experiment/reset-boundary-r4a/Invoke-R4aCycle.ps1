[CmdletBinding()]
param([ValidateRange(1,3)][int]$Cycle=1,[switch]$Execute,[switch]$StaticAudit,[string]$RunName='r4a_3cycle_v1')

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RunRoot=Join-Path $PSScriptRoot ("runs\{0}" -f $RunName)
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4a\{0}" -f $RunName)
$R3=Join-Path $Repo 'experiment\reset-boundary-r3\Prepare-R3Cycle.ps1'
$Producer=Join-Path $PSScriptRoot 'Invoke-Qcrild2ColdEpoch.ps1'
$Pipeline=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v263_state_machine\X55-WFC-OneClick-v2.6.3-repeatable-state-machine.ps1'
[IO.Directory]::CreateDirectory($RunRoot)|Out-Null
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null

function Run([string]$Path,[string[]]$Arguments){$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$o|ForEach-Object{Write-Host $_};if($rc -ne 0){throw "CHILD_FAILED=$Path exit=$rc"}}

if($StaticAudit){
  Run $R3 @('-StaticAudit')
  Run $Producer @('-StaticAudit')
  $hash=(Get-FileHash (Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1') -Algorithm SHA256).Hash
  if($hash -ne '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'){throw "V262_HASH_MISMATCH=$hash"}
  Write-Host 'R4A_ORDER=R0_NATIVE_READY>QCRILD2_COLD_EPOCH>PRODUCER_READY>R3>A_READY>P>V262'
  Write-Host 'STATE_MACHINE_STATIC_AUDIT=PASS'
  Write-Host 'PHONE_WRITES=0'
  exit 0
}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}

$common=@('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName,'-SummaryRootOverride',$RunRoot,'-HostRootOverride',$HostRoot)
Run $R3 ($common+@('-StopAfterR0','-LabelPrefix','R4A_R0'))
Run $Producer @('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName)
Run $R3 ($common+@('-LabelPrefix','R4A'))
Run $Pipeline @('-Cycle',[string]$Cycle,'-Execute','-RunName',$RunName)
Write-Host "R4A_CYCLE=$Cycle"
Write-Host 'R4A_CYCLE_RESULT=PASS'
