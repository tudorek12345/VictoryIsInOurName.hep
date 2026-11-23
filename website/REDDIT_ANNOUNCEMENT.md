# I’m building an experimental Leonida fork toward GTA VI on PC — focused on fast, reproducible runtime work

I’m Heperkoo, and I’m working on an experimental fork of Leonida with a clear goal: move toward the first real game-generated frame on PC, then input and playable progress.

Full credit to ItsNotRexed and the Leonida contributors for the original project. My fork is a place for focused experiments, integration and developer handoffs, building on that ongoing work.

## The experience I’m bringing

I’m already working on My Winter Car Multiplayer, my Batman Telltale port, CoD2 co-op and TWD source recovery. That work involves multiplayer synchronization, native engine integration, calling-convention investigation, Godot porting, C++ reconstruction and differential testing.

I use VS Code with Codex for investigation and implementation. I want to bring that practical workflow here: inspect what the runtime actually does, make a targeted change, test it and leave a clear next step.

## How I want to get useful results quickly

- Compare current upstream changes before duplicating work.
- Follow the first reproducible startup or graphics failure.
- Use small probes and reversible experiments to test one hypothesis at a time.
- Reuse valid build/shader outputs and run focused checks between changes.
- Investigate loader/memory, graphics/ABI and reproduction in parallel where they can be separated.
- Keep exact commits, commands, results and the next blocker in every handoff.

The target is the shortest practical route to a real native PC result. Progress will be based on reproducible runs.

**Current status:** the project website, frontend/backend source and developer handoff are available. A real GTA VI frame and playable gameplay have not been verified in this fork. The pinned upstream report reached graphics initialization without demonstrating a draw or presentation in that run; newer upstream work needs to be checked before choosing the next blocker.

If you work with C++, Windows internals, x86/x64 ABIs, memory management, Vulkan or runtime debugging, I’d like to collaborate. Reproducible testing on different GPUs is useful too.

- **Fork:** https://github.com/tudorek12345/Leonida
- **Website:** https://leonida-heperkoo.meshedgoby9.chatgpt.site/
- **Developer handoff:** https://github.com/tudorek12345/Leonida/blob/main/website/public/handoff.md
- **My Discord / MWCMP community:** https://discord.gg/ufXqPcVdVj

— Heperkoo
