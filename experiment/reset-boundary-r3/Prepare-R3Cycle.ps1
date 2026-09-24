[CmdletBinding()]
param(
  [ValidateRange(1,3)][int]$Cycle = 1,
  [switch]$Execute,
  [switch]$StaticAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Serial = 'fd0ff892'
$ReadyTimeoutSeconds = 120
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$RepeatRoot = Join-Path $Repo 'experiments\wfc_repeatability_normalization'
$CaptureScript = Join-Path $RepeatRoot 'capture_snapshot.ps1'
$NativeNormalize = Join-Path $RepeatRoot 'v262_freeze_run\normalize_a1_native_owner.ps1'
$QcrildNormalize = Join-Path $RepeatRoot 'v262_freeze_run\normalize_a1_qcrild2_reacquire.ps1'
$Recovery = Join-Path $RepeatRoot 'v262_freeze_run\X55-WFC-OneClick-v2.6.2-freeze-on-success.ps1'
$RunName = 'r3_3cycle'
$SummaryRoot = Join-Path $PSScriptRoot 'runs\r3_3cycle'
$SnapshotRoot = Join-Path $SummaryRoot 'snapshots'
$GeneratedSnapshotRoot = Join-Path $RepeatRoot 'runs\r3_3cycle\snapshots'
$HostRoot = Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\reset_boundary_r3\r3_3cycle'
$Timeline = Join-Path $HostRoot ("cycle_{0}_r3.log" -f $Cycle)
[IO.Directory]::CreateDirectory($SnapshotRoot) | Out-Null
[IO.Directory]::CreateDirectory($HostRoot) | Out-Null

function Log([string]$Message) {
  $line = '{0} {1}' -f (Get-Date -Format o), $Message
  Add-Content -LiteralPath $Timeline -Value $line -Encoding UTF8
  Write-Host $line
}

function Quote-Sh([string]$Value) {
  $single=[string][char]39; $double=[string][char]34
  $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}

function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  $info.Arguments=(@($Arguments|ForEach-Object{if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_}}) -join ' ')
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd(); $process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}

function Read-Root([string]$Command) {
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){throw "READ_FAILED: $Command`n$($result.Text)"}
  $result.Text
}

function Root-Write([string]$Command) {
  if(-not $Execute){throw "DRY_RUN_BLOCKED_WRITE: $Command"}
  Log "PHONE_WRITE=$Command"
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  if($result.ExitCode -ne 0){throw "PHONE_WRITE_FAILED: $Command`n$($result.Text)"}
  $result.Text.Trim()
}

function Invoke-Child([string]$Path,[string[]]$Arguments=@()) {
  $oldPreference=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    $output=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
    $exitCode=$LASTEXITCODE
  } finally {$ErrorActionPreference=$oldPreference}
  [pscustomobject]@{ExitCode=$exitCode;Output=$output}
}

function Assert-Hash([string]$Path,[string]$Expected) {
  if(-not (Test-Path -LiteralPath $Path)){throw "MISSING_ARTIFACT=$Path"}
  $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if($actual -ne $Expected){throw "HASH_MISMATCH path=$Path expected=$Expected actual=$actual"}
  Log "HASH_PASS path=$Path sha256=$actual"
}

function Capture([string]$Label) {
  $result=Invoke-Child $CaptureScript @('-Label',$Label,'-Serial',$Serial,'-RunName',$RunName)
  foreach($line in $result.Output){Log "CAPTURE=$line"}
  if($result.ExitCode -ne 0){throw "CAPTURE_FAILED=$Label"}
  $generated=Join-Path $GeneratedSnapshotRoot ($Label+'.json')
  $json=Get-Content -LiteralPath $generated -Raw
  [IO.File]::WriteAllText((Join-Path $SnapshotRoot ($Label+'.json')),$json,[Text.UTF8Encoding]::new($false))
  Remove-Item -LiteralPath $generated -Force
  $json | ConvertFrom-Json
}

function Holder-Owns($State) {
  if($null -eq $State.processes.holder){return $false}
  $pidText=[string]$State.processes.holder.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$pidText\s"}).Count)
}

function Pm-Owns($State) {
  if($null -eq $State.processes.pmService){return $false}
  $pidText=[string]$State.processes.pmService.pid
  [bool](@($State.native.ownerLines|Where-Object{$_ -match '/dev/subsys_esoc0' -and $_ -match "\s$pidText\s"}).Count)
}

function Target-Gate($State) {
  $State.device.root -and $State.device.product -eq 'cas' -and $State.target.mappingGate -and
  $State.target.subId -eq 11 -and $State.target.slotId -eq 1 -and $State.target.phoneId -eq 1 -and
  $State.target.carrierId -eq 28 -and $State.target.mcc -eq 234 -and $State.target.mnc -eq 15 -and
  $State.subscription.active -and $State.subscription.uiccAppsEnabled
}

function Process-Gate($State) {
  $null -ne $State.processes.qcrild -and $State.processes.qcrild.ppid -eq 1 -and $State.processes.qcrild.cmdline -eq 'qcrild' -and
  $null -ne $State.processes.qcrild2 -and $State.processes.qcrild2.ppid -eq 1 -and $State.processes.qcrild2.cmdline -eq 'qcrild -c 2' -and
  $null -ne $State.processes.pmProxy -and $null -ne $State.processes.mdmHelper
}

function Native-Clean($State) {
  $State.native.perMgrState -eq 'running' -and $null -ne $State.processes.pmService -and
  $State.processes.pmService.ppid -eq 1 -and $State.processes.pmService.cmdline -eq 'pm-service' -and
  (Pm-Owns $State) -and -not (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.x55State -eq 'ONLINE' -and
  $State.native.crashCount -eq 0 -and -not $State.residues.holderPidFile
}

function A-Canonical($State) {
  (Target-Gate $State) -and (Process-Gate $State) -and (Native-Clean $State) -and
  $State.environment.airplaneMode -eq 0 -and $State.environment.wlan0Up -and $State.environment.vpnNetwork -and
  $State.iwlan.rilTechnology -eq 'LTE' -and -not $State.iwlan.preferred -and
  -not $State.data.qtiCneRequest -and -not $State.residues.moduleLock
}

function Frozen-Residue($State) {
  $State.environment.airplaneMode -eq 0 -and $State.native.perMgrState -eq 'stopped' -and
  $null -eq $State.processes.pmService -and (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'ONLINE' -and $State.native.x55State -eq 'ONLINE' -and $State.native.crashCount -eq 0
}

function Fallback-Residue($State) {
  $State.environment.airplaneMode -eq 0 -and $State.native.perMgrState -eq 'running' -and
  $null -ne $State.processes.pmService -and -not (Pm-Owns $State) -and (Holder-Owns $State) -and
  $State.native.vendorPeripheralState -eq 'OFFLINE' -and $State.native.x55State -eq 'ONLINE' -and $State.native.crashCount -eq 0
}

function Extra-Environment-Gate {
  $text=Read-Root "cmd location is-location-enabled; settings get secure location_mode; pidof com.cxorz.anywhere; dumpsys location | grep -E -i -m8 'com.cxorz.anywhere|last mock location'"
  $lines=@($text -split "\r?\n")
  ($lines.Count -ge 3 -and $lines[0].Trim() -eq 'true' -and $lines[1].Trim() -ne '0' -and
   $lines[2].Trim() -match '^\d+$' -and $text -match 'com\.cxorz\.anywhere' -and $text -match 'mock')
}

function Normalize-R0($State) {
  if(A-Canonical $State){Log 'R0=A_PASS_NO_WRITE';return $State}
  if(-not $Execute){throw 'R0_EXECUTE_REQUIRED'}
  if(Fallback-Residue $State) {
    $result=Invoke-Child $QcrildNormalize @('-Serial',$Serial)
    foreach($line in $result.Output){Log "R0_QCRILD=$line"}
    if($result.ExitCode -ne 0){throw 'R0_QCRILD_FAILED'}
  } elseif(Frozen-Residue $State) {
    $result=Invoke-Child $NativeNormalize @('-Serial',$Serial)
    foreach($line in $result.Output){Log "R0_NATIVE=$line"}
    if($result.ExitCode -ne 0) {
      $fallback=Invoke-Child $QcrildNormalize @('-Serial',$Serial)
      foreach($line in $fallback.Output){Log "R0_QCRILD=$line"}
      if($fallback.ExitCode -ne 0){throw 'R0_QCRILD_FAILED'}
    }
  } else {throw 'R0_UNKNOWN_FINGERPRINT'}
  Start-Sleep -Seconds 60
  $normalized=Capture ("R3_C{0}_R0_NORMALIZED" -f $Cycle)
  if(-not (A-Canonical $normalized)){throw 'R0_NOT_CANONICAL'}
  Log 'R0=PASS'
  $normalized
}

function Get-Scope {
  $ps=Read-Root 'ps -A -o UID,PID,PPID,NAME,ARGS; echo ===Z===; ps -AZ; echo ===ACT===; dumpsys activity processes com.android.phone; echo ===PKG===; dumpsys package com.android.phone | grep -E "flags=|User 0:"'
  function One([string]$Pattern,[string]$Label) {
    $rows=@($ps -split "\r?\n" | Where-Object{$_ -match $Pattern})
    if($rows.Count -ne 1){throw "PROCESS_IDENTITY_$Label count=$($rows.Count)"}
    $parts=$rows[0].Trim() -split '\s+',5
    [pscustomobject]@{uid=[int]$parts[0];pid=[int]$parts[1];ppid=[int]$parts[2];name=$parts[3];args=$parts[4]}
  }
  $main=One '^\s*1001\s+\d+\s+\d+\s+com\.android\.phone\s+com\.android\.phone\s*$' 'PHONE'
  if($ps -notmatch "u:r:radio:s0\s+radio\s+$($main.pid)\s+"){throw 'PHONE_SELINUX_MISMATCH'}
  if($ps -notmatch "\*PERS\* UID 1001 ProcessRecord\{[^\r\n]* $($main.pid):com\.android\.phone/1001\}" -or $ps -notmatch 'persistent=true removed=false'){throw 'PHONE_NOT_PERSISTENT'}
  if($ps -notmatch 'User 0:.*stopped=false'){throw 'PHONE_PACKAGE_STOPPED_OR_UNOBSERVABLE'}
  [pscustomobject]@{
    phone=$main
    qcrild=(One '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild\s*$' 'QCRILD')
    qcrild2=(One '^\s*1001\s+\d+\s+1\s+qcrild\s+qcrild -c 2\s*$' 'QCRILD2')
    qtidata=(One '^\s*10104\s+\d+\s+\d+\s+\.qtidataservices\s+\.qtidataservices\s*$' 'QTIDATA')
    qcomims=(One '^\s*10196\s+\d+\s+\d+\s+org\.codeaurora\.ims\s+org\.codeaurora\.ims\s*$' 'QCOMIMS')
  }
}

function Same-Vendor-Scope($Before,$After) {
  $Before.qcrild.pid -eq $After.qcrild.pid -and $Before.qcrild2.pid -eq $After.qcrild2.pid -and
  $Before.qtidata.pid -eq $After.qtidata.pid -and $Before.qcomims.pid -eq $After.qcomims.pid
}

function Creation-Markers([string]$Text,[int]$NewPid) {
  $phoneLines=@($Text -split "\r?\n" | Where-Object{$_ -match "\s$NewPid\s+$NewPid\s+" -or $_ -match "\s$NewPid\s+\d+\s+"}) -join "`n"
  [ordered]@{
    phone0=($phoneLines -match 'PhoneFactory: Creating Phone with type = .* sub = 0')
    phone1=($phoneLines -match 'PhoneFactory: Creating Phone with type = .* sub = 1')
    anm1=($phoneLines -match 'ANM-1\s*: (operates in AP-assisted mode|bind to vendor\.qti\.iwlan)')
    sst1=($phoneLines -match '\[1\] QtiServiceStateTracker created')
    nrm1Register=($phoneLines -match 'NRM-I-1\s*: registerForNetworkRegistrationInfoChanged')
    nrm1Connected=($phoneLines -match 'NRM-I-1\s*: service .*IWlanNetworkService.* is now connected')
    dnc1=($phoneLines -match 'DNC-1\s*: DataNetworkController created')
    dnc1Wlan=($phoneLines -match 'DNC-1\s*: onDataServiceBindingChanged: WLAN data service is bound')
    carrierLoaded=($Text -match 'phoneId: 1 simState: LOADED' -or $phoneLines -match 'DNC-1\s*: onDataConfigUpdated: config is carrier specific\. mSimState=LOADED')
    mmtel11=($phoneLines -match '\[1, MMTEL\] connectionReady 11' -or $phoneLines -match '\[1\] connectionReady for subId = 11')
  }
}

Log "R3_PREPARE_BEGIN cycle=$Cycle execute=$Execute"
Assert-Hash $Recovery '445752BB49FB487850D0B1A1EFF4F0AA29D58C363C3A86E75BAA841E4CC08F75'
if($StaticAudit){
  Write-Host 'STATIC_NO_ADB=PASS'
  Write-Host 'R3_METHOD=EXACT_UID1001_PHONE_PID_SIGTERM'
  Write-Host 'R3_READY_TIMEOUT_SECONDS=120'
  exit 0
}

$devices=Invoke-Adb @('devices')
if($devices.Text -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw 'TARGET_NOT_ONLINE'}
$aRaw=Capture ("R3_C{0}_A_RAW" -f $Cycle)
if($aRaw.environment.airplaneMode -ne 0){throw 'R3_ENTRY_REQUIRES_AIRPLANE_OFF'}
$a=Normalize-R0 $aRaw
if(-not (Extra-Environment-Gate)){throw 'R3_ENVIRONMENT_NOT_READY'}

$before=Get-Scope
Log "R3_SCOPE_BEFORE phone=$($before.phone.pid) qcrild=$($before.qcrild.pid) qcrild2=$($before.qcrild2.pid) qtidata=$($before.qtidata.pid) qcomims=$($before.qcomims.pid)"
$since=(Read-Root "date '+%m-%d %H:%M:%S.000'").Trim()
[void](Root-Write ("kill -TERM {0}" -f $before.phone.pid))

$deadline=(Get-Date).AddSeconds($ReadyTimeoutSeconds)
$markers=$null; $after=$null; $logText=''
while((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 2
  try {$after=Get-Scope} catch {continue}
  if($after.phone.pid -eq $before.phone.pid){continue}
  if(-not (Same-Vendor-Scope $before $after)){throw 'R3_SCOPE_VIOLATION_VENDOR_PID_CHANGED'}
  $logText=Read-Root ("logcat -d -b all -v threadtime -T " + (Quote-Sh $since))
  $markers=Creation-Markers $logText $after.phone.pid
  $missing=@($markers.GetEnumerator()|Where-Object{-not $_.Value}|ForEach-Object{$_.Key})
  Log "R3_READY_PROGRESS newPhone=$($after.phone.pid) missing=$($missing -join ',')"
  if($missing.Count -eq 0){break}
}
if($null -eq $after -or $after.phone.pid -eq $before.phone.pid){throw 'R3_READY_TIMEOUT_NO_NEW_PHONE'}
$missing=@($markers.GetEnumerator()|Where-Object{-not $_.Value}|ForEach-Object{$_.Key})
if($missing.Count -ne 0){throw "R3_READY_TIMEOUT_MISSING_MARKERS=$($missing -join ',')"}

$stable=0
while($stable -lt 5) {
  Start-Sleep -Seconds 1
  $sample=Get-Scope
  if($sample.phone.pid -ne $after.phone.pid -or -not (Same-Vendor-Scope $before $sample)){throw 'R3_READY_STABILITY_SCOPE_CHANGED'}
  $stable++
}
$ready=Capture ("R3_C{0}_A_READY" -f $Cycle)
if(-not (A-Canonical $ready)){throw 'R3_READY_A_NOT_CANONICAL'}
if(-not (Extra-Environment-Gate)){throw 'R3_READY_ENVIRONMENT_LOST'}
[IO.File]::WriteAllText((Join-Path $HostRoot ("cycle_{0}_phone_rebuild_log.txt" -f $Cycle)),$logText,[Text.UTF8Encoding]::new($false))
Log "R3_READY=PASS oldPhone=$($before.phone.pid) newPhone=$($after.phone.pid)"
Write-Host "R3_OLD_PHONE_PID=$($before.phone.pid)"
Write-Host "R3_NEW_PHONE_PID=$($after.phone.pid)"
Write-Host 'R3_READY=PASS'
Write-Host 'PHONE_TERM_COUNT=1'
