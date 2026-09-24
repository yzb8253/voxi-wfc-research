[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'Prepare-R3Cycle.ps1'
$text = Get-Content -LiteralPath $runner -Raw
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runner,[ref]$tokens,[ref]$errors)
if($errors.Count -ne 0){throw "PS_PARSE_ERRORS=$($errors.Count)"}

function Function-Text([string]$Name) {
  $functionAst = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name},$true)
  if($null -eq $functionAst){throw "MISSING_FUNCTION=$Name"}
  $functionAst.Extent.Text
}

$r0 = Function-Text 'R0-Native-Ready'
$r3 = Function-Text 'R3-Framework-Ready'
$normalize = Function-Text 'Normalize-R0'

foreach($forbidden in @('rilTechnology','preferred','qtiCneRequest','SST','DNC')) {
  if($r0 -match [regex]::Escape($forbidden)){throw "R0_NATIVE_GATE_CONTAINS_FRAMEWORK_FIELD=$forbidden"}
}
foreach($required in @('Target-Gate','Process-Gate','Native-Clean','moduleLock')) {
  if($r0 -notmatch [regex]::Escape($required)){throw "R0_NATIVE_GATE_MISSING=$required"}
}
foreach($required in @('R0-Native-Ready','airplaneMode','wlan0Up','vpnNetwork','rilTechnology','preferred','qtiCneRequest')) {
  if($r3 -notmatch [regex]::Escape($required)){throw "R3_FRAMEWORK_GATE_MISSING=$required"}
}
if($normalize -match 'A-Canonical|R3-Framework-Ready'){throw 'NORMALIZE_R0_REFERENCES_FRAMEWORK_GATE'}
if($normalize -notmatch 'R0-Native-Ready'){throw 'NORMALIZE_R0_MISSING_NATIVE_GATE'}

$normalizeIndex = $text.IndexOf('$a=Normalize-R0 $aRaw',[StringComparison]::Ordinal)
$scopeIndex = $text.IndexOf('$before=Get-Scope',[StringComparison]::Ordinal)
$termIndex = $text.IndexOf('[void](Root-Write ("kill -TERM {0}"',[StringComparison]::Ordinal)
$readyIndex = $text.IndexOf('if(-not (R3-Framework-Ready $ready))',[StringComparison]::Ordinal)
if($normalizeIndex -lt 0 -or $scopeIndex -le $normalizeIndex -or $termIndex -le $scopeIndex -or $readyIndex -le $termIndex){throw 'GATE_ORDER_INVALID'}

Write-Host 'PS5_PARSE=PASS'
Write-Host 'R0_NATIVE_READY_AUDIT=PASS'
Write-Host 'R0_FRAMEWORK_FIELD_EXCLUSION=PASS'
Write-Host 'R3_FRAMEWORK_READY_AUDIT=PASS'
Write-Host 'GATE_ORDER_AUDIT=PASS'
Write-Host 'PHONE_WRITES=0'

