[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$DisplayMode,
    [string]$StageRoot = (Join-Path $PSScriptRoot 'isolated-run\stage')
)
$ErrorActionPreference = 'Stop'
$mode = & (Join-Path $PSScriptRoot 'Resolve-VictoryDisplayOptions.ps1') -DisplayMode $DisplayMode -GuestDisplaySupported
$width, $height = $mode.GuestDisplayMode.Split('x')
$stage = [IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
$output = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$run = Split-Path -Parent $output
if ((Split-Path -Leaf $output) -ne 'output' -or (Split-Path -Parent $run) -ne $stage -or
    (Split-Path -Leaf $run) -notmatch '^original-\d{8}-\d{6}-[a-f0-9]{8}$') {
    throw 'Display settings may only change an isolated run output, never the shared profile.'
}
function Assert-PlainPath([string]$Path) {
    $walk = $Path
    while ($walk) {
        if ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Display settings path crosses a reparse point.' }
        $walk = Split-Path -Parent $walk
    }
}
Assert-PlainPath $output
$matched = 0
$updated = 0
$data = Join-Path $output 'data'
if (Test-Path -LiteralPath $data -PathType Container) {
    Assert-PlainPath $data
    foreach ($title in Get-ChildItem -LiteralPath $data -Directory) {
        if ($title.Name -notmatch '^[0-9a-fA-F]{8}$') { continue }
        $file = Join-Path $title.FullName 'storage\settings\settings.xml'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        Assert-PlainPath $file
        $readerSettings = [Xml.XmlReaderSettings]::new()
        $readerSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $readerSettings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($file, $readerSettings)
        $xml = [Xml.XmlDocument]::new()
        $xml.PreserveWhitespace = $true
        $xml.XmlResolver = $null
        try { $xml.Load($reader) } finally { $reader.Dispose() }
        $resolution = $xml.SelectSingleNode('/rage__fwSystemSettingsCollection/video/resolutionFullscreen')
        if ($null -eq $resolution) { continue }
        $w = $resolution.SelectSingleNode('width[@value]')
        $h = $resolution.SelectSingleNode('height[@value]')
        if ($null -eq $w -or $null -eq $h) { continue }
        $matched++
        if ($w.GetAttribute('value') -eq $width -and $h.GetAttribute('value') -eq $height) { continue }
        $w.SetAttribute('value', $width)
        $h.SetAttribute('value', $height)
        $writerSettings = [Xml.XmlWriterSettings]::new()
        $writerSettings.Encoding = [Text.UTF8Encoding]::new($false)
        $writerSettings.NewLineHandling = [Xml.NewLineHandling]::None
        $writer = [Xml.XmlWriter]::Create($file, $writerSettings)
        try { $xml.Save($writer) } finally { $writer.Dispose() }
        $updated++
    }
}
[pscustomobject]@{ matchedFiles=$matched; updatedFiles=$updated }
