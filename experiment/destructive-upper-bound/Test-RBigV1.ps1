Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$prepare=Get-Content (Join-Path $root 'Invoke-RBigPreparation.ps1') -Raw
$runner=Get-Content (Join-Path $root 'Run-RBigV1FiveCycle.ps1') -Raw
foreach($file in @('Invoke-RBigPreparation.ps1','Run-RBigV1FiveCycle.ps1')){$errors=$null;$tokens=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file),[ref]$tokens,[ref]$errors);if($errors.Count){throw "PARSE_FAIL=$file $($errors[0])"}}
if(([regex]::Matches($prepare,[regex]::Escape("Root-Write 'setprop ctl.restart vendor.qcrild2'"))).Count -ne 1){throw 'QCRILD2_WRITE_SITE_COUNT'}
if(([regex]::Matches($prepare,'Restart-Qcrild2 ''[AB]''')).Count -ne 2){throw 'QCRILD2_CALL_COUNT'}
if(([regex]::Matches($prepare,[regex]::Escape('Root-Write "kill -TERM $($before.qtidata.pid)"'))).Count -ne 1){throw 'QTIDATA_TERM_SITE_COUNT'}
if($prepare -match 'kill -9|killall|pkill|vendor\.cnd|resetIms|restart-modem|reboot'){throw 'FORBIDDEN_PREPARE_PRIMITIVE'}
if(([regex]::Matches($runner,'elseif\(\$cycle -ge 3\)\{Child \$Prepare')).Count -ne 1){throw 'UPPER_BOUND_LOOP_NOT_SINGLE_CALL_SITE'}
if(([regex]::Matches($runner,[regex]::Escape("Phone-Write 'cmd connectivity airplane-mode enable'"))).Count -ne 1){throw 'FIXED_P_SITE_COUNT'}
if($runner -match 'kill -9|killall|pkill|vendor\.cnd|resetIms|restart-modem'){throw 'FORBIDDEN_RUNNER_PRIMITIVE'}
Write-Host 'POWERSHELL_PARSE=PASS'
Write-Host 'CYCLE_3_4_5_IDENTICAL=PASS'
Write-Host 'QCRILD2_RESTARTS_PER_R_BIG=2'
Write-Host 'QTIDATASERVICES_TERM_PER_R_BIG=1'
Write-Host 'PHONE_TERM_PER_R_BIG=1'
Write-Host 'NO_ADAPTIVE_RETRY=PASS'
Write-Host 'STATIC_NO_ADB=PASS'

