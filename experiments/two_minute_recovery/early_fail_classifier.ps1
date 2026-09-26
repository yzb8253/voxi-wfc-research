Set-StrictMode -Version Latest

function Get-WfcRecoveryProgressClassification {
    param(
        [Parameter(Mandatory=$true)][int]$ElapsedMs,
        [Parameter(Mandatory=$true)][bool]$TargetMappingValid,
        [Parameter(Mandatory=$true)][bool]$SubscriptionActive,
        [Parameter(Mandatory=$true)][bool]$UiccEnabled,
        [Parameter(Mandatory=$true)][bool]$Qcrild2Stable,
        [Parameter(Mandatory=$true)][bool]$NativeStateStable,
        [Parameter(Mandatory=$true)][bool]$MmtelReady,
        [Parameter(Mandatory=$true)][string]$CneRegistered,
        [Parameter(Mandatory=$true)][string]$CneActive,
        [AllowNull()][object]$CurrentRequest,
        [AllowNull()][object]$CurrentSatisfied,
        [Parameter(Mandatory=$true)][string]$ImsState,
        [Parameter(Mandatory=$true)][string]$Transport,
        [Parameter(Mandatory=$true)][bool]$VoiceIwlan,
        [Parameter(Mandatory=$true)][bool]$WfcAvailable,
        [Parameter(Mandatory=$true)][bool]$ImsNetworkAgent,
        [Parameter(Mandatory=$true)][bool]$Epdg4500,
        [Parameter(Mandatory=$true)][bool]$Xfrm,
        [int]$ConsecutiveDeadSamples=1,
        [int]$DeadSpanMs=0
    )
    if(-not $TargetMappingValid -or -not $SubscriptionActive -or -not $UiccEnabled -or -not $Qcrild2Stable -or -not $NativeStateStable){return 'INSUFFICIENT_EVIDENCE'}
    $progress=($CneRegistered -eq 'YES' -or $CneActive -eq 'YES' -or $null -ne $CurrentRequest -or $null -ne $CurrentSatisfied -or $ImsState -in @('REGISTERING','REGISTERED') -or $Transport -eq 'WLAN' -or $VoiceIwlan -or $WfcAvailable -or $ImsNetworkAgent -or $Epdg4500 -or $Xfrm)
    if($progress){return 'RECOVERY_PROGRESSING'}
    if(-not $MmtelReady){return 'INSUFFICIENT_EVIDENCE'}
    if($ElapsedMs -lt 15000){return 'INSUFFICIENT_EVIDENCE'}
    if($ElapsedMs -lt 30000){return 'NO_CNE_SUSPECTED'}
    if($ConsecutiveDeadSamples -ge 3 -and $DeadSpanMs -ge 10000){return 'NO_CNE_CONFIRMED'}
    'INSUFFICIENT_EVIDENCE'
}
