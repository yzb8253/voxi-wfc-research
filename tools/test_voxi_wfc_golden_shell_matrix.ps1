[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Fixtures = @(
  Join-Path $Repo 'tools\test_voxi_wfc_golden_owner_preflight.sh'
  Join-Path $Repo 'tools\test_voxi_wfc_golden_selftest.sh'
)
$GitUsrBin = 'C:\Program Files\Git\usr\bin'
$GitBin = 'C:\Program Files\Git\bin'
$GitMingwBin = 'C:\Program Files\Git\mingw64\bin'
$env:PATH = "$GitUsrBin;$GitMingwBin;$env:PATH"
$Candidates = @(
  @{ Name='SH'; Path=(Join-Path $GitBin 'sh.exe'); Prefix=@() },
  @{ Name='BASH'; Path=(Join-Path $GitBin 'bash.exe'); Prefix=@() },
  @{ Name='DASH'; Path=(Join-Path $GitUsrBin 'dash.exe'); Prefix=@() },
  @{ Name='BUSYBOX_ASH'; Path=''; Prefix=@('sh') },
  @{ Name='MKSH'; Path=''; Prefix=@() }
)
$Modes = @(
  @{ Name='ERREXIT_OFF_NOUNSET_OFF'; Args=@() },
  @{ Name='ERREXIT_ON_NOUNSET_OFF'; Args=@('-e') },
  @{ Name='ERREXIT_OFF_NOUNSET_ON'; Args=@('-u') },
  @{ Name='ERREXIT_ON_NOUNSET_ON'; Args=@('-eu') }
)

$tested = 0
foreach($candidate in $Candidates) {
  $path = $candidate.Path
  if([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
    Write-Host "SHELL_MATRIX_$($candidate.Name)=SKIPPED unavailable"
    continue
  }
  foreach($fixture in $Fixtures) {
    $fixtureName = [IO.Path]::GetFileNameWithoutExtension($fixture)
    $baseline = $null
    foreach($mode in $Modes) {
      $args = @($candidate.Prefix) + @($mode.Args) + @($fixture)
      $output = @(& $path @args 2>&1)
      $rc = $LASTEXITCODE
      if($rc -ne 0) { throw "$($candidate.Name)/$($mode.Name)/$(Split-Path $fixture -Leaf) rc=$rc output=$($output -join '; ')" }
      $joined = $output -join "`n"
      if($joined -notmatch 'OWNER_PREFLIGHT_FIXTURES=8/8 PASS|RC1_SELFTEST_FIXTURE=PASS') {
        throw "$($candidate.Name)/$($mode.Name)/$(Split-Path $fixture -Leaf) missing fixture PASS"
      }
      if($null -eq $baseline) { $baseline = $joined }
      elseif($joined -ne $baseline) { throw "$($candidate.Name)/$($mode.Name)/$(Split-Path $fixture -Leaf) output drift" }
      Write-Host "SHELL_MODE_$($candidate.Name)_$($mode.Name)_$fixtureName=PASS"
    }
  }
  $tested++
  Write-Host "SHELL_MATRIX_$($candidate.Name)=PASS modes=4 fixtures=$($Fixtures.Count)"
}
if($tested -lt 1) { throw 'No compatible host shell was available' }
Write-Host "SHELL_MATRIX_TESTED=$tested"
Write-Host 'SHELL_OPTION_REGRESSION=PASS'
Write-Host 'PHONE_WRITES=0'
