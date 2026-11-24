# Windows D3D12 runtime integration

This repository tracks work on running the Xbox Series build of GTA VI on Windows. It combines the original Leonida compatibility runtime with the separately selectable VIctory backend, which translates console shaders and presents through native D3D12. The two backends keep their runtime state separate.

## Latest run on 24 November 2026

| Stage | Maintainer observation |
| --- | --- |
| Intro title | The latest local run displayed **“Rockstar Games Presents.”** |
| Entering the world | The maintainer reports reaching the world transition with a **black screen**. No visible world or player-controlled movement has been demonstrated. |

The [dated run report](tracking/runtime-progress.json) records these observations. The exact tested commit, a recording of this sequence and an independent reproduction are pending. It gives no frame-rate measurement for this run.

For PortWatch, the requested tracking source is this repository, **`tudorek12345/VictoryIsInOurName.hep`**. The [tracking request](docs/portwatch-submission.md) links the previous registration for the same implementation and requests a single entry.

## Implementation and open work

The [integration checkpoint](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) adds consistent raw shader buffer views, typed UINT16 buffer access, a 3:1 compositor fast path and coalescing of concurrent shader-cache fills. Submission, fence and presentation diagnostics record where device removal is detected.

In this repository’s [Windows CI run for that revision](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225342), the native release and diagnostics builds passed. The native Windows test job failed at the runtime tests. The [source-boundary check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225195) passed for the same commit. These jobs exercise source and synthetic inputs.

The next hardware test is to reproduce the black screen, identify the last successful guest submission and host presentation, and record whether subsequent frames respond to input. Record the exact runtime commit, GPU driver, time of the title card and the first black frame so another tester can compare their run. See the [experiment workflow](docs/FORK_EXPERIMENTS.md).

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
| [Fork notes](FORK.md) | Local integration work and upstream provenance |
| [Technical documentation](docs/README.md) | Runtime, formats, graphics and validation |
| [Contribution guide](CONTRIBUTING.md) | Reproductions, source boundaries and coordination |

Heperkoo maintains this integration. Credit for the original Leonida runtime belongs to ItsNotRexed and the Leonida contributors. Credit for VIctory belongs to Marvisak and the VIctory contributors. See the [upstream pin and change record](runtimes/victory/SOURCE.json), [upstream credits](README.upstream.md#credits), [project license](LICENSE) and [VIctory license](runtimes/victory/LICENSE).
