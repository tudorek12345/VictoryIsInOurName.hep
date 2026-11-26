[CmdletBinding()]
param([string]$LocalRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
$resolver=Join-Path $LocalRoot 'Resolve-VictoryGuestOutput.ps1'
$checks=0
function Reject([hashtable]$Options) {
    $failed=$false
    try { $null=& $resolver @Options } catch { $failed=$true }
    if(-not $failed){throw 'An invalid guest-output configuration was accepted.'}
    $script:checks++
}
if($null -ne (& $resolver)){throw 'An unset option must remain disabled.'}
$checks++
foreach($mode in @('1280x720','1664x936','1920x1080','2560x1440','3840x2160')){
    $actual=& $resolver -GuestOutput $mode -Supported -FreshState
    if($actual -ne $mode){throw 'Supported output mode changed.'}
    $checks++
}
if((& $resolver -GuestOutput ' 1920X1080 ' -Supported -FreshState) -ne '1920x1080'){throw 'Normalization failed.'}
$checks++
foreach($mode in @('1080p','1920x720','0x0','7680x4320','1920x1080;echo x')){
    Reject @{GuestOutput=$mode;Supported=$true;FreshState=$true}
}
Reject @{GuestOutput='1920x1080';FreshState=$true}
Reject @{GuestOutput='1920x1080';Supported=$true}
foreach($conflict in @('Test720p','MenuPicture','PrepareOnly','PrewarmPipelines','PrewarmLibrary','PrewarmCurrentCache')){
    $options=@{GuestOutput='1920x1080';Supported=$true;FreshState=$true}
    $options[$conflict]=$true
    Reject $options
}
Reject @{GuestOutput='1920x1080';Supported=$true;FreshState=$true;DisplayMode='1920x1080'}
Write-Output "$checks guest-output checks passed; no runtime or title launched."
