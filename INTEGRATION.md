# Runtime integration notes

This repository is the requested tracking source for the Windows D3D12 runtime integration. See the [latest maintainer observations](README.md#reported-boot-progress) and the [PortWatch submission](docs/portwatch-submission.md) for the status and scope of this single effort.

## Runtime history

The original Leonida project by ItsNotRexed and its contributors runs the existing x86-64 code through reimplemented console services and translates console GPU programs for Vulkan. [Upstream credits](README.upstream.md#credits) document the authors and dependencies.

The separate VIctory backend by Marvisak and its contributors uses native D3D12. The integration adds a launcher for choosing the backend, isolates runtime state and carries changes to shader resource views, the compositor and device-loss diagnostics. The [upstream source record](runtimes/victory/SOURCE.json) identifies the revision, license and local changes. The [implementation commit](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) records the shader, cache and diagnostic work.

## Development handoff

Start with the [sanitized runtime report](tracking/runtime-progress.json) and [reproduction checklist](docs/EXPERIMENTS.md). Record the backend, exact build, GPU and driver, observed output and next unresolved failure. Keep runtime measurements tied to the run that produced them. Use the [contribution guide](CONTRIBUTING.md) and [repository instructions](AGENTS.md) before changing shared code.

## Series S presentation candidate

The [Series S patch](runtimes/patches/victory-7900xtx-series-s-present.patch) applies to the [7900 XTX fork at `e2a28ec7`](https://github.com/avatarmanz/VIctory-7900XTX/tree/e2a28ec70632f5112be085abfa7d0a557b25e8d8). It reads the full display-plane record, uses completed draw evidence to choose a single 4K menu target, and avoids redundant copy-source transitions. `git apply --check` passed against the matching source snapshot. The selector regression and the regular and optimized diagnostics build checks passed.

The isolated AMD test built the diagnostics profile, selected `--console series-s`, and set `VICTORY_SERIES_S_MENU_PICTURE=1`, `VICTORY_LATE_WAIT=0`, `VICTORY_THIN=0` and `VICTORY_ASYNC_SUBMIT=0`. Those settings keep the selector on the synchronous submission path. The original package and raw runtime artifacts stay local. The test demonstrated the menus and intro. World rendering and input remain open.

## World-entry candidate

Apply [the follow-up patch](runtimes/patches/victory-7900xtx-world-entry.patch)
after the Series S presentation patch above. Together they reproduce local
candidate `629334cd32ca6a1f21dbfcb3fc4861a66d4e3891` from the pinned `e2a28ec7`
source. Patch application was checked against the exact intermediate source.

The follow-up snapshots display planes with owned texture references and consumes
draw evidence on the ordered submission worker. It allows queued rendering while
preserving the Series S menu selection. Empty, fully retired GPU pool blocks are
trimmed under physical-memory pressure; live resources and their retirement
quarantine remain intact. The requested Radeon adapter is explicitly selected
and recorded, including hardware/software status.

Integrated source changes retain their upstream provenance:

- 7900 XTX fork: [pool alignment](https://github.com/avatarmanz/VIctory-7900XTX/commit/c278f0d5),
  [deferred descriptor exposure](https://github.com/avatarmanz/VIctory-7900XTX/commit/4cd2d133),
  [exposure deduplication](https://github.com/avatarmanz/VIctory-7900XTX/commit/91018a5d),
  and [diagnostic follow-up](https://github.com/avatarmanz/VIctory-7900XTX/commit/85d56416).
- fxceless `19a45d19`: track GPU-written alias sources separately from CPU upload
  tracking so an earlier upload does not suppress a later lighting-atlas copy.
- [VIctory `7ac1f54d`](https://github.com/Marvisak/VIctory/commit/7ac1f54d83179d4d7656b39dee0a06917d139e2e):
  initialize the non-overlapping POPS wave ID to one. The adapted synthetic test
  checks inactive pixel lanes in both wave32 and wave64 modes.

The optimized diagnostics GPU crate passed 381 tests with 34 ignored. The shader
crate passed 278 tests with four ignored after excluding one separately reproduced
driver failure. That is not a fully passing workspace suite: the structured-buffer
count/indexed-read test aborts in `amdxc64.dll` on driver `32.0.32029.2010`.
Its expected output passes WARP and DXIL validation. An equivalent, hand-written
shader compiled by Microsoft DXC also triggers the same AMD exception. An integer
load experiment did not help and was removed; the failing test remains enabled
in source. The exclusion applies only to the recorded follow-up test command.

The [Windows harness](runtimes/tools/windows/README.md) records exact executable
hashes, requested inputs, adapter evidence and stop reasons. Its pipeline seed
and report-parser tests each passed ten synthetic checks. These changes are
AI-assisted. Original package data and generated shader programs are not part of
the patch. Gameplay validation and sustained frame rate remain separate runtime
requirements; see the measured report before treating this as a playable build.

## Shader compiler follow-up (25 November 2026, PST)

Apply [the shader compacting patch](runtimes/patches/victory-7900xtx-shader-compact.patch)
after the world-entry patch. It recreates local candidate `3747dfc` from `629334cd`.
The adaptation uses only the missing parts of Marvisak/VIctory
[850b66ff](https://github.com/Marvisak/VIctory/commit/850b66ffd7e06a9c21bc20ccd9168a627f653f3d)
(fixed-address and uniform-join handle sharing) and
[286a00e9](https://github.com/Marvisak/VIctory/commit/286a00e9b69851d1dc0d68d313a01822a251084f)
(safe empty forwarder folding). Existing dead-code optimization, recursive joins,
raw-view bounds and nonuniform waterfall behavior are retained. Synthetic tests
cover the new dominance/phi-edge cases; 36 focused CPU tests passed with two
existing ignores. The optimized diagnostics executable built successfully.

Two recorded compute pipelines showed 40.4?40.6% fewer heap handles and about
2.6% smaller DXIL. Both still ended with access violations below 0.6 GiB job
commit. New offline-child crash reports identify `amdxc64.dll+0x861b9f`, the
same location as the separately reproduced synthetic compiler failure on driver
`32.0.32029.2010`. This is a measured code-size improvement, not a resolved
compiler crash or verified gameplay fix. The raw shaders and crash reports
remain local.

The launcher now accepts `-PrewarmIndices` with `-PrewarmPipelines` to compile
specific recorded indices under the existing external timeout and memory guard.
This bypasses stale warm-failure markers and records the exact indices in the
run metadata. Offline children retain their own module/RVA crash log. The
warmer currently persists translated shader caches; reuse of an AMD disk cache
across isolated profiles has not been established, and a persistent Victory
pipeline-library blob is not produced by this command.

## Compiler worker budget

Apply [the worker-budget patch](runtimes/patches/victory-7900xtx-worker-budget.patch)
after the shader compacting patch. Slow speculative compilation previously used
the CPU-derived default even when two general workers were explicitly selected.
It now uses that configured count, allowing one slow prewarm alongside requested
work. Dedicated screen workers and the explicit unlimited override are preserved.
Startup diagnostics expose both counts and the quota. Seven focused queue tests
passed. This corrects scheduling; lower peak memory in the title is not yet
measured. The system physical/commit reserves remain in force for OBS.

## Radeon buffer-query compiler workaround

Apply [the buffer-query patch](runtimes/patches/victory-7900xtx-buffer-query.patch)
after the worker-budget patch. This reproduces candidate `33cbd2f`. The complete
patch sequence passed application checks against its pinned source.

A buffer size query now uses a separate handle whose index is read from the
same active lane. This preserves every lane's descriptor index while avoiding
the AMD compiler's failing query/load handle combination. Raw twins, null-slot
bounds and descriptor properties remain unchanged; pixel helpers retain the
original bounded index. Image queries and all data loads/stores keep their
existing paths. No new GPU allocation, size approximation or skipped shader is
introduced. The [authored reproducer](runtimes/tools/windows/shader-compiler-probe/RESULTS.md)
records the failure-to-success controls.

All ten focused size tests pass, including the previously crashing indexed
structured-buffer count, a raw-UAV query/load/store and a raw-twin count whose
original view has different contents. The complete optimized shader suite now
passes **285 tests, zero failures, four existing ignores, no exclusions**.
Test statistics observe the actual optimized module; the original strict
waterfall/descriptor assertions were preserved, together with their GPU output
checks.

The six previously failing recorded world pipelines all created successfully
with the query fix on RX 9060 XT / driver 32.0.32029.2010. The first took about
7.17 seconds; the remaining five completed in one bounded process with a peak
of 625,065,984 bytes (0.58 GiB). Tests used 6 GiB caps and the existing physical
and commit reserves. This resolves the demonstrated compiler exception;
rendered gameplay remains a separate end-to-end validation requirement.

## Upstream review and timed memory diagnostics (25 November 2026, PST)

Apply [the memory-sampling patch](runtimes/patches/victory-7900xtx-memory-sampling.patch)
after the buffer-query patch. It reproduces candidate `0001d4b` from `33cbd2f`.
Patch application was checked against the preceding sequence.

Reviewed 7900XTX head [9c23e8dd](https://github.com/avatarmanz/VIctory-7900XTX/commit/9c23e8dd40cac6fb4a2aa8c804587e7c2e2a5853)
and fxceless head [46bf5351](https://github.com/fxceless/victory-fork/commit/46bf5351707b1697c04e5d871c30973ebaa3e973).
The local `victory-fork-main` directory is an archive without Git history; its
raw-address memory implementation matches the fetched fxceless source.

Selected adaptations:

- [c83e54c8](https://github.com/avatarmanz/VIctory-7900XTX/commit/c83e54c808aaf3fe173cd56bc4463324e75022d2):
  index watched ranges by start and prefix maximum end for binary-search
  containment checks. The existing serial kernel-query path is retained.
  Tests cover overlapping/nested ranges, gaps, replacement and address boundaries.
- [fb28d49e](https://github.com/avatarmanz/VIctory-7900XTX/commit/fb28d49e959359cb20992e5c5533a647cb408054):
  configurable full memory-map walks, defaulting to every 60 report lines instead
  of six. These queries can delay write-watch calls. Experimental query scheduling
  remains unchanged.
- An opt-in independent memory sampler observes allocations during frame stalls.
  It uses atomic counters and nonblocking pool snapshots without changing resource
  lifetimes. Five focused CPU tests passed, with no failures or ignores.

The fxceless [zero-length constant-buffer fix](https://github.com/fxceless/victory-fork/commit/619b2dc5c4cb37fa32abe4f64ed6e78145c8fa01)
is already present semantically in `constant_bytes`; no duplicate patch was applied.
Its new texture worker remains default-off upstream and did not improve the
author's measured frame rate. The new 7900XTX constant-heap remapping cluster is
experimental and default-off, with two immediate follow-up fixes; it is not
enabled or imported in this candidate.

The fxceless diagnostics index reports a black Series S world in run 304 while
Series X renders on the author's machine. That is upstream evidence, not a local
reproduction. The user selected Series X for the next test. The launcher and
asset-icon shortcut use that profile; the checkout retains its historical name.
Radeon, two pipeline workers, the 3 GiB physical reserve, the 4 GiB commit reserve
and the Windows GPU watchdog remain unchanged.

## Offline library checkpoint and physical reserve (25 November, later pass)

Apply [the offline-library patch](runtimes/patches/victory-7900xtx-offline-library.patch)
after the memory-sampling patch. It reproduces `dc9fd41` from `0001d4b`.
Application against the preceding patch chain matched all three changed source
files byte for byte. The diagnostics build, two warmer tests, five library tests
and sixteen synthetic diagnostic-summary checks passed.

`-PrewarmLibrary` opts into one compiler child at a time. Each child saves the
host library before exiting, without replacing the parent's open early/slow
lists. Failed checkpoints and incomplete batches are reported as failures.
Legacy driver-only markers cannot suppress the persistent pass. GPU resource
lifetimes, shader semantics and the title's regular save path are unchanged.

The first six-PSO test created six and saved a 1,748-byte library. The next process
loaded all six and created none. However, reloading the expensive compute PSOs
still took roughly 5-6 seconds each on this Radeon/driver. Cache hits therefore
do not establish a frame-rate improvement. Full preparation and title testing
must be reported separately from these compiler probes.

At the user's explicit request, `HostReserveMiB` now defaults to zero in the
launcher and icon shortcut. It disables only the physical-RAM floor. The guard
runner, 4 GiB system-commit reserve, startup commit-headroom check, automatic job
cap of at most 24 GiB and Windows GPU watchdog remain active. Synthetic runner
checks confirmed that the commit guard still terminates its probe with no
physical reserve, and the hardware probe metadata records 0/4096 MiB reserves.

The 7900XTX and fxceless heads were checked again and remain `9c23e8dd` and
`46bf5351`. XCL advanced to `b49be183`: `ec80c071` reuses whole cached compute
PSOs before its split dispatch path, `c836ecd9` expands atomic-heavy compaction,
and `60447294` shares scratch across deferred split lists. These use XCL-specific
translation and command-list structures. They have been inspected, not merged
into Victory or claimed as local fixes. A standalone authored compute probe
also tested `GetCachedBlob` (954 bytes); a tiny-shader test cannot establish that
this alternative fixes multi-second world PSO loads.
