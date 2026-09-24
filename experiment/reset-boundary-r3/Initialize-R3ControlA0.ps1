[CmdletBinding()]
param([switch]$Execute,[switch]$StaticAudit,[switch]$ResumeAfterReboot)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Serial='fd0ff892'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$CaptureScript=Join-Path $Repo 'experiments\wfc_repeatability_normalization\capture_snapshot.ps1'
$Recovery=Join-Path $Repo 'experiments\wfc_repeatability_normalization\v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$HostRoot=Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\reset_boundary_r3\r3_3cycle_v2'
$Marker=Join-Path $HostRoot 'CONTROL_A0_V2_REBOOT_USED.marker'
[IO.Directory]::CreateDirectory($HostRoot)|Out-Null

function Quote-Sh([string]$Value){$s=[string][char]39;$d=[string][char]34;$s+$Value.Replace($s,($s+$d+$s+$d+$s))+$s}
function Invoke-Adb([string[]]$Arguments){
  $i=[Diagnostics.ProcessStartInfo]::new();$i.FileName=$Adb;$i.UseShellExecute=$false;$i.CreateNoWindow=$true;$i.RedirectStandardOutput=$true;$i.RedirectStandardError=$true
  $i.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+$_.Replace('"','\"')+'"'}else{$_}})-join ' ')
  $p=[Diagnostics.Process]::new();$p.StartInfo=$i;if(-not $p.Start()){throw 'adb start failed'};$o=$p.StandardOutput.ReadToEnd()+$p.StandardError.ReadToEnd();$p.WaitForExit();[pscustomobject]@{ExitCode=$p.ExitCode;Text=$o}
}
function Root([string]$Command){$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw $r.Text};$r.Text}
function Write-Phone([string]$Command){if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE=$Command"};Write-Host "PHONE_WRITE=$Command";$r=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)));if($r.ExitCode -ne 0){throw $r.Text};$r.Text}

$hash=(Get-FileHash -LiteralPath $Recovery -Algorithm SHA256).Hash
if($hash -ne '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'){throw "V262_HASH_MISMATCH=$hash"}
if($StaticAudit){Write-Host 'STATIC_NO_ADB=PASS';Write-Host "V262_SHA256=$hash";exit 0}
$devices=Invoke-Adb @('devices');if($devices.Text -notmatch "(?m)^$Serial\s+device\s*$"){throw 'TARGET_NOT_ONLINE'}
if((Root 'id') -notmatch 'uid=0\(root\)'){throw 'ROOT_REQUIRED'}
if(-not $Execute){throw 'EXECUTE_REQUIRED'}

if($ResumeAfterReboot) {
  if(-not (Test-Path -LiteralPath $Marker)){throw 'CONTROL_A0_REBOOT_MARKER_MISSING'}
  Write-Host 'BASELINE_RESUME=AFTER_EXISTING_REBOOT; PHONE_WRITES=0'
} else {
  if(Test-Path -LiteralPath $Marker){throw 'CONTROL_A0_REBOOT_ALREADY_USED'}
  [IO.File]::WriteAllText($Marker,(Get-Date -Format o),[Text.UTF8Encoding]::new($false))
  Write-Host 'PHONE_WRITE=adb reboot (authorized baseline reboot 1/1)'
  $reboot=Invoke-Adb @('-s',$Serial,'reboot');if($reboot.ExitCode -ne 0){throw $reboot.Text}
  [void](Invoke-Adb @('wait-for-device'))
  $bootDeadline=(Get-Date).AddMinutes(5)
  do {Start-Sleep -Seconds 2;try{$boot=(Root 'getprop sys.boot_completed').Trim()}catch{$boot=''}} while($boot -ne '1' -and (Get-Date)-lt $bootDeadline)
  if($boot -ne '1'){throw 'BOOT_COMPLETED_TIMEOUT'}
  [void](Write-Phone 'cmd connectivity airplane-mode disable')
  [void](Write-Phone 'svc wifi enable')
}

$envDeadline=(Get-Date).AddMinutes(10)
$ready=$false
do {
  Start-Sleep -Seconds 3
  $e=Root "settings get global airplane_mode_on; ip -br link show wlan0; dumpsys connectivity | grep -m1 'VPN CONNECTED' || true; cmd location is-location-enabled; pidof com.cxorz.anywhere || true; dumpsys location | grep -E -i -m1 'last mock location' || true"
  $ready=($e -match '(?m)^0\s*$' -and $e -match '(?m)^wlan0\s+UP' -and $e -match 'VPN CONNECTED' -and $e -match '(?m)^true\s*$' -and $e -match 'mock')
} while(-not $ready -and (Get-Date)-lt $envDeadline)
if(-not $ready){throw 'CONTROL_A0_ENVIRONMENT_TIMEOUT'}

$old=$ErrorActionPreference
try{$ErrorActionPreference='Continue';$out=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $CaptureScript -Label CONTROL_A0_V2 -Serial $Serial -RunName r3_3cycle_v2 2>&1);$rc=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
$out|ForEach-Object{Write-Host $_}
if($rc -ne 0){throw 'CONTROL_A0_CAPTURE_FAILED'}
$generated=Join-Path $Repo 'experiments\wfc_repeatability_normalization\runs\r3_3cycle_v2\snapshots\CONTROL_A0_V2.json'
$destination=Join-Path $PSScriptRoot 'runs\r3_3cycle_v2\snapshots\CONTROL_A0_V2.json'
[IO.Directory]::CreateDirectory((Split-Path $destination -Parent))|Out-Null
$json=Get-Content -LiteralPath $generated -Raw
[IO.File]::WriteAllText($destination,$json,[Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $generated -Force
Write-Host 'CONTROL_A0=CAPTURED'
Write-Host 'BASELINE_REBOOT_COUNT=1'
