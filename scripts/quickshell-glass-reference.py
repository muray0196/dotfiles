#!/usr/bin/env python3
"""Open a native Clear-glass comparison scene; restore the renderer on exit."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
SCENE = ROOT / "scripts/quickshell-glass-reference/shell.qml"
VERSION = "0.10.0-optics24"
REFERENCE_VERSION = VERSION + "-reference"
LIBRARY = Path.home() / ".local/lib/quickshell-glass"


def command(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip())
    return result.stdout.strip()


def checked(*args):
    result = command(*args)
    if result != "ok":
        raise RuntimeError(result)


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stop", action="store_true", help="close the scene and restore the desktop renderer")
    parser.add_argument("--instance", help="Hyprland instance; inferred when only one is running")
    parser.add_argument("--screen", help="output for internal captures; defaults to the focused monitor")
    args = parser.parse_args()
    for name in ("hyprctl", "qs"):
        if not shutil.which(name):
            raise RuntimeError(f"Required command is unavailable: {name}")

    instances = json.loads(command("hyprctl", "-j", "instances"))
    instance_name = args.instance or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    candidates = [item for item in instances if not instance_name or item["instance"] == instance_name]
    if len(candidates) != 1:
        raise RuntimeError("Choose the desktop session with --instance.")
    instance = candidates[0]
    hypr = ("hyprctl", "--instance", instance["instance"])
    ipc = ("qs", "--no-color", "ipc", "-p", str(SCENE), "--any-display", "call", "reference")
    if args.stop:
        command(*ipc, "quit")
        print("Reference scene closing; its launcher restores the desktop renderer.")
        return

    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    if not runtime.is_dir() or runtime.stat().st_uid != os.getuid():
        raise RuntimeError("The current user's runtime directory is unavailable.")
    lock_fd = os.open(runtime / "quickshell-glass-reference.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("The reference scene is already open. Use --stop to close it.") from None

        def loaded():
            return next((p for p in json.loads(command(*hypr, "-j", "plugin", "list"))
                         if p["name"].lower() == "hyprglass"), None)

        current = loaded()
        if not current or current["version"] != VERSION:
            raise RuntimeError(f"Start the desktop's {VERSION} Clear material before opening this scene.")
        # Shaders compile lazily; hidden desktop widgets legitimately leave them pending.
        state = json.loads(command(*hypr, "-j", "hyprglass", "status"))
        if state.get("shaders") not in ("ready", "pending") or not state["features"]["layers"]["active"]:
            raise RuntimeError("The desktop glass renderer is not enabled or has failed.")
        hypr_version = command("pkg-config", "--modversion", "hyprland")
        original = LIBRARY / f"hyprglass-{VERSION}-{hypr_version}.so"
        reference = LIBRARY / f"hyprglass-{REFERENCE_VERSION}-{hypr_version}.so"
        for path in (original, reference):
            if not path.is_file():
                raise RuntimeError(f"Build the reference renderer first (docs/quickshell-glass.md): {path}")
        monitors = json.loads(command(*hypr, "-j", "monitors"))
        monitor = next((m for m in monitors if m["name"] == args.screen), None) if args.screen else next(
            (m for m in monitors if m.get("focused")), monitors[0])
        if monitor is None:
            raise RuntimeError(f"Output is not connected: {args.screen}")
        env = dict(os.environ, WAYLAND_DISPLAY=instance["wl_socket"], GLASS_REFERENCE_SCREEN=monitor["name"],
                   GLASS_REFERENCE_INTERACTIVE="1" if monitor.get("focused") else "0")
        log_dir = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "dotfiles-linux"
        log_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        child = None
        changed = False
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        try:
            checked(*hypr, "eval", "hl.plugin.hyprglass.config({ layers = { enabled = false } })")
            # From here even a failed unload must restore the enabled state.
            changed = True
            checked(*hypr, "plugin", "unload", str(original))
            checked(*hypr, "plugin", "load", str(reference))
            checked(*hypr, "reload")
            if command(*hypr, "configerrors"):
                raise RuntimeError(command(*hypr, "configerrors"))
            if loaded()["version"] != REFERENCE_VERSION:
                raise RuntimeError("The reference renderer did not load.")
            with (log_dir / "quickshell-glass-reference.log").open("w") as log:
                child = subprocess.Popen(["qs", "--no-color", "-p", str(SCENE)], env=env,
                                         stdin=subprocess.DEVNULL, stdout=log, stderr=log)
                print("Reference scene open. Close or Escape restores the desktop renderer.", flush=True)
                result = child.wait()
                if result:
                    raise RuntimeError(f"Reference scene exited with code {result}; see {log_dir / 'quickshell-glass-reference.log'}")
        except KeyboardInterrupt:
            pass
        finally:
            # Finish one restoration even if the terminal sends another signal.
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            if child and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            if changed:
                current = loaded()
                if current and current["version"] == REFERENCE_VERSION:
                    checked(*hypr, "eval", "hl.plugin.hyprglass.config({ layers = { enabled = false } })")
                    checked(*hypr, "plugin", "unload", str(reference))
                    current = None
                if current is None:
                    checked(*hypr, "plugin", "load", str(original))
                elif current["version"] != VERSION:
                    raise RuntimeError("Another renderer replaced the test renderer; it was left unchanged.")
                checked(*hypr, "reload")
                checked(*hypr, "eval", "hl.plugin.hyprglass.config({ layers = { force_live_resample = true } })")
                try:
                    time.sleep(1.5)
                finally:
                    checked(*hypr, "eval", "hl.plugin.hyprglass.config({ layers = { force_live_resample = false } })")
                state = json.loads(command(*hypr, "-j", "hyprglass", "status"))
                if state.get("shaders") not in ("ready", "pending") or not state["features"]["layers"]["active"]:
                    raise RuntimeError("The original renderer was reloaded but is disabled or has failed.")
                print("Desktop renderer restored; saved material and wallpaper unchanged.", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
