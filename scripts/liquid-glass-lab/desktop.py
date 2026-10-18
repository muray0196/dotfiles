"""Run and verify the independent compositor-backed Quickshell widget."""

from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time

from desktop_build import build, publish


def fingerprint(source):
    names = ("desktop.cpp", "desktop-gpu.hpp", "desktop_build.py", "desktop.py", "lab.py", "DesktopWidget.qml", "desktop-shell.qml",
             "shaders/glass.frag", "shaders/blur.frag", "tints.json")
    digest = hashlib.sha256()
    for name in names:
        digest.update(name.encode() + b"\0" + (source / name).read_bytes())
    return digest.hexdigest()


def command(args, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True, timeout=60, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def wait_for(test, label, processes=()):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if any(process.poll() is not None for process in processes):
            raise RuntimeError(f"Desktop test process exited while waiting for {label}")
        value = test()
        if value:
            return value
        time.sleep(0.1)
    raise RuntimeError(f"Timed out waiting for {label}")


def prepare(source, output):
    output.mkdir(parents=True, exist_ok=True)
    for name in ("DesktopWidget.qml", "desktop-shell.qml", "DesktopFixture.qml"):
        shutil.copy2(source / name, output / name)
    shutil.copy2(source / "assets/flower.png", output / "flower.png")
    return build(source, output)


@contextmanager
def nested(source, output, scale=1):
    processes = []
    files = []
    plugin = publish(output / "liquid-glass.so", output / "plugins")
    env = os.environ.copy()
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    env.update({"LIBSEAT_BACKEND": "liquid-glass-probe-disabled", "HYPRLAND_NO_SD_VARS": "1",
                "HYPRLAND_NO_SD_NOTIFY": "1", "HYPRLAND_NO_RT": "1"})
    config = (source / "desktop-probe.lua").read_text().replace("damage_tracking = 0", "damage_tracking = 2")
    config = config.replace("scale = 1", f"scale = {scale}")
    (output / "hyprland.lua").write_text(config)

    def launch(args, child_env, log):
        stream = (output / log).open("w")
        files.append(stream)
        process = subprocess.Popen(args, env=child_env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(process)
        return process

    try:
        compositor = launch(["Hyprland", "--config", str(output / "hyprland.lua")], env, "hyprland.log")
        instance = wait_for(lambda: next((item for item in json.loads(command(["hyprctl", "-j", "instances"]))
                                         if item["pid"] == compositor.pid), None), "nested instance", processes)

        def control(*args):
            return command(["hyprctl", "-i", instance["instance"], *args])

        monitors = wait_for(lambda: json.loads(control("-j", "monitors")), "nested output", processes)
        if any(not m["name"].startswith("WAYLAND-") for m in monitors):
            raise RuntimeError("Desktop tests require an isolated Wayland output")
        client_env = env | {"WAYLAND_DISPLAY": instance["wl_socket"], "HYPRLAND_INSTANCE_SIGNATURE": instance["instance"],
                            "QT_QPA_PLATFORM": "wayland", "QSG_RHI_BACKEND": "opengl", "QT_SCALE_FACTOR": "1"}
        fixture = launch(["qs", "--path", str(output / "DesktopFixture.qml")], client_env, "fixture.log")
        wait_for(lambda: control("-j", "clients") != "[]\n" and "Independent Liquid Glass desktop fixture" in control("clients"),
                 "background window", processes)
        if control("plugin", "load", str(plugin)).strip() != "ok":
            raise RuntimeError("Could not load the independent material backend")
        widget = launch(["qs", "--path", str(output / "desktop-shell.qml")], client_env, "widget.log")
        wait_for(lambda: "liquid-glass-v1" in control("layers"), "Quickshell glass surface", processes)
        time.sleep(0.6)

        def ipc(process, target, method, *args):
            return command(["qs", "ipc", "--pid", str(process.pid), "call", target, method,
                            *[str(value).lower() if isinstance(value, bool) else str(value) for value in args]], env=client_env)

        yield control, ipc, fixture, widget, client_env, instance, plugin
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        for file in files:
            file.close()


def capture(output, name, env):
    path = output / f"{name}.ppm"
    command(["grim", "-t", "ppm", str(path)], env=env)
    with path.open("rb") as file:
        if file.readline() != b"P6\n":
            raise RuntimeError("Expected PPM screenshot")
        width, height = map(int, file.readline().split())
        if file.readline() != b"255\n":
            raise RuntimeError("Expected 8-bit screenshot")
        pixels = file.read()
    if len(pixels) != width * height * 3:
        raise RuntimeError("Incomplete screenshot")
    command(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(path), "-frames:v", "1",
             str(output / f"{name}.png")])
    path.unlink()
    return width, height, pixels


def difference(a, b, rect=None, inset=40):
    if a[:2] != b[:2]:
        raise RuntimeError("Comparison size changed")
    width, height, first = a
    second = b[2]
    # The fixture owns the inset window. Hyprland's startup warning outside it
    # expires independently and must not be scored as material instability.
    x, y, w, h = rect or (inset, inset, width - 2 * inset, height - 2 * inset)
    count = total = 0
    for row in range(max(0, int(y)), min(height, int(y + h))):
        start, end = (row * width + max(0, int(x))) * 3, (row * width + min(width, int(x + w))) * 3
        total += sum(abs(c - d) for c, d in zip(first[start:end], second[start:end]))
        count += end - start
    if not count:
        raise RuntimeError("Comparison region does not intersect the captured output")
    return total / count


def reload_check(source, output, control, shell, photo, compare, instance, plugin):
    """Exercise replacement in one compositor, including the actual mapped files."""
    checks = {}
    maps = Path(f"/proc/{instance['pid']}/maps")
    checks["unloaded_binary_leaves_address_space"] = str(plugin) not in maps.read_text()
    inode = plugin.stat().st_ino
    same = publish(output / "liquid-glass.so", plugin.parent)
    checks["republishing_keeps_existing_library_inode"] = same == plugin and same.stat().st_ino == inode
    symbols = command(["readelf", "--dyn-syms", "--wide", str(plugin)])
    checks["plugin_has_no_gnu_unique_symbols"] = not any("UNIQUE" in line.split() for line in symbols.splitlines())
    plain = photo("reload-plain")

    def load(path):
        if control("plugin", "load", str(path)).strip() != "ok":
            raise RuntimeError("Isolated plugin reload failed")
        shell("visible", True)
        return json.loads(control("liquidglass"))

    def unload(path):
        if control("plugin", "unload", str(path)).strip() != "ok":
            raise RuntimeError("Isolated plugin unload failed")
        shell("visible", False)

    loaded = load(plugin)
    baseline = photo("reload-baseline")
    checks["same_binary_reloads_and_renders"] = (loaded["presence"] == 1 and loaded["clarity"] == "soft" and loaded["tint"] == "off" and not loaded["failed"]
                                                 and compare(plain, baseline) > 0.1)
    control("liquidglass", "presence", "0.37")
    control("liquidglass", "clarity", "clear")
    control("liquidglass", "tint", "black")
    unload(plugin)

    # A real rebuild with a changed default proves that the replacement's code
    # executes, rather than accidentally reusing the first dlopen handle.
    with tempfile.TemporaryDirectory(prefix="reload-source-", dir=output) as directory:
        variant = Path(directory)
        shutil.copy2(source / "desktop-gpu.hpp", variant)
        shutil.copytree(source / "shaders", variant / "shaders")
        shutil.copy2(source / "tints.json", variant / "tints.json")
        original = (source / "desktop.cpp").read_text()
        changed = original.replace("  presence = 1;\n", "  presence = 0.75;\n")
        if changed == original:
            raise RuntimeError("Reload fixture did not change the backend default")
        (variant / "desktop.cpp").write_text(changed)
        replacement = publish(build(variant, variant / "build"), plugin.parent)
        checks["replacement_uses_a_separate_library_file"] = (replacement != plugin
                                                               and plugin.stat().st_ino == inode)
        loaded = load(replacement)
        checks["replacement_binary_runs_after_unload"] = loaded["presence"] == 0.75 and not loaded["failed"]
        control("liquidglass", "presence", "1")
        replaced = photo("reload-replaced")
        checks["replacement_keeps_rendering_correct"] = compare(baseline, replaced) < 0.05
        unload(replacement)
        checks["replacement_unmaps_on_unload"] = str(replacement) not in maps.read_text()

    repeated = []
    for index in range(2):
        loaded = load(plugin)
        restored = photo(f"reload-restored-{index}")
        repeated.append(loaded["presence"] == 1 and loaded["clarity"] == "soft" and loaded["tint"] == "off" and not loaded["failed"]
                        and compare(baseline, restored) < 0.05)
        control("liquidglass", "presence", "0.37")
        control("liquidglass", "clarity", "diffused")
        control("liquidglass", "tint", "black")
        unload(plugin)
        repeated.append(str(plugin) not in maps.read_text())
    checks["repeated_reload_resets_state_and_releases_library"] = all(repeated)
    checks["reload_cycles_leave_normal_composition"] = compare(plain, photo("reload-final")) < 0.05
    if all(checks.values()):
        for path in output.glob("reload-*.png"):
            path.unlink()
        replacement.unlink()
    return checks


def check(source, output, scale=1):
    prepare(source, output)
    tested_source = fingerprint(source)
    checks = {}
    comparisons = {}
    shot_names = {}

    def compare(a, b, rect=None):
        value = difference(a, b, rect, inset=40 * scale)
        comparisons[f"{shot_names.get(id(a))}/{shot_names.get(id(b))}"] = value
        return value
    with nested(source, output, scale) as (control, ipc, fixture, widget, env, instance, plugin):
        def shell(method, *args):
            ipc(widget, "glass", method, *args)
            time.sleep(0.25)

        def photo(name):
            time.sleep(0.25)
            shot = capture(output, name, env)
            shot_names[id(shot)] = name
            return shot

        shell("fixedClock")
        shell("ink", False)
        shell("visible", False)
        plain = photo("plain")
        shell("visible", True)
        glass = photo("glass")
        status = json.loads(control("liquidglass"))
        checks["gpu_backend_renders"] = status["frames"] > 0 and not status["failed"]
        checks["real_window_is_refracted"] = compare(plain, glass) > 0.1
        stable = photo("stable")
        checks["stationary_source_does_not_feed_back"] = compare(glass, stable) < 0.05
        checks["defaults_soft_and_tint_off"] = status["clarity"] == "soft" and status["tint"] == "off"
        control("liquidglass", "clarity", "clear")
        clear = photo("clear")
        checks["soft_gently_smooths_clear"] = compare(glass, clear) > 0.01
        control("liquidglass", "clarity", "soft")
        checks["soft_round_trip_is_exact"] = compare(glass, photo("soft-restored")) < 0.05
        palette = json.loads((source / "tints.json").read_text())
        for clarity in ("clear", "soft", "diffused"):
            control("liquidglass", "clarity", clarity)
            control("liquidglass", "tint", "off")
            natural = photo(clarity + "-off")
            filtering = json.loads(control("liquidglass"))
            expected_anisotropy = min(4, filtering["max_anisotropy"]) if clarity == "clear" else 1
            checks[f"{clarity}_source_filter_matches_selected_mode"] = filtering["source_anisotropy"] == expected_anisotropy
            for tint in palette:
                selected = json.loads(control("liquidglass", "tint", tint))
                tinted = photo(f"{clarity}-{tint}-tint")
                changed = compare(natural, tinted)
                checks[f"{clarity}_{tint}_independent_tint"] = (
                    selected["clarity"] == clarity and selected["tint"] == tint
                    and (changed < 0.05 if tint == "off" else changed > 0.5)
                    and selected["source_anisotropy"] == expected_anisotropy)
                control("liquidglass", "presence", "0")
                checks[f"{clarity}_{tint}_zero_presence_is_identity"] = compare(plain, photo(f"{clarity}-{tint}-identity")) < 0.05
                control("liquidglass", "presence", "1")
            checks[f"{clarity}_tint_has_no_feedback"] = compare(tinted, photo(clarity + "-stable")) < 0.05
            control("liquidglass", "tint", "off")
            checks[f"{clarity}_tint_off_round_trip_is_exact"] = compare(natural, photo(clarity + "-tint-restored")) < 0.05
        control("liquidglass", "tint", "blue")
        control("liquidglass", "clarity", "soft")
        selected = json.loads(control("liquidglass"))
        checks["clarity_selection_preserves_tint"] = selected["tint"] == "blue" and selected["clarity"] == "soft"
        for attribute, values in (("clarity", "clear|soft|diffused"), ("tint", "|".join(palette))):
            rejected = [subprocess.run(["hyprctl", "-i", instance["instance"], "liquidglass", attribute, *args],
                                       capture_output=True, text=True, timeout=10)
                        for args in ((), ("invalid",), (selected[attribute], "extra"))]
            current = json.loads(control("liquidglass"))
            checks[f"invalid_{attribute}_requests_leave_state_unchanged"] = (
                all(result.returncode != 0 and f"error: expected liquidglass {attribute} <{values}>"
                    in result.stdout + result.stderr for result in rejected)
                and all(current[key] == selected[key] for key in ("clarity", "tint")))

        def interior(shot):
            width, _, pixels = shot
            values, differences = [], []
            for y in range(round(290 * scale), round(390 * scale)):
                row = pixels[(y * width + round(290 * scale)) * 3:(y * width + round(490 * scale)) * 3]
                values.extend(row)
                differences.extend((a - b) ** 2 for a, b in zip(row[3:], row[:-3]))
            return max(values), sum(differences) / len(differences), sum(values) / len(values)

        for pattern, name in ((1, "bright"), (2, "dark")):
            ipc(fixture, "fixture", "pattern", pattern)
            control("liquidglass", "clarity", "clear")
            control("liquidglass", "tint", "off")
            original = photo("clear-" + name)
            control("liquidglass", "clarity", "diffused")
            control("liquidglass", "tint", "black")
            supported = photo("diffused-dark-" + name)
            peak, detail, tinted_mean = interior(supported)
            _, original_detail, original_mean = interior(original)
            checks[f"diffused_dark_{name}_interior_limits_brightness"] = peak <= 120
            checks[f"diffused_dark_{name}_reduces_competing_detail"] = detail < original_detail * 0.5
            control("liquidglass", "tint", "off")
            untinted = photo("diffused-" + name)
            _, soft_detail, soft_mean = interior(untinted)
            checks[f"diffused_{name}_retains_background_brightness"] = soft_mean >= original_mean * 0.9
            checks[f"diffused_{name}_reduces_competing_detail"] = soft_detail < original_detail * 0.75
            checks[f"diffused_{name}_has_no_dark_backing"] = soft_mean > tinted_mean + 10
            control("liquidglass", "tint", "black")
            checks[f"diffused_{name}_tint_restores_without_filter_change"] = compare(supported, photo("tint-restored-" + name)) < 0.05
        ipc(fixture, "fixture", "pattern", 0)
        control("liquidglass", "clarity", "soft")
        control("liquidglass", "tint", "off")
        checks["soft_restored_without_retuning"] = compare(glass, photo("soft-final")) < 0.05
        control("liquidglass", "presence", "0")
        identity = photo("identity")
        checks["zero_strength_matches_uncovered_window"] = compare(plain, identity) < 0.05
        shell("move", 163, 183)
        off_grid = photo("off-grid")
        checks["fractional_raster_keeps_identity_sampling"] = compare(plain, off_grid) < 0.05
        control("liquidglass", "presence", "1")
        shell("move", 840, 180)
        moved = photo("moved")
        checks["moving_widget_erases_old_material"] = compare(plain, moved, (160 * scale, 180 * scale, 556 * scale, 356 * scale)) < 0.05
        shell("visible", False)
        hidden = photo("hidden")
        checks["hiding_widget_restores_window"] = compare(plain, hidden) < 0.05
        shell("move", 160, 180)
        shell("visible", True)
        shell("compact", True)
        time.sleep(2)
        compact = photo("compact")
        checks["compact_shape_changes_render"] = compare(glass, compact) > 0.1
        shell("compact", False)
        time.sleep(2)
        restored = photo("restored")
        checks["resize_returns_without_trails"] = compare(glass, restored) < 0.05
        shell("ink", True)
        ink = photo("ink")
        checks["quickshell_foreground_is_composited_after_glass"] = compare(glass, ink) > 0.05
        # Exercise real Wayland pointer events, not an invocation of QML handlers.
        # A cursor event after each injected button sends the pointer frame that
        # Qt uses to deliver the pending press/release.
        def cursor(x, y):
            control("dispatch", f"hl.dsp.cursor.move({{x={x},y={y}}})")
            time.sleep(0.1)

        def button(state):
            control("dispatch", f'hl.dsp.send_key_state({{mods="",key="mouse:272",state="{state}"}})')

        def geometry():
            layers = json.loads(control("-j", "layers"))
            return next(layer for monitor in layers.values() for level in monitor["levels"].values()
                        for layer in level if layer["namespace"] == "liquid-glass-v1")

        cursor(300, 260)
        button("down")
        cursor(301, 260)
        time.sleep(0.6)
        checks["pointer_press_deforms_material_geometry"] = geometry()["w"] < 554
        button("up")
        cursor(300, 260)
        time.sleep(2)
        checks["pointer_click_changes_control_size"] = geometry()["w"] == 316
        button("down")
        cursor(301, 260)
        cursor(351, 300)
        button("up")
        cursor(352, 300)
        time.sleep(1)
        dragged = geometry()
        checks["pointer_drag_moves_material_and_foreground"] = dragged["x"] > 190 and dragged["y"] > 200
        checks["drag_release_preserves_compact_state"] = dragged["w"] == 316
        shell("move", 160, 180)
        shell("compact", False)
        time.sleep(2)
        ipc(fixture, "fixture", "motion", True)
        time.sleep(2)
        moving = photo("moving")
        checks["live_window_updates_glass"] = compare(ink, moving) > 0.2
        time.sleep(2)
        ipc(fixture, "fixture", "motion", False)
        time.sleep(0.5)
        before_idle = json.loads(control("liquidglass"))
        time.sleep(1)
        after_idle = json.loads(control("liquidglass"))
        checks["no_self_scheduled_idle_redraw_loop"] = after_idle["frames"] - before_idle["frames"] <= 3
        checks["backend_remains_healthy"] = not after_idle["failed"]
        shell("visible", False)
        control("plugin", "unload", str(plugin))
        shell("visible", True)
        shell("ink", False)
        without_plugin = photo("unloaded")
        shell("visible", False)
        after_unload = photo("after-unload")
        checks["unloading_backend_restores_normal_composition"] = compare(without_plugin, after_unload) < 0.05
        if scale == 1:
            checks.update(reload_check(source, output, control, shell, photo, compare, instance, plugin))
        result = {"checks": checks, "comparisons_mean_abs_rgb": comparisons,
                  "scale": scale, "stats": after_idle, "instance": instance,
                  "version": json.loads(control("-j", "version")),
                  "sources_sha256": tested_source,
                  "plugin_sha256": hashlib.sha256((output / "liquid-glass.so").read_bytes()).hexdigest()}
        (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
        for name, passed in checks.items():
            print(f"{'ok' if passed else 'FAIL'}  {name}", flush=True)
        print(f"Compositor timing: {json.dumps(after_idle)}", flush=True)
        if not all(checks.values()):
            raise RuntimeError(f"Desktop checks failed; evidence: {output}")
        for name in ("stable", "identity", "off-grid", "hidden", "restored", "unloaded", "after-unload",
                     "soft-restored", "soft-final"):
            (output / f"{name}.png").unlink(missing_ok=True)
    print(f"PASS {len(checks)} desktop GPU checks at scale {scale}; evidence: {output}", flush=True)


def live(source, cache):
    tested = cache / "desktop"
    result = json.loads((tested / "results.json").read_text())
    if (not all(result["checks"].values()) or not result["checks"].get("replacement_binary_runs_after_unload")
            or result.get("sources_sha256") != fingerprint(source)):
        raise RuntimeError("Run desktop-check for the current source before launching on the desktop")
    binary = tested / "liquid-glass.so"
    if hashlib.sha256(binary.read_bytes()).hexdigest() != result["plugin_sha256"]:
        raise RuntimeError("The compositor backend differs from the tested binary")
    display = os.environ.get("WAYLAND_DISPLAY")
    instances = json.loads(command(["hyprctl", "-j", "instances"]))
    instance = next((item for item in instances if item["wl_socket"] == display), None)
    if instance is None:
        raise RuntimeError("Run from the intended Hyprland graphical session")
    ctl = ["hyprctl", "-i", instance["instance"]]
    version = json.loads(command([*ctl, "-j", "version"]))
    if version["abiHash"] != result["version"]["abiHash"]:
        raise RuntimeError("The running Hyprland ABI differs from the tested compositor")
    output = cache / "desktop-live"
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    state = output / "session.json"
    if state.exists():
        raise RuntimeError("A desktop session is already recorded; use desktop-stop before relaunching")
    for name in ("DesktopWidget.qml", "desktop-shell.qml"):
        shutil.copy2(source / name, output / name)
    plugin = str(publish(binary, output))
    if command([*ctl, "plugin", "load", plugin]).strip() != "ok":
        raise RuntimeError("Could not load the tested material backend")
    try:
        env = os.environ | {"QT_QPA_PLATFORM": "wayland", "QSG_RHI_BACKEND": "opengl", "QT_SCALE_FACTOR": "1"}
        command(["qs", "--no-duplicate", "--daemonize", "--path", str(output / "desktop-shell.qml")], env=env)
        wait_for(lambda: "liquid-glass-v1" in command([*ctl, "layers"]), "desktop glass widget")
        def rendered():
            status = json.loads(command([*ctl, "liquidglass"]))
            return status if status["failed"] or status["frames"] else None

        status = wait_for(rendered, "first desktop material frame")
        if status["failed"]:
            raise RuntimeError("The current output could not render the material")
        state.write_text(json.dumps({"instance": instance, "plugin": plugin, "plugin_sha256": result["plugin_sha256"]}) + "\n")
    except BaseException:
        subprocess.run(["qs", "kill", "--path", str(output / "desktop-shell.qml")], capture_output=True)
        command([*ctl, "plugin", "unload", plugin])
        raise
    print("Desktop glass clock is running. Drag to move; click to change size. Use desktop-stop to close it.")


def record(source, output):
    prepare(source, output)
    with nested(source, output) as (control, ipc, fixture, widget, env, _, _plugin):
        ipc(widget, "glass", "fixedClock")
        ipc(fixture, "fixture", "motion", True)
        frames = []
        with (output / "record.log").open("w") as log:
            encoder = subprocess.Popen(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "image2pipe",
                                        "-vcodec", "ppm", "-framerate", "20", "-i", "-", "-c:v", "libx264",
                                        "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                                        str(output / "desktop-motion.mp4")], stdin=subprocess.PIPE, stderr=log)
            try:
                start = time.monotonic()
                for frame in range(120):
                    if frame == 35:
                        ipc(widget, "glass", "compact", True)
                    if frame == 70:
                        ipc(widget, "glass", "move", 560, 280)
                    if frame == 85:
                        ipc(widget, "glass", "compact", False)
                    delay = start + frame / 20 - time.monotonic()
                    if delay > 0:
                        time.sleep(delay)
                    raw = subprocess.run(["grim", "-t", "ppm", "-g", "100,120 1120x760", "-"], env=env,
                                         capture_output=True, timeout=10, check=True).stdout
                    encoder.stdin.write(raw)
                    frames.append(time.monotonic() - start)
                encoder.stdin.close()
                if encoder.wait(timeout=30):
                    raise RuntimeError(f"Video encoding failed; see {output / 'record.log'}")
            finally:
                if encoder.poll() is None:
                    encoder.kill()
                    encoder.wait()
        (output / "desktop-motion.json").write_text(json.dumps({
            "frames": len(frames), "encoded_fps": 20, "capture_elapsed_seconds": frames[-1],
            "capture_times_seconds": frames, "stats": json.loads(control("liquidglass")),
            "scope": "Real nested compositor capture of separate Wayland clients. Capture overhead is not a frame-pacing benchmark."
        }, indent=2) + "\n")
    print(f"Recorded desktop glass: {output / 'desktop-motion.mp4'}")


def stop(cache):
    output = cache / "desktop-live"
    path = output / "session.json"
    if not path.exists():
        print("No desktop glass session is recorded.")
        return
    state = json.loads(path.read_text())
    digest = state.get("plugin_sha256", "")
    if (len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest)
            or state["plugin"] != str(output / f"liquid-glass-{digest}.so")):
        raise RuntimeError("The recorded plugin path is outside this desktop session")
    active = json.loads(command(["hyprctl", "-j", "instances"]))
    if state["instance"] in active:
        env = os.environ | {"WAYLAND_DISPLAY": state["instance"]["wl_socket"]}
        subprocess.run(["qs", "kill", "--path", str(output / "desktop-shell.qml")], env=env, capture_output=True)
        ctl = ["hyprctl", "-i", state["instance"]["instance"]]
        if "independent-liquid-glass" in command([*ctl, "plugin", "list"]):
            reply = command([*ctl, "plugin", "unload", state["plugin"]])
            if reply.strip() != "ok":
                raise RuntimeError(f"Could not unload the material backend: {reply}")
    path.unlink()
    print("Closed the independent desktop widget and unloaded its material backend.")
