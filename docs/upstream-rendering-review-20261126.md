# Upstream rendering review, 26 November 2026

This review selects small source changes for the Radeon runtime and distinguishes
executed regression tests from proposed improvements. It does not establish a
playable first mission, stable gameplay, higher FPS or lower whole-process memory.
The shader tests use authored inputs; no game shaders, assets or raw captures are
included here.

The following public heads were checked through the GitHub connector during this
pass. They identify the reviewed revisions, not a promise that their branches
will remain at those commits.

| Repository | Reviewed head | Relevant findings |
| --- | --- | --- |
| avatarmanz/VIctory-7900XTX | [9576c45](https://github.com/avatarmanz/VIctory-7900XTX/commit/9576c45f1d551be0cfde154da027707658ce031e) | Descriptor-table planning, ambient-history timing and optional texture storage reviewed separately. |
| fxceless/victory-fork | [f6a09d3](https://github.com/fxceless/victory-fork/commit/f6a09d3ba4ca425e71429ddbcb43b18ad507202a) | Legacy fused arithmetic selected narrowly; separate upload-worker and denormal changes not imported. |
| Belobug/VIctory-Belobug-AMD | [81ebb7b](https://github.com/Belobug/VIctory-Belobug-AMD/commit/81ebb7bdc9b7ca6ec2f3169973f50be77c7c803c) | Resource-pressure policy, ambient filtering and compiler-fault handling reviewed; none selected in this pass. |
| DexNom/VIctory | [64bd58f](https://github.com/DexNom/VIctory/commit/64bd58f5fb794216894bc0e33e03a3a64d19c347) | Earlier rendering change [921d8d3](https://github.com/DexNom/VIctory/commit/921d8d3b43b44f3a6ca4b44095edd3c4baf10a87) supplied the pixel-helper comparison and sparse-texture/remap candidates. |

The implemented shader correction is runtime source commit
`00ea5d4cc5450f0578d0d16980a653e62218f7c0`. The decoder retains legacy MAD/MAC
names, but their RDNA2 encodings specify fused FMA/FMAC. The correction uses fused
arithmetic while retaining the legacy zero-factor rule, accumulator behavior,
source/output modifiers and existing lane-identity handling. A zero product also
preserves positive zero when added to negative zero. Ordinary nonlegacy
arithmetic is unchanged. The opcode interpretation was independently checked
against the [AMD RDNA2 ISA](https://docs.amd.com/v/u/en-US/rdna2-shader-instruction-set-architecture)
and LLVM's [VOP3 definitions](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AMDGPU/VOP3Instructions.td)
and [VOP2 definitions](https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AMDGPU/VOP2Instructions.td).

Before applying the production correction, an authored precision test actually
failed on the physical Radeon RX 9060 XT: the cancellation expression
`(1 + 2^-23) * (1 - 2^-23) - 1` returned zero instead of `-2^-46`.
Afterward, all four hardware precision cases executed and passed. Additional
tests cover zero factors, NaN/infinity, signed zero, accumulation and modifiers
on Radeon and WARP. WARP was not used as the fused-precision reference.
The final complete `victory-shader` library suite passed **291 tests**, with
**zero failures and four existing ignored tests**, in 108.08 seconds. It used
the optimized `diag` profile, `diagnostics,host`, one build job and serialized
test execution on driver 32.0.32029.2010. An older test's requirement for different
generic/RDNA legacy-MAD bytecode was updated because both now intentionally use
the same fused lowering; its 100 hardware value comparisons were retained.

DexNom's pixel-helper fix was already represented by this runtime's
`helpers_read()` / `quad_read()` path. Replacing it was unnecessary. An authored
16-by-16 shared-triangle-edge test verified DS swizzles and DPP across four
broadcasts, identity, three exchanges and one mixed permutation. **All 18 cases
executed on Radeon and all 18 on WARP**, checking every pixel. The test uses the
existing GPU-test mutex and reports absent-device skips explicitly. No pixel
production rewrite was applied. Additional DPP8 support is deferred without an
observed failing shader; the existing lane-identity workaround remains intact.

Two additional adaptations passed focused validation and are committed locally
as `1337a9a` and `988ed8f`. Neither is credited with a measured title performance
or memory improvement before a guarded comparison.

| Selected adaptation | Scope and safeguards | Validation status |
| --- | --- | --- |
| Descriptor `TablePlan`, adapted from [avatarmanz 46e329](https://github.com/avatarmanz/VIctory-7900XTX/commit/46e32978188d2a82e1723f31cfe42c799751dee7) | Precompute immutable table metadata instead of repeatedly scanning declarations. Preserve declaration order, first duplicate descriptor, live root-constant selection, checked invalid-maximum fallback, shader identity and dynamic descriptor leases. Separate fallback-heap changes are excluded. | Four focused regressions passed, including 3,840 boundary combinations. CPU savings unmeasured. |
| Sparse textures and remap overflow, adapted from [DexNom 921d8d3](https://github.com/DexNom/VIctory/commit/921d8d3b43b44f3a6ca4b44095edd3c4baf10a87) | Preserve view tracking and the existing upload-consumer join. If both endpoint pages are absent, inspect bounded interior memory regions with checked arithmetic and guard/no-access exclusion. When the bounded remap queue fills, request a rescan of registered spans instead of losing notifications; this does not walk the whole address space. | Six focused regressions passed. The old implementation failed the same interior-page test with zero bytes instead of 65,536. |

The combined focused GPU-library checks completed 29 successful executions,
representing 26 unique tests, with no failures or ignored tests. Existing span,
binding-hash, dynamic-release, heap-identity, lease and retirement checks passed.
The sparse correction can discover additional legitimate resources; it must not
be described as a RAM-saving change. Both adaptations preserve GPU resource
lifetime protections.

Several changes were deliberately excluded:

- Unconditional flush-to-zero from the legacy-FMA upstream patch: the ISA makes
  denormal handling depend on MODE. This correction preserves the existing
  policy instead of asserting that all input subnormals must be flushed.
- The separate [fxceless upload worker](https://github.com/fxceless/victory-fork/commit/d4a528ba08c92214a106392c65e645ba298263f9):
  its ready-list queue lacks a total byte limit. Per-list limits alone do not
  bound retained memory when submission stalls; admission and lifetime checks
  are needed before importing it into a memory-pressure investigation.
- Belobug's compiler-fault recovery: parking faulted workers while creating
  replacements can retain stacks and driver-owned state. Its pressure thresholds
  and fallback-view policy also require a measured budget-pressure case before
  claiming a benefit here.
- Ambient color heuristics and broad lighting probes: rejecting magenta history
  can discard valid light. The newer time-based ambient settling also resets
  frame deltas above one second, which needs examination at very low FPS.
  These do not establish a correction for malformed geometry.
- The optional [texture store](https://github.com/avatarmanz/VIctory-7900XTX/commit/9386b828554a7e066e2d2ecebe6a99d252f63bdf):
  its additional CPU cache conflicts with the current memory-pressure target.
  Cube-LOD, ray-directory and other unrelated renderer changes were not bundled
  into these selections.

Synthetic GPU correctness is necessary but does not establish title behavior.
The combined runtime still needs a successful build, refreshed shader cache and
a guarded title comparison before any claim about world visibility, controller
response, first-mission progress, FPS or memory reduction. Existing submission
lifetime protection and system-memory safeguards remain part of that validation.
