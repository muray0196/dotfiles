"""Bounded Clear experiments using the desktop renderer on an explicit GPU."""

import hashlib
import json
import os
from pathlib import Path
import random
import shlex
import shutil
import statistics
import subprocess
import time

from desktop_build import shaders


def checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, timeout=180, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def compile_benchmark(source, output, variant):
    output.mkdir(parents=True, exist_ok=True)
    shaders(source, output)
    header = (source / "desktop-gpu.hpp").read_text()
    shader = (output / "desktop-shaders.hpp").read_text()
    if variant == "dynamic-sigma":
        # Reproduce the pre-optimization desktop's identical Gaussian kernel.
        shader = shader.replace("const float sigma = 2.8;", "uniform float sigma;")
        for program in ("hBlur", "vBlur"):
            header = header.replace(f"glUseProgram({program});",
                                    f'glUseProgram({program}); one({program}, "sigma", 2.8);')
    elif variant == "lod-bias":
        shader = shader.replace("texture(backdrop, uv)", "texture(backdrop, uv, -0.5)")
    elif variant == "no-mips":
        header = header.replace("GL_LINEAR_MIPMAP_LINEAR", "GL_LINEAR")
    elif variant == "full-analysis":
        # Control: original full-frame lighting blur and its unused Clear mips.
        setting = "const bool lightingOnly = !diffuse;"
        if header.count(setting) != 1:
            raise RuntimeError("Full-analysis control no longer matches the renderer")
        header = header.replace(setting, "const bool lightingOnly = false;")
    (output / "desktop-shaders.hpp").write_text(shader)
    (output / "desktop-gpu.hpp").write_text(header)
    shutil.copy2(source / "benchmark.cpp", output / "benchmark.cpp")
    flags = shlex.split(checked(["pkg-config", "--cflags", "--libs", "Qt6Gui", "egl", "glesv2"]))
    checked(["g++", "-std=c++23", "-O2", "-fPIC", "-Wall", "-Wextra", "-Werror",
             str(output / "benchmark.cpp"), "-I", str(output), "-o", str(output / "benchmark"), *flags])
    return output / "benchmark"


def run(source, output, device, frames=512, repeats=3, motion=False, power_seconds=0):
    if not 32 <= frames <= 10000 or not 1 <= repeats <= 10 or (power_seconds != 0 and not 4 <= power_seconds <= 60):
        raise RuntimeError("Use 32..10000 frames, 1..10 repeats and either 0 or 4..60 power seconds")
    device = str(Path(device).resolve(strict=True))
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ | {"QT_QPA_PLATFORM": "offscreen"}
    variants = ("current", "dynamic-sigma", "lod-bias", "no-mips", "full-analysis")
    binaries = {name: compile_benchmark(source, output / name, name) for name in variants}
    settings = [("dynamic-sigma", 1), ("current", 1), ("current", 4), ("current", 8), ("current", 16),
                ("lod-bias", 1), ("no-mips", 1), ("full-analysis", 4)]
    scenes = ("grid", "flower", "desert")
    records = []

    def command(variant, anisotropy, scale, scene, count, hz=0, moving=False, suffix=""):
        image = "grid" if scene == "grid" else str(source / "assets" / f"{scene}.png")
        prefix = output / variant / f"{scene}-{scale}x-af{anisotropy}{suffix}"
        return [str(binaries[variant]), device, image, str(prefix), str(scale), "clear", str(anisotropy),
                str(count), str(hz), *(["motion"] if moving else ["animate"] if hz else [])], prefix

    # Interleave all cases so clock/temperature drift does not systematically
    # favor one setting. Each process warms up 48 complete material frames.
    jobs = [(v, a, s, scene, repeat) for repeat in range(repeats) for s in (1, 2)
            for scene in scenes for v, a in settings]
    random.Random(318).shuffle(jobs)
    for index, (variant, anisotropy, scale, scene, repeat) in enumerate(jobs):
        args, prefix = command(variant, anisotropy, scale, scene, frames)
        result = json.loads(checked(args, env=env))
        records.append(result | {"variant": variant, "scene": scene, "repeat": repeat,
                                 "image": str(prefix.relative_to(output)) + ".png"})
        if (index + 1) % 21 == 0:
            print(f"Clear benchmark: {index + 1}/{len(jobs)} cases", flush=True)
    comparisons = []
    for scene in scenes:
        args, reference = command("current", 16, 4, scene, 1, suffix="-reference")
        checked(args, env=env)
        for scale in (1, 2):
            for variant, anisotropy in settings:
                _, prefix = command(variant, anisotropy, scale, scene, 1)
                base = output / "current" / f"{scene}-{scale}x-af1.png"
                def compare(path):
                    return json.loads(checked([str(binaries["current"]), "compare", str(prefix) + ".png", str(path)], env=env))
                comparisons.append({"variant": variant, "anisotropy": anisotropy, "scale": scale, "scene": scene,
                                    "vs_current": compare(base),
                                    "vs_af4": compare(output / "current" / f"{scene}-{scale}x-af4.png"),
                                    "vs_4x_reference": compare(str(reference) + ".png")})
    if any(c["vs_af4"]["max"] != 0 for c in comparisons if c["variant"] == "full-analysis"):
        raise RuntimeError("Optimized Clear differs from the full-analysis AF4 control")
    videos = []
    if motion:
        for scene in ("grid", "flower"):
            for variant, anisotropy in (("current", 1), ("current", 4), ("current", 16), ("lod-bias", 1), ("no-mips", 1)):
                args, prefix = command(variant, anisotropy, 1, scene, 96, moving=True, suffix="-motion")
                checked(args, env=env)
                checked(["ffmpeg", "-v", "error", "-y", "-framerate", "60", "-i", str(prefix) + "-%04d.png",
                         "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(prefix) + ".mp4"])
                # Keep four exact subpixel phases; the video is a lossy viewing aid.
                for frame in range(4, 96):
                    Path(f"{prefix}-{frame:04d}.png").unlink()
                videos.append({"scene": scene, "variant": variant, "anisotropy": anisotropy,
                               "path": str(prefix.relative_to(output)) + ".mp4"})
            print(f"Clear motion: {scene}", flush=True)
    power = []
    if power_seconds:
        sensors = sorted((Path("/sys/class/drm") / Path(device).name / "device/hwmon").glob("*/power1_average"))
        if not sensors:
            raise RuntimeError("Requested GPU board-power sensor is unavailable")
        for repeat in range(3):
            order = [("full-analysis", 4), ("current", 4)]
            random.Random(318 + repeat).shuffle(order)
            for variant, anisotropy in order:
                args, _ = command(variant, anisotropy, 2, "flower", round(power_seconds * 60), hz=60, suffix="-power")
                with subprocess.Popen(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
                    samples = []
                    deadline = time.monotonic() + power_seconds + 30
                    while process.poll() is None and time.monotonic() < deadline:
                        samples.append(float(sensors[0].read_text()) / 1e6)
                        time.sleep(0.1)
                    if process.poll() is None:
                        process.kill()
                        raise RuntimeError("Power experiment timed out")
                    stdout, stderr = process.communicate(timeout=5)
                    if process.returncode:
                        raise RuntimeError(stderr)
                # Exclude startup and exit from the slow board sensor average.
                samples = samples[10:-5]
                if not samples:
                    raise RuntimeError("Power run too short; use at least four seconds")
                power.append(json.loads(stdout) | {"variant": variant, "repeat": repeat,
                             "board_watts_median": statistics.median(samples), "board_watts_min": min(samples),
                             "board_watts_max": max(samples), "sensor": str(sensors[0])})
            print(f"Clear board power: repeat {repeat + 1}/3", flush=True)
    fingerprints = {name: hashlib.sha256((source / name).read_bytes()).hexdigest()
                    for name in ("desktop-gpu.hpp", "desktop_build.py", "benchmark.cpp", "benchmark.py", "shaders/glass.frag", "shaders/blur.frag")}
    report = {"scope": "Clear desktop material pass, 1024x768 logical scene, three surfaces; not whole-desktop pacing.",
              "reference": "4x-per-axis render of the same optical model, AF16; diagnostic, not ground truth.",
              "power_scope": "Whole GPU board sensor with moving source at 60 frames/s, AF4; includes other desktop workloads. No per-frame readback or image writes; no isolated energy claim.",
              "source_sha256": fingerprints, "records": records, "comparisons": comparisons, "videos": videos, "power": power}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    write_report(output, report, settings)
    print(f"Clear experiments: {output / 'index.html'}", flush=True)


def write_report(output, report, settings):
    rows = []
    for variant, anisotropy in settings:
        times = []
        for scale in (1, 2):
            values = [r["gpu_median_ms"] for r in report["records"]
                      if (r["variant"], r["anisotropy"], r["scale"]) == (variant, anisotropy, scale)]
            times.append(f"{statistics.median(values):.4f}")
        rows.append(f"<tr><td>{variant} / AF{anisotropy}</td><td>{times[0]}</td><td>{times[1]}</td></tr>")
    data = json.dumps(report).replace("</", "<\\/")
    page = '''<!doctype html><html lang="en"><meta charset="utf-8"><title>Clear experiments</title>
<style>body{font:16px system-ui;background:#17191e;color:#eee;max-width:1100px;margin:32px auto;padding:16px}button,select{font:inherit;padding:8px;margin:4px}td,th{padding:8px 18px;text-align:left}p{line-height:1.5}canvas{max-width:100%;border:1px solid #555;cursor:crosshair}video{max-width:100%}.zoom{width:48%;image-rendering:pixelated}a{color:#aacaff}</style>
<h1>Clear: quality and GPU cost</h1><p>Native captures from the desktop renderer. A = isotropic AF1 reference. B = selected filtering (desktop Clear defaults to AF4).
Click the large image to switch A/B. Move over it to inspect matching 4× nearest-neighbor crops below.</p>
<table><tr><th>Experiment</th><th>1× GPU ms</th><th>2× GPU ms</th></tr>ROWS</table>
<p>Median of per-run medians across Grid/Type, Flower and Desert; repeated, shuffled cases after 48 warmup frames.
Includes copy, mipmaps, analysis blur and three glass surfaces. Excludes source fixture, capture and file writes.
No inference about whole-desktop FPS or battery life.</p>
<select id="scene"><option>grid</option><option>flower</option><option>desert</option></select>
<select id="scale"><option value="1">1× display scale</option><option value="2">2× display scale</option></select>
<select id="variant"><option value="current/4">AF4</option><option value="current/8">AF8</option><option value="current/16">AF16</option><option value="lod-bias/1">LOD −0.5</option><option value="no-mips/1">Bilinear only</option><option value="dynamic-sigma/1">Before constant weights</option><option value="full-analysis/4">Full-frame analysis / AF4 control</option></select>
<button id="toggle">Showing A: AF1 reference</button><p id="metric"></p><canvas id="view"></canvas>
<p>A: AF1 reference (left) · B: selected filtering (right). Native pixels enlarged without smoothing.</p>
<canvas class="zoom" id="left" width="512" height="320"></canvas> <canvas class="zoom" id="right" width="512" height="320"></canvas>
<h2>Motion</h2><p>Same source moves 0.25 physical pixels per frame at 60 fps. Videos use lossy H.264 and are a viewing aid;
exact PNGs for the first four subpixel phases are retained. Each loop resets after 24 pixels. Use native stills for fine-detail judgments.</p>
<select id="movie"></select><br><video id="video" controls loop muted playsinline></video>
<h2>How to judge</h2><p>Check detail along curved edges, lost or duplicated text strokes, and shimmering while the source moves.
More contrast alone is not better sampling. The 4×-per-axis reference is the same optical model, not an Apple capture or objective truth.
Edge RMSE covers 2–48 logical pixels inside the shapes; lower is closer to this diagnostic reference.</p>
<p>The broad buffer remains necessary for highlight brightness even in Clear. Desktop Clear uses AF4; the benchmark explicitly selects each tested level.
Negative LOD and no-mipmap settings exist only in the experiment harness.</p><p><a href="results.json">Full measurements, pixel comparisons, source hashes and optional board-power samples</a></p>
<script>const report=DATA;
const $=id=>document.getElementById(id), view=$('view'), ctx=view.getContext('2d');let a=new Image,b=new Image,showB=false;
async function load(){const s=$('scene').value,k=$('scale').value,[v,af]=$('variant').value.split('/');
await Promise.all([new Promise(r=>{a.onload=r;a.src=`current/${s}-${k}x-af1.png`}),new Promise(r=>{b.onload=r;b.src=`${v}/${s}-${k}x-af${af}.png`})]);
view.width=a.width;view.height=a.height;showB=false;draw();zoom(a.width*.14,a.height*.73);
const m=report.comparisons.find(x=>x.scene===s&&x.scale==k&&x.variant===v&&x.anisotropy==af);
const base=report.comparisons.find(x=>x.scene===s&&x.scale==k&&x.variant==='current'&&x.anisotropy===1);
$('metric').textContent=`Difference from A: max ${m.vs_current.max}/255, mean ${m.vs_current.mae.toFixed(4)}/255. Edge RMSE vs 4× reference: A ${base.vs_4x_reference.edge_rmse.toFixed(3)}, B ${m.vs_4x_reference.edge_rmse.toFixed(3)}.`;}
function draw(){ctx.drawImage(showB?b:a,0,0);$('toggle').textContent=showB?'Showing B: selected filtering':'Showing A: AF1 reference'}
function zoom(x,y){for(const[id,img]of[['left',a],['right',b]]){const c=$(id).getContext('2d');c.imageSmoothingEnabled=false;c.clearRect(0,0,512,320);c.drawImage(img,x-64,y-40,128,80,0,0,512,320)}}
view.onmousemove=e=>{const r=view.getBoundingClientRect();zoom((e.clientX-r.left)*view.width/r.width,(e.clientY-r.top)*view.height/r.height)};
view.onclick=$('toggle').onclick=()=>{showB=!showB;draw()};for(const id of['scene','scale','variant'])$(id).onchange=load;
for(const v of report.videos){const option=document.createElement('option');option.value=v.path;option.textContent=`${v.scene}: ${v.variant} / AF${v.anisotropy}`;$('movie').append(option)}
$('movie').onchange=()=>{$('video').src=$('movie').value};if(report.videos.length)$('movie').onchange();load();
</script></html>'''
    (output / "index.html").write_text(page.replace("ROWS", "".join(rows)).replace("DATA", data))
