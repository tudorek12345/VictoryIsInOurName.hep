# Memory-management review, 25 November 2026 (PST)

Scope: candidate `0001d4b947e17640b919b4ec37e9a49413f235b8`, RX 9060 XT,
32 GiB RAM, OBS running. This compares the proposed budget/lifetime/pool
architecture with the code actually tested; it does not claim gameplay works.

| Proposed change | Current implementation and remaining evidence needed |
| --- | --- |
| Track shadow allocation lifetimes | `shadow::let_go_idle` already checks Arc ownership, descriptor references and idle use, then calls `host::retire`. Retention is not simply unbounded. The last timed sample of the nonblocking-read run held 2,114,574,570 shadow bytes; this alone does not explain the full process footprint. |
| Bound submissions by bytes | `queue::behind::room` bounds queued run counts, and host flights are bounded separately. A run count is not a byte budget. A byte limit needs owned-byte accounting and a wait outside locks required by consumers; otherwise the producer can deadlock the work that must free memory. No speculative limit has been installed. |
| Bound transient uploads/snapshots | Texture and staging allocations use pools. Empty staging blocks are reduced under physical-memory pressure. The final timed sample held 140,418,542 staging bytes and a 671,088,640-byte staging pool; these overlap. They do not demonstrate a multi-gigabyte runaway upload queue. |
| Reclaim completed resources | `host::retire` includes started and queued submissions; `bury` waits for completion plus the existing 64-submission grace period. Pool pieces also have a quarantine. Previous page faults motivated those guards. They have not been shortened. |
| Account for GPU residency | `resource::room` reserves capacity for buffer copies and world render targets before optional indexed texture work. Dedicated VRAM, shared backing and system RAM are different budgets. Host texture totals are not a measurement of dedicated residency. |
| Deduplicate allocations | Resource tables and shadow lookups already reuse known objects; descriptor references can legitimately keep more than one version alive. A concurrent duplicate must be demonstrated before collapsing versions that in-flight work still references. |

The tested shorter idle-retention switch did not get through world entry and
remains off by default. The one-worker/nonblocking-read comparison reduced its
worst sampled texture-preparation interval from 273.5 ms to 12.5 ms, but still
hit the physical reserve. Cache state and worker count also differed, so this is
not a controlled attribution of the whole-run performance change.

The independent memory sampler uses atomic counters and nonblocking pool reads.
It does not walk virtual memory, call GPU APIs, or wait for resource locks.
Retained categories overlap; `made_*` fields are cumulative. A null pool sample
means its lock was busy, not that it was empty. The external job guard measures
main and child processes separately, including the final allocation burst.

Next discriminating test: precompile the recorded used pipelines with no title
running, then reuse the exact-build cache and compare actual pipeline loads,
new compilations, frame stalls and memory growth. Precompilation does not remove
the title's resources, and a pipeline-created result is not rendered gameplay.
The 3 GiB physical reserve, 4 GiB commit reserve and normal Windows GPU watchdog
remain enabled throughout. No live resource is freed to force a test past them.
