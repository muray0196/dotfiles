#!/usr/bin/env python3
"""Select or restore Quickshell glass without changing wallpaper or layout."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "modules/quickshell/.config/quickshell/glass.lua"
DEFAULT_PLUGIN = (
    Path.home() / ".local/lib/quickshell-glass/hyprglass-0.10.0-0.56.2.so"
)
LEGACY_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics1-0.56.2.so")
CURVED_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics2-0.56.2.so")
MOTION_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics3-0.56.2.so")
RIM_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics4-0.56.2.so")
LIGHT_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics5-0.56.2.so")
LENS_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics6-0.56.2.so")
BALANCED_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics7-0.56.2.so")
CONTOUR_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics8-0.56.2.so")
VOLUME_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics9-0.56.2.so")
RETURN_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics10-0.56.2.so")
COHERENT_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics11-0.56.2.so")
MENISCUS_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics12-0.56.2.so")
ROLLED_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics13-0.56.2.so")
SOFT_JOIN_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics14-0.56.2.so")
CLEAR_ROLL_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics15-0.56.2.so")
FIXED_LIGHT_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics16-0.56.2.so")
CORNER_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics17-0.56.2.so")
CONTINUOUS_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics18-0.56.2.so")
WIDE_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics19-0.56.2.so")
SHOULDER_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics20-0.56.2.so")
RETURN_BAND_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics21-0.56.2.so")
TRANSPORT_OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics22-0.56.2.so")
OPTICS_PLUGIN = DEFAULT_PLUGIN.with_name("hyprglass-0.10.0-optics23-0.56.2.so")
OPTICS_VERSION = "0.10.0-optics23"
CURVED_STYLES = ("clear", "blurred", "rounded", "soft", "sculpted")
STYLES = ("off", "smoky", "legacy-clear", "frosted", "liquid", *CURVED_STYLES)


def check_material_version(style, version):
    if style in CURVED_STYLES and version != OPTICS_VERSION:
        raise RuntimeError("Adaptive curved materials require the optics23 build. Unload the older plugin first.")
    if style == "liquid" and version not in ("0.10.0-optics1", "0.10.0-optics2", "0.10.0-optics3", "0.10.0-optics4", "0.10.0-optics5", "0.10.0-optics6", "0.10.0-optics7", "0.10.0-optics8", "0.10.0-optics9", "0.10.0-optics10", "0.10.0-optics11", "0.10.0-optics12", "0.10.0-optics13", "0.10.0-optics14", "0.10.0-optics15", "0.10.0-optics16", "0.10.0-optics17", "0.10.0-optics18", "0.10.0-optics19", "0.10.0-optics20", "0.10.0-optics21", "0.10.0-optics22", OPTICS_VERSION):
        raise RuntimeError("Liquid requires an optics build. Unload the stock HyprGlass plugin first.")


def write_style(path, style):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        stream.write(style + "\n")
        temporary = Path(stream.name)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def save_style(style):
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    if not runtime.is_dir() or runtime.stat().st_uid != os.getuid():
        raise RuntimeError("The current user's runtime directory is unavailable.")
    write_style(runtime / "quickshell-glass-style", style)


def saved_style_path():
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return state / "dotfiles-linux/quickshell-glass-style"


def remember_style(style):
    path = saved_style_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    write_style(path, style)


def load_style():
    path = saved_style_path()
    try:
        style = path.read_text().strip()
    except FileNotFoundError:
        return None
    if style not in STYLES:
        raise RuntimeError(f"Invalid saved glass style in {path}.")
    # The accepted rounded material is now named Clear. Keep older commands
    # and saved selections working without changing their appearance.
    return "clear" if style == "rounded" else style


def choose_style():
    current = load_style()
    options = {}
    for style, label in (("clear", "Clear"), ("blurred", "Blurred")):
        options[label + ("  (current)" if style == current else "")] = style
    try:
        result = subprocess.run(
            ["wofi", "--dmenu", "--prompt", "Widget glass", "--width", "340",
             "--lines", "2", "--hide-scroll", "--insensitive", "--no-custom-entry",
             "--cache-file", "/dev/null"],
            input="\n".join(options) + "\n", text=True, capture_output=True,
        )
    except FileNotFoundError as error:
        raise RuntimeError("The picker needs wofi. You can also select clear or blurred directly.") from error
    if result.returncode == 1:
        return None  # Escape closes the picker without touching the desktop.
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not open the glass picker.")
    selected = result.stdout.strip()
    if selected not in options:
        raise RuntimeError("The glass picker returned an unknown mode.")
    return options[selected]


def command(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=15)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout.strip()


def compositor(instance):
    if not instance:
        instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not instance:
        instances = json.loads(command("hyprctl", "-j", "instances"))
        if len(instances) != 1:
            raise RuntimeError("Choose the desktop session with --instance.")
        instance = instances[0]["instance"]
    return ("hyprctl", "--instance", instance)


def widget(config, *args):
    return command("qs", "--no-color", "ipc", "-c", config, "--any-display", *args)


def wait_for_widgets(timeout=45):
    deadline = time.monotonic() + timeout
    last_error = "widgets have not started"
    while time.monotonic() < deadline:
        try:
            for config in ("clock", "performance"):
                style = widget(config, "prop", "get", "widgets", "glassStyle")
                if style.strip('"') not in STYLES:
                    raise RuntimeError(f"{config}: material IPC is not ready")
            return
        except (RuntimeError, subprocess.SubprocessError) as error:
            last_error = str(error)
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for desktop widgets: {last_error}")


def set_widgets(style, motion=False):
    for config in ("clock", "performance"):
        deadline = time.monotonic() + 8
        last_error = "widget did not acknowledge the style"
        while time.monotonic() < deadline:
            try:
                widget(config, "call", "widgets", "setGlassStyle", style)
                widget(config, "call", "widgets", "setGlassMotion", str(motion).lower())
                actual = widget(config, "prop", "get", "widgets", "glassStyle")
                actual_motion = widget(config, "prop", "get", "widgets", "glassMotion")
                if actual.strip('"') == style and actual_motion == str(motion).lower():
                    break
                last_error = actual
            except RuntimeError as error:
                last_error = str(error)
            time.sleep(0.2)
        else:
            raise RuntimeError(f"{config}: {last_error}")


def apply_lua(hypr, code):
    result = command(*hypr, "eval", code)
    if result != "ok":
        raise RuntimeError(result)


def status(hypr):
    result = command(*hypr, "-j", "hyprglass", "status")
    try:
        return json.loads(result)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"HyprGlass is unavailable: {result}") from error


def main():
    parser = argparse.ArgumentParser(
        description="Choose Clear or Blurred glass for both Quickshell columns.",
        epilog=("Requires a matching HyprGlass build and glass.lua sourced by Hyprland. "
                "Clear preserves the accepted rounded appearance; Blurred softens its background. "
                "No argument (or choose) opens the optional wofi picker. "
                "rounded is an alias for clear; legacy-clear is the earlier square fallback. "
                "Applying a material reloads Hyprland configuration; adaptive curved materials require optics23. "
                "Successful selections are remembered across reboots. Use restore from desktop startup; "
                "it waits for both widgets. Does not install software or enable startup itself."),
    )
    parser.add_argument("style", nargs="?", default="choose", choices=(*STYLES, "choose", "status", "restore"))
    parser.add_argument("--plugin", type=Path, help="Plugin binary; prefers the local optics build")
    parser.add_argument("--instance", help="Hyprland instance signature")
    args = parser.parse_args()
    if args.style == "choose":
        args.style = choose_style()
        if args.style is None:
            return
    if args.style == "rounded":
        args.style = "clear"
    restoring = args.style == "restore"
    if restoring:
        args.style = load_style()
        if args.style is None:
            print("No saved glass material; desktop left unchanged.")
            return
    if args.plugin is None:
        args.plugin = next((path for path in (OPTICS_PLUGIN, TRANSPORT_OPTICS_PLUGIN, RETURN_BAND_OPTICS_PLUGIN, SHOULDER_OPTICS_PLUGIN, WIDE_OPTICS_PLUGIN, CONTINUOUS_OPTICS_PLUGIN, CORNER_OPTICS_PLUGIN, FIXED_LIGHT_OPTICS_PLUGIN, CLEAR_ROLL_OPTICS_PLUGIN, SOFT_JOIN_OPTICS_PLUGIN, ROLLED_OPTICS_PLUGIN, MENISCUS_OPTICS_PLUGIN, COHERENT_OPTICS_PLUGIN, RETURN_OPTICS_PLUGIN, VOLUME_OPTICS_PLUGIN, CONTOUR_OPTICS_PLUGIN, BALANCED_OPTICS_PLUGIN, LENS_OPTICS_PLUGIN, LIGHT_OPTICS_PLUGIN, RIM_OPTICS_PLUGIN, MOTION_OPTICS_PLUGIN, CURVED_OPTICS_PLUGIN, LEGACY_OPTICS_PLUGIN, DEFAULT_PLUGIN)
                            if path.is_file()), OPTICS_PLUGIN)
    hypr = compositor(args.instance)

    # Desktop autostart launches Quickshell asynchronously. Wait before loading
    # the renderer or changing its preset, not just before writing widget state.
    if restoring:
        wait_for_widgets()

    if args.style == "status":
        print(command(*hypr, "hyprglass", "status"))
        for config in ("clock", "performance"):
            print(f"{config}: {widget(config, 'prop', 'get', 'widgets', 'glassStyle')}")
            print(f"  material motion: {widget(config, 'prop', 'get', 'widgets', 'glassMotion')}")
        return

    if args.style == "off":
        set_widgets("off")
        save_style("off")
        apply_lua(hypr, "if hl.plugin.hyprglass then "
                  "hl.plugin.hyprglass.config({ enabled = false, "
                  "layers = { enabled = false } }) end")
        remember_style("off")
        print("Original widget material restored; glass rendering disabled.")
        return

    plugins = json.loads(command(*hypr, "-j", "plugin", "list"))
    loaded = next((p for p in plugins if p["name"].lower() == "hyprglass"), None)
    if loaded:
        check_material_version(args.style, loaded["version"])
    loaded_here = loaded is None
    if loaded_here:
        if not args.plugin.is_file():
            raise RuntimeError(f"Build HyprGlass first; plugin not found: {args.plugin}")

    try:
        save_style(args.style)
        if loaded_here:
            result = command(*hypr, "plugin", "load", str(args.plugin.resolve()))
            if result != "ok":
                raise RuntimeError(result)
        plugins = json.loads(command(*hypr, "-j", "plugin", "list"))
        active = next(p for p in plugins if p["name"].lower() == "hyprglass")
        check_material_version(args.style, active["version"])
        # Preset definitions are pending until HyprGlass's configReloaded hook.
        # Evaluating dofile alone changes the name but does not activate presets.
        result = command(*hypr, "reload")
        if result != "ok":
            raise RuntimeError(result)
        selected = json.loads(command(*hypr, "-j", "getoption", "plugin:hyprglass:layers:preset"))
        if selected.get("str") != f"widgets-{args.style}":
            raise RuntimeError(f"Source {CONFIG} from the Hyprland config before trying glass.")
        config_errors = command(*hypr, "configerrors")
        if config_errors:
            raise RuntimeError(f"Hyprland configuration errors: {config_errors}")
        state = status(hypr)
        if state.get("versionCheck") != "match" or not state["features"]["layers"]["active"]:
            raise RuntimeError("The plugin does not report compatible, active layer rendering.")
        set_widgets(args.style, motion=args.style in CURVED_STYLES)
        # Flush old material samples, including the stock build's layer-close
        # cache issue. The optics build also invalidates on layer closure.
        # Allow a clock tick to schedule rendering, then return to damage-driven updates.
        apply_lua(hypr, "hl.plugin.hyprglass.config({ layers = { force_live_resample = true } })")
        try:
            time.sleep(1.5)
        finally:
            apply_lua(hypr, "hl.plugin.hyprglass.config({ layers = { force_live_resample = false } })")
        rendered = status(hypr)
        if rendered.get("shaders") != "ready" or not rendered["features"]["layers"]["active"]:
            raise RuntimeError("The material did not reach a ready, active renderer.")
    except Exception:
        save_style("off")
        try:
            set_widgets("off")
        except (RuntimeError, subprocess.SubprocessError) as cleanup_error:
            print(f"Widget rollback: {cleanup_error}", file=sys.stderr)
        try:
            if loaded_here:
                command(*hypr, "plugin", "unload", str(args.plugin.resolve()))
            else:
                apply_lua(hypr, "hl.plugin.hyprglass.config({ enabled = false, "
                          "layers = { enabled = false } })")
        except (RuntimeError, subprocess.SubprocessError) as cleanup_error:
            print(f"Plugin rollback: {cleanup_error}", file=sys.stderr)
        raise
    remember_style(args.style)
    print(f"{args.style.capitalize()} material active on both widget columns.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
