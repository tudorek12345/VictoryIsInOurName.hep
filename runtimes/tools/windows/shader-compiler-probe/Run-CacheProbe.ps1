param(
    [ValidateRange(1, 120)][int]$Seconds = 60,
    [ValidatePattern('^cache-stress-\d{8}-\d{6}-[a-f0-9]{8}$')][string]$DriverCacheFrom
)
$ErrorActionPreference='Stop'
$local=Split-Path -Parent $PSScriptRoot
$root=Join-Path $local ('isolated-run\stage\cache-stress-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$bin=Join-Path $root 'bin'
$output=Join-Path $root 'output'
New-Item -ItemType Directory -Path $bin,$output | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'compiler_probe.exe') -Destination (Join-Path $bin 'probe.exe')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'cache-stress.dxil') -Destination (Join-Path $bin 'authored.dxil')
if ($DriverCacheFrom) {
    $seed = Join-Path $local ('isolated-run\stage\'+$DriverCacheFrom)
    if ((Get-FileHash (Join-Path $seed 'bin\probe.exe')).Hash -ne (Get-FileHash (Join-Path $bin 'probe.exe')).Hash -or
        (Get-FileHash (Join-Path $seed 'bin\authored.dxil')).Hash -ne (Get-FileHash (Join-Path $bin 'authored.dxil')).Hash) { throw 'Probe seed inputs differ.' }
    Copy-Item -LiteralPath (Join-Path $seed 'output\driver-cache') -Destination (Join-Path $output 'driver-cache') -Recurse
}
$records=@()
foreach ($phase in @('cold','reuse')) {
    $arguments=@('--program',(Join-Path $bin 'probe.exe'),'--rx',$bin,'--modify',$output,
        '--log',(Join-Path $root ($phase+'.log')),'--seconds',$Seconds,'--commit-mib',4096,'--reserve-commit-mib',4096)
    if ($phase -eq 'reuse' -or $DriverCacheFrom) { $arguments += '--reuse-output' }
    $arguments+=@('--',(Join-Path $bin 'authored.dxil'),'--cache',(Join-Path $output 'authored.pso'))
    & (Join-Path $local 'isolated-run\isolated-run-guard.exe') @arguments *> (Join-Path $root ($phase+'-runner.log'))
    $code=$LASTEXITCODE
    $records+=[pscustomobject]@{phase=$phase;exitCode=$code;shaderSha256=(Get-FileHash (Join-Path $bin 'authored.dxil')).Hash;exeSha256=(Get-FileHash (Join-Path $bin 'probe.exe')).Hash}
    $records | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'results.json') -Encoding UTF8
    Get-Content -LiteralPath (Join-Path $root ($phase+'.log'))
    if ($code -ne 0) { throw "The authored $phase probe failed with $code; see $root" }
}
$root
