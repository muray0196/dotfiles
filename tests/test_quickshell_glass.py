"""Exercise mode selection and reboot restoration without touching the desktop."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/quickshell-glass.py"
SPEC = importlib.util.spec_from_file_location("quickshell_glass", SCRIPT)
glass = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(glass)


class RestoreTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir()
        self.plugin = self.root / "plugin.so"
        self.plugin.touch()
        self.enterContext(patch.dict(os.environ, {
            "XDG_RUNTIME_DIR": str(self.runtime),
            "XDG_STATE_HOME": str(self.root / "state"),
        }))
        self.enterContext(patch.object(glass.time, "sleep"))
        self.enterContext(patch.object(glass, "command", side_effect=self.command))
        self.loaded = False
        self.shaders_ready = True
        self.delay = 0
        self.events = []
        self.widgets = {name: {"glassStyle": "off", "glassMotion": "false"}
                        for name in ("clock", "performance")}

    def command(self, *args):
        self.events.append(args)
        if args[0] == "qs":
            name = args[4]
            if name == "performance" and self.delay:
                self.delay -= 1
                raise RuntimeError("IPC endpoint not ready")
            action = args[6:]
            if action[:3] == ("prop", "get", "widgets"):
                return self.widgets[name][action[3]]
            if action[:2] == ("call", "widgets"):
                prop = {"setGlassStyle": "glassStyle", "setGlassMotion": "glassMotion"}[action[2]]
                self.widgets[name][prop] = action[3]
                return ""
        if args[:3] == ("hyprctl", "--instance", "test"):
            action = args[3:]
            if action == ("-j", "plugin", "list"):
                return json.dumps([{"name": "hyprglass", "version": glass.OPTICS_VERSION}]
                                  if self.loaded else [])
            if action[:2] == ("plugin", "load"):
                self.loaded = True
                return "ok"
            if action[:2] == ("plugin", "unload"):
                self.loaded = False
                return "ok"
            if action == ("reload",) or action[0] == "eval":
                return "ok"
            if action[:2] == ("-j", "getoption"):
                style = (self.runtime / "quickshell-glass-style").read_text().strip()
                return json.dumps({"str": "widgets-" + style})
            if action == ("configerrors",):
                return ""
            if action == ("-j", "hyprglass", "status"):
                return json.dumps({"versionCheck": "match",
                                   "shaders": "ready" if self.shaders_ready else "failed",
                                   "features": {"layers": {"active": True}}})
        raise AssertionError(f"Unexpected desktop command: {args}")

    def run_helper(self, style):
        with patch("sys.argv", [str(SCRIPT), style, "--instance", "test",
                                "--plugin", str(self.plugin)]), contextlib.redirect_stdout(io.StringIO()):
            glass.main()

    def test_reboot_restores_after_delayed_widget_start(self):
        # A saved selection from before the Clear rename keeps its appearance.
        glass.remember_style("rounded")
        self.delay = 1
        self.run_helper("restore")
        self.assertTrue(self.loaded)
        self.assertEqual(glass.load_style(), "clear")
        self.assertEqual((self.runtime / "quickshell-glass-style").read_text(), "clear\n")
        self.assertEqual(glass.saved_style_path().stat().st_mode & 0o777, 0o600)
        for widget in self.widgets.values():
            self.assertEqual(widget, {"glassStyle": "clear", "glassMotion": "true"})
        load = next(i for i, event in enumerate(self.events) if event[3:5] == ("plugin", "load"))
        ready_checks = [event for event in self.events[:load] if event[0] == "qs" and event[4] == "performance"]
        self.assertEqual(len(ready_checks), 2)

    def test_failed_material_keeps_previous_successful_selection(self):
        glass.remember_style("clear")
        self.shaders_ready = False
        with self.assertRaisesRegex(RuntimeError, "ready, active renderer"):
            self.run_helper("blurred")
        self.assertEqual(glass.load_style(), "clear")
        self.assertFalse(self.loaded)
        for widget in self.widgets.values():
            self.assertEqual(widget["glassStyle"], "off")

    def test_restore_timeout_does_not_load_plugin_or_erase_selection(self):
        glass.remember_style("rounded")
        self.delay = 100
        with patch.object(glass.time, "monotonic", side_effect=[0, 1, 46]):
            with self.assertRaisesRegex(RuntimeError, "Timed out waiting"):
                self.run_helper("restore")
        self.assertFalse(self.loaded)
        self.assertEqual(glass.load_style(), "clear")
        self.assertFalse((self.runtime / "quickshell-glass-style").exists())

    def test_off_is_remembered_and_restored_without_loading_plugin(self):
        glass.remember_style("rounded")
        self.run_helper("off")
        self.assertEqual(glass.load_style(), "off")
        (self.runtime / "quickshell-glass-style").unlink()
        self.run_helper("restore")
        self.assertFalse(self.loaded)
        self.assertEqual(glass.load_style(), "off")

    def test_missing_or_invalid_selection_does_not_touch_desktop(self):
        self.run_helper("restore")
        self.assertEqual(self.events, [])
        glass.remember_style("not-a-material")
        with self.assertRaisesRegex(RuntimeError, "Invalid saved"):
            self.run_helper("restore")
        self.assertEqual(self.events, [])

    def test_both_modes_survive_loss_of_runtime_and_widget_state(self):
        for style in ("clear", "blurred"):
            with self.subTest(style=style):
                self.run_helper(style)
                self.assertEqual(glass.load_style(), style)
                (self.runtime / "quickshell-glass-style").unlink()
                self.loaded = False
                for widget in self.widgets.values():
                    widget.update(glassStyle="off", glassMotion="false")
                self.run_helper("restore")
                self.assertTrue(self.loaded)
                self.assertEqual((self.runtime / "quickshell-glass-style").read_text(), style + "\n")
                for widget in self.widgets.values():
                    self.assertEqual(widget, {"glassStyle": style, "glassMotion": "true"})

    def test_rounded_command_remains_an_alias_for_clear(self):
        self.run_helper("rounded")
        self.assertEqual(glass.load_style(), "clear")
        self.assertEqual(self.widgets["clock"]["glassStyle"], "clear")

    def test_picker_selects_blurred_on_both_columns(self):
        glass.remember_style("rounded")
        result = glass.subprocess.CompletedProcess([], 0, "Blurred\n", "")
        with patch.object(glass.subprocess, "run", return_value=result) as picker:
            self.run_helper("choose")
        self.assertEqual(picker.call_args.kwargs["input"], "Clear  (current)\nBlurred\n")
        self.assertEqual(glass.load_style(), "blurred")
        for widget in self.widgets.values():
            self.assertEqual(widget["glassStyle"], "blurred")

    def test_cancel_picker_leaves_selection_and_desktop_untouched(self):
        glass.remember_style("blurred")
        result = glass.subprocess.CompletedProcess([], 1, "", "")
        with patch.object(glass.subprocess, "run", return_value=result):
            self.run_helper("choose")
        self.assertEqual(glass.load_style(), "blurred")
        self.assertEqual(self.events, [])
        self.assertFalse((self.runtime / "quickshell-glass-style").exists())

    def test_missing_picker_reports_direct_mode_alternative(self):
        with patch.object(glass.subprocess, "run", side_effect=FileNotFoundError):
            with self.assertRaisesRegex(RuntimeError, "select clear or blurred directly"):
                self.run_helper("choose")
        self.assertEqual(self.events, [])

    def test_modern_modes_reject_older_optics(self):
        for style in ("clear", "blurred"):
            with self.subTest(style=style), self.assertRaisesRegex(RuntimeError, "optics24"):
                glass.check_material_version(style, "0.10.0-optics23")


if __name__ == "__main__":
    unittest.main()
