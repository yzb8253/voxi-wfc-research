[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Label,
  [string]$Serial='fd0ff892',
  [string]$RunName=''
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Adb=Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$RunRoot=Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs\repeatability_normalization'
$SummaryRoot=$PSScriptRoot
if($RunName) {
  $RunRoot=Join-Path $RunRoot $RunName
  $SummaryRoot=Join-Path (Join-Path $PSScriptRoot 'runs') $RunName
}
$RunDir=Join-Path $RunRoot $Label
$SummaryDir=Join-Path $SummaryRoot 'snapshots'
$SummaryPath=Join-Path $SummaryDir ($Label + '.json')
[IO.Directory]::CreateDirectory($RunDir)|Out-Null
[IO.Directory]::CreateDirectory($SummaryDir)|Out-Null

function Quote-Sh([string]$Value) {
  $single=[string][char]39; $double=[string][char]34
  $single + $Value.Replace($single,($single+$double+$single+$double+$single)) + $single
}
function Invoke-Adb([string[]]$Arguments) {
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  $quoted=@($Arguments | ForEach-Object { if($_ -match '[\s"]'){ '"'+$_.Replace('"','\"')+'"' }else{$_} })
  $info.Arguments=$quoted -join ' '
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
  if(-not $process.Start()){throw 'Unable to start adb'}
  $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd()
  $process.WaitForExit()
  [pscustomobject]@{ExitCode=$process.ExitCode;Text=$stdout+$stderr}
}
function Read-Root([string]$Name,[string]$Command) {
  $result=Invoke-Adb @('-s',$Serial,'shell',('su -c '+(Quote-Sh $Command)))
  [IO.File]::WriteAllText((Join-Path $RunDir ($Name+'.txt')),$result.Text,[Text.UTF8Encoding]::new($false))
  $result
}
function Last-Match([string]$Text,[string]$Pattern) {
  $all=[regex]::Matches($Text,$Pattern,[Text.RegularExpressions.RegexOptions]::Multiline)
  if($all.Count){$all[$all.Count-1].Value}else{''}
}
function Process-FromPs([string]$Text,[string]$Pattern) {
  $rows=@($Text -split "\r?\n" | Where-Object { $_ -match $Pattern })
  if($rows.Count -eq 1) {
    $parts=$rows[0].Trim() -split '\s+',4
    return [ordered]@{pid=[int]$parts[0];ppid=[int]$parts[1];name=$parts[2];cmdline=$parts[3]}
  }
  $null
}
function Bool-Text([string]$Text,[string]$Pattern){[bool]($Text -match $Pattern)}

$timestamp=(Get-Date).ToString('o')
$gitHead=(git -C $Repo rev-parse HEAD).Trim()
$devices=Invoke-Adb @('devices')
if($devices.Text -notmatch "(?m)^$([regex]::Escape($Serial))\s+device\s*$"){throw "ADB target not online: $Serial"}

$identity=(Read-Root identity 'id; getprop ro.product.device; getprop ro.product.model; getprop ro.build.fingerprint').Text
$settings=(Read-Root settings 'settings get global airplane_mode_on; settings get global wifi_on; settings get global mobile_data; settings get global preferred_network_mode').Text
$network=(Read-Root network 'ip -br addr; ip route show table all; dumpsys connectivity').Text
$subscriptions=(Read-Root subscriptions 'dumpsys isub; dumpsys telephony.registry; dumpsys phone; dumpsys carrier_config').Text
$ims=(Read-Root ims 'dumpsys telephony_ims; dumpsys ims; dumpsys connectivity; dumpsys phone').Text
$processes=(Read-Root processes 'ps -A -o PID,PPID,NAME,ARGS').Text
$holderIdentity=(Read-Root holder_identity 'p=""; for f in /data/local/tmp/x55_holder.pid /data/local/tmp/x55_v27_holder.pid; do test -r "$f" && p=$(cat "$f") && break; done; case "$p" in *[!0-9]*|"") exit 0;; esac; test -d "/proc/$p" && ps -p "$p" -o PID,PPID,NAME,ARGS').Text
$init=(Read-Root init_services 'getprop init.svc.vendor.qcrild; getprop init.svc.vendor.qcrild2; getprop init.svc.vendor.per_mgr; getprop init.svc.vendor.per_proxy; getprop init.svc.vendor.mdm_helper').Text
$native=(Read-Root native_x55 'getprop vendor.peripheral.SDX55M.state; cat /sys/bus/msm_subsys/devices/subsys10/state; cat /sys/bus/msm_subsys/devices/subsys10/crash_count; lsof /dev/subsys_esoc0 2>&1; lsof /dev/esoc-0 2>&1').Text
$statusResult=Read-Root wfc_status '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh status-json'
$statusLine=@($statusResult.Text -split "\r?\n" | Where-Object {$_.Trim().StartsWith('{')}) | Select-Object -Last 1
if(-not $statusLine){throw 'wfcctl status-json missing'}
$status=$statusLine|ConvertFrom-Json
$xfrm=(Read-Root xfrm 'ip xfrm state; ip xfrm policy; ss -anupe').Text
$temp=(Read-Root module_temp 'for f in /data/local/tmp/x55* /data/local/tmp/voxi* /data/adb/modules/voxi_wfc_recovery/*.lock /data/adb/modules/voxi_wfc_recovery/*.state /data/adb/modules/voxi_wfc_recovery/*.tmp; do test -e "$f" && ls -ld "$f"; done').Text
$qcrilEvidence=(Read-Root qcril_x55_evidence 'logcat -d -b all -v threadtime | grep -E "PM_SUPPORTED|ESOC_SUPPORTED|ESOC_FD|VOTING_STATE|POWER_NODE|SDX55M|PeripheralManager|IWLAN|qti.cne|NetworkAvailabilityHandler" | tail -n 1200').Text

$qcrild=Process-FromPs $processes '^\s*\d+\s+1\s+qcrild\s+qcrild\s*$'
$qcrild2=Process-FromPs $processes '^\s*\d+\s+1\s+qcrild\s+qcrild -c 2\s*$'
$pmService=Process-FromPs $processes '^\s*\d+\s+1\s+pm-service\s+'
$pmProxy=Process-FromPs $processes '^\s*\d+\s+1\s+pm-proxy\s+'
$mdmHelper=Process-FromPs $processes '^\s*\d+\s+1\s+mdm_helper\s+'
$holder=Process-FromPs $holderIdentity '^\s*\d+\s+\d+\s+'
$ownerLines=@($native -split "\r?\n" | Where-Object {$_ -match '/dev/(subsys_esoc0|esoc-0)'})
$nativeValues=@($native -split "\r?\n" | ForEach-Object {$_.Trim()} | Where-Object {$_ -ne ''})
$safeEvidence=[regex]::Replace($qcrilEvidence,'\b\d{12,}\b','[REDACTED]')
[IO.File]::WriteAllText((Join-Path $RunDir 'qcril_x55_evidence_sanitized.txt'),$safeEvidence,[Text.UTF8Encoding]::new($false))
$requestLogIndex=$network.IndexOf('mNetworkRequestInfoLogs')
$currentConnectivity=if($requestLogIndex -ge 0){$network.Substring(0,$requestLogIndex)}else{$network}
$currentQtiImsPattern='(?m)^\s*uid/pid:[^\r\n]*activeRequest:\s*\d+[^\r\n]*Capabilities:\s*IMS[^\r\n]*mSubId = 11[^\r\n]*RequestorPkg: com\.qualcomm\.qti\.cne'
$currentQtiImsRequest=[bool]($currentConnectivity -match $currentQtiImsPattern)

$summary=[ordered]@{
  schema='wfc-repeatability-snapshot-v1'; label=$Label; timestamp=$timestamp; gitHead=$gitHead; serial=$Serial
  device=[ordered]@{root=($identity -match 'uid=0\(root\)');product='cas'}
  environment=[ordered]@{
    airplaneMode=[int](($settings -split "\r?\n")[0].Trim())
    wifiSetting=(($settings -split "\r?\n")[1].Trim())
    wlan0Up=Bool-Text $network '(?m)^wlan0\s+UP'
    tunPresent=Bool-Text $network '(?m)^(tun|clat|wg)\S*\s+UP'
    vpnNetwork=Bool-Text $network '(?i)VPN|TRANSPORT_VPN'
  }
  target=[ordered]@{subId=$status.target.subId;slotId=$status.target.slotId;phoneId=$status.target.phoneId;carrierId=$status.target.carrierId;mcc=$status.target.mcc;mnc=$status.target.mnc;mappingGate=$status.target.mappingGate}
  subscription=[ordered]@{active=$status.subscription.active;uiccAppsEnabled=$status.subscription.areUiccApplicationsEnabled;defaultDataSubId=$status.subscription.defaultDataSubId;activeDataSubId=$status.subscription.activeDataSubId}
  processes=[ordered]@{qcrild=$qcrild;qcrild2=$qcrild2;pmService=$pmService;pmProxy=$pmProxy;mdmHelper=$mdmHelper;holder=$holder}
  native=[ordered]@{
    perMgrState=(($init -split "\r?\n")[2].Trim()); ownerLines=$ownerLines
    vendorPeripheralState=if($nativeValues.Count -ge 1){$nativeValues[0]}else{'UNKNOWN'}
    x55State=if($nativeValues.Count -ge 2){$nativeValues[1]}else{'UNKNOWN'}
    x55Online=($nativeValues.Count -ge 2 -and $nativeValues[0] -ceq 'ONLINE' -and $nativeValues[1] -ceq 'ONLINE')
    crashCount=if($nativeValues.Count -ge 3 -and $nativeValues[2] -match '^\d+$'){[int]$nativeValues[2]}else{$null}
    pmSupported=Last-Match $safeEvidence 'PM_SUPPORTED[^\r\n]*';esocSupported=Last-Match $safeEvidence 'ESOC_SUPPORTED[^\r\n]*'
    esocFd=Last-Match $safeEvidence 'ESOC_FD[^\r\n]*';votingState=Last-Match $safeEvidence 'VOTING_STATE[^\r\n]*'
    powerNode=Last-Match $safeEvidence 'POWER_NODE[^\r\n]*'
  }
  ims=[ordered]@{stateRaw=$status.ims.registrationStateRaw;state=$status.ims.registrationStateName;transportRaw=$status.ims.registrationTransportRaw;transport=$status.ims.registrationTransportName;feature=$status.mmtel.featureState;voiceIwlan=$status.mmtel.voiceIwlanAvailable}
  iwlan=[ordered]@{rilTechnology=$status.iwlan.rilDataTechnology;psWlan=$status.iwlan.psWlanState;accessNetwork=$status.iwlan.accessNetworkTechnology;preferred=$status.iwlan.iwlanPreferred}
  data=[ordered]@{wfcAvailable=$status.wfc.wifiCallingAvailable;qtiCneRequest=$currentQtiImsRequest;qtiCneProbeReported=$status.connectivity.qtiCneRequestActive;imsNetworkAgent=$status.connectivity.imsIwlanNetworkAgent;udp4500=$status.epdg.udp4500Keepalive;xfrm=$status.epdg.xfrmTunnel}
  residues=[ordered]@{holderPidFile=Bool-Text $temp 'x55(?:_v27)?_holder\.pid';moduleLock=Bool-Text $temp '\.lock';moduleStateFiles=@($temp -split "\r?\n" | Where-Object {$_})}
  health=[ordered]@{goldenStrong=$status.goldenStrong;failureClass=$status.failureClass}
}
$json=$summary|ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($SummaryPath,$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $RunDir 'snapshot.json'),$json+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Host "SNAPSHOT=$Label"
Write-Host "SUMMARY=$SummaryPath"
Write-Host "RAW=$RunDir"
Write-Host "AIRPLANE=$($summary.environment.airplaneMode)"
Write-Host "WFC_HEALTHY=$($summary.health.goldenStrong)"
Write-Host "FAILURE_CLASS=$($summary.health.failureClass)"
