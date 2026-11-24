# Windows D3D12 runtime integration

This repository tracks work on running the Xbox Series build of GTA VI on Windows. It combines the original Leonida compatibility runtime with the separately selectable VIctory backend, which translates console shaders and presents through native D3D12. The two backends keep their runtime state separate.
DISCORD: https://discord.gg/3qCnTarkPk
## Reported boot progress

24 November 2026

**4 of 5 stages reported working on one machine. World reached · rendering blocked.** The count covers the five stages below. PortWatch assigns its own compatibility score. Independent reproduction and controllable hardware gameplay remain open.

**Test system** · AMD Radeon RX 9060 XT with 16 GB VRAM · AMD Ryzen 7 5700X · 32 GB system RAM

| Stage | Reported state | What happened |
| --- | --- | --- |
| Boot and first-boot screens | **Working** | Accessibility, language, settings and legal screens displayed at a reported 30 FPS. |
| Intro video with sound | **Working** | The intro video played with sound. |
| Start screen, profile and saves | **Working** | The start screen, profile selection and save flow worked. |
| Loading into the world | **Working** | Loading reached the first mission’s intro in about 50 seconds. |
| World / first mission’s intro | **Reached · rendering blocked** | The picture stayed black and the host GPU failed within seconds. The cause is unresolved. |

In the latest local update, the maintainer also reports seeing the **“Rockstar Games Presents”** title card. The exact runtime commit and a recording of that sequence are pending. Visible world geometry, player movement and gameplay FPS remain unverified.

**Short intro measurement** · The hardware run recorded **30 FPS / 33.3 ms** per frame. WARP software rendering recorded **about 10 FPS / 100 ms** per frame. These measurements cover the short intro. The 30 FPS in the first row is the maintainer’s separate first-boot observation.

[Plain-text boot-progress.log](boot-progress.log) · [Machine-readable run report](tracking/runtime-progress.json) · [PortWatch review notes](docs/portwatch-submission.md) · [PortWatch tracking request #38](https://github.com/4lwayz/portwatch-vi/issues/38)

![Maintainer’s status panel with four working stages. The fifth stage, world rendering, is blocked by a black picture and a host GPU failure.](docs/images/boot-progress.png)


## Implementation and open work

The [integration checkpoint](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) adds consistent raw bindless shader resource views (SRVs), typed UINT16 unordered access views (UAVs), exact 3:1 compositor downscaling and coalescing of concurrent shader-cache fills. D3D12 diagnostics record the submission caller, fence phase and Present result.

| Investigation | State | Result or outstanding question |
| --- | --- | --- |
| Trace single-list device removal | **Completed** | The trace narrowed device removal to a single-list submission. The defect responsible has yet to be identified. |
| Distinguish failure paths and retain the fence phase | **Completed** | Caller, fence and Present instrumentation distinguishes submission and presentation failures and records the fence phase. Fault attribution remains open. |
| Serial build, tests and debug reproduction | **In progress** | The local serial build passed. The workspace suite recorded **303 passed, 5 ignored**. The GPU crate recorded **62 passed, 2 ignored**. Original-file protection checks passed. The latest debug run could not enable the missing D3D12 debug layer and exited with code **0 after 28.42 seconds**, before world entry. |
| Fix the remaining defect and verify controllable gameplay on hardware | **Pending** | Reproduce the black screen on hardware, identify the cause, verify the fix, then record a visible world and response to player input. |

In the [Windows CI run for this implementation](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225342), the native release and diagnostics builds passed and the native runtime test job failed. The [source-boundary check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225195) passed for the same commit. The serial test counts above come from the maintainer’s local run.

The next hardware run should record the exact build, GPU driver, title-card time, first black frame, last successful guest submission, host Present result and response to input. See the [experiment workflow](docs/EXPERIMENTS.md).

## Build and check

Clone this repository with its submodules:

```powershell
git clone --recursive https://github.com/tudorek12345/VictoryIsInOurName.hep.git
cd VictoryIsInOurName.hep
.\run_runtime.cmd --help
```

To reproduce the source-only D3D12 build and serial diagnostics checks on Windows with the pinned Rust toolchain:

```powershell
cd runtimes/victory
$env:VICTORY_WARP = '1'
$env:VICTORY_D3D12_WARP = '1'
cargo build --locked --profile diag -p victory --features diagnostics
cargo test --locked --workspace --features diagnostics -- --test-threads=1
```

Keep local game inputs, saves, caches and generated artifacts outside Git. The [boot runbook](docs/boot.md) documents the original runtime. The [backend launcher](runtime_backend.py) and [Windows CI definition](.github/workflows/victory-runtime.yml) document backend selection and validation.

For development discussion, [join the project Discord](https://discord.gg/ufXqPcVdVj).

## Code and attribution

| Location | Purpose |
| --- | --- |
| [runtime/](runtime/) | Original Leonida compatibility runtime and Vulkan renderer |
| [runtimes/victory/](runtimes/victory/) | VIctory native D3D12 backend, shader translation and graphics tests |
| [Integration notes](INTEGRATION.md) | Local integration work and upstream provenance |
| [Technical documentation](docs/README.md) | Runtime, formats, graphics and validation |
| [Contribution guide](CONTRIBUTING.md) | Reproductions, source boundaries and coordination |

Heperkoo maintains this integration. Credit for the original Leonida runtime belongs to ItsNotRexed and the Leonida contributors. Credit for VIctory belongs to Marvisak and the VIctory contributors. See the [upstream pin and change record](runtimes/victory/SOURCE.json), [upstream credits](README.upstream.md#credits), [project license](LICENSE) and [VIctory license](runtimes/victory/LICENSE).
