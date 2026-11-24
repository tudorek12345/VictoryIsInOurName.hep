# PortWatch registration packet

**Status: prepared, not submitted or registered.** This document requests review of [tudorek12345/Leonida](https://github.com/tudorek12345/Leonida) as a distinct contributor fork and runtime integration effort. It does not establish a PortWatch listing, score, endorsement or partnership.

PortWatch's current scout does **not** ingest JSON from this repository. The adjacent [customized candidate proposal](../tracking/portwatch-candidate.json) follows its real `candidates[]` record shape so a reviewer can inspect or reuse it. Its factual description is proposed review wording, rather than a verbatim copy of the repository description. Registration requires a human-reviewed change to [PortWatch's registry](https://github.com/4lwayz/portwatch-vi/blob/main/data/tracker.json), normally requested through an issue or pull request.

## Source and validation evidence

| Evidence | Reference and scope |
| --- | --- |
| Integration checkpoint | [367002ac15bf6efe6af0355afc3da4d257ce712c](https://github.com/tudorek12345/Leonida/commit/367002ac15bf6efe6af0355afc3da4d257ce712c). Review this immutable commit; later fixes and CI results must identify their own commit. |
| VIctory provenance | [SOURCE.json at that checkpoint](https://github.com/tudorek12345/Leonida/blob/367002ac15bf6efe6af0355afc3da4d257ce712c/runtimes/victory/SOURCE.json), including upstream commit `35b054ec038c11bc8a0de66b1eee764b1ad4f101`, authorship, GPL-3.0-or-later licensing, omitted assets and local changes. |
| Runtime integration | [runtime_backend.py](https://github.com/tudorek12345/Leonida/blob/367002ac15bf6efe6af0355afc3da4d257ce712c/runtime_backend.py) selects the independent VIctory and Leonida processes and separates external runtime state. |
| Windows validation definition | [VIctory workflow](https://github.com/tudorek12345/Leonida/blob/367002ac15bf6efe6af0355afc3da4d257ce712c/.github/workflows/victory-runtime.yml): Windows MSVC tests, release and diagnostics builds, and CLI smoke checks. |
| Windows fixture-path correction | [97bb13714b2c6f1988578b0827fc19ebc3808847](https://github.com/tudorek12345/Leonida/commit/97bb13714b2c6f1988578b0827fc19ebc3808847). Canonicalizes the temporary fixture root to handle Windows short-path aliases; it does not establish gameplay. |
| Completed Windows CI result | **Passed:** [run 45299795364](https://github.com/tudorek12345/Leonida/actions/runs/45299795364), testing [bd812d9f1fd779dc1c23d6e6fc7eea2606b40cce](https://github.com/tudorek12345/Leonida/commit/bd812d9f1fd779dc1c23d6e6fc7eea2606b40cce). All three jobs passed: 234 Rust tests, 24 launcher tests, native release and diagnostics builds, and both executable CLI smoke tests. Three existing external-reference tests were ignored. |

The fork builds on the original Leonida contributors and [Marvisak/VIctory](https://github.com/Marvisak/VIctory). Heperkoo maintains this integration; inherited runtime authorship remains with its authors. Local changes include external BCPack table loading and validation, source-boundary checks, portable synthetic PE coverage and protection against replacing the parent repository's Git hooks.

Tests using synthetic inputs and successful compilation provide implementation evidence. GTA VI boot, menu, world rendering, performance and stability require evidence from the exact integrated build. Existing maintainer reports and upstream VIctory results must retain their original provenance; they do not establish those milestones for this new integration. No merged-build GTA milestone or rank is requested here.

The passing source revision also includes the [native D3D12 test-fixture correction](https://github.com/tudorek12345/Leonida/commit/69b44411be335792c386805da8d017427941681a). It replaces an incorrectly packed test structure with the generated Windows API type; production serialization was unchanged.

The workflow publishes [release](https://github.com/tudorek12345/Leonida/actions/runs/45299795364/artifacts/14877598673) and [diagnostics](https://github.com/tudorek12345/Leonida/actions/runs/45299795364/artifacts/14877878171) archives with 14-day retention. The linked workflow and source remain available to rebuild them. The repository's separate legacy CI still has failures also seen before this integration; this packet reports the dedicated VIctory workflow only.

## Scout compatibility check

Snapshot: **24 November 2026, 01:33:49 CET (00:33:49 UTC)**. Repository metadata and the default-branch README were read from GitHub. The discovery calculations below use PortWatch's actual [core functions](https://github.com/4lwayz/portwatch-vi/blob/main/scripts/lib/core.mjs) and [pipeline predicates](https://github.com/4lwayz/portwatch-vi/blob/main/scripts/lib/pipeline.mjs).

| Check | Observed result |
| --- | --- |
| Fork gate | GitHub reports a fork with 13 stars. It passes the scout's `fork && stars < 10` rejection condition. |
| Relevant project | `isRelevant` returned `true`; the detected kind was `effort`. |
| Discovery substance | 73, above the discovery threshold of 35. This is a screening heuristic; gameplay milestones and ranking are assessed separately. |
| Commit-count input | The scout's own one-page query returned 100 commits and uses the signal `100+ commits/7d`. Fork history is included; this does not mean Heperkoo authored those commits. |
| Same-name screening | The tracked name `Leonida` resolves to `ItsNotRexed/Leonida`. GitHub returned 404 for that repository during this check. |
| Actual predicate result | With no comparison README, the same-name predicate substitutes an overlap value of `1` and returns `{copyOf: "ItsNotRexed/Leonida", pct: 0}`. The `pct: 0` value is a missing-comparison sentinel, not a measured overlap. |

The last result is a **local evaluation of the public scout code**, not a claim that the live tracker has already flagged this fork. It means automatic discovery cannot be relied upon. Ask for manual review of the actual source changes. PortWatch's [editorial instructions](https://github.com/4lwayz/portwatch-vi/blob/main/EDITOR.md) explicitly treat surviving Leonida contributor forks as separate candidate efforts.

The JSON is a customized proposal: repository facts come from the snapshot, while the description summarizes the source integration and explicitly leaves GTA VI behavior unverified. It contains no `gta`, `groundwork`, `tier`, `verification` or leaderboard score fields. Its `status: "new"` is the candidate schema's review state; this file has not been submitted to PortWatch. Refresh metadata after later commits; the current default branch is `main`.

## Registration and subsequent updates

Open a review request in [4lwayz/portwatch-vi](https://github.com/4lwayz/portwatch-vi/issues), or prepare a narrowly scoped registry pull request. A maintainer can add a reviewed `efforts[]` record with a unique ID, repository, branch, approach, target, tier and evidence-based assessment. **`leonida-heperkoo` is a proposed ID only.** The owner chooses whether to register it and how to assess it.

A direct insertion into the candidate queue may encounter the same copy predicate on its next scout run. Ask the reviewer to resolve that classification explicitly. Do not rename the project or disguise inherited source to evade screening.

After acceptance, retain the assigned ID and update evidence through the registry's review process. The scout refreshes repository metadata and README claims; it does not synchronize this local JSON or automatically verify a milestone. Use `self-reported` until credible independent reproduction supports another verification state.

## Ready-to-post registration issue

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

Posting this draft is a separate action. No issue, pull request or tracker edit has been made as part of preparing this packet.
