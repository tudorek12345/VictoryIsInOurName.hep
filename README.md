<div align="center">
  <img src="assets/logo.png" alt="Leonida" width="160">

# Leonida · Heperkoo

**An experimental fork working toward GTA VI running natively on PC.**

Fast, focused experiments. Reproducible progress. Clear developer handoffs.

[**Project website**](https://leonida-heperkoo.meshedgoby9.chatgpt.site/) ·
[**My Discord**](https://discord.gg/ufXqPcVdVj) ·
[**Developer handoff**](website/public/handoff.md) ·
[**Upstream Leonida**](https://github.com/ItsNotRexed/Leonida)

</div>

---

## What I’m building

I’m **Heperkoo** ([tudorek12345](https://github.com/tudorek12345)). This is my working fork of Leonida for reverse engineering, runtime integration, testing and collaboration.

The goal is the **shortest practical route to a real game-generated frame on PC**, followed by input and playable progress. I want each experiment to answer a concrete question, remove the next measured blocker and leave work another developer can continue immediately.

Leonida executes the game’s existing x86-64 CPU code through reimplemented console services, with console GPU programs translated for Vulkan. Full credit for that foundation belongs to **ItsNotRexed and the upstream Leonida contributors**.

## Current status

| Area | Status |
| --- | --- |
| Fork website, frontend and backend | Published · [open the site](https://leonida-heperkoo.meshedgoby9.chatgpt.site/) |
| Developer handoff and experiment workflow | Available · [handoff](website/public/handoff.md) · [experiment notes](docs/FORK_EXPERIMENTS.md) |
| Runtime work in this fork | Experimental; the next pass starts by reproducing the current checkout |
| Real game frame and gameplay in this fork | **Not yet verified** |
| Release date | No committed date; milestones depend on measured results |

The [pinned upstream retail experiment from 23 November 2026](https://github.com/ItsNotRexed/Leonida/blob/8e3c7c72b79cabfbe8a2059fce56a5b99d6ddb51/docs/retail_boot_chain.md) reached graphics initialization and a descriptor-heap assertion, with no draw or presentation demonstrated in that run. It used locally combined changes and stand-ins. Later upstream work may be further along, so this is a reference checkpoint rather than a claim about the latest branch.

## Experience I bring

My ongoing work already involves multiplayer systems, native engine investigation, porting and testing:

| Project | Relevant experience |
| --- | --- |
| **My Winter Car Multiplayer (MWCMP)** | Multiplayer state synchronization, mod integration, Steam/LAN transport and debugging interactions across running instances |
| **Batman Telltale port** | Godot porting work, scene and asset integration, rendering and visual iteration |
| **[CoD2SP-CO-OP](https://github.com/tudorek12345/CoD2SP-CO-OP)** | Native x86 runtime integration, exact-build engine calls, calling conventions, signature checks and host-authoritative UDP |
| **[TWD source recovery](https://github.com/tudorek12345/decomptwdgame1season)** | C++ reconstruction experiments, hybrid native execution and differential testing |

I work in **VS Code with Codex**, using AI assistance for investigation, implementation and parallel analysis. The useful part is closing the loop: inspect the behavior, make a focused change, run it, and document what actually happened. These projects remain ongoing work.

## How I want to move quickly

1. **Start from current upstream work.** Compare the actual commits and active work before implementing a fix somebody already has.
2. **Follow the first reproducible failure.** Use startup traces and small probes to choose the next loader, memory, ABI or graphics experiment.
3. **Change one behavior at a time.** State the hypothesis, expected result and rollback before changing shared runtime code.
4. **Keep the feedback cycle short.** Reuse valid shader/build outputs, skip optional full asset exports during boot work, and run the tests relevant to the changed behavior.
5. **Parallelize independent questions.** Loader/memory, graphics/ABI and reproduction can move together when ownership and interfaces are clear.
6. **Keep only demonstrated progress.** Compare before and after, preserve useful negative results, then hand off the exact next experiment.

A passing synthetic test, a skipped assertion or a successful API return is a different milestone from a real game frame. The [experiment workflow](docs/FORK_EXPERIMENTS.md) keeps those distinctions explicit.

## Get the fork

```powershell
git clone --recursive https://github.com/tudorek12345/Leonida.git
cd Leonida
```

Read the [build prerequisites and full technical guide](README.upstream.md#how-to-build) before starting. For a runtime-focused pass with the required local inputs and toolchain already available:

```powershell
python -I make_game.py --game "D:\Games\GTA-VI-package" --stages check,shaders,runtime --out "D:\Leonida\runtime" --work "D:\Leonida\work"
```

The repository contains source and tools. Supply your own locally readable game files; keep game content and generated artifacts outside Git. The [boot runbook](docs/boot.md) and [developer handoff](website/public/handoff.md) cover the next stages.

## Collaborate

**[Join my Discord / MWCMP community](https://discord.gg/ufXqPcVdVj)** for discussion, coordination and project updates. This is my existing development community.

For changes that need to stay traceable, use this fork’s [pull requests](https://github.com/tudorek12345/Leonida/pulls). Useful contributions include C++ runtime work, Windows internals, calling-convention analysis, memory behavior, Vulkan/graphics integration and reproducible GPU testing.

Bring a commit, a specific question, the commands you ran, the result and the next blocker. Check [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md) and current upstream coordination before overlapping runtime work.

## Project links

| Resource | What it contains |
| --- | --- |
| [Project website](https://leonida-heperkoo.meshedgoby9.chatgpt.site/) | Overview, development priorities, repository activity and collaboration |
| [Fork notes](FORK.md) | Scope, ongoing work and attribution |
| [Developer handoff](website/public/handoff.md) | End-to-end brief for the next runtime investigation |
| [Experiment workflow](docs/FORK_EXPERIMENTS.md) | Fast iteration loop and a reusable handoff record |
| [Website source](website/README.md) | Frontend, backend, local development and deployment notes |
| [Discord announcement](website/DISCORD_ANNOUNCEMENT.md) | Copy-ready community update |
| [Reddit announcement](website/REDDIT_ANNOUNCEMENT.md) | Copy-ready public introduction |
| [Technical documentation](docs/README.md) | Runtime, formats, graphics and validation |
| [Inherited technical guide](README.upstream.md) | Preserved upstream build/platform details and historical status notes |

## Credits and license

**Leonida was created by [ItsNotRexed](https://github.com/ItsNotRexed/Leonida) and its contributors.** This fork builds on their work. Original attribution, the [upstream dependency and artwork credits](README.upstream.md#credits), and third-party licenses remain applicable.

GPLv3 or later — see [LICENSE](LICENSE). Website and documentation work is AI-assisted.

Independent community research; not affiliated with Rockstar Games, Take-Two Interactive or Microsoft.
