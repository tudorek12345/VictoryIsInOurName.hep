# Upstream refresh, 26 November 2026

This supplements the [earlier rendering review](upstream-rendering-review-20261126.md).
GitHub default heads were checked again at approximately 03:08 PST. The following
revisions identify the source reviewed; branch heads can change afterward.

| Repository / branch | Reviewed head | Change since the earlier review |
| --- | --- | --- |
| avatarmanz/VIctory-7900XTX / main | [0dec5dcc](https://github.com/avatarmanz/VIctory-7900XTX/commit/0dec5dcc228b6e0b7540d170c2dcd7d52e6d0b99) | Seven commits after `9576c45`: guest-resolution controls, optional raw constant-buffer reads and replay changes. |
| fxceless/victory-fork / main | [06702fe8](https://github.com/fxceless/victory-fork/commit/06702fe86b91bacbf4a0a27662ae443435bf732e) | One commit after `f6a09d3`: BC7 rotation, dispatch spreading and optional scheduling/diagnostic changes. |
| DexNom/VIctory / main | [64bd58f](https://github.com/DexNom/VIctory/commit/64bd58f5fb794216894bc0e33e03a3a64d19c347) | Unchanged. |
| Belobug/VIctory-Belobug-AMD / rx9070xt | [81ebb7b](https://github.com/Belobug/VIctory-Belobug-AMD/commit/81ebb7bdc9b7ca6ec2f3169973f50be77c7c803c) | Unchanged. |
| xcl-dev/xcl / main | [b49be183](https://github.com/xcl-dev/xcl/commit/b49be1836844fe0b0cdb3211dce3cb7fb4e21ac7) | Current canonical repository for the old `ivall/xcl` URL; latest merge concerns offline compute PSOs and repeated atomic shaders. |

## Implemented and tested

The isolated BC7 correction from fxceless `06702fe8` is implemented in runtime
source commit `2ebbf740b97c2527dfeb0510c374d4be6b8c6ff6`. Channel rotation now
applies only to BC7 modes 4 and 5 in both endpoint precision and block packing.
Authored regressions cover ignored rotation bits in other modes and valid
rotation in modes 4/5. The formats test suite passed **42 tests, with zero
failures and five ignored tests**. This establishes decoder behavior, not an
observed gameplay/FPS improvement.

## Candidates and changes not imported

- **Guest output size remains under evaluation.** [avatarmanz's resolution
  change](https://github.com/avatarmanz/VIctory-7900XTX/commit/f63b4b12c556ff123c6fd591d8380dba2f17c8ff)
  changes the title's output-setting path with byte checks. Resizing a host
  window does not prove that guest render targets changed. The candidate is
  not validated here. Its separate FidelityFX scale experiment documents a
  Series-S crash; those switches are not being adopted together.
- **Raw constant buffers are deferred.** [3920dc26](https://github.com/avatarmanz/VIctory-7900XTX/commit/3920dc26bf995d7ea8772c9d9b9a8176fa7bc2db)
  uses raw descriptor twins/root SRVs to avoid alignment-driven copies. It
  depends on earlier title-memory mapping and lifetime contracts absent from
  this integration. Importing only its switch would not establish those contracts.
- **Dispatch spreading needs separate validation.** The new shader prologue,
  root constants and indirect-record layout overlap the active AMD wide-dispatch
  approach. They were not merged without a semantic comparison.
- **Larger flight limits are not a memory fix.** `VICTORY_SETTLE_ROOM` permits
  more outstanding lists and merged ranges, increasing retained work. Pipeline
  denial and unmeasured synchronization probes were also not adopted.
- **XCL remains a reference.** Its architecture and large divergence from the
  local reference do not support an unreviewed drop-in merge.

## Pipeline-cache warnings

Live XCL [identifies device slots 57/67](https://github.com/xcl-dev/xcl/blob/b49be1836844fe0b0cdb3211dce3cb7fb4e21ac7/crates/xcl/src/hle/d3d12x/device_x.rs#L581)
as console pipeline-state deserialization. It returns `E_NOTIMPL` and documents
ordinary description-based creation as the alternative. The four VIctory forks
retain the same failure behavior. Warning invocation counts are therefore not
counts of proven missing rendering pipelines. This title's actual fallback
success still needs tracing; returning artificial success is not a fix.

## Zettrox archive

The original `Zettrox/ztrx` returned HTTP 404 during this review. Accessible
[random-archives](https://github.com/random-archives/ztrx/commit/90b529f878a470fec9bf07b7be316bc769a12232)
and [grosterr](https://github.com/grosterr/ztrx/commit/90b529f878a470fec9bf07b7be316bc769a12232)
mirrors agree on archived head `90b529f8`; this is not a verified current original
head. Selected local snapshot files matched their Git blobs.

Its wave-barrier/cache fix, separated lane-mask restoration, pending-pipeline
prewarm, shader cleanup and idle-memory reclamation are already represented in
the active runtime. No distinct missing memory fix was established. The archive
reports 1-3 world FPS and black shadows on an RTX 3050 with **8 GB VRAM**, not a
measured 8 GB system-RAM footprint. Those author reports are not local benchmarks.

Code is declared GPL-3.0-or-later; preserve upstream authorship. Its asset policy
excludes a format-table binary from that license, so it is not included in any
source integration. No archive-wide merge was selected.

These source reviews and decoder tests do not establish a playable first mission,
stable 30 FPS or reduced whole-process memory. Series S/X selection remains tied
to controlled runs, visible rendering, measured memory and actual guest dimensions.
