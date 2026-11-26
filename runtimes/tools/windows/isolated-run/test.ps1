param([switch] $ExternalPackage, [switch] $PhysicalGuard)

$ErrorActionPreference = 'Stop'

$testRoot = Join-Path $PSScriptRoot ('stage\test-' + [guid]::NewGuid().ToString('N'))
$inputRoot = Join-Path $testRoot 'read only'
$output = Join-Path $testRoot 'output'
$timeoutOutput = Join-Path $testRoot 'timeout-output'
$guardOutput = Join-Path $testRoot 'guard-output'
$commitGuardOutput = Join-Path $testRoot 'commit-guard-output'
$private = Join-Path $testRoot 'private'
$logs = Join-Path $testRoot 'logs'
New-Item -ItemType Directory -Path $inputRoot, $output, $timeoutOutput, $guardOutput, $commitGuardOutput, $private, $logs -Force | Out-Null

$inputFile = Join-Path $inputRoot 'seed.bin'
$outFile = Join-Path $output 'new.bin'
$privateFile = Join-Path $private 'secret.bin'
$inputWrite = Join-Path $inputRoot 'must-not-exist.bin'
$program = Join-Path $inputRoot 'probe.exe'
$log = Join-Path $logs 'probe.log'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'probe.exe') -Destination $program
[IO.File]::WriteAllText($inputFile, 'probe')
[IO.File]::WriteAllText($privateFile, 'probe')
$runner = Join-Path $PSScriptRoot $(if ($PhysicalGuard) { 'isolated-run-guard.exe' } else { 'isolated-run.exe' })
$aclPaths = $inputRoot, $program, $inputFile, $output, $timeoutOutput, $guardOutput, $commitGuardOutput
$externalArgs = @()
if ($ExternalPackage) {
    $runner = Join-Path $PSScriptRoot 'isolated-run-external-test.exe'
    $externalRoot = Join-Path $PSScriptRoot 'external-test-package'
    $externalSample = Join-Path $externalRoot (Split-Path -Leaf $testRoot)
    New-Item -ItemType Directory -Path $externalSample -Force | Out-Null
    $inputFile = Join-Path $externalSample 'seed.bin'
    $inputWrite = Join-Path $externalSample 'must-not-exist.bin'
    [IO.File]::WriteAllText($inputFile, 'probe')
    [IO.File]::SetAttributes($inputFile, [IO.FileAttributes]::ReadOnly)
    $externalArgs = @('--external-rx', $externalRoot)
    $aclPaths += $externalRoot, $externalSample, $inputFile
}
function Get-AccessRules {
    param([string[]] $Path)
    # Windows marks a descriptor auto-inherited after propagating an ACL.
    # Ignore that control bit while comparing owners, protection and each ACE.
    $Path | ForEach-Object { (Get-Acl -LiteralPath $_).Sddl -replace '(?<=D:)AI(?=\()', '' }
}
$before = Get-AccessRules $aclPaths

# This endpoint is bound to a non-loopback interface on this same machine.
# A host-side client first connects, proving the reference endpoint is reachable.
$ipv4 = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
    Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1 -ExpandProperty IPAddress
if (!$ipv4) { throw 'A non-loopback IPv4 interface is required for the socket-denial test.' }
$address = [Net.IPAddress]::Parse($ipv4)
$listener = [Net.Sockets.TcpListener]::new($address, 0)
$listener.Start()
try {
    $port = $listener.LocalEndpoint.Port
    $baseline = [Net.Sockets.TcpClient]::new()
    try {
        $baseline.Connect($address, $port)
        $accepted = $listener.AcceptTcpClient()
        $accepted.Dispose()
    } finally {
        $baseline.Dispose()
    }
    & $runner --program $program --rx $inputRoot @externalArgs --modify $output --log $log --seconds 10 --commit-mib 64 -- $inputFile $inputWrite $outFile $privateFile $ipv4 $port
    $result = $LASTEXITCODE
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }
    if ($result -ne 0) { throw "Probe returned $result. See $log" }
    if ($listener.Pending()) { throw 'The isolated probe reached the host listener.' }
} finally {
    $listener.Stop()
}

$timeoutLog = Join-Path $logs 'timeout.log'
$wrapperMessages = & $runner --program $program --rx $inputRoot @externalArgs --modify $timeoutOutput --log $timeoutLog --seconds 1 --commit-mib 64 -- wait
$result = $LASTEXITCODE
Write-Output $wrapperMessages
if ($result -ne 124 -or (Get-Content -LiteralPath $timeoutLog) -ne 'Waiting in test process') {
    throw "Timeout test returned $result. See $timeoutLog"
}
$child = $wrapperMessages | Select-String 'Child PID (\d+)' | Select-Object -First 1
if (!$child -or (Get-Process -Id $child.Matches[0].Groups[1].Value -ErrorAction SilentlyContinue)) {
    throw 'The timed-out test process may still be running.'
}
if ($PhysicalGuard) {
    $guardLog = Join-Path $logs 'guard.log'
    $reserve = [Math]::Ceiling((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024) + 1024
    $messages = & $runner --program $program --rx $inputRoot @externalArgs --modify $guardOutput --log $guardLog --seconds 10 --commit-mib 64 --reserve-physical-mib $reserve -- wait
    if ($LASTEXITCODE -ne 126 -or -not ($messages | Select-String 'Host memory guard reached')) {
        throw 'The physical-memory guard did not stop the probe.'
    }
    Write-Output $messages
    $commitLog = Join-Path $logs 'commit-guard.log'
    $commitReserve = [Math]::Ceiling((Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).CommitLimit / 1MB) + 1024
    $messages = & $runner --program $program --rx $inputRoot @externalArgs --modify $commitGuardOutput --log $commitLog --seconds 10 --commit-mib 64 --reserve-commit-mib $commitReserve -- wait
    if ($LASTEXITCODE -ne 126 -or -not ($messages | Select-String 'Host commit guard reached')) {
        throw 'The commit guard did not stop the probe.'
    }
    Write-Output $messages
}
$after = Get-AccessRules $aclPaths
if (Compare-Object $before $after -SyncWindow 0) { throw 'An ACL changed after the run.' }
if ((Get-AccessRules $outFile) -like '*S-1-15-2-*') { throw 'The output retained the AppContainer grant.' }
if ((Get-Content -LiteralPath $outFile) -ne 'probe' -or (Test-Path -LiteralPath $inputWrite)) {
    throw 'The staged files do not match the permissions exercised by the probe.'
}
if ($ExternalPackage -and ((Get-Content -LiteralPath $inputFile) -ne 'probe' -or -not (Get-Item -LiteralPath $inputFile).IsReadOnly)) {
    throw 'The external fixture bytes or readonly attribute changed.'
}
Write-Output "Isolation and timeout checks passed. Staged test files and logs are in $testRoot"
