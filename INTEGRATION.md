# Runtime integration notes

This repository is the requested tracking source for the Windows D3D12 runtime integration. See the [latest maintainer observations](README.md#reported-boot-progress) and the [PortWatch submission](docs/portwatch-submission.md) for the status and scope of this single effort.

## Runtime history

The original Leonida project by ItsNotRexed and its contributors runs the existing x86-64 code through reimplemented console services and translates console GPU programs for Vulkan. [Upstream credits](README.upstream.md#credits) document the authors and dependencies.

The separate VIctory backend by Marvisak and its contributors uses native D3D12. The integration adds a launcher for choosing the backend, isolates runtime state and carries changes to shader resource views, the compositor and device-loss diagnostics. The [upstream source record](runtimes/victory/SOURCE.json) identifies the revision, license and local changes. The [implementation commit](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) records the shader, cache and diagnostic work.

## Development handoff

Start with the [sanitized runtime report](tracking/runtime-progress.json) and [reproduction checklist](docs/EXPERIMENTS.md). Record the backend, exact build, GPU and driver, observed output and next unresolved failure. Keep runtime measurements tied to the run that produced them. Use the [contribution guide](CONTRIBUTING.md) and [repository instructions](AGENTS.md) before changing shared code.
