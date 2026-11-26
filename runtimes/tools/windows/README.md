# Local Windows reproduction tools

These are the source of the workstation harness. Game files, recorded pipeline
books, generated shader caches, captures and raw logs stay outside the repository.
The tools record measured output; they do not certify gameplay from draw counts.

`Launch-Victory.ps1 -LocalRoot <workspace-local>` uses the existing workspace
layout: the package is `../buildgta`, Rust is in `cargo`/`rustup`, source checkouts
are siblings of the launcher, and the isolated runner is in `isolated-run`.
Copy these scripts to that local directory, or pass its path with `-LocalRoot`.
The matching source-only candidate patches and their exact base are documented
in [the integration notes](../../../INTEGRATION.md).

Build the runner with `isolated-run/build.cmd guard`. Its source preserves the
read-only package grants, zero-capability AppContainer and bounded job. It leaves
the Windows GPU watchdog unchanged. The memory reserve monitor is checked every
500 ms; it cannot guarantee recovery from a driver hang.

Direct invocation now defaults to the Series X profile on Radeon, with ordered
submission and two pipeline workers. At the user's request, the physical-RAM
reserve defaults to zero. The independent 4 GiB system-commit reserve, automatic
job cap of at most 24 GiB and 8 GiB startup commit headroom remain enabled. Builds use
two Cargo jobs to leave CPU headroom for other applications. The explicit profile is:

```powershell
.\Launch-Victory.ps1 -LocalRoot 'D:\BuildGTA$\victory-local' `
  -VictorySource amd7900-series-s -Console series-x -Renderer hardware `
  -Seconds 240 -HostReserveMiB 0 -FreshState `
  -PipelineWorkers 2 -QueuedSubmit -MemorySamples -CaptureAudio
```

`-QueuedSubmit:$false` selects synchronous submission for a comparison.
`-TextureNoWait` remains opt-in for fault-safe texture reads during remapping.
`-TrimIdleTextures` selects the existing shorter texture-retention policy for
comparisons; it remains off because the Series X comparison still hit the RAM
reserve. It preserves resource references and retirement checks.
Queued submission demonstrated about 30 FPS in many intro/loading intervals,
but the Series X tests also recorded 2.6-5.4 FPS loading intervals; stable 30 FPS
loading and gameplay are not established. `-DiagnosticKeys` supplies a bounded local input script and is
included in the run metadata. Closing the game ends its associated runner.

The source checkout name `amd7900-series-s` is historical; `-Console` selects
the title profile independently. Series X was selected after the upstream fork
also reported a black world with Series S. This selection is not proof that
Series X gameplay works on this machine. Explicit `-Console series-s` retains
the menu-picture workaround for comparisons.

`-MemorySamples` enables the regular memory report plus an independent one-second
sample during frame stalls. It reads atomic counters and uses nonblocking pool
snapshots. Retained categories overlap; do not add them together. `made_*` fields
are cumulative allocations, and a missing pool value means unavailable, not zero.
The ordinary expensive memory-map walk now defaults to every 60 report lines.

`-PrewarmPipelines -PipelineBookFrom <run-id> -PipelineUseFrom <run-id>` creates a
fresh cache from compatible **raw** local pipeline records. `-PrewarmLimit`
defaults to 2048 and the warmer uses two compiler workers. The seed validates the
package hash and record layout, selects only recorded uses, and rejects nonempty
destinations and reparse paths. It never transfers compiled shaders or marks
them warm across runtime versions. For the subsequent title test,
`-WarmCacheFrom <warm-run-id>` requires the identical executable, console and
renderer. Warm-up can fail; check its actual completion and failure counts.
The default warmer persists translated shader files and exercises the driver's
cache. `-PrewarmLibrary` additionally checkpoints the host pipeline library after
each recycled compiler child, using exactly one writer to avoid lost updates.
It revisits selected entries even when a previous driver-only marker exists;
existing library entries can load without creating another PSO. A failed child,
refused pipeline or failed checkpoint makes this mode return failure. Its
`library checkpoint` lines distinguish creations, loads and bytes actually saved.
A copied cache directory alone is not proof of fast host-pipeline reuse; compare
load times and the subsequent title's actual `loaded` and `made` counters.
The isolated runner sets `AMD_SHADER_DISK_CACHE_PATH` to its private writable
`output/driver-cache`. `-WarmCacheFrom` copies this folder alongside the shader
and pipeline caches after checking the executable and selected profile. The
global user driver cache remains inaccessible. On the tested Radeon, this path
reduced the six previously slow pipeline reloads to 19-244 ms each; sustained
gameplay FPS still requires a title test.
Use `-CommitMiB 6144` for bounded offline preparation. Setting
`-HostReserveMiB 0` disables only the physical floor, never the commit guard.

Read a run with:

```powershell
.\Summarize-VictoryRun.ps1 -Run <run-id> `
  -StageRoot 'D:\BuildGTA$\victory-local\isolated-run\stage'
```

The report distinguishes timers, memory guards and missing metadata. Timing
values are sampled intervals, not a whole-run average or a one-percent low.
Guarded runs sample private and resident memory for each job process every five
seconds and once before termination. Decoder/compiler children are included;
the report keeps each process's sampled maximum separate from the job peak.
`timedMemory` includes the independent one-second sampler even when a frame
stalls. `pipelineCacheEvents` retains actual library loads/new compilations;
`precompile` keeps completion, refusal and child-failure counts distinct.
Optional phase evidence is a local JSON array with `label`, `evidence`,
`startUtc` and `endUtc`; assign a phase only after inspecting its captures.
Device-removal message counts do not replace checking Windows events.

The launcher also sets a job notification up to 512 MiB below the existing hard
cap. It requests termination before allocation denial, without reserving physical
RAM. The asynchronous notification cannot guarantee catching a rapid burst.
`runtimeResultBeforeCleanup`, `cleanupFailure` and `allocationFailureAtJobLimit`
keep a later cleanup failure from hiding an earlier memory failure. A job stop
records both its notification threshold and the hard limit.

`Sample-VictoryHostMemory.ps1 -Run <active-run-id> -StageRoot <local-stage>`
records available physical RAM, system commit and paging counters every five
seconds in a local JSONL file. It observes the machine without changing limits
or processes, stops when the launcher writes finalized metadata (also on manual
close), and has its own bounded deadline. Start it after the run directory
exists. These are system totals, not allocations attributable solely to Victory.

The two `Test-*.ps1` scripts use synthetic files only. The runner's additional
tests are documented in `isolated-run/README.md`.

For a bounded compiler reproduction, add `-PrewarmIndices 51362` (an example
index, not a portable shader identity) to `-PrewarmPipelines -FreshState
-PipelineBookFrom <run-id>`, with `-Seconds 150 -CommitMiB 6144
-HostReserveMiB 3072`. Each index belongs to the exact recorded book. Inspect the
reported `made` result and exit code; generating DXIL is not proof of successful
pipeline creation. Offline crash logs remain in that run's local pipeline cache.

`Create-VictoryShortcut.ps1 -LocalRoot <workspace-local>` refreshes the workspace
shortcut to build and launch this candidate. It uses the existing local
`Victory.ico` created from the package asset; the icon and package assets are
not redistributed in this repository. The minimized launcher exits with the
session, while diagnostics remain on disk.
