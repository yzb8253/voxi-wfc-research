Set-StrictMode -Version Latest

function Get-GoldenSimpleSubRow {
    param([Parameter(Mandatory=$true)][string]$IsubText,[Parameter(Mandatory=$true)][int]$SubId)
    $pattern=('\{{id={0}\s' -f $SubId)
    @($IsubText -split "\r?\n" | Where-Object { $_ -match $pattern }) | Select-Object -First 1
}

function Test-GoldenSimpleSlot0Absent {
    param([Parameter(Mandatory=$true)][string]$IsubText,[Parameter(Mandatory=$true)][string]$SimState)
    $states=@($SimState.Split(',')|ForEach-Object{$_.Trim().ToUpperInvariant()})
    $slot0PhysicalAbsent=($states.Count -ge 2 -and $states[0] -eq 'ABSENT')
    $slot0Mappings=@($IsubText -split "\r?\n"|Where-Object{$_ -match 'simSlotIndex=0(?:\s|\})'})
    $slot0PhysicalAbsent -and $slot0Mappings.Count -eq 0
}

function Test-GoldenSimpleVoxiEnabled {
    param([Parameter(Mandatory=$true)][string]$IsubText)
    $row=Get-GoldenSimpleSubRow -IsubText $IsubText -SubId 11
    (-not [string]::IsNullOrWhiteSpace($row)) -and
    $row -match 'simSlotIndex=1' -and $row -match 'carrierId=28' -and
    $row -match 'mcc=234' -and $row -match 'mnc=15' -and
    $row -match 'areUiccApplicationsEnabled=true'
}

function Test-GoldenSimpleF8 {
    param([Parameter(Mandatory=$true)][string]$IsubText)
    $row=Get-GoldenSimpleSubRow -IsubText $IsubText -SubId 11
    (-not [string]::IsNullOrWhiteSpace($row)) -and
    $row -match 'simSlotIndex=-1' -and $row -match 'areUiccApplicationsEnabled=false'
}

function Test-GoldenSimpleFreshCne {
    param([AllowNull()][object]$Baseline,[AllowNull()][object]$Current)
    if($null -eq $Current -or [string]$Current -eq 'null'){return $false}
    if($null -eq $Baseline -or [string]$Baseline -eq 'null'){return $true}
    [string]$Baseline -cne [string]$Current
}

function Test-GoldenSimpleStrictHealthText {
    param([Parameter(Mandatory=$true)][string]$Text)
    ($Text -match '(?m)^IMS:\s+REGISTERED\s+\(raw 2\)\s*$') -and
    ($Text -match '(?m)^Transport:\s+WLAN\s+\(raw 2\)\s*$') -and
    ($Text -match '(?m)^VOICE/IWLAN:\s+AVAILABLE\s*$') -and
    ($Text -match '(?m)^WFC:\s+AVAILABLE\s*$')
}

function Test-GoldenSimplePPredecessor {
    param([Parameter(Mandatory=$true)][object]$Status)
    [bool]$Status.target.mappingGate -and [int]$Status.target.subId -eq 11 -and
    [int]$Status.target.slotId -eq 1 -and [int]$Status.target.phoneId -eq 1 -and
    [int]$Status.target.carrierId -eq 28 -and [int]$Status.target.mcc -eq 234 -and
    [int]$Status.target.mnc -eq 15 -and [bool]$Status.subscription.active -and
    [bool]$Status.subscription.areUiccApplicationsEnabled -and
    [string]$Status.mmtel.featureState -eq 'READY' -and
    [string]$Status.iwlan.psWlanState -eq 'HOME' -and
    [bool]$Status.iwlan.iwlanPreferred
}
