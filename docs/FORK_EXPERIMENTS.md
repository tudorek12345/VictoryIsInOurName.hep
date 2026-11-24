# Fast, reproducible runtime experiments

The aim is to reduce time between a concrete question and a trustworthy result. Start with the [current runtime findings](../tracking/runtime-progress.json), then use this loop for the next observed blocker.

## One experiment, one question

1. **Pin the baseline.** Record the fork/upstream commit, local changes, submodules, toolchain, GPU and driver. Reproduce the failure before changing behavior.
2. **Choose the smallest useful probe.** A loader fixture, ABI call probe, descriptor check or memory-visibility test should answer the specific question. Use real executable traces where the local inputs and runner are available.
3. **Write down the hypothesis.** Identify the expected behavior and an observation that would disprove it. A guessed COM slot or address relationship remains a hypothesis until measured.
4. **Make a reversible change.** Keep instrumentation separate from compatibility changes. Use an isolated branch or worktree for competing approaches.
5. **Run the shortest relevant checks.** Exercise the affected contract first. Reuse valid build/shader caches and the runtime-focused stages; avoid a full optional asset export unless the measured dependency needs it.
6. **Reproduce and decide.** Compare the same run before and after. Keep a useful result, revert a rejected hypothesis, or narrow the next probe. Broaden regression checks when shared behavior changes.
7. **Leave a handoff immediately.** Another developer should be able to reproduce the result without reconstructing the investigation.

## Parallel work that helps

| Track | Useful output |
| --- | --- |
| Loader and memory | A measured mapping, TLS, allocation or aliasing contract |
| Graphics and ABI | A measured call layout, descriptor relationship or resource/submission result |
| Reproduction and tooling | A repeatable command, focused fixture and concise result comparison |

Assign ownership before editing shared files. Agree on interface changes, compare current upstream work, and integrate one coherent change at a time. VS Code and Codex can help investigate independent questions; completion still depends on the observed behavior.

## What counts as progress

Track these separately: build success, synthetic test success, retail mapping, retail initialization, entry-point progress, real graphics submission, a game-generated presented frame, input and playable progression.

Record failed experiments too. Ruling out the wrong ABI or a disconnected memory backing can prevent repeated work. Passing an assertion through a placeholder does not establish correct resource semantics.

## Copyable experiment record

```text
Question:
Baseline commit / upstream reference:
Local changes and submodule pins:
Environment / GPU / driver:
Observed failure:
Hypothesis:
Smallest probe or change:
Commands actually run:
Expected result:
Observed result and exit status:
Checks passed / not run:
Decision: keep / revise / revert
Next unresolved blocker:
Next exact experiment:
Sanitized evidence summary / local evidence location:
```

Keep private package contents, generated game artifacts and raw game traces local. Follow the repository's existing [contribution rules](../CONTRIBUTING.md). Public records should contain independently written results and enough context to reproduce the work with the contributor's own inputs.
