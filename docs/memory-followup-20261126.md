# Memory ownership and Radeon follow-up, 26 November

The latest completed run, `original-20261126-010757-50007ff0`, rendered a
recognizable character and street, houses, fence, trees and power lines in the
private capture near 65 seconds. The image remains very dark; its caption shows
2 FPS, 521.7 ms/frame and 2,755 draws/frame. This is a rendering advance, but
the first mission is still not verified playable or controllable.

The run used clean source `6e11a9a`, the Radeon RX 9060 XT, Series X mode and
light DRED diagnostics. Source `8c7f573` implements the aliased buffer transition
fix and retained-owner census. Source `6e11a9a` adds the narrowly scoped RGBA32
typed-buffer compatibility fix. Two focused checks, including an authored Radeon
GPU probe, 47 descriptor tests and seven draw tests passed; one existing draw test remains ignored. The
optimized build passed. These tests do not establish whole-title correctness.

The job commit guard stopped the runtime at 69.031 seconds, before the planned
four-minute test and scheduled gameplay input. Peak job commit was
23,150,866,432 bytes against the unchanged 22 GiB hard limit. Runtime result was
126. A subsequent AppContainer-profile deletion returned `0x80070020`, so the
launcher reported 125 after 75.97 seconds. All 151 package access paths were
restored. An exact-profile cleanup retry at 09:17:21 UTC succeeded with `S_OK`;
the original run metadata retains both earlier results. The manual-close
request arrived after the process had already ended.

The latest interval measured 0.8 FPS and 1,258.4 ms/frame, including 829 ms of
CPU preparation versus 18.3 ms recorded on the GPU. List steps took 781 ms;
the heap-buffer metric reported two passes taking 592.6 ms. These overlapping
timings identify CPU preparation as a measured optimization target, not a full
GPU-utilization measurement. Light DRED emitted no marker-formatting metric,
so a quantified formatting speedup is not established. The run-wide median
interval was 30 FPS because earlier intro and
loading intervals dominate that statistic; it is not gameplay performance.
No allocation-failure or device-removal message was recorded. Windows System
event 4101 and Victory Application event 1000 had no matches from run start
through 09:17:31 UTC. Their absence does not prove driver stability.

The final independent memory sample recorded 23,079,059,456 private bytes,
18,211,713,024 working-set bytes and 405,553,152 free physical bytes. DXGI separately
reported 7,151 MiB local usage against a 15,419 MiB budget and 7,408 MiB shared
usage. These counters overlap and must not be added together. Memory pressure
remains severe; a memory leak has not been demonstrated fixed end to end.

At the 59.025-second sampler mark, the new ownership census identified 451
completed lists across 64 quarantined submissions, 35 idle lists, zero observed
in-flight lists and 26 queued submissions. The retirement queue held 181,927
resource references. Those references are not necessarily distinct resources
or leaks. Samples are independent and the owner buckets are not exhaustive;
busy-lock results remain unknown rather than zero. The final sample has unknown
in-flight counts while landing was active. The 64-submission lifetime protection
remains unchanged.

The first 45 seconds of captured stereo PCM are non-silent: peak 9,798 and RMS
1,018.35 at 48 kHz. This measures captured data, not audible speaker output,
synchronization or gameplay sound. Raw captures, audio and logs remain local.

An isolated loose-window sharing prototype was withheld. The earlier run had
2,694 MiB of window backing over 1,369 MiB of unique title memory, but sharing a
larger backing can change descriptor bounds and alignment-dependent exact-copy
decisions. It is not a safe memory-only substitution without descriptor-aware
validation. The prototype is not integrated or enabled, and no gameplay memory
saving is claimed. Completed-list and retirement ownership remain the next
diagnostic target.

## Earlier descriptor-lifetime comparison

The preceding completed run,
`original-20261126-004118-20b9fe10`, used source `5987159` and stopped at the
22 GiB job notification after about 67 seconds. This was a guard termination,
with no allocation-failure or device-removal message; it is not proof that the
prior driver fault is fixed. All 151 package access paths were restored.

Returning dynamic descriptor slots now relinquishes their retained resource
references through the existing retirement queue. Slot leases own the original
host heap and cannot return slots to a replacement heap at a reused address.
The defect and its regression tests are addressed, but the title comparison
does not demonstrate lower peak commit: the job still reached 23,249,711,104
bytes. The raw logs, images, audio and generated shaders remain local.

At the last timed sample, process private memory was 22,960,377,856 bytes,
resident memory 19,088,654,336 bytes, and free physical memory 834,371,584 bytes.
The counters recorded 27,021 host textures, 9,183 shadows and 1,296 host lists.
These are live/retained objects, not individually proven leaks. Their categories
overlap and cannot be summed. The existing idle list pool permits 512 reset lists.

The last DXGI sample separately reports local usage 7,349 MiB against a 15,419 MiB
budget and shared usage 6,238 MiB against 15,578 MiB. Shared usage alone does not
prove VRAM oversubscription: CPU-visible buffers also use shared memory. The D:
pagefile is active at 24 GiB and was not the limiting capacity; see the
[pagefile audit](pagefile-check-20261126.md).

The 65-second image contains dark green/black output, not recognizable world
geometry. Its caption shows 1 FPS and 816 draws/frame. The runtime sample records
478 pipeline drops and 59 indirect drops; detailed counters identify disabled
BVH work and pipelines still being created. Full DRED marker formatting costs
455.9 ms/frame in that interval. The launcher now selects the existing light
DRED mode: crash breadcrumbs and page-fault information remain enabled without
per-command text. This is a measured performance target, not a rendering fix.

## New upstream review

GitHub heads checked after the test:

| Project | Revision | Assessment |
| --- | --- | --- |
| [VIctory-7900XTX](https://github.com/avatarmanz/VIctory-7900XTX/commit/722c0e1ce1e80bd045ba63ecb88c440041233fea) | `722c0e1` | New integrations require selective review. |
| [victory-fork](https://github.com/fxceless/victory-fork/commit/f6a09d3ba4ca425e71429ddbcb43b18ad507202a) | `f6a09d3` | Typed-view correctness and texture/retirement experiments are distinct changes. |
| [XCL](https://github.com/xcl-dev/xcl/commit/b49be1836844fe0b0cdb3211dce3cb7fb4e21ac7) | `b49be183` | Repository moved to xcl-dev; revision unchanged from the prior review. |
| codec-d/cool_fox | unavailable | GitHub still returns 404; only the previously retrieved `f4b48ad` snapshot is available locally. |

[773d902f](https://github.com/avatarmanz/VIctory-7900XTX/commit/773d902f16d523c431925a319d6b430dedcba157)
deduplicates a COPY_DEST-to-NON_PIXEL_SHADER_RESOURCE transition when shadows
alias the same host buffer. This is a narrow correctness change that preserves
copy ordering and resource lifetime. It is implemented in local `8c7f573`, with
an authored alias-transition regression test, and included in the latest title
run. The larger residency import remains separate.

The same-resource retirement fast path is already present in local
`HostHeap::keep`; importing `RETIRE_LEAN` again would add no fix. New upstream
residency behavior can shorten a 64-submission quarantine to 16 on smaller hosts
and uses OS commit floors rather than this job's limit. Those changes are not
enabled. The asynchronous reaper adds another destruction queue, with no local
evidence of a lower peak. Descriptor TablePlan is a possible CPU optimization,
not a remedy for retained backing storage.

The latest measurements now split completed-but-quarantined, in-flight and idle
owners. They report busy snapshots as unknown, preserve the 64-submission
lifetime protection, and avoid resource traversal and GPU calls in the sampler.
World rendering and control must be verified independently of interval FPS,
shader compilation success or audio PCM amplitude.
