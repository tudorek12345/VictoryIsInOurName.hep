[CmdletBinding()]
param([string]$LocalRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('victory-pin-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $fixture 'amd7900-series-s'
$run = 'original-20000101-000000-00000000'
$seed = Join-Path $fixture ('isolated-run\stage\' + $run)
New-Item -ItemType Directory -Path $repo, (Join-Path $seed 'bin'), (Join-Path $seed 'logs') | Out-Null
# This is plain authored text, never executed.
Set-Content -LiteralPath (Join-Path $repo 'source.txt') -Value 'authored fixture'
Set-Content -LiteralPath (Join-Path $seed 'bin\victory.exe') -Value 'authored fixture bytes'
& git -C $repo init -q
& git -C $repo add source.txt
& git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
if ($LASTEXITCODE -ne 0) { throw 'Fixture setup failed.' }
$metadata = @{
    backend='victory'; victorySource='amd7900-series-s'; checkoutDirty=$false; exitCode=0
    checkout=(& git -C $repo rev-parse HEAD)
    runtimeSha256=(Get-FileHash -LiteralPath (Join-Path $seed 'bin\victory.exe')).Hash
}
$resolver = Join-Path $LocalRoot 'Resolve-VictoryBuiltRuntime.ps1'
function Save-Metadata { $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') }
function Reject([string]$Label) {
    Save-Metadata
    $rejected = $false
    try { $null = & $resolver -Run $run -LocalRoot $fixture } catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid fixture: $Label" }
    Write-Output "PASS $Label"
}
Save-Metadata
$resolved = & $resolver -Run $run -LocalRoot $fixture
if ($resolved -ne (Join-Path $seed 'bin\victory.exe')) { throw 'Wrong executable selected.' }
Write-Output 'PASS clean source and matching executable'
$metadata.exitCode = 1
Reject 'failed seed run'
$metadata.Remove('exitCode')
Reject 'unfinished seed run'
$metadata.exitCode = 0
$originalCheckout = $metadata.checkout
$metadata.checkout = '0000000000000000000000000000000000000000'
Reject 'different source revision'
$metadata.checkout = $originalCheckout
$metadata.checkoutDirty = $true
Reject 'dirty seed source'
$metadata.checkoutDirty = $false
Set-Content -LiteralPath (Join-Path $repo 'source.txt') -Value 'changed source'
Reject 'dirty current source'
& git -C $repo checkout -- source.txt
Set-Content -LiteralPath (Join-Path $seed 'bin\victory.exe') -Value 'changed executable'
Reject 'tampered staged executable'
Write-Output "7 checks passed. Authored fixture retained at $fixture"
