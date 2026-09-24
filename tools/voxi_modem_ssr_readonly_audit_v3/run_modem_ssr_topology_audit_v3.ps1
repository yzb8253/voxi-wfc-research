
[CmdletBinding()]
param(
    [string]$Serial
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$Root = $PSScriptRoot
$CaptureRoot = Join-Path $Root "captures"
New-Item -ItemType Directory -Force $CaptureRoot | Out-Null

function Find-Adb {
    $c = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $cands = @(
        "$env:USERPROFILE\Desktop\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    )
    foreach ($p in $cands) { if (Test-Path $p) { return $p } }
    throw "adb.exe not found"
}

function Invoke-Adb {
    param([string[]]$AdbArgs, [switch]$AllowFailure)
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $script:Adb @AdbArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    $txt = ($out | ForEach-Object { "$_" }) -join "`r`n"
    if ((-not $AllowFailure) -and $code -ne 0) {
        throw "adb failed ($code): adb $($AdbArgs -join ' ')`n$txt"
    }
    [pscustomobject]@{ Code = $code; Text = $txt }
}

function Root-Read([string]$Command) {
    Invoke-Adb -AdbArgs @("-s",$script:Serial,"shell","su","-c",$Command) -AllowFailure
}

function Save-Text([string]$Name,[string]$Text) {
    [IO.File]::WriteAllText((Join-Path $script:RunDir $Name), $Text, [Text.UTF8Encoding]::new($false))
}

function Capture([string]$Name,[string]$Command) {
    $r = Root-Read $Command
    Save-Text $Name $r.Text
    return $r
}

function Resolve-Serial {
    $r = Invoke-Adb -AdbArgs @("devices")
    $devs = @()
    foreach ($line in ($r.Text -split "`r?`n")) {
        if ($line -match '^(\S+)\s+device(?:\s|$)') { $devs += $Matches[1] }
    }
    if ($Serial) {
        if ($devs -notcontains $Serial) { throw "Serial $Serial is not online" }
        return $Serial
    }
    if ($devs.Count -ne 1) { throw "Expected exactly one online device; found $($devs.Count)" }
    return $devs[0]
}

$script:Adb = Find-Adb
$script:Serial = Resolve-Serial

$stamp = [DateTimeOffset]::Now.ToString("yyyyMMdd_HHmmss_fffzzz").Replace(":","")
$script:RunDir = Join-Path $CaptureRoot "run_$stamp"
New-Item -ItemType Directory -Force $RunDir | Out-Null

Write-Host "VOXI modem SSR topology audit v3 - READ ONLY"
Write-Host "Device: $Serial"
Write-Host "Capture: $RunDir"

$root = Root-Read "id; cat /proc/self/attr/current"
Save-Text "root_identity.txt" $root.Text
if ($root.Text -notmatch 'uid=0\(root\)') { throw "Root gate failed" }

Capture "remoteproc_detail.txt" @'
echo "=== REMOTEPROC ==="
for p in /sys/class/remoteproc/remoteproc*; do
  [ -e "$p" ] || continue
  echo
  echo "### $p"
  echo "realpath=$(readlink -f "$p" 2>/dev/null)"
  for f in name state firmware recovery_disabled coredump uevent; do
    if [ -r "$p/$f" ]; then
      echo "--- $f ---"
      cat "$p/$f" 2>/dev/null
    fi
  done
  [ -L "$p/device/driver" ] && echo "driver=$(readlink -f "$p/device/driver")"
  [ -L "$p/device/of_node" ] && echo "of_node=$(readlink -f "$p/device/of_node")"
  if [ -L "$p/device/of_node" ]; then
    n=$(readlink -f "$p/device/of_node")
    for f in name compatible status; do
      if [ -r "$n/$f" ]; then
        printf "dt.%s=" "$f"
        tr '\000' ' ' < "$n/$f" 2>/dev/null
        echo
      fi
    done
  fi
  echo "--- permissions ---"
  ls -laZ "$p" 2>/dev/null
done
'@ | Out-Null

Capture "esoc_detail.txt" @'
echo "=== ESOC DEVICES ==="
for p in /sys/bus/esoc/devices/*; do
  [ -e "$p" ] || continue
  echo
  echo "### $p"
  echo "realpath=$(readlink -f "$p" 2>/dev/null)"
  [ -L "$p/driver" ] && echo "driver=$(readlink -f "$p/driver")"
  [ -L "$p/of_node" ] && echo "of_node=$(readlink -f "$p/of_node")"
  echo "--- attrs ---"
  ls -laZ "$p" 2>/dev/null
  for f in "$p"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    case "$b" in
      modalias|uevent|esoc_link_info|link_name|link_state|modem_state|state|status|name|ssr|restart*)
        echo "--- $b ---"
        cat "$f" 2>/dev/null
        ;;
    esac
  done
done
'@ | Out-Null

Capture "subsys_detail.txt" @'
echo "=== SUBSYSTEM FRAMEWORK ==="
for base in /sys/class/subsys /sys/bus/msm_subsys/devices /sys/devices/virtual/subsys; do
  [ -d "$base" ] || continue
  echo
  echo "## BASE $base"
  for p in "$base"/*; do
    [ -e "$p" ] || continue
    echo
    echo "### $p"
    echo "realpath=$(readlink -f "$p" 2>/dev/null)"
    [ -L "$p/driver" ] && echo "driver=$(readlink -f "$p/driver")"
    [ -L "$p/of_node" ] && echo "of_node=$(readlink -f "$p/of_node")"
    for f in name state restart_level crash_status status uevent; do
      [ -r "$p/$f" ] && { echo "--- $f ---"; cat "$p/$f" 2>/dev/null; }
    done
    echo "--- permissions ---"
    ls -laZ "$p" 2>/dev/null
  done
done
'@ | Out-Null

Capture "devnode_detail.txt" @'
echo "=== CANDIDATE DEVICE NODES ==="
find /dev -maxdepth 2 \( -iname "*esoc*" -o -iname "*subsys*" -o -iname "*ssr*" -o -iname "*remoteproc*" -o -iname "*ramdump*" -o -iname "*modem*" \) -exec ls -laZ {} \; 2>/dev/null
echo
echo "=== QRTR / DIAG / SMD CONTEXT ==="
find /dev -maxdepth 2 \( -iname "*qrtr*" -o -iname "*diag*" -o -iname "*smd*" \) -exec ls -laZ {} \; 2>/dev/null | head -n 1000
'@ | Out-Null

Capture "platform_driver_map.txt" @'
echo "=== PLATFORM / BUS DRIVER MAP ==="
for d in /sys/bus/platform/drivers /sys/bus/esoc/drivers /sys/bus/remoteproc/drivers; do
  [ -d "$d" ] || continue
  echo "## $d"
  ls -1 "$d" 2>/dev/null | grep -Ei "modem|mss|mba|remoteproc|esoc|subsys|ssr|pil|qcom" | head -n 1000
done

echo
echo "=== MATCHING PLATFORM DEVICES ==="
find /sys/bus/platform/devices -maxdepth 1 -type l 2>/dev/null | while read p; do
  r=$(readlink -f "$p" 2>/dev/null)
  echo "$p -> $r"
done | grep -Ei "modem|mss|mba|remoteproc|esoc|subsys|ssr|pil|qcom" | head -n 2000
'@ | Out-Null

Capture "device_tree_detail.txt" @'
echo "=== DT MATCHES WITH COMPATIBLE ==="
find /proc/device-tree -maxdepth 10 -type d 2>/dev/null | grep -Ei "modem|mss|mba|remoteproc|esoc|subsys|ssr|pil" | head -n 1000 | while read n; do
  echo "### $n"
  [ -r "$n/compatible" ] && { printf "compatible="; tr '\000' ' ' < "$n/compatible"; echo; }
  [ -r "$n/status" ] && { printf "status="; tr '\000' ' ' < "$n/status"; echo; }
done
'@ | Out-Null

Capture "kernel_history.txt" @'
echo "=== DMESG ==="
dmesg 2>/dev/null | grep -Ei "remoteproc|rproc|esoc|subsystem|subsys|ssr|pil|mba|mss|modem|ramdump|fatal|crash|restart" | tail -n 3500
echo
echo "=== PSTORE / LAST_KMSG IF PRESENT ==="
for f in /sys/fs/pstore/* /proc/last_kmsg; do
  [ -r "$f" ] || continue
  echo "### $f"
  cat "$f" 2>/dev/null | grep -Ei "remoteproc|rproc|esoc|subsystem|subsys|ssr|pil|mba|mss|modem|ramdump|fatal|crash|restart" | tail -n 1500
done
'@ | Out-Null

Capture "proc_module_symbols.txt" @'
echo "=== MODULES ==="
cat /proc/modules 2>/dev/null | grep -Ei "remoteproc|rproc|esoc|subsys|ssr|pil|mba|mss|modem|ramdump"
echo
echo "=== KALLSYMS NAMES ONLY ==="
cat /proc/kallsyms 2>/dev/null | grep -Ei "subsystem_restart|subsys.*restart|esoc.*restart|remoteproc.*(stop|start|shutdown|boot)|qcom.*remoteproc|modem.*restart" | head -n 2000
'@ | Out-Null

Capture "properties_services.txt" @'
echo "=== PROPS ==="
getprop | grep -Ei "baseband|radio|modem|ssr|esoc|remoteproc|subsys|pil|mss|mba|rild|qcril|ramdump|qrtr|pd_mapper"
echo
echo "=== PROCESSES ==="
ps -AZ 2>/dev/null | grep -Ei "qcril|rild|modem|rmt_storage|qrtr|pd-mapper|pd_mapper|ims|cnd|netmgr|esoc|ssr|subsys"
echo
echo "=== HIDL/AIDL-ish ==="
lshal 2>/dev/null | grep -Ei "radio|modem|iwlan|ims|qti|esoc|subsys"
service list 2>/dev/null | grep -Ei "radio|modem|ims|qti|phone"
'@ | Out-Null

$rp = Get-Content (Join-Path $RunDir "remoteproc_detail.txt") -Raw
$es = Get-Content (Join-Path $RunDir "esoc_detail.txt") -Raw
$ss = Get-Content (Join-Path $RunDir "subsys_detail.txt") -Raw
$dn = Get-Content (Join-Path $RunDir "devnode_detail.txt") -Raw
$kh = Get-Content (Join-Path $RunDir "kernel_history.txt") -Raw

$rpNames = [regex]::Matches($rp,'(?m)^--- name ---\r?\n([^\r\n]+)').Groups[1].Value
$hasMss = [bool]($rp -match '(?i)\b(mss|modem|mba)\b')
$esocPaths = @([regex]::Matches($es,'(?m)^### (.+)$') | ForEach-Object {$_.Groups[1].Value})
$subsysModem = [bool]($ss -match '(?i)\b(modem|mss|mba)\b')
$devNodes = @([regex]::Matches($dn,'(?m)^.*(/dev/\S*(?:esoc|subsys|ssr|ramdump|modem)\S*).*$') | ForEach-Object {$_.Groups[1].Value})
$restartHistory = [bool]($kh -match '(?i)subsystem.*restart|ssr.*modem|remoteproc.*(?:stop|start|shutdown|boot)|modem.*(?:crash|restart)')

$summary = @"
=== MODEM SSR TOPOLOGY AUDIT V3 ===
RunDir: $RunDir
Device: $Serial
PHONE_WRITE_COUNT: 0
AP_REBOOT: NO
SIM_UICC_WRITE: NO
RADIO_MODEM_WRITE: NO

RemoteprocCount: $(([regex]::Matches($rp,'(?m)^### /sys/class/remoteproc/remoteproc')).Count)
RemoteprocModemLikeNameSeen: $hasMss
EsocDeviceCount: $($esocPaths.Count)
SubsystemModemLikeEntrySeen: $subsysModem
CandidateDevNodeCount: $($devNodes.Count)
KernelRestartHistorySeen: $restartHistory

IMPORTANT:
- This audit is topology discovery only.
- No SSR/remoteproc/sysfs/devnode write was attempted.
- Next decision must be based on exact realpath/driver/name/state evidence in the capture files.
"@

Save-Text "SUMMARY.txt" $summary
Write-Host ""
Write-Host $summary
Write-Host "Please send SUMMARY.txt plus remoteproc_detail.txt, esoc_detail.txt, subsys_detail.txt, and kernel_history.txt."
