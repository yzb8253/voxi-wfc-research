$ErrorActionPreference = "Stop"

$Adb = Join-Path $PSScriptRoot "..\..\..\..\adb.exe"
$Serial = "192.168.137.134:39581"
$ProbeJar = "/data/adb/modules/voxi_wfc_recovery/lib/wfc-probe.jar"
$Timeline = Join-Path $PSScriptRoot "direct_health_300s.jsonl"
$ResultPath = Join-Path $PSScriptRoot "direct_health_300s_result.json"

Remove-Item -LiteralPath $Timeline -Force -ErrorAction SilentlyContinue
$start = Get-Date
$allDirectHealthy = $true
$allSlot0Protected = $true
$sampleCount = 0
$networkAgentEverSeen = $false
$keepaliveEverMissing = $false
$last = $null

foreach ($targetSecond in 0..30 | ForEach-Object { $_ * 10 }) {
    $elapsed = [int][Math]::Floor((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds)
    if ($elapsed -lt $targetSecond) { Start-Sleep -Seconds ($targetSecond - $elapsed) }

    $raw = & $Adb -s $Serial shell su -c "CLASSPATH=$ProbeJar app_process /system/bin WfcStateProbe read-only-json" 2>&1
    $line = $raw | Where-Object { $_ -match '^\{' } | Select-Object -Last 1
    if (-not $line) { throw "Probe returned no JSON at target ${targetSecond}s" }
    $state = $line | ConvertFrom-Json
    $elapsed = [int][Math]::Floor((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds)
    $directHealthy = $state.ims.registrationStateRaw -eq 2 `
        -and $state.ims.registrationTransportRaw -eq 2 `
        -and $state.mmtel.voiceIwlanAvailable `
        -and $state.wfc.wifiCallingAvailable
    $slot0Protected = $state.protectedSlot0.active -and $state.protectedSlot0.mappingGate

    $record = [ordered]@{
        elapsedSeconds = $elapsed
        timestamp = $state.timestamp
        directWfcHealthy = $directHealthy
        registrationStateRaw = $state.ims.registrationStateRaw
        registrationTransportRaw = $state.ims.registrationTransportRaw
        voiceIwlanAvailable = $state.mmtel.voiceIwlanAvailable
        wifiCallingAvailable = $state.wfc.wifiCallingAvailable
        imsIwlanNetworkAgentEvidence = $state.connectivity.imsIwlanNetworkAgent
        qtiCneRequestEvidence = $state.connectivity.qtiCneRequestActive
        udp4500KeepaliveEvidence = $state.epdg.udp4500Keepalive
        mmtelFeatureState = $state.mmtel.featureState
        protectedSlot0 = $slot0Protected
        legacyFailureClass = $state.failureClass
    }
    ($record | ConvertTo-Json -Compress) | Add-Content -LiteralPath $Timeline -Encoding ascii
    $sampleCount++
    if (-not $directHealthy) { $allDirectHealthy = $false }
    if (-not $slot0Protected) { $allSlot0Protected = $false }
    if ($state.connectivity.imsIwlanNetworkAgent) { $networkAgentEverSeen = $true }
    if (-not $state.epdg.udp4500Keepalive) { $keepaliveEverMissing = $true }
    $last = $record
}

$duration = [int][Math]::Floor((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds)
$result = [ordered]@{
    durationSeconds = $duration
    sampleCount = $sampleCount
    allDirectWfcHealthy = $allDirectHealthy
    allSlot0Protected = $allSlot0Protected
    userVisibleWfcIcon = "PRESENT (user-confirmed)"
    imsIwlanNetworkAgentEverSeen = $networkAgentEverSeen
    udp4500KeepaliveEverMissing = $keepaliveEverMissing
    final = $last
    passed = $allDirectHealthy -and $allSlot0Protected -and $duration -ge 300
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultPath -Encoding ascii
Write-Output ($result | ConvertTo-Json -Depth 4 -Compress)
