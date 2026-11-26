
streaming now at https://rumble.com/v7ixhj8-vi-victoryisinourname.hep-repo.html?mref=4r2t6m&mc=bzeiw
<img width="2366" height="1312" alt="image" src="https://github.com/user-attachments/assets/efc9fc86-3982-4671-8007-e16867529d15" />

<img width="2363" height="1281" alt="image" src="https://github.com/user-attachments/assets/23f12951-f439-49a1-93be-fda45e436559" />

<img width="1562" height="842" alt="image lucia where we should go" src="https://github.com/user-attachments/assets/40907987-9d7e-4cba-afde-b8ab5f5a12f6" /> Latest Progress check. 11/25/2026 7AM EST, LUCIA, SHADERS INTEGRATED, Not playable but reaching gameplay treshold stabilization.
# Windows D3D12 runtime integration

> **FIRST RUMBLE STREAM · THURSDAY, 26 NOV 2026 · 04:00 CET** (Wednesday, 25 Nov · 10:00 PM EST)  
> [Live countdown and stream banner](https://tudorek12345.github.io/victory-progress-watch/) · [Watch on Rumble — @hepdev](https://rumble.com/user/hepdev)

This repository tracks work on running the Xbox Series build of GTA VI on Windows. It combines the original Leonida compatibility runtime with the separately selectable VIctory backend, which translates console shaders and presents through native D3D12. The two backends keep their runtime state separate.
**Tracking request:** [PortWatch issue #38](https://github.com/4lwayz/portwatch-vi/issues/38). This repository, `tudorek12345/VictoryIsInOurName.hep`, is the sole proposed reporting source for one integration effort. No separate entry is requested for the earlier Leonida repository. The previous request #17 was closed by its author, not rejected by PortWatch.

**Evidence status:** Maintainer-reported; no independent reproduction, editorial acceptance, or PortWatch score is claimed. See the [review packet](docs/portwatch-submission.md) for source attribution, the known takedown context, implementation evidence and limitations.

## Reported boot progress

24 November 2026

**Boot and menu reported working; attempted world transition ends in a black screen and GPU failure.** The historical report counted four of five local test stages, including the loading attempt. That count is not a compatibility percentage or confirmation that the game world rendered. The PortWatch rubric requires rendered world output and player control for its later milestones.

**Test system** · AMD Radeon RX 9060 XT with 16 GB VRAM · AMD Ryzen 7 5700X · 32 GB system RAM

| Stage | Reported state | What happened |
| --- | --- | --- |
| Boot and first-boot screens | **Working** | Accessibility, language, settings and legal screens displayed at a reported 30 FPS. |
| Intro video with sound | **Working** | The intro video played with sound. |
| Start screen, profile and saves | **Working** | The start screen, profile selection and save flow worked. |
| Loading transition | **Reported** | The maintainer reports reaching the first mission’s intro after about 50 seconds; world entry and rendering are not verified. |
| World rendering and player control | **Verified** | In progress

In the latest local update, the maintainer also reports seeing the **“Rockstar Games Presents”** title card. The exact runtime commit and a recording of that sequence are pending. Visible world geometry, player movement and gameplay FPS remain unverified.

**Short intro measurement** · The hardware run recorded **30 FPS / 33.3 ms** per frame. WARP software rendering recorded **about 10 FPS / 100 ms** per frame. These measurements cover the short intro. The 30 FPS in the first row is the maintainer’s separate first-boot observation.

[Plain-text boot-progress.log](boot-progress.log) · [Machine-readable run report](tracking/runtime-progress.json) · [PortWatch review notes](docs/portwatch-submission.md) · [PortWatch tracking request #38](https://github.com/4lwayz/portwatch-vi/issues/38)

![Historical maintainer-authored status panel; not a game capture or independent proof.](docs/images/boot-progress.png)

The panel and log summarize the same historical report, not additional reproductions.


## Implementation and open work

### 26 November candidate comparison

The 7900 XTX fork held 30 FPS through the original intro and early loading on the RX 9060 XT. Its Series X runs reached world loading and exhausted a 16 GiB job limit. The Series S software test stayed under 6 GiB for four minutes with black captures. Warming 23 previously used pipelines succeeded, and a measured loading interval still spent 371 ms preparing textures in a 385 ms frame. Controllable gameplay remains unverified. [Candidate source](https://github.com/avatarmanz/VIctory-7900XTX/tree/e2a28ec70632f5112be085abfa7d0a557b25e8d8)

A subsequent Series X trial allowed up to 24 GiB of job commit. It stopped at 15.66 GiB when available physical RAM fell below the 3 GiB guard. The runtime restored the package access rules after the stop.

The Series S presentation patch selected the submitted 4K plane and displayed the account picker, navigation settings and intro at about 30 FPS on Radeon. It captured non-silent stereo audio. The world transition fell to 0.4 FPS and the physical memory guard stopped the test at 13.41 GiB of job commit. [Series S patch and scope](INTEGRATION.md#series-s-presentation-candidate)

The integration now selects the physical AMD adapter, records resource operations in isolated GPU list traces, and fixes integer render-target blending, shader liveness through successive joins, and DirectStorage page-read ordering. The serial source suite passed 307 tests with five ignored. [Validation and run summary](tracking/runtime-progress.json)

The [integration checkpoint](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) adds consistent raw bindless shader resource views (SRVs), typed UINT16 unordered access views (UAVs), exact 3:1 compositor downscaling and coalescing of concurrent shader-cache fills. D3D12 diagnostics record the submission caller, fence phase and Present result.

| Investigation | State | Result or outstanding question |
| --- | --- | --- |
| Trace single-list device removal | **Completed** | The trace narrowed device removal to a single-list submission. The defect responsible has yet to be identified. |
| Distinguish failure paths and retain the fence phase | **Completed** | Caller, fence and Present instrumentation distinguishes submission and presentation failures and records the fence phase. Fault attribution remains open. |
| Serial build, tests and debug reproduction | **In progress** | The local serial build passed. The workspace suite recorded **303 passed, 5 ignored**. The GPU crate recorded **62 passed, 2 ignored**. Original-file protection checks passed. The latest debug run could not enable the missing D3D12 debug layer and exited with code **0 after 28.42 seconds**, before world entry. |
| Fix the remaining defect and verify controllable gameplay on hardware | **Pending** | Reproduce the black screen on hardware, identify the cause, verify the fix, then record a visible world and response to player input. |

In the [Windows CI run for this implementation](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225342), the native release and diagnostics builds passed and the native runtime test job failed. The [source-boundary check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225195) passed for the same commit. The serial test counts above come from the maintainer’s local run.

The next hardware run should record the exact build, GPU driver, title-card time, first black frame, last successful guest submission, host Present result and response to input. See the [experiment workflow](docs/EXPERIMENTS.md).

## Source-only validation

For an existing authorized source checkout, the source-only D3D12 build and synthetic diagnostics tests do not require game files. With the pinned Windows Rust toolchain:

```powershell
cd runtimes/victory
$env:VICTORY_WARP = '1'
$env:VICTORY_D3D12_WARP = '1'
cargo build --locked --profile diag -p victory --features diagnostics
cargo test --locked --workspace --features diagnostics -- --test-threads=1
```

Keep game files, saves, caches and generated artifacts outside Git. The [No Game Data workflow](.github/workflows/no-game-data.yml) checks tracked filenames and content signatures. It is a source-boundary check, not a legal determination. The [Windows CI definition](.github/workflows/victory-runtime.yml) documents source-only validation.

## Source boundary and review eligibility

The earlier Leonida repository was blocked by GitHub under a DMCA notice on 24 November 2026. This integration shares that runtime's lineage and preserves upstream attribution. See the [published notice](https://github.com/github/dmca/blob/master/2026/11/2026-11-24-take-two.md) and [source provenance](runtimes/victory/SOURCE.json). The current repository's accessibility is not a finding that the underlying copyright concerns are resolved.

No link to a removed repository, leaked executable, game files, keys, or alternative distribution location is requested for PortWatch. The submission is a request to review the reported technical observations only; eligibility and whether to publish a link are for PortWatch's maintainer to decide. If the source cannot be listed under its rules, a factual review without a distribution link may be considered at the maintainer's discretion. No attempt to circumvent a legal block is requested.

## Code and attribution

| Location | Purpose |
| --- | --- |
| [runtime/](runtime/) | Original Leonida compatibility runtime and Vulkan renderer |
| [runtimes/victory/](runtimes/victory/) | VIctory native D3D12 backend, shader translation and graphics tests |
| [Integration notes](INTEGRATION.md) | Local integration work and upstream provenance |
| [Technical documentation](docs/README.md) | Runtime, formats, graphics and validation |
| [Contribution guide](CONTRIBUTING.md) | Reproductions, source boundaries and coordination |

Heperkoo maintains this integration. Credit for the original Leonida runtime belongs to ItsNotRexed and the Leonida contributors. Credit for VIctory belongs to Marvisak and the VIctory contributors. See the [upstream pin and change record](runtimes/victory/SOURCE.json), [upstream credits](README.upstream.md#credits), [project license](LICENSE) and [VIctory license](runtimes/victory/LICENSE).
