"""Independent runtime dispatch and external state, using only synthetic files.

Run: python -I tests/test_runtime_backend.py
No game package, graphics driver, Rust toolchain or native compiler is needed.
"""
from __future__ import annotations

import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import runtime_backend as bridge


class RuntimeBackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        # Windows TEMP can use an 8.3 alias; expected paths use the same
        # canonical long form that the launcher deliberately returns.
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / "checkout"
        self.root.mkdir()
        self.game = self.base / "Game's package & space λ"
        self.game.mkdir()
        self.image = self.game / bridge.GAME_IMAGE
        self.image.write_bytes(b"synthetic input; not a PE image")
        self.state = self.base / "runtime state"
        self.shaders = self.base / "Leonida shaders"
        self.shaders.mkdir()
        self.env = {"PATH": os.environ.get("PATH", ""), "HOME": str(self.base),
                    "VICTORY_GAME_DIR": str(self.root / "unwanted-game"),
                    "VICTORY_CONFIG": str(self.root / "unwanted.toml"),
                    "VICTORY_D3D12_WARP": "1", "LEONIDA_SHADERS": str(self.shaders)}

    def args(self, *words):
        return bridge.parse_args(list(words))

    def plan(self, *words, windows=True):
        return bridge.make_plan(self.args(*words), root=self.root, windows=windows, environment=self.env)

    def runtime_plan(self, *words):
        return self.plan(*words, "--game", str(self.game), "--state-dir", str(self.state))

    def test_victory_build_is_locked_native_and_data_free(self):
        plan = self.plan("build", "--diagnostics", "--jobs", "3")
        self.assertEqual(plan.cwd, self.root / "runtimes" / "victory")
        self.assertEqual(plan.argv, ["cargo", "build", "--locked", "--target-dir",
                         str(plan.cwd / "target"), "--package", "victory", "--target",
                         bridge.WINDOWS_TARGET, "--profile", "diag", "--features",
                         "victory/diagnostics", "--jobs", "3"])
        self.assertFalse(any(key.startswith(("VICTORY_", "LEONIDA_")) for key in plan.environment))
        self.assertFalse(self.state.exists())

    def test_victory_test_is_workspace_locked_and_needs_no_tables(self):
        self.env["VICTORY_BCPACK_TABLES"] = str(self.root / "missing-private-file")
        plan = self.plan("test", windows=False)
        self.assertIn("--workspace", plan.argv)
        self.assertIn("--locked", plan.argv)
        self.assertNotIn("--target", plan.argv)
        self.assertNotIn("VICTORY_BCPACK_TABLES", plan.environment)

    def test_leonida_build_and_test_use_existing_entry_points(self):
        plan = self.plan("build", "--backend", "leonida", "--jobs", "2")
        self.assertEqual(plan.argv[-3:], [str(self.root / "scripts" / "build_runtime.ps1"), "-jobs", "2"])
        self.assertTrue(plan.windows_only)
        test = self.plan("test", "--backend", "leonida")
        self.assertEqual(test.argv[0], "ctest")
        self.assertIn(str(self.root / "runtime" / "build"), test.argv)

    def test_each_backend_gets_separate_state_and_correct_native_cli(self):
        victory = self.runtime_plan("run")
        leonida = self.runtime_plan("run", "--backend", "leonida")
        self.assertNotEqual(victory.cwd, leonida.cwd)
        self.assertEqual(victory.overrides["VICTORY_CACHE_DIR"], str(self.state / "victory" / "cache"))
        self.assertEqual(victory.overrides["VICTORY_DATA_DIR"], str(self.state / "victory" / "data"))
        self.assertEqual(victory.argv[1:3], ["run", str(self.image)])
        self.assertIn("--execute", victory.argv)
        self.assertEqual(leonida.argv[1:3], ["--run", str(self.image)])
        self.assertIn(str(self.state / "leonida" / "overlay"), leonida.argv)
        self.assertNotIn("VICTORY_CONFIG", victory.environment)
        self.assertNotIn("VICTORY_D3D12_WARP", victory.environment)
        self.assertNotIn("LEONIDA_SHADERS", victory.environment)
        self.assertFalse(any(key.startswith("VICTORY_") for key in leonida.environment))

    def test_inspect_and_bind_only_do_not_request_title_execution(self):
        victory = self.runtime_plan("inspect", "--imports", "--exports")
        self.assertEqual(victory.argv[1:], ["inspect", str(self.image), "--imports", "--exports"])
        self.assertNotIn("--execute", self.runtime_plan("run", "--bind-only").argv)
        leonida = self.runtime_plan("inspect", "--backend", "leonida")
        self.assertEqual(leonida.argv[1], "--dry-run")

    def test_warp_is_explicit_and_requires_diagnostics(self):
        for words in (("run", "--warp"), ("run", "--backend", "leonida", "--diagnostics", "--warp")):
            with self.subTest(words=words), self.assertRaises(bridge.BridgeError):
                self.args(*words)
        plan = self.runtime_plan("run", "--warp", "--diagnostics")
        self.assertEqual(plan.overrides["VICTORY_D3D12_WARP"], "1")
        self.assertIn("diag", str(plan.argv[0]))

    def test_series_s_menu_picture_is_explicit_and_selects_the_series_s_profile(self):
        self.env["VICTORY_SERIES_S_MENU_PICTURE"] = "1"
        self.assertNotIn("VICTORY_SERIES_S_MENU_PICTURE", self.runtime_plan("run", "--diagnostics").environment)
        plan = self.runtime_plan("run", "--diagnostics", "--series-s-menu-picture")
        self.assertEqual(plan.overrides["VICTORY_SERIES_S_MENU_PICTURE"], "1")
        self.assertEqual(plan.argv[plan.argv.index("--console") + 1], "series-s")
        for words in (("run",), ("test", "--diagnostics"),
                      ("run", "--diagnostics", "--console", "series-x")):
            with self.subTest(words=words), self.assertRaises(bridge.BridgeError):
                self.args(*words, "--series-s-menu-picture")

    def test_leonida_retains_explicit_vulkan_and_cli_can_override_it(self):
        initial = self.runtime_plan("run", "--backend", "leonida")
        self.assertNotIn("LEONIDA_D3D12", initial.environment)
        self.assertEqual(self.runtime_plan("run", "--backend", "leonida", "--vulkan").environment["LEONIDA_D3D12"], "vulkan")
        self.env["LEONIDA_D3D12"] = "vulkan"
        inherited = self.runtime_plan("run", "--backend", "leonida")
        self.assertEqual(inherited.environment["LEONIDA_D3D12"], "vulkan")
        host = self.runtime_plan("run", "--backend", "leonida", "--no-vulkan")
        self.assertNotIn("LEONIDA_D3D12", host.environment)
        self.assertNotIn("LEONIDA_D3D12", self.runtime_plan("run").environment)
        with self.assertRaises(bridge.BridgeError):
            self.args("run", "--vulkan")

    def test_safe_diagnostic_switches_keep_native_values_and_backend_isolation(self):
        for index, name in enumerate(bridge.VICTORY_DIAGNOSTIC_SWITCHES):
            self.env[name] = "" if index == 0 else "0"
        self.env["LEONIDA_VK_VALIDATION"] = "1"
        self.env["VICTORY_CRASH_SAVE"] = "unvalidated-other-setting"
        victory = self.runtime_plan("run", "--diagnostics")
        for name in bridge.VICTORY_DIAGNOSTIC_SWITCHES:
            self.assertEqual(victory.environment[name], self.env[name])
        self.assertNotIn("LEONIDA_VK_VALIDATION", victory.environment)
        self.assertNotIn("VICTORY_CRASH_SAVE", victory.environment)
        leonida = self.runtime_plan("run", "--backend", "leonida")
        self.assertEqual(leonida.environment["LEONIDA_VK_VALIDATION"], "1")
        self.assertFalse(any(key.startswith("VICTORY_") for key in leonida.environment))

    def test_inherited_shader_directory_is_validated_and_cli_takes_precedence(self):
        inherited = self.runtime_plan("run", "--backend", "leonida")
        self.assertEqual(inherited.environment["LEONIDA_SHADERS"], str(self.shaders))
        self.env["LEONIDA_SHADERS"] = str(self.root)
        with self.assertRaisesRegex(bridge.BridgeError, "outside"):
            self.runtime_plan("run", "--backend", "leonida")
        explicit = self.runtime_plan("run", "--backend", "leonida", "--shader-dir", str(self.shaders))
        self.assertEqual(explicit.environment["LEONIDA_SHADERS"], str(self.shaders))
        self.assertNotIn("LEONIDA_SHADERS", self.runtime_plan("run").environment)
        self.env["LEONIDA_SHADERS"] = str(self.base / "missing shaders")
        with self.assertRaisesRegex(bridge.BridgeError, "not a directory"):
            self.runtime_plan("run", "--backend", "leonida")

    def test_leonida_saves_are_isolated_and_shader_symlink_cannot_enter_checkout(self):
        self.env["LEONIDA_SAVE_DIR"] = str(self.root / "unwanted saves")
        plan = self.runtime_plan("run", "--backend", "leonida")
        self.assertEqual(plan.environment["LEONIDA_SAVE_DIR"], str(self.state / "leonida" / "data" / "saves"))
        link = self.base / "shader link"
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("directory symlinks unavailable")
        self.env["LEONIDA_SHADERS"] = str(link)
        with self.assertRaisesRegex(bridge.BridgeError, "outside"):
            self.runtime_plan("run", "--backend", "leonida")

    def test_warp_test_selects_both_native_d3d12_and_shader_test_adapters(self):
        plan = self.plan("test", "--diagnostics", "--warp")
        self.assertEqual(plan.environment["VICTORY_D3D12_WARP"], "1")
        self.assertEqual(plan.environment["VICTORY_WARP"], "1")

    def test_dry_run_never_launches_or_creates_state(self):
        output = io.StringIO()
        with mock.patch.object(bridge.subprocess, "run", side_effect=AssertionError("process started")), contextlib.redirect_stdout(output):
            code = bridge.main(["run", "--game", str(self.game), "--state-dir", str(self.state), "--dry-run"],
                               root=self.root, windows=True, environment=self.env)
        self.assertEqual(code, 0)
        self.assertFalse(self.state.exists())
        self.assertFalse(json.loads(output.getvalue())["executed"])

    def test_process_keeps_arguments_separate_and_returns_failure_code(self):
        plan = self.runtime_plan("run")
        for file in plan.required_files:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.touch()
        plan.argv += ["--", "two words", "$(not-a-shell)", "a&b"]
        with mock.patch.object(bridge.subprocess, "run", return_value=mock.Mock(returncode=37)) as run:
            self.assertEqual(bridge.execute(plan, windows=True), 37)
        self.assertEqual(run.call_args.args[0][-3:], ["two words", "$(not-a-shell)", "a&b"])
        self.assertIs(run.call_args.kwargs["shell"], False)
        self.assertEqual(run.call_args.kwargs["cwd"], self.state / "victory")

    def test_missing_leonida_tls_host_stops_before_launch_or_state_creation(self):
        build = self.base / "prebuilt"
        build.mkdir()
        (build / "gta6rt.exe").touch()
        plan = self.runtime_plan("run", "--backend", "leonida", "--runtime-build", str(build))
        with mock.patch.object(bridge.subprocess, "run") as run, self.assertRaisesRegex(bridge.BridgeError, "gta6rt_tls_host"):
            bridge.execute(plan, windows=True)
        run.assert_not_called()
        self.assertFalse(self.state.exists())

    def test_runtime_refuses_non_windows_execution_but_allows_plan(self):
        plan = self.runtime_plan("run")
        with self.assertRaisesRegex(bridge.BridgeError, "requires native Windows"):
            bridge.execute(plan, windows=False)

    def test_checkout_traversal_and_package_state_overlap_are_rejected(self):
        for path in (self.root / "derived", self.base / "external" / ".." / "checkout" / "derived", self.game / "state"):
            with self.subTest(path=path), self.assertRaises(bridge.BridgeError):
                self.plan("run", "--game", str(self.game), "--state-dir", str(path))

    def test_symlink_cannot_hide_state_inside_checkout(self):
        link = self.base / "linked"
        try:
            link.symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("directory symlinks unavailable")
        with self.assertRaises(bridge.BridgeError):
            self.plan("run", "--game", str(self.game), "--state-dir", str(link / "state"))

    def test_state_child_symlink_cannot_hide_cache_in_checkout(self):
        state = self.state / "victory"
        state.mkdir(parents=True)
        try:
            (state / "cache").symlink_to(self.root, target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("directory symlinks unavailable")
        with self.assertRaises(bridge.BridgeError):
            self.runtime_plan("run")

    def test_backend_symlink_cannot_alias_other_backend_state(self):
        self.state.mkdir()
        (self.state / "leonida").mkdir()
        try:
            (self.state / "victory").symlink_to(self.state / "leonida", target_is_directory=True)
        except (OSError, NotImplementedError):
            self.skipTest("directory symlinks unavailable")
        with self.assertRaisesRegex(bridge.BridgeError, "must not redirect"):
            self.runtime_plan("run")

    def test_tables_are_optional_external_readable_and_exact_size(self):
        path = self.base / "tables.bin"
        path.write_bytes(bytes(bridge.BCPACK_TABLES_SIZE))
        plan = self.runtime_plan("run", "--bcpack-tables", str(path))
        self.assertEqual(plan.overrides["VICTORY_BCPACK_TABLES"], str(path.resolve()))
        path.write_bytes(b"invalid size")
        with self.assertRaisesRegex(bridge.BridgeError, "77,982"):
            self.runtime_plan("run", "--bcpack-tables", str(path))
        inside = self.root / "tables.bin"
        inside.write_bytes(bytes(bridge.BCPACK_TABLES_SIZE))
        with self.assertRaisesRegex(bridge.BridgeError, "outside"):
            self.runtime_plan("run", "--bcpack-tables", str(inside))

    def test_game_and_executable_must_be_external_and_same_package(self):
        with self.assertRaises(bridge.BridgeError):
            self.plan("inspect", "--game", str(self.root))
        other = self.base / "other.exe"
        other.touch()
        with self.assertRaisesRegex(bridge.BridgeError, "inside the selected"):
            self.plan("inspect", "--game", str(self.game), "--exe", str(other))

    def test_victory_run_requires_executable_parent_but_inspect_accepts_nested_image(self):
        nested = self.game / "nested" / "image.exe"
        nested.parent.mkdir()
        nested.write_bytes(b"synthetic nested image")
        with self.assertRaisesRegex(bridge.BridgeError, "executable's parent directory"):
            self.runtime_plan("run", "--exe", str(nested))
        inspected = self.runtime_plan("inspect", "--exe", str(nested))
        self.assertEqual(inspected.argv[1:3], ["inspect", str(nested)])

    def test_game_arguments_are_forwarded_without_shell_reparsing(self):
        args = self.args("run", "--game", str(self.game), "--state-dir", str(self.state), "--", "--custom", "two words")
        plan = bridge.make_plan(args, root=self.root, windows=True, environment=self.env)
        self.assertEqual(plan.argv[-3:], ["--", "--custom", "two words"])

    def test_doctor_does_not_spawn_and_reports_missing_tools(self):
        output = io.StringIO()
        with mock.patch.object(bridge.subprocess, "run", side_effect=AssertionError("process started")), \
                mock.patch.object(bridge.shutil, "which", return_value=None), contextlib.redirect_stdout(output):
            code = bridge.main(["doctor", "--state-dir", str(self.state)], root=self.root, windows=True, environment=self.env)
        self.assertEqual(code, 1)
        self.assertIsNone(json.loads(output.getvalue())["tools"]["cargo"])
        self.assertFalse(self.state.exists())


if __name__ == "__main__":
    unittest.main()
