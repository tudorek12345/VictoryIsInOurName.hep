# Runtime integration notes

This repository is the requested tracking source for the Windows D3D12 runtime integration. See the [latest maintainer observations](README.md#reported-boot-progress) and the [PortWatch submission](docs/portwatch-submission.md) for the status and scope of this single effort.

## Runtime history

The original Leonida project by ItsNotRexed and its contributors runs the existing x86-64 code through reimplemented console services and translates console GPU programs for Vulkan. [Upstream credits](README.upstream.md#credits) document the authors and dependencies.

The separate VIctory backend by Marvisak and its contributors uses native D3D12. The integration adds a launcher for choosing the backend, isolates runtime state and carries changes to shader resource views, the compositor and device-loss diagnostics. The [upstream source record](runtimes/victory/SOURCE.json) identifies the revision, license and local changes. The [implementation commit](https://github.com/tudorek12345/VictoryIsInOurName.hep/commit/298042a3388e400464824d246ed3ec265c238345) records the shader, cache and diagnostic work.

## Development handoff

Start with the [sanitized runtime report](tracking/runtime-progress.json) and [reproduction checklist](docs/EXPERIMENTS.md). Record the backend, exact build, GPU and driver, observed output and next unresolved failure. Keep runtime measurements tied to the run that produced them. Use the [contribution guide](CONTRIBUTING.md) and [repository instructions](AGENTS.md) before changing shared code.

## Series S presentation candidate

The [Series S patch](runtimes/patches/victory-7900xtx-series-s-present.patch) applies to the [7900 XTX fork at `e2a28ec7`](https://github.com/avatarmanz/VIctory-7900XTX/tree/e2a28ec70632f5112be085abfa7d0a557b25e8d8). It reads the full display-plane record, uses completed draw evidence to choose a single 4K menu target, and avoids redundant copy-source transitions. `git apply --check` passed against the matching source snapshot. The selector regression and the regular and optimized diagnostics build checks passed.

The isolated AMD test built the diagnostics profile, selected `--console series-s`, and set `VICTORY_SERIES_S_MENU_PICTURE=1`, `VICTORY_LATE_WAIT=0`, `VICTORY_THIN=0` and `VICTORY_ASYNC_SUBMIT=0`. Those settings keep the selector on the synchronous submission path. The original package and raw runtime artifacts stay local. The test demonstrated the menus and intro. World rendering and input remain open.
