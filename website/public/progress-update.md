# Leonida · Heperkoo — progress update

## Recent changes — 24 November 2026, 03:00 EST (UTC−05:00)

Integrated VIctory raw bindless SRV consistency and typed UINT16 UAV fixes, a 3:1 compositor fast path, concurrent shader-cache cold-fill coalescing, and caller/fence/Present device-loss diagnostics. **303 serial Rust tests pass, 5 ignored**; optimized diagnostics build passes. Synthetic tests are not gameplay verification.

On **RX 9060 XT 16 GB / Ryzen 7 5700X / 32 GB DDR4**, a short hardware **intro-only** run held **30 FPS / 33.3 ms**. WARP software intro remains around **10 FPS / 100 ms** without capture. Neither result measures gameplay.

- [x] Trace the single-list device removal and inspect the working-copy source and run evidence.
- [x] Distinguish guest and presenter failure paths and retain the exact fence phase in diagnostics (instrumentation implemented; crash attribution pending).
- [ ] **In progress:** build/test serially, bounded debug repro and original-file protection. Build/tests and 151-path ACL restoration passed; the latest requested debug run lacked the debug layer and ended after 28.42 seconds before world entry.
- [ ] Fix a demonstrated remaining defect and verify controllable hardware gameplay.

**Left off:** WARP world-transition device removal remains unresolved (0x887A0005 at 184.84 seconds in the previous completed repro). Next: reproduce with caller/fence diagnostics and establish the failing path before fixing it. Game captures, raw logs, extracted shaders and package files stay local.

[Source and complete recent notes](https://github.com/tudorek12345/Leonida#readme) · [Same-source mirror](https://github.com/tudorek12345/VictoryIsInOurName.hep) · [Sanitized results](https://github.com/tudorek12345/Leonida/blob/main/tracking/runtime-progress.json) · [PortWatch review request](https://github.com/4lwayz/portwatch-vi/issues/17)

The two repositories represent **one effort**. PortWatch is a third-party tracker: a submitted update does not establish a listing, score, approval or live-site publication.

## Historical report — published 23 November 2026

The RX 9070 XT observations below are a separate historical maintainer report, not the latest RX 9060 XT test.

## Join the progress showcase

**[GTA VI port progress showcase — join the Discord event](https://discord.com/events/1459617753907331094/1574557419596677260)**

Wednesday, 25 November 2026. Open the event in Discord for your local start time and current event details. Join for the stream, showcases, development updates and build progress.

[View the supplied event screenshot](images/showcase-discord.png).

The progress stream is scheduled for 25 November. The separate seven-day target for a **possible reproducible build showcase** remains 30 November 2026 at 19:55:45 CET (Europe/Prague); it is a target, not a release commitment.

## Latest reported runtime progress

One tested machine: **Windows 11 · AMD RX 9070 XT**. These are the maintainer’s supplied results, not an independently reproduced run or a compatibility claim for other hardware.

| Stage | State |
| --- | --- |
| Boot and first-boot screens: accessibility, language, settings and legal | Works, **30 fps** |
| Intro video with sound | Works |
| Start screen, profile and saves | Works |
| Loading into the world | Works, **about 50 seconds** |
| The world / first mission’s intro | Reached; **the picture is black and the host GPU fails within seconds** |

The 30 fps report applies to the first-boot screens. Stable rendered gameplay has not been demonstrated by this report. The exact cause of the GPU failure has not been established here.

## Ongoing work and the next handoff

The next milestone is repeatable world entry with correct rendering and a stable GPU. Capture the exact source revision, local changes, package/build identifier, GPU driver, reproduction command and failure diagnostics so another developer can test the same result. Keep original game files and raw traces local.

## Collaboration credit

**Huge respect to Marvis for the ongoing code research and collaboration. This research programme is committed to working under applicable law.**

Leonida’s foundation remains the work of [ItsNotRexed and the upstream contributors](https://github.com/ItsNotRexed/Leonida). Heperkoo’s fork is an ongoing space for experiments, integration, testing and developer handoffs.

[Project website](https://leonida-heperkoo.meshedgoby9.chatgpt.site/) · [GitHub fork](https://github.com/tudorek12345/Leonida) · [Developer handoff](handoff.md)
