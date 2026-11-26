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
    Write-Output "$passed synthetic diagnostic-summary checks passed."
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture=$culture
    $parentPrefix=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
    if (-not $root.StartsWith($parentPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $root) -notmatch '^\.summary-test-[a-f0-9]{32}$') { throw 'Refusing cleanup outside the uniquely created test directory.' }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
