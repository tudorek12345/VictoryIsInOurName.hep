# PortWatch registration packet

**Status: submitted as [PortWatch issue #17](https://github.com/4lwayz/portwatch-vi/issues/17); awaiting maintainer review.** This document requests review of [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) as a distinct contributor fork and runtime integration effort. It does not establish a PortWatch listing, score, endorsement or partnership.

PortWatch's current scout does **not** ingest JSON from this repository. The adjacent [customized candidate proposal](../tracking/portwatch-candidate.json) follows its real `candidates[]` record shape so a reviewer can inspect or reuse it. Its factual description is proposed review wording, rather than a verbatim copy of the repository description. Registration requires a human-reviewed change to [PortWatch's registry](https://github.com/4lwayz/portwatch-vi/blob/main/data/tracker.json), normally requested through an issue or pull request.

## Source and validation evidence

| Evidence | Reference and scope |
| --- | --- |
| Current integration checkpoint | [2b643c705ab3bd8e48560e5bab0f991274a32113](https://github.com/tudorek12345/Leonida/commit/2b643c705ab3bd8e48560e5bab0f991274a32113). This source revision adds native shader-test isolation to the upstream refresh. |
| Current VIctory provenance | [SOURCE.json at the current checkpoint](https://github.com/tudorek12345/Leonida/blob/2b643c705ab3bd8e48560e5bab0f991274a32113/runtimes/victory/SOURCE.json), pinning upstream `d2a4bae1f49533ef5cb512fd1b1ba1513f2e1989` and recording authorship, GPL-3.0-or-later licensing, omitted assets and local changes. |
| Upstream refresh scope | The [upstream interval](https://github.com/Marvisak/VIctory/compare/35b054ec038c11bc8a0de66b1eee764b1ad4f101...d2a4bae1f49533ef5cb512fd1b1ba1513f2e1989) spans 58 commits; the vendored refresh updates 22 Rust source files. This is a source snapshot refresh, with upstream authorship retained. |
| Native shader-test mitigation | A shared guard covers all 13 native GPU/DXIL test entry points under `cfg(test, windows)`. No assertion was removed, and production runtime behavior is unchanged. [Upstream issue #181](https://github.com/Marvisak/VIctory/issues/181) reports a related intermittent access violation when GPU tests run in parallel; it does not establish the exact cause of our CI failure. |
| Runtime integration | [runtime_backend.py at the current checkpoint](https://github.com/tudorek12345/Leonida/blob/2b643c705ab3bd8e48560e5bab0f991274a32113/runtime_backend.py) selects the independent VIctory and Leonida processes and separates external runtime state. |
| Current Windows validation definition | [VIctory workflow at the current checkpoint](https://github.com/tudorek12345/Leonida/blob/2b643c705ab3bd8e48560e5bab0f991274a32113/.github/workflows/victory-runtime.yml): the full native suite, five repeated shader-test runs with eight test threads, separate release and diagnostics builds through the launcher, and native CLI smoke checks. |
| Current Windows CI result | **Passed:** [run 45304650680](https://github.com/tudorek12345/Leonida/actions/runs/45304650680), testing `2b643c705ab3bd8e48560e5bab0f991274a32113`. All three jobs passed: 271 Rust tests passed, 0 failed and 4 were ignored (three external-reference tests and one benchmark); 24 Python launcher tests passed. Native release and diagnostics builds and both executable CLI smoke checks passed. |
| Current repeated shader-test result | Five separate runs with eight test threads each passed all 69 shader tests, with 0 failures and 0 ignored tests per run. This is 345 repeated executions of the same 69 tests, not 345 distinct tests. The results support the test-isolation mitigation on this CI runner; they do not establish its effect on every GPU or prove the root cause of the earlier crash. |
| Current source-data check | **Passed:** [No Game Data run 45304650622](https://github.com/tudorek12345/Leonida/actions/runs/45304650622), checking the same `2b643c705ab3bd8e48560e5bab0f991274a32113` revision. |
| Current workflow validation | **Passed:** [workflow-validation run 45304650601](https://github.com/tudorek12345/Leonida/actions/runs/45304650601), checking the same `2b643c705ab3bd8e48560e5bab0f991274a32113` revision. |
| Previous upstream-refresh validation (historical) | [Run 45303223688](https://github.com/tudorek12345/Leonida/actions/runs/45303223688) tested [74a7b88a944901f28256baf5988c93032acb41f9](https://github.com/tudorek12345/Leonida/commit/74a7b88a944901f28256baf5988c93032acb41f9). Release and diagnostics builds, native CLI smoke checks and Python launcher tests passed; the native shader-test process failed with `STATUS_ACCESS_VIOLATION` (`0xC0000005`). This failed native-suite result motivated the test-isolation mitigation above. |
| Initial integration checkpoint (historical) | [367002ac15bf6efe6af0355afc3da4d257ce712c](https://github.com/tudorek12345/Leonida/commit/367002ac15bf6efe6af0355afc3da4d257ce712c), with [its original SOURCE.json](https://github.com/tudorek12345/Leonida/blob/367002ac15bf6efe6af0355afc3da4d257ce712c/runtimes/victory/SOURCE.json), pinned upstream `35b054ec038c11bc8a0de66b1eee764b1ad4f101`. |
| Windows fixture-path correction (historical) | [97bb13714b2c6f1988578b0827fc19ebc3808847](https://github.com/tudorek12345/Leonida/commit/97bb13714b2c6f1988578b0827fc19ebc3808847). Canonicalizes the temporary fixture root to handle Windows short-path aliases; it does not establish gameplay. |
| Previous completed Windows CI result (historical) | **Passed:** [run 45299795364](https://github.com/tudorek12345/Leonida/actions/runs/45299795364), testing [bd812d9f1fd779dc1c23d6e6fc7eea2606b40cce](https://github.com/tudorek12345/Leonida/commit/bd812d9f1fd779dc1c23d6e6fc7eea2606b40cce). All three jobs passed: 234 Rust tests, 24 launcher tests, native release and diagnostics builds, and both executable CLI smoke tests. Three existing external-reference tests were ignored. These results apply to that earlier revision. |

The fork builds on the original Leonida contributors and [Marvisak/VIctory](https://github.com/Marvisak/VIctory). Heperkoo maintains this integration; inherited runtime authorship remains with its authors. Local changes include external BCPack table loading and validation, source-boundary checks, portable synthetic PE coverage and protection against replacing the parent repository's Git hooks.

Tests using synthetic inputs and successful compilation provide implementation evidence. GTA VI boot, menu, world rendering, performance and stability require evidence from the exact integrated build. Existing maintainer reports and upstream VIctory results must retain their original provenance; they do not establish those milestones for this new integration. No merged-build GTA milestone or rank is requested here.

The earlier passing revision includes the [native D3D12 test-fixture correction](https://github.com/tudorek12345/Leonida/commit/69b44411be335792c386805da8d017427941681a). It replaced an incorrectly packed test structure with the generated Windows API type; production serialization was unchanged. The refreshed snapshot uses the matching upstream fixture, as recorded in its provenance, so this is no longer a remaining local difference.

Current `2b643c705ab3bd8e48560e5bab0f991274a32113` artifacts are available for [release](https://github.com/tudorek12345/Leonida/actions/runs/45304650680/artifacts/14879794110) and [diagnostics](https://github.com/tudorek12345/Leonida/actions/runs/45304650680/artifacts/14879219595). Both builds and native executable CLI smoke checks passed in the successful workflow. These artifacts and test results do not establish a GTA VI gameplay milestone.

Historical artifacts from the preceding `74a7b88a944901f28256baf5988c93032acb41f9` refresh are [release](https://github.com/tudorek12345/Leonida/actions/runs/45303223688/artifacts/14879143221) and [diagnostics](https://github.com/tudorek12345/Leonida/actions/runs/45303223688/artifacts/14880285816). Their builds and executable CLI smoke checks passed, but the native shader-test process failed. They do not include the subsequent test-isolation change and do not establish its validation result.

Historical artifacts from the previous passing revision remain linked here for traceability: [release](https://github.com/tudorek12345/Leonida/actions/runs/45299795364/artifacts/14877598673) and [diagnostics](https://github.com/tudorek12345/Leonida/actions/runs/45299795364/artifacts/14877878171), with 14-day retention. They do not contain the latest upstream refresh. Their linked workflow and source remain available to rebuild them. At the initial integration checkpoint, the separate legacy CI had failures also seen before this integration; this packet reports the dedicated VIctory workflow.

## Historical scout compatibility check

Original discovery snapshot: **24 November 2026, 01:33:49 CET (00:33:49 UTC)**. The screening results below retain that snapshot, including the then-current 13-star count. Repository metadata and the default-branch README were read from GitHub. The discovery calculations below use PortWatch's actual [core functions](https://github.com/4lwayz/portwatch-vi/blob/main/scripts/lib/core.mjs) and [pipeline predicates](https://github.com/4lwayz/portwatch-vi/blob/main/scripts/lib/pipeline.mjs).

| Check | Observed result |
| --- | --- |
| Fork gate | GitHub reports a fork with 13 stars. It passes the scout's `fork && stars < 10` rejection condition. |
| Relevant project | `isRelevant` returned `true`; the detected kind was `effort`. |
| Discovery substance | 73, above the discovery threshold of 35. This is a screening heuristic; gameplay milestones and ranking are assessed separately. |
| Commit-count input | The scout's own one-page query returned 100 commits and uses the signal `100+ commits/7d`. Fork history is included; this does not mean Heperkoo authored those commits. |
| Same-name screening | The tracked name `Leonida` resolves to `ItsNotRexed/Leonida`. GitHub returned 404 for that repository during this check. |
| Actual predicate result | With no comparison README, the same-name predicate substitutes an overlap value of `1` and returns `{copyOf: "ItsNotRexed/Leonida", pct: 0}`. The `pct: 0` value is a missing-comparison sentinel, not a measured overlap. |

The last result is a **local evaluation of the public scout code**, not a claim that the live tracker has already flagged this fork. It means automatic discovery cannot be relied upon. Ask for manual review of the actual source changes. PortWatch's [editorial instructions](https://github.com/4lwayz/portwatch-vi/blob/main/EDITOR.md) explicitly treat surviving Leonida contributor forks as separate candidate efforts.

The JSON is a customized proposal. Its repository metadata was refreshed from GitHub on **24 November 2026 at 02:25:23 CET (01:25:23 UTC)**: `stars` is **17** and `pushedAt` is **2026-11-24T01:23:10Z**. GitHub still reports `Python` and default branch `main`. The original `foundAt`, discovery `substance: 73` and `signals` are retained from the historical screening snapshot above; the discovery score is not a gameplay percentage. Current source, provenance, workflow and CI references appear in `links`.

The description summarizes the integration and explicitly leaves GTA VI behavior unverified. The proposal contains no `gta`, `groundwork`, `tier`, `verification` or leaderboard score fields. Its `status: "new"` is the candidate schema's proposed review state. The proposal was linked in [registration issue #17](https://github.com/4lwayz/portwatch-vi/issues/17); it has not been added to PortWatch's registry. Updating this local packet does not edit the submitted issue. The original submitted text is retained verbatim below.

## Registration and subsequent updates

The review request was submitted to [4lwayz/portwatch-vi as issue #17](https://github.com/4lwayz/portwatch-vi/issues/17) on 24 November 2026 at 01:58 CET. A maintainer can add a reviewed `efforts[]` record with a unique ID, repository, branch, approach, target, tier and evidence-based assessment. **`leonida-heperkoo` is a proposed ID only.** The owner chooses whether to register it and how to assess it.

A direct insertion into the candidate queue may encounter the same copy predicate on its next scout run. Ask the reviewer to resolve that classification explicitly. Do not rename the project or disguise inherited source to evade screening.

After acceptance, retain the assigned ID and update evidence through the registry's review process. The scout refreshes repository metadata and README claims; it does not synchronize this local JSON or automatically verify a milestone. Use `self-reported` until credible independent reproduction supports another verification state.

## Submitted registration issue

**Title:** Review Hep's Leonida as a distinct Leonida/VIctory runtime integration effort

---

I maintain [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) and would like it reviewed as a separate contributor fork focused on running the Xbox Series executable natively on Windows.

The fork integrates [Marvisak/VIctory](https://github.com/Marvisak/VIctory) alongside the original Leonida runtime. The integration checkpoint is [367002ac](https://github.com/tudorek12345/Leonida/commit/367002ac15bf6efe6af0355afc3da4d257ce712c); [SOURCE.json](https://github.com/tudorek12345/Leonida/blob/367002ac15bf6efe6af0355afc3da4d257ce712c/runtimes/victory/SOURCE.json) records the upstream pin, authorship, licence and changes.

The work includes backend selection with separate external state, loading user-supplied BCPack tables, source-boundary checks and synthetic tests. Please assess the fork's own code and results. The newly integrated build has no independently reproduced GTA VI milestone to claim.

Windows fixture-path correction: [97bb137](https://github.com/tudorek12345/Leonida/commit/97bb13714b2c6f1988578b0827fc19ebc3808847).

Windows CI evidence: [run 45299795364](https://github.com/tudorek12345/Leonida/actions/runs/45299795364) **passed** on [bd812d9f](https://github.com/tudorek12345/Leonida/commit/bd812d9f1fd779dc1c23d6e6fc7eea2606b40cce): 234 Rust tests and 24 launcher tests passed, with three existing external-reference tests ignored. Release and diagnostics binaries were built through the integration launcher and each passed a native `--help` smoke test. These are code and synthetic-input checks, not evidence of GTA VI gameplay.

I checked your scout: the fork currently passes its star threshold, but the same-name check classifies it as a copy when the deleted `ItsNotRexed/Leonida` README is unavailable. Your editorial notes identify surviving Leonida contributor forks as separate candidates, so I am requesting manual review of the implementation.

The repository includes [a candidate-shaped metadata proposal](https://github.com/tudorek12345/Leonida/blob/main/tracking/portwatch-candidate.json) for review. Proposed stable ID: `leonida-heperkoo`. Please choose the appropriate tier and assessment from the evidence.

Credit remains with the original Leonida contributors and Marvisak/VIctory. I maintain the fork integration; this request does not assert an upstream partnership.

---

Submitted with maintainer authorization as [issue #17](https://github.com/4lwayz/portwatch-vi/issues/17). At submission, the issue was open with no maintainer reply. No PortWatch registry entry or approval is implied by the submission.
