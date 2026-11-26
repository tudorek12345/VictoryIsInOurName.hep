[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Run,
    [string]$StageRoot = (Join-Path $PSScriptRoot 'isolated-run\stage'),
    [string]$PhaseEvidencePath,
    [ValidateRange(1, 1000)] [int]$TailSamples = 5,
    [switch]$IncludeSamples,
    [switch]$AsObject,
    [string]$OutFile
)

# Local diagnostics only: raw logs, captures and shader inputs are never copied.
# FPS values are interval samples. They cannot prove a visible/playable mission,
# and their median is neither a whole-run FPS nor a per-frame 1% low.
$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$runPath = if ([IO.Path]::IsPathRooted($Run)) { $Run } else { Join-Path $StageRoot $Run }
$runPath = (Get-Item -LiteralPath $runPath -ErrorAction Stop).FullName
$logDir = Join-Path $runPath 'logs'
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) { throw "No logs directory in $runPath" }

function Read-LinesShared([string]$Path, [scriptblock]$OnLine) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    $reader = New-Object IO.StreamReader($stream)
    try {
        $number = 0
        while ($null -ne ($line = $reader.ReadLine())) {
            $number++
            & $OnLine ([regex]::Replace($line, '\x1b\[[0-9;]*[a-zA-Z]', '')) $number
        }
    } finally { $reader.Dispose(); $stream.Dispose() }
}
function Number([string]$Text) { [double]::Parse($Text, $invariant) }
function Statistics($Values) {
    $sorted = @($Values | Where-Object { $null -ne $_ } | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle-1] + $sorted[$middle]) / 2 }
    [ordered]@{ count=$sorted.Count; minimum=$sorted[0]; median=$median; maximum=$sorted[-1] }
}
function SampleSummary($Items) {
    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) { return [ordered]@{ count=0 } }
    $result = [ordered]@{
        count=$itemsArray.Count
        firstTimestamp=$itemsArray[0].timestamp
        lastTimestamp=$itemsArray[-1].timestamp
    }
    foreach ($field in @('fps','frameMs','prepareMs','copyMs','textureMs','gpuMs','readbackMs','drawsPerFrame','droppedWithoutPipeline','pipelinesBeingMade','droppedIndirect')) {
        $result[$field] = Statistics @($itemsArray | ForEach-Object { $_.$field })
    }
    return $result
}
$diagFile = Join-Path $logDir 'diagnostics.json'
$metadata = if (Test-Path -LiteralPath $diagFile -PathType Leaf) { Get-Content -LiteralPath $diagFile -Raw | ConvertFrom-Json } else { $null }
$samples = New-Object 'System.Collections.Generic.List[object]'
$memory = New-Object 'System.Collections.Generic.List[object]'
$state = @{
    stopReason = 'not recorded'; stoppedPhysicalBytes=$null; stoppedCommitBytes=$null
    reservePhysicalBytes=$null; reserveCommitBytes=$null; peakJobCommitBytes=$null; jobCommitLimitBytes=$null
    restoredPaths=$null; zeroCapabilityAppContainerVerified=$false; childResult=$null
    adapter=$null; software=$null; vendorId=$null; vramMiB=$null
    deviceRemovedMessages=0; allocationFailureMessages=0; malformedFrameSamples=0
}
Read-LinesShared (Join-Path $logDir 'runner.log') {
    param($line,$lineNumber)
    if ($line -match 'Host memory guard reached\. Available physical bytes: (\d+); reserve bytes: (\d+)') {
        $state.stopReason='physical memory reserve'; $state.stoppedPhysicalBytes=[long]$Matches[1]; $state.reservePhysicalBytes=[long]$Matches[2]
    } elseif ($line -match 'Host commit guard reached\. Available commit bytes: (\d+); reserve bytes: (\d+)') {
        $state.stopReason='system commit reserve'; $state.stoppedCommitBytes=[long]$Matches[1]; $state.reserveCommitBytes=[long]$Matches[2]
    } elseif ($line -match 'Timeout reached\. Terminating job\.') { $state.stopReason='timer' }
    if ($line -match 'Peak job commit bytes: (\d+); limit bytes: (\d+)') { $state.peakJobCommitBytes=[long]$Matches[1]; $state.jobCommitLimitBytes=[long]$Matches[2] }
    if ($line -match 'Verified restored package access rules on (\d+) paths') { $state.restoredPaths=[int]$Matches[1] }
    if ($line -match 'Verified zero-capability AppContainer and bounded job') { $state.zeroCapabilityAppContainerVerified=$true }
    if ($line -match 'Child result (\d+)') { $state.childResult=[long]$Matches[1] }
}
$framePattern = '(?<fps>\d+(?:\.\d+)?) fps, (?<frame>\d+(?:\.\d+)?) ms/frame \((?<prep>[\d.]+) preparing: copies (?<copy>[\d.]+) ms [\d.]+ MB, textures (?<texture>[\d.]+) ms [\d.]+ MB; (?<gpu>[\d.]+) on the GPU; (?<back>[\d.]+) copying back [\d.]+ MB\), (?<draws>[\d.]+) draws/frame, dropped (?<dropped>[\d.]+) without a host pipeline \((?<making>\d+) being made\) and (?<indirect>[\d.]+) indirect'
Read-LinesShared (Join-Path $logDir 'victory.log') {
    param($line,$lineNumber)
    $timestamp = $null
    if ($line -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))') { $timestamp=$Matches[1] }
    $match = [regex]::Match($line, $framePattern)
    if ($match.Success) {
        $g=$match.Groups
        $samples.Add([pscustomobject][ordered]@{
            logLine=$lineNumber; timestamp=$timestamp
            fps=(Number $g['fps'].Value); frameMs=(Number $g['frame'].Value)
            prepareMs=(Number $g['prep'].Value); copyMs=(Number $g['copy'].Value); textureMs=(Number $g['texture'].Value)
            gpuMs=(Number $g['gpu'].Value); readbackMs=(Number $g['back'].Value)
            drawsPerFrame=(Number $g['draws'].Value); droppedWithoutPipeline=(Number $g['dropped'].Value)
            pipelinesBeingMade=[int]$g['making'].Value; droppedIndirect=(Number $g['indirect'].Value)
        })
    } elseif ($line -match '\d+(?:\.\d+)? fps, .* ms/frame') { $state.malformedFrameSamples++ }
    if ($line -match 'memory: (\d+) MB private \((\d+) MB of it in memory; the PC has (\d+) MB free and (\d+) MB left to commit\)') {
        $memory.Add([pscustomobject]@{logLine=$lineNumber;timestamp=$timestamp;privateMiB=[long]$Matches[1];residentPrivateMiB=[long]$Matches[2];availablePhysicalMiB=[long]$Matches[3];availableCommitMiB=[long]$Matches[4]})
    }
    if ($line -match 'host D3D12 adapter' -and $line -match 'adapter="([^"]+)"') {
        $state.adapter=$Matches[1]
        if ($line -match 'software=(true|false)') { $state.software=$Matches[1] -eq 'true' }
        if ($line -match 'vendor_id=(\d+)') { $state.vendorId=[int]$Matches[1] }
        if ($line -match 'vram_mib=(\d+)') { $state.vramMiB=[long]$Matches[1] }
    }
    if ($line -match '(?i)(DXGI_ERROR_DEVICE_REMOVED|DXGI_ERROR_DEVICE_HUNG|device (was )?removed|0x887a000[567])') { $state.deviceRemovedMessages++ }
    if ($line -match '(?i)(memory allocation of .* failed|out of memory|E_OUTOFMEMORY|0x8007000e)') { $state.allocationFailureMessages++ }
}

# Explicitly supplied observations can group samples; counts/draws never assign a game phase.
$phaseGroups = New-Object 'System.Collections.Generic.List[object]'
if ($PhaseEvidencePath) {
    $phaseDefinitions = @(Get-Content -LiteralPath $PhaseEvidencePath -Raw | ConvertFrom-Json)
    foreach ($phase in $phaseDefinitions) {
        if (-not $phase.label -or -not $phase.evidence -or -not $phase.startUtc -or -not $phase.endUtc) {
            throw 'Each phase needs label, evidence, startUtc and endUtc.'
        }
        if ($phase.startUtc -notmatch '(Z|[+-]\d{2}:\d{2})$' -or $phase.endUtc -notmatch '(Z|[+-]\d{2}:\d{2})$') { throw 'Phase timestamps must include an explicit UTC offset.' }
        $start=[DateTimeOffset]::Parse($phase.startUtc,$invariant)
        $end=[DateTimeOffset]::Parse($phase.endUtc,$invariant)
        if ($end -le $start) { throw 'Phase endUtc must be later than startUtc.' }
        $selected=@($samples | Where-Object { $_.timestamp -and [DateTimeOffset]::Parse($_.timestamp,$invariant) -ge $start -and [DateTimeOffset]::Parse($_.timestamp,$invariant) -lt $end })
        $phaseGroups.Add([pscustomobject]@{label=$phase.label;evidence=$phase.evidence;startUtc=$phase.startUtc;endUtc=$phase.endUtc;samples=(SampleSummary $selected)})
    }
}
$warnings = New-Object 'System.Collections.Generic.List[string]'
if ($null -eq $metadata) { $warnings.Add('diagnostics.json is absent; the launcher may still be running or its cleanup was interrupted.') }
if ($state.malformedFrameSamples) { $warnings.Add("$($state.malformedFrameSamples) frame-stat lines did not match the known format and were not counted.") }
if (-not $state.adapter) { $warnings.Add('No actual adapter log record; the requested renderer is not adapter verification.') }
if ($phaseGroups.Count -eq 0) { $warnings.Add('No phase evidence supplied. These samples do not distinguish intro, menus, loading, or visible gameplay.') }
if ($state.deviceRemovedMessages -eq 0) { $warnings.Add('No matching device-removal log message does not establish driver health; check Windows events for the run window.') }
$report = [ordered]@{
    schemaVersion=1; run=(Split-Path -Leaf $runPath); generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
    interpretation='Interval samples only. Sample median is not whole-run FPS or a 1% low. CPU preparation is a subset of frame time. GPU time uses the runtime counter and may include waits; overlapping queued work must not be summed. Visible, responsive gameplay and audible output require independent evidence.'
    checkout=$metadata.checkout; checkoutDirty=$metadata.checkoutDirty; runtimeSha256=$metadata.runtimeSha256
    requestedRenderer=$metadata.renderer; console=$metadata.console; adapter=$state.adapter; softwareAdapter=$state.software; vramMiB=$state.vramMiB
    elapsedSeconds=$metadata.elapsedSeconds; launcherExitCode=$metadata.exitCode
    stopReason=$state.stopReason; childResult=$state.childResult
    peakJobCommitBytes=$state.peakJobCommitBytes; jobCommitLimitBytes=$state.jobCommitLimitBytes
    availablePhysicalBytesAtStop=$state.stoppedPhysicalBytes; reservePhysicalBytes=$state.reservePhysicalBytes
    availableCommitBytesAtStop=$state.stoppedCommitBytes; reserveCommitBytes=$state.reserveCommitBytes
    restoredPackagePaths=$state.restoredPaths; zeroCapabilityAppContainerVerified=$state.zeroCapabilityAppContainerVerified
    allSamples=(SampleSummary $samples.ToArray()); tailSamples=@($samples | Select-Object -Last $TailSamples)
    memorySamples=$memory.Count; lastMemorySample=($memory | Select-Object -Last 1)
    deviceRemovalMessages=$state.deviceRemovedMessages; allocationFailureMessages=$state.allocationFailureMessages
    phaseEvidence=@($phaseGroups.ToArray()); warnings=@($warnings.ToArray())
}
if ($IncludeSamples) { $report['samples']=$samples.ToArray() }
$json=$report | ConvertTo-Json -Depth 12
if ($OutFile) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $json + "`n", (New-Object Text.UTF8Encoding($false))) }
if ($AsObject) { [pscustomobject]$report } else { $json }
