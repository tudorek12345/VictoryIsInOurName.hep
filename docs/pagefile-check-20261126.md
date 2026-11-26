# Pagefile and D: drive check

Checked 26 November 2026, 00:20 PST. The configured D: pagefile increase is
active. No pagefile setting was changed: capacity was not the limiting resource
in the inspected run.

| Volume | Configured initial | Configured maximum | Active allocation |
| --- | ---: | ---: | ---: |
| C: | 16 GiB | 32 GiB | 16 GiB |
| D: | 24 GiB | 32 GiB | 24 GiB |

Windows reports manual sizing and both pagefiles as active, non-temporary files.
D: is an ADATA LEGEND 860 NVMe volume with about 125.4 GiB free. Windows reports
the disk/volume healthy and online. A bounded System-event check for storage
providers and event IDs 7, 51, 55, 129, 153 and 157 found no matching errors in
the preceding 24 hours. This is not a full device-health or surface test.

Run `original-20261126-001501-5fc759d7` stopped at the job commit notification
threshold: 21.64 GiB committed against a 22 GiB hard limit. Its final runtime
memory sample still reported 12.45 GiB of available system commit and 2.88 GiB
of available physical RAM. Increasing a pagefile cannot change that job limit.

Nine host samples taken before the final runtime sample showed D: pagefile use
between 813 and 819 MiB of its 24 GiB allocation. The largest sampled average
D: read latency was 0.294 ms; write latency was 0.515 ms; instantaneous queue
length ranged from zero to one. Sampled throughput peaked at 142.8 MiB/s read
and 511.5 MiB/s write. These are interval samples, not whole-run averages or
maximum individual-request latencies.

A later sample during termination/cleanup reported 1,333 MiB of D: pagefile use
and 11.8 ms average write latency. Do not attribute that cleanup sample to live
gameplay. Drive counters include all D: activity, including game assets, caches,
logs and other processes. System hard-page-read counters also include mapped
file reads; they do not identify pagefile traffic or its drive by themselves.

The evidence establishes an active, adequately sized pagefile for this run.
It does not rule out transient I/O stalls between samples. Continue reducing
runtime allocation demand and keep collecting paging telemetry alongside the
existing job and system-commit guards.
