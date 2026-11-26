# Checked 1080p output, 26 November 2026

**The output reduction worked; the first mission is still not verified playable.**
The fresh Series X test created a 1920×1080 swapchain and a 1280×720 internal
depth target. Later rendering intervals fell to 2.2–3.1 FPS and the existing
memory guard stopped the runtime. No valid world capture was obtained before
termination, no gameplay input was sent, and mission identity remains unknown.

This report covers preparation `033001-ec0c62cb` and title run
`033111-8cad5208`. Both used clean source
`f690d6fbd6e879cbc185c4abb4cb5fca52dc64ad`, executable SHA-256
`0C3B6914C2FFCDB26B5674DF380905F6ECC525308CC346B370C83D79DF4F2C5E`,
the Radeon RX 9060 XT 16 GB and driver 32.0.32029.2010. The maintainer reports
a Ryzen 7 5700X and 32 GB system RAM. Captures, audio and raw logs remain private.

## What was applied

The optional output patch verifies the original executable identity and both
mapped patch footprints before changing the live image. It calls the title's
existing size setter. Reduced output retains the original pool capacity and
an unsigned capacity check; it does not bypass the allocator's bounds checks.
Native 4K retains the original final pool check. Ten focused loader tests passed,
including transaction failures, unsigned boundaries and an actual Windows
memory-protection test. These tests alone are not gameplay validation.

The title run separately confirmed the applied 1920×1080 output request and
1920×1080 swapchain creation. There were no subsequent logged resizes. The
advertised guest display still reported 3840×2160, which is a separate value.
A later aspect-ratio depth target was 1280×720; square shadow targets included
2048×2048. The patch leaves native render-scale logic unchanged, so every pass
must not be described as rendering at the output size.

## Preparation and observed frame intervals

The final preparation selected and processed 1,715 pipelines from the known
pipeline book, loaded all 1,715, made zero new pipelines, and completed with
zero refused pipelines and zero child failures. It took 48.46 seconds including
the launcher, peaked at 453,230,592 bytes of job commit under a 6 GiB cap, and
exited successfully. All 151 original-package access paths were restored.
The title run then seeded 4,067 cache files and four private driver-cache files.
This was preparation of the selected set, not every pipeline the title can use.

The first 13 logged frame intervals contained only 3–28 draws/frame. Twelve
were 29.3–30.1 FPS and one was 15.9 FPS. They do not establish sustained loading
performance or gameplay FPS. Later samples were:

| UTC timestamp | FPS | Frame time | CPU preparation | Draws/frame | Pipelines being made |
|---|---:|---:|---:|---:|---:|
| 11:32:37 | 0.4 | 2,821.3 ms | 626.0 ms | 327 | 0 |
| 11:32:43 | 3.1 | 318.6 ms | 260.7 ms | 3,396 | 0 |
| 11:32:48 | 2.7 | 372.2 ms | 196.6 ms | 1,628 | 2 |
| 11:32:53 | 2.2 | 450.8 ms | 249.1 ms | 2,339 | 8 |

The last saved pipeline-library event was earlier, at 11:32:06, with 1,668
loaded and one newly made pipeline. Later recording-thread aggregates included
159.2 and 455.3 ms waiting for pipelines. Additional encountered pipeline work
therefore remained after preparation; the earlier save is not a final total.
Early asynchronous pipeline counts must not be counted as distinct cache misses.
Deliberately disabled ray-tracing builder stages were classified separately.

The aggregate historically labelled “on the GPU” is **CPU fence/landing wait**,
not hardware GPU execution time. Recording-thread totals and preparation
subtotals overlap and cannot be added to form another frame duration.

Compared with [the earlier fresh-console runs](prepared-console-comparison-20261126.md),
this build also includes the BC7 correction and different cache history.
Reached workloads and capture coverage differ. Smaller output is verified,
but the runs are not a matched-scene, resolution-only performance experiment.

## Memory stop and cleanup

The title retained hardware rendering, queued submission, light DRED, one
pipeline worker, 256 KiB shadow windows and disabled mapped-VRAM buffer uploads.
The 22 GiB hard job cap, 512 MiB job reserve and 4 GiB system commit reserve
remained in place. No physical-memory reserve was configured for this test.
These are recorded conditions, not a recommendation to increase exposure.

The job reserve triggered at 95.547 seconds, with 23,110,279,168 committed bytes
against the 23,085,449,216-byte stop threshold. Peak job commit was
23,146,758,144 bytes, below the 23,622,320,128-byte hard limit. The last runner
sample recorded 23,098,843,136 title-private bytes and a 17,499,172,864-byte
working set. A late memory sample had only 581 MiB of available physical RAM;
DXGI then reported 7,193 MiB local and 6,917 MiB shared GPU memory use.
These accounting categories overlap and must not be summed.

The runtime result was 126 from the memory guard. All 151 original-package
access paths were restored, then profile deletion failed with sharing violation
`0x80070020`, producing launcher result 125 after 102.94 seconds. This separate
cleanup failure must not be called a gameplay crash or successful completion.
Any later recovery does not erase the initial result.

The exact stale profile was subsequently removed successfully after its recorded
processes were confirmed absent. The runner now retries only sharing violations
for up to 30 seconds of backoff, instead of the previous 4.875 seconds. It logs
attempts and elapsed time; permanent errors remain cleanup failures, and a
successful cleanup preserves the original runtime result. Ten deterministic
policy tests and five isolated stub runs passed (normal exit, timer, physical
reserve, system commit reserve, job reserve). This repairs cleanup handling;
it does not extend the title's memory limit or change GPU resource lifetimes.

## Audio and Windows events

The local recording contains 94.501 seconds of stereo 48 kHz, 16-bit PCM.
RMS levels were −30.35 dBFS for 0–45 seconds, −43.65 dBFS for 45–90 seconds,
and −25.52 dBFS for the remainder. No sampled one-second bucket was entirely
zero; the final bucket was partial. This confirms recorded signal, not correct
logo audibility, synchronization or glitch-free playback.

A successful Windows event query for 11:31:10–11:35:00Z found zero Display 4101
and zero Application 1000 events. The runtime log also had no recognized
device-removal or allocation-failure messages. This does not establish general
driver health; the recorded termination was the memory guard.

Responsive control, visible mission context, stable rendering and reduced
allocation pressure remain the next required evidence. No world screenshot or
mission completion is claimed from this run.
