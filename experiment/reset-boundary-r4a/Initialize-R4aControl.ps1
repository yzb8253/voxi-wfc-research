[CmdletBinding()]
param([switch]$Execute,[switch]$StaticAudit,[switch]$ResumeAfterReboot)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Base=Join-Path $Repo 'experiment\reset-boundary-r3\Initialize-R3ControlA0.ps1'
$RunRoot=Join-Path $PSScriptRoot 'runs\r4a_3cycle_v1\snapshots'
$HostRoot=Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\reset_boundary_r4a\r4a_3cycle_v1'
$args=@('-RunName','r4a_3cycle_v1','-ControlLabel','CONTROL_A0_R4A','-HostRootOverride',$HostRoot,'-SummaryRootOverride',$RunRoot,'-MarkerFileName','CONTROL_A0_R4A_REBOOT_USED.marker')
if($Execute){$args+='-Execute'}
if($StaticAudit){$args+='-StaticAudit'}
if($ResumeAfterReboot){$args+='-ResumeAfterReboot'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Base @args
exit $LASTEXITCODE

