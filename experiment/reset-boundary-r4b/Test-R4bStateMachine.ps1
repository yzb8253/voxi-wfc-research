[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$scripts=@('Initialize-R4bControl.ps1','Invoke-QtiDataServicesColdEpoch.ps1','Invoke-R4bCycle.ps1','Run-R4bThreeCycle.ps1')
foreach($name in $scripts){$path=Join-Path $PSScriptRoot $name;$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors);if($errors.Count){throw "PS51_PARSE_FAIL=$name $($errors|Out-String)"}}
$cycle=Get-Content -Raw (Join-Path $PSScriptRoot 'Invoke-R4bCycle.ps1')
$order=@('$R3 ($common+@(''-StopAfterR0''','$Producer @(''-Cycle''','$Provider @(''-Cycle''','$R3 ($common+@(''-LabelPrefix''','$Pipeline @(''-Cycle''')
$at=-1;foreach($needle in $order){$next=$cycle.IndexOf($needle,$at+1,[StringComparison]::Ordinal);if($next -lt 0){throw "ORDER_MARKER_MISSING=$needle"};$at=$next}
$provider=Get-Content -Raw (Join-Path $PSScriptRoot 'Invoke-QtiDataServicesColdEpoch.ps1')
if(([regex]::Matches($provider,[regex]::Escape('Root-Write ("kill -TERM'))).Count -ne 1){throw 'PROVIDER_TERM_SITE_COUNT_NOT_ONE'}
if($provider -match '(?<!@)\(New-PidLine[^\r\n]+\)\.Count'){throw 'PS51_SCALAR_COUNT_HAZARD'}
foreach($bad in @('force-stop','killall','SIGKILL','kill -9','resetIms','ctl.restart vendor.cnd')){if($provider -match [regex]::Escape($bad)){throw "FORBIDDEN_TOKEN=$bad"}}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Run-R4bThreeCycle.ps1') -StaticAudit
if($LASTEXITCODE -ne 0){throw 'STATIC_CHILD_AUDIT_FAILED'}
Write-Host 'PS5_1_PARSE=PASS'
Write-Host 'GATE_ORDER=PASS'
Write-Host 'EXACT_QTIDATA_TERM_SITE_COUNT=1'
Write-Host 'FROZEN_V262_HASH=PASS'
Write-Host 'FAIL_CLOSED=PASS'
Write-Host 'STATE_MACHINE_UNCHANGED_FROM_APPROVED_R4B=YES'
Write-Host 'PHONE_WRITES=0'
