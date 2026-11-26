[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StateRoot,
    [string]$Backend = 'victory',
    [string]$VictorySource = 'amd7900-series-s',
    [string]$Renderer = 'hardware',
    [switch]$PrewarmPipelines,
    [switch]$PrewarmLibrary,
    [switch]$PrepareOnly,
    [switch]$FreshState,
    [switch]$Test720p,
    [string]$DisplayMode,
    [string]$WarmCacheFrom,
    [string]$PipelineBookFrom,
    [string]$PipelineUseFrom
)
$ErrorActionPreference = 'Stop'
if ($Backend -ne 'victory' -or $VictorySource -ne 'amd7900-series-s' -or $Renderer -ne 'hardware') {
    throw 'PrewarmCurrentCache requires the active AMD Victory candidate on hardware.'
}
if (-not ($PrewarmPipelines -and $PrewarmLibrary) -or $PrepareOnly) {
    throw 'PrewarmCurrentCache requires PrewarmPipelines and PrewarmLibrary, without PrepareOnly.'
}
if ($FreshState -or $Test720p -or $DisplayMode -or $WarmCacheFrom -or $PipelineBookFrom -or $PipelineUseFrom) {
    throw 'PrewarmCurrentCache uses the normal shared state and conflicts with fresh, resolution, or imported cache/book options.'
}
if (-not [IO.Path]::IsPathRooted($StateRoot)) { throw 'The current prewarm state must be an absolute path.' }
$state = [IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
if ((Split-Path -Leaf $state) -ne 'victory-amd-series-s-state' -or
    (Split-Path -Leaf (Split-Path -Parent $state)) -ne 'stage') {
    throw 'PrewarmCurrentCache must use the normal AMD shared state beneath stage.'
}
$pipelines = Join-Path $state 'cache\pipelines'
$walk = $pipelines
while ($walk) {
    $item = Get-Item -LiteralPath $walk -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Current prewarm cache paths must be plain directories.'
    }
    $walk = Split-Path -Parent $walk
}
$lengths = @{}
foreach ($name in @('known-pipelines.bin', 'known-shaders.bin', 'early-pipelines.txt')) {
    $file = Get-Item -LiteralPath (Join-Path $pipelines $name) -Force
    if ($file.PSIsContainer -or $file.Length -le 0 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Current prewarm cache requires a nonempty plain $name file."
    }
    $lengths[$name] = [long]$file.Length
}
# No copies or markers are changed here. The warmer reopens selected entries;
# translator/DXIL content keys and the driver's library validation govern reuse.
[pscustomobject]@{
    mode = 'shared-content-keyed'
    state = $state
    pipelineDirectory = $pipelines
    knownPipelineBytes = $lengths['known-pipelines.bin']
    knownShaderBytes = $lengths['known-shaders.bin']
    earlyPipelineBytes = $lengths['early-pipelines.txt']
    libraryWriters = 1
}
