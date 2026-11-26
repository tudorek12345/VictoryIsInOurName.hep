[CmdletBinding()]
param(
    [string]$DisplayMode,
    [switch]$Test720p,
    [switch]$GuestDisplaySupported,
    [switch]$LegacyPresentSupported,
    [switch]$MissionTrace,
    [switch]$MissionTraceSupported
)
$ErrorActionPreference = 'Stop'
$guestMode = $null
$legacy720p = $false
if ($DisplayMode) {
    if ($DisplayMode -notmatch '^([0-9]{3,4})[xX]([0-9]{3,4})$') {
        throw 'DisplayMode must be WIDTHxHEIGHT, for example 1920x1080.'
    }
    $width = [int]$Matches[1]
    $height = [int]$Matches[2]
    if ($width -lt 640 -or $width -gt 7680 -or $height -lt 360 -or $height -gt 4320) {
        throw 'DisplayMode must be within 640x360 and 7680x4320.'
    }
    $guestMode = '{0}x{1}' -f $width, $height
    if (-not $GuestDisplaySupported) {
        throw 'The selected runtime does not implement VICTORY_DISPLAY_MODE.'
    }
}
if ($Test720p) {
    if ($guestMode -and $guestMode -ne '1280x720') {
        throw 'Test720p conflicts with a DisplayMode other than 1280x720.'
    }
    if ($GuestDisplaySupported) {
        $guestMode = '1280x720'
    } elseif ($LegacyPresentSupported) {
        $legacy720p = $true
    } else {
        throw 'The selected runtime implements neither a guest display mode nor the legacy 720p presentation limit.'
    }
}
if ($MissionTrace -and -not $MissionTraceSupported) {
    throw 'MissionTrace is unsupported by this runtime. It cannot identify or select a mission.'
}
[pscustomobject]@{
    GuestDisplayMode = $guestMode
    LegacyPresent720p = $legacy720p
    MissionTraceEnabled = [bool]$MissionTrace
}
