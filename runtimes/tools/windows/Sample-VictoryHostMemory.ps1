[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$Run,
    [string]$StageRoot = (Join-Path $PSScriptRoot 'isolated-run\stage'),
    [ValidateRange(1, 3600)] [int]$MaxSeconds = 300,
    [ValidateRange(1, 60)] [int]$IntervalSeconds = 5
)

# Read-only host telemetry. Never changes a guard, process, driver or resource.
# The launcher's finalized metadata ends collection, including a manual close.
$ErrorActionPreference = 'Stop'
$logs = Join-Path (Join-Path $StageRoot $Run) 'logs'
if (-not (Test-Path -LiteralPath $logs -PathType Container)) { throw 'Start the run before its host sampler.' }
$finished = Join-Path $logs 'diagnostics.json'
$destination = Join-Path $logs ('host-memory-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.jsonl')
$stream = [IO.File]::Open($destination, 'CreateNew', 'Write', 'Read')
$writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
$timer = [Diagnostics.Stopwatch]::StartNew()
$count = 0
try {
    do {
        $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $row = [ordered]@{
            timestampUtc = [DateTimeOffset]::UtcNow.ToString('o')
            samplerElapsedMs = $timer.ElapsedMilliseconds
            availablePhysicalBytes = [uint64]$memory.AvailableMBytes * 1MB
            committedBytes = [uint64]$memory.CommittedBytes
            commitLimitBytes = [uint64]$memory.CommitLimit
            availableCommitBytes = [uint64]$memory.CommitLimit - [uint64]$memory.CommittedBytes
            pageReadsPerSecond = [uint64]$memory.PageReadsPersec
            pageWritesPerSecond = [uint64]$memory.PageWritesPersec
            launcherFinalized = [bool](Test-Path -LiteralPath $finished -PathType Leaf)
        }
        $writer.WriteLine(($row | ConvertTo-Json -Compress))
        $writer.Flush()
        $count++
        if ($row.launcherFinalized) { break }
        $remaining = $MaxSeconds * 1000 - $timer.ElapsedMilliseconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Min($remaining, $IntervalSeconds * 1000)) }
    } while ($timer.Elapsed.TotalSeconds -lt $MaxSeconds)
} finally {
    $writer.Dispose()
    $stream.Dispose()
}
[pscustomobject]@{ run=$Run; samples=$count; elapsedSeconds=$timer.Elapsed.TotalSeconds; launcherFinalized=$row.launcherFinalized; file=$destination }
