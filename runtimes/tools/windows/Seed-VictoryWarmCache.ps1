[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$Run,
    [Parameter(Mandatory)][string]$DestinationOutput,
    [Parameter(Mandatory)][string]$RuntimeExe,
    [Parameter(Mandatory)][ValidateSet('hardware','warp')][string]$Renderer,
    [Parameter(Mandatory)][ValidateSet('series-x','series-s')][string]$Console,
    [string]$StageRoot = (Join-Path $PSScriptRoot 'isolated-run\stage')
)
$ErrorActionPreference = 'Stop'
$stage = [IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
function Stage-Directory([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Cache paths must be absolute.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $full.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Cache path escaped stage.' }
    $walk = $full
    while ($walk) {
        $item = Get-Item -LiteralPath $walk -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Cache paths must be plain directories.' }
        $walk = Split-Path -Parent $walk
    }
    $full
}
$seed = Stage-Directory (Join-Path $stage $Run)
$destination = Stage-Directory $DestinationOutput
$destinationRun = Split-Path -Parent $destination
if ((Split-Path -Leaf $destination) -ne 'output' -or
    (Split-Path -Parent $destinationRun) -ne $stage -or
    (Split-Path -Leaf $destinationRun) -notmatch '^original-\d{8}-\d{6}-[a-f0-9]{8}$' -or $destinationRun -eq $seed) {
    throw 'Cache destination must be another isolated run output.'
}
$null = Stage-Directory (Join-Path $seed 'logs')
$null = Stage-Directory (Join-Path $seed 'bin')
$metadata = Get-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') -Raw | ConvertFrom-Json
$seedEngine = Join-Path $seed 'bin\victory.exe'
if ($metadata.renderer -ne $Renderer -or $metadata.console -ne $Console -or
    (Get-FileHash -LiteralPath $seedEngine).Hash -ne (Get-FileHash -LiteralPath $RuntimeExe).Hash) {
    throw 'The seed must use the same Victory executable, renderer, and console profile.'
}
# Modern runs identify either a shared state or an isolated output here.
# Only old metadata without state falls back to the historical output path.
$sourceState = Stage-Directory $(if ($metadata.state) { [string]$metadata.state } else { Join-Path $seed 'output' })
$plan = @()
$cacheFiles = 0
$driverFiles = 0
foreach ($kind in @('cache\shaders','cache\pipelines','driver-cache')) {
    $source = Join-Path $sourceState $kind
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { continue }
    $null = Stage-Directory $source
    $entries = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
    if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1) {
        throw 'Cache contains a reparse point.'
    }
    $count = @($entries | Where-Object { -not $_.PSIsContainer -and $_.Length -gt 0 }).Count
    if ($kind -eq 'driver-cache') { $driverFiles += $count } else { $cacheFiles += $count }
    $target = Join-Path $destination $kind
    if (Test-Path -LiteralPath $target) { throw 'Cache destination already contains a cache tree.' }
    $plan += [pscustomobject]@{ source=$source; target=$target }
}
if ($cacheFiles -eq 0) { throw 'The source state contains no shader or pipeline cache files to seed.' }
# Caller holds the launcher lease. Validate the whole plan before copying.
New-Item -ItemType Directory -Path (Join-Path $destination 'cache') -Force | Out-Null
foreach ($entry in $plan) { Copy-Item -LiteralPath $entry.source -Destination $entry.target -Recurse }
[pscustomobject]@{ sourceState=$sourceState; cacheFiles=$cacheFiles; driverCacheFiles=$driverFiles }
