[CmdletBinding()]
param([switch]$Execute)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Serial='fd0ff892'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CycleScript=Join-Path $PSScriptRoot 'X55-WFC-OneClick-v2.6.3-repeatable-state-machine.ps1'
$HostLogRoot=Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\repeatability_normalization\v263_state_machine_3cycle'
$DriverLog=Join-Path $HostLogRoot 'three_cycle_driver.log'
[IO.Directory]::CreateDirectory($HostLogRoot)|Out-Null

function Log([string]$Message) {
  $line='{0} {1}' -f (Get-Date -Format o),$Message
  Add-Content -LiteralPath $DriverLog -Value $line -Encoding UTF8
  Write-Host $line
}
function Quote-Sh([string]$Value) {
  $single=[string][char]39; $double=[string][char]34
  $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}
function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Adb
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
  $process=[Diagnostics.Process]::new();$process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd();$stderr=$process.StandardError.ReadToEnd();$process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}
function Root-Write([string]$Command) {
  if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE: $Command"}
  Log "PHONE_WRITE=$Command"
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){throw "PHONE_WRITE_FAILED: $Command`n$($result.Text)"}
}

Log "THREE_CYCLE_BEGIN execute=$Execute"
for($cycle=1;$cycle -le 3;$cycle++) {
  Log "CYCLE_${cycle}_BEGIN"
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$CycleScript,'-Cycle',[string]$cycle)
  if($Execute){$arguments+='-Execute'}
  & powershell @arguments
  if($LASTEXITCODE -ne 0){throw "CYCLE_${cycle}_FAILED exit=$LASTEXITCODE"}
  Log "CYCLE_${cycle}_PASS_FREEZE"

  if($cycle -lt 3) {
    Root-Write 'cmd connectivity airplane-mode disable'
    Log "CYCLE_${cycle}_TO_NEXT_A_SETTLE_SECONDS=60"
    Start-Sleep -Seconds 60
  }
}
Log 'THREE_CYCLE_RESULT=PASS'
Write-Host 'VALIDATION_1=PASS'
Write-Host 'VALIDATION_2=PASS'
Write-Host 'VALIDATION_3=PASS'
Write-Host 'FINAL_STATE=W3_HEALTHY_FROZEN'

