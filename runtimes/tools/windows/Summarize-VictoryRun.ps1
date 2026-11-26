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
    foreach ($field in @('fps','frameMs','prepareMs','copyMs','textureMs','gpuMs','runtimeGpuWaitMs','readbackMs','drawsPerFrame','droppedWithoutPipeline','pipelinesBeingMade','droppedIndirect')) {
        $result[$field] = Statistics @($itemsArray | ForEach-Object { $_.$field })
    }
    return $result
}
$diagFile = Join-Path $logDir 'diagnostics.json'
$metadata = if (Test-Path -LiteralPath $diagFile -PathType Leaf) { Get-Content -LiteralPath $diagFile -Raw | ConvertFrom-Json } else { $null }
# This flag requests separate timestamp diagnostics. It does not change the
# aggregate SUBMISSION_US[1] counter, which measures CPU fence/landing waits.
$metadataGpuTiming = if ($metadata.gpuTiming -is [bool]) { $metadata.gpuTiming } else { $null }
$samples = New-Object 'System.Collections.Generic.List[object]'
$memory = New-Object 'System.Collections.Generic.List[object]'
$timedMemory = New-Object 'System.Collections.Generic.List[object]'
$videoMemory = New-Object 'System.Collections.Generic.List[object]'
$pipelineCache = New-Object 'System.Collections.Generic.List[object]'
$displayModes = New-Object 'System.Collections.Generic.List[object]'
$swapchains = New-Object 'System.Collections.Generic.Queue[object]'
$swapchainState = @{ count=0; first=$null }
$appliedGuestOutputs = New-Object 'System.Collections.Generic.Queue[object]'
$appliedGuestOutputState = @{ count=0; last=$null }
$thinUploadTail = New-Object 'System.Collections.Generic.Queue[object]'
$thinUploadState = @{ count=0; maximum=$null; last=$null }
$precompile = [ordered]@{ requested=$false; known=$null; previouslyProcessed=$null; previouslyBad=$null; selected=$null; processes=$null; completed=$false; processed=$null; refused=$null; childFailures=$null; elapsedSeconds=$null }
$jobMemory = New-Object 'System.Collections.Generic.List[object]'
$state = @{
    stopReason = 'not recorded'; stoppedPhysicalBytes=$null; stoppedCommitBytes=$null
    reservePhysicalBytes=$null; reserveCommitBytes=$null; peakJobCommitBytes=$null; jobCommitLimitBytes=$null
    restoredPaths=$null; zeroCapabilityAppContainerVerified=$false; childResult=$null
    runtimeResultBeforeCleanup=$null; cleanupFailure=$false; stoppedJobBytes=$null; jobStopThresholdBytes=$null
    adapter=$null; software=$null; vendorId=$null; vramMiB=$null
    deviceRemovedMessages=0; allocationFailureMessages=0; malformedFrameSamples=0
}
Read-LinesShared (Join-Path $logDir 'runner.log') {
    param($line,$lineNumber)
    if ($line -match 'Host memory guard reached\. Available physical bytes: (\d+); reserve bytes: (\d+)') {
        $state.stopReason='physical memory reserve'; $state.stoppedPhysicalBytes=[long]$Matches[1]; $state.reservePhysicalBytes=[long]$Matches[2]
    } elseif ($line -match 'Host commit guard reached\. Available commit bytes: (\d+); reserve bytes: (\d+)') {
        $state.stopReason='system commit reserve'; $state.stoppedCommitBytes=[long]$Matches[1]; $state.reserveCommitBytes=[long]$Matches[2]
    } elseif ($line -match 'Job commit guard reached\. Committed bytes: (\d+); stop threshold bytes: (\d+); hard limit bytes: (\d+)') {
        $state.stopReason='job commit reserve'; $state.stoppedJobBytes=[long]$Matches[1]; $state.jobStopThresholdBytes=[long]$Matches[2]; $state.jobCommitLimitBytes=[long]$Matches[3]
    } elseif ($line -match 'Timeout reached\. Terminating job\.') { $state.stopReason='timer' }
    if ($line -match 'Peak job commit bytes: (\d+); limit bytes: (\d+)') { $state.peakJobCommitBytes=[long]$Matches[1]; $state.jobCommitLimitBytes=[long]$Matches[2] }
    if ($line -match 'Verified restored package access rules on (\d+) paths') { $state.restoredPaths=[int]$Matches[1] }
    if ($line -match 'Verified zero-capability AppContainer and bounded job') { $state.zeroCapabilityAppContainerVerified=$true }
    if ($line -match 'Child result (\d+)') { $state.childResult=[long]$Matches[1] }
    if ($line -match 'Runtime result before cleanup (\d+)') { $state.runtimeResultBeforeCleanup=[long]$Matches[1] }
    if ($line -match 'DeleteAppContainerProfile failed|Job termination did not finish|Failed to restore') { $state.cleanupFailure=$true }
    if ($line -match 'Job memory sample: elapsed_ms=(\d+) pid=(\d+) private_bytes=(\d+) working_set_bytes=(\d+)') {
        $jobMemory.Add([pscustomobject]@{ elapsedMs=[long]$Matches[1]; processId=[int]$Matches[2]; privateBytes=[long]$Matches[3]; workingSetBytes=[long]$Matches[4] })
    }
}
$framePattern = '(?<fps>\d+(?:\.\d+)?) fps, (?<frame>\d+(?:\.\d+)?) ms/frame \((?<prep>[\d.]+) preparing: copies (?<copy>[\d.]+) ms [\d.]+ MB, textures (?<texture>[\d.]+) ms [\d.]+ MB; (?<gpu>[\d.]+) on the GPU; (?<back>[\d.]+) copying back [\d.]+ MB\), (?<draws>[\d.]+) draws/frame, dropped (?<dropped>[\d.]+) without a host pipeline \((?<making>\d+) being made\) and (?<indirect>[\d.]+) indirect'
Read-LinesShared (Join-Path $logDir 'victory.log') {
    param($line,$lineNumber)
    $timestamp = $null
    if ($line -match '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))') { $timestamp=$Matches[1] }
    if ($line.Contains('list calls translated by threads of ours per frame (VICTORY_THIN):') -and
        $line -match '; pending uploads reclaimed (\d+(?:\.\d+)?)\s*$') {
        # The runtime divides this count by frames in its reporting interval.
        # Keep only a bounded tail even with IncludeSamples; these are not bytes.
        $value = Number $Matches[1]
        $sample = [pscustomobject]@{logLine=$lineNumber;timestamp=$timestamp;reclaimedUploadsPerFrame=$value}
        $thinUploadState.count++
        if ($null -eq $thinUploadState.maximum -or $value -gt $thinUploadState.maximum) { $thinUploadState.maximum=$value }
        $thinUploadState.last=$sample
        $thinUploadTail.Enqueue($sample)
        if ($thinUploadTail.Count -gt $TailSamples) { $null=$thinUploadTail.Dequeue() }
    }
    if ($line -match "\b(display mode reported to the title|presenting to a window|the swap chain's buffers were made again for another size or format)\s+width=(\d+)\s+height=(\d+)") {
        $kind = $Matches[1]
        $size = [pscustomobject]@{ logLine=$lineNumber; timestamp=$timestamp; width=[int]$Matches[2]; height=[int]$Matches[3] }
        if ($kind -eq 'display mode reported to the title') { $displayModes.Add($size) } else {
            $size | Add-Member -NotePropertyName event -NotePropertyValue $(if ($kind -eq 'presenting to a window') { 'created' } else { 'resized' })
            $swapchainState.count++
            if ($null -eq $swapchainState.first) { $swapchainState.first=$size }
            $swapchains.Enqueue($size)
            if ($swapchains.Count -gt $TailSamples) { $null=$swapchains.Dequeue() }
        }
    }
    # Only the loader's success event after the verified transaction, cache
    # flush and protection restoration proves application. Neither a request
    # nor the caller's human-readable output line establishes that event.
    $eventLine = if ($timestamp) { $line.Substring($timestamp.Length).TrimStart() } else { $line.TrimStart() }
    if ($eventLine -match '^INFO\s+victory_loader::resolution:\s+guest output: sites verified; output applied; native scale unchanged\s+width=(?<outputWidth>[1-9]\d*)\s+height=(?<outputHeight>[1-9]\d*)\s*$') {
        $outputWidth=0; $outputHeight=0
        if ([int]::TryParse($Matches['outputWidth'], [ref]$outputWidth) -and [int]::TryParse($Matches['outputHeight'], [ref]$outputHeight)) {
            $applied=[pscustomobject]@{ logLine=$lineNumber; timestamp=$timestamp; width=$outputWidth; height=$outputHeight; nativeRenderScaleUnchanged=$true }
            $appliedGuestOutputState.count++
            $appliedGuestOutputState.last=$applied
            $appliedGuestOutputs.Enqueue($applied)
            if ($appliedGuestOutputs.Count -gt $TailSamples) { $null=$appliedGuestOutputs.Dequeue() }
        }
    }
    $match = [regex]::Match($line, $framePattern)
    if ($match.Success) {
        $g=$match.Groups
        $samples.Add([pscustomobject][ordered]@{
            logLine=$lineNumber; timestamp=$timestamp
            fps=(Number $g['fps'].Value); frameMs=(Number $g['frame'].Value)
            prepareMs=(Number $g['prep'].Value); copyMs=(Number $g['copy'].Value); textureMs=(Number $g['texture'].Value)
            gpuMs=(Number $g['gpu'].Value); runtimeGpuWaitMs=(Number $g['gpu'].Value)
            readbackMs=(Number $g['back'].Value)
            drawsPerFrame=(Number $g['draws'].Value); droppedWithoutPipeline=(Number $g['dropped'].Value)
            pipelinesBeingMade=[int]$g['making'].Value; droppedIndirect=(Number $g['indirect'].Value)
        })
    } elseif ($line -match '\d+(?:\.\d+)? fps, .* ms/frame') { $state.malformedFrameSamples++ }
    if ($line -match 'memory: (\d+) MB private \((\d+) MB of it in memory; the PC has (\d+) MB free and (\d+) MB left to commit\)') {
        $memory.Add([pscustomobject]@{logLine=$lineNumber;timestamp=$timestamp;privateMiB=[long]$Matches[1];residentPrivateMiB=[long]$Matches[2];availablePhysicalMiB=[long]$Matches[3];availableCommitMiB=[long]$Matches[4]})
    }
    # Host::log_video_memory shifts bytes by 20 despite its historical MB label.
    # Preserve local/shared budgets separately; they overlap process accounting.
    if ($line -match "video memory as the system counts it, .*: the card's own: budget (\d+) MB, in use (\d+) MB, \d+ MB could still be reserved, \d+ MB reserved; the PC's shared with the card: budget (\d+) MB, in use (\d+) MB") {
        $videoMemory.Add([pscustomobject]@{timestamp=$timestamp;localBudgetMiB=[uint64]$Matches[1];localUsedMiB=[uint64]$Matches[2];sharedBudgetMiB=[uint64]$Matches[3];sharedUsedMiB=[uint64]$Matches[4]})
    }
    if ($line.Contains('memory sample (retained except made_*;')) {
        # Keep the runtime's names and units. None is an unavailable try_lock,
        # not an empty pool. These overlapping counters must never be summed.
        $fields=[ordered]@{logLine=$lineNumber;timestamp=$timestamp}
        foreach ($field in [regex]::Matches($line, '\b(?<key>[a-z][a-z0-9_]*)=(?<value>Some\((?:\d+|true|false)\)|None|\d+)(?=\s|$)')) {
            $value=$field.Groups['value'].Value
            $fields[$field.Groups['key'].Value]=if ($value -eq 'None') { $null } elseif ($value -eq 'Some(true)') { $true } elseif ($value -eq 'Some(false)') { $false } else { [uint64]($value -replace '^Some\((\d+)\)$','$1') }
        }
        if ($fields.Contains('elapsed_ms') -and $fields.Contains('private_bytes')) {
            $timedMemory.Add([pscustomobject]$fields)
        }
    }
    if ($line -match '^library checkpoint: made=(\d+) loaded=(\d+) saved_bytes=(\d+)$') {
        $pipelineCache.Add([pscustomobject]@{logLine=$lineNumber;timestamp=$timestamp;event='offline-checkpoint';made=[uint64]$Matches[1];loaded=[uint64]$Matches[2];saved_bytes=[uint64]$Matches[3]})
    }
    if ($line -match 'host pipeline library (saved|loaded)') {
        $fields=[ordered]@{logLine=$lineNumber;timestamp=$timestamp;event=$Matches[1]}
        foreach ($field in [regex]::Matches($line, '\b(?<key>bytes|early|made|loaded|started_early)=(?<value>\d+)(?=\s|$)')) {
            $fields[$field.Groups['key'].Value]=[uint64]$field.Groups['value'].Value
        }
        $pipelineCache.Add([pscustomobject]$fields)
    }
    if ($line -match '^(\d+) pipelines known, (\d+) made before \([a-f0-9]+\), (\d+) bad; (\d+) to make, (\d+) processes') {
        $precompile.requested=$true; $precompile.known=[int]$Matches[1]; $precompile.previouslyProcessed=[int]$Matches[2]
        $precompile.previouslyBad=[int]$Matches[3]; $precompile.selected=[int]$Matches[4]; $precompile.processes=[int]$Matches[5]
    }
    if ($line -match '^(\d+) made in (\d+) s \((\d+) have no host pipeline, (\d+) ended their process\);') {
        $precompile.completed=$true; $precompile.processed=[int]$Matches[1]; $precompile.elapsedSeconds=[int]$Matches[2]
        $precompile.refused=[int]$Matches[3]; $precompile.childFailures=[int]$Matches[4]
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
if ($precompile.requested -and -not $precompile.completed) { $warnings.Add('Precompilation has no completion summary. A successful launch or warm-done file does not establish that all requested host pipelines were created.') }
$allocationAtLimit = $state.allocationFailureMessages -gt 0 -and $null -ne $state.jobCommitLimitBytes -and $state.peakJobCommitBytes -ge $state.jobCommitLimitBytes
if ($allocationAtLimit) { $warnings.Add('The runtime logged an allocation failure and the job reached its hard cap. A later runner guard or cleanup exit must not hide that failure; the logs alone do not attribute every allocation to a subsystem.') }
if ($state.cleanupFailure) { $warnings.Add('Cleanup reported a failure. Package access restoration and profile deletion are separate outcomes; the launcher exit code may describe cleanup instead of the runtime.') }
$lastDisplay = $displayModes | Select-Object -Last 1
$lastSwapchain = $swapchains | Select-Object -Last 1
$swapchainMatchesRequest = $null
if ($metadata.requestedGuestDisplayMode -and $lastSwapchain) {
    $swapchainMatchesRequest = ('{0}x{1}' -f $lastSwapchain.width, $lastSwapchain.height) -eq $metadata.requestedGuestDisplayMode
    if (-not $swapchainMatchesRequest) { $warnings.Add('The observed swapchain does not match the requested guest display mode. This is not a verified lower-resolution rendering test.') }
}
$report = [ordered]@{
    schemaVersion=1; run=(Split-Path -Leaf $runPath); generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
    interpretation='Interval samples only. Sample median is not whole-run FPS or a 1% low. CPU preparation is a subset of frame time. runtimeGpuWaitMs (legacy gpuMs) measures CPU fence/landing waits, not hardware GPU execution time; overlapping queued work must not be summed. Visible, responsive gameplay and audible output require independent evidence.'
    timing=[ordered]@{
        metadataGpuTiming=$metadataGpuTiming
        interpretation='runtimeGpuWaitMs is the aggregate CPU fence/landing wait counter; gpuMs is its compatibility alias, not hardware GPU timestamp duration. No hardware GPU duration is inferred from this aggregate, even when metadataGpuTiming is true. That flag records a diagnostic request only; absent or non-boolean metadata is unknown.'
    }
    checkout=$metadata.checkout; checkoutDirty=$metadata.checkoutDirty; runtimeSha256=$metadata.runtimeSha256
    requestedRenderer=$metadata.renderer; console=$metadata.console; adapter=$state.adapter; softwareAdapter=$state.software; vramMiB=$state.vramMiB
    resolution=[ordered]@{
        requestedGuestDisplayMode=$metadata.requestedGuestDisplayMode
        requestedGuestOutput=$metadata.requestedGuestOutput
        appliedGuestOutput=$appliedGuestOutputState.last; appliedGuestOutputCount=$appliedGuestOutputState.count
        appliedGuestOutputHistory=@($appliedGuestOutputs.ToArray())
        legacyPresentationOnly=$metadata.legacy720pPresentationOnly
        reportedGuestDisplay=$lastDisplay; observedSwapchain=$lastSwapchain
        initialSwapchain=$swapchainState.first; swapchainObservationCount=$swapchainState.count
        swapchainHistory=@($swapchains.ToArray())
        swapchainMatchesRequest=$swapchainMatchesRequest
        interpretation='The guest display report, swapchain and internal render targets are different. Display-mode and guest-output requests do not prove that a change was applied. appliedGuestOutput records only the verified loader success event; its absence is unknown, not proof of failure, and its presence does not establish actual rendering dimensions. observedSwapchain is the latest recognized creation or resize, not the size of the entire run. Both histories are bounded tails in log order. A matching swapchain alone does not prove every pass renders at that size. Missing observations remain unknown.'
    }
    elapsedSeconds=$metadata.elapsedSeconds; launcherExitCode=$metadata.exitCode
    stopReason=$state.stopReason; childResult=$state.childResult
    runtimeResultBeforeCleanup=$state.runtimeResultBeforeCleanup; cleanupFailure=$state.cleanupFailure
    allocationFailureAtJobLimit=$allocationAtLimit
    peakJobCommitBytes=$state.peakJobCommitBytes; jobCommitLimitBytes=$state.jobCommitLimitBytes
    availablePhysicalBytesAtStop=$state.stoppedPhysicalBytes; reservePhysicalBytes=$state.reservePhysicalBytes
    availableCommitBytesAtStop=$state.stoppedCommitBytes; reserveCommitBytes=$state.reserveCommitBytes
    jobCommitBytesAtStop=$state.stoppedJobBytes; jobStopThresholdBytes=$state.jobStopThresholdBytes
    restoredPackagePaths=$state.restoredPaths; zeroCapabilityAppContainerVerified=$state.zeroCapabilityAppContainerVerified
    allSamples=(SampleSummary $samples.ToArray()); tailSamples=@($samples | Select-Object -Last $TailSamples)
    memorySamples=$memory.Count; lastMemorySample=($memory | Select-Object -Last 1)
    thinUploadReclamation=[ordered]@{
        count=$thinUploadState.count; units='uploads/frame'
        sampledMaximumUploadsPerFrame=$thinUploadState.maximum
        lastSample=$thinUploadState.last; tailSamples=@($thinUploadTail.ToArray())
        interpretation='Interval-average reclaimed pending-upload counts per frame, not bytes or a cumulative upload total. Maximum covers matching log samples; only the bounded tail is retained. Missing samples are unknown, not zero. This counter alone does not establish a leak cause or memory savings.'
    }
    videoMemory=[ordered]@{
        count=$videoMemory.Count
        lastSample=($videoMemory | Select-Object -Last 1)
        interpretation='DXGI process local/shared usage and changing budgets in MiB; not installed capacity or an additional amount to sum with private bytes. Shared usage does not by itself prove VRAM eviction.'
    }
    timedMemory=[ordered]@{
        count=$timedMemory.Count
        interpretation='Independent timer samples, including frame stalls. Byte counters overlap; do not sum them. made_* counters are cumulative, other allocation counters are retained. Missing fields and null pool values are unknown, not zero. Card-side counters may include shared-memory fallbacks.'
        sampledPeakPrivateBytes=if ($timedMemory.Count) { ($timedMemory | Measure-Object private_bytes -Maximum).Maximum } else { $null }
        lastSample=($timedMemory | Select-Object -Last 1)
        tailSamples=@($timedMemory | Select-Object -Last $TailSamples)
    }
    precompile=$precompile
    pipelineCacheEvents=@($pipelineCache.ToArray())
    jobProcessMemorySamples=$jobMemory.Count
    jobProcesses=@($jobMemory | Group-Object processId | ForEach-Object {
        [pscustomobject]@{ processId=[int]$_.Name; sampledPeakPrivateBytes=($_.Group | Measure-Object privateBytes -Maximum).Maximum; sampledPeakWorkingSetBytes=($_.Group | Measure-Object workingSetBytes -Maximum).Maximum; lastSample=$_.Group[-1] }
    })
    deviceRemovalMessages=$state.deviceRemovedMessages; allocationFailureMessages=$state.allocationFailureMessages
    phaseEvidence=@($phaseGroups.ToArray()); warnings=@($warnings.ToArray())
}
if ($IncludeSamples) { $report['samples']=$samples.ToArray(); $report.timedMemory['samples']=$timedMemory.ToArray(); $report.videoMemory['samples']=$videoMemory.ToArray() }
$json=$report | ConvertTo-Json -Depth 12
if ($OutFile) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutFile), $json + "`n", (New-Object Text.UTF8Encoding($false))) }
if ($AsObject) { [pscustomobject]$report } else { $json }
