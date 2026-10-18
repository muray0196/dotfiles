#!/usr/bin/env python3
"""Validate and explicitly run the desktop widget surfaces. No automatic plugin reload."""

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
from urllib.parse import unquote, urlparse

from preview import isolated_display

SOURCE = Path(__file__).resolve().parent
MATERIAL = SOURCE.parent / "liquid-glass-lab"
TINTS = tuple(json.loads((MATERIAL / "tints.json").read_text()))
CACHE_ROOT = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
CACHE = CACHE_ROOT / "quickshell-widgets"
OUTPUT = CACHE / "app"
FILES = ("DesktopShell.qml", "DesktopPanel.qml", "PanelContent.qml", "Layout.js", "Label.qml", "Button.qml", "DeviceIcon.qml", "MetricRow.qml", "Machine.qml",
         "History.qml", "Today.qml", "Clock.qml", "Calendar.qml", "Weather.qml", "Radar.qml", "Format.js")
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


def appearance(state, env, attribute, value):
    """Change one surface attribute, preserving the other and using light ink."""
    before = json.loads(control(state["instance"], "liquidglass"))
    control(state["instance"], "liquidglass", attribute, value)
    try:
        ipc(state["pid"], env, "foreground", False)
    except (OSError, RuntimeError):
        control(state["instance"], "liquidglass", attribute, before[attribute])
        raise


def reference_snapshot(app, output):
    """Use the running UI as the authority; bootstrap once if none is running."""
    env = os.environ.copy()
    if (CACHE / "session.json").exists():
        state, env = recorded()
        different = [name for name in FILES if (OUTPUT / name).read_bytes() != (app / name).read_bytes()]
        if different:
            raise RuntimeError("Running widget UI differs from the test source: " + ", ".join(different)
                               + ". Update the running foreground before comparing it.")
        snapshot = json.loads(ipc(state["pid"], env, "snapshot"))
        material = json.loads(control(state["instance"], "liquidglass"))
        origin = "running desktop"
    else:
        monitor = next(m for m in json.loads(control(session(env), "-j", "monitors")) if m["focused"])
        size = (monitor["width"], monitor["height"])
        if monitor["transform"] % 2:
            size = size[::-1]
        size = tuple(round(value / monitor["scale"]) for value in size)
        directory = output / "reference"
        with isolated_display(env, directory, logical_size=size) as display:
            display.update(WIDGET_SOURCE=str(SOURCE), WIDGET_AUTOMATION="0", WIDGET_TEXT="light",
                           WIDGET_RUNTIME_CACHE=str(directory / "runtime"))
            display.pop("WIDGET_SNAPSHOT", None)
            process = launch(display, app / "DesktopShell.qml", directory / "widgets.log")
            try:
                wait_for(lambda: (s if (s := json.loads(ipc(process.pid, display, "state"))).get("local") in ("Live", "Partial")
                                  and s.get("outdoor") == "Live" and s.get("radar") in ("Live", "Cached") else None),
                         "reference collectors", 50)
                snapshot = json.loads(ipc(process.pid, display, "snapshot"))
            finally:
                stop_process(process)
        material = {"clarity": "soft", "tint": "off"}
        origin = "one collector snapshot (desktop widgets not running)"
    sizes = {(p["screen"]["width"], p["screen"]["height"]) for p in snapshot["panels"]}
    if len(sizes) != 1 or len(snapshot["panels"]) != 5:
        raise RuntimeError("The five-widget reference must occupy one logical desktop size")
    # Radar caches rotate independently; retain exactly the tiles used in this
    # private snapshot so all scales render the same image bytes.
    tiles = output / "snapshot-tiles"
    tiles.mkdir(exist_ok=True)
    used = set()
    for frame in snapshot["readings"].get("radar", {}).get("frames", []):
        for tile in frame.get("radar_tiles", []):
            url = urlparse(tile["url"])
            if url.scheme == "file":
                source = Path(unquote(url.path))
                data = source.read_bytes()
                target = tiles / (hashlib.sha256(data).hexdigest() + source.suffix)
                target.write_bytes(data)
                used.add(target)
                tile["url"] = target.as_uri()
    for path in tiles.iterdir():
        if path.is_file() and path not in used:
            path.unlink()
    path = output / "snapshot.json"
    path.write_text(json.dumps(snapshot) + "\n")
    return snapshot, next(iter(sizes)), {"clarity": material["clarity"], "tint": material.get("tint", "black" if material.get("tone") == "dark" else "off")}, origin


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
    snapshot, logical_size, selected, origin = reference_snapshot(app, output)
    expected_geometry = sorted((p["side"] if p["left"] else logical_size[0] - p["side"] - p["width"],
                                p["top"], p["width"], p["height"]) for p in snapshot["panels"])
    left_edge = max(p["side"] + p["width"] for p in snapshot["panels"] if p["left"])
    right_edge = logical_size[0] - max(p["side"] + p["width"] for p in snapshot["panels"] if not p["left"])
    if right_edge <= left_edge + 4:
        raise RuntimeError("No unobstructed desktop center in the reference layout")
    results = []
    for scale in (1, 1.25, 2):
        directory = output / str(scale)
        directory.mkdir(exist_ok=True)
        processes = []
        with isolated_display(os.environ.copy(), directory, scale, logical_size) as env:
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
                           WIDGET_SNAPSHOT=str(output / "snapshot.json"))
                widgets = launch(env, app / "DesktopShell.qml", directory / "widgets.log")
                processes.append(widgets)
                state = wait_for(lambda: (s if (s := json.loads(ipc(widgets.pid, env, "state"))).get("snapshot") else None), "snapshot loaded")
                wait_for(lambda: len(widget_layers(instance)) == 5, "all five surfaces")
                replay = wait_for(lambda: (s if (s := json.loads(ipc(widgets.pid, env, "snapshot"))) == snapshot else None),
                                  "desktop layout, data, clock and radar parity")
                for attribute, value in selected.items():
                    control(instance, "liquidglass", attribute, value)
                # Dismiss only this disposable compositor's launcher notice.
                control(instance, "dismissnotify", "-1")
                time.sleep(0.3)
                clear = backend.capture(directory, "desktop-matched", env)
                if clear[:2] != tuple(round(value * scale) for value in logical_size):
                    raise RuntimeError("Captured resolution differs from the requested desktop size")
                def pixels(rect):
                    return tuple(round(value * scale) for value in rect)
                center = pixels((left_edge + 2, 0, right_edge - left_edge - 4, logical_size[1]))
                ipc(widgets.pid, env, "hideWidgets")
                wait_for(lambda: len(widget_layers(instance)) == 0, "hidden side surfaces")
                time.sleep(0.3)
                plain = backend.capture(directory, "desktop-background", env)
                # There must be no preview controls or hint surfaces in the center.
                center_difference = backend.difference(clear, plain, center)
                if center_difference > 0.01:
                    raise RuntimeError(f"Unexpected center content: difference {center_difference}")
                if backend.difference(clear, plain, pixels((0, 0, left_edge, logical_size[1]))) <= 0.1:
                    raise RuntimeError("Left surface did not render")
                if backend.difference(clear, plain, pixels((right_edge, 0, logical_size[0] - right_edge, logical_size[1]))) <= 0.1:
                    raise RuntimeError("Right surface did not render")
                ipc(widgets.pid, env, "showWidgets")
                wait_for(lambda: len(widget_layers(instance)) == 5, "restored five surfaces")
                selection = {"instance": instance, "pid": widgets.pid}
                # A stale foreground choice from an older process must not survive
                # selecting any of the new light-text-only desktop appearances.
                ipc(widgets.pid, env, "foreground", True)
                for clarity in ("clear", "soft", "diffused"):
                    appearance(selection, env, "clarity", clarity)
                    for tint in TINTS:
                        appearance(selection, env, "tint", tint)
                        status = json.loads(control(instance, "liquidglass"))
                        if (status["clarity"] != clarity or status["tint"] != tint
                                or json.loads(ipc(widgets.pid, env, "state"))["darkText"]):
                            raise RuntimeError(f"{clarity}/{tint} material/light foreground pairing failed")
                        time.sleep(0.4)
                        shot = backend.capture(directory, f"desktop-{clarity}-{tint}", env)
                        if backend.difference(shot, plain, center) > 0.01:
                            raise RuntimeError(f"{clarity}/{tint} changed pixels outside the widget surfaces")
                appearance(selection, env, "clarity", "soft")
                appearance(selection, env, "tint", "off")
                ipc(background.pid, env, "background", 1, target="fixture")
                time.sleep(0.4)
                backend.capture(directory, "desktop-desert", env)
                appearance(selection, env, "clarity", "diffused")
                appearance(selection, env, "tint", "black")
                time.sleep(0.4)
                backend.capture(directory, "desktop-diffused-dark-desert", env)
                before = json.loads(control(instance, "liquidglass"))["frames"]
                ipc(background.pid, env, "moving", True, target="fixture")
                time.sleep(2)
                stats = json.loads(control(instance, "liquidglass"))
                if stats["failed"] or stats["frames"] <= before:
                    raise RuntimeError("Moving desktop background did not render")
                ipc(background.pid, env, "moving", False, target="fixture")
                layers = widget_layers(instance)
                if sorted((p["x"], p["y"], p["w"], p["h"]) for p in layers) != expected_geometry:
                    raise RuntimeError("Compositor surface geometry differs from the desktop reference")
                results.append({"scale": scale, "layers": layers, "center_difference": center_difference,
                                "state": state, "stats": stats, "automation": False,
                                "logical_size": logical_size, "panels": replay["panels"],
                                "snapshot_matches": True, "geometry_matches": True})
                # Unload only in this owned nested instance, while widgets exist.
                if control(instance, "plugin", "unload", str(plugin)).strip() != "ok":
                    raise RuntimeError("Nested backend unload failed")
            finally:
                for process in reversed(processes):
                    stop_process(process)
    if fingerprint() != tested_fingerprint:
        raise RuntimeError("Widget source changed during validation; rerun check")
    if origin == "running desktop" and any((OUTPUT / name).read_bytes() != (app / name).read_bytes() for name in FILES):
        raise RuntimeError("Running foreground changed during validation; rerun check")
    (output / "results.json").write_text(json.dumps({"fingerprint": tested_fingerprint,
        "integration_fingerprint": integration_fingerprint(), "results": results,
        "reference": {"origin": origin, "logical_size": logical_size, "appearance": selected,
                      "snapshot_sha256": hashlib.sha256((output / "snapshot.json").read_bytes()).hexdigest()},
        "normal_session_modified": False, "controls_in_desktop_center": False}, indent=2) + "\n")
    print(f"Desktop rendering, data, show/hide, motion and center-clear checks passed at three scales: {output}")


def start(load_backend, selected_clarity, selected_tint):
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
    env.pop("WIDGET_SNAPSHOT", None)
    process = launch(env, OUTPUT / "DesktopShell.qml", CACHE / "widgets.log")
    try:
        wait_for(lambda: len(widget_layers(instance)) == 5, "desktop widgets")
        wait_for(lambda: json.loads(ipc(process.pid, env, "state")).get("receivedAt"), "widget data")
        selection = {"instance": instance, "pid": process.pid}
        appearance(selection, env, "clarity", selected_clarity)
        appearance(selection, env, "tint", selected_tint)
        wait_for(lambda: json.loads(control(instance, "liquidglass")).get("frames"), "first material frame")
        if json.loads(control(instance, "liquidglass"))["failed"]:
            raise RuntimeError("The backend could not render this desktop output")
        (CACHE / "session.json").write_text(json.dumps({"instance": instance, "pid": process.pid,
            "plugin": str(plugin)}) + "\n")
    except BaseException:
        stop_process(process)
        raise
    print("All five desktop surfaces are running. No preview controls are shown.")


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
    sub.add_parser("check", help="validate desktop-matched layout/data at three scales in disposable compositors")
    launch_parser = sub.add_parser("start", help="start validated widgets on the current desktop")
    launch_parser.add_argument("--load-backend", action="store_true", help="explicitly allow first load of the tested backend; never reload")
    launch_parser.add_argument("--clarity", choices=("clear", "soft", "diffused"), default="soft",
                               help="background detail: clear, gently smoothed soft (default), or diffused")
    launch_parser.add_argument("--tint", choices=TINTS, default="off",
                               help="optional surface tint, independent of clarity (default: off)")
    sub.add_parser("stop", help="close these widgets; leave the accepted backend loaded")
    sub.add_parser("toggle", help="show/hide all five surfaces")
    sub.add_parser("status", help="show runtime state")
    for attribute, values, help_text in (
            ("clarity", ("clear", "soft", "diffused"), "background detail: Clear, Soft, or Diffused"),
            ("tint", TINTS, "optional tint color; Off preserves the original material")):
        setting = sub.add_parser(attribute, help=help_text)
        setting.add_argument("value", nargs="?", choices=values, help="omit to read the current setting")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Serialize first load, start/stop and appearance updates. Keep the lock
        # open until this controller process exits; it is never inherited by qs.
        lock = (CACHE / ("check.lock" if args.command == "check" else "controller.lock")).open("w")
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == "check":
            check()
        elif args.command == "start":
            start(args.load_backend, args.clarity, args.tint)
        else:
            state, env = recorded()
            if args.command == "stop":
                command(["qs", "kill", "--pid", str(state["pid"])], env=env)
                (CACHE / "session.json").unlink()
            elif args.command == "toggle":
                visible = json.loads(ipc(state["pid"], env, "state"))["visible"]
                ipc(state["pid"], env, "hideWidgets" if visible else "showWidgets")
            elif args.command == "status":
                status = json.loads(ipc(state["pid"], env, "state"))
                material = json.loads(control(state["instance"], "liquidglass"))
                status["clarity"] = material["clarity"]
                status["tint"] = material["tint"]
                print(json.dumps(status))
            elif args.command in ("clarity", "tint"):
                if args.value:
                    appearance(state, env, args.command, args.value)
                result = json.loads(control(state["instance"], "liquidglass"))
                print(args.command + ": " + result[args.command])
        return 0
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(f"desktop-widgets: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
