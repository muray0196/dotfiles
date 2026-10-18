#!/usr/bin/env python3
"""Validate and explicitly run the two desktop widgets. No automatic plugin reload."""

import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

from preview import isolated_display

SOURCE = Path(__file__).resolve().parent
MATERIAL = SOURCE.parent / "liquid-glass-lab"
CACHE_ROOT = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE = CACHE_ROOT / "quickshell-widgets"
OUTPUT = CACHE / "app"
FILES = ("DesktopShell.qml", "DesktopPanel.qml", "PanelContent.qml", "Layout.js", "Label.qml", "Button.qml", "DeviceIcon.qml", "MetricRow.qml", "Machine.qml",
         "History.qml", "Today.qml", "Weather.qml", "Radar.qml", "Format.js")
sys.path.insert(0, str(MATERIAL))
spec = importlib.util.spec_from_file_location("accepted_desktop_backend", MATERIAL / "desktop.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


def command(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=45, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name}: {result.stdout}{result.stderr}")
    return result.stdout


def tested_backend():
    tested = CACHE_ROOT / "dotfiles-liquid-glass-lab/desktop"
    result = json.loads((tested / "results.json").read_text())
    if (not all(result["checks"].values()) or not result["checks"].get("replacement_binary_runs_after_unload")
            or result["sources_sha256"] != backend.fingerprint(MATERIAL)):
        raise RuntimeError("Accepted backend needs its isolated desktop-check for the current source")
    binary = tested / "liquid-glass.so"
    if hashlib.sha256(binary.read_bytes()).hexdigest() != result["plugin_sha256"]:
        raise RuntimeError("Backend binary differs from its validation receipt")
    return binary, result


def fingerprint():
    _, result = tested_backend()
    digest = hashlib.sha256(result["plugin_sha256"].encode())
    for name in (*FILES, "runtime.py", "collect.py", "desktop.py", "preview.py", "DesktopBackdrop.qml"):
        digest.update(name.encode() + b"\0" + (SOURCE / name).read_bytes())
    return digest.hexdigest()


def integration_fingerprint():
    """Foreground text/layout edits do not invalidate compositor integration."""
    _, result = tested_backend()
    digest = hashlib.sha256(result["plugin_sha256"].encode())
    for name in ("DesktopShell.qml", "DesktopPanel.qml", "Layout.js", "desktop.py", "runtime.py", "collect.py", "preview.py", "DesktopBackdrop.qml"):
        digest.update(name.encode() + b"\0" + (SOURCE / name).read_bytes())
    return digest.hexdigest()


def validate_ui():
    for name in FILES:
        if not name.endswith(".qml"):
            continue
        result = subprocess.run(["/usr/lib/qt6/bin/qmlformat", "--ignore-settings", str(SOURCE / name)],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, timeout=15)
        if result.returncode:
            raise RuntimeError(f"Invalid QML in {name}: {result.stderr.strip()}")


def prepare(output=OUTPUT):
    binary, result = tested_backend()
    output.mkdir(parents=True, exist_ok=True, mode=0o700)
    for name in FILES:
        shutil.copy2(SOURCE / name, output / name)
    plugin = backend.publish(binary, CACHE / "backend")
    return plugin, result


def session(env):
    display = env.get("WAYLAND_DISPLAY")
    if not display:
        raise RuntimeError("Run from the intended Hyprland graphical session")
    instances = json.loads(command(["hyprctl", "-j", "instances"]))
    match = next((i for i in instances if i["wl_socket"] == display), None)
    if not match:
        raise RuntimeError("No matching Hyprland instance")
    return match


def control(instance, *args):
    return command(["hyprctl", "-i", instance["instance"], *args])


def ipc(pid, env, method, *args, target="widgets"):
    return command(["qs", "ipc", "--pid", str(pid), "call", target, method,
                    *[str(v).lower() if isinstance(v, bool) else str(v) for v in args]], env=env)


def wait_for(test, label, timeout=40):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            value = test()
            if value:
                return value
        except (RuntimeError, ValueError):
            pass
        time.sleep(0.25)
    raise RuntimeError(f"Timed out waiting for {label}")


def launch(env, qml, log):
    with log.open("w") as stream:
        return subprocess.Popen(["qs", "--path", str(qml)], env=env, stdout=stream,
                                stderr=subprocess.STDOUT, start_new_session=True)


def stop_process(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def widget_layers(instance):
    result = []
    for monitor in json.loads(control(instance, "-j", "layers")).values():
        for layer in monitor.get("levels", {}).values():
            result += [s for s in layer if s.get("namespace") == "liquid-glass-v1"]
    return result


def check():
    validate_ui()
    app = CACHE / "check/app"
    plugin, accepted = prepare(app)
    tested_fingerprint = fingerprint()
    output = CACHE / "check"
    output.mkdir(exist_ok=True)
    shutil.copy2(SOURCE / "DesktopBackdrop.qml", app / "DesktopBackdrop.qml")
    for name in ("flower.png", "desert.png"):
        shutil.copy2(MATERIAL / "assets" / name, app / name)
    command(["/usr/lib/qt6/bin/qsb", "--glsl", "150,300 es", "-o", str(app / "desert.frag.qsb"),
             str(MATERIAL / "shaders/desert.frag")])
    results = []
    for scale in (1, 1.25, 2):
        directory = output / str(scale)
        directory.mkdir(exist_ok=True)
        processes = []
        with isolated_display(os.environ.copy(), directory, scale) as env:
            instance = session(env)
            try:
                version = json.loads(control(instance, "-j", "version"))
                if version["abiHash"] != accepted["version"]["abiHash"]:
                    raise RuntimeError("Nested compositor ABI differs from accepted backend")
                if control(instance, "plugin", "load", str(plugin)).strip() != "ok":
                    raise RuntimeError("Nested backend load failed")
                background = launch(env, app / "DesktopBackdrop.qml", directory / "background.log")
                processes.append(background)
                env.update(WIDGET_SOURCE=str(SOURCE), WIDGET_AUTOMATION="0", WIDGET_TEXT="light",
                           WIDGET_RUNTIME_CACHE=str(directory / "runtime"))
                widgets = launch(env, app / "DesktopShell.qml", directory / "widgets.log")
                processes.append(widgets)
                state = wait_for(lambda: json.loads(ipc(widgets.pid, env, "state")), "widget IPC")
                wait_for(lambda: len(widget_layers(instance)) == 2, "both side surfaces")
                if scale == 1:
                    state = wait_for(lambda: (s if (s := json.loads(ipc(widgets.pid, env, "state"))).get("local") in ("Live", "Partial")
                                     and s.get("outdoor") == "Live" and s.get("radar") in ("Live", "Cached") else None), "continuous collectors", 50)
                else:
                    time.sleep(3)
                # Dismiss only this disposable compositor's launcher notice.
                control(instance, "dismissnotify", "-1")
                time.sleep(0.3)
                clear = backend.capture(directory, "desktop-clear", env)
                ipc(widgets.pid, env, "hideWidgets")
                wait_for(lambda: len(widget_layers(instance)) == 0, "hidden side surfaces")
                time.sleep(0.3)
                plain = backend.capture(directory, "desktop-background", env)
                # There must be no preview controls or hint surfaces in the center.
                center_difference = backend.difference(clear, plain, (700, 100, 520, 880))
                if center_difference > 0.01:
                    raise RuntimeError(f"Unexpected center content: difference {center_difference}")
                if backend.difference(clear, plain, (30, 100, 400, 850)) <= 0.1:
                    raise RuntimeError("Left surface did not render")
                if backend.difference(clear, plain, (1490, 100, 400, 850)) <= 0.1:
                    raise RuntimeError("Right surface did not render")
                ipc(widgets.pid, env, "showWidgets")
                wait_for(lambda: len(widget_layers(instance)) == 2, "restored side surfaces")
                ipc(widgets.pid, env, "foreground", True)
                if not json.loads(ipc(widgets.pid, env, "state"))["darkText"]:
                    raise RuntimeError("Dark foreground selection failed")
                time.sleep(0.4)
                backend.capture(directory, "desktop-clear-dark-text", env)
                ipc(widgets.pid, env, "foreground", False)
                if json.loads(ipc(widgets.pid, env, "state"))["darkText"]:
                    raise RuntimeError("Light foreground selection failed")
                ipc(background.pid, env, "background", 1, target="fixture")
                time.sleep(0.4)
                backend.capture(directory, "desktop-desert", env)
                before = json.loads(control(instance, "liquidglass"))["frames"]
                ipc(background.pid, env, "moving", True, target="fixture")
                time.sleep(2)
                stats = json.loads(control(instance, "liquidglass"))
                if stats["failed"] or stats["frames"] <= before:
                    raise RuntimeError("Moving desktop background did not render")
                ipc(background.pid, env, "moving", False, target="fixture")
                layers = widget_layers(instance)
                if len(layers) != 2:
                    raise RuntimeError("Unexpected surface count")
                results.append({"scale": scale, "layers": layers, "center_difference": center_difference,
                                "state": state, "stats": stats, "automation": False})
                # Unload only in this owned nested instance, while widgets exist.
                if control(instance, "plugin", "unload", str(plugin)).strip() != "ok":
                    raise RuntimeError("Nested backend unload failed")
            finally:
                for process in reversed(processes):
                    stop_process(process)
    if fingerprint() != tested_fingerprint:
        raise RuntimeError("Widget source changed during validation; rerun check")
    (output / "results.json").write_text(json.dumps({"fingerprint": tested_fingerprint,
        "integration_fingerprint": integration_fingerprint(), "results": results,
        "normal_session_modified": False, "controls_in_desktop_center": False}, indent=2) + "\n")
    print(f"Desktop rendering, data, show/hide, motion and center-clear checks passed at three scales: {output}")


def start(load_backend):
    receipt = json.loads((CACHE / "check/results.json").read_text())
    if receipt.get("integration_fingerprint") != integration_fingerprint() or len(receipt.get("results", [])) != 3:
        raise RuntimeError("Run desktop.py check for the current desktop integration before starting")
    validate_ui()
    env = os.environ.copy()
    instance = session(env)
    state_path = CACHE / "session.json"
    if state_path.exists():
        old = json.loads(state_path.read_text())
        active = json.loads(command(["hyprctl", "-j", "instances"]))
        pid_file = Path(f"/proc/{old['pid']}/cmdline")
        if (old["instance"] in active and pid_file.exists()
                and str(OUTPUT / "DesktopShell.qml").encode() in pid_file.read_bytes().split(b"\0")):
            raise RuntimeError("The desktop widgets are already running")
        # A previous login's record must not prevent the next login from starting.
        state_path.unlink()
    plugin, accepted = prepare()
    if json.loads(control(instance, "-j", "version"))["abiHash"] != accepted["version"]["abiHash"]:
        raise RuntimeError("Running compositor ABI differs from validated backend")
    loaded = "independent-liquid-glass" in control(instance, "plugin", "list")
    if not loaded and not load_backend:
        raise RuntimeError("The material backend is not loaded. --load-backend explicitly opts into loading the tested plugin in this session.")
    if not loaded:
        if control(instance, "plugin", "load", str(plugin)).strip() != "ok":
            raise RuntimeError("Backend load failed")
    else:
        mapped = {line.split()[-1] for line in Path(f"/proc/{instance['pid']}/maps").read_text().splitlines()
                  if "liquid-glass-" in line and ".so" in line}
        if not any(Path(path).is_file() and hashlib.sha256(Path(path).read_bytes()).hexdigest() == accepted["plugin_sha256"] for path in mapped):
            raise RuntimeError("The loaded material is not the validated binary; no reload was attempted")
    # No replacement/reload path exists here. A running backend is reused.
    env.update(WIDGET_SOURCE=str(SOURCE), WIDGET_AUTOMATION="1", WIDGET_TEXT="light")
    process = launch(env, OUTPUT / "DesktopShell.qml", CACHE / "widgets.log")
    try:
        wait_for(lambda: len(widget_layers(instance)) == 2, "desktop widgets")
        wait_for(lambda: json.loads(ipc(process.pid, env, "state")).get("receivedAt"), "widget data")
        wait_for(lambda: json.loads(control(instance, "liquidglass")).get("frames"), "first material frame")
        if json.loads(control(instance, "liquidglass"))["failed"]:
            raise RuntimeError("The backend could not render this desktop output")
        (CACHE / "session.json").write_text(json.dumps({"instance": instance, "pid": process.pid,
            "plugin": str(plugin)}) + "\n")
    except BaseException:
        stop_process(process)
        raise
    print("Both desktop widgets are running. No preview controls are shown.")


def recorded():
    state = json.loads((CACHE / "session.json").read_text())
    instance = state["instance"]
    if instance not in json.loads(command(["hyprctl", "-j", "instances"])):
        raise RuntimeError("Recorded compositor session is no longer running")
    pid = state["pid"]
    commandline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    if str(OUTPUT / "DesktopShell.qml").encode() not in commandline:
        raise RuntimeError("Recorded PID no longer belongs to these widgets")
    return state, os.environ | {"WAYLAND_DISPLAY": instance["wl_socket"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="validate only in disposable nested compositors")
    launch_parser = sub.add_parser("start", help="start validated widgets on the current desktop")
    launch_parser.add_argument("--load-backend", action="store_true", help="explicitly allow first load of the tested backend; never reload")
    sub.add_parser("stop", help="close these widgets; leave the accepted backend loaded")
    sub.add_parser("toggle", help="show/hide both side panels")
    sub.add_parser("status", help="show runtime state")
    foreground = sub.add_parser("text", help="choose stable Clear text colors")
    foreground.add_argument("value", choices=("light", "dark"))
    args = parser.parse_args()
    os.umask(0o077)
    try:
        CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Serialize first load, start/stop and foreground updates. Keep the lock
        # open until this controller process exits; it is never inherited by qs.
        lock = (CACHE / ("check.lock" if args.command == "check" else "controller.lock")).open("w")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == "check":
            check()
        elif args.command == "start":
            start(args.load_backend)
        else:
            state, env = recorded()
            if args.command == "stop":
                command(["qs", "kill", "--pid", str(state["pid"])], env=env)
                (CACHE / "session.json").unlink()
            elif args.command == "toggle":
                visible = json.loads(ipc(state["pid"], env, "state"))["visible"]
                ipc(state["pid"], env, "hideWidgets" if visible else "showWidgets")
            elif args.command == "status":
                print(ipc(state["pid"], env, "state").strip())
            elif args.command == "text":
                ipc(state["pid"], env, "foreground", args.value == "dark")
        return 0
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(f"desktop-widgets: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
