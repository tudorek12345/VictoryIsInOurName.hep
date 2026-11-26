[CmdletBinding()]
param([string]$LocalRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$seedHelper = Join-Path $LocalRoot 'Seed-VictoryWarmCache.ps1'
$displayHelper = Join-Path $LocalRoot 'Set-VictoryTestDisplayMode.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('victory-resolution-' + [Guid]::NewGuid().ToString('N'))
$seedRun = 'original-20000101-000000-00000001'
$newRun = 'original-20000101-000000-00000002'
function New-Fixture([string]$Name, [switch]$Shared, [switch]$Legacy, [switch]$Empty) {
    $root = Join-Path $testRoot $Name
    $stage = Join-Path $root 'stage'
    $seed = Join-Path $stage $seedRun
    $output = Join-Path $stage ($newRun + '\output')
    $state = if ($Shared) { Join-Path $stage 'victory-amd-series-s-state' } else { Join-Path $seed 'output' }
    New-Item -ItemType Directory -Path $output, (Join-Path $seed 'bin'), (Join-Path $seed 'logs'),
        (Join-Path $state 'cache\shaders'), (Join-Path $state 'cache\pipelines'), (Join-Path $state 'driver-cache') | Out-Null
    # Authored bytes only; these files are never executed or parsed as game data.
    $binary = Join-Path $root 'runtime.txt'
    Set-Content -LiteralPath $binary -Value 'authored runtime identity'
    Copy-Item -LiteralPath $binary -Destination (Join-Path $seed 'bin\victory.exe')
    if (-not $Empty) {
        foreach($kind in @('cache\shaders','cache\pipelines','driver-cache')) {
            Set-Content -LiteralPath (Join-Path $state ($kind + '\fixture.txt')) -Value $kind
        }
    }
    $metadata = @{ renderer='hardware'; console='series-x' }
    if (-not $Legacy) { $metadata.state = $state }
    $fixture = [pscustomobject]@{ stage=$stage; seed=$seed; output=$output; state=$state; binary=$binary; metadata=$metadata }
    Save-Metadata $fixture
    $fixture
}
function Save-Metadata($Fixture) {
    $Fixture.metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Fixture.seed 'logs\diagnostics.json')
}
function Seed($Fixture) {
    & $seedHelper -Run $seedRun -DestinationOutput $Fixture.output -RuntimeExe $Fixture.binary `
        -Renderer hardware -Console series-x -StageRoot $Fixture.stage
}
function Reject-Seed($Fixture, [string]$Expected) {
    $rejected = $false
    try { $null = Seed $Fixture } catch { if ($_.Exception.Message -notmatch $Expected) { throw }; $rejected = $true }
    if (-not $rejected) { throw "Invalid cache seed accepted: $Expected" }
    if (Test-Path -LiteralPath (Join-Path $Fixture.output 'cache')) { throw 'Rejected seed copied cache data.' }
    Write-Output "PASS rejects $Expected"
}
foreach($kind in @('shared','fresh','legacy')) {
    $f = New-Fixture $kind -Shared:($kind -eq 'shared') -Legacy:($kind -eq 'legacy')
    $seeded = Seed $f
    if($seeded.sourceState -ne $f.state -or $seeded.cacheFiles -ne 2 -or $seeded.driverCacheFiles -ne 1) { throw "Wrong $kind provenance/counts." }
    foreach($path in @('cache\shaders\fixture.txt','cache\pipelines\fixture.txt','driver-cache\fixture.txt')) {
        if((Get-FileHash -LiteralPath (Join-Path $f.output $path)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $f.state $path)).Hash) { throw "Wrong $kind copied bytes." }
    }
    Write-Output "PASS $kind cache source and private driver cache"
}
$f = New-Fixture empty -Empty
Reject-Seed $f 'no shader or pipeline cache files'
$f = New-Fixture outside
$f.metadata.state = $testRoot
Save-Metadata $f
Reject-Seed $f 'escaped stage'
$f = New-Fixture relative
$f.metadata.state = 'relative\state'
Save-Metadata $f
Reject-Seed $f 'absolute'
$f = New-Fixture wrong-binary
Set-Content -LiteralPath $f.binary -Value 'different authored identity'
Reject-Seed $f 'same Victory executable'
foreach($field in @('renderer','console')) {
    $f = New-Fixture ('wrong-' + $field)
    $f.metadata[$field] = 'different'
    Save-Metadata $f
    Reject-Seed $f 'same Victory executable'
}

$f = New-Fixture xml -Shared
$relative = 'data\12345678\storage\settings\settings.xml'
$file = Join-Path $f.output $relative
$original = Join-Path $f.state $relative
New-Item -ItemType Directory -Path (Split-Path -Parent $file),(Split-Path -Parent $original) | Out-Null
$xmlText = '<?xml version="1.0"?><rage__fwSystemSettingsCollection keep="yes"><graphics><desiredFPS value="30" /></graphics><video><resolutionFullscreen><width value="3840" extra="keep"/><height value="2160"/></resolutionFullscreen><vSync value="2"/></video><unrelated>preserve me</unrelated></rage__fwSystemSettingsCollection>'
Set-Content -LiteralPath $original -Value $xmlText
Copy-Item -LiteralPath $original -Destination $file
$originalHash = (Get-FileHash -LiteralPath $original).Hash
$changed = & $displayHelper -OutputDirectory $f.output -DisplayMode '1920x1080' -StageRoot $f.stage
[xml]$xml = Get-Content -LiteralPath $file -Raw
if($changed.matchedFiles -ne 1 -or $changed.updatedFiles -ne 1 -or
    $xml.rage__fwSystemSettingsCollection.video.resolutionFullscreen.width.value -ne '1920' -or
    $xml.rage__fwSystemSettingsCollection.video.resolutionFullscreen.height.value -ne '1080' -or
    $xml.rage__fwSystemSettingsCollection.video.resolutionFullscreen.width.extra -ne 'keep' -or
    $xml.rage__fwSystemSettingsCollection.video.vSync.value -ne '2' -or
    $xml.rage__fwSystemSettingsCollection.graphics.desiredFPS.value -ne '30' -or
    $xml.rage__fwSystemSettingsCollection.unrelated -ne 'preserve me' -or
    (Get-FileHash -LiteralPath $original).Hash -ne $originalHash) { throw 'Copied XML mode or preservation failed.' }
Write-Output 'PASS only copied resolution changes; source and unrelated XML preserved'
$changed = & $displayHelper -OutputDirectory $f.output -DisplayMode '1920x1080' -StageRoot $f.stage
if($changed.matchedFiles -ne 1 -or $changed.updatedFiles -ne 0) { throw 'Repeated XML update should be unchanged.' }
Write-Output 'PASS already matching settings unchanged'
$empty = New-Fixture no-settings
$changed = & $displayHelper -OutputDirectory $empty.output -DisplayMode '1920x1080' -StageRoot $empty.stage
if($changed.matchedFiles -ne 0 -or $changed.updatedFiles -ne 0) { throw 'Missing settings must be a no-op.' }
Write-Output 'PASS absent settings no-op'
$rejected = $false
try { $null = & $displayHelper -OutputDirectory $f.state -DisplayMode '1920x1080' -StageRoot $f.stage } catch { $rejected = $true }
if(-not $rejected -or (Get-FileHash -LiteralPath $original).Hash -ne $originalHash) { throw 'Shared profile settings were not protected.' }
Write-Output 'PASS shared profile mutation rejected'
Write-Output "13 checks passed; authored fixtures retained at $testRoot"
