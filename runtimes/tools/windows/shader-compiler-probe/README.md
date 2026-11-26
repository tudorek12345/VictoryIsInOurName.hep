# Synthetic D3D12 compiler probe

A source-only reproducer for a Radeon driver compiler access violation involving dynamically indexed buffer resources. See [RESULTS.md](RESULTS.md) for the tested matrix and its limits.

Build with the installed Windows x64 MSVC and SDK:

```powershell
& .\build.cmd
python .\build_variants.py
```

The C++ host accepts `SHADER.dxil` and an optional root-layout argument: `--explicit`, `--array16`, `--array`, or `--mixed-array`. It deliberately selects AMD device `1002:7590`, logs compilation results and faults, and never creates a command queue or dispatches work. The default layout uses 64 b0 constants and directly indexed view/sampler heaps. Array modes use 62 constants plus two descriptor tables to remain within the 64-DWORD root budget. Mixed mode also permits direct heap indexing.

The variant builder compiles only the accompanying authored `probe.hlsl` and records hashes and arguments in local `variants.json`. Its Windows SDK DXC path is explicit and can be adjusted for another installed SDK. Build outputs and local observations are ignored by Git.

`Run-Probe.ps1` integrates with the project's existing guard. By default it looks for sibling `isolated-run/isolated-run-guard.exe`; use `-GuardPath` when the guard is elsewhere. It copies a selected synthetic variant into a unique stage and enforces a 60-second maximum, 4 GiB process/job commit cap, 3 GiB free physical reserve and 4 GiB system-commit reserve. It verifies the variant's hash. Run one probe at a time, coordinated with other GPU tests. The guard is required; this subset does not bundle it or silently run unguarded.

```powershell
& .\Run-Probe.ps1 -Variant baseline -GuardPath C:\work\isolated-run\isolated-run-guard.exe
& .\Run-Probe.ps1 -Variant query-lane-identity -GuardPath C:\work\isolated-run\isolated-run-guard.exe
```

Removing a query or wave operation is a diagnostic control, not a valid production fix. A constant lane-zero read is not a general replacement for the first active lane. A proposed query-index identity still needs behavioral tests and careful handling of pixel helper lanes. No game inputs, generated game shaders, executable binaries, device dumps or raw runtime logs belong in this source subset.
