# Prepared Series X and Series S comparison, 26 November 2026

**The first mission is not verified playable.** Both fresh-profile runs reached
the memory guard. Series S produced a recognizable rendered character close-up,
but the subsequent logged intervals were 1.3–2.4 FPS and no gameplay input was
sent. This is progress in visible rendering, not a completed gameplay test.

This report covers the two completed runs ending `0331fdc6` and `b28a27fe`, plus
their three preparation runs. It does not describe later experiments. Captures,
audio, caches, package files and raw logs remain private; only authored
observations and measurements are included here.

Both title runs used clean source `8f6f742cfcd324501d7a11f9926d5ff40dcacdec`, runtime
SHA-256 `DA612AE0D2B6ED570C09162CE5E4398CDA7A86427165183E6BD8D04DACA1B8C8`, the
Radeon RX 9060 XT 16 GB and driver 32.0.32029.2010. The reported host is a Ryzen 7
5700X with 32 GB RAM. Both used hardware rendering, queued submission, light DRED,
one pipeline worker, 256 KiB shadow windows and disabled mapped-VRAM buffer
uploads. The title-job hard cap was 22 GiB, with termination requested 512 MiB
below it; the system commit reserve remained 4 GiB. No physical-memory reserve
was configured for these particular runs. These are recorded settings, not a
recommendation to increase memory exposure.

## Preparation completed for the selected pipelines

All three preparations selected 1,715 entries from a book containing 83,555
known pipelines, reopened each selected entry, and completed with zero refused
pipelines and zero child failures. This is not compilation of every pipeline
the title can encounter. The shared cache uses translated-content identity and
the driver-specific pipeline library; the final executable's exact identity was
then checked when seeding each title run.

| Preparation run suffix | Source / console | Newly made / loaded | Launcher elapsed | Peak job commit |
|---|---|---:|---:|---:|
| `b6a02f20` | `988ed8f`, Series X | 884 / 831 | 1,533.87 s | 916,004,864 bytes |
| `5155ba61` | `8f6f742`, Series X | 0 / 1,715 | 38.61 s | 453,300,224 bytes |
| `5e22eda4` | `8f6f742`, Series S | 0 / 1,715 | 40.68 s | 453,332,992 bytes |

The first preparation used the preceding binary; the final two reopens used
the tested executable after the pending-upload ownership correction. Each used
one library writer and a 6 GiB job cap, exited successfully, and restored access
rules on all 151 original-package paths. Each title run seeded 4,067 cache files
and four private driver-cache files. The cache was demonstrably reused: the
Series X title run reported 1,735 loaded pipelines and only one newly made.
Series S later encountered additional world pipelines: its last saved-library
event reported 1,681 loaded and 77 made, with 21 still being made at the final
frame sample. Additional unseen pipeline work remains possible after a warm.

## Compare the observed phases, not the whole-run median

| Evidence | Series X `0331fdc6` | Series S `b28a27fe` |
|---|---|---|
| Visible intro | Rockstar intro capture at 30 FPS | Valid restored-window Rockstar logo capture at 30 FPS |
| Earlier captures | Intro visible; later capture black, caption 18 FPS | First two captures were occluded by another application and are invalid as game-image evidence |
| Later rendered scene | No valid world image captured before termination | Recognizable character close-up at 10:59:54.498Z; caption 3 FPS, 363.5 ms, 2,255 draws |
| Later diagnostic intervals | One final sample: 1.5 FPS, 660.2 ms/frame | Seven samples at 10:59:43–11:00:18Z: 1.3–2.4 FPS, sample median 1.9 |
| Gameplay input / mission completion | Unverified | No gameplay input sent; mission identity, control and completion unverified |
| Final output size | 3840×2160 | 1920×1080 after multiple output changes |
| Logged intermediate depth targets | 2560×1440 | 1280×720 and 1920×1080, plus other smaller/shadow targets |

Series S also enabled its `MenuPicture` presentation path, unlike Series X,
and the window was restored to the foreground at 10:58:53.105Z. It is therefore
not a resolution-only or matched-scene performance comparison. The longer run
does not establish a proportional stability improvement. The all-sample median
of 30 FPS includes intro/background intervals and must not be called gameplay FPS.
Capture-title values and multi-frame log intervals also describe different
sampling windows.

Series S initially created a 1080p swapchain, switched to 4K at 10:57:29.106Z,
to 1080p at 10:58:55.920Z, back to 4K at 10:58:56.921Z, and finally to 1080p at
10:59:33.299Z. The advertised guest display remained 4K. The summary parser now
records creation and resize history separately from the guest display report;
its latest output size is not a claim about the entire run or every internal pass.

## Remaining rendering and preparation costs

Series X's final 462 dropped dispatches per frame were classified as disabled
ray-tracing structure-builder stages, with zero pipelines being made. The
builder is deliberately off unless `VICTORY_BVH_BUILDER=1`: incomplete stages
can write invalid offsets into neighboring title objects. It was not enabled
for this test. The guard rejects those dispatches before host-pipeline acquisition
and resource binding, so the dispatch itself does not perform the later texture,
buffer and table preparation. Separate resource creation and other passes still
run; their cost is not attributable to the disabled builder from these counts.
Series S reported both disabled builder stages and pipelines still being made.

Series X's last interval recorded 122.5 ms preparing submissions, including
58.7 ms in list steps and 55.3 ms preparing card-memory copies. Later queue
telemetry showed up to 62 queued submissions. Series S preparation ranged up
to 715.6 ms in its later intervals. These counters overlap and use different
reporting windows; they cannot be added to form a new frame duration.

The historical aggregate labelled "on the GPU" measures **CPU fence/landing
waiting**, not hardware GPU execution duration. The diagnostic summary preserves
`gpuMs` for compatibility and adds the explicit `runtimeGpuWaitMs` alias and
timing interpretation. Requesting GPU timestamp diagnostics would not change
the meaning of that aggregate. Neither run enabled those timestamp diagnostics.

The repeated device-slot warnings at byte offsets `0x1c8`/`0x218` also require
care: XCL identifies slots 57/67 as console-driver pipeline-cache deserialization
and documents creation from descriptions as the fallback. It likewise returns
`E_NOTIMPL` for the cache. The 16,384/2,048 Series X invocation checkpoints do
not prove that many unique pipelines or render passes were missing. Actual
fallback execution for each request remains unverified. See the reference
[XCL implementation](https://github.com/xcl-dev/xcl/blob/4178e888c0b5be50a2887eda45cdb832763b68a4/crates/xcl/src/hle/d3d12x/device_x.rs#L577).

## Memory guard and cleanup

| Measurement | Series X | Series S |
|---|---:|---:|
| Final runner elapsed | 71.500 s | 173.766 s |
| Launcher elapsed | 77.91 s | 181.36 s |
| Peak job commit | 23,247,933,440 bytes | 23,194,882,048 bytes |
| Commit at guard trigger | 23,180,140,544 bytes | 23,182,458,880 bytes |
| Last timed available physical RAM | 809,041,920 bytes | 1,390,850,048 bytes |
| Last timed shadow count / bytes | 9,304 / 4,081,361,726 | 8,501 / 3,580,183,254 |
| Last timed texture count / bytes | 27,764 / 5,628,035,072 | 34,393 / 5,085,331,456 |
| Last timed host-list count | 1,243 | 1,460 |
| Runtime result before cleanup | 126, memory guard | 126, memory guard |
| Launcher result | 126 | 125, subsequent profile-cleanup failure |

The timed snapshots are not exact stop-time samples, and their allocation
categories overlap. Different scenes and durations prevent assigning the
differences to a single patch. Neither run demonstrates a solved memory limit.
The pending-upload correction reported 0.0 reclaimed uploads/frame in all 59 X
and 150 S interval samples. Those rounded rates do not establish an exact
cumulative count or measured memory savings; its ownership regression tests
remain separate evidence.

Both runs restored all 151 original-package access paths. Series S's initial
`DeleteAppContainerProfile` failed with sharing violation `0x80070020` after the
runtime had already stopped. A recorded manual API retry, with runtime processes
absent, returned `S_OK` at 11:02:10.555Z. This recovery does not erase the original
cleanup failure or reclassify the runtime stop as successful completion.

## Audio and Windows events

Series X's first 45 seconds contained recorded signal at -30.33 dBFS RMS.
Series S's first 45 seconds were effectively silent (-96.71 dBFS, peak one
16-bit quantization step); 45–90 seconds measured -30.35 dBFS and 135–173 seconds
measured -28.90 dBFS. The early background/occluded interval and later signal
must not be collapsed into a claim that logo audio worked. These measurements
do not establish glitch-free playback or perceptual audibility.

The queried Windows event windows were 10:52:10–10:54:10Z for X and
10:57:20–11:02:20Z for S. Each had zero Display 4101 and Application 1000 events.
This is no observed matching reset/crash event in those windows, not proof of
general driver health. The recorded stops were the memory guard and, for S,
the separate cleanup failure.

## Reviewed references for this build

The earlier source review checked avatarmanz `9576c45`, fxceless `f6a09d3`,
Belobug `81ebb7b` and DexNom `64bd58f`; these are historical reviewed revisions,
not claims about today's latest heads. Selected changes and authored validation
are recorded in [the rendering review](upstream-rendering-review-20261126.md),
including the narrow legacy-FMA correction, descriptor `TablePlan` adaptation
from avatarmanz `46e329`, and bounded sparse-texture/remap fixes. The confirmed
pending-upload leak and its limited measured scope are described
[separately](pending-upload-leak-20261126.md). No broader upstream merge or
additional rendering fix is implied by this run comparison.

The next useful evidence is responsive control in a visible scene under the
existing guards, alongside measurements that distinguish new pipeline work,
CPU preparation and retained allocation ownership. No raw captures or game
data are needed in the public progress record.
