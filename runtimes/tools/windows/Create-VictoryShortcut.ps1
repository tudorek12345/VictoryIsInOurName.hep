[CmdletBinding()]
param(
    [string]$LocalRoot = $PSScriptRoot,
    [string]$Destination
)
$ErrorActionPreference = 'Stop'
$local = (Resolve-Path -LiteralPath $LocalRoot).Path
$launcher = Join-Path $local 'Launch-Victory.ps1'
$icon = Join-Path $local 'Victory.ico'
foreach ($file in @($launcher, $icon)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing local launch asset: $file" }
}
if (-not $Destination) { $Destination = Join-Path (Split-Path -Parent $local) 'Launch Victory.lnk' }
if ([IO.Path]::GetExtension($Destination) -ne '.lnk') { throw 'Destination must be a Windows .lnk shortcut.' }
$destinationPath = [IO.Path]::GetFullPath($Destination)
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($destinationPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcut.Arguments = '-NoProfile -File "' + $launcher + '" -VictorySource amd7900-series-s -Console series-x -Renderer hardware -HostReserveMiB 0 -PipelineWorkers 2 -QueuedSubmit -MemorySamples'
$shortcut.WorkingDirectory = $local
$shortcut.IconLocation = $icon + ',0'
$shortcut.Description = 'Build and run Radeon Series X with diagnostics, a bounded job and a system-commit reserve; no physical-RAM floor.'
$shortcut.WindowStyle = 7
$shortcut.Save()
Write-Output $destinationPath
