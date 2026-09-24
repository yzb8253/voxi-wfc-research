[CmdletBinding()]
param(
  [switch]$Execute,
  [switch]$StaticNoAdb,
  [ValidateSet('', 'EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF')]
  [string]$Confirmation = '',
  [string]$Serial = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Version = 'v2.7-alpha-native-handoff'
$DeviceNode = '/dev/subsys_esoc0'
$X55StatePath = '/sys/bus/msm_subsys/devices/subsys10/state'
$CrashCountPath = '/sys/bus/msm_subsys/devices/subsys10/crash_count'
$HolderPidFile = '/data/local/tmp/x55_v27_holder.pid'
$DeviceWorkDir = '/data/local/tmp/voxi-x55-v27-alpha'
$WfcCtl = '/data/adb/modules/voxi_wfc_recovery/bin/wfcctl.sh'
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Adb = Join-Path (Split-Path $Repo -Parent) 'adb.exe'
$RunRoot = Join-Path (Split-Path $Repo -Parent) 'voxi_wfc_local_runs'
$RunDir = Join-Path $RunRoot ('v27_alpha_native_handoff_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Transcript = Join-Path $RunDir 'experiment.log'
$RawLogcat = Join-Path $RunDir 'logcat_all.raw.txt'
$FilteredLogcat = Join-Path $RunDir 'logcat_filtered_sanitized.txt'

$DualHelperLocal = Join-Path $Repo 'experiments\sim_soft_reset\L1_5_voxi_power_cycle\executor\build\slot1-sim-power-helper.jar'
$DualHelperHash = 'BE877B6E9694B4100F2487DC892803DE6399C89588F194A1E54D4C3AE3173A31'
$DualOrchestrator = Join-Path $PSScriptRoot 'device\v27_sim_cycle_dual.sh'
$SingleHelperLocal = Join-Path $Repo 'experiments\sim_soft_reset\single_sim_isolation\build\single-sim-slot1-power-helper.jar'
$SingleHelperHash = '90D6F55FBE1F941C1E3EEE1AA1F93B569FA3AE4084B93C5560082A38AAAF5C39'
$SingleOrchestrator = Join-Path $PSScriptRoot 'device\v27_sim_cycle_single.sh'

$script:PhoneWrites = 0
$script:HolderHostProcess = $null
$script:HolderAndroidProcessId = $null
$script:HolderTermSent = $false
$script:PerMgrWasStopped = $false
$script:LogcatProcess = $null
$script:Failure = $null
$script:RecoveryResult = 'NOT_RUN'
$script:NativeHandoffResult = 'NOT_RUN'
$script:FinalWfcResult = 'NOT_CHECKED'
$script:CleanupResult = 'NOT_RUN'
$script:RevoteEvidence = 'NOT_CHECKED'

function Write-Log([string]$Message) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'), $Message
  [IO.File]::AppendAllText($Transcript, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
  Write-Host $line
}

function Save-Text([string]$Name, [string]$Text) {
  [IO.File]::WriteAllText((Join-Path $RunDir $Name), $Text.TrimEnd() + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function ConvertTo-WindowsCommandLineArgument([AllowEmptyString()][string]$Value) {
  if ($Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  $builder = [Text.StringBuilder]::new()
  [void]$builder.Append('"')
  $backslashes = 0
  foreach ($character in $Value.ToCharArray()) {
    if ($character -eq '\') {
      $backslashes++
      continue
    }
    if ($character -eq '"') {
      [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
      [void]$builder.Append('"')
      $backslashes = 0
      continue
    }
    if ($backslashes -gt 0) {
      [void]$builder.Append(('\' * $backslashes))
      $backslashes = 0
    }
    [void]$builder.Append($character)
  }
  if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
  [void]$builder.Append('"')
  $builder.ToString()
}

function Join-WindowsCommandLine([string[]]$Arguments) {
  (@($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument $_ }) -join ' ')
}

function Normalize-AndroidShellText([string]$Text) {
  $Text.Replace("`r`n", "`n").Replace("`r", '')
}

function Stop-OwnedHostProcessTree([Diagnostics.Process]$Process) {
  if($null -eq $Process -or $Process.HasExited) { return }
  $taskkillInfo = [Diagnostics.ProcessStartInfo]::new()
  $taskkillInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
  $taskkillInfo.UseShellExecute = $false
  $taskkillInfo.CreateNoWindow = $true
  $taskkillInfo.Arguments = '/PID {0} /T /F' -f $Process.Id
  try {
    $taskkillProcess = [Diagnostics.Process]::new()
    $taskkillProcess.StartInfo = $taskkillInfo
    if($taskkillProcess.Start()) { [void]$taskkillProcess.WaitForExit(5000) }
  } catch {}
  if(-not $Process.HasExited) { try { $Process.Kill() } catch {} }
  try { [void]$Process.WaitForExit(5000) } catch {}
}

function Invoke-ProcessCapture {
  param([string]$FileName, [string[]]$Arguments, [int]$TimeoutMs = 30000)
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $FileName
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.Arguments = Join-WindowsCommandLine $Arguments
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $info
  if (-not $process.Start()) { throw "Unable to start $FileName" }
  $stdout = $process.StandardOutput.ReadToEndAsync()
  $stderr = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($TimeoutMs)) {
    Stop-OwnedHostProcessTree $process
    throw "Host command timeout: $FileName"
  }
  [pscustomobject]@{ ExitCode=$process.ExitCode; StdOut=$stdout.GetAwaiter().GetResult(); StdErr=$stderr.GetAwaiter().GetResult() }
}

function Invoke-Adb([string[]]$Arguments, [int]$TimeoutMs = 30000) {
  Invoke-ProcessCapture -FileName $Adb -Arguments (@('-s', $Serial) + $Arguments) -TimeoutMs $TimeoutMs
}

function ConvertTo-ShSingleQuoted([string]$Value) {
  $single = [string][char]39
  $double = [string][char]34
  $escape = $single + $double + $single + $double + $single
  $single + $Value.Replace($single, $escape) + $single
}

function Invoke-Root([string]$Command, [int]$TimeoutMs = 30000) {
  $androidCommand = Normalize-AndroidShellText $Command
  Invoke-Adb -Arguments @('shell', ('su -c ' + (ConvertTo-ShSingleQuoted $androidCommand))) -TimeoutMs $TimeoutMs
}

function Require([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Get-Section([string]$Text, [string]$Name) {
  $match = [regex]::Match($Text, "(?ms)^====$([regex]::Escape($Name))====\r?\n(.*?)(?=^====|\z)")
  if ($match.Success) { return $match.Groups[1].Value.Trim() }
  ''
}

function Resolve-ExactProcess([ValidateSet('pm-service', 'qcrild2')] [string]$Kind) {
  $result = Invoke-Root 'ps -A -o PID,PPID,NAME,ARGS'
  Require ($result.ExitCode -eq 0) 'Unable to list root processes'
  $resolvedProcesses = @()
  foreach ($line in ($result.StdOut -split "\r?\n")) {
    $parts = $line.Trim() -split '\s+', 4
    if ($parts.Count -ne 4 -or $parts[0] -notmatch '^\d+$') { continue }
    $item = [pscustomobject]@{ ProcessId=[int]$parts[0]; ParentProcessId=[int]$parts[1]; Name=$parts[2]; Arguments=$parts[3] }
    if ($Kind -eq 'pm-service' -and $item.Name -eq 'pm-service' -and $item.Arguments -match '^(?:/vendor/bin/)?pm-service$') { $resolvedProcesses += $item }
    if ($Kind -eq 'qcrild2' -and $item.Name -eq 'qcrild' -and $item.Arguments -match '^(?:/vendor/bin/hw/)?qcrild -c 2$') { $resolvedProcesses += $item }
  }
  if ($resolvedProcesses.Count -ne 1) { return $null }
  $resolved=$resolvedProcesses[0]
  $exeResult=Invoke-Root ("readlink /proc/{0}/exe 2>/dev/null" -f $resolved.ProcessId)
  if($exeResult.ExitCode -ne 0) { return $null }
  $resolved | Add-Member -NotePropertyName ExecutablePath -NotePropertyValue $exeResult.StdOut.Trim()
  $resolved
}

function Test-ExactPmServiceProcess($Process) {
  $null -ne $Process -and $Process.ParentProcessId -eq 1 -and $Process.Name -eq 'pm-service' -and
  $Process.Arguments -match '^(?:/vendor/bin/)?pm-service$' -and $Process.ExecutablePath -ceq '/vendor/bin/pm-service'
}

function Test-ExactQcrild2Process($Process) {
  $null -ne $Process -and $Process.ParentProcessId -eq 1 -and $Process.Name -eq 'qcrild' -and
  $Process.Arguments -match '^(?:/vendor/bin/hw/)?qcrild -c 2$' -and $Process.ExecutablePath -ceq '/vendor/bin/hw/qcrild'
}

function Resolve-OnlineSerial {
  $result = Invoke-ProcessCapture -FileName $Adb -Arguments @('devices')
  $rows = @($result.StdOut -split "\r?\n" | Where-Object { $_ -match '^\S+\s+device\s*$' } | ForEach-Object { ($_ -split '\s+')[0] })
  if ($Serial) {
    Require ($rows -contains $Serial) "Requested ADB device is not online: $Serial"
    return $Serial
  }
  Require ($rows.Count -eq 1) "Expected exactly one online ADB device, found: $($rows -join ', ')"
  $rows[0]
}

function New-NativeStateProbeCommand {
  @"
echo ====ROOT====
id
echo ====DEVICE====
getprop ro.product.device
getprop ro.product.model
getprop ro.build.fingerprint
echo ====AIRPLANE====
settings get global airplane_mode_on
echo ====PER_MGR====
getprop init.svc.vendor.per_mgr
echo ====OWNER====
lsof $DeviceNode 2>&1
echo ====X55====
cat $X55StatePath 2>&1
echo ====CRASH_COUNT====
cat $CrashCountPath 2>&1
echo ====HOLDER_FILES====
test -e $HolderPidFile && echo PRESENT:$HolderPidFile || echo ABSENT:$HolderPidFile
test -e /data/local/tmp/x55_holder.pid && echo PRESENT:/data/local/tmp/x55_holder.pid || echo ABSENT:/data/local/tmp/x55_holder.pid
test -e /data/local/tmp/x55_handoff_test.pid && echo PRESENT:/data/local/tmp/x55_handoff_test.pid || echo ABSENT:/data/local/tmp/x55_handoff_test.pid
"@
}

function Capture-NativeState([string]$Label) {
  $command = New-NativeStateProbeCommand
  $result = Invoke-Root $command
  Save-Text "native_$Label.txt" ("EXIT=$($result.ExitCode)" + [Environment]::NewLine + $result.StdOut + $result.StdErr)
  $ownerText = Get-Section $result.StdOut 'OWNER'
  [pscustomobject]@{
    Root=(Get-Section $result.StdOut 'ROOT') -match 'uid=0\(root\)'
    Device=((Get-Section $result.StdOut 'DEVICE') -split "\r?\n")[0].Trim()
    Airplane=(Get-Section $result.StdOut 'AIRPLANE').Trim()
    PerMgr=(Get-Section $result.StdOut 'PER_MGR').Trim()
    PmService=(Resolve-ExactProcess 'pm-service')
    Qcrild2=(Resolve-ExactProcess 'qcrild2')
    OwnerLines=@($ownerText -split "\r?\n" | Where-Object { $_ -match [regex]::Escape($DeviceNode) })
    X55=(Get-Section $result.StdOut 'X55').Trim().ToUpperInvariant()
    CrashCount=(Get-Section $result.StdOut 'CRASH_COUNT').Trim()
    HolderFiles=Get-Section $result.StdOut 'HOLDER_FILES'
  }
}

function Get-OwnerProcessIds([string[]]$OwnerLines) {
  @($OwnerLines | ForEach-Object {
    $ownerMatch=[regex]::Match($_,'^\S+\s+(\d+)\s+')
    if($ownerMatch.Success) { [int]$ownerMatch.Groups[1].Value }
  })
}

function Test-ExactAndroidHolderIdentityModel($Identity, [int]$ExpectedProcessId) {
  if($null -eq $Identity -or -not $Identity.PidFilePresent -or -not $Identity.ProcExists) { return $false }
  if($Identity.PidFileValue -cne $ExpectedProcessId.ToString() -or $Identity.Fd9 -cne $DeviceNode) { return $false }
  $parts=@($Identity.CommandLineParts)
  $parts.Count -eq 3 -and $parts[0] -ceq '/system/bin/sh' -and $parts[1] -ceq '-c' -and $parts[2] -ceq (New-HolderCommand)
}

function Get-AndroidHolderIdentity([int]$ProcessId) {
  $command=@"
echo ====PID_FILE====
if test -f $HolderPidFile; then echo PRESENT; cat $HolderPidFile; else echo ABSENT; fi
echo ====PROC====
if test -d /proc/$ProcessId; then echo PRESENT; else echo ABSENT; fi
echo ====CMDLINE====
if test -r /proc/$ProcessId/cmdline; then tr '\000' '\n' </proc/$ProcessId/cmdline; fi
echo ====FD9====
readlink /proc/$ProcessId/fd/9 2>/dev/null
"@
  $result=Invoke-Root $command
  $pidFileLines=@((Get-Section $result.StdOut 'PID_FILE') -split "\r?\n" | Where-Object { $_ -ne '' })
  [pscustomobject]@{
    PidFilePresent=$pidFileLines.Count -eq 2 -and $pidFileLines[0] -ceq 'PRESENT'
    PidFileValue=if($pidFileLines.Count -ge 2){$pidFileLines[1].Trim()}else{''}
    ProcExists=(Get-Section $result.StdOut 'PROC').Trim() -ceq 'PRESENT'
    CommandLineParts=@((Get-Section $result.StdOut 'CMDLINE') -split "\r?\n" | Where-Object { $_ -ne '' })
    Fd9=(Get-Section $result.StdOut 'FD9').Trim()
  }
}

function Test-ExactAndroidHolderIdentity([int]$ProcessId) {
  Test-ExactAndroidHolderIdentityModel (Get-AndroidHolderIdentity $ProcessId) $ProcessId
}

function Test-HolderSoleOwnerModel([bool]$ExactIdentity, [string[]]$OwnerLines, [int]$HolderProcessId) {
  if(-not $ExactIdentity) { return $false }
  $ids=@(Get-OwnerProcessIds $OwnerLines)
  $ids.Count -eq 1 -and $ids[0] -eq $HolderProcessId
}

function Test-HolderSoleOwner($State, [int]$HolderProcessId) {
  Test-HolderSoleOwnerModel (Test-ExactAndroidHolderIdentity $HolderProcessId) $State.OwnerLines $HolderProcessId
}

function Test-HolderPmDualOwnerModel([bool]$ExactIdentity, [string[]]$OwnerLines, [int]$HolderProcessId, $PmService) {
  if(-not $ExactIdentity -or -not (Test-ExactPmServiceProcess $PmService)) { return $false }
  $ids=@(Get-OwnerProcessIds $OwnerLines | Sort-Object)
  $expected=@(@($HolderProcessId,[int]$PmService.ProcessId) | Sort-Object)
  $ids.Count -eq 2 -and $ids[0] -eq $expected[0] -and $ids[1] -eq $expected[1]
}

function Test-HolderPmDualOwner($State, [int]$HolderProcessId) {
  Test-HolderPmDualOwnerModel (Test-ExactAndroidHolderIdentity $HolderProcessId) $State.OwnerLines $HolderProcessId $State.PmService
}

function Test-PmSoleOwnerModel([string[]]$OwnerLines, $PmService) {
  if(-not (Test-ExactPmServiceProcess $PmService)) { return $false }
  $ids=@(Get-OwnerProcessIds $OwnerLines)
  $ids.Count -eq 1 -and $ids[0] -eq $PmService.ProcessId
}

function Test-PmSoleOwner($State) {
  Test-PmSoleOwnerModel $State.OwnerLines $State.PmService
}

function Get-WfcJson([string]$Label) {
  $result = Invoke-Root "$WfcCtl status-json"
  Save-Text "wfc_$Label.txt" ($result.StdOut + [Environment]::NewLine + $result.StdErr)
  $jsonLine = @($result.StdOut -split "\r?\n" | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -Last 1)
  Require ($jsonLine.Count -eq 1) "No WFC JSON for $Label"
  $jsonLine[0] | ConvertFrom-Json
}

function Test-TargetGate($State) {
  $target=$State.target; $subscription=$State.subscription
  $target.mappingGate -eq $true -and [int]$target.subId -eq 11 -and [int]$target.slotId -eq 1 -and
  [int]$target.phoneId -eq 1 -and [int]$target.carrierId -eq 28 -and [int]$target.mcc -eq 234 -and
  [int]$target.mnc -eq 15 -and $subscription.active -eq $true -and $subscription.areUiccApplicationsEnabled -eq $true
}

function Resolve-Topology($State) {
  $slot0=$State.protectedSlot0
  if ($slot0.active -eq $true -and $slot0.mappingGate -eq $true -and [int]$slot0.subId -eq 1 -and
      [int]$slot0.slotId -eq 0 -and [int]$slot0.carrierId -eq 2237 -and [int]$slot0.mcc -eq 460 -and [int]$slot0.mnc -eq 11) { return 'DUAL_SIM' }
  if ($slot0.active -eq $false) { return 'SINGLE_SIM_SLOT0_ABSENT' }
  throw 'slot0 topology is neither protected dual-SIM nor confirmed absent'
}

function Test-Healthy($State) {
  [int]$State.ims.registrationStateRaw -eq 2 -and [int]$State.ims.registrationTransportRaw -eq 2 -and
  $State.mmtel.voiceIwlanAvailable -eq $true -and $State.wfc.wifiCallingAvailable -eq $true
}

function Wait-Until([scriptblock]$Condition, [int]$Seconds, [string]$Description) {
  $deadline=(Get-Date).AddSeconds($Seconds)
  do {
    if (& $Condition) { Write-Log "WAIT PASS $Description"; return $true }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  Write-Log "WAIT FAIL $Description"
  $false
}

function Read-PonSuccess([string]$Label) {
  $result=Invoke-Root 'cat /sys/kernel/debug/ipc_logging/esoc-mdm/log 2>&1'
  $lines=@($result.StdOut -split "\r?\n" | Where-Object { $_ -match 'PON_SUCCESS' })
  Save-Text "pon_success_$Label.txt" ($lines -join [Environment]::NewLine)
  if ($lines.Count -eq 0) { return '' }
  $lines[-1]
}

function New-HolderCommand {
  'echo $$ > {0}; trap ''rm -f {0}'' EXIT; exec 9<{1} || exit 71; trap ''exit 0'' TERM INT HUP; while :; do sleep 60; done' -f $HolderPidFile,$DeviceNode
}

function Start-OwnedHolder {
  $holderCommand=Normalize-AndroidShellText (New-HolderCommand)
  $info=[Diagnostics.ProcessStartInfo]::new()
  $info.FileName=$Adb; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
  $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
  $info.Arguments=Join-WindowsCommandLine @('-s',$Serial,'shell',('su -c '+(ConvertTo-ShSingleQuoted $holderCommand)))
  $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
  Require ($process.Start()) 'Unable to start holder ADB process'
  Write-Log "holder host process=$($process.Id)"
  $process
}

function Get-HolderAndroidProcessId {
  $result=Invoke-Root "cat $HolderPidFile 2>/dev/null"
  $value=$result.StdOut.Trim()
  if($value -match '^\d+$') { return [int]$value }
  $null
}

function Test-AndroidProcessAbsent([int]$ProcessId) {
  (Invoke-Root ("test ! -d /proc/{0}" -f $ProcessId)).ExitCode -eq 0
}

function Stop-OwnedHolder {
  if($null -eq $script:HolderAndroidProcessId -or $script:HolderTermSent) { return }
  Require (Test-ExactAndroidHolderIdentity $script:HolderAndroidProcessId) 'FAILSAFE_HOLDER_IDENTITY_UNPROVEN'
  $script:HolderTermSent=$true
  $result=Invoke-Root "kill -TERM $($script:HolderAndroidProcessId)"
  $script:PhoneWrites++
  Save-Text 'holder_term.txt' ($result.StdOut+$result.StdErr)
  Require ($result.ExitCode -eq 0) 'Holder TERM failed'
  Require (Wait-Until { Test-AndroidProcessAbsent $script:HolderAndroidProcessId } 10 'exact holder exit') 'Holder did not exit'
  $left=Get-HolderAndroidProcessId
  if($null -ne $left) {
    Require ($left -eq $script:HolderAndroidProcessId) 'Unexpected holder PID file content'
    Save-Text 'holder_pidfile_status.txt' 'STALE_PIDFILE'
    throw 'STALE_PIDFILE'
  }
}

function Stop-PerMgr {
  $result=Invoke-Root 'setprop ctl.stop vendor.per_mgr'
  $script:PhoneWrites++; $script:PerMgrWasStopped=$true
  Save-Text 'per_mgr_stop.txt' ($result.StdOut+$result.StdErr)
}
function Start-PerMgr {
  $result=Invoke-Root 'setprop ctl.start vendor.per_mgr'
  $script:PhoneWrites++
  Save-Text 'per_mgr_start.txt' ($result.StdOut+$result.StdErr)
}
function Ensure-PerMgrRunning {
  if((Invoke-Root 'getprop init.svc.vendor.per_mgr').StdOut.Trim() -ne 'running') {
    $result=Invoke-Root 'setprop ctl.start vendor.per_mgr'
    $script:PhoneWrites++
    Save-Text 'failsafe_per_mgr_start.txt' ($result.StdOut+$result.StdErr)
  }
  $script:PerMgrWasStopped=$false
}
function Get-Sha256Hex([string]$Path) {
  Require (Test-Path -LiteralPath $Path -PathType Leaf) "Hash input missing: $Path"
  $stream=$null
  $sha=$null
  try {
    $stream=[IO.File]::OpenRead($Path)
    $sha=[Security.Cryptography.SHA256]::Create()
    $bytes=$sha.ComputeHash($stream)
    ([BitConverter]::ToString($bytes)).Replace('-','').ToUpperInvariant()
  } finally {
    if($null -ne $sha) { $sha.Dispose() }
    if($null -ne $stream) { $stream.Dispose() }
  }
}

function Assert-LocalArtifact([string]$Path,[string]$ExpectedHash) {
  Require (Test-Path -LiteralPath $Path -PathType Leaf) "Missing local audited artifact: $Path"
  $actualHash=Get-Sha256Hex $Path
  Require ($actualHash -ceq $ExpectedHash) "Artifact hash mismatch: $Path"
}

function Deploy-File([string]$LocalPath,[string]$RemoteName,[string]$ExpectedHash) {
  $stage="/data/local/tmp/$RemoteName.v27-stage"
  $push=Invoke-Adb @('push',$LocalPath,$stage) 60000
  $script:PhoneWrites++
  Require ($push.ExitCode -eq 0) "ADB push failed: $RemoteName"
  $install=Invoke-Root "mkdir -p $DeviceWorkDir && cp $stage $DeviceWorkDir/$RemoteName && chmod 0700 $DeviceWorkDir/$RemoteName && rm -f $stage"
  $script:PhoneWrites++
  Require ($install.ExitCode -eq 0) "Install failed: $RemoteName"
  Require ((Invoke-Root "sha256sum $DeviceWorkDir/$RemoteName").StdOut.ToUpperInvariant().Contains($ExpectedHash)) "Device hash mismatch: $RemoteName"
}

function Invoke-SimHelper([string]$HelperClass,[string]$HelperJar,[ValidateSet('DRY_RUN','ARM_ROLLBACK')][string]$Command) {
  Invoke-Root "LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH=$DeviceWorkDir/$HelperJar app_process /system/bin $HelperClass $Command" 60000
}

function Start-OneShotSimCycle([string]$RemoteScript) {
  $prepare=Invoke-Root "rm -f $DeviceWorkDir/cycle.done $DeviceWorkDir/cycle.result $DeviceWorkDir/cycle.log $DeviceWorkDir/cycle.stdout"
  $script:PhoneWrites++
  Require ($prepare.ExitCode -eq 0) 'Unable to clear cycle markers'
  $start=Invoke-Root "X55_V27_MODE=1 X55_V27_EXECUTE=YES nohup /system/bin/sh $DeviceWorkDir/$RemoteScript >$DeviceWorkDir/cycle.stdout 2>&1 </dev/null &"
  $script:PhoneWrites++
  Require ($start.ExitCode -eq 0) 'Unable to start one-shot SIM cycle'
}

function Start-LogcatCapture {
  Start-Process -FilePath $Adb -ArgumentList @('-s',$Serial,'logcat','-b','all','-v','threadtime') -RedirectStandardOutput $RawLogcat -RedirectStandardError (Join-Path $RunDir 'logcat_stderr.txt') -WindowStyle Hidden -PassThru
}
function Stop-LogcatCapture {
  if($null -ne $script:LogcatProcess -and -not $script:LogcatProcess.HasExited) {
    try { Stop-OwnedHostProcessTree $script:LogcatProcess } catch {}
  }
  if(Test-Path -LiteralPath $RawLogcat) {
    $pattern='PerMgrLib|PerMgrSrv|QCRIL|qcrild|SDX55M|vote|PeripheralManager|PON_SUCCESS|RADIO_NOT_AVAILABLE|IMS|IWLAN|ePDG|XFRM'
    $filtered=Get-Content -LiteralPath $RawLogcat | Where-Object { $_ -match $pattern } | ForEach-Object { [regex]::Replace($_.TrimEnd(),'[0-9]{12,}','[REDACTED]') }
    [IO.File]::WriteAllLines($FilteredLogcat,@($filtered),[Text.UTF8Encoding]::new($false))
  }
}

function Invoke-StaticNoAdbSelfTest {
  Require (-not $Execute) 'StaticNoAdb cannot be combined with Execute'
  Require ($PSVersionTable.PSVersion.Major -eq 5) 'StaticNoAdb must run under Windows PowerShell 5.1'
  $parseTokens=$null
  $parseErrors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$parseTokens,[ref]$parseErrors)
  Require ($parseErrors.Count -eq 0) 'Windows PowerShell 5.1 parser errors found'

  $sourceText=[IO.File]::ReadAllText($PSCommandPath)
  $automaticAssignmentPattern='(?im)(?<![A-Za-z0-9_])\$(?:PID|Matches|Error|Args|Input|Home|Host|Null|True|False)(?![A-Za-z0-9_])\s*(?:\+\+|--|\+=|-=|=)'
  $automaticAssignments=[regex]::Matches($sourceText,$automaticAssignmentPattern)
  Require ($automaticAssignments.Count -eq 0) 'PowerShell automatic variable used as custom state'
  $forbiddenMatchesToken=([string][char]36) + 'matches'
  Require ($sourceText.IndexOf($forbiddenMatchesToken,[StringComparison]::OrdinalIgnoreCase) -lt 0) 'Custom Matches variable remains'
  $legacyHashToken='Get' + '-File' + 'Hash'
  $legacyHashDependencyCount=([regex]::Matches($sourceText,[regex]::Escape($legacyHashToken),[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Count
  Require ($legacyHashDependencyCount -eq 0) 'Legacy hash cmdlet dependency remains'

  $knownVectorPath=Join-Path ([IO.Path]::GetTempPath()) ('v27-sha256-' + [guid]::NewGuid().ToString('N') + '.bin')
  try {
    [IO.File]::WriteAllBytes($knownVectorPath,[byte[]](0x61,0x62,0x63))
    $knownVectorHash=Get-Sha256Hex $knownVectorPath
    Require ($knownVectorHash -ceq 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') 'SHA-256 known vector mismatch'
  } finally {
    if(Test-Path -LiteralPath $knownVectorPath) { Remove-Item -LiteralPath $knownVectorPath -Force }
  }

  Assert-LocalArtifact $SingleHelperLocal $SingleHelperHash
  $singleHelperActualHash=Get-Sha256Hex $SingleHelperLocal
  Require (Test-Path -LiteralPath $SingleOrchestrator -PathType Leaf) "Single-SIM orchestrator missing: $SingleOrchestrator"
  $singleOrchestratorActualHash=Get-Sha256Hex $SingleOrchestrator

  $androidPayloads=[ordered]@{
    ReadOnlyStateProbe=(New-NativeStateProbeCommand)
    HolderLaunch=(New-HolderCommand)
    HolderPidRead="cat $HolderPidFile 2>/dev/null"
    HolderIdentityProbe=('test -d /proc/{0}; tr ''\000'' ''\n'' </proc/{0}/cmdline; readlink /proc/{0}/fd/9' -f 4242)
    HolderTermination='kill -TERM 4242'
    OwnerProbe="lsof $DeviceNode 2>&1"
    X55Probe="cat $X55StatePath 2>&1; cat $CrashCountPath 2>&1"
    SimPowerHelper="LAB_MODE=1 LAB_EXECUTE=YES CLASSPATH=$DeviceWorkDir/single-sim-slot1-power-helper.jar app_process /system/bin SingleSimSlot1PowerHelper ARM_ROLLBACK"
    SimCycleStart="X55_V27_MODE=1 X55_V27_EXECUTE=YES nohup /system/bin/sh $DeviceWorkDir/v27_sim_cycle_single.sh >$DeviceWorkDir/cycle.stdout 2>&1 </dev/null &"
  }
  $androidPayloadCrCount=0
  foreach($payloadName in $androidPayloads.Keys) {
    $normalizedPayload=Normalize-AndroidShellText ([string]$androidPayloads[$payloadName])
    $androidPayloadCrCount += ([regex]::Matches($normalizedPayload,"`r")).Count
    Require (-not $normalizedPayload.Contains("`r")) "Android payload contains CR after normalization: $payloadName"
  }
  Require ($androidPayloadCrCount -eq 0) 'Android payload CR count is not zero'
  Require ((Normalize-AndroidShellText "alpha`r`nbeta`rgamma") -ceq "alpha`nbetagamma") 'Android LF normalization behavior mismatch'
  Require ($androidPayloads.HolderLaunch.Contains('echo $$ >') -and $androidPayloads.HolderLaunch.Contains("exec 9<$DeviceNode") -and $androidPayloads.HolderLaunch.Contains('while :; do sleep 60; done')) 'Holder command construction mismatch'
  Require ($androidPayloads.SimPowerHelper.Contains('SingleSimSlot1PowerHelper ARM_ROLLBACK') -and $androidPayloads.SimCycleStart.Contains('v27_sim_cycle_single.sh')) 'SIM command construction mismatch'
  $exactCleanupArguments='/PID {0} /T /F' -f 4242
  Require ($exactCleanupArguments -ceq '/PID 4242 /T /F') 'Exact process cleanup command construction mismatch'

  $modelHolderProcessId=4242
  $modelPmProcessId=5252
  $modelHolderCommand=New-HolderCommand
  $modelIdentity=[pscustomobject]@{
    PidFilePresent=$true
    PidFileValue='4242'
    ProcExists=$true
    CommandLineParts=@('/system/bin/sh','-c',$modelHolderCommand)
    Fd9=$DeviceNode
    HostProcessPresent=$false
  }
  $modelPmService=[pscustomobject]@{
    ProcessId=$modelPmProcessId
    ParentProcessId=1
    Name='pm-service'
    Arguments='/vendor/bin/pm-service'
    ExecutablePath='/vendor/bin/pm-service'
  }
  $holderOwnerLine="holder $modelHolderProcessId root 9r CHR 0,0 0t0 1 $DeviceNode"
  $pmOwnerLine="pm-service $modelPmProcessId root 9r CHR 0,0 0t0 1 $DeviceNode"
  $thirdOwnerLine="unknown 6262 root 9r CHR 0,0 0t0 1 $DeviceNode"
  $holderIdentityModel=Test-ExactAndroidHolderIdentityModel $modelIdentity $modelHolderProcessId
  $holderSoleModel=Test-HolderSoleOwnerModel $holderIdentityModel @($holderOwnerLine) $modelHolderProcessId
  $dualOwnerModel=Test-HolderPmDualOwnerModel $holderIdentityModel @($holderOwnerLine,$pmOwnerLine) $modelHolderProcessId $modelPmService
  $pmSoleModel=Test-PmSoleOwnerModel @($pmOwnerLine) $modelPmService
  $unknownThirdRejected=-not (Test-HolderPmDualOwnerModel $holderIdentityModel @($holderOwnerLine,$pmOwnerLine,$thirdOwnerLine) $modelHolderProcessId $modelPmService)
  $hostAbsentIdentityModel=(-not $modelIdentity.HostProcessPresent) -and (Test-ExactAndroidHolderIdentityModel $modelIdentity $modelHolderProcessId)
  $badFdIdentity=[pscustomobject]@{ PidFilePresent=$true; PidFileValue='4242'; ProcExists=$true; CommandLineParts=@('/system/bin/sh','-c',$modelHolderCommand); Fd9='/dev/null' }
  $badCommandIdentity=[pscustomobject]@{ PidFilePresent=$true; PidFileValue='4242'; ProcExists=$true; CommandLineParts=@('/system/bin/sh','-c','sleep 60'); Fd9=$DeviceNode }
  Require $holderIdentityModel 'case A exact holder identity failed'
  Require $holderSoleModel 'case B holder sole-owner model failed'
  Require $dualOwnerModel 'case C exact dual-owner model failed'
  Require $pmSoleModel 'case D pm-service sole-owner model failed'
  Require $unknownThirdRejected 'case E unknown third owner was accepted'
  Require (-not (Test-ExactAndroidHolderIdentityModel $badFdIdentity $modelHolderProcessId)) 'case F wrong FD9 was accepted'
  Require (-not (Test-ExactAndroidHolderIdentityModel $badCommandIdentity $modelHolderProcessId)) 'case F wrong command was accepted'
  Require $hostAbsentIdentityModel 'case G host-process absence invalidated Android holder identity'

  $qcrild2RestartToken='setprop ctl.'+'restart vendor.qcrild2'
  $qcrild2RestartCount=([regex]::Matches($sourceText,[regex]::Escape($qcrild2RestartToken))).Count
  Require ($qcrild2RestartCount -eq 0) 'qcrild2 restart remains in production path'
  $stopPerMgrIndex=[regex]::Match($sourceText,'(?m)^  Stop-PerMgr\r?$').Index
  $holderStartIndex=[regex]::Match($sourceText,'(?m)^  \$script:HolderHostProcess=Start-OwnedHolder\r?$').Index
  $startPerMgrIndex=[regex]::Match($sourceText,'(?m)^  Start-PerMgr\r?$').Index
  $dualGateIndex=[regex]::Match($sourceText,'(?m)^  \$dualOwnerReady=Wait-Until \{\r?$').Index
  $holderTermIndex=[regex]::Match($sourceText,'(?m)^  Stop-OwnedHolder\r?$').Index
  $pmSoleGateIndex=[regex]::Match($sourceText,'(?m)^  \$pmSoleReady=Wait-Until \{\r?$').Index
  $handoffSuccessIndex=[regex]::Match($sourceText,'(?m)^  \$script:NativeHandoffResult=''MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS''\r?$').Index
  $simCycleIndex=[regex]::Match($sourceText,'(?m)^    Start-OneShotSimCycle \$orchestratorRemote\r?$').Index
  $stateMachineOrder=$stopPerMgrIndex -gt 0 -and $stopPerMgrIndex -lt $holderStartIndex -and
    $holderStartIndex -lt $startPerMgrIndex -and $startPerMgrIndex -lt $dualGateIndex -and
    $dualGateIndex -lt $holderTermIndex -and $holderTermIndex -lt $pmSoleGateIndex -and
    $pmSoleGateIndex -lt $handoffSuccessIndex -and $handoffSuccessIndex -lt $simCycleIndex
  Require $stateMachineOrder 'make-before-break state-machine order mismatch'

  $childScript = Join-Path ([IO.Path]::GetTempPath()) ('v27-ps51-argv-' + [guid]::NewGuid().ToString('N') + '.ps1')
  $childSource = @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Values)
foreach($value in $Values) {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($value))
}
'@
  $expected = @(
    'plain',
    'space value',
    'single''quote',
    'double"quote',
    'trailing\',
    ('su -c ' + (ConvertTo-ShSingleQuoted (Normalize-AndroidShellText (New-HolderCommand)))),
    ('su -c ' + (ConvertTo-ShSingleQuoted (Normalize-AndroidShellText (New-NativeStateProbeCommand))))
  )
  try {
    [IO.File]::WriteAllText($childScript,$childSource,[Text.UTF8Encoding]::new($false))
    $child = Invoke-ProcessCapture -FileName (Join-Path $PSHOME 'powershell.exe') -Arguments (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$childScript) + $expected)
    Require ($child.ExitCode -eq 0) "PS5.1 argv child failed: $($child.StdErr)"
    $actual = @($child.StdOut -split "\r?\n" | Where-Object { $_ -ne '' } | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
    Require ($actual.Count -eq $expected.Count) 'PS5.1 argv round-trip count mismatch'
    for($index=0; $index -lt $expected.Count; $index++) {
      Require ($actual[$index] -ceq $expected[$index]) "PS5.1 argv round-trip mismatch at index $index"
    }
  } finally {
    if(Test-Path -LiteralPath $childScript) { Remove-Item -LiteralPath $childScript -Force }
  }
  Write-Host "WINDOWS_POWERSHELL_VERSION=$($PSVersionTable.PSVersion.ToString())"
  Write-Host 'PS51_PARSE=PASS'
  Write-Host 'AUTO_VARIABLE_AUDIT=PASS'
  Write-Host 'CUSTOM_MATCHES_VARIABLES=0'
  Write-Host 'ANDROID_LF_NORMALIZATION=PASS'
  Write-Host "ANDROID_PAYLOAD_CR_COUNT=$androidPayloadCrCount"
  Write-Host 'DOTNET_SHA256_KNOWN_VECTOR=PASS'
  Write-Host 'LOCAL_HASH_ENGINE=DOTNET_SHA256'
  Write-Host 'LOCAL_HASH_ENGINE_SELFTEST=PASS'
  Write-Host "GET_FILE_HASH_DEPENDENCY_COUNT=$legacyHashDependencyCount"
  Write-Host 'SINGLE_SIM_HELPER_PRESENT=YES'
  Write-Host "SINGLE_SIM_HELPER_SHA256=$singleHelperActualHash"
  Write-Host 'SINGLE_SIM_HELPER_HASH_MATCH=YES'
  Write-Host 'SINGLE_ORCHESTRATOR_PRESENT=YES'
  Write-Host "SINGLE_ORCHESTRATOR_SHA256=$singleOrchestratorActualHash"
  Write-Host 'ARTIFACT_GATE=PASS'
  Write-Host 'HOLDER_COMMAND_BUILD=PASS'
  Write-Host 'SIM_COMMAND_BUILD=PASS'
  Write-Host 'HOLDER_IDENTITY_MODEL=PASS'
  Write-Host 'HOLDER_SOLE_MODEL=PASS'
  Write-Host 'DUAL_OWNER_MODEL=PASS'
  Write-Host 'PM_SOLE_MODEL=PASS'
  Write-Host 'UNKNOWN_THIRD_OWNER_REJECTED=PASS'
  Write-Host 'HOST_PROCESS_ABSENT_IDENTITY_MODEL=PASS'
  Write-Host 'MAKE_BEFORE_BREAK_STATE_MACHINE=PASS'
  Write-Host "QCRILD2_RESTARTS_IN_NEW_PATH=$qcrild2RestartCount"
  Write-Host 'SIM_OFF_MAX=1'
  Write-Host 'SIM_ON_MAX=1'
  Write-Host 'STATE_MACHINE_ORDER=ENTRY>STOP_PER_MGR>HOLDER_SOLE>X55_REBIRTH>START_PER_MGR>DUAL_OWNER>EXACT_TERM>PM_SOLE>WFC_CHECK>OPTIONAL_ONE_SIM_CYCLE'
  Write-Host 'STATIC_NO_ADB=PASS'
  Write-Host 'WINDOWS_ARGUMENT_ROUNDTRIP=PASS'
  Write-Host 'PHONE_WRITES=0'
}

if($StaticNoAdb) {
  Invoke-StaticNoAdbSelfTest
  return
}

[IO.Directory]::CreateDirectory($RunDir)|Out-Null
Write-Log "version=$Version execute=$Execute"
try {
  Require (Test-Path -LiteralPath $Adb) "adb.exe not found: $Adb"
  $Serial=Resolve-OnlineSerial
  $entry=Capture-NativeState 'entry'
  $entryWfc=Get-WfcJson 'entry'
  $topology=Resolve-Topology $entryWfc
  Require $entry.Root 'root UID 0 gate failed'
  Require ($entry.Device -eq 'cas') "unexpected device: $($entry.Device)"
  Require ($entry.Airplane -eq '1') 'airplane mode must be ON'
  Require ($entry.PerMgr -eq 'running') 'vendor.per_mgr is not running'
  Require (Test-ExactPmServiceProcess $entry.PmService) 'pm-service identity failed'
  Require (Test-PmSoleOwner $entry) 'pm-service is not sole native owner'
  Require ($entry.X55 -eq 'ONLINE' -and $entry.CrashCount -eq '0') 'X55 ONLINE/crash gate failed'
  Require ($entry.HolderFiles -notmatch '(?m)^PRESENT:') 'holder file already exists'
  Require (Test-ExactQcrild2Process $entry.Qcrild2) 'fixed qcrild2 identity failed'
  $entryQcrild2ProcessId=$entry.Qcrild2.ProcessId
  Require (Test-TargetGate $entryWfc) 'VOXI active/UICC/mapping gate failed'

  if($topology -eq 'DUAL_SIM') {
    $helperLocal=$DualHelperLocal; $helperHash=$DualHelperHash; $helperClass='Slot1SimPowerHelper'
    $helperJar='slot1-sim-power-helper.jar'; $orchestratorLocal=$DualOrchestrator; $orchestratorRemote='v27_sim_cycle_dual.sh'
  } else {
    $helperLocal=$SingleHelperLocal; $helperHash=$SingleHelperHash; $helperClass='SingleSimSlot1PowerHelper'
    $helperJar='single-sim-slot1-power-helper.jar'; $orchestratorLocal=$SingleOrchestrator; $orchestratorRemote='v27_sim_cycle_single.sh'
  }
  Assert-LocalArtifact $helperLocal $helperHash
  Require (Test-Path -LiteralPath $orchestratorLocal) 'orchestrator missing'
  $initialPon=Read-PonSuccess 'entry'
  Write-Log "ENTRY_GATE=PASS topology=$topology initialF1Allowed=true"

  if(-not $Execute) {
    Write-Log 'DRY_RUN=PASS phone_writes=0'
    Write-Host 'DRY RUN ONLY. Real execution requires the fixed confirmation token.'
    return
  }
  Require ($Confirmation -eq 'EXECUTE-V2.7-ALPHA-NATIVE-HANDOFF') 'confirmation token missing'
  $script:LogcatProcess=Start-LogcatCapture

  Stop-PerMgr
  Require (Wait-Until { (Invoke-Root 'getprop init.svc.vendor.per_mgr').StdOut.Trim() -eq 'stopped' -and $null -eq (Resolve-ExactProcess 'pm-service') } 15 'per_mgr stopped') 'per_mgr stop failed'
  $afterStop=Capture-NativeState 'after_per_mgr_stop'
  Require ($afterStop.OwnerLines.Count -eq 0 -and $afterStop.X55 -eq 'OFFLINE' -and $afterStop.CrashCount -eq '0') 'post-stop state mismatch'

  $script:HolderHostProcess=Start-OwnedHolder
  $script:PhoneWrites++
  Require (Wait-Until {
    $script:HolderAndroidProcessId=Get-HolderAndroidProcessId
    if($null -eq $script:HolderAndroidProcessId) { return $false }
    $holderState=Capture-NativeState 'holder_identity_wait'
    (Test-HolderSoleOwner $holderState $script:HolderAndroidProcessId)
  } 15 'exact holder sole ownership') 'holder failed'

  Require (Wait-Until { $state=Capture-NativeState 'holder_wait'; $state.X55 -eq 'ONLINE' -and $state.CrashCount -eq '0' } 15 'holder X55 ONLINE') 'holder X55 gate failed'
  $holderPon=Read-PonSuccess 'holder'
  Require ($holderPon -and $holderPon -ne $initialPon) 'new PON_SUCCESS missing'
  $script:RecoveryResult='X55_REBIRTH_SUCCESS'

  Start-PerMgr
  Require (Wait-Until { (Invoke-Root 'getprop init.svc.vendor.per_mgr').StdOut.Trim() -eq 'running' } 15 'per_mgr contended start') 'per_mgr start failed'
  $script:PerMgrWasStopped=$false
  $dualOwnerReady=Wait-Until {
    $contended=Capture-NativeState 'holder_plus_per_mgr_wait'
    (Test-HolderPmDualOwner $contended $script:HolderAndroidProcessId) -and
      $contended.PerMgr -eq 'running' -and $contended.X55 -eq 'ONLINE' -and $contended.CrashCount -eq '0' -and
      (Test-ExactQcrild2Process $contended.Qcrild2) -and $contended.Qcrild2.ProcessId -eq $entryQcrild2ProcessId
  } 15 'holder plus pm-service dual ownership'
  if(-not $dualOwnerReady) {
    $script:NativeHandoffResult='EXPECTED_DUAL_OWNER_NOT_FORMED'
    throw 'expected exact dual-owner state did not form; refusing holder release'
  }

  Stop-OwnedHolder
  $pmSoleReady=Wait-Until {
    $released=Capture-NativeState 'post_break_wait'
    (Test-PmSoleOwner $released) -and $released.PerMgr -eq 'running' -and
      $released.HolderFiles -notmatch '(?m)^PRESENT:' -and
      (Test-ExactQcrild2Process $released.Qcrild2) -and $released.Qcrild2.ProcessId -eq $entryQcrild2ProcessId
  } 15 'pm-service sole ownership after exact holder TERM'
  if(-not $pmSoleReady) {
    $script:NativeHandoffResult='POST_BREAK_NATIVE_OWNER_INVALID'
    $script:CleanupResult='HOLDER_RELEASED_NATIVE_OWNER_INVALID'
    throw 'post-break pm-service sole-owner gate failed; SIM cycle forbidden'
  }
  $released=Capture-NativeState 'post_break_verified'
  if($released.X55 -ne 'ONLINE' -or $released.CrashCount -ne '0') {
    $script:NativeHandoffResult='POST_BREAK_X55_REGRESSION'
    $script:CleanupResult='NATIVE_OWNER_PRESENT_X55_REGRESSED'
    throw 'X55 regressed after exact holder release; SIM cycle forbidden'
  }

  $script:NativeHandoffResult='MAKE_BEFORE_BREAK_NATIVE_HANDOFF_SUCCESS'
  $script:CleanupResult='NATIVE_CLEAN'
  Start-Sleep -Seconds 10
  Read-PonSuccess 'post_handoff'|Out-Null
  $postHandoff=Get-WfcJson 'post_handoff_10s'
  if(Test-Healthy $postHandoff) {
    $script:FinalWfcResult='HEALTHY'
  } else {
    $cycleGate=Get-WfcJson 'pre_sim_cycle'
    Require (Test-TargetGate $cycleGate) 'VOXI gate failed before SIM cycle'
    Require ((Resolve-Topology $cycleGate) -eq $topology) 'topology changed before SIM cycle'
    Deploy-File $helperLocal $helperJar $helperHash
    $orchestratorHash=Get-Sha256Hex $orchestratorLocal
    Deploy-File $orchestratorLocal $orchestratorRemote $orchestratorHash
    $dry=Invoke-SimHelper $helperClass $helperJar 'DRY_RUN'
    Save-Text 'sim_helper_dry_run.txt' ($dry.StdOut+$dry.StdErr)
    Require ($dry.ExitCode -eq 0 -and $dry.StdOut -match 'result=DRY_RUN_ZERO_WRITE') 'SIM helper dry-run failed'
    $arm=Invoke-SimHelper $helperClass $helperJar 'ARM_ROLLBACK'
    $script:PhoneWrites++
    Save-Text 'sim_helper_arm.txt' ($arm.StdOut+$arm.StdErr)
    Require ($arm.ExitCode -eq 0 -and $arm.StdOut -match 'result=ROLLBACK_ARMED') 'SIM arm failed'
    Start-OneShotSimCycle $orchestratorRemote
    Require (Wait-Until { (Invoke-Root "test -f $DeviceWorkDir/cycle.done").ExitCode -eq 0 } 40 'SIM cycle complete') 'SIM cycle timeout'
    $cycleResult=Invoke-Root "cat $DeviceWorkDir/cycle.result $DeviceWorkDir/cycle.log $DeviceWorkDir/cycle.stdout 2>&1"
    Save-Text 'sim_cycle_result.txt' ($cycleResult.StdOut+$cycleResult.StdErr)
    Require ($cycleResult.StdOut -match 'RESULT=SUCCESS') 'single SIM cycle failed'

    $healthy=$false
    foreach($second in 0,3,6,9,12,15,18,21,24,27,30) {
      if($second -gt 0) { Start-Sleep -Seconds 3 }
      $sample=Get-WfcJson ("post_cycle_{0:D2}s" -f $second)
      $native=Capture-NativeState ("post_cycle_{0:D2}s" -f $second)
      Require ($native.X55 -eq 'ONLINE' -and $native.CrashCount -eq '0') 'X55 regressed after SIM cycle'
      Require (Test-PmSoleOwner $native) 'owner regressed after SIM cycle'
      Require ((Test-ExactQcrild2Process $native.Qcrild2) -and $native.Qcrild2.ProcessId -eq $entryQcrild2ProcessId) 'qcrild2 changed after SIM cycle'
      if(Test-Healthy $sample) { $healthy=$true; Write-Log "WFC HEALTHY at $($second)s"; break }
    }
    if($healthy) { $script:FinalWfcResult='HEALTHY' } else {
      $script:FinalWfcResult='FAILED_AFTER_ONE_SIM_CYCLE'
      throw 'WFC failed after one SIM cycle'
    }
  }
} catch {
  $script:Failure=$_.Exception.Message
  Write-Log "ERROR=$($script:Failure)"
} finally {
  if($null -eq $script:HolderAndroidProcessId -and $null -ne $script:HolderHostProcess) { $script:HolderAndroidProcessId=Get-HolderAndroidProcessId }
  if($null -ne $script:HolderAndroidProcessId -and -not $script:HolderTermSent) {
    try { Stop-OwnedHolder } catch { Write-Log "FAILSAFE_HOLDER_ERROR=$($_.Exception.Message)" }
  }
  if($null -ne $script:HolderHostProcess -and -not $script:HolderHostProcess.HasExited) {
    try { Stop-OwnedHostProcessTree $script:HolderHostProcess } catch {}
  }
  if($script:PerMgrWasStopped) {
    try { Ensure-PerMgrRunning } catch { Write-Log "FAILSAFE_PER_MGR_ERROR=$($_.Exception.Message)" }
  }
  Stop-LogcatCapture
  if(Test-Path -LiteralPath $FilteredLogcat) {
    $evidenceText=[IO.File]::ReadAllText($FilteredLogcat)
    $requiredEvidence=@('PerMgrLib: QCRIL successfully registered for SDX55M','PerMgrLib: QCRIL voting for SDX55M','PerMgrSrv: QCRIL registered','PerMgrSrv: QCRIL voting for SDX55M')
    $missingEvidence=@($requiredEvidence | Where-Object { -not $evidenceText.Contains($_) })
    $script:RevoteEvidence=if($missingEvidence.Count -eq 0){'PROVEN'}else{'UNPROVEN'}
  }
  Write-Host "RECOVERY_RESULT=$($script:RecoveryResult)"
  Write-Host "NATIVE_HANDOFF_RESULT=$($script:NativeHandoffResult)"
  Write-Host "FINAL_WFC_RESULT=$($script:FinalWfcResult)"
  Write-Host "CLEANUP_RESULT=$($script:CleanupResult)"
  Write-Host "REVOTE_MECHANISM_LOG=$($script:RevoteEvidence)"
  Write-Host "PHONE_WRITE_ACTIONS=$($script:PhoneWrites)"
  Write-Host "LOG_DIR=$RunDir"
}
if($null -ne $script:Failure) { throw $script:Failure }
