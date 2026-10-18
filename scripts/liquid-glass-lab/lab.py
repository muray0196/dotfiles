#!/usr/bin/env python3
"""Build, run, and verify the independent Quickshell optical prototype."""

import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "dotfiles-liquid-glass-lab"
SCENES = ("color", "grid", "type", "contrast", "flower", "desert", "boundary", "lighting", "panel", "size")


def run_checked(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def build(program=None):
    qsb = shutil.which("qsb") or "/usr/lib/qt6/bin/qsb"
    if not Path(qsb).is_file():
        raise RuntimeError("Qt Shader Tools (qsb) is required; no packages were installed.")
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    for source in sorted((SOURCE / "shaders").glob("*.frag")):
        target = CACHE / (source.name + ".qsb")
        run_checked([qsb, "--glsl", "150,300 es", "-o", str(target), str(source)])
    for source in SOURCE.glob("*.qml"):
        shutil.copy2(source, CACHE / source.name)
    for name in ("flower.png", "desert.png"):
        shutil.copy2(SOURCE / "assets" / name, CACHE / name)
    if program:
        flags = shlex.split(run_checked(["pkg-config", "--cflags", "--libs", "Qt6Quick", "Qt6Test"]))
        run_checked(["g++", "-std=c++20", "-O2", "-fPIC", "-pie", "-Wall", "-Wextra", "-Werror",
                     str(SOURCE / f"{program}.cpp"), "-o", str(CACHE / program), *flags])
    print(f"Built independent glass shaders in {CACHE}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="compile shaders; write only to the bounded lab cache")
    sub.add_parser("stop", help="close only this prototype's Quickshell instance")
    sub.add_parser("desktop-probe", help="verify backdrop ordering in a disposable nested Hyprland session")
    sub.add_parser("desktop-check", help="test GPU desktop glass in isolated compositors at scales 1, 1.25, and 2")
    sub.add_parser("desktop", help="launch the tested independent clock on the current desktop")
    sub.add_parser("desktop-stop", help="close the independent desktop clock and unload only its backend")
    sub.add_parser("desktop-record", help="record desktop glass over a separate Wayland window in an isolated compositor")
    launch = sub.add_parser("run", help="open a separate Quickshell test window")
    launch.add_argument("--paused", action="store_true", help="start with background motion paused")
    launch.add_argument("--scene", choices=SCENES, default="flower", help="initial study (default: flower)")
    sub.add_parser("check", help="run GPU pixel and interaction checks at scale 1 and 2; needs a display")
    record = sub.add_parser("record", help="render a repeatable 6-second study; needs a display and ffmpeg")
    record.add_argument("--scene", choices=SCENES[4:], default="flower", help="study to render (default: flower)")
    args = parser.parse_args()
    try:
        if args.command in ("desktop", "desktop-check", "desktop-stop", "desktop-record"):
            import desktop

            if args.command == "desktop":
                desktop.live(SOURCE, CACHE)
            elif args.command == "desktop-stop":
                desktop.stop(CACHE)
            elif args.command == "desktop-record":
                desktop.record(SOURCE, CACHE / "desktop-record")
            else:
                for scale in (1, 1.25, 2):
                    directory = "desktop" if scale == 1 else f"desktop-{scale}x"
                    desktop.check(SOURCE, CACHE / directory, scale)
            return 0
        if args.command == "desktop-probe":
            from desktop_probe import run

            run(SOURCE, CACHE)
            return 0
        if args.command == "stop":
            return subprocess.call(["qs", "kill", "--path", str(CACHE / "shell.qml")])
        build(program={"check": "proof", "record": "record"}.get(args.command))
        if args.command == "run":
            env = os.environ.copy()
            env["LIQUID_GLASS_LAB_PAUSED"] = "1" if args.paused else "0"
            env["LIQUID_GLASS_LAB_SCENE"] = str(SCENES.index(args.scene))
            return subprocess.call(["qs", "--no-duplicate", "--path", str(CACHE / "shell.qml")], env=env)
        if args.command == "check":
            for scale in (1, 2):
                env = os.environ.copy()
                env["QT_SCALE_FACTOR"] = str(scale)
                env.setdefault("QSG_RHI_BACKEND", "opengl")
                result = subprocess.run([str(CACHE / "proof"), str(CACHE), str(CACHE / f"proof-{scale}x")],
                                        env=env, text=True, capture_output=True, timeout=90)
                print(result.stdout, end="")
                if result.stderr:
                    print(result.stderr, file=sys.stderr, end="")
                if result.returncode:
                    return result.returncode
        if args.command == "record":
            env = os.environ.copy()
            env["QT_SCALE_FACTOR"] = "1"
            env.setdefault("QSG_RHI_BACKEND", "opengl")
            return subprocess.run([str(CACHE / "record"), str(CACHE),
                                   str(SCENES.index(args.scene)), args.scene], env=env, timeout=120).returncode
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"liquid-glass-lab: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
