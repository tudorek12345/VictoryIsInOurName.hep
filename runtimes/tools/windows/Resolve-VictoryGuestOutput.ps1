[CmdletBinding()]
param(
    [string]$GuestOutput,
    [switch]$Supported,
    [switch]$FreshState,
    [string]$DisplayMode,
    [switch]$Test720p,
    [switch]$MenuPicture,
    [switch]$PrepareOnly,
    [switch]$PrewarmPipelines,
    [switch]$PrewarmLibrary,
    [switch]$PrewarmCurrentCache
)
$ErrorActionPreference = 'Stop'
if (-not $GuestOutput) { return $null }
$mode = $GuestOutput.Trim().ToLowerInvariant()
if ($mode -notin @('1280x720','1664x936','1920x1080','2560x1440','3840x2160')) {
    throw 'GuestOutput must be one of 1280x720, 1664x936, 1920x1080, 2560x1440 or 3840x2160.'
}
if (-not $Supported) { throw 'The selected runtime does not implement the checked VICTORY_OUTPUT patch.' }
if (-not $FreshState) { throw 'GuestOutput requires FreshState so experimental title settings cannot overwrite the normal saved profile.' }
if ($DisplayMode -or $Test720p -or $MenuPicture) {
    throw 'GuestOutput conflicts with DisplayMode, Test720p and MenuPicture; use one resolution experiment at a time.'
}
if ($PrepareOnly -or $PrewarmPipelines -or $PrewarmLibrary -or $PrewarmCurrentCache) {
    throw 'GuestOutput is a title experiment, not a pipeline-preparation option.'
}
return $mode
