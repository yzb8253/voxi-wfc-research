[CmdletBinding()]
param([switch]$Execute,[switch]$StaticAudit,[string]$RunName='r4b_3cycle_v1')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CycleScript=Join-Path $PSScriptRoot 'Invoke-R4bCycle.ps1'
$HostRoot=Join-Path (Split-Path $Repo -Parent) ("voxi_wfc_local_runs\reset_boundary_r4b\{0}" -f $RunName)
$Timeline=Join-Path $HostRoot 'series.log'
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null
function Log([string]$Message){$l='{0} {1}' -f (Get-Date -Format o),$Message;Add-Content $Timeline $l -Encoding UTF8;Write-Host $l}
function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Adb([string[]]$Arguments){$i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true;$i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ');$p=[Diagnostics.Process]::new();$p.StartInfo=$i;[void]$p.Start();$o=$p.StandardOutput.ReadToEnd()+$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o}}
function Phone-Write([string]$Command){if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE=$Command"};Log "PHONE_WRITE=$Command";$r=Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw $r.Text}}
function Run-Cycle([int]$Number,[switch]$Audit){$args=@('-Cycle',[string]$Number,'-RunName',$RunName);if($Audit){$args+='-StaticAudit'}else{$args+='-Execute'};$old=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$o=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CycleScript @args 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old};$o|ForEach-Object{Log "C${Number}=$_"};if($rc -ne 0){throw "R4B_STOP_AT_CYCLE=$Number exit=$rc"}}
if($StaticAudit){Run-Cycle 1 -Audit;Write-Host 'THREE_CYCLE_ORCHESTRATOR_AUDIT=PASS';Write-Host 'FAIL_CLOSED_ON_FIRST_VALID_FAILURE=YES';Write-Host 'PHONE_WRITES=0';exit 0}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}
for($cycle=1;$cycle -le 3;$cycle++){
  Run-Cycle $cycle
  if($cycle -lt 3){Phone-Write 'cmd connectivity airplane-mode disable';Log "C${cycle}_TO_C$($cycle+1)_AIRPLANE_OFF_COUNT=1";Start-Sleep -Seconds 10}
}
Write-Host 'R4B_NOT_FALSIFIED_3_CYCLES'

