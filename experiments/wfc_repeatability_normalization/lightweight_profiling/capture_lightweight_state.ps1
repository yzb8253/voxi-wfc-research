[CmdletBinding()]
param(
  [string]$Serial='fd0ff892',
  [Parameter(Mandatory=$true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$WfcCtl='/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$captureErrors=New-Object 'System.Collections.Generic.List[string]'
$hostStart=[DateTimeOffset]::UtcNow
$epoch=[guid]::NewGuid().ToString('D')
$commandCount=0

function Quote-Sh([string]$Value) {
  $single=[string][char]39
  $double=[string][char]34
  $single+$Value.Replace($single,($single+$double+$single+$double+$single))+$single
}

function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb
  $info.UseShellExecute=$false
  $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true
  $info.RedirectStandardError=$true
  $quoted=@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}})
  $info.Arguments=$quoted -join ' '
  $process=[Diagnostics.Process]::new()
  $process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd()
  $stderr=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  $result=[pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
  $process.Dispose()
  $result
}

function Read-Root([string]$Name,[string]$Command) {
  $script:commandCount++
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){$script:captureErrors.Add("command_failed:$Name")}
  $result.Text
}

function Parse-KeyValue([string]$Text) {
  $result=[ordered]@{}
  foreach($line in @($Text -split "\r?\n")) {
    if($line -match '^([A-Z0-9_]+)=(.*)$'){$result[$Matches[1]]=$Matches[2].Trim()}
  }
  $result
}

function Parse-ProcessLine([string]$Line) {
  if([string]::IsNullOrWhiteSpace($Line)){return $null}
  $parts=$Line.Trim() -split '\s+',4
  if($parts.Count -ne 4 -or $parts[0] -notmatch '^\d+$' -or $parts[1] -notmatch '^\d+$'){return $null}
  [ordered]@{processExists=$true;pid=[int]$parts[0];ppid=[int]$parts[1];name=$parts[2];cmdline=$parts[3]}
}

function Null-Process {
  [ordered]@{processExists=$false;pid=$null;ppid=$null;name=$null;cmdline=$null}
}

function Read-Property([object]$Object,[string]$Name) {
  if($null -eq $Object){return $null}
  $property=$Object.PSObject.Properties[$Name]
  if($null -eq $property){return $null}
  $property.Value
}

function Has-Property([object]$Object,[string]$Name) {
  $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

if(-not (Test-Path -LiteralPath $Adb)){throw "adb.exe not found: $Adb"}
$devices=Invoke-Adb @('devices')
if($devices.Text -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw "ADB target not online: $Serial"}

$meta=Parse-KeyValue (Read-Root 'meta' 'echo DEVICE_START_MS=$(date +%s%3N); echo AIRPLANE=$(settings get global airplane_mode_on); echo WIFI=$(settings get global wifi_on)')
$statusText=Read-Root 'status' "$WfcCtl status-json"
$statusLine=@($statusText -split "\r?\n"|Where-Object{$_.Trim().StartsWith('{')})|Select-Object -Last 1
$status=$null
if($statusLine){
  try{$status=$statusLine|ConvertFrom-Json}catch{$captureErrors.Add('parse_error:wfc_status_json')}
}else{$captureErrors.Add('missing:wfc_status_json')}

$processText=Read-Root 'processes' "ps -A -o PID,PPID,NAME,ARGS | grep -E '^ *[0-9]+ +1 +(qcrild|pm-service) +' || true"
$processLines=@($processText -split "\r?\n"|Where-Object{$_})
$primaryLine=@($processLines|Where-Object{$_ -match '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$'})
$secondaryLine=@($processLines|Where-Object{$_ -match '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'})
$pmLine=@($processLines|Where-Object{$_ -match '^\s*\d+\s+1\s+pm-service\s+pm-service\s*$'})
if($primaryLine.Count -ne 1){$captureErrors.Add('ambiguous:qcrild_primary')}
if($secondaryLine.Count -ne 1){$captureErrors.Add('ambiguous:qcrild2')}
if($pmLine.Count -gt 1){$captureErrors.Add('ambiguous:pm_service')}

$holderRaw=Read-Root 'holder' 'f=/data/local/tmp/x55_holder.pid; if test -r "$f"; then p=$(cat "$f"); echo PIDFILE_PRESENT=1; echo PIDFILE_VALUE=$p; case "$p" in *[!0-9]*|"") echo PROCESS_EXISTS=0;; *) if test -d "/proc/$p"; then echo PROCESS_EXISTS=1; echo PROCESS_LINE=$(ps -p "$p" -o PID,PPID,NAME,ARGS | tail -n 1); echo FD9=$(readlink "/proc/$p/fd/9" 2>/dev/null); else echo PROCESS_EXISTS=0; fi;; esac; else echo PIDFILE_PRESENT=0; echo PROCESS_EXISTS=0; fi'
$holderKv=Parse-KeyValue $holderRaw
$holderPresent=($holderKv.Contains('PIDFILE_PRESENT') -and $holderKv.PIDFILE_PRESENT -eq '1')
$holderExists=($holderKv.Contains('PROCESS_EXISTS') -and $holderKv.PROCESS_EXISTS -eq '1')
$holderProcess=if($holderExists -and $holderKv.Contains('PROCESS_LINE')){Parse-ProcessLine $holderKv.PROCESS_LINE}else{$null}

$nativeRaw=Read-Root 'native' 'p=$(getprop init.svc_debug_pid.vendor.per_mgr); echo PER_MGR=$(getprop init.svc.vendor.per_mgr); echo PM_SERVICE_PID=$p; echo PM_SERVICE_EXE=$(readlink "/proc/$p/exe" 2>/dev/null); echo VENDOR_X55=$(getprop vendor.peripheral.SDX55M.state); echo KERNEL_X55=$(cat /sys/bus/msm_subsys/devices/subsys10/state); echo CRASH_COUNT=$(cat /sys/bus/msm_subsys/devices/subsys10/crash_count); lsof /dev/subsys_esoc0 2>/dev/null | sed "s/^/OWNER=/"; echo DEVICE_END_MS=$(date +%s%3N)'
$nativeKv=Parse-KeyValue $nativeRaw
$ownerRows=@($nativeRaw -split "\r?\n"|Where-Object{$_ -match '^OWNER='})
$owners=@()
foreach($row in $ownerRows) {
  $line=$row.Substring(6).Trim()
  $parts=$line -split '\s+'
  if($parts.Count -lt 2 -or $parts[1] -notmatch '^\d+$' -or $parts[$parts.Count-1] -cne '/dev/subsys_esoc0') {
    $captureErrors.Add('parse_error:esoc_owner')
    continue
  }
  $owners += [ordered]@{pid=[int]$parts[1];name=$parts[0];path='/dev/subsys_esoc0'}
}

$deviceStart=if($meta.Contains('DEVICE_START_MS') -and $meta.DEVICE_START_MS -match '^\d+$'){[int64]$meta.DEVICE_START_MS}else{$captureErrors.Add('parse_error:device_start_ms');$null}
$deviceEnd=if($nativeKv.Contains('DEVICE_END_MS') -and $nativeKv.DEVICE_END_MS -match '^\d+$'){[int64]$nativeKv.DEVICE_END_MS}else{$captureErrors.Add('parse_error:device_end_ms');$null}
$hostEnd=[DateTimeOffset]::UtcNow
$spanMs=[int64][Math]::Round(($hostEnd-$hostStart).TotalMilliseconds)

if($null -eq $status){$status=[pscustomobject]@{}}
$statusTarget=Read-Property $status 'target'
$statusSubscription=Read-Property $status 'subscription'
$statusConnectivity=Read-Property $status 'connectivity'
$statusIms=Read-Property $status 'ims'
$statusMmtel=Read-Property $status 'mmtel'
$statusWfc=Read-Property $status 'wfc'
$summary=[ordered]@{
  schema='voxi-wfc-lightweight-state-v1'
  capture=[ordered]@{
    observationEpoch=$epoch
    hostStartUtc=$hostStart.ToString('o')
    hostEndUtc=$hostEnd.ToString('o')
    deviceStartMs=$deviceStart
    deviceEndMs=$deviceEnd
    spanMs=$spanMs
    commandCount=$commandCount
    complete=($captureErrors.Count -eq 0)
    errors=@($captureErrors)
  }
  environment=[ordered]@{
    airplaneMode=if($meta.Contains('AIRPLANE') -and $meta.AIRPLANE -match '^[01]$'){[int]$meta.AIRPLANE}else{$null}
    wifiSetting=if($meta.Contains('WIFI')){[string]$meta.WIFI}else{$null}
  }
  target=[ordered]@{
    subId=Read-Property $statusTarget 'subId'
    slotId=Read-Property $statusTarget 'slotId'
    phoneId=Read-Property $statusTarget 'phoneId'
    carrierId=Read-Property $statusTarget 'carrierId'
    mcc=Read-Property $statusTarget 'mcc'
    mnc=Read-Property $statusTarget 'mnc'
    mappingGate=Read-Property $statusTarget 'mappingGate'
    subscriptionActive=Read-Property $statusSubscription 'active'
    uiccApplicationsEnabled=Read-Property $statusSubscription 'areUiccApplicationsEnabled'
  }
  holder=[ordered]@{
    pidFilePresent=$holderPresent
    pidFileValue=if($holderPresent -and $holderKv.Contains('PIDFILE_VALUE') -and $holderKv.PIDFILE_VALUE -match '^\d+$'){[int]$holderKv.PIDFILE_VALUE}else{$null}
    processExists=$holderExists
    pid=if($holderProcess){$holderProcess.pid}else{$null}
    cmdline=if($holderProcess){$holderProcess.cmdline}else{$null}
    fd9Target=if($holderExists -and $holderKv.Contains('FD9')){[string]$holderKv.FD9}else{$null}
  }
  native=[ordered]@{
    ownerCount=@($owners).Count
    owners=$owners
    perMgrState=if($nativeKv.Contains('PER_MGR')){[string]$nativeKv.PER_MGR}else{$null}
    pmService=if($pmLine.Count -eq 1){
      $parsed=Parse-ProcessLine $pmLine[0]
      [ordered]@{processExists=$true;pid=$parsed.pid;ppid=$parsed.ppid;name=$parsed.name;cmdline=$parsed.cmdline;exe=if($nativeKv.Contains('PM_SERVICE_EXE')){[string]$nativeKv.PM_SERVICE_EXE}else{$null};initPid=if($nativeKv.Contains('PM_SERVICE_PID') -and $nativeKv.PM_SERVICE_PID -match '^\d+$'){[int]$nativeKv.PM_SERVICE_PID}else{$null}}
    }else{[ordered]@{processExists=$false;pid=$null;ppid=$null;name=$null;cmdline=$null;exe=$null;initPid=if($nativeKv.Contains('PM_SERVICE_PID') -and $nativeKv.PM_SERVICE_PID -match '^\d+$'){[int]$nativeKv.PM_SERVICE_PID}else{$null}}}
    vendorX55State=if($nativeKv.Contains('VENDOR_X55')){[string]$nativeKv.VENDOR_X55}else{$null}
    kernelX55State=if($nativeKv.Contains('KERNEL_X55')){[string]$nativeKv.KERNEL_X55}else{$null}
    crashCount=if($nativeKv.Contains('CRASH_COUNT') -and $nativeKv.CRASH_COUNT -match '^\d+$'){[int]$nativeKv.CRASH_COUNT}else{$null}
  }
  qcril=[ordered]@{
    primary=if($primaryLine.Count -eq 1){Parse-ProcessLine $primaryLine[0]}else{Null-Process}
    secondary=if($secondaryLine.Count -eq 1){Parse-ProcessLine $secondaryLine[0]}else{Null-Process}
  }
  cne=[ordered]@{
    requestId=Read-Property $statusConnectivity 'qtiCneRequestId'
    satisfiedId=Read-Property $statusConnectivity 'qtiCneSatisfiedRequestId'
    currentEvidenceValid=((Has-Property $statusConnectivity 'qtiCneRequestId') -and (Has-Property $statusConnectivity 'qtiCneSatisfiedRequestId'))
  }
  health=[ordered]@{
    imsRegistrationRaw=Read-Property $statusIms 'registrationStateRaw'
    transportRaw=Read-Property $statusIms 'registrationTransportRaw'
    voiceIwlanAvailable=Read-Property $statusMmtel 'voiceIwlanAvailable'
    wfcAvailable=Read-Property $statusWfc 'wifiCallingAvailable'
    goldenStrong=Read-Property $status 'goldenStrong'
  }
}

$parent=Split-Path -Parent $OutputPath
if($parent){[IO.Directory]::CreateDirectory($parent)|Out-Null}
$json=$summary|ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($OutputPath,$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ("LIGHTWEIGHT_STATE={0}" -f (Resolve-Path -LiteralPath $OutputPath).Path)
Write-Output ("CAPTURE_SPAN_MS={0}" -f $spanMs)
Write-Output ("COMMAND_COUNT={0}" -f $commandCount)
Write-Output ("COMPLETE={0}" -f ($captureErrors.Count -eq 0))
