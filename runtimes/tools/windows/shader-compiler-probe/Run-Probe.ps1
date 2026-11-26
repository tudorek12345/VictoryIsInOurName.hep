param(
    [Parameter(Mandatory=$true)][string]$Variant,
    [ValidateRange(1,60)][int]$Seconds = 60,
    [string]$GuardPath
)
$ErrorActionPreference = 'Stop'
$probeRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$localRoot = Split-Path -Parent $probeRoot
$guard = if ([string]::IsNullOrWhiteSpace($GuardPath)) {
    Join-Path (Join-Path $localRoot 'isolated-run') 'isolated-run-guard.exe'
} else {
    [IO.Path]::GetFullPath($GuardPath)
}
$runnerRoot = Split-Path -Parent $guard
$manifest = @(Get-Content -LiteralPath (Join-Path $probeRoot 'variants.json') -Raw | ConvertFrom-Json)
$entry = @($manifest | Where-Object { $_.name -ceq $Variant })
if ($entry.Count -ne 1) { throw 'Variant must be an exact name from variants.json.' }
$entry = $entry[0]
$shader = Join-Path (Join-Path $probeRoot 'variants') ($Variant + '.dxil')
$exe = Join-Path $probeRoot 'compiler_probe.exe'
foreach ($path in @($guard,$exe,$shader)) {
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $path" }
}
if ((Get-FileHash -LiteralPath $shader -Algorithm SHA256).Hash -ine $entry.sha256) {
    throw 'The compiled shader differs from the manifest; rebuild variants before testing.'
}
$runName = 'shader-compiler-probe-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,8)
$stageRoot = [IO.Path]::GetFullPath((Join-Path $runnerRoot 'stage'))
$runRoot = [IO.Path]::GetFullPath((Join-Path $stageRoot $runName))
if (!$runRoot.StartsWith($stageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run directory escaped the isolated stage.'
}
$program = Join-Path $runRoot 'program'
$output = Join-Path $runRoot 'output'
$logs = Join-Path $runRoot 'logs'
foreach ($directory in @($program,$output,$logs)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}
$stagedExe = Join-Path $program 'compiler_probe.exe'
$stagedShader = Join-Path $program ($Variant + '.dxil')
Copy-Item -LiteralPath $exe -Destination $stagedExe
Copy-Item -LiteralPath $shader -Destination $stagedShader
$log = Join-Path $logs 'probe.log'
$argsForGuard = @('--program',$stagedExe,'--rx',$program,'--modify',$output,'--log',$log,
                  '--seconds',([string]$Seconds),'--commit-mib','4096',
                  '--reserve-physical-mib','3072','--reserve-commit-mib','4096','--',$stagedShader)
foreach ($argument in @($entry.probeArguments | Select-Object -Skip 1)) {
    if ($argument -notin @('--explicit','--array16','--array','--mixed-array')) { throw 'Unexpected root-layout argument.' }
    $argsForGuard += $argument
}
$metadata = [ordered]@{
    variant=$Variant; startUtc=[DateTime]::UtcNow.ToString('o'); seconds=$Seconds
    executableSha256=(Get-FileHash -LiteralPath $stagedExe -Algorithm SHA256).Hash
    shaderSha256=$entry.sha256; shaderBytes=$entry.bytes
    commitLimitMiB=4096; physicalReserveMiB=3072; commitReserveMiB=4096
    operation='CreateComputePipelineState only; no dispatch'; log=$log
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'metadata.json') -Encoding UTF8
Write-Output "Variant $Variant; log $log"
& $guard @argsForGuard
$probeExit = $LASTEXITCODE
$metadata.endUtc=[DateTime]::UtcNow.ToString('o')
$metadata.exitCode=$probeExit
$metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'metadata.json') -Encoding UTF8
[pscustomobject]@{ Variant=$Variant; ExitCode=$probeExit; Log=$log; RunRoot=$runRoot }
