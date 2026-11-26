[CmdletBinding()]
param([string]$LocalRoot = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$resolver = Join-Path $LocalRoot 'Resolve-VictoryDisplayOptions.ps1'
$checks = 0
function Reject([string]$Label, [hashtable]$Options) {
    $rejected = $false
    try { $null = & $resolver @Options } catch { $rejected = $true }
    if (-not $rejected) { throw "Accepted invalid configuration: $Label" }
    $script:checks++
    Write-Output "PASS $Label"
}
foreach ($bad in @('1920','1920:1080','0x0','639x720','1280x359','7681x4320','7680x4321','99999999999x720')) {
    Reject "invalid display mode $bad" @{ DisplayMode=$bad; GuestDisplaySupported=$true }
}
Reject 'conflicting 720p and 1080p requests' @{ DisplayMode='1920x1080'; Test720p=$true; GuestDisplaySupported=$true }
Reject 'guest mode unsupported by selected runtime' @{ DisplayMode='1280x720'; LegacyPresentSupported=$true }
Reject '720p unsupported by selected runtime' @{ Test720p=$true }
Reject 'mission trace unsupported by selected runtime' @{ MissionTrace=$true }
$result = & $resolver -DisplayMode '1920X1080' -GuestDisplaySupported
if ($result.GuestDisplayMode -ne '1920x1080' -or $result.LegacyPresent720p) { throw 'Wrong guest display mapping.' }
$checks++
Write-Output 'PASS normalized 1080p guest mode'
$result = & $resolver -Test720p -GuestDisplaySupported -LegacyPresentSupported
if ($result.GuestDisplayMode -ne '1280x720' -or $result.LegacyPresent720p) { throw '720p used the obsolete output-only flag.' }
$checks++
Write-Output 'PASS 720p prefers the effective guest mode'
$result = & $resolver -Test720p -LegacyPresentSupported
if ($result.GuestDisplayMode -or -not $result.LegacyPresent720p) { throw 'Legacy runtime behavior was not preserved.' }
$checks++
Write-Output 'PASS legacy output-only mode stays explicit'
$result = & $resolver -DisplayMode '1280x720' -Test720p -GuestDisplaySupported
if ($result.GuestDisplayMode -ne '1280x720') { throw 'Matching 720p options conflict.' }
$checks++
Write-Output 'PASS matching options agree'
$result = & $resolver
if ($result.GuestDisplayMode -or $result.LegacyPresent720p -or $result.MissionTraceEnabled) { throw 'Default run was changed.' }
$checks++
Write-Output 'PASS default run unchanged'
Write-Output "$checks checks passed; no runtime or title launched."
