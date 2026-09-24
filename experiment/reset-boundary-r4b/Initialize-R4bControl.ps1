[CmdletBinding()]
param([switch]$Execute,[switch]$StaticAudit,[switch]$ResumeAfterReboot,[string]$RunName='r4b_3cycle_v1',[string]$ControlLabel='CONTROL_A0_R4B_V1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Base=Join-Path $Repo 'experiment\reset-boundary-r3\Initialize-R3ControlA0.ps1'
$RunRoot=Join-Path $PSScriptRoot ("runs\{0}\snapshots" -f $RunName)
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$args=@('-RunName',$RunName,'-ControlLabel',$ControlLabel,'-HostRootOverride',$HostRoot,'-SummaryRootOverride',$RunRoot,'-MarkerFileName',($ControlLabel+'_REBOOT_USED.marker'))
if($Execute){$args+='-Execute'}
if($StaticAudit){$args+='-StaticAudit'}
if($ResumeAfterReboot){$args+='-ResumeAfterReboot'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Base @args
exit $LASTEXITCODE

