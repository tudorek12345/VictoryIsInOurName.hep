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
submission, two pipeline workers and a 3 GiB physical-memory reserve. Builds use
two Cargo jobs to leave CPU headroom for other applications. The explicit profile is:

```powershell
.\Launch-Victory.ps1 -LocalRoot 'D:\BuildGTA$\victory-local' `
  -VictorySource amd7900-series-s -Console series-x -Renderer hardware `
  -Seconds 240 -HostReserveMiB 3072 -FreshState `
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
The current warmer persists translated shader files and exercises the driver's
cache. It does not serialize a shared Victory pipeline library from its compiler
children. A copied cache directory alone is not proof of host-pipeline reuse;
compare the subsequent title's actual `loaded` and `made` counters. Keep the
physical/commit reserves in force during warm-up; a 6 GiB job cap and two processes
are used for the local precompile comparison while OBS remains open.

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
