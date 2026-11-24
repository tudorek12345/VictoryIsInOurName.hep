#!/usr/bin/env python3
"""Build and launch the independent VIctory and Leonida runtimes (stdlib only).

The bridge selects a process, not a graphics implementation. Game inputs and
runtime state stay outside this checkout; no game data is copied or downloaded.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Mapping, Sequence

ROOT = Path(__file__).resolve().parent
WINDOWS_TARGET = "x86_64-pc-windows-msvc"
BCPACK_TABLES_SIZE = 77_982
GAME_IMAGE = "game_scarlett_master.exe"
VICTORY_DIAGNOSTIC_SWITCHES = (
    "VICTORY_D3D12_DEBUG", "VICTORY_D3D12_DRED", "VICTORY_D3D12_GBV", "VICTORY_GPU_TIMING",
)


class BridgeError(ValueError):
    """An actionable configuration error, without an implementation traceback."""


@dataclass
class Plan:
    backend: str
    action: str
    argv: list[str]
    cwd: Path
    environment: dict[str, str]
    overrides: dict[str, str]
    required_files: tuple[Path, ...] = ()
    directories: tuple[Path, ...] = ()
    windows_only: bool = False


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Build, inspect or run an independent runtime. VIctory is the default.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=r'''Examples (Windows, from this checkout):
  py -3 -I runtime_backend.py doctor
  py -3 -I runtime_backend.py build --diagnostics
  py -3 -I runtime_backend.py test --diagnostics
  py -3 -I runtime_backend.py inspect --game "D:\Games\GTA VI" --imports --diagnostics
  py -3 -I runtime_backend.py run --game "D:\Games\GTA VI" --diagnostics --warp --dry-run
  py -3 -I runtime_backend.py run --game "D:\Games\GTA VI" --diagnostics --warp
  py -3 -I runtime_backend.py run --game "D:\Games\GTA VI" --diagnostics --series-s-menu-picture
  py -3 -I runtime_backend.py run --game "D:\Games\GTA VI" --bcpack-tables "D:\Private\tables.bin"
  py -3 -I runtime_backend.py build --backend leonida
  py -3 -I runtime_backend.py run --backend leonida --vulkan --runtime-build "D:\Leonida" --game "D:\Games\GTA VI"

--dry-run prints a plan and never starts a process or creates directories.
inspect uses VIctory's PE inspector; Leonida's inspect maps/binds without
executing the title. run starts title code unless --bind-only is supplied.
Build/test require no game or BCPack tables. VIctory run is Windows-only;
its hardware D3D12 path remains experimental. --warp explicitly selects
software D3D12 and requires a diagnostic build. State is kept separately
under <state-dir>/<backend>/{cache,data}; Leonida also gets its own overlay.
The two backends never share shader formats or pipeline caches.
Windows builds require Python 3.12+, Visual Studio C++ x64 build tools and
the Windows SDK. VIctory also requires Rust/rustup (the vendored workspace
pins its toolchain); Windows builds/tests target x86_64-pc-windows-msvc.
Leonida uses scripts/build_runtime.ps1 and its existing CMake/MSVC setup.
Leonida --vulkan selects its compiled Vulkan device; --no-vulkan selects
the host D3D12 path. Without either option, an existing LEONIDA_D3D12=vulkan
is retained; Vulkan is not enabled by default. LEONIDA_SHADERS is inherited
only after the same external-directory validation as --shader-dir. Saves
use <state-dir>/leonida/data/saves rather than an inherited save location.
The selected backend retains these diagnostic environment switches:
  VIctory: VICTORY_D3D12_DEBUG, VICTORY_D3D12_DRED, VICTORY_D3D12_GBV,
           VICTORY_GPU_TIMING (native presence semantics; diagnostics build).
  Leonida: LEONIDA_VK_VALIDATION (native value semantics).
Other backend variables and unvalidated path overrides remain isolated.
''',
    )
    result.add_argument("command", choices=("doctor", "build", "test", "inspect", "run"))
    result.add_argument("--backend", choices=("victory", "leonida"), default="victory")
    result.add_argument("--dry-run", action="store_true", help="print a plan without executing or writing")
    result.add_argument("--diagnostics", action="store_true", help="VIctory: use the diag profile and diagnostics feature")
    result.add_argument("--warp", action="store_true", help="VIctory diagnostics: explicitly use the software D3D12 adapter")
    result.add_argument("--series-s-menu-picture", action="store_true",
                        help="VIctory diagnostics: use the Series S menu presentation workaround")
    result.add_argument("--vulkan", action=argparse.BooleanOptionalAction, default=None,
                        help="Leonida: select Vulkan, or --no-vulkan for host D3D12; otherwise retain LEONIDA_D3D12=vulkan")
    result.add_argument("--jobs", type=positive_int, default=max(1, (os.cpu_count() or 2) // 2))
    result.add_argument("--game", metavar="DIR", help="external plain package directory (inspect/run)")
    result.add_argument("--exe", metavar="FILE", help="package executable; relative to --game when given")
    result.add_argument("--state-dir", metavar="DIR", help="external state parent; default: user-local Leonida/runtimes")
    result.add_argument("--runtime-build", metavar="DIR", help="directory containing the selected runtime executable; Leonida also needs gta6rt_tls_host.dll")
    result.add_argument("--bcpack-tables", metavar="FILE", help=f"VIctory: external {BCPACK_TABLES_SIZE:,}-byte table file; otherwise VICTORY_BCPACK_TABLES for inspect/run/doctor")
    result.add_argument("--shader-dir", metavar="DIR", help="Leonida only: external SPIR-V catalog; overrides validated LEONIDA_SHADERS")
    result.add_argument("--imports", action="store_true", help="VIctory inspect: list imports")
    result.add_argument("--exports", action="store_true", help="VIctory inspect: list exports")
    result.add_argument("--bind-only", action="store_true", help="run: map/bind without executing title code")
    result.add_argument("--strict", action="store_true", help="VIctory run: disable host pass-through")
    result.add_argument("--console", choices=("series-x", "series-s"), default=None, help="VIctory run: console model (default series-x)")
    return result


def positive_int(value: str) -> int:
    try:
        number = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be a positive integer") from error
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    words = list(sys.argv[1:] if argv is None else argv)
    title_args: list[str] = []
    if "--" in words:
        split = words.index("--")
        words, title_args = words[:split], words[split + 1:]
    args = parser().parse_args(words)
    args.title_args = title_args
    if title_args and args.command != "run":
        raise BridgeError("title arguments after -- are supported only by run")
    if args.warp and (args.backend != "victory" or not args.diagnostics):
        raise BridgeError("--warp requires --backend victory --diagnostics")
    if args.series_s_menu_picture:
        if args.backend != "victory" or args.command != "run" or not args.diagnostics or args.console == "series-x":
            raise BridgeError("--series-s-menu-picture requires a diagnostic VIctory Series S run")
        args.console = "series-s"
    if args.backend == "leonida" and (args.diagnostics or args.bcpack_tables or args.strict or args.console):
        raise BridgeError("--diagnostics, --bcpack-tables, --strict and --console are VIctory options")
    if args.shader_dir and args.backend != "leonida":
        raise BridgeError("--shader-dir belongs to Leonida; VIctory does not use its SPIR-V catalog")
    if args.vulkan is not None and args.backend != "leonida":
        raise BridgeError("--vulkan/--no-vulkan belong to the Leonida backend")
    if (args.imports or args.exports) and (args.backend != "victory" or args.command != "inspect"):
        raise BridgeError("--imports and --exports are supported only by VIctory inspect")
    if (args.bind_only or args.strict or args.console) and args.command != "run":
        raise BridgeError("--bind-only, --strict and --console are run options")
    if args.runtime_build and (args.command == "build" or (args.command == "test" and args.backend == "victory")):
        raise BridgeError("--runtime-build selects an existing runtime; it does not change the source build destination")
    if args.command in ("build", "test") and (args.game or args.exe or args.bcpack_tables or args.shader_dir):
        raise BridgeError("build/test use source-only inputs; omit game, executable, tables and shader paths")
    return args


def resolved(value: str | Path) -> Path:
    try:
        return Path(value).expanduser().resolve()
    except (OSError, RuntimeError) as error:
        raise BridgeError(f"cannot resolve path {value}: {error}") from error


def contains(parent: Path, child: Path) -> bool:
    try:
        return os.path.commonpath((os.path.normcase(str(parent)), os.path.normcase(str(child)))) == os.path.normcase(str(parent))
    except ValueError:  # Different Windows volumes.
        return False


def external(value: str | Path, label: str, root: Path, *, kind: str | None = None) -> Path:
    path = resolved(value)
    if contains(root, path):
        raise BridgeError(f"{label} must be outside the entire Leonida checkout: {path}")
    if kind == "file" and not path.is_file():
        raise BridgeError(f"{label} is not a readable file: {path}")
    if kind == "dir" and not path.is_dir():
        raise BridgeError(f"{label} is not a directory: {path}")
    if kind is None:
        for ancestor in (path, *path.parents):
            if ancestor.exists() and not ancestor.is_dir():
                raise BridgeError(f"{label} is under a file, not a directory: {ancestor}")
    return path


def state_paths(args: argparse.Namespace, root: Path, env: Mapping[str, str]) -> tuple[Path, Path, Path]:
    base = env.get("LOCALAPPDATA") or env.get("XDG_STATE_HOME")
    default = Path(base) if base else Path(env.get("HOME") or Path.home()) / ".local" / "state"
    parent = external(args.state_dir or default / "Leonida" / "runtimes", "--state-dir", root)
    state = external(parent / args.backend, "backend state", root)
    cache = external(state / "cache", "cache directory", root)
    data = external(state / "data", "data directory", root)
    # A chosen parent may be a symlink to another volume. Its backend-specific
    # children cannot redirect to another backend's state or cache, however.
    for expected, actual in ((parent / args.backend, state), (state / "cache", cache), (state / "data", data)):
        if os.path.normcase(str(expected)) != os.path.normcase(str(actual)):
            raise BridgeError(f"backend state child must not redirect through a symlink/junction: {expected}")
    if contains(cache, data) or contains(data, cache):
        raise BridgeError("cache and persistent data must be separate directories")
    return state, cache, data


def tables_path(args: argparse.Namespace, root: Path, env: Mapping[str, str]) -> Path | None:
    value = args.bcpack_tables or env.get("VICTORY_BCPACK_TABLES")
    if not value:
        return None
    path = external(value, "BCPack tables", root, kind="file")
    try:
        if path.stat().st_size != BCPACK_TABLES_SIZE:
            raise BridgeError(f"BCPack tables must be exactly {BCPACK_TABLES_SIZE:,} bytes: {path}")
        with path.open("rb") as stream:
            stream.read(1)
    except OSError as error:
        raise BridgeError(f"cannot read BCPack tables {path}: {error}") from error
    return path


def package_paths(args: argparse.Namespace, root: Path) -> tuple[Path, Path]:
    if not args.game and not args.exe:
        raise BridgeError("inspect/run require --game DIR or --exe FILE outside the checkout")
    game = external(args.game, "--game", root, kind="dir") if args.game else None
    image = Path(args.exe) if args.exe else Path(GAME_IMAGE)
    if not image.is_absolute() and game is not None:
        image = game / image
    image = external(image, "package executable", root, kind="file")
    game = game or image.parent
    if not contains(game, image):
        raise BridgeError("--exe must be inside the selected --game package")
    if args.backend == "victory" and args.command == "run" and \
            os.path.normcase(str(game)) != os.path.normcase(str(image.parent)):
        raise BridgeError("VIctory run mounts its package from the executable's parent directory; "
                          "--game must name that exact directory. Select the executable beside "
                          "MicrosoftGame.config, or use inspect for a nested image.")
    return game, image


def powershell(env: Mapping[str, str]) -> str:
    system_root = env.get("SystemRoot") or env.get("SYSTEMROOT")
    if system_root:
        candidate = Path(system_root) / "System32" / "WindowsPowerShell" / "v1.0" / "powershell.exe"
        if candidate.is_file():
            return str(candidate)
    return "powershell.exe"


def runtime_directory(args: argparse.Namespace, root: Path, windows: bool) -> Path:
    if args.runtime_build:
        return resolved(args.runtime_build)
    if args.backend == "leonida":
        return root / "runtime" / "build"
    target = root / "runtimes" / "victory" / "target"
    if windows:
        target /= WINDOWS_TARGET
    return target / ("diag" if args.diagnostics else "release")


def runtime_switches(args: argparse.Namespace, original: Mapping[str, str]) -> dict[str, str]:
    names = VICTORY_DIAGNOSTIC_SWITCHES if args.backend == "victory" else ("LEONIDA_VK_VALIDATION",)
    # Preserve native semantics: VIctory checks presence, even for the value
    # "0". These allowlisted switches carry no output or package paths.
    result = {name: original[name] for name in names if name in original}
    if args.backend == "leonida" and (args.vulkan is True or
            args.vulkan is None and original.get("LEONIDA_D3D12") == "vulkan"):
        result["LEONIDA_D3D12"] = "vulkan"
    return result


def shader_path(args: argparse.Namespace, root: Path, original: Mapping[str, str]) -> Path | None:
    value = args.shader_dir or original.get("LEONIDA_SHADERS")
    return external(value, "Leonida shader directory", root, kind="dir") if value else None


def make_plan(args: argparse.Namespace, *, root: Path = ROOT, windows: bool | None = None,
              environment: Mapping[str, str] | None = None) -> Plan:
    root = resolved(root)
    windows = os.name == "nt" if windows is None else windows
    original = dict(os.environ if environment is None else environment)
    # A different backend's settings must not silently select adapters, shader
    # formats, game paths or output locations. Build/test also have no game env.
    env = {key: value for key, value in original.items() if not key.upper().startswith(("VICTORY_", "LEONIDA_"))}
    overrides = runtime_switches(args, original)
    if args.command in ("build", "test"):
        if args.backend == "victory":
            source = root / "runtimes" / "victory"
            env.pop("CARGO_TARGET_DIR", None)
            env.pop("CARGO_BUILD_TARGET", None)
            argv = ["cargo", args.command, "--locked", "--target-dir", str(source / "target")]
            argv += ["--package", "victory"] if args.command == "build" else ["--workspace"]
            if windows:
                argv += ["--target", WINDOWS_TARGET]
            argv += ["--profile", "diag", "--features", "victory/diagnostics"] if args.diagnostics else ["--release"]
            argv += ["--jobs", str(args.jobs)]
            if args.warp:
                overrides["VICTORY_D3D12_WARP"] = "1"
                if args.command == "test":
                    overrides["VICTORY_WARP"] = "1"
            env.update(overrides)
            return Plan(args.backend, args.command, argv, source, env, overrides,
                        (source / "Cargo.toml", source / "Cargo.lock"))
        if args.command == "build":
            script = root / "scripts" / "build_runtime.ps1"
            argv = [powershell(original), "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-jobs", str(args.jobs)]
            env.update(overrides)
            return Plan(args.backend, args.command, argv, root, env, overrides, (script,), windows_only=True)
        argv = ["ctest", "--test-dir", str(runtime_directory(args, root, windows)), "-C", "RelWithDebInfo", "--output-on-failure"]
        env.update(overrides)
        return Plan(args.backend, args.command, argv, root, env, overrides)

    game, image = package_paths(args, root)
    state, cache, data = state_paths(args, root, original)
    for directory in (state, cache, data):
        if contains(game, directory) or contains(directory, game):
            raise BridgeError("runtime state must be separate from the game package")
    build = runtime_directory(args, root, windows)
    if args.backend == "victory":
        binary = build / ("victory.exe" if windows else "victory")
        overrides.update(VICTORY_GAME_DIR=str(game), VICTORY_CACHE_DIR=str(cache),
                         VICTORY_DATA_DIR=str(data), VICTORY_TEST_TITLES="")
        tables = tables_path(args, root, original)
        if tables:
            overrides["VICTORY_BCPACK_TABLES"] = str(tables)
        if args.warp:
            overrides["VICTORY_D3D12_WARP"] = "1"
        if args.series_s_menu_picture:
            overrides["VICTORY_SERIES_S_MENU_PICTURE"] = "1"
        argv = [str(binary), args.command, str(image)]
        if args.command == "inspect":
            argv += (["--imports"] if args.imports else []) + (["--exports"] if args.exports else [])
        else:
            argv += ["--unimplemented", "trap", "--console", args.console or "series-x"]
            if not args.bind_only:
                argv.append("--execute")
            if args.strict:
                argv.append("--strict")
        required = (binary,)
        native_only = args.command == "run"
    else:
        binary = build / "gta6rt.exe"
        overlay = external(state / "overlay", "Leonida overlay", root)
        if os.path.normcase(str(overlay)) != os.path.normcase(str(state / "overlay")):
            raise BridgeError("Leonida overlay must not redirect through a symlink/junction")
        if contains(game, overlay) or contains(overlay, game):
            raise BridgeError("Leonida overlay must be separate from the game package")
        mode = "--dry-run" if args.command == "inspect" or args.bind_only else "--run"
        argv = [str(binary), mode, str(image), "--game-dir", str(game), "--overlay", str(overlay)]
        shaders = shader_path(args, root, original)
        if shaders:
            overrides["LEONIDA_SHADERS"] = str(shaders)
        saves = external(data / "saves", "Leonida save directory", root)
        if os.path.normcase(str(saves)) != os.path.normcase(str(data / "saves")):
            raise BridgeError("Leonida save directory must not redirect through a symlink/junction")
        overrides["LEONIDA_SAVE_DIR"] = str(saves)
        required = (binary, build / "gta6rt_tls_host.dll")
        native_only = True
    if args.title_args:
        argv += ["--", *args.title_args]
    env.update(overrides)
    # All configured paths are absolute. A runtime starts in its own external
    # state folder, so ./victory.toml from the source checkout is never read.
    return Plan(args.backend, args.command, argv, state, env, overrides, required,
                (state,), windows_only=native_only)


def print_plan(plan: Plan) -> None:
    print(json.dumps({"backend": plan.backend, "command": plan.action, "argv": plan.argv,
                      "cwd": str(plan.cwd), "environment_overrides": plan.overrides,
                      "create_directories": [str(path) for path in plan.directories],
                      "windows_only": plan.windows_only, "executed": False}, indent=2))


def execute(plan: Plan, *, windows: bool | None = None) -> int:
    windows = os.name == "nt" if windows is None else windows
    if plan.windows_only and not windows:
        raise BridgeError(f"{plan.backend} {plan.action} requires native Windows; use --dry-run to inspect its plan")
    for path in plan.required_files:
        if not path.is_file():
            raise BridgeError(f"required runtime/build file is missing: {path}; build the selected backend or use --runtime-build")
    for directory in plan.directories:
        directory.mkdir(parents=True, exist_ok=True)
    return subprocess.run(plan.argv, cwd=plan.cwd, env=plan.environment, shell=False, check=False).returncode


def doctor(args: argparse.Namespace, *, root: Path, windows: bool, environment: Mapping[str, str]) -> int:
    root = resolved(root)
    state, cache, data = state_paths(args, root, environment)
    tools = ("cargo",) if args.backend == "victory" else (powershell(environment), "ctest")
    available = {name: shutil.which(name, path=environment.get("PATH")) for name in tools}
    tables = tables_path(args, root, environment) if args.backend == "victory" else None
    details = {"backend": args.backend, "native_windows": windows, "tools": available,
               "runtime_build": str(runtime_directory(args, root, windows)),
               "state": str(state), "cache": str(cache), "data": str(data),
               "diagnostics": args.diagnostics, "warp_requested": args.warp,
               "bcpack_tables": str(tables) if tables else None,
               "bcpack_requirement": f"Optional external {BCPACK_TABLES_SIZE:,}-byte file; required when VIctory decompresses BCPack. Build/test need no game or tables.",
               "checks": "Paths and tool presence only; no compiler, GPU or game process was started."}
    details["runtime_switches"] = runtime_switches(args, environment)
    if args.backend == "leonida":
        shaders = shader_path(args, root, environment)
        details["shader_directory"] = str(shaders) if shaders else None
    if args.game or args.exe:
        game, image = package_paths(args, root)
        details.update(game=str(game), image=str(image))
    print(json.dumps(details, indent=2))
    return 0 if all(available.values()) else 1


def main(argv: Sequence[str] | None = None, *, root: Path = ROOT, windows: bool | None = None,
         environment: Mapping[str, str] | None = None) -> int:
    try:
        args = parse_args(argv)
        windows = os.name == "nt" if windows is None else windows
        env = os.environ if environment is None else environment
        if args.command == "doctor":
            return doctor(args, root=root, windows=windows, environment=env)
        plan = make_plan(args, root=root, windows=windows, environment=env)
        if args.dry_run:
            print_plan(plan)
            return 0
        return execute(plan, windows=windows)
    except (BridgeError, OSError) as error:
        print(f"runtime backend: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
