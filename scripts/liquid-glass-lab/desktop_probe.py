"""Bounded render-order proof in a disposable nested Hyprland session."""

import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import time


def run(source, cache):
    output = cache / "desktop-probe"
    output.mkdir(mode=0o700, parents=True, exist_ok=True)

    def command(args, **kwargs):
        result = subprocess.run(args, text=True, capture_output=True, timeout=60, **kwargs)
        if result.returncode:
            raise RuntimeError(f"{Path(args[0]).name} failed:\n{result.stdout}{result.stderr}")
        return result.stdout

    flags = shlex.split(command(["pkg-config", "--cflags", "--libs", "hyprland", "glesv2"]))
    command(["g++", "-std=c++23", "-shared", "-fPIC", "-O2", "-Wall", "-Wextra",
             str(source / "desktop-probe.cpp"), "-o", str(output / "probe.so"), *flags])
    command(["Hyprland", "--verify-config", "--config", str(source / "desktop-probe.lua")])
    shutil.copy2(source / "desktop-probe.qml", output / "shell.qml")
    for name in ("before.ppm", "after.ppm", "before.png", "after.png", "results.json"):
        (output / name).unlink(missing_ok=True)

    env = os.environ.copy()
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    env.update({
        # libseat treats an explicitly unknown backend as a hard failure. It
        # cannot fall back to logind, acquire a seat, or switch the physical VT.
        "LIBSEAT_BACKEND": "liquid-glass-probe-disabled",
        "HYPRLAND_NO_SD_VARS": "1",
        "HYPRLAND_NO_SD_NOTIFY": "1",
        "HYPRLAND_NO_RT": "1",
        "LIQUID_GLASS_PROBE_OUTPUT": str(output),
    })
    processes = []

    def wait_for(test, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if any(process.poll() is not None for process in processes):
                raise RuntimeError(f"Probe process exited while waiting for {label}; see {output}")
            value = test()
            if value:
                return value
            time.sleep(0.1)
        raise RuntimeError(f"Timed out waiting for {label}; see {output}")

    with (output / "hyprland.log").open("w") as compositor_log, (output / "quickshell.log").open("w") as shell_log:
        try:
            compositor = subprocess.Popen(
                ["sh", "-c", 'export LIQUID_GLASS_PROBE_PID=$$; exec Hyprland "$@"',
                 "liquid-glass-probe", "--config", str(source / "desktop-probe.lua")],
                env=env, stdout=compositor_log, stderr=subprocess.STDOUT, start_new_session=True,
            )
            processes.append(compositor)

            def instance():
                return next((item for item in json.loads(command(["hyprctl", "-j", "instances"]))
                             if item["pid"] == compositor.pid), None)

            nested = wait_for(instance, "nested compositor socket")
            signature = nested["instance"]
            socket = nested["wl_socket"]
            if socket == env.get("WAYLAND_DISPLAY"):
                raise RuntimeError("The nested compositor must have its own Wayland socket")

            def control(*args):
                return command(["hyprctl", "-i", signature, *args])

            monitors = wait_for(lambda: json.loads(control("-j", "monitors")), "nested Wayland output")
            if any(not item["name"].startswith("WAYLAND-") or item["transform"] != 0 for item in monitors):
                raise RuntimeError("Refusing to load the diagnostic outside the nested Wayland output")
            if control("configerrors").strip() not in ("", "ok"):
                raise RuntimeError("Nested compositor reported configuration errors")
            client_env = env | {"WAYLAND_DISPLAY": socket, "HYPRLAND_INSTANCE_SIGNATURE": signature,
                                "QT_QPA_PLATFORM": "wayland", "QSG_RHI_BACKEND": "opengl", "QT_SCALE_FACTOR": "1"}
            shell = subprocess.Popen(["qs", "--path", str(output / "shell.qml")], env=client_env,
                                     stdout=shell_log, stderr=subprocess.STDOUT, start_new_session=True)
            processes.append(shell)
            wait_for(lambda: any(item["title"] == "Liquid Glass backdrop probe"
                                 for item in json.loads(control("-j", "clients"))), "underlying Wayland window")
            wait_for(lambda: "liquid-glass-probe-marker" in control("layers"), "top-layer marker")
            time.sleep(0.5)
            result = control("plugin", "load", str(output / "probe.so"))
            if result.strip() != "ok":
                raise RuntimeError(f"Diagnostic plugin load failed: {result}")
            wait_for(lambda: (output / "after.ppm").exists() and (output / "before.ppm").exists(),
                     "paired pre-layer and final framebuffer reads")

            def ppm(name):
                with (output / name).open("rb") as file:
                    if file.readline() != b"P6\n":
                        raise RuntimeError("Invalid diagnostic image")
                    width, height = map(int, file.readline().split())
                    if file.readline() != b"255\n":
                        raise RuntimeError("Unexpected diagnostic image depth")
                    pixels = file.read()
                if len(pixels) != width * height * 3:
                    raise RuntimeError("Incomplete diagnostic image")
                return width, height, pixels

            width, height, before = ppm("before.ppm")
            after_width, after_height, after = ppm("after.ppm")
            center = ((height // 2) * width + width // 2) * 3
            amber = bytes((237, 170, 50))
            magenta = bytes((255, 0, 255))
            checks = {
                "same_framebuffer_size": (width, height) == (after_width, after_height),
                "underlying_window_in_backdrop": before[center:center + 3] == amber,
                "marker_in_final_frame": after[center:center + 3] == magenta,
                "marker_excluded_from_backdrop": not any(before[i:i + 3] == magenta for i in range(0, len(before), 3)),
                "background_unchanged_outside_marker": before[0:3] == after[0:3] == bytes((25, 76, 119)),
                "top_left_orientation": any(before[i:i + 3] == bytes((41, 182, 135))
                                            for i in range(0, 80 * width * 3, 3))
                                        and not any(before[i:i + 3] == bytes((41, 182, 135))
                                                    for i in range((height - 80) * width * 3, len(before), 3)),
            }
            receipt = {"checks": checks, "size": [width, height], "nested_instance": nested,
                       "version": json.loads(control("-j", "version")),
                       "before_center_rgb": list(before[center:center + 3]),
                       "after_center_rgb": list(after[center:center + 3]),
                       "scope": "Render ordering only; CPU diagnostic reads, not production glass transport."}
            (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
            for name in ("before", "after"):
                command(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(output / f"{name}.ppm"),
                         "-frames:v", "1", str(output / f"{name}.png")])
            if not all(checks.values()):
                raise RuntimeError(f"Render-order checks failed: {checks}; see {output}")
            print(f"PASS {len(checks)} nested compositor checks; evidence: {output}", flush=True)
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=5)
