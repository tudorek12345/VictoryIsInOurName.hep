$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'Seed-VictoryPipelineBook.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('victory-book-tests-' + [Guid]::NewGuid().ToString('N'))
$run = 'original-20261126-000000-00000001'
$stage = Join-Path $testRoot 'stage'
$root = Join-Path $stage $run
$pipelineRoot = Join-Path $root 'output\cache\pipelines'
$logs = Join-Path $root 'logs'
[void][IO.Directory]::CreateDirectory($pipelineRoot)
[void][IO.Directory]::CreateDirectory($logs)
$package = Join-Path $testRoot 'package\fixture.bin'
[void][IO.Directory]::CreateDirectory((Split-Path -Parent $package))
[IO.File]::WriteAllBytes($package, [byte[]]@(10,20,30,40))
$hash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
$summary = [ordered]@{ backend='victory'; victorySource='amd7900'; packageExecutableSha256=$hash; console='series-x'; runtimeSha256=('1'*64) }
$summaryPath = Join-Path $logs 'diagnostics.json'
$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath -Encoding utf8
$key = '01' * 16
$unused = '02' * 16
$earlyPath = Join-Path $pipelineRoot 'early-pipelines.txt'
[IO.File]::WriteAllText($earlyPath, "$key`n$unused`n$key`n")
$shader = [byte[]](@(5) + @(1)*32 + @([BitConverter]::GetBytes([uint32]4)) + @(10,11,12,13))
$entry = [byte[]](@(1)*16 + @(1,5) + @(1)*32 + @(0))
$pipeline = [byte[]](@([BitConverter]::GetBytes([uint32]$entry.Length)) + $entry)
$shaderPath = Join-Path $pipelineRoot 'known-shaders.bin'
$pipelinePath = Join-Path $pipelineRoot 'known-pipelines.bin'
[IO.File]::WriteAllBytes($shaderPath, $shader)
[IO.File]::WriteAllBytes($pipelinePath, $pipeline)
[IO.File]::WriteAllText((Join-Path $pipelineRoot 'host-pipelines.bin'), 'compiled artifact must not copy')
$baseArgs = @{BookRun=$run; StageRoot=$stage; PackageExecutable=$package}
$ok = Join-Path $testRoot 'seed-good'
$actual = & $helper @baseArgs -DestinationCache $ok
if ($actual.knownPipelines -ne 1 -or $actual.knownShaders -ne 1 -or
    $actual.selectedPipelines -ne 1 -or $actual.unavailablePipelines -ne 1 -or
    $actual.requestedPipelines -ne 2 -or $actual.derivedCacheCopied) { throw 'Counts or derived-cache exclusion failed.' }
if (Test-Path -LiteralPath (Join-Path $ok 'pipelines\host-pipelines.bin')) { throw 'Copied a compiled library.' }
if ((Get-Content -LiteralPath (Join-Path $ok 'pipelines\early-pipelines.txt')) -ne $key) { throw 'The intersection is incorrect.' }
$script:passed = 1
function Reject([string]$Name, [scriptblock]$Act) {
    $caught = $false
    try { & $Act | Out-Null } catch { $caught = $true }
    if (-not $caught) { throw "Expected rejection: $Name" }
    $script:passed++
}
Reject 'nonempty destination' { & $helper @baseArgs -DestinationCache $ok }
Reject 'original package destination' { & $helper @baseArgs -DestinationCache (Join-Path (Split-Path -Parent $package) 'cache') }
Reject 'source run destination' { & $helper @baseArgs -DestinationCache (Join-Path $root 'seed') }
$summary.packageExecutableSha256 = '0' * 64
$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath -Encoding utf8
Reject 'different package' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-hash') }
$summary.packageExecutableSha256 = $hash
$summary | ConvertTo-Json | Set-Content -LiteralPath $summaryPath -Encoding utf8
[IO.File]::WriteAllText($earlyPath, "not-a-key`n")
Reject 'invalid early key' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-key') }
[IO.File]::WriteAllText($earlyPath, "$key`n")
[IO.File]::WriteAllBytes($pipelinePath, [byte[]]$pipeline[0..($pipeline.Length - 2)])
Reject 'torn pipeline record' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-torn') }
if (Test-Path -LiteralPath (Join-Path $testRoot 'seed-torn')) { throw 'A rejected record created output.' }
[IO.File]::WriteAllBytes($pipelinePath, $pipeline)
$shader[1] = 9
[IO.File]::WriteAllBytes($shaderPath, $shader)
Reject 'missing referenced shader' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-missing') }
$shader[1] = 1
$shader[0] = 8
[IO.File]::WriteAllBytes($shaderPath, $shader)
Reject 'unknown shader stage' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-stage') }
$shader[0] = 5
[IO.File]::WriteAllBytes($shaderPath, $shader)
$pipeline[$pipeline.Length - 1] = 1
[IO.File]::WriteAllBytes($pipelinePath, $pipeline)
Reject 'graphics layout mismatch' { & $helper @baseArgs -DestinationCache (Join-Path $testRoot 'seed-layout') }
Write-Output "$script:passed pipeline-book seed tests passed. Synthetic fixtures: $testRoot"
