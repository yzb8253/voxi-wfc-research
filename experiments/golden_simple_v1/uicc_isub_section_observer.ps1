Set-StrictMode -Version Latest

function Get-IsubSectionRange {
    param([string[]]$Lines,[string]$Heading,[int]$EndExclusive)
    $start=-1
    for($i=0;$i -lt $Lines.Count;$i++){if($Lines[$i].Trim() -ceq $Heading){$start=$i;break}}
    if($start -lt 0 -or $start -ge $EndExclusive){return $null}
    [pscustomobject]@{Start=$start+1;End=$EndExclusive}
}

function Convert-IsubRow {
    param([AllowNull()][string]$Row)
    if([string]::IsNullOrWhiteSpace($Row)){return [pscustomobject]@{Present=$false;Slot=$null;CarrierId=$null;Mcc=$null;Mnc=$null;Apps=$null;Raw=$null}}
    function Field([string]$Name){if($Row -match ("(?:^|\s){0}=([^\s\}}]+)" -f [regex]::Escape($Name))){$Matches[1]}else{$null}}
    [pscustomobject]@{Present=$true;Slot=Field 'simSlotIndex';CarrierId=Field 'carrierId';Mcc=Field 'mcc';Mnc=Field 'mnc';Apps=Field 'areUiccApplicationsEnabled';Raw=$Row.Trim()}
}

function Get-IsubSectionObserver {
    param([Parameter(Mandatory=$true)][string]$IsubText,[Parameter(Mandatory=$true)][string]$SimState,[int]$SubId=11)
    $lines=@($IsubText -split "\r?\n")
    $active=-1;$db=-1;$all=-1
    for($i=0;$i -lt $lines.Count;$i++){
        switch -CaseSensitive ($lines[$i].Trim()){
            'ActiveSubInfoList:' {$active=$i}
            'ActiveSubInfoList in the DB:' {$db=$i}
            'AllSubInfoList:' {$all=$i}
        }
    }
    if($active -lt 0 -or $db -le $active -or $all -le $db){return [pscustomobject]@{Valid=$false;Reason='SECTION_BOUNDARY_MISSING'}}
    $allEnd=$lines.Count
    for($i=$all+1;$i -lt $lines.Count;$i++){if($lines[$i].Trim() -match '^\+{10,}$'){$allEnd=$i;break}}
    if($allEnd -eq $lines.Count){return [pscustomobject]@{Valid=$false;Reason='ALL_SECTION_END_MISSING'}}
    $pattern=('^\s*\{{id={0}\s' -f $SubId)
    function SectionText([int]$Start,[int]$End){if($End -le $Start){return ''};($lines[$Start..($End-1)] -join "`n")}
    $activeText=SectionText ($active+1) $db;$dbText=SectionText ($db+1) $all;$allText=SectionText ($all+1) $allEnd
    $activeRow=@($activeText -split "\r?\n"|Where-Object{$_ -match $pattern})|Select-Object -First 1
    $dbRow=@($dbText -split "\r?\n"|Where-Object{$_ -match $pattern})|Select-Object -First 1
    $allRow=@($allText -split "\r?\n"|Where-Object{$_ -match $pattern})|Select-Object -First 1
    $slot1='MISSING'
    $prefix=($lines[0..($active-1)] -join "`n")
    if($prefix -match '(?m)^\s*sSlotIndexToSubId\[1\]:\s*subIds=1=\[([^\]]*)\]'){$slot1=$Matches[1].Trim()}
    $states=@($SimState.Split(',')|ForEach-Object{$_.Trim().ToUpperInvariant()})
    $slot0Absent=($states.Count -ge 2 -and $states[0] -eq 'ABSENT')
    $slot0Mapped=($activeText -match 'simSlotIndex=0(?:\s|\})' -or $dbText -match 'simSlotIndex=0(?:\s|\})' -or $allText -match 'simSlotIndex=0(?:\s|\})')
    [pscustomobject]@{Valid=$true;Reason='PASS';Active=Convert-IsubRow $activeRow;Db=Convert-IsubRow $dbRow;All=Convert-IsubRow $allRow;Slot1Map=$slot1;Slot0Absent=$slot0Absent;Slot0Mapped=$slot0Mapped}
}

function Test-VoxiRowExact {
    param([object]$Row,[string]$Slot,[string]$Apps)
    $Row.Present -and $Row.Slot -ceq $Slot -and $Row.CarrierId -ceq '28' -and $Row.Mcc -ceq '234' -and $Row.Mnc -ceq '15' -and $Row.Apps -ceq $Apps
}

function Get-IsubObserverState {
    param([Parameter(Mandatory=$true)][object]$Observer)
    if(-not $Observer.Valid){return 'INVALID'}
    if(-not $Observer.Db.Present -or -not $Observer.All.Present){return 'INCOMPLETE'}
    $same=($Observer.Db.Slot -ceq $Observer.All.Slot -and $Observer.Db.CarrierId -ceq $Observer.All.CarrierId -and $Observer.Db.Mcc -ceq $Observer.All.Mcc -and $Observer.Db.Mnc -ceq $Observer.All.Mnc -and $Observer.Db.Apps -ceq $Observer.All.Apps)
    if(-not $same){return 'CONFLICT'}
    $storedF8=(Test-VoxiRowExact $Observer.Db '-1' 'false') -and (Test-VoxiRowExact $Observer.All '-1' 'false')
    $activeNotSlot1=(-not $Observer.Active.Present -or $Observer.Active.Slot -cne '1')
    if($storedF8 -and $activeNotSlot1){return 'F8'}
    $restored=(Test-VoxiRowExact $Observer.Active '1' 'true') -and (Test-VoxiRowExact $Observer.Db '1' 'true') -and (Test-VoxiRowExact $Observer.All '1' 'true') -and $Observer.Slot1Map -ceq '11'
    if($restored){return 'RESTORED'}
    'TRANSITION'
}

function Format-IsubObserverRow {
    param([object]$Row)
    if(-not $Row.Present){return 'MISSING'}
    'slot{0}/apps={1}/carrier={2}/mccmnc={3}{4}' -f $Row.Slot,$Row.Apps,$Row.CarrierId,$Row.Mcc,$Row.Mnc
}

function Format-IsubObserver {
    param([object]$Observer)
    if(-not $Observer.Valid){return "INVALID/$($Observer.Reason)"}
    'ACTIVE={0} DB={1} ALL={2} SLOT1_MAP={3} SLOT0_ABSENT={4} STATE={5}' -f (Format-IsubObserverRow $Observer.Active),(Format-IsubObserverRow $Observer.Db),(Format-IsubObserverRow $Observer.All),$Observer.Slot1Map,$Observer.Slot0Absent,(Get-IsubObserverState $Observer)
}
