# PortWatch review packet — Windows D3D12 runtime integration

Updated 25 November 2026. The hardware observations are dated 24 November 2026; this documentation revision does not represent a new hardware run.

**Only requested tracking source:** `tudorek12345/VictoryIsInOurName.hep`. **Active submission:** [issue #38](https://github.com/4lwayz/portwatch-vi/issues/38). It supersedes #17, which was closed by its author. This is one effort with a shared upstream history, not two projects or a request to rank a second repository.

**Status:** Self-reported, awaiting editorial review. This local packet does not create a PortWatch candidate, set a score, certify code, or claim editorial acceptance.

## Evidence for the published rubric

| Milestone | Maintainer's observation and limitation |
| --- | --- |
| Executable / first frames | First-boot accessibility, language, settings and legal screens; intro video with sound. Exact hardware-tested commit, driver and continuous capture are missing. |
| Menu | Start screen, profile and save flow reportedly worked on one PC. Input behavior and the complete sequence need a capture. |
| World | The maintainer reports a title card and a transition to the first mission's intro after about 50 seconds. Output remains black and the host GPU fails. Visible world geometry and actual world entry remain unverified. |
| Playable / story / rendering | Player control, visible game-world rendering and mission progress are unverified. |
| Performance / stability | Hardware 30 FPS / 33.3 ms and WARP about 10 FPS / 100 ms are separate short-intro measurements, not gameplay FPS. The reported failure's cause is unknown. A separate debug attempt ended before world entry after 28.42 seconds. |

Reported hardware: AMD Radeon RX 9060 XT (16 GB), Ryzen 7 5700X, 32 GB RAM. The original four-of-five stage count includes a loading attempt; it must not be interpreted as a PortWatch percentage.

The [root report](../README.md#reported-boot-progress), [maintainer-authored log](../boot-progress.log), [structured report](../tracking/runtime-progress.json), and [status panel](images/boot-progress.png) describe the same observations. The status panel is an illustration of the report, not captured gameplay. No raw telemetry or independent reproduction is attached. Review against the [PortWatch rubric](https://github.com/4lwayz/portwatch-vi/blob/main/assets/js/scoring.js); editorial values remain unset by this submission.

## Source evidence, not gameplay evidence

The [integration checkpoint](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) records changes separate from the upstream baseline. For a source-text review:

| Area | Review reference | What this establishes |
| --- | --- | --- |
| Shader buffer handling | [Synthetic regression tests](https://github.com/tudorek12345/VictoryIsInOurName.hep/blob/298042a3388e400464824d246ed3ec265c238345/runtimes/victory/crates/victory-shader/src/emit/valu_tests.rs) | Raw SRV and UINT16 buffer behavior are covered by test code; no whole-game shader coverage is established. |
| Presentation | [Compositor tests](https://github.com/tudorek12345/VictoryIsInOurName.hep/blob/298042a3388e400464824d246ed3ec265c238345/runtimes/victory/crates/victory-gpu/src/present/tests.rs) | Comparison code exists for fractional and exact scaling. The full-size benchmark is opt-in. No gameplay speedup is established. |
| Shader cache | [Concurrency tests](https://github.com/tudorek12345/VictoryIsInOurName.hep/blob/298042a3388e400464824d246ed3ec265c238345/runtimes/victory/crates/victory-gpu/src/shader_cache.rs) | Synthetic tests cover coalesced misses, shared failure, retry and independent keys. |
| GPU diagnostics | [Host submission diagnostics](https://github.com/tudorek12345/VictoryIsInOurName.hep/blob/298042a3388e400464824d246ed3ec265c238345/runtimes/victory/crates/victory-gpu/src/host.rs) | Source records fence phase and device-removal diagnostics. It does not establish the defect's root cause or that it has been fixed. |

Historical checks: [Windows CI](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45355225342) passed native release and diagnostic builds; the runtime test job failed. The maintainer reported a local serial workspace run of 303 passed / 5 ignored, and a focused GPU run of 62 passed / 2 ignored. The [No Game Data check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45383761167) passed for revision `d861def`. These results refer to their original runs and cannot establish playable GTA VI or certify every file or revision.

## Attribution and source boundary

This is integration work based on the original Leonida runtime (ItsNotRexed and contributors) and VIctory (Marvisak and contributors). The [source provenance](../runtimes/victory/SOURCE.json) documents upstream revisions, omitted assets and local changes. Original credits and licenses remain intact.

The earlier Leonida repository was blocked under GitHub's DMCA process on 24 November. The [published notice](https://github.com/github/dmca/blob/master/2026/11/2026-11-24-take-two.md) describes the upstream network. The current repository's accessibility and source-boundary CI do not resolve copyright or license concerns. No alternate access to removed material or distribution of game files, keys, or executables is requested. PortWatch should decide whether it can list the reporting source under its own rules; if it cannot, any linkless factual review is at its discretion.

## Next evidence needed

- Exact tested source revision, Windows version, GPU driver and backend.
- One continuous capture of the claimed menu, attempted transition, first black frame, and any input response.
- Sanitized diagnostic trace with last successful submission, fence phase and Present result.
- Repeated source-only tests and an independent reproduction when available.

The above are outstanding requirements, not completed work. No new issue, duplicate listing, assigned tier, score or request to bypass discovery or editorial filters is included.
