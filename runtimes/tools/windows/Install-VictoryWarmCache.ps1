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
$destination = Join-Path $stage 'victory-amd-series-s-state'

function Assert-PlainDirectory([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a directory without a reparse point: $Path"
    }
}

function Assert-StagePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Cache path escaped stage.'
    }
}

# Validate ancestors before creating the lease or changing any cache path.
foreach ($path in @($local, (Join-Path $local 'isolated-run'), $stage)) {
    Assert-PlainDirectory $path
}
$lease = [IO.File]::Open((Join-Path $local 'launch.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    foreach ($path in @($seed, (Join-Path $seed 'logs'), (Join-Path $seed 'bin'), (Join-Path $seed 'output'))) {
        Assert-PlainDirectory $path
    }
    $metadata = Get-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') -Raw | ConvertFrom-Json
    $report = & (Join-Path $local 'Summarize-VictoryRun.ps1') -Run $Run -StageRoot $stage -AsObject
    if ($null -eq $metadata.exitCode -or $metadata.exitCode -ne 0 -or -not $metadata.prewarmLibrary -or
        $metadata.console -ne 'series-x' -or $metadata.renderer -ne 'hardware' -or
        $metadata.victorySource -ne 'amd7900-series-s' -or -not $report.precompile.completed -or
        $null -eq $report.precompile.selected -or $report.precompile.selected -le 0 -or
        $report.precompile.processed -ne $report.precompile.selected -or
        $null -eq $report.precompile.refused -or $report.precompile.refused -ne 0 -or
        $null -eq $report.precompile.childFailures -or $report.precompile.childFailures -ne 0) {
        throw 'Seed must be a completed, successful Series X hardware library preparation for this candidate.'
    }
    # A same-source rebuild can change PE bytes. Verify the prepared executable
    # and current clean source; Victory also checks its shader/driver fingerprint.
    $null = & (Join-Path $local 'Resolve-VictoryBuiltRuntime.ps1') -Run $Run -LocalRoot $local
    if (Test-Path -LiteralPath $destination) { Assert-PlainDirectory $destination }

    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $plan = @()
    foreach ($kind in @('cache', 'driver-cache', 'prepared-cache.json')) {
        $entry = [pscustomobject]@{
            kind = $kind
            source = if ($kind -eq 'prepared-cache.json') { $null } else { Join-Path $seed ('output\' + $kind) }
            target = Join-Path $destination $kind
            prepared = Join-Path $destination ($kind + '.prepared-' + $stamp)
            backup = Join-Path $destination ($kind + '.before-' + $stamp)
            movedOriginal = $false
            installed = $false
        }
        foreach ($path in @($entry.target, $entry.prepared, $entry.backup)) { Assert-StagePath $path }
        if ($entry.source) {
            Assert-StagePath $entry.source
            Assert-PlainDirectory $entry.source
            $reparse = Get-ChildItem -LiteralPath $entry.source -Recurse -Force |
                Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Select-Object -First 1
            if ($reparse) { throw 'Cache contains a reparse point.' }
        }
        if (Test-Path -LiteralPath $entry.target) {
            $item = Get-Item -LiteralPath $entry.target -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                ($item.PSIsContainer -ne [bool]$entry.source)) { throw "Invalid cache destination: $($entry.target)" }
        }
        if ((Test-Path -LiteralPath $entry.prepared) -or (Test-Path -LiteralPath $entry.backup)) {
            throw 'Backup/preparation path already exists.'
        }
        $plan += $entry
    }

    # One decision covers the pair and its provenance; declining makes no changes.
    if (-not $PSCmdlet.ShouldProcess($destination, 'Install both prepared caches and preserve the previous pair')) { return }
    New-Item -ItemType Directory -Path $destination -Force -Confirm:$false | Out-Null
    # Copy everything before moving any active path. A staging failure leaves
    # old caches/provenance intact; incomplete prepared paths remain for inspection.
    foreach ($entry in $plan) {
        if ($entry.source) {
            Copy-Item -LiteralPath $entry.source -Destination $entry.prepared -Recurse -Confirm:$false
        } else {
            @{ run=$Run; runtimeSha256=$metadata.runtimeSha256; installedUtc=[DateTimeOffset]::UtcNow.ToString('o') } |
                ConvertTo-Json | Set-Content -LiteralPath $entry.prepared -Encoding UTF8 -Confirm:$false
        }
    }
    try {
        foreach ($entry in $plan) {
            if (Test-Path -LiteralPath $entry.target) {
                Move-Item -LiteralPath $entry.target -Destination $entry.backup -Confirm:$false
                $entry.movedOriginal = $true
            }
            Move-Item -LiteralPath $entry.prepared -Destination $entry.target -Confirm:$false
            $entry.installed = $true
        }
    } catch {
        $activationError = $_
        $rollbackErrors = @()
        for ($index = $plan.Count - 1; $index -ge 0; $index--) {
            $entry = $plan[$index]
            try {
                if ($entry.installed) {
                    Move-Item -LiteralPath $entry.target -Destination $entry.prepared -Confirm:$false
                }
                if ($entry.movedOriginal) {
                    Move-Item -LiteralPath $entry.backup -Destination $entry.target -Confirm:$false
                }
            } catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count) {
            throw "Cache activation failed: $($activationError.Exception.Message). Rollback also failed; preserved paths need inspection: $($rollbackErrors -join '; ')"
        }
        throw $activationError
    }
    Write-Output "Prepared cache installed for the normal launcher; saved profile data preserved: $destination"
} finally { $lease.Dispose() }
