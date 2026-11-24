# Leonida fork: stable world-entry and first world-frame handoff

## Current handoff — 24 November 2026, 03:00 EST (UTC−05:00)

**Continue the integrated VIctory backend under `runtimes/victory/`, not an unrelated pristine checkout.** Source is synchronized to [Leonida](https://github.com/tudorek12345/Leonida) and its [same-source mirror](https://github.com/tudorek12345/VictoryIsInOurName.hep); these are one effort. The tested working-tree changes were based on `5dd9c2c21093e17d16ec577c76a9e721e3a08c59`. Read the current root README and `tracking/runtime-progress.json` for source files, skills, commands, observations and task states.

### Verified and not verified

- Implemented: raw bindless scalar/vector SRV agreement, fixed typed UINT16 compute UAV specialization, exact-ratio compositor fast path, keyed cache-fill coalescing and expanded host submission/fence/Present diagnostics.
- Optimized diagnostics build passes. Serial diagnostics workspace: **303 passed / 0 failed / 5 ignored**. Latest focused GPU crate: **62 passed / 0 failed / 2 ignored**. Static review found no actionable introduced defect; that does not establish compatibility.
- RX 9060 XT 16 GB / Ryzen 7 5700X / 32 GB DDR4: short intro **30 FPS / 33.3 ms**, not gameplay. WARP intro approximately **10 FPS / 100 ms**, even without capture; it is software throughput, not Radeon performance.
- Last completed world-transition repro: WARP **0x887A0005 after 184.84 s**, peak job commit **11.02 GiB**, below the 16 GiB cap. A 31-list batch finished before a one-list failure. The exact caller/command remains unestablished in that older trace. Do not attribute it to the last successful list.
- Latest debug-requested repro: **28.42 s, exit 0**, lifecycle shutdown before world entry. The D3D12 debug layer was unavailable. No world-entry, fault-attribution or debug-validation success can be claimed from that attempt.
- Originals/saves remain local. Isolation verified restoration on 151 package paths and the unchanged executable hash.

### Latest tasks

- [x] Trace the single-list device removal and inspect source/run evidence.
- [x] Distinguish failure paths and retain the exact fence phase in diagnostics (implemented instrumentation, not a proven crash cause).
- [ ] **In progress:** serial build/test, bounded debug reproduction and protection checks. Build/tests/protection passed; effective debug/world reproduction remains open.
- [ ] Fix a demonstrated remaining defect and verify controllable hardware gameplay.

### Exact next experiment

1. Check availability of the D3D12 debug layer. Do not install Windows features or change TDR/driver settings without authorization; requesting the layer does not mean it was enabled.
2. Reproduce a bounded isolated Series S world-entry attempt with the new `Host::execute` caller/fence reporting. Compare guest submission, compositor/capture and swap-chain Present paths; diagnostics timing changes submission behavior.
3. Preserve a local trace of the first failed phase and its immediately preceding completed fences. Empty DRED history does not identify a shader. Earlier raw/structured SRV mismatches remain investigation leads, not an established latest cause.
4. Fix the smallest demonstrated defect, add a hand-written synthetic regression, rerun GPU tests and title runs **serially**, then attempt hardware world rendering and input/audio verification. Measure gameplay percentiles only after controllable gameplay is demonstrated.

The raw traces, captures, shaders, BCPack tables and workstation launcher remain outside Git. Local ignored `handoff.md` / `currenstatus.md` record the exact machine paths. Public evidence is summarized, not extracted game content. Skills used: `game-reverse-engineering`, `reverse-engineer-anything`, `review-agent`, `tinyfish-web`, `tinyfish-authenticated` (workflow instructions, not runtime dependencies).

---

## Historical handoff below — original Leonida/Vulkan investigation

The following Nov 23 report and `gta6rt` commands describe the older path. Do not mistake them for current VIctory reproduction commands or current measured hardware.

## Latest reported result — 23 November 2026

The maintainer reports the following on **one Windows 11 / AMD RX 9070 XT machine**. These are supplied observations, not an independently reproduced result or a compatibility claim for other hardware. The exact runtime revision, local changes, package/build identifier and GPU driver must be captured before this becomes a reproducible baseline.

| Stage | Maintainer-reported result |
| --- | --- |
| Boot and first-boot accessibility, language, settings and legal screens | Working at **30 fps** |
| Intro video with sound | Working |
| Start screen, profile and save flow | Working |
| Loading into the world | Working, **about 50 seconds** |
| World / first-mission intro | Reached, but **the picture is black and the host GPU fails within seconds** |

The 30 fps figure applies to the first-boot screens. Stable rendered gameplay has not been demonstrated by this report, and the cause of the GPU failure remains unknown. The next priority is a correctly rendered first world frame and repeatable world entry without that failure.

Published summary: https://leonida-heperkoo.meshedgoby9.chatgpt.site/progress-update.md

## Goal

Work in my existing fork: https://github.com/tudorek12345/Leonida. Upstream is https://github.com/ItsNotRexed/Leonida. Continue the existing implementation and preserve ongoing work. Starting from the maintainer-reported boot, menu, video and loading progress above, I want the shortest technically sound route to a correctly rendered first world frame, stable world entry, and then repeatable interactive gameplay through Leonida on Windows.

Implement and verify the next useful changes end to end. The fork is an experimental workspace and a handoff point for other developers. My background includes MWCMP, the Batman Telltale port and CoD2 experiments; use that practical RE approach: inspect, measure, implement, reproduce, document. Those projects explain the workflow; GTA VI compatibility claims need this project's own run evidence.

“Native” here means executing the game's existing x86-64 instructions on the PC CPU with the required console services reimplemented and console graphics translated through Leonida. It does not mean we have Rockstar's source code or an official Windows port.

## Establish the real baseline first

The original inspected fork snapshot was `561b65a8`; it is historical and must not be presented as the revision that produced the new reported result. Record the actual tested runtime branch, full SHA, remotes, submodule pins and uncommitted changes before editing. A website-only commit does not identify the tested game runtime. Do not reset or overwrite another developer's work. Use an isolated worktree or branch when necessary.

Read the applicable `AGENTS.md`, `CONTRIBUTING.md`, runtime guide, build scripts, `docs/boot.md`, `docs/runtime_imports.md` and `docs/d3d12_vulkan.md`. Compare the fork with current upstream. Integrate relevant fixes with review and focused verification; avoid duplicating work that already landed.

A historical reference is upstream's [retail boot-chain report](https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md), added on 23 November 2026. It describes a separate Windows 11 / RTX 4090 experiment using `1cc6e3c12`, several locally merged PRs and additional local stand-ins. It reports reaching device creation, queues, fences, hundreds of command lists and the first descriptor heap, where a CPU descriptor-handle assertion stopped execution. It explicitly reports no draw or present in that earlier experiment.

Keep that report as historical context and check which fixes have since landed. It is not the current maintainer-reported blocker and must not erase the newer menu, video and world-loading progress. Older README statements about an unavailable executable are also insufficient to describe the reported run. Reproduce the current failure before selecting a fix; revisit an earlier loader or descriptor stop only if the current trace reaches it.

## Inputs and build

Inspect the local environment before prescribing installs. Use a Windows x64 test machine, the repository's supported C++/Windows SDK toolchain, Python, .NET, Vulkan tools and AMDGPU-capable LLVM as required by the selected stages. Record the actual versions and GPU driver. Confirm requirements against the checked-out build scripts.

Use the user's locally readable game package and separately available compatible executable. Record package version, executable SHA-256 and the configured paths. Do not assume an executable exists because an online report mentions one. Keep package inputs read-only, runtime writes in a separate overlay, and generated assets and raw game traces outside version control. Use an offline test session for title execution because the current loader can bind networking imports to the host.

For the first runtime pass, prefer the existing `check,shaders,runtime` stages when supported. Avoid a full optional asset export unless a measured runtime dependency requires it. Reuse valid caches and translated outputs; invalidate them only when the relevant source, toolchain or settings change.

## Reproduce before changing behavior

First build the runtime and run the existing focused loader and graphics tests needed to establish a usable baseline. Then exercise the actual executable in this order:

1. `gta6rt --dry-run`: mapping, relocations and import binding.
2. `gta6rt --init`: module initialization and TLS callbacks.
3. `gta6rt --run`: the executable entry point and the next observed failure.

Use the existing `--game-dir`, `--overlay`, `--trace` and `--trace-d3d12` options, confirming exact syntax with the current runtime help. Select the Vulkan backend with `LEONIDA_D3D12=vulkan`. Give every run a new trace filename because startup tracing refuses an existing file. Preserve the exit code and stdout/stderr separately from the launcher or shell's status.

Process startup and graphics traces with `tools/boot_trace.py`. Capture the first meaningful failure, the last completed stage, unresolved call or interface, exception information and any earlier diagnostic that explains it. Distinguish the cause from a teardown crash. Use the existing unimplemented-call controls to isolate the first missing import; do not silently turn every missing function into success.

If the executable, package or Windows/GPU runner is unavailable, state exactly which prerequisite is missing. Continue with meaningful source-built fixtures and runtime fixes that can be tested, but label retail execution as untested.

## Implementation priorities

Follow the measured execution path. Prioritize the reported transition into the first mission and give the remaining areas attention where the current trace supports them:

- **World-entry failure:** reproduce the menu/video/loading sequence and identify the transition to the black image. Capture the last successful graphics submission and presentation, queue/fence state, relevant runtime or Vulkan errors, and any available Windows graphics-failure diagnostics. Distinguish an application rendering failure from a confirmed host driver/GPU failure using the evidence; do not assume a device-loss code, memory cause or hardware fault from the report alone.
- **Memory and TLS:** XMem allocation attributes, page sizes, reserve/commit behavior, placeholder splitting, physical-page mapping and aliasing, and the executable's TLS assumptions. Keep resource lifetime, address stability and failure semantics explicit.
- **Xbox ABI:** verify observed COM slots and argument/return conventions rather than assuming desktop D3D12's layout. Implement the actual called surface and log unknown interfaces clearly.
- **Descriptor addressing:** investigate the expected CPU/GPU heap addresses, increments, record representation and shader-visible descriptor contract when the current trace points there. The old handle assertion is historical context; if it recurs, model the expected relationship rather than merely removing the check.
- **CPU/GPU memory visibility:** connect placed or reserved resources to the memory backing the game writes. The retail report's slot-133 stand-in created a separate committed buffer; advancing startup with that substitute does not establish correct GPU data. Validate aliasing, uploads, synchronization and visible contents.
- **Submission and presentation:** proceed through root signatures, pipeline creation, command recording, execution, fences and the actual presentation path. Match the existing translated-shader contract. Address ray tracing or other subsystems when they block this path.

Use small, reversible experiments with explicit switches when necessary. Keep diagnostics separate from compatibility fixes. Skipping an assertion, fabricating a successful return or drawing a substitute image is not a completed implementation. A game-generated incorrect frame is useful evidence, but must be reported as incorrect.

## Verification and collaboration

Parallelize independent investigations with clear ownership: loader/memory, graphics/ABI, and reproduction/evidence. Agree on interface changes before different agents edit shared runtime files. Reuse upstream measurements and cite their exact commits; do not credit inherited Leonida work as our original contribution.

Add focused regression coverage where a failure establishes a meaningful contract: memory aliasing, descriptor translation, calling conventions, or the particular submission sequence. Prefer source-built minimal fixtures. Run the relevant tests and one real reproduction after each coherent fix. Broaden testing when changes affect shared behavior; avoid spending the session on unrelated cleanup.

Track milestones separately: build succeeds; synthetic fixtures pass; retail image maps; retail initialization completes; entry point advances; real graphics submission occurs; a real frame is presented; input reaches the running game. Each needs its own evidence. A synthetic draw, asset viewer, shader-validation total or clean exit cannot substitute for a later milestone.

For this pass, also separate reported setup/menu rendering and video playback from a correctly rendered world frame, stable first-mission entry, and a repeatable playable session. Label each result as maintainer-reported, locally reproduced, or independently reproduced. Preserve the single-machine scope until additional hardware is actually tested.

Leave a concise handoff with full commit IDs, changes and rationale, commands actually run, environment, verified results, remaining assumptions, first unresolved failure and the next concrete experiment. Link sanitized summaries to local evidence locations without committing game content. Keep public website status and announcements aligned with these results.

Start with the current checkout and carry the next reproducible blocker as far as the available inputs allow. The objective is measurable progress toward the real game running, with enough evidence for the next developer to continue immediately.

## Primary references

- Fork: https://github.com/tudorek12345/Leonida
- Upstream: https://github.com/ItsNotRexed/Leonida
- Latest maintainer report: https://leonida-heperkoo.meshedgoby9.chatgpt.site/progress-update.md
- Historical upstream retail run: https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md
- Runtime imports: https://github.com/ItsNotRexed/Leonida/blob/main/docs/runtime_imports.md
- Boot runbook: https://github.com/ItsNotRexed/Leonida/blob/main/docs/boot.md
- Graphics contract: https://github.com/ItsNotRexed/Leonida/blob/main/docs/d3d12_vulkan.md
