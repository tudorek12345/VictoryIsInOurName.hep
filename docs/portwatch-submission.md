# Windows D3D12 runtime integration

**Active request:** [PortWatch #38](https://github.com/4lwayz/portwatch-vi/issues/38), submitted on 24 November 2026 at 11:29 UTC. The maintainer closed the earlier request after filing this replacement.

**Tracking source:** [tudorek12345/VictoryIsInOurName.hep](https://github.com/tudorek12345/VictoryIsInOurName.hep). This repository is the requested source for one existing integration effort. [Earlier registration #17](https://github.com/4lwayz/portwatch-vi/issues/17) records the shared history.

## Evidence for milestone review · 24 November 2026

The [root README’s five-stage table](../README.md#reported-boot-progress), [maintainer-authored boot-progress.log](../boot-progress.log), [structured report](../tracking/runtime-progress.json) and [status-panel screenshot](images/boot-progress.png) describe the same report. The screenshot is a picture of the report. This update has no independent reproduction.

| PortWatch milestone | What the maintainer reports |
| --- | --- |
| Boot and menu | First-boot accessibility, language, settings and legal screens work. The intro plays with sound. The start screen, profile and save flow work. The maintainer also reports the “Rockstar Games Presents” title card after a local update. |
| In-game | After about 50 seconds of loading, the run reaches the first mission’s intro. The picture is black and the host GPU fails within seconds. Visible world geometry and a response to player input remain unverified. |
| Frame rate | First-boot screens were reported at 30 FPS. Separate short-intro runs measured 30 FPS / 33.3 ms on hardware and about 10 FPS / 100 ms on WARP. Gameplay FPS is unknown. |
| Stability | The cause of the host GPU failure remains open. A separate debug attempt exited before world entry after 28.42 seconds with the debug layer unavailable. |

The reported five-stage test system used an AMD Radeon RX 9060 XT with 16 GB of VRAM, an AMD Ryzen 7 5700X and 32 GB of RAM. The exact tested revision, driver and a continuous world-entry recording are pending. Four working stages out of five is the project's local count. PortWatch’s editors assign a score using [their published rubric](https://github.com/4lwayz/portwatch-vi/blob/6eb0d18933f9e14e302c7d05ac41b04e48a8dbfd/assets/js/scoring.js).

## Source and checks

The [integration commit](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) contains shader, presentation and device-loss diagnostics. The [source provenance](../runtimes/victory/SOURCE.json) documents upstream ownership, the source revision and local changes. The repository’s [No Game Data check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45383761167) passed for revision `d861def`. These references establish what source and checks are available. The visual observations come from the maintainer.

A continuous recording tied to a commit and showing the attempted transition and an input response would let reviewers compare the report against the actual output.
