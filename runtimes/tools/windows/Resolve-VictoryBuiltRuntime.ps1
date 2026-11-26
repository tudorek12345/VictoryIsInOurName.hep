[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$Run,
    [string]$LocalRoot = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$local = (Resolve-Path -LiteralPath $LocalRoot).Path
$repo = Join-Path $local 'amd7900-series-s'
$seed = Join-Path $local ('isolated-run\stage\' + $Run)
$metadata = Get-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') -Raw | ConvertFrom-Json
$engine = Join-Path $seed 'bin\victory.exe'
$checkout = & git -C $repo rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the current runtime source.' }
$dirty = [bool](& git -C $repo status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the current runtime source.' }
if ($dirty -or $metadata.checkoutDirty -ne $false -or $metadata.checkout -ne $checkout -or
    $metadata.backend -ne 'victory' -or $metadata.victorySource -ne 'amd7900-series-s' -or
    $null -eq $metadata.exitCode -or $metadata.exitCode -ne 0) {
    throw 'A pinned executable requires a successful run of the exact current clean runtime source.'
}
if (-not $metadata.runtimeSha256 -or (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash -ne $metadata.runtimeSha256) {
    throw 'The staged executable no longer matches its recorded SHA-256.'
}
Write-Output $engine
