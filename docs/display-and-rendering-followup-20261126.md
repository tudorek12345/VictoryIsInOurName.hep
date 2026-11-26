# Display request and world-entry check, 26 November

The latest resolution attempt did **not** lower the observed rendering sizes.
Run `original-20261126-015434-7397c202` used the same clean runtime source
`f09f18e` and executable as the preceding completed-list comparison.

| Observation | Result |
| --- | --- |
| Guest display requested and reported | 1920 x 1080 |
| Copied profile fullscreen setting | 1920 x 1080; one file updated |
| Actual swapchain | 3840 x 2160 |
| Observed intermediate targets | 2560 x 1440; this is not an exhaustive pass inventory |
| Final logged frame interval | 1.8 FPS, 545.4 ms/frame; 334.2 ms preparation |
| Final logged missing-pipeline draws | 2,970, with five pipelines being made |
| Peak job commit | 23,329,865,728 bytes |
| Stop | Job-memory notification, exit 126; final runner sample at 77.719 seconds |
| Cleanup | Normal; all 151 package access paths restored |

The private window capture near 75 seconds shows heavily obscured, blurred
geometry. Its caption reads 1 FPS and 1,409.1 ms/frame. Window captions and the
periodic log summarize different intervals. Neither establishes player control,
mission progress or a stable gameplay frame rate.

The launcher supplied no mission-selection arguments. It reused a copy of the
normal profile, with scheduled Enter inputs and longer W/D holds. No mission
identifier, objective or causal response to those movement inputs was verified.
This is **world entry**, not a verified first-mission test. The appearance of a
character and street cannot establish which mission is active.

The prior `Test720p` flag was ignored by the active runtime. It now selects the
supported guest display-mode option, and the launcher updates only an isolated
copy of the profile. Unsupported mission-tracing requests are rejected; even
the older runtime's trace describes GPU commands, not mission identity.
The cache-seeding helper now reads the prior run's actual state directory rather
than assuming its caches live in `output`. This comparison seeded 2,051
shader/pipeline files and four private driver-cache files. Thirty focused
launcher checks passed.

Diagnostics now record requested display mode and observed swapchain separately,
including an explicit mismatch. All 26 summary-parser checks passed. A matching
swapchain would still not prove that every internal pass used that resolution.

The runtime logged no device removal or allocation failure. Queries found no
matching Display 4101 or Victory/title Application 1000 events through 30 seconds
after exit. The first 45 seconds of captured stereo PCM were non-silent at
48 kHz, with peak 9,797 and RMS 1,029.83. These checks do not prove driver health,
correct speaker output or audio synchronization. Raw logs, captures and audio
remain local.

4K targets can add GPU and memory cost, but this run did not measure that cost
against genuinely smaller targets. Recorded CPU preparation and submission stalls
remain substantial. No resolution-based FPS or memory saving is claimed, and the
memory guards and Windows TDR settings remain unchanged.
