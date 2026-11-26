[CmdletBinding()]
param(
    [ValidateSet('victory', 'xcl')]
    [string]$Backend = 'victory',

    [ValidateSet('review', 'project', 'amd7900', 'amd7900-series-s', 'fxceless')]
    [string]$VictorySource = 'review',

    [ValidateSet('series-s', 'series-x')]
    [string]$Console = 'series-s',

    [ValidateSet('warp', 'hardware')]
    [string]$Renderer = 'hardware',

    [ValidateRange(1, 3600)]
    [int]$Seconds = 3600,

    [ValidateRange(0, 131072)]
    [int]$CommitMiB = 0,

    [ValidateRange(0, 32768)]
    [int]$HostReserveMiB = 0,

    [switch]$PrepareOnly,

    [switch]$CaptureFrames,
    [uint32[]]$CaptureAt,

    [switch]$MenuPicture,
    [switch]$QueuedSubmit,
    [switch]$TextureNoWait,

    [switch]$CaptureAudio,
    [switch]$MovieAudio = $true,
    [switch]$MemoryStats,
    [switch]$GpuTiming,
    [switch]$SplitGpuLists,
    [switch]$MissionTrace,
    [ValidateRange(0, 128)]
    [int]$PipelineWorkers = 0,
    [switch]$PipelineBook,
    [switch]$PrewarmPipelines,
    [ValidateRange(1, 10000)]
    [int]$PrewarmLimit = 2048,
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$PipelineBookFrom,
    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$PipelineUseFrom,
    [ValidateSet(0, 64, 128, 256, 512, 1024, 2048, 4096)]
    [int]$ShadowWindowKiB = 0,

    [switch]$FreshState,
    [switch]$Test720p,
    [string]$WarpDll,

    [ValidatePattern('^original-\d{8}-\d{6}-[a-f0-9]{8}$')]
    [string]$WarmCacheFrom,

    [string]$BcpackTables = $env:VICTORY_BCPACK_TABLES,
    [string]$DiagnosticKeys,

    [uint32]$TraceFrame,

    [string]$LocalRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$local = (Resolve-Path -LiteralPath $LocalRoot).Path
$workspace = Split-Path -Parent $local
$useXcl = $Backend -eq 'xcl'
if ($useXcl -and $VictorySource -ne 'review') {
    throw 'VictorySource only applies to the Victory backend.'
}
$snapshot = $VictorySource -in 'amd7900', 'fxceless'
$standalone = $snapshot -or $VictorySource -eq 'amd7900-series-s'
$amdFork = $VictorySource -in 'amd7900', 'amd7900-series-s'
if (($PipelineWorkers -or $PipelineBook -or $PrewarmPipelines) -and -not $amdFork) {
    throw 'Pipeline worker, recording and prewarm options require the AMD fork.'
}
if ($PrewarmPipelines -and -not ($WarmCacheFrom -or $PipelineBookFrom)) {
    throw 'PrewarmPipelines requires WarmCacheFrom or PipelineBookFrom with a prior PipelineBook run.'
}
if ($PipelineBookFrom -and (-not $amdFork -or -not $FreshState -or $WarmCacheFrom -or $PrepareOnly)) {
    throw 'PipelineBookFrom requires an AMD fork fresh state and cannot be combined with WarmCacheFrom or PrepareOnly.'
}
if ($PipelineUseFrom -and -not $PipelineBookFrom) {
    throw 'PipelineUseFrom requires PipelineBookFrom.'
}
if ($QueuedSubmit -and ($VictorySource -ne 'amd7900-series-s' -or $GpuTiming)) {
    throw 'QueuedSubmit requires the Series S candidate and cannot use synchronous GPU timing.'
}
if ($TextureNoWait -and -not $amdFork) {
    throw 'TextureNoWait requires the AMD fork with fault-safe texture reads.'
}
if ($ShadowWindowKiB -and -not $amdFork) {
    throw 'ShadowWindowKiB requires the AMD fork.'
}
$repo = if ($useXcl) { Join-Path $local 'upstream-xcl' } else {
    switch ($VictorySource) {
        'review' { Join-Path $local 'leonida-review' }
        'project' { Join-Path $local 'VictoryIsInOurName.hep' }
        'amd7900' { Join-Path $workspace 'VIctory-7900XTX-main' }
        'amd7900-series-s' { Join-Path $local 'amd7900-series-s' }
        'fxceless' { Join-Path $workspace 'victory-fork-main' }
    }
}
$runtime = if ($useXcl -or $standalone) { $repo } else { Join-Path $repo 'runtimes\victory' }
$package = Join-Path $workspace 'buildgta'
$title = Join-Path $package 'game_scarlett_master.exe'
$toolHome = Join-Path $local 'isolated-run'
$helper = Join-Path $toolHome $(if ($HostReserveMiB) { 'isolated-run-guard.exe' } else { 'isolated-run.exe' })
$cargoHome = Join-Path $local 'cargo'
$cargo = Join-Path $cargoHome 'bin\cargo.exe'
$target = Join-Path $local $(if ($useXcl) { 'target-xcl' } else {
    switch ($VictorySource) {
        'review' { 'target' }
        'project' { 'target-leonida-review' }
        'amd7900' { 'target-7900xtx' }
        'amd7900-series-s' { 'target-amd7900-series-s' }
        'fxceless' { 'target-fxceless' }
    }
})
$engine = Join-Path $target $(if ($useXcl) { 'release\xcl.exe' } else { 'diag\victory.exe' })
$launchLock = Join-Path $local 'launch.lock'
$warpModule = $null

if ($WarpDll) {
    if ($useXcl -or $Renderer -ne 'warp' -or $PrepareOnly) {
        throw 'The optional WARP DLL requires a Victory software-renderer run.'
    }
    $warpModule = Get-Item -LiteralPath $WarpDll
    if ($warpModule.PSIsContainer -or $warpModule.Name -ne 'd3d10warp.dll') {
        throw 'The WARP file must be named d3d10warp.dll.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $warpModule.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )CN=Microsoft Corporation(,|$)') {
        throw 'The app-local WARP DLL must have a valid Microsoft signature.'
    }
}

if ($WarmCacheFrom -and ($useXcl -or $PrepareOnly -or -not ($Test720p -or $FreshState))) {
    throw 'A warm cache seed requires a Victory run with its own test profile.'
}

if (-not (Test-Path -LiteralPath $title -PathType Leaf)) {
    throw "The original title is missing at $title"
}
if (-not (Test-Path -LiteralPath $cargo -PathType Leaf)) {
    throw "The workspace Rust toolchain is missing at $cargo"
}
if (-not ($useXcl -or $PrepareOnly)) {
    if (-not $BcpackTables) {
        $BcpackTables = Join-Path $workspace 'VIctory-main\crates\victory-formats\src\bcpack-tables.bin'
    }
    $tables = Get-Item -LiteralPath $BcpackTables
    if ($tables.PSIsContainer -or $tables.Length -ne 77982) {
        throw "The local BCPack tables file must contain 77,982 bytes. See $BcpackTables"
    }
}
try {
    $lease = [IO.File]::Open($launchLock, 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] {
    throw 'Another Victory launcher is already using this workspace.'
}

$settings = @{
    CARGO_HOME = $cargoHome
    RUSTUP_HOME = (Join-Path $local 'rustup')
    CARGO_TARGET_DIR = $target
}
$previous = @{}
$exitCode = 1
try {
    foreach ($name in $settings.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $settings[$name], 'Process')
    }
    $checkout = $null
    $checkoutDirty = $null
    if (-not $snapshot) {
        $checkout = (& git -C $repo rev-parse HEAD)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the runtime checkout.' }
        $checkoutDirty = [bool](& git -C $repo status --porcelain --untracked-files=no)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the runtime checkout.' }
    }
    Push-Location -LiteralPath $runtime
    try {
        Write-Host "Building the current $Backend source at $runtime"
        # Windows PowerShell turns redirected native stderr (including compiler
        # warnings) into ErrorRecords. The compiler's exit code decides success.
        $buildErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            if ($useXcl) {
                & $cargo +1.98.1 build --locked --release -p xcl
            } else {
                & $cargo build --locked --jobs 4 --profile diag -p victory --features diagnostics
            }
            $buildExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $buildErrorPreference
        }
        if ($buildExitCode -ne 0) { throw "$Backend failed to build (exit $buildExitCode)." }
    } finally {
        Pop-Location
    }

    if ($PrepareOnly) {
        if ($useXcl) {
            & $engine inspect $title
        } else {
            $previous['VICTORY_CONFIG'] = [Environment]::GetEnvironmentVariable('VICTORY_CONFIG', 'Process')
            $env:VICTORY_CONFIG = Join-Path $local 'victory.toml'
            & $engine run $title --console $Console
        }
        $exitCode = $LASTEXITCODE
    } else {
        if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) {
            throw "The isolation helper is missing at $helper"
        }
        $memory = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
        $available = $memory.CommitLimit - $memory.CommittedBytes
        $reserveCommitBytes = if ($HostReserveMiB) { 8GB } else { 1GB }
        $withReserve = [Math]::Floor(($available - $reserveCommitBytes) / 1MB)
        if ($CommitMiB -eq 0) {
            $preferredCommitMiB = if ($HostReserveMiB) { 24576 } else { 16384 }
            $CommitMiB = [Math]::Min($preferredCommitMiB, $withReserve)
        }
        if ($CommitMiB -lt 512 -or $CommitMiB -gt $withReserve) {
            throw ('Host commit headroom is {0:N2} GiB. Choose a cap that leaves a {1:N0} GiB host reserve.' -f ($available / 1GB), ($reserveCommitBytes / 1GB))
        }
        if ($HostReserveMiB -and ($HostReserveMiB -lt 512 -or $memory.AvailableMBytes -le $HostReserveMiB)) {
            throw ('Physical memory available is {0} MiB. The reserve must be at least 512 MiB and below available memory.' -f $memory.AvailableMBytes)
        }

        $runId = $(if ($useXcl) { 'xcl-original-' } else { 'original-' }) +
            (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $run = Join-Path $toolHome ('stage\' + $runId)
        $bin = Join-Path $run 'bin'
        $sharedState = Join-Path $toolHome $(switch ($VictorySource) {
            'review' { 'stage\victory-state' }
            'project' { 'stage\victory-project-state' }
            'amd7900' { 'stage\victory-amd7900-state' }
            'amd7900-series-s' { 'stage\victory-amd-series-s-state' }
            'fxceless' { 'stage\victory-fxceless-state' }
        })
        $output = if ($useXcl -or $FreshState -or $Test720p) {
            Join-Path $run 'output'
        } else {
            $sharedState
        }
        $logs = Join-Path $run 'logs'
        New-Item -ItemType Directory -Path $bin, $output, $logs -Force | Out-Null
        if ($Test720p) {
            if ($useXcl -or $FreshState) { throw 'The resolution test uses a copy of the saved Victory profile.' }
            $sharedData = Join-Path $sharedState 'data'
            if (Test-Path -LiteralPath $sharedData -PathType Container) {
                Copy-Item -LiteralPath $sharedData -Destination (Join-Path $output 'data') -Recurse
            }
        }
        if ($WarmCacheFrom) {
            $seed = Join-Path $toolHome ('stage\' + $WarmCacheFrom)
            $seedSummary = Get-Content -LiteralPath (Join-Path $seed 'logs\diagnostics.json') -Raw | ConvertFrom-Json
            $seedEngine = Join-Path $seed 'bin\victory.exe'
            if ($seedSummary.renderer -ne $Renderer -or
                $seedSummary.console -ne $Console -or
                (Get-FileHash -LiteralPath $seedEngine).Hash -ne (Get-FileHash -LiteralPath $engine).Hash) {
                throw 'The seed must use the same Victory executable, renderer, and console profile.'
            }
            $seededCache = Join-Path $output 'cache'
            New-Item -ItemType Directory -Path $seededCache | Out-Null
            foreach ($kind in @('shaders', 'pipelines')) {
                $source = Join-Path $seed ('output\cache\' + $kind)
                if (Test-Path -LiteralPath $source -PathType Container) {
                    Copy-Item -LiteralPath $source -Destination (Join-Path $seededCache $kind) -Recurse
                }
            }
            Write-Host "Seeded shader and pipeline cache from $WarmCacheFrom"
            if ($PrewarmPipelines -and -not (Test-Path -LiteralPath (Join-Path $seededCache 'pipelines\known-pipelines.bin'))) {
                throw 'The selected seed has no saved pipeline book.'
            }
        }
        if ($PipelineBookFrom) {
            $seedArguments = @{ BookRun = $PipelineBookFrom; DestinationCache = (Join-Path $output 'cache') }
            if ($PipelineUseFrom) { $seedArguments.UseRun = $PipelineUseFrom }
            & (Join-Path $local 'Seed-VictoryPipelineBook.ps1') @seedArguments
        }
        $captureDir = Join-Path $output ('captures\' + $runId)
        if (-not $useXcl -and ($CaptureFrames -or $CaptureAt -or $CaptureAudio -or $TraceFrame)) {
            New-Item -ItemType Directory -Path $captureDir -Force | Out-Null
        }

        $stagedEngine = Join-Path $bin (Split-Path -Leaf $engine)
        Copy-Item -LiteralPath $engine -Destination $stagedEngine
        if ($warpModule) {
            Copy-Item -LiteralPath $warpModule.FullName -Destination $bin
            Write-Host "App-local WARP version $($warpModule.VersionInfo.ProductVersion)"
        }
        $titleLog = Join-Path $logs "$Backend.log"
        Write-Host "Original package is $package"
        Write-Host "Launch log is $titleLog"
        $profile = if ($useXcl) { 'default XCL console profile' } else { $Console }
        Write-Host "Renderer $Renderer, $profile, $CommitMiB MiB commit cap"

        $logFilter = 'info,victory_hle::modules::files=debug,victory_hle::modules::dstorage=debug'
        if ($TraceFrame) { $logFilter += ',victory_gpu::draw=debug' }
        $arguments = @(
            '--program', $stagedEngine,
            '--rx', $bin, '--external-rx', $package,
            '--modify', $output, '--log', $titleLog,
            '--seconds', $Seconds, '--commit-mib', $CommitMiB
        )
        if ($HostReserveMiB) {
            $arguments += @('--reserve-physical-mib', $HostReserveMiB, '--reserve-commit-mib', '4096')
        }
        if ($useXcl) {
            $adapter = if ($Renderer -eq 'warp') { 'warp' } else { 'radeon' }
            $arguments += @(
                '--env', "XCL_DATA_ROOT=$output",
                '--env', "XCL_ADAPTER=$adapter",
                '--env', 'XCL_DRED=1',
                '--env', 'XCL_NETWORK=0'
            )
            if ($MemoryStats) { $arguments += @('--env', 'XCL_ACTIVITY=1') }
            if ($CaptureFrames) { $arguments += @('--env', 'XCL_FRAME_DUMP=60') }
            $arguments += @('--', 'run', $title)
        } else {
            $stagedTables = Join-Path $bin 'bcpack-tables.bin'
            Copy-Item -LiteralPath $tables.FullName -Destination $stagedTables
            $adapter = if ($Renderer -eq 'warp') { 'warp' } else { 'radeon' }
            $arguments += @(
                '--reuse-output',
                '--env', "VICTORY_BCPACK_TABLES=$stagedTables",
                '--env', "VICTORY_GAME_DIR=$package",
                '--env', ('VICTORY_CACHE_DIR=' + (Join-Path $output 'cache')),
                '--env', ('VICTORY_DATA_DIR=' + (Join-Path $output 'data')),
                '--env', 'VICTORY_D3D12_DRED=1',
                '--env', "VICTORY_D3D12_ADAPTER=$adapter",
                '--env', "VICTORY_LOG=$logFilter"
            )
            if ($MemoryStats) { $arguments += @('--env', 'VICTORY_MEMORY_STATS=1') }
            if ($TextureNoWait) { $arguments += @('--env', 'VICTORY_TEXTURE_NO_WAIT=1') }
            if ($Renderer -eq 'warp' -and $VictorySource -ne 'review') {
                $arguments += @('--env', 'VICTORY_D3D12_WARP=1')
            }
            if ($GpuTiming) { $arguments += @('--env', 'VICTORY_GPU_TIMING=1') }
            if ($SplitGpuLists) { $arguments += @('--env', 'VICTORY_GPU_SPLIT_LISTS=1') }
            if ($MissionTrace) { $arguments += @('--env', 'VICTORY_MISSION_TRACE=1') }
            if ($PipelineWorkers) { $arguments += @('--env', "VICTORY_PIPELINE_WORKERS=$PipelineWorkers") }
            if ($PipelineBook) { $arguments += @('--env', 'VICTORY_PIPELINE_BOOK=1') }
            if ($ShadowWindowKiB) {
                $arguments += @('--env', "VICTORY_WINDOW_KB=$ShadowWindowKiB")
                if ($ShadowWindowKiB -lt 4096) { $arguments += @('--env', 'VICTORY_WINDOW_TAILS=1') }
            }
            if ($MenuPicture -and $Console -eq 'series-s') {
                $arguments += @('--env', 'VICTORY_SERIES_S_MENU_PICTURE=1')
                if ($VictorySource -eq 'amd7900-series-s' -and -not $QueuedSubmit) {
                    $arguments += @('--env', 'VICTORY_LATE_WAIT=0', '--env', 'VICTORY_THIN=0', '--env', 'VICTORY_ASYNC_SUBMIT=0')
                }
            }
            if ($QueuedSubmit) {
                $arguments += @('--env', 'VICTORY_RELAY=1', '--env', 'VICTORY_LATE_WAIT=3', '--env', 'VICTORY_THIN=1', '--env', 'VICTORY_ASYNC_SUBMIT=1')
            }
            if ($CaptureAudio) {
                $arguments += @('--env', ('VICTORY_AUDIO_CAPTURE=' + (Join-Path $captureDir 'audio.wav')))
            }
            $arguments += @('--env', ('VICTORY_BINK_XAUDIO2=' + [int][bool]$MovieAudio))
            if ($Test720p) { $arguments += @('--env', 'VICTORY_PRESENT_720P=1') }
            if ($DiagnosticKeys) {
                $arguments += @('--env', "VICTORY_KEYS=$DiagnosticKeys", '--env', 'VICTORY_KEYS_STAND_IN=1')
            }
            if ($CaptureFrames -or $CaptureAt -or $TraceFrame) {
                $arguments += @('--env', "VICTORY_CAPTURE=$captureDir")
                if ($TraceFrame) {
                    $arguments += @('--env', "VICTORY_CAPTURE_FRAMES=$TraceFrame", '--env', 'VICTORY_DUMP_TARGETS=1')
                } elseif ($CaptureAt) {
                    $arguments += @('--env', ('VICTORY_CAPTURE_FRAMES=' + ($CaptureAt -join ',')))
                }
            }
            if ($PrewarmPipelines) {
                $arguments += @('--', 'warm', '--used', '--jobs', '2', '--limit', "$PrewarmLimit")
            } else {
                $arguments += @('--', 'run', $title, '--console', $Console, '--execute')
            }
        }
        $runnerLog = Join-Path $logs 'runner.log'
        $started = Get-Date
        $ErrorActionPreference = 'Continue'
        & $helper @arguments *>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $runnerLog
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $peak = Select-String -LiteralPath $runnerLog -Pattern 'Peak job commit bytes: (\d+);' |
            Select-Object -Last 1
        $peakBytes = if ($peak) { [long]$peak.Matches[0].Groups[1].Value } else { $null }
        $actualAdapter = $null
        $driverVersion = $null
        if (-not $useXcl -and (Test-Path -LiteralPath $titleLog)) {
            $device = Select-String -LiteralPath $titleLog -SimpleMatch 'host D3D12 adapter' | Select-Object -First 1
            $deviceText = $device.Line -replace ([string][char]27 + '\[[0-9;]*m'), ''
            if ($deviceText -match 'adapter="([^"]+)"') {
                $actualAdapter = $Matches[1]
                if ($Renderer -eq 'hardware') {
                    $driverVersion = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                        Where-Object Name -eq $actualAdapter | Select-Object -First 1 -ExpandProperty DriverVersion
                }
            } elseif ($Renderer -eq 'warp' -and (Select-String -LiteralPath $titleLog -SimpleMatch 'host device on the software adapter (WARP)' -Quiet)) {
                $actualAdapter = 'Microsoft Basic Render Driver'
            }
        }
        $summary = [ordered]@{
            backend = $Backend
            victorySource = if ($useXcl) { $null } else { $VictorySource }
            renderer = $Renderer
            adapter = $actualAdapter
            driverVersion = $driverVersion
            console = $profile
            requested720p = [bool]$Test720p
            warmCacheFrom = if ($WarmCacheFrom) { $WarmCacheFrom } else { $null }
            queuedSubmit = [bool]$QueuedSubmit
            textureNoWait = [bool]$TextureNoWait
            menuPicture = [bool]$MenuPicture
            memoryStats = [bool]$MemoryStats
            pipelineBookFrom = if ($PipelineBookFrom) { $PipelineBookFrom } else { $null }
            pipelineUseFrom = if ($PipelineUseFrom) { $PipelineUseFrom } else { $null }
            gpuTiming = [bool]$GpuTiming
            splitGpuLists = [bool]($SplitGpuLists -or $GpuTiming)
            missionTrace = [bool]$MissionTrace
            pipelineWorkers = if ($PipelineWorkers) { $PipelineWorkers } else { $null }
            pipelineBook = [bool]$PipelineBook
            prewarmPipelines = [bool]$PrewarmPipelines
            prewarmLimit = if ($PrewarmPipelines) { $PrewarmLimit } else { $null }
            requestedSeconds = $Seconds
            diagnosticKeys = if ($DiagnosticKeys) { $DiagnosticKeys } else { $null }
            captureFrames = @($CaptureAt)
            shadowWindowKiB = if ($ShadowWindowKiB) { $ShadowWindowKiB } else { $null }
            binkXAudio2 = [bool]$MovieAudio
            warpProductVersion = if ($warpModule) { $warpModule.VersionInfo.ProductVersion } else { $null }
            checkout = $checkout
            checkoutPath = $repo
            checkoutDirty = $checkoutDirty
            runtimeSha256 = (Get-FileHash -LiteralPath $stagedEngine -Algorithm SHA256).Hash
            packageExecutableSha256 = (Get-FileHash -LiteralPath $title -Algorithm SHA256).Hash
            started = $started.ToString('o')
            elapsedSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
            availableCommitBytesAtStart = $available
            hostPhysicalReserveMiB = $HostReserveMiB
            hostCommitReserveMiB = if ($HostReserveMiB) { 4096 } else { 0 }
            jobCommitLimitBytes = [long]$CommitMiB * 1MB
            peakJobCommitBytes = $peakBytes
            exitCode = $exitCode
            exitHex = ('0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$exitCode), 0))
            log = $titleLog
            state = $output
        }
        if (Test-Path -LiteralPath $captureDir) { $summary['captures'] = $captureDir }
        $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logs 'diagnostics.json') -Encoding utf8
        if ($exitCode -eq 126 -and $HostReserveMiB) {
            Write-Warning 'The host memory guard ended this session.'
        } elseif ($exitCode -eq 124) {
            Write-Host "$Backend reached the configured session time limit."
        } elseif ($exitCode -ne 0) {
            Write-Host "$Backend exited with code $exitCode. See $titleLog"
        }
    }
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
    $lease.Dispose()
}
exit $exitCode
