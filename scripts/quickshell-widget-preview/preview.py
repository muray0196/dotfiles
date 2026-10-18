#!/usr/bin/env python3
"""Build and review isolated widget UI. Never controls Hyprland or active widgets."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parent
MATERIAL = SOURCE.parent / "liquid-glass-lab"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-widget-preview"


@contextmanager
def isolated_display(env, cache=None, scale=1, logical_size=None):
    """No plugin operations. Select only the compositor PID launched here."""
    if not env.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Run capture from your graphical session (WAYLAND_DISPLAY is required).")
    cache = cache or CACHE
    cache.mkdir(parents=True, exist_ok=True)
    config = cache / "nested.lua"
    config.write_text('''-- Disposable UI preview; no includes, startup tasks or plugins.
hl.monitor({output = "", mode = "1920x1080@60", position = "auto", scale = 1})
hl.config({
  general = {gaps_in = 0, gaps_out = 0, border_size = 0},
  animations = {enabled = false},
  decoration = {rounding = 0, blur = {enabled = false}, shadow = {enabled = false}},
  misc = {disable_hyprland_logo = true, disable_splash_rendering = true},
  xwayland = {enabled = false},
})
-- Optical proofs resize between fixtures. Tiling would silently stretch the
-- reference scene after the first load, defeating its fixed source alignment.
hl.window_rule({name = "optical-proof-size", match = {class = "liquid-glass-lab-proof"}, float = true})
'''.replace("scale = 1}", f"scale = {scale}}}"))
    child = env.copy()
    child.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    child.update(LIBSEAT_BACKEND="widget-preview-disabled", HYPRLAND_NO_SD_VARS="1",
                 HYPRLAND_NO_SD_NOTIFY="1", HYPRLAND_NO_RT="1")
    with (cache / "nested.log").open("w") as log:
        process = subprocess.Popen(["Hyprland", "--config", str(config)], env=child,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            instance = None
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and process.poll() is None:
                instances = json.loads(checked(["hyprctl", "-j", "instances"]))
                instance = next((i for i in instances if i["pid"] == process.pid), None)
                if instance:
                    monitors = json.loads(checked(["hyprctl", "-i", instance["instance"], "-j", "monitors"]))
                    if monitors:
                        if any(not m["name"].startswith("WAYLAND-") for m in monitors):
                            raise RuntimeError("The preview requires a nested Wayland output.")
                        break
                time.sleep(0.1)
            else:
                raise RuntimeError(f"Nested preview did not start; see {cache / 'nested.log'}")
            if logical_size:
                # Parent window management can resize a Wayland output at any
                # time. A virtual output in this owned compositor stays fixed.
                ctl = ["hyprctl", "-i", instance["instance"]]
                width, height = (round(value * scale) for value in logical_size)
                checked([*ctl, "output", "create", "headless", "widget-validation"])
                # Plugin load/unload reloads the compositor configuration, so
                # these rules must survive beyond a transient `hyprctl eval`.
                with config.open("a") as rules:
                    # Headless outputs composite a software cursor into captures.
                    rules.write('hl.config({cursor = {invisible = true}})\n')
                    rules.write('hl.monitor({output = "widget-validation", '
                                f'mode = "{width}x{height}@60", position = "0x0", scale = {scale}}})\n')
                    for monitor in monitors:
                        rules.write('hl.monitor({output = ' + json.dumps(monitor["name"]) + ', disabled = true})\n')
                checked([*ctl, "reload"])
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    active = json.loads(checked([*ctl, "-j", "monitors"]))
                    if len(active) == 1 and (active[0]["name"], active[0]["width"], active[0]["height"], active[0]["scale"]) == (
                            "widget-validation", width, height, scale):
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError("Could not establish the fixed desktop validation output")
            child.update(WAYLAND_DISPLAY=instance["wl_socket"], HYPRLAND_INSTANCE_SIGNATURE=instance["instance"],
                         QT_QPA_PLATFORM="wayland", QSG_RHI_BACKEND="opengl")
            yield child
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)


def checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, check=False, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name}: {result.stdout}{result.stderr}")
    return result.stdout


def build(renderer=False):
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    material = CACHE / "material"
    material.mkdir(exist_ok=True)
    fingerprints = {}
    for name in ("Glass.qml", "BackdropSource.qml"):
        path = MATERIAL / name
        shutil.copy2(path, material / name)
        fingerprints[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    qsb = shutil.which("qsb") or "/usr/lib/qt6/bin/qsb"
    for name in ("glass", "blur", "desert"):
        path = MATERIAL / "shaders" / f"{name}.frag"
        checked([qsb, "--glsl", "150,300 es", "-o", str(material / f"{name}.frag.qsb"), str(path)])
        fingerprints[f"{name}.frag"] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ("flower.png", "desert.png"):
        shutil.copy2(MATERIAL / "assets" / name, material / name)
    # Retire only the previous preview's generated adaptive-foreground files.
    for path in (CACHE / "Ink.qml", CACHE / "foreground.frag.qsb",
                 material / "AdaptiveInk.qml", material / "ink.frag.qsb"):
        path.unlink(missing_ok=True)
    for pattern in ("*.qml", "*.js"):
        for path in SOURCE.glob(pattern):
            shutil.copy2(path, CACHE / path.name)
    (CACHE / "material-sha256.json").write_text(json.dumps(fingerprints, indent=2) + "\n")
    if renderer:
        flags = shlex.split(checked(["pkg-config", "--cflags", "--libs", "Qt6Quick", "Qt6Test"]))
        checked(["g++", "-std=c++20", "-O2", "-fPIC", "-pie", "-Wall", "-Wextra", "-Werror", str(SOURCE / "render.cpp"), "-o", str(CACHE / "render"), *flags])


def check_quickshell(env, live):
    with isolated_display(env) as display, (CACHE / "quickshell.log").open("w") as log:
        display.update(WIDGET_PREVIEW_SOURCE=str(SOURCE), WIDGET_PREVIEW_LIVE="1" if live else "0")
        process = subprocess.Popen(["qs", "--path", str(CACHE / "shell.qml")], env=display,
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 40
            state = {}
            while time.monotonic() < deadline and process.poll() is None:
                result = subprocess.run(["qs", "ipc", "--pid", str(process.pid), "call", "preview", "state"],
                                        env=display, text=True, capture_output=True, timeout=3)
                if result.returncode == 0:
                    state = json.loads(result.stdout)
                    if not live or state.get("demo") is False:
                        break
                time.sleep(0.25)
            else:
                raise RuntimeError(f"Quickshell did not become ready; see {CACHE / 'quickshell.log'}")
            captures = CACHE / "captures"
            captures.mkdir(exist_ok=True)
            if live:
                # Observe repeated two-second updates, not only initial admission.
                time.sleep(6)
                state = json.loads(checked(["qs", "ipc", "--pid", str(process.pid), "call", "preview", "state"], env=display))
            for dark in (False, True):
                checked(["qs", "ipc", "--pid", str(process.pid), "call", "preview", "foreground", str(dark).lower()], env=display)
                state = json.loads(checked(["qs", "ipc", "--pid", str(process.pid), "call", "preview", "state"], env=display))
                if state["darkText"] != dark:
                    raise RuntimeError("Quickshell foreground selection failed")
                time.sleep(1)
                name = "quickshell-" + ("live-" if live else "") + "soft" + ("-dark-text" if dark else "") + ".png"
                target = captures / name
                target.unlink(missing_ok=True)
                checked(["qs", "ipc", "--pid", str(process.pid), "call", "preview", "capture", str(target)], env=display)
                deadline = time.monotonic() + 5
                while not target.exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if not target.exists():
                    raise RuntimeError("Quickshell scene capture did not finish")
            (captures / ("quickshell-live.json" if live else "quickshell.json")).write_text(json.dumps({
                "state": state, "path": "Actual Quickshell scene grab in disposable nested Hyprland",
                "plugin_loaded": False, "automation_enabled": False,
            }, indent=2) + "\n")
            print("Quickshell loaded, IPC foreground controls passed, and complete window captures saved.")
        finally:
            if process.poll() is None:
                # Process groups also contain bounded one-shot collectors.
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="copy the accepted material unchanged and compile its shaders")
    run = sub.add_parser("run", help="open a separate ordinary Quickshell window")
    run.add_argument("--text", choices=("light", "dark"), default="light", help="stable Soft foreground; choose dark for bright wallpaper")
    run.add_argument("--direction", choices=("lens", "duet", "islands", "split"), default="lens", help="lens is the selected layout; duet remains an alias")
    run.add_argument("--background", choices=("flower", "desert", "bright", "dark", "detail"), default="flower")
    run.add_argument("--live", action="store_true", help="read existing collectors; no remote desktop automation")
    sub.add_parser("stop", help="close only this study's Quickshell instance")
    check = sub.add_parser("check", help="verify the actual Quickshell window in a disposable nested compositor")
    check.add_argument("--live", action="store_true", help="also verify read-only live collectors")
    capture = sub.add_parser("capture", help="render directions, Soft stress cases, and motion clips")
    capture.add_argument("--snapshot", type=Path, help="optional real collector snapshot (private, local file)")
    capture.add_argument("--stills-only", action="store_true", help="omit the six-second moving-background recording")
    args = parser.parse_args()
    try:
        if args.command == "stop":
            return subprocess.call(["qs", "kill", "--path", str(CACHE / "shell.qml")])
        build(renderer=args.command == "capture")
        if args.command == "build":
            print(f"Built {CACHE}")
            return 0
        env = os.environ.copy()
        env.setdefault("QSG_RHI_BACKEND", "opengl")
        env["TZ"] = "Asia/Tokyo"
        if args.command == "check":
            check_quickshell(env, args.live)
            return 0
        if args.command == "run":
            env.update(WIDGET_PREVIEW_SOURCE=str(SOURCE),
                       WIDGET_PREVIEW_TEXT=args.text,
                       WIDGET_PREVIEW_DIRECTION=str({"lens": 0, "duet": 0, "islands": 1, "split": 2}[args.direction]),
                       WIDGET_PREVIEW_BACKGROUND=str(("flower", "desert", "bright", "dark", "detail").index(args.background)),
                       WIDGET_PREVIEW_LIVE="1" if args.live else "0")
            return subprocess.call(["qs", "--no-duplicate", "--path", str(CACHE / "shell.qml")], env=env)
        env["QT_SCALE_FACTOR"] = "1"
        with isolated_display(env) as display:
            return subprocess.call([str(CACHE / "render"), str(CACHE), str(args.snapshot.resolve()) if args.snapshot else "", "stills" if args.stills_only else "motion"], env=display)
    except (OSError, RuntimeError) as error:
        print(f"widget-preview: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
