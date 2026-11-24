# Windows D3D12 runtime integration

**Active request:** [PortWatch #38](https://github.com/4lwayz/portwatch-vi/issues/38), submitted on 24 November 2026 at 11:29 UTC. The maintainer closed the earlier request after filing this replacement.

**Tracking source:** [tudorek12345/VictoryIsInOurName.hep](https://github.com/tudorek12345/VictoryIsInOurName.hep). This repository is the requested source for one existing integration effort. [Earlier registration #17](https://github.com/4lwayz/portwatch-vi/issues/17) records the shared history.

## Maintainer report · 24 November 2026

| Stage | Reported observation | Evidence available |
| --- | --- | --- |
| Title card | “Rockstar Games Presents” appears after the latest local update. | [Dated repository report](../tracking/runtime-progress.json). A capture of this run and its build revision are pending. |
| World transition | The maintainer describes the run as reaching an in-game stage with a black picture. | Same report. Visible world geometry, player movement and input response have yet to be demonstrated. |

The hardware, driver and frame rate for this particular run have not been recorded. A reviewer can evaluate the report as self-reported and assign any milestone under [PortWatch’s rubric](https://github.com/4lwayz/portwatch-vi/blob/cae15b09acac2bc4871101811fa229874d66416a/EDITOR.md).

## Source and checks

The [integration commit](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) contains shader, presentation and device-loss diagnostics. The [source provenance](../runtimes/victory/SOURCE.json) documents upstream ownership, the source revision and local changes. The repository’s [No Game Data check](https://github.com/tudorek12345/VictoryIsInOurName.hep/actions/runs/45383761167) passed for revision `d861def`. These references establish what source and checks are available. The visual observations come from the maintainer.

A continuous recording tied to a commit and showing the attempted transition and an input response would let reviewers compare the report against the actual output.
