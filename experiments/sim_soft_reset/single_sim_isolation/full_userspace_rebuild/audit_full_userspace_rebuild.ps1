$ErrorActionPreference='Stop'
$S=Get-Content -Raw (Join-Path $PSScriptRoot 'device\single_sim_userspace_rebuild.sh')
function Need($P,$L){if($S-notmatch$P){throw "FAIL $L"};"PASS $L"}
function Reject($P,$L){if($S-match$P){throw "FAIL $L"};"PASS $L"}
function Count($P,$N,$L){$x=([regex]::Matches($S,$P)).Count;if($x-ne$N){throw "FAIL $L expected=$N actual=$x"};"PASS $L"}
if([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'device\single_sim_userspace_rebuild.sh'))-contains 13){throw 'FAIL CR byte'}
'PASS LF-only'
Need "getprop gsm\.sim\.state\).*ABSENT,LOADED" 'slot0 ABSENT/single-SIM gate'
Need '"target":\{\"subId\":11,\"slotId\":1,\"phoneId\":1,\"carrierId\":28' 'fixed VOXI mapping gate'
Need '(?s)restart_init_once vendor\.imsdatadaemon.*restart_init_once vendor\.imsqmidaemon.*restart_init_once vendor\.cnd.*restart_app_once \.qtidataservices 10104.*restart_app_once org\.codeaurora\.ims 10196' 'fixed restart order'
Count 'kill -TERM "\$old"' 2 'only two generic exact-PID TERM call sites'
Need '(?s)find_exact_app.*found=.*return 1' 'application process uniqueness gate'
Need 'unstable-new-pid' 'new PID stability gate'
Need 'wait_ims_service_bind' 'ImsService rebind gate'
Need 'protected-qcrild' 'qcrild protected'
Need 'protected-qcrild2' 'qcrild2 protected'
Need 'protected-netmgrd' 'netmgrd protected'
Need 'protected-phone' 'phone protected'
Need 'protected-system-server' 'system_server protected'
Reject 'killall|pkill|SIGKILL|kill -9|reboot|restart-modem|resetIms|setSimPowerState|setUiccApplicationsEnabled|airplane|ctl\.(start|stop|restart)' 'forbidden operations absent'
'SINGLE-SIM FULL USERSPACE STATIC AUDIT: PASS'
