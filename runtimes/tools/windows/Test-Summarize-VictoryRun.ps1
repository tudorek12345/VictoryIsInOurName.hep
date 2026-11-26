[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$helper=Join-Path $PSScriptRoot 'Summarize-VictoryRun.ps1'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('.summary-test-'+[Guid]::NewGuid().ToString('N'))))
$logs=Join-Path $root 'synthetic\logs'
$null=New-Item -ItemType Directory -Path $logs -Force
$passed=0
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Write-Text([string]$Path,[string]$Value) { [IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false))) }
function Report { & $helper -Run synthetic -StageRoot $root -AsObject -IncludeSamples }
$runner=Join-Path $logs 'runner.log'
$victory=Join-Path $logs 'victory.log'
$metadata=Join-Path $logs 'diagnostics.json'
$culture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    Write-Text $metadata '{"renderer":"hardware","console":"series-s","checkout":"test-only","elapsedSeconds":10,"exitCode":126}'
    Write-Text $runner @'
Verified zero-capability AppContainer and bounded job. Child PID 1
Host memory guard reached. Available physical bytes: 2000000000; reserve bytes: 3221225472. Terminating job.
Peak job commit bytes: 4000000000; limit bytes: 8000000000
Verified restored package access rules on 151 paths.
Job ended and stage grants were restored. Child result 126
'@
    $frame1='2026-01-01T00:00:01Z INFO victory_gpu::host: 30.0 fps, 33.3 ms/frame (2.5 preparing: copies 1.0 ms 2.0 MB, textures 0.5 ms 1.0 MB; 3.0 on the GPU; 0.0 copying back 0.0 MB), 4 draws/frame, dropped 0 without a host pipeline (0 being made) and 0 indirect'
    $frame2='2026-01-01T00:00:02Z INFO victory_gpu::host: 10.0 fps, 100.0 ms/frame (40.0 preparing: copies 10.0 ms 2.0 MB, textures 20.0 ms 1.0 MB; 45.0 on the GPU; 2.0 copying back 0.0 MB), 12 draws/frame, dropped 100 without a host pipeline (30 being made) and 20 indirect'
    $frame3='2026-01-01T00:00:03Z INFO victory_gpu::host: 2.0 fps, 500.0 ms/frame (200.0 preparing: copies 90.0 ms 2.0 MB, textures 100.0 ms 1.0 MB; 250.0 on the GPU; 20.0 copying back 0.0 MB), 1000 draws/frame, dropped 3 without a host pipeline (5 being made) and 6 indirect'
    $esc=[char]27
    $text = "${esc}[2m2026-01-01T00:00:00Z${esc}[0m INFO victory_gpu::host: host D3D12 adapter adapter=`"Synthetic Radeon`" vendor_id=4098 software=false vram_mib=16384`n$frame1`n$frame2`n$frame3`n2026-01-01T00:00:03Z memory: 512 MB private (256 MB of it in memory; the PC has 8192 MB free and 16000 MB left to commit)`n"
    Write-Text $victory $text
    $r=Report
    Assert ($r.allSamples.count -eq 3 -and $r.allSamples.fps.median -eq 10 -and $r.samples[0].prepareMs -eq 2.5 -and $r.samples[2].pipelinesBeingMade -eq 5) 'Full metric parsing or interval median is wrong.'
    Assert ($r.adapter -eq 'Synthetic Radeon' -and $r.softwareAdapter -eq $false -and $r.vramMiB -eq 16384) 'ANSI adapter fields were not parsed.'
    Assert ($r.lastMemorySample.availablePhysicalMiB -eq 8192 -and $r.lastMemorySample.privateMiB -eq 512) 'Memory counters were not parsed.'
    $passed++
    Assert ($r.samples[0].runtimeGpuWaitMs -eq 3 -and $r.samples[2].runtimeGpuWaitMs -eq 250 -and $r.samples[2].gpuMs -eq $r.samples[2].runtimeGpuWaitMs -and $r.tailSamples[-1].runtimeGpuWaitMs -eq 250 -and $r.allSamples.runtimeGpuWaitMs.median -eq 45 -and $r.allSamples.gpuMs.median -eq 45) 'CPU GPU-wait samples and summaries must preserve the legacy values without relabeling them as hardware durations.'
    Assert ($null -eq $r.timing.metadataGpuTiming -and $r.timing.interpretation -match 'not hardware GPU timestamp duration' -and $r.interpretation -match 'CPU fence/landing waits') 'Missing timestamp-request metadata must remain unknown and aggregate timing must identify CPU waits.'
    $passed++
    $originalMetadata=Get-Content -LiteralPath $metadata -Raw
    foreach ($case in @(
        @{json='{"gpuTiming":true}'; expected=$true},
        @{json='{"gpuTiming":false}'; expected=$false},
        @{json='{"gpuTiming":null}'; expected=$null},
        @{json='{"gpuTiming":"false"}'; expected=$null}
    )) {
        Write-Text $metadata $case.json
        $timingReport=Report
        Assert ($timingReport.timing.metadataGpuTiming -eq $case.expected -and $timingReport.samples[0].runtimeGpuWaitMs -eq 3 -and $timingReport.timing.interpretation -match 'even when metadataGpuTiming is true' -and -not $timingReport.samples[0].PSObject.Properties['hardwareGpuMs']) 'Timestamp-request metadata must preserve boolean/unknown values and never manufacture hardware GPU time from the aggregate.'
    }
    Write-Text $metadata $originalMetadata
    $passed++
    Assert ($r.phaseEvidence.Count -eq 0 -and -not $r.PSObject.Properties['gameplayVerified'] -and $r.interpretation -match 'not whole-run FPS') 'Draw counts must not infer gameplay or whole-run FPS.'
    $passed++
    Assert ($r.stopReason -eq 'physical memory reserve' -and $r.availablePhysicalBytesAtStop -eq 2000000000 -and $r.restoredPackagePaths -eq 151 -and $r.peakJobCommitBytes -eq 4000000000 -and $r.zeroCapabilityAppContainerVerified) 'Guard and cleanup evidence was not retained.'
    $passed++
    Write-Text $runner 'Host commit guard reached. Available commit bytes: 12345678; reserve bytes: 4294967296. Terminating job.'
    $r=Report
    Assert ($r.stopReason -eq 'system commit reserve' -and $r.availableCommitBytesAtStop -eq 12345678 -and $null -eq $r.availablePhysicalBytesAtStop -and $null -eq $r.restoredPackagePaths) 'Commit stop must not imply a physical stop or cleanup.'
    $passed++
    Write-Text $runner 'Timeout reached. Terminating job.'
    Assert ((Report).stopReason -eq 'timer') 'Timer termination parsing failed.'
    $passed++
    Write-Text $victory ($text+"2026-01-01T00:00:04Z 8.0 fps, 125.0 ms/frame (new unrecognized layout)`n")
    $r=Report
    Assert ($r.allSamples.count -eq 3 -and @($r.warnings | Where-Object { $_ -match '1 frame-stat lines' }).Count -eq 1) 'Unknown timing formats must be reported, not silently counted.'
    $passed++
    $phaseFile=Join-Path $root 'phases.json'
    Write-Text $phaseFile '[{"label":"observed test interval","evidence":"synthetic screenshot observation","startUtc":"2026-01-01T00:00:01Z","endUtc":"2026-01-01T00:00:03Z"}]'
    $r=& $helper -Run synthetic -StageRoot $root -PhaseEvidencePath $phaseFile -AsObject
    Assert ($r.phaseEvidence.Count -eq 1 -and $r.phaseEvidence[0].samples.count -eq 2 -and $r.phaseEvidence[0].samples.fps.median -eq 20) 'Phase selection must include start, exclude end and preserve supplied evidence.'
    $passed++
    Write-Text $phaseFile '[{"label":"gameplay","startUtc":"2026-01-01T00:00:01Z","endUtc":"2026-01-01T00:00:03Z"}]'
    $rejected=$false
    try { $null=& $helper -Run synthetic -StageRoot $root -PhaseEvidencePath $phaseFile -AsObject } catch { $rejected=$_.Exception.Message -match 'Each phase needs' }
    Assert $rejected 'Phase labels with no supporting evidence must fail.'
    $passed++
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $r=Report
    Assert ($r.samples[0].prepareMs -eq 2.5) 'Decimal parsing must not depend on locale.'
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    $passed++
    Remove-Item -LiteralPath $metadata
    Write-Text $victory ''
    Write-Text $runner ''
    $output=Join-Path $root 'summary.json'
    $r=& $helper -Run synthetic -StageRoot $root -AsObject -OutFile $output
    $readBack=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    Assert ($r.allSamples.count -eq 0 -and $r.stopReason -eq 'not recorded' -and $null -eq $r.launcherExitCode -and $readBack.schemaVersion -eq 1) 'An unfinished empty run must stay unknown and serialize as JSON.'
    $passed++
    Write-Text $runner @'
Job memory sample: elapsed_ms=0 pid=10 private_bytes=100 working_set_bytes=80
Job memory sample: elapsed_ms=5000 pid=10 private_bytes=200 working_set_bytes=70
Job memory sample: elapsed_ms=5000 pid=11 private_bytes=300 working_set_bytes=150
'@
    $r=Report
    $parentSample=@($r.jobProcesses | Where-Object processId -eq 10)[0]
    Assert ($r.jobProcessMemorySamples -eq 3 -and $r.jobProcesses.Count -eq 2 -and $parentSample.sampledPeakPrivateBytes -eq 200 -and $parentSample.sampledPeakWorkingSetBytes -eq 80 -and $parentSample.lastSample.elapsedMs -eq 5000) 'Job members and sampled memory peaks must remain separate.'
    $passed++
    Write-Text $victory @"
${esc}[2m2026-01-01T00:00:01Z${esc}[0m memory sample (retained except made_*; pool None means unavailable) elapsed_ms=0 frame=9 private_bytes=4000000000 rust_bytes=100 host_texture_bytes=200 texture_pool_bytes=Some(300) staging_pool_bytes=None made_upload_bytes=123
2026-01-01T00:00:02Z memory sample (retained except made_*; pool None means unavailable) elapsed_ms=1000 frame=9 private_bytes=6000000000 rust_bytes=120 host_texture_bytes=250 texture_pool_bytes=None staging_pool_bytes=Some(0) made_upload_bytes=456
2026-01-01T00:00:03Z memory sample (retained except made_*; pool None means unavailable) frame=9
"@
    $r=Report
    Assert ($r.allSamples.count -eq 0 -and $r.timedMemory.count -eq 2 -and $r.timedMemory.sampledPeakPrivateBytes -eq 6000000000 -and $r.timedMemory.lastSample.frame -eq 9) 'Timed memory growth during a stalled frame must be retained without frame samples.'
    Assert ($r.timedMemory.samples[0].texture_pool_bytes -eq 300 -and $null -eq $r.timedMemory.samples[0].staging_pool_bytes -and $null -eq $r.timedMemory.lastSample.texture_pool_bytes -and $r.timedMemory.lastSample.staging_pool_bytes -eq 0) 'Unavailable pool snapshots must stay distinct from zero.'
    Assert ($r.timedMemory.lastSample.made_upload_bytes -eq 456 -and $r.timedMemory.interpretation -match 'do not sum' -and -not $r.timedMemory.lastSample.PSObject.Properties['total_bytes']) 'Cumulative and overlapping memory counters must not be added.'
    $passed++
    Write-Text $victory ''
    $r=Report
    Assert ($r.timedMemory.count -eq 0 -and $null -eq $r.timedMemory.sampledPeakPrivateBytes -and $null -eq $r.timedMemory.lastSample) 'An absent timer sample must not imply zero memory use.'
    $passed++
    Write-Text $victory @'
100 pipelines known, 10 made before (abcd1234), 2 bad; 20 to make, 2 processes
2026-01-01T00:00:01Z host pipeline library loaded bytes=4096 mapped=true
2026-01-01T00:00:02Z host pipeline library saved bytes=8192 early=20 made=4 loaded=15 started_early=20
'@
    $r=Report
    Assert ($r.precompile.requested -and -not $r.precompile.completed -and $r.precompile.selected -eq 20 -and $null -eq $r.precompile.refused) 'A started warmer must not be counted as completed or free of failures.'
    Assert ($r.pipelineCacheEvents.Count -eq 2 -and $r.pipelineCacheEvents[0].event -eq 'loaded' -and $r.pipelineCacheEvents[1].loaded -eq 15 -and $r.pipelineCacheEvents[1].made -eq 4) 'Actual cache loads and new pipeline creation must remain distinct.'
    $passed++
    Add-Content -LiteralPath $victory -Value "`n19 made in 123 s (3 have no host pipeline, 1 ended their process); ms each: median 1.0"
    $r=Report
    Assert ($r.precompile.completed -and $r.precompile.processed -eq 19 -and $r.precompile.refused -eq 3 -and $r.precompile.childFailures -eq 1) 'A warmer completion must retain refused pipelines and child failures separately.'
    $passed++
    Add-Content -LiteralPath $victory -Value "`nlibrary checkpoint: made=6 loaded=0 saved_bytes=4096`nlibrary checkpoint: made=0 loaded=6 saved_bytes=0"
    $r=Report
    $checkpoints=@($r.pipelineCacheEvents | Where-Object event -eq 'offline-checkpoint')
    Assert ($checkpoints.Count -eq 2 -and $checkpoints[0].made -eq 6 -and $checkpoints[0].saved_bytes -eq 4096 -and $checkpoints[1].loaded -eq 6 -and $checkpoints[1].saved_bytes -eq 0) 'Offline checkpoints must distinguish created pipelines, library reuse and bytes actually written.'
    $passed++
    Write-Text $runner @'
Job commit guard reached. Committed bytes: 5500000000; stop threshold bytes: 5400000000; hard limit bytes: 6000000000. Terminating job.
Runtime result before cleanup 126
DeleteAppContainerProfile failed for Synthetic (0x80070020)
'@
    Write-Text $victory ''
    $r=Report
    Assert ($r.stopReason -eq 'job commit reserve' -and $r.jobCommitBytesAtStop -eq 5500000000 -and $r.jobStopThresholdBytes -eq 5400000000 -and $r.runtimeResultBeforeCleanup -eq 126 -and $r.cleanupFailure -and -not $r.allocationFailureAtJobLimit) 'Job notification and cleanup failures must be recorded separately.'
    $passed++
    Write-Text $runner @'
Host commit guard reached. Available commit bytes: 100000; reserve bytes: 4294967296. Terminating job.
Peak job commit bytes: 6000000000; limit bytes: 6000000000
DeleteAppContainerProfile failed for Synthetic (0x80070020)
'@
    Write-Text $victory 'memory allocation of 1048576 bytes failed'
    $r=Report
    Assert ($r.allocationFailureAtJobLimit -and $r.allocationFailureMessages -eq 1 -and $r.stopReason -eq 'system commit reserve' -and $r.cleanupFailure -and $null -eq $r.runtimeResultBeforeCleanup) 'An allocation failure at the hard cap must not be hidden by a later guard or cleanup failure.'
    $passed++
    Write-Text $runner ''
    Assert (-not (Report).allocationFailureAtJobLimit) 'An allocation error alone must not imply reaching the job limit.'
    $passed++
    Write-Text $victory @'
2026-01-01T00:00:01Z video memory as the system counts it, synthetic: the card's own: budget 16000 MB, in use 7000 MB, 100 MB could still be reserved, 0 MB reserved; the PC's shared with the card: budget 15000 MB, in use 6000 MB, 100 MB could still be reserved, 0 MB reserved
2026-01-01T00:00:02Z video memory as the system counts it, synthetic: the card's own: budget 14000 MB, in use 8000 MB, 100 MB could still be reserved, 0 MB reserved; the PC's shared with the card: budget 15000 MB, in use 0 MB, 100 MB could still be reserved, 0 MB reserved
'@
    $r=Report
    Assert ($r.videoMemory.count -eq 2 -and $r.videoMemory.samples[0].sharedUsedMiB -eq 6000 -and $r.videoMemory.lastSample.localBudgetMiB -eq 14000 -and $r.videoMemory.lastSample.localUsedMiB -eq 8000 -and $r.videoMemory.lastSample.sharedUsedMiB -eq 0) 'Changing DXGI budgets and zero shared usage must remain distinct from capacity or missing data.'
    $passed++
    Write-Text $victory ''
    $r=Report
    Assert ($r.videoMemory.count -eq 0 -and $null -eq $r.videoMemory.lastSample) 'Absent DXGI samples must remain unknown.'
    $passed++
    Write-Text $victory @'
2026-01-01T00:00:01Z memory sample (retained except made_*; owner/pool None means unknown; owner buckets are not exhaustive) elapsed_ms=1000 private_bytes=100 host_idle_lists=Some(512) host_inflight_lists=None host_landing_active=Some(true) retired_resources=Some(800) submissions_finished=52
2026-01-01T00:00:02Z memory sample (retained except made_*; owner/pool None means unknown; owner buckets are not exhaustive) elapsed_ms=2000 private_bytes=110 host_idle_lists=None host_inflight_lists=Some(0) host_landing_active=Some(false) retired_resources=Some(0) submissions_finished=53
'@
    $r=Report
    Assert ($r.timedMemory.count -eq 2 -and $r.timedMemory.samples[0].host_idle_lists -eq 512 -and $null -eq $r.timedMemory.samples[0].host_inflight_lists -and $r.timedMemory.samples[0].host_landing_active -eq $true -and $r.timedMemory.lastSample.host_landing_active -eq $false -and $r.timedMemory.lastSample.host_inflight_lists -eq 0 -and $null -eq $r.timedMemory.lastSample.host_idle_lists) 'Busy ownership snapshots and landing flags must preserve unknown, false and zero separately.'
    $passed++
    Write-Text $metadata '{"requestedGuestDisplayMode":"1920x1080","legacy720pPresentationOnly":false}'
    Write-Text $victory ("${esc}[2m2026-01-01T00:00:01Z${esc}[0m display mode reported to the title width=1920 height=1080`n2026-01-01T00:00:02Z presenting to a window width=3840 height=2160 format=28")
    $r=Report
    Assert ($r.resolution.reportedGuestDisplay.width -eq 1920 -and $r.resolution.observedSwapchain.width -eq 3840 -and $r.resolution.swapchainMatchesRequest -eq $false -and @($r.warnings | Where-Object { $_ -match 'not a verified lower-resolution' }).Count -eq 1) 'A guest mode request must not masquerade as actual lower-resolution rendering.'
    $passed++
    Write-Text $victory 'presenting to a window width=1920 height=1080 format=28'
    $r=Report
    Assert ($r.resolution.swapchainMatchesRequest -eq $true -and $null -eq $r.resolution.reportedGuestDisplay -and $r.resolution.interpretation -match 'does not prove every pass') 'Matching output size must not imply internal render-target sizes.'
    $passed++
    Write-Text $victory ''
    $r=Report
    Assert ($null -eq $r.resolution.observedSwapchain -and $null -eq $r.resolution.swapchainMatchesRequest) 'Absent swapchain observations must stay unknown.'
    $passed++
    Write-Text $metadata '{}'
    Write-Text $victory 'presenting to a window width=3840 height=2160 format=28'
    $r=Report
    Assert ($r.resolution.observedSwapchain.height -eq 2160 -and $null -eq $r.resolution.swapchainMatchesRequest) 'An observed output without a request is not a mode mismatch.'
    $passed++
    Write-Text $metadata '{"requestedGuestDisplayMode":"1920x1080"}'
    Write-Text $victory @'
2026-01-01T00:00:01Z presenting to a window width=3840 height=2160 format=28
2026-01-01T00:00:02Z the swap chain's buffers were made again for another size or format width=1920 height=1080 format=28 frame=30
2026-01-01T00:00:03Z the swap chain's buffers were made again for another size or format width=3840 height=2160 format=28 frame=60
2026-01-01T00:00:04Z the swap chain's buffers were made again for another size or format width=1920 height=1080 format=28 frame=90
'@
    $r=& $helper -Run synthetic -StageRoot $root -AsObject -IncludeSamples -TailSamples 2
    Assert ($r.resolution.swapchainObservationCount -eq 4 -and $r.resolution.initialSwapchain.width -eq 3840 -and $r.resolution.initialSwapchain.event -eq 'created' -and $r.resolution.observedSwapchain.width -eq 1920 -and $r.resolution.observedSwapchain.event -eq 'resized' -and $r.resolution.observedSwapchain.logLine -eq 4 -and $r.resolution.swapchainMatchesRequest -eq $true) 'The latest actual resize must replace initial dimensions without losing the first observation or inventing a whole-run resolution.'
    Assert ($r.resolution.swapchainHistory.Count -eq 2 -and $r.resolution.swapchainHistory[0].logLine -eq 3 -and $r.resolution.swapchainHistory[0].timestamp -eq '2026-01-01T00:00:03Z' -and $r.resolution.swapchainHistory[0].width -eq 3840 -and $r.resolution.swapchainHistory[1].timestamp -eq '2026-01-01T00:00:04Z' -and $r.resolution.swapchainHistory[1].width -eq 1920) 'Swapchain history must preserve source order and timestamps while remaining bounded even with IncludeSamples.'
    $passed++
    Write-Text $victory "2026-01-01T00:00:05Z swapchain resized to 1280x720`n2026-01-01T00:00:06Z the swap chain's buffers were made again for another size or format size=1280x720"
    $r=Report
    Assert ($r.resolution.swapchainObservationCount -eq 0 -and $null -eq $r.resolution.initialSwapchain -and $null -eq $r.resolution.observedSwapchain -and $r.resolution.swapchainHistory.Count -eq 0 -and $null -eq $r.resolution.swapchainMatchesRequest) 'Unrecognized old resize formats must stay unknown rather than inventing actual dimensions.'
    $passed++
    Write-Text $metadata '{"requestedGuestOutput":"1920x1080"}'
    Write-Text $victory 'presenting to a window width=3840 height=2160 format=28'
    $r=Report
    Assert ($r.resolution.requestedGuestOutput -eq '1920x1080' -and $null -eq $r.resolution.requestedGuestDisplayMode -and $r.resolution.observedSwapchain.width -eq 3840 -and $null -eq $r.resolution.swapchainMatchesRequest -and $null -eq $r.resolution.appliedGuestOutput) 'A guest-output request must remain separate from a display-mode request and must not imply successful application or changed observed output.'
    $passed++
    Write-Text $victory @"
${esc}[2m2026-01-01T00:00:01Z${esc}[0m INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=1920 height=1080
2026-01-01T00:00:02Z presenting to a window width=3840 height=2160 format=28
2026-01-01T00:00:03Z INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=2560 height=1440
2026-01-01T00:00:04Z INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=1280 height=720
"@
    $r=& $helper -Run synthetic -StageRoot $root -AsObject -IncludeSamples -TailSamples 2
    Assert ($r.resolution.appliedGuestOutputCount -eq 3 -and $r.resolution.appliedGuestOutput.width -eq 1280 -and $r.resolution.appliedGuestOutput.height -eq 720 -and $r.resolution.appliedGuestOutput.nativeRenderScaleUnchanged -eq $true -and $r.resolution.appliedGuestOutput.logLine -eq 4 -and $r.resolution.appliedGuestOutput.timestamp -eq '2026-01-01T00:00:04Z') 'Only a complete verified loader success event must establish the applied guest-output dimensions and source position.'
    Assert ($r.resolution.appliedGuestOutputHistory.Count -eq 2 -and $r.resolution.appliedGuestOutputHistory[0].width -eq 2560 -and $r.resolution.appliedGuestOutputHistory[0].logLine -eq 3 -and $r.resolution.appliedGuestOutputHistory[1].width -eq 1280 -and $r.resolution.requestedGuestOutput -eq '1920x1080' -and $r.resolution.observedSwapchain.width -eq 3840) 'Application history must remain bounded and ordered while requested, applied and observed dimensions remain independent.'
    $passed++
    Write-Text $victory 'presenting to a window width=1920 height=1080 format=28'
    $r=Report
    Assert ($r.resolution.requestedGuestOutput -eq '1920x1080' -and $r.resolution.observedSwapchain.width -eq 1920 -and $null -eq $r.resolution.appliedGuestOutput -and $r.resolution.appliedGuestOutputCount -eq 0 -and $r.resolution.appliedGuestOutputHistory.Count -eq 0) 'A requested size matching the observed swapchain must not manufacture a loader application event.'
    $passed++
    Write-Text $victory @'
2026-01-01T00:00:01Z ERROR victory_loader::resolution: applying requested guest output before title execution: transaction failed width=1920 height=1080
2026-01-01T00:00:02Z INFO victory_loader::resolution: guest output: sites verified; output not applied; native scale unchanged width=1920 height=1080
2026-01-01T00:00:03Z INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=1920
2026-01-01T00:00:04Z INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=999999999999999999999 height=1080
2026-01-01T00:00:05Z INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=0 height=1080
2026-01-01T00:00:06Z INFO other_module: guest output: sites verified; output applied; native scale unchanged width=1920 height=1080
2026-01-01T00:00:07Z ERROR other_module: quoted INFO victory_loader::resolution: guest output: sites verified; output applied; native scale unchanged width=1920 height=1080
guest output   1920x1080; native render scale unchanged
'@
    $r=Report
    Assert ($null -eq $r.resolution.appliedGuestOutput -and $r.resolution.appliedGuestOutputCount -eq 0 -and $r.resolution.appliedGuestOutputHistory.Count -eq 0 -and $null -eq $r.resolution.observedSwapchain) 'Failure, partial, malformed, unrelated-module and caller status lines must not count as a verified application or actual presentation.'
    $passed++
    $thin='list calls translated by threads of ours per frame (VICTORY_THIN): 20 in 1.0 ms (all threads), 2.0 lists, 3.0 pieces; left in the middle 0.00'
    Write-Text $victory "2026-01-01T00:00:01Z INFO victory_gpu::list::thin: $thin"
    $r=Report
    Assert ($r.thinUploadReclamation.count -eq 0 -and $null -eq $r.thinUploadReclamation.sampledMaximumUploadsPerFrame -and $null -eq $r.thinUploadReclamation.lastSample -and $r.thinUploadReclamation.tailSamples.Count -eq 0) 'Old thin lines without reclamation must remain unknown, not zero.'
    $passed++
    Write-Text $victory ("${esc}[2m2026-01-01T00:00:01Z${esc}[0m INFO victory_gpu::list::thin: $thin; pending uploads reclaimed 3.50`n2026-01-01T00:00:02Z INFO victory_gpu::list::thin: $thin; pending uploads reclaimed 1.25`n2026-01-01T00:00:03Z INFO victory_gpu::list::thin: $thin; pending uploads reclaimed 2.75")
    $r=& $helper -Run synthetic -StageRoot $root -AsObject -IncludeSamples -TailSamples 2
    $reclaimed=$r.thinUploadReclamation
    Assert ($reclaimed.count -eq 3 -and $reclaimed.units -eq 'uploads/frame' -and $reclaimed.sampledMaximumUploadsPerFrame -eq 3.5 -and $reclaimed.lastSample.reclaimedUploadsPerFrame -eq 2.75 -and $reclaimed.lastSample.logLine -eq 3 -and $reclaimed.lastSample.timestamp -eq '2026-01-01T00:00:03Z' -and $reclaimed.tailSamples.Count -eq 2 -and $reclaimed.tailSamples[0].logLine -eq 2) 'Thin upload summaries must preserve source positions and interval units, keep a bounded tail, and compute the maximum across all matching samples.'
    Assert ($reclaimed.interpretation -match 'not bytes' -and $reclaimed.interpretation -match 'does not establish a leak cause' -and -not $reclaimed.Contains('totalBytes') -and -not $reclaimed.Contains('samples')) 'Reclamation rates must not imply bytes, leak attribution or unbounded sample storage.'
    $passed++
    Write-Text $victory "$thin; pending uploads reclaimed 0.00"
    $r=Report
    Assert ($r.thinUploadReclamation.count -eq 1 -and $r.thinUploadReclamation.sampledMaximumUploadsPerFrame -eq 0 -and $r.thinUploadReclamation.lastSample.reclaimedUploadsPerFrame -eq 0 -and $r.thinUploadReclamation.lastSample.logLine -eq 1 -and $null -eq $r.thinUploadReclamation.lastSample.timestamp) 'An observed zero upload rate must remain zero while a missing timestamp stays unknown.'
    $passed++
    Write-Output "$passed synthetic diagnostic-summary checks passed."
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    $parentPrefix=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
    if (-not $root.StartsWith($parentPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $root) -notmatch '^\.summary-test-[a-f0-9]{32}$') { throw 'Refusing cleanup outside the uniquely created test directory.' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
