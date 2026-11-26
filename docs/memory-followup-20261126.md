# Memory ownership and Radeon follow-up, 26 November

The first mission is still not verified playable. The latest completed run,
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
copy ordering and resource lifetime. It is being validated separately from the
larger residency import.

The same-resource retirement fast path is already present in local
`HostHeap::keep`; importing `RETIRE_LEAN` again would add no fix. New upstream
residency behavior can shorten a 64-submission quarantine to 16 on smaller hosts
and uses OS commit floors rather than this job's limit. Those changes are not
enabled. The asynchronous reaper adds another destruction queue, with no local
evidence of a lower peak. Descriptor TablePlan is a possible CPU optimization,
not a remedy for retained backing storage.

Next measurements split completed-but-quarantined, in-flight and idle owners.
They must report busy snapshots as unknown, preserve the 64-submission lifetime
protection, and avoid traversing resources or issuing GPU calls in the sampler.
World rendering and control must be verified independently of interval FPS,
shader compilation success or audio PCM amplitude.
