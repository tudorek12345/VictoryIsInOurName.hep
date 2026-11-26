[CmdletBinding()]
param([string]$LocalRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$helper = Join-Path $LocalRoot 'Resolve-VictoryCurrentPrewarm.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('victory-current-prewarm-' + [Guid]::NewGuid().ToString('N'))
$state = Join-Path $fixture 'stage\victory-amd-series-s-state'
$pipelineDir = Join-Path $state 'cache\pipelines'
New-Item -ItemType Directory -Path $pipelineDir, (Join-Path $state 'data') -Force | Out-Null
$files = @('known-pipelines.bin', 'known-shaders.bin', 'early-pipelines.txt')
foreach ($name in $files) { [IO.File]::WriteAllText((Join-Path $pipelineDir $name), 'authored fixture') }
$profile = Join-Path $state 'data\profile.txt'
[IO.File]::WriteAllText($profile, 'profile must remain untouched')
$before = (Get-FileHash -LiteralPath $profile).Hash
$valid = @{ StateRoot=$state; PrewarmPipelines=$true; PrewarmLibrary=$true }
$checks = 0
function Reject([string]$Label, [hashtable]$Changes) {
    $options = $valid.Clone()
    foreach ($key in $Changes.Keys) { $options[$key] = $Changes[$key] }
    $rejected = $false
    try { $null = & $helper @options } catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid current-cache prewarm: $Label" }
    $script:checks++
    Write-Output "PASS rejects $Label"
}
$resolved = & $helper @valid
if ($resolved.mode -ne 'shared-content-keyed' -or $resolved.state -ne $state -or
    $resolved.libraryWriters -ne 1 -or $resolved.knownPipelineBytes -ne 16 -or
    $resolved.knownShaderBytes -ne 16 -or $resolved.earlyPipelineBytes -ne 16) {
    throw 'Wrong current-cache mode, file evidence or writer count.'
}
$checks++
Write-Output 'PASS active hardware current-cache mode with one writer'
Reject 'XCL backend' @{ Backend='xcl' }
Reject 'inactive candidate' @{ VictorySource='review' }
Reject 'software adapter' @{ Renderer='warp' }
Reject 'missing pipeline warm' @{ PrewarmPipelines=$false }
Reject 'missing persistent library warm' @{ PrewarmLibrary=$false }
Reject 'prepare-only operation' @{ PrepareOnly=$true }
foreach ($switch in @('FreshState','Test720p')) { Reject $switch @{ $switch=$true } }
foreach ($option in @('DisplayMode','WarmCacheFrom','PipelineBookFrom','PipelineUseFrom')) {
    Reject $option @{ $option='conflicting request' }
}
Reject 'nonshared output path' @{ StateRoot=(Join-Path $fixture 'stage\original-20000101-000000-00000001\output') }
Reject 'relative state path' @{ StateRoot='stage\victory-amd-series-s-state' }
foreach ($name in $files) {
    $path = Join-Path $pipelineDir $name
    [IO.File]::WriteAllBytes($path, [byte[]]@())
    Reject "empty $name" @{}
    [IO.File]::WriteAllText($path, 'authored fixture')
}
Remove-Item -LiteralPath (Join-Path $pipelineDir 'known-shaders.bin')
Reject 'missing shader book' @{}
if ((Get-FileHash -LiteralPath $profile).Hash -ne $before) { throw 'Validation changed profile data.' }
$checks++
Write-Output 'PASS profile data untouched'
Write-Output "$checks checks passed; no runtime compiled or launched. Authored fixtures: $fixture"
