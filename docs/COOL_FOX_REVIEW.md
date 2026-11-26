# cool_fox compatibility review

Reviewed `codec-d/cool_fox` at
[`f4b48ad766ddbec1a1867022cd42f7645b0dd55e`](https://github.com/codec-d/cool_fox/tree/f4b48ad766ddbec1a1867022cd42f7645b0dd55e),
against the local Radeon candidate `ed6d475`. The upstream code is GPL-3.0.
This review does not replace the measured Radeon run record.

## Memory claim and evidence

[PortWatch's current CGBJ entry](https://portwatch-vi.xyz/#effort-cgbj) lists
8 GB system RAM, 16 GB VRAM and a 25 FPS gameplay average. It labels the project
PortWatch-verified, while also listing independent reproduction and README
verification as outstanding. The entry does not define whether 8 GB is installed
capacity or a measured working set. Its story/rendering/stability values are
owner ratings.

The repository's [bug journal](https://github.com/codec-d/cool_fox/blob/f4b48ad766ddbec1a1867022cd42f7645b0dd55e/docs/bug-journal.md)
records a different experiment: peak process commit 34.42 GiB, minimum Windows
commit headroom 1.30 GiB and median high-draw caption interval 54.3 ms. Later
entries identify an RTX 5090 and a 32 GiB host. Commit is not resident RAM;
these measurements neither disprove the 8 GB claim nor establish an equivalent
8 GB workload. No matching low-memory reproduction has been performed here.

## Selected candidate

The heap-lifetime part of
[`18bdf793`](https://github.com/codec-d/cool_fox/commit/18bdf7932b79f4d0f000ee5b449d91ce970e4be3)
addresses code still present in our candidate:

- `heap_buffer_pass` stores strong shadow references in a process-global map
  indexed by a host heap address, with no heap-destruction removal path.
- A global once-per-frame flag lets one descriptor heap suppress another heap's
  buffer refresh in that frame.
- One list-wide sentinel suppresses refresh after switching descriptor heaps.

The adapted candidate moves retained ranges and refresh history into `HostHeap`,
uses each heap's stride-buffer identity for list deduplication, and rejects a
deferred refresh if a different heap has replaced the original at the same CPU
address. Range-growth checks prevent throttled unwatched refreshes from treating
new bytes as already current. Existing command-list references and GPU retirement
rules remain in place. It does not shorten fence quarantine or change shaders.

The [adaptation patch](../runtimes/patches/victory-cool-fox-heap-lifetime.patch)
applies after the validation patch, at `ed6d475`. The affected draw test group
passed seven tests with one existing ignore, including new ownership-drop and
range-growth regressions. This is a separate candidate pending title validation,
not a measured RAM/FPS saving.

## Changes not copied wholesale

| Area | Decision |
|---|---|
| NVIDIA Wave32 and typed integer lowering | Adapter-specific paths require separate semantic tests; retain the tested Radeon translator. |
| Residency and upload thresholds | The fork changed these repeatedly after starvation and missing-material regressions; do not import its 256-512 MiB commit floors onto this OBS host. |
| Pool allocation retry backoff | Useful failure-path candidate, but this runtime falls back to individual allocations after a pool refusal; copying only the backoff does not solve total memory admission. |
| Dynamic descriptor release at fence completion | Worth a separate lifetime audit; do not remove the existing retirement delay indiscriminately. |
| XMA input refill and partial blocks | Plausible audio correction, but not established as the cause of this run's stalls; requires a targeted refill/ring-buffer regression test. |
| 256 MiB DirectStorage floor | Raises staging memory; no local I/O evidence yet justifies raising the existing 32 MiB setting. |
| Series S two-plane composition | Already separately addressed; Series X remains the selected local profile. |

Keep source adaptations and synthetic tests public. Original shaders, runtime
captures, pipeline books, audio and raw traces remain local.
