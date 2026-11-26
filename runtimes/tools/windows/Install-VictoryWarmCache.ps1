[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$Run,
    [string]$LocalRoot = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
$local = (Resolve-Path -LiteralPath $LocalRoot).Path
$stage = (Resolve-Path -LiteralPath (Join-Path $local 'isolated-run\stage')).Path
$seed = Join-Path $stage $Run
$metadata = Get-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') -Raw | ConvertFrom-Json
$report = & (Join-Path $local 'Summarize-VictoryRun.ps1') -Run $Run -StageRoot $stage -AsObject
if ($metadata.exitCode -ne 0 -or -not $metadata.prewarmLibrary -or
    $metadata.console -ne 'series-x' -or $metadata.renderer -ne 'hardware' -or
    $metadata.victorySource -ne 'amd7900-series-s' -or
    -not $report.precompile.completed -or $report.precompile.processed -ne $report.precompile.selected -or
    $report.precompile.refused -gt 0 -or $report.precompile.childFailures -gt 0) {
    throw 'Seed must be a completed, successful Series X hardware library preparation for this candidate.'
}
$destination = Join-Path $stage 'victory-amd-series-s-state'
# The launcher holds this lease throughout a title or warm-up session.
$lease = [IO.File]::Open((Join-Path $local 'launch.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    # A rebuild can change PE bytes without a source change. Verify the exact
    # prepared executable against the current clean source, not a later build.
    # Victory still validates its shader/driver fingerprint when opening caches.
    $null = & (Join-Path $local 'Resolve-VictoryBuiltRuntime.ps1') -Run $Run -LocalRoot $local
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $paths = @($stage, $seed, $destination, (Join-Path $seed 'output'))
    foreach ($path in $paths) {
        $item = Get-Item -LiteralPath $path
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse path rejected: $path" }
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($kind in @('cache', 'driver-cache')) {
        $source = Join-Path $seed ('output\' + $kind)
        $target = Join-Path $destination $kind
        $prepared = Join-Path $destination ($kind + '.prepared-' + $stamp)
        $backup = Join-Path $destination ($kind + '.before-' + $stamp)
        foreach ($path in @($source, $target, $prepared, $backup)) {
            $full = [IO.Path]::GetFullPath($path)
            if (-not $full.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Cache path escaped stage.' }
        }
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Missing prepared $kind" }
        $entries = @(Get-Item -LiteralPath $source) + @(Get-ChildItem -LiteralPath $source -Recurse -Force)
        if (Test-Path -LiteralPath $target) { $entries += Get-Item -LiteralPath $target }
        if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Cache contains a reparse point.' }
        if ((Test-Path -LiteralPath $prepared) -or (Test-Path -LiteralPath $backup)) { throw 'Backup/preparation path already exists.' }
        if ($PSCmdlet.ShouldProcess($target, "Install prepared $kind and preserve old cache")) {
            Copy-Item -LiteralPath $source -Destination $prepared -Recurse
            if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup }
            Move-Item -LiteralPath $prepared -Destination $target
        }
    }
    if (-not $WhatIfPreference) {
        @{ run=$Run; runtimeSha256=$metadata.runtimeSha256; installedUtc=[DateTimeOffset]::UtcNow.ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'prepared-cache.json') -Encoding UTF8
    }
} finally { $lease.Dispose() }
if (-not $WhatIfPreference) { Write-Output "Prepared cache installed for the normal launcher; saved profile data preserved: $destination" }
