# Leonida · Heperkoo — progress update

**Published 23 November 2026 · Maintainer-reported results**

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
