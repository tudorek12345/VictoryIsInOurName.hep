# Isolated process runner

`build.cmd` uses the installed x64 MSVC toolchain and Windows SDK. `test.ps1` runs the included probe against synthetic files and an in-process listener bound to a non-loopback interface on this machine. It checks file access, TCP isolation, private commit limits, timeout termination, and removal of staged AppContainer grants.

```powershell
.\build.cmd
.\test.ps1
```

`isolated-run.exe` launches a staged local Windows executable with a fresh AppContainer profile containing zero capability SIDs. It checks the suspended child’s token and job assignment before resuming. A private job limits committed memory for each process and the entire job and terminates remaining processes on close. The runner returns the child’s exit code, `124` on timeout, or `125` for a runner error. Output and errors go to the same new log. Child stdin is empty and the environment contains the Windows paths, temporary paths, and VICTORY variables explicitly supplied.

```text
isolated-run.exe --program EXE --rx DIRECTORY [--rx DIRECTORY ...]
                 --modify EMPTY_DIRECTORY --log NEW_FILE
                 --seconds 1..3600 --commit-mib 64..131072
                 [--reserve-physical-mib N] [--reserve-commit-mib N]
                 [--external-rx PACKAGE_DIRECTORY]
                 [--env VICTORY_NAME=VALUE ...] -- [PROGRAM_ARGS ...]
```

Use independent copies under `stage` beside the runner. The program goes inside an RX directory. Keep the writable directory and log directory separate from all RX directories. The destination log must be new, and the writable directory must already exist and be empty. The runner rejects reparse points and multiply-linked input files before applying grants. The working directory is the program’s directory.

`build.cmd guard` builds `isolated-run-guard.exe` separately from the existing helper. The two reserve options check available physical RAM and system commit every 500 ms. Crossing either floor ends the job with code 126 and records which limit fired. `test.ps1 -PhysicalGuard` checks both stops on the synthetic probe, plus the existing job and access-rule checks.

The runner restores staged filesystem access rules and removes the profile when it exits normally, including after a child timeout. It retries profile deletion for up to about five seconds if Windows reports a sharing violation. Windows can set its automatic-inheritance flag when restoring access rules. Files created during the run can retain a low-integrity label. Force-killing the runner can interrupt profile and ACL cleanup, while the job’s kill-on-close still applies. Keep the staged directories dedicated to the run.

The optional `--external-rx` accepts `D:\BuildGTA$\buildgta`. It allows the AppContainer SID read and execute access to the original package and denies file writes, attribute changes, deletion, and permission changes for that SID. The runner checks each inherited grant before launch and verifies the original access entries across the package after restoring the root ACL. This path requires working ACL inheritance, single-link files, and ordinary directories. The launcher reads the package and keeps writable data in the separate output root. Use the runner timeout for cleanup.

Victory’s diagnostics build takes `--env VICTORY_D3D12_WARP=1` for its software adapter. Point `VICTORY_GAME_DIR` at the package and set `VICTORY_DATA_DIR` and `VICTORY_CACHE_DIR` to subdirectories of the writable root. The external ACL fixture uses `build.cmd test-external` and `test.ps1 -ExternalPackage`. It exercises a separate synthetic directory with a nested read-only file.
