# Local Windows reproduction tools

These are the source of the workstation harness. Game files, recorded pipeline
books, generated shader caches, captures and raw logs stay outside the repository.
The tools record measured output; they do not certify gameplay from draw counts.

`Launch-Victory.ps1 -LocalRoot <workspace-local>` uses the existing workspace
layout: the package is `../buildgta`, Rust is in `cargo`/`rustup`, source checkouts
are siblings of the launcher, and the isolated runner is in `isolated-run`.
Copy these scripts to that local directory, or pass its path with `-LocalRoot`.
The matching source-only candidate patches and their exact base are documented
in `../../../INTEGRATION.md` from the repository root.

Build the runner with `isolated-run/build.cmd guard`. Its source preserves the
read-only package grants, zero-capability AppContainer and bounded job. It leaves
the Windows GPU watchdog unchanged. The memory reserve monitor is checked every
500 ms; it cannot guarantee recovery from a driver hang.

For the candidate checkout, the explicit launch profile is:

```powershell
.\Launch-Victory.ps1 -LocalRoot 'D:\BuildGTA$\victory-local' `
  -VictorySource amd7900-series-s -Console series-s -Renderer hardware `
  -Seconds 240 -HostReserveMiB 3072 -FreshState -MenuPicture `
  -PipelineWorkers 2 -MemoryStats -CaptureAudio
```

`-QueuedSubmit` opts into ordered asynchronous submission. `-TextureNoWait`
opts into the fork's fault-safe texture reads during remapping; neither option
is enabled by this example. Use the recorded comparison results before changing
the default. `-DiagnosticKeys` supplies a bounded local input script and is
included in the run metadata. Closing the game ends its associated runner.

`-PrewarmPipelines -PipelineBookFrom <run-id> -PipelineUseFrom <run-id>` creates a
fresh cache from compatible **raw** local pipeline records. `-PrewarmLimit`
defaults to 2048 and the warmer uses two compiler workers. The seed validates the
package hash and record layout, selects only recorded uses, and rejects nonempty
destinations and reparse paths. It never transfers compiled shaders or marks
them warm across runtime versions. For the subsequent title test,
`-WarmCacheFrom <warm-run-id>` requires the identical executable, console and
renderer. Warm-up can fail; check its actual completion and failure counts.

Read a run with:

```powershell
.\Summarize-VictoryRun.ps1 -Run <run-id> `
  -StageRoot 'D:\BuildGTA$\victory-local\isolated-run\stage'
```

The report distinguishes timers, memory guards and missing metadata. Timing
values are sampled intervals, not a whole-run average or a one-percent low.
Optional phase evidence is a local JSON array with `label`, `evidence`,
`startUtc` and `endUtc`; assign a phase only after inspecting its captures.
Device-removal message counts do not replace checking Windows events.

The two `Test-*.ps1` scripts use synthetic files only. The runner's additional
tests are documented in `isolated-run/README.md`.
