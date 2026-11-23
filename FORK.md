# Heperkoo experimental Leonida fork

This fork is a workspace for native PC runtime experiments, integration and reproducible developer handoffs. It builds on [ItsNotRexed/Leonida](https://github.com/ItsNotRexed/Leonida) and its contributors.

- [Project website](https://leonida-heperkoo.meshedgoby9.chatgpt.site)
- [First native frame development handoff](website/public/handoff.md)
- [Website frontend and backend](website/README.md)
- [My Discord / MWCMP community](https://discord.gg/ufXqPcVdVj)
- [Fast experiment workflow and handoff record](docs/FORK_EXPERIMENTS.md)
- [Discord announcement](website/DISCORD_ANNOUNCEMENT.md) · [Reddit announcement](website/REDDIT_ANNOUNCEMENT.md)

## Immediate goal

Advance the real Xbox Series executable through the existing Leonida compatibility runtime toward its first correctly rendered and presented frame on Windows, then toward input and gameplay. A verified rendered game frame has not been demonstrated by this fork.

The initial evidence checkpoint is the [23 November 2026 upstream retail report](https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md). It describes one experiment with locally combined changes and stand-ins, which reached a descriptor-heap assertion before any draw or presentation. Later upstream branches may be further along; reproduce the actual current checkout before selecting the next blocker.

## Ongoing focus

- Reconcile current upstream work and preserve local experiments.
- Trace runtime startup, Xbox API behavior, memory mappings and descriptor semantics.
- Connect CPU writes to the correct GPU resource backing and reach the real submission/presentation path.
- Keep each change testable and leave an exact next step for the next developer.

Heperkoo's ongoing work includes My Winter Car Multiplayer, the Batman Telltale port, [Call of Duty 2 co-op](https://github.com/tudorek12345/CoD2SP-CO-OP) and [TWD source recovery](https://github.com/tudorek12345/decomptwdgame1season). That work provides practical experience with multiplayer synchronization, native engine integration, calling conventions, Godot porting, C++ reconstruction and differential testing.

The aim is the shortest practical route to a real result: reproduce the first failure, test one hypothesis with the smallest useful probe, reuse valid build outputs, run focused checks and record the next exact experiment. Independent investigations can proceed in parallel with clear ownership. See the [experiment workflow](docs/FORK_EXPERIMENTS.md).

## Collaboration

Start with the handoff and the existing contribution rules. Check upstream coordination and active pull requests before duplicating runtime work. Keep upstream measurements separate from results reproduced in this fork. Bring focused code changes, environment details, sanitized outcomes and a repeatable test.

The website adds a responsive frontend, public GitHub activity backend, curated status API and downloadable handoff. GitHub activity is not automatic verification of runtime progress. The website source lives under `website/`; publication is separate from a GitHub commit.

AI-assisted website and documentation implementation. No game files or generated game assets are included. Existing upstream authorship and licensing are preserved.
