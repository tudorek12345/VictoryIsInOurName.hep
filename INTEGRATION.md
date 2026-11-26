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
