[CmdletBinding()]
param([string]$LocalRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('victory-cache-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$installer = Join-Path $LocalRoot 'Install-VictoryWarmCache.ps1'
$run = 'original-20000101-000000-00000000'
$faults = [pscustomobject]@{failCopy=$false; failMoveKind=''}

# Inject failures in this test's command scope, never in production options.
# The real filesystem operations still run within each authored temp fixture.
Set-Item -Path Function:Copy-Item -Value ({
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LiteralPath, [string]$Destination, [switch]$Recurse)
    if ($faults.failCopy -and (Split-Path -Leaf $LiteralPath) -eq 'driver-cache') {
        throw 'Injected second cache staging failure'
    }
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
}.GetNewClosure())

Set-Item -Path Function:Move-Item -Value ({
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$LiteralPath, [string]$Destination)
    if ($faults.failMoveKind -and (Split-Path -Leaf $LiteralPath).StartsWith($faults.failMoveKind + '.prepared-')) {
        throw 'Injected cache activation failure'
    }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
}.GetNewClosure())

function New-Fixture([string]$Name, [switch]$Fresh, [switch]$MissingDriver) {
    $root = Join-Path $testRoot $Name
    $repo = Join-Path $root 'amd7900-series-s'
    $stage = Join-Path $root 'isolated-run\stage'
    $seed = Join-Path $stage $run
    $destination = Join-Path $stage 'victory-amd-series-s-state'
    New-Item -ItemType Directory -Path $repo, (Join-Path $seed 'bin'), (Join-Path $seed 'logs'), (Join-Path $seed 'output\cache') | Out-Null
    Set-Content -LiteralPath (Join-Path $repo 'source.rs') -Value '// authored fixture source'
    Set-Content -LiteralPath (Join-Path $seed 'bin\victory.exe') -Value 'authored fixture; never executed'
    Set-Content -LiteralPath (Join-Path $seed 'output\cache\new.txt') -Value 'new shader cache'
    if (-not $MissingDriver) {
        New-Item -ItemType Directory -Path (Join-Path $seed 'output\driver-cache') | Out-Null
        Set-Content -LiteralPath (Join-Path $seed 'output\driver-cache\new.txt') -Value 'new driver cache'
    }
    & git -C $repo init -q
    & git -C $repo add source.rs
    & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture setup failed.' }
    $metadata = @{
        backend='victory'; victorySource='amd7900-series-s'; checkoutDirty=$false; exitCode=0
        console='series-x'; renderer='hardware'; prewarmLibrary=$true
        checkout=(& git -C $repo rev-parse HEAD)
        runtimeSha256=(Get-FileHash -LiteralPath (Join-Path $seed 'bin\victory.exe')).Hash
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json')
    Copy-Item -LiteralPath (Join-Path $LocalRoot 'Resolve-VictoryBuiltRuntime.ps1') -Destination (Join-Path $root 'Resolve-VictoryBuiltRuntime.ps1')
    # Parser coverage belongs to Test-Summarize-VictoryRun; this suite isolates
    # installer transactions using a successful synthetic summary.
    Set-Content -LiteralPath (Join-Path $root 'Summarize-VictoryRun.ps1') -Value @'
param($Run, $StageRoot, [switch]$AsObject)
[pscustomobject]@{ precompile=[pscustomobject]@{completed=$true; selected=2; processed=2; refused=0; childFailures=0} }
'@
    if (-not $Fresh) {
        New-Item -ItemType Directory -Path (Join-Path $destination 'cache'), (Join-Path $destination 'driver-cache'), (Join-Path $destination 'data') | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'cache\old.txt') -Value 'old shader cache'
        Set-Content -LiteralPath (Join-Path $destination 'driver-cache\old.txt') -Value 'old driver cache'
        Set-Content -LiteralPath (Join-Path $destination 'data\profile.txt') -Value 'saved profile'
        Set-Content -LiteralPath (Join-Path $destination 'prepared-cache.json') -Value '{"run":"previous"}'
    }
    [pscustomobject]@{root=$root; repo=$repo; seed=$seed; destination=$destination; metadata=$metadata}
}

function Assert-Text([string]$Path, [string]$Expected) {
    if ((Get-Content -LiteralPath $Path -Raw).Trim() -ne $Expected) { throw "Unexpected contents at $Path" }
}

function Assert-Original($Fixture) {
    Assert-Text (Join-Path $Fixture.destination 'cache\old.txt') 'old shader cache'
    Assert-Text (Join-Path $Fixture.destination 'driver-cache\old.txt') 'old driver cache'
    Assert-Text (Join-Path $Fixture.destination 'prepared-cache.json') '{"run":"previous"}'
    Assert-Text (Join-Path $Fixture.destination 'data\profile.txt') 'saved profile'
    foreach ($kind in @('cache', 'driver-cache')) {
        if (Test-Path -LiteralPath (Join-Path $Fixture.destination ($kind + '\new.txt'))) { throw 'New cache leaked into the active pair.' }
    }
}

function Expect-Rejection($Fixture, [string]$Message) {
    $rejected = $false
    $result = @()
    try { $result = & $installer -Run $run -LocalRoot $Fixture.root -Confirm:$false }
    catch {
        if ($_.Exception.Message -notmatch $Message) { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw 'Invalid installation unexpectedly succeeded.' }
    if ($result -match 'Prepared cache installed') { throw 'Failed installation reported success.' }
    Assert-Original $Fixture
}

$fixture = New-Fixture success
$result = & $installer -Run $run -LocalRoot $fixture.root -Confirm:$false
if ($result -notmatch 'Prepared cache installed') { throw 'Successful installation did not report success.' }
Assert-Text (Join-Path $fixture.destination 'cache\new.txt') 'new shader cache'
Assert-Text (Join-Path $fixture.destination 'driver-cache\new.txt') 'new driver cache'
Assert-Text (Join-Path $fixture.destination 'data\profile.txt') 'saved profile'
$installed = Get-Content -LiteralPath (Join-Path $fixture.destination 'prepared-cache.json') -Raw | ConvertFrom-Json
if ($installed.run -ne $run -or $installed.runtimeSha256 -ne $fixture.metadata.runtimeSha256) { throw 'Wrong installed provenance.' }
foreach ($kind in @('cache', 'driver-cache')) {
    $backups = @(Get-ChildItem -LiteralPath $fixture.destination -Directory -Filter ($kind + '.before-*'))
    if ($backups.Count -ne 1) { throw 'Previous cache was not preserved once.' }
    Assert-Text (Join-Path $backups[0].FullName 'old.txt') $(if ($kind -eq 'cache') {'old shader cache'} else {'old driver cache'})
}
Write-Output 'PASS installs both caches, preserves profile and backups, records provenance'

$fixture = New-Fixture missing-driver -MissingDriver
Expect-Rejection $fixture 'driver-cache'
if (@(Get-ChildItem -LiteralPath $fixture.destination -Filter '*.prepared-*').Count) { throw 'Staging started before all sources were validated.' }
Write-Output 'PASS missing second cache leaves the active pair untouched'

$fixture = New-Fixture staging-failure
$faults.failCopy = $true
try { Expect-Rejection $fixture 'Injected second cache staging failure' } finally { $faults.failCopy = $false }
if (@(Get-ChildItem -LiteralPath $fixture.destination -Filter '*.before-*').Count) { throw 'Active cache moved before staging completed.' }
Write-Output 'PASS second-copy failure preserves old caches and provenance'

$fixture = New-Fixture activation-failure
$faults.failMoveKind = 'driver-cache'
try { Expect-Rejection $fixture 'Injected cache activation failure' } finally { $faults.failMoveKind = '' }
Write-Output 'PASS second-cache activation failure rolls back the complete pair'

$fixture = New-Fixture provenance-failure
$faults.failMoveKind = 'prepared-cache.json'
try { Expect-Rejection $fixture 'Injected cache activation failure' } finally { $faults.failMoveKind = '' }
Write-Output 'PASS provenance activation failure restores old caches and provenance'

$fixture = New-Fixture whatif
$result = & $installer -Run $run -LocalRoot $fixture.root -WhatIf
Assert-Original $fixture
if ($result -match 'Prepared cache installed') { throw 'WhatIf reported installation success.' }
if (@(Get-ChildItem -LiteralPath $fixture.destination -Filter '*.prepared-*').Count -or
    @(Get-ChildItem -LiteralPath $fixture.destination -Filter '*.before-*').Count) { throw 'WhatIf changed cache storage.' }
Write-Output 'PASS WhatIf leaves existing caches and provenance unchanged'

$fixture = New-Fixture fresh-whatif -Fresh
$result = & $installer -Run $run -LocalRoot $fixture.root -WhatIf
if (Test-Path -LiteralPath $fixture.destination) { throw 'WhatIf created a missing destination.' }
if ($result -match 'Prepared cache installed') { throw 'Fresh WhatIf reported installation success.' }
Write-Output 'PASS WhatIf handles an absent destination without creating it'

$fixture = New-Fixture locked
$lease = [IO.File]::Open((Join-Path $fixture.root 'launch.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try { Expect-Rejection $fixture 'being used by another process' } finally { $lease.Dispose() }
Write-Output 'PASS launcher lease prevents installation'

$fixture = New-Fixture junction -MissingDriver
$authoredTarget = Join-Path $fixture.root 'authored-junction-target'
New-Item -ItemType Directory -Path $authoredTarget | Out-Null
Set-Content -LiteralPath (Join-Path $authoredTarget 'new.txt') -Value 'authored redirected cache'
New-Item -ItemType Junction -Path (Join-Path $fixture.seed 'output\driver-cache') -Target $authoredTarget | Out-Null
Expect-Rejection $fixture 'reparse'
if (@(Get-ChildItem -LiteralPath $fixture.destination -Filter '*.prepared-*').Count) { throw 'Staging started before rejecting the junction.' }
Write-Output 'PASS second-cache junction is rejected before staging or activation'

Write-Output "9 cache checks passed. Authored fixtures retained at $testRoot"
