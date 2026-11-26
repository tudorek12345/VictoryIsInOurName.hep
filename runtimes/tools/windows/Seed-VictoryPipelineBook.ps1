[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$BookRun,
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$UseRun,
    [Parameter(Mandatory)]
    [string]$DestinationCache,
    [string]$StageRoot = (Join-Path $PSScriptRoot 'isolated-run\stage'),
    [string]$PackageExecutable = (Join-Path (Split-Path -Parent $PSScriptRoot) 'buildgta\game_scarlett_master.exe')
)

$ErrorActionPreference = 'Stop'
# Only the raw, version-checked pipeline book crosses a runtime revision.
# Compiled shaders, pipeline libraries and warm-success markers never do.
function Get-FullLocalPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]') {
        throw 'Use an absolute local drive path.'
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $walk = $full
    while ($walk) {
        if (Test-Path -LiteralPath $walk) {
            $item = Get-Item -LiteralPath $walk -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Pipeline book paths must not cross a junction or symbolic link.'
            }
        }
        $walk = Split-Path -Parent $walk
    }
    return $full
}

$stage = Get-FullLocalPath $StageRoot
$package = Get-FullLocalPath $PackageExecutable
$destination = Get-FullLocalPath $DestinationCache
$packageRoot = Split-Path -Parent $package
if ($destination -eq [IO.Path]::GetPathRoot($destination).TrimEnd('\') -or
    $destination -eq $packageRoot -or $destination.StartsWith($packageRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The destination must be separate from the original package.'
}
if (Test-Path -LiteralPath $destination) {
    if (-not (Test-Path -LiteralPath $destination -PathType Container) -or
        @(Get-ChildItem -LiteralPath $destination -Force).Count) {
        throw 'DestinationCache must be a new or empty directory.'
    }
}
$packageHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
$sources = @($BookRun)
if ($UseRun -and $UseRun -ne $BookRun) { $sources += $UseRun }
$sourceInfo = @()
$early = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($run in $sources) {
    $root = Get-FullLocalPath (Join-Path $stage $run)
    if ($destination -eq $root -or $destination.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'The destination must not replace or extend a source run.'
    }
    $summaryPath = Get-FullLocalPath (Join-Path $root 'logs\diagnostics.json')
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    if ($summary.backend -ne 'victory' -or $summary.victorySource -notin @('amd7900', 'amd7900-series-s') -or
        $summary.packageExecutableSha256 -ne $packageHash) {
        throw 'A source run must use this original package and the compatible AMD pipeline-book format.'
    }
    $path = Get-FullLocalPath (Join-Path $root 'output\cache\pipelines\early-pipelines.txt')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 16MB) {
        throw 'The source run has no bounded isolated pipeline-use list.'
    }
    $count = 0
    $reader = [IO.StreamReader]::new($path)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line -eq '') { continue }
            if ($line -cnotmatch '^[0-9a-f]{32}$') { throw 'A pipeline-use list has an invalid key.' }
            [void]$early.Add($line)
            $count++
        }
    } finally { $reader.Dispose() }
    $sourceInfo += [pscustomobject]@{
        run = $run
        console = $summary.console
        runtimeSha256 = $summary.runtimeSha256
        usedRecords = $count
        usedListSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}

# Streaming validation keeps the book's 200+ MB payload out of managed memory.
# This is the explicit known.rs layout of the pinned AMD fork, not a decoder
# for arbitrary future book formats. Trailing/torn records are rejected.
if (-not ('VictoryBookSeed' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Security.Cryptography;
public sealed class VictoryBookSeed : IDisposable {
    readonly FileStream shaders, pipelines;
    public readonly HashSet<string> Keys = new HashSet<string>(StringComparer.Ordinal);
    public int ShaderCount { get; private set; }
    public int PipelineCount { get; private set; }
    static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
    static void Need(bool ok) { if (!ok) throw new InvalidDataException("Invalid, truncated or incompatible pipeline book."); }
    static byte[] Bytes(BinaryReader r, int n) { var b = r.ReadBytes(n); Need(b.Length == n); return b; }
    static void Skip(BinaryReader r, long n, long end) { Need(n >= 0 && r.BaseStream.Position <= end - n); r.BaseStream.Position += n; }
    public VictoryBookSeed(string shaderPath, string pipelinePath) {
        try {
            shaders = new FileStream(shaderPath, FileMode.Open, FileAccess.Read, FileShare.Read);
            pipelines = new FileStream(pipelinePath, FileMode.Open, FileAccess.Read, FileShare.Read);
            Need(shaders.Length > 0 && shaders.Length <= 2147483648L);
            Need(pipelines.Length > 0 && pipelines.Length <= 1073741824L);
            var hashes = new HashSet<string>(StringComparer.Ordinal);
            using (var r = new BinaryReader(shaders, System.Text.Encoding.UTF8, true)) {
                while (shaders.Position < shaders.Length) {
                    Need(shaders.Length - shaders.Position >= 37);
                    Need(r.ReadByte() < 8);
                    Need(hashes.Add(Hex(Bytes(r, 32))));
                    var size = r.ReadUInt32();
                    Need(size > 0 && size <= 67108864);
                    Skip(r, size, shaders.Length);
                    Need(++ShaderCount <= 1000000);
                }
            }
            using (var r = new BinaryReader(pipelines, System.Text.Encoding.UTF8, true)) {
                while (pipelines.Position < pipelines.Length) {
                    Need(pipelines.Length - pipelines.Position >= 4);
                    var size = r.ReadUInt32();
                    Need(size >= 51 && size <= 1048576 && size <= pipelines.Length - pipelines.Position);
                    long end = pipelines.Position + size;
                    Need(Keys.Add(Hex(Bytes(r, 16))));
                    int count = r.ReadByte();
                    Need(count > 0 && count <= 8 && 18 + count * 33 <= size);
                    for (int n = 0; n < count; n++) {
                        Need(r.ReadByte() < 8);
                        Need(hashes.Contains(Hex(Bytes(r, 32))));
                    }
                    int graphics = r.ReadByte();
                    Need(graphics <= 1);
                    if (graphics != 0) {
                        Need(end - pipelines.Position >= 490);
                        Need(r.ReadByte() <= 1); // depth-bounds flag
                        Skip(r, 122 * 4, end); // two floats, then 120 u32 state fields
                        int inputs = r.ReadByte();
                        for (int n = 0; n < inputs; n++) {
                            int name = r.ReadByte();
                            Need(name > 0);
                            Skip(r, name + 24, end);
                        }
                    }
                    Need(pipelines.Position == end);
                    Need(++PipelineCount <= 1000000);
                }
            }
        } catch { Dispose(); throw; }
    }
    static string Hash(FileStream file) {
        file.Position = 0;
        using (var hash = SHA256.Create()) { return Hex(hash.ComputeHash(file)); }
    }
    public string ShaderSha256 { get { return Hash(shaders); } }
    public string PipelineSha256 { get { return Hash(pipelines); } }
    static void Copy(FileStream source, string destination) {
        source.Position = 0;
        using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { source.CopyTo(output); }
    }
    public void CopyTo(string directory) {
        Copy(shaders, Path.Combine(directory, "known-shaders.bin"));
        Copy(pipelines, Path.Combine(directory, "known-pipelines.bin"));
    }
    public void Dispose() { if (shaders != null) shaders.Dispose(); if (pipelines != null) pipelines.Dispose(); }
}
'@
}
$bookFolder = Get-FullLocalPath (Join-Path $stage ($BookRun + '\output\cache\pipelines'))
$shaders = Get-FullLocalPath (Join-Path $bookFolder 'known-shaders.bin')
$pipelines = Get-FullLocalPath (Join-Path $bookFolder 'known-pipelines.bin')
$book = [VictoryBookSeed]::new($shaders, $pipelines)
try {
    $selected = @($early | Where-Object { $book.Keys.Contains($_) } | Sort-Object)
    if ($selected.Count -eq 0) { throw 'No requested pipeline has a complete record in this book.' }
    $manifest = [ordered]@{
        schema = 1
        format = 'amd7900-known-pipelines-depth-bounds-v1'
        bookRun = $BookRun
        useRun = $UseRun
        packageExecutableSha256 = $packageHash
        knownShaders = $book.ShaderCount
        knownPipelines = $book.PipelineCount
        requestedPipelines = $early.Count
        selectedPipelines = $selected.Count
        unavailablePipelines = $early.Count - $selected.Count
        knownShadersSha256 = $book.ShaderSha256
        knownPipelinesSha256 = $book.PipelineSha256
        sources = $sourceInfo
        copied = @('known-shaders.bin', 'known-pipelines.bin', 'early-pipelines.txt')
        derivedCacheCopied = $false
    }
    $out = Join-Path $destination 'pipelines'
    [void][IO.Directory]::CreateDirectory($out)
    $book.CopyTo($out)
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $out 'early-pipelines.txt'), ($selected -join "`n") + "`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $destination 'pipeline-book-seed.json'), ($manifest | ConvertTo-Json -Depth 6) + "`n", $utf8)
    [pscustomobject]$manifest
} finally {
    $book.Dispose()
}
