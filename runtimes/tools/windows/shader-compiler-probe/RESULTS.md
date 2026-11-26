# Synthetic AMD shader compiler observations

Measured on a Radeon RX 9060 XT (16 GB), driver 32.0.32029.2010, November 25, 2026. The small standalone tool calls `CreateComputePipelineState` only, with no GPU command submission or dispatch. Each process ran in a zero-capability AppContainer under a 4 GiB commit cap, 3 GiB free-physical-memory floor, 4 GiB system-commit floor and 60-second timeout.

All inputs here are authored synthetic HLSL. No original game shader, binary, asset or runtime dump is included.

The baseline and the no-wave case fail at the same `amdxc64.dll+0x861b9f` instruction, reading address `0x8` with `rcx=0`. Their first nine captured module-relative stack addresses match. Changing wave size, removing wave-first, changing its lane selection or conservatively annotating the original resource index as nonuniform does not remove that failure.

The dimensions-only cases pass, as do the load-only cases. Combining a dimension query and a load through the same root-uniform dynamically indexed buffer reproduces the failure for raw SRVs, typed SRVs and raw UAVs in the tested forms. A single explicitly bound register passes; finite and unbounded dynamically indexed arrays still fail. This is more specific than a general failure of `GetDimensions` or wave operations.

Keeping the query and load on distinct resource handles by introducing a same-lane wave read into only the query index passes in the synthetic test. It keeps each active lane's index unchanged. The thread-varying baseline also passes; therefore the varying-index comparison checks compatibility with that form and does not by itself demonstrate a failure-to-success transition. Pixel helper-lane behavior and full emulator behavior require separate validation.

The two simple split-nonuniform source variants were coalesced to the same DXIL by DXC, so they were not accepted as distinct-handle experiments. Mixed table/heap variants are prepared but were not executed in this matrix.

| Synthetic case | Pipeline creation | Fault |
|---|---|---|
| `baseline` | Access violation | amdxc64.dll+0x861b9f |
| `no-wave` | Access violation | amdxc64.dll+0x861b9f |
| `no-dimensions` | S_OK (3.478 ms) | none |
| `load-only` | S_OK (2.845 ms) | none |
| `threads32` | Access violation | amdxc64.dll+0x861b9f |
| `wave64` | Access violation | amdxc64.dll+0x861b9f |
| `wave32` | Access violation | amdxc64.dll+0x861b9f |
| `lane-at-zero` | Access violation | amdxc64.dll+0x861b9f |
| `lane-at-first-active` | Access violation | amdxc64.dll+0x861b9f |
| `lane-at-first-active-no-dimensions` | S_OK (3.428 ms) | none |
| `nonuniform-index` | Access violation | amdxc64.dll+0x861b9f |
| `nonuniform-source` | Access violation | amdxc64.dll+0x861b9f |
| `nonuniform-source-no-dimensions` | S_OK (2.958 ms) | none |
| `explicit-registers` | S_OK (3.207 ms) | none |
| `explicit-registers-no-wave` | S_OK (2.504 ms) | none |
| `dimensions-only` | S_OK (3.095 ms) | none |
| `typed-srv-dimensions-only` | S_OK (3.143 ms) | none |
| `raw-uav-dimensions-only` | S_OK (2.778 ms) | none |
| `typed-srv-dimensions-load` | Access violation | amdxc64.dll+0x861b9f |
| `raw-uav-dimensions-load` | Access violation | amdxc64.dll+0x861b9f |
| `raw-srv-finite-array` | Access violation | amdxc64.dll+0x861b9f |
| `raw-srv-unbounded-array` | Access violation | amdxc64.dll+0x861b9f |
| `raw-uav-finite-array` | Access violation | amdxc64.dll+0x861b9f |
| `raw-uav-unbounded-array` | Access violation | amdxc64.dll+0x861b9f |
| `split-dimension-wave-index` | S_OK (3.605 ms) | none |
| `split-load-wave-index` | S_OK (2.96 ms) | none |
| `query-lane-identity` | S_OK (3.315 ms) | none |
| `varying-index-baseline` | S_OK (3.057 ms) | none |
| `query-lane-identity-varying` | S_OK (3.354 ms) | none |
| `query-lane-identity-dimensions-only` | S_OK (3.606 ms) | none |

Compiler success does not establish numerical equivalence, rendered output, stable gameplay, or absence of other driver bugs. These results motivate a narrow query-only translation workaround while retaining dimensions, loads, descriptor bounds and resource indices.

## Cache reuse follow-up

`build-cache-stress.py` authors a 2,048-branch compute shader; `Run-CacheProbe.ps1`
creates its PSO without executing GPU commands. The test uses a 4 GiB job cap,
4 GiB system-commit reserve and 60-second timeout, with no physical-memory floor.
The generated shader and cached binary remain local.

| Setup | First creation | Reuse in a new process |
|---|---:|---:|
| Original isolated runner | 3,128.839 ms | 3,050.335 ms |
| Non-isolated authored control | 3,090.688 ms | 1.115 ms |
| Isolated runner with private AMD cache | 3,419.573 ms | 1.079 ms |

Copying the private driver cache into a fresh isolated output/profile loaded the
PSO in 1.394 ms without an input `GetCachedBlob` file. That blob is only 954 bytes;
the driver code cache must persist separately. `-DriverCacheFrom <probe-run-id>`
validates identical probe and shader hashes before copying it. The runner supplies
`AMD_SHADER_DISK_CACHE_PATH` within its writable output; global cache ACLs and
AppContainer capabilities remain unchanged. This demonstrates compiler reuse,
not gameplay performance or rendering correctness.
