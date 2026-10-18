"""Compile the compositor backend from the same optical shaders as the Qt lab."""

import re
import json
import shlex
import subprocess
import hashlib
import os
import tempfile
from pathlib import Path


def write_tints(source, output):
    """Generate Qt and native palette data from the same ARGB color table."""
    palette = json.loads((source / "tints.json").read_text())
    if not palette or next(iter(palette)) != "off" or palette["off"] != "#00000000":
        raise RuntimeError("The tint palette must start with transparent Off")
    entries, presets = [], []
    for name, color in palette.items():
        if not re.fullmatch(r"[a-z]+", name) or not re.fullmatch(r"#[0-9a-fA-F]{8}", color):
            raise RuntimeError("Invalid tint name or ARGB color")
        a, r, g, b = (int(color[i:i + 2], 16) / 255 for i in (1, 3, 5, 7))
        values = ", ".join(f"{v:.9f}f" for v in (r, g, b, a))
        entries.append('{"' + name + '", {' + values + '}}')
        presets.append({"name": name, "label": name.title(), "color": color, "swatch": "#" + color[3:]})
    output.mkdir(parents=True, exist_ok=True)
    (output / "tints.json").write_text(json.dumps(palette, indent=2) + "\n")
    (output / "TintPalette.js").write_text(".pragma library\nvar presets = " + json.dumps(presets) + ";\n")
    (output / "desktop-tints.hpp").write_text(
        "#include <array>\nnamespace GlassTints {\n"
        "struct Preset { const char* name; std::array<float, 4> color; };\n"
        f"inline constexpr std::array<Preset, {len(entries)}> presets = {{{{\n"
        + ",\n".join(entries) + "\n}};\n"
        + 'inline constexpr const char* options = "' + "|".join(palette) + '";\n}\n')


def publish(binary, directory):
    """Publish complete, immutable bytes without ever truncating a mapped DSO."""
    data = binary.read_bytes()
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / f"liquid-glass-{hashlib.sha256(data).hexdigest()}.so"
    with tempfile.NamedTemporaryFile(dir=directory, suffix=".pending", delete=False) as file:
        pending = Path(file.name)
        try:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
            pending.chmod(0o444)
            try:
                os.link(pending, target)
            except FileExistsError:
                if target.is_symlink() or target.read_bytes() != data:
                    raise RuntimeError(f"Refusing to replace an existing plugin: {target}")
        finally:
            pending.unlink()
    return target


def shaders(source, output):
    """Adapt the shared shaders for the desktop and the offscreen benchmark."""
    output.mkdir(parents=True, exist_ok=True)
    write_tints(source, output)

    def glsl(name, defines=()):
        text = (source / "shaders" / name).read_text()
        preamble = "#version 300 es\n" + "".join(f"#define {name}\n" for name in defines)
        text = text.replace("#version 440", preamble + "precision highp float;")
        text = re.sub(r"layout\(std140, binding = 0\) uniform \w+ \{(.*?)\};",
                      lambda m: "\n".join("uniform " + line.strip() for line in m[1].splitlines() if line.strip()),
                      text, flags=re.S)
        text = re.sub(r"layout\(binding = \d+\) ", "", text)
        if name == "blur.frag":
            # The desktop always uses sigma 2.8. Let the compiler fold the
            # Gaussian weights; the Qt playground keeps its adjustable sigma.
            text = text.replace("uniform float sigma;", "const float sigma = 2.8;")
        return text.replace("layout(location = 0) in", "in")

    variants = (("materialSource", "glass.frag", ()), ("blurSource", "blur.frag", ()),
                ("linearHorizontalSource", "blur.frag", ("GLASS_LINEAR_OUTPUT",)),
                ("linearVerticalSource", "blur.frag", ("GLASS_LINEAR_INPUT",)),
                ("pairedVerticalSource", "blur.frag", ("GLASS_LINEAR_INPUT", "GLASS_ADJACENT_TAPS")))
    header = "\n".join(f'static constexpr char {variable}[] = R"GLSL({glsl(name, defines)})GLSL";'
                       for variable, name, defines in variants)
    (output / "desktop-shaders.hpp").write_text("namespace IndependentGlassShaders {\n" + header + "\n}\n")


def build(source, output):
    shaders(source, output)
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "hyprland", "glesv2"], text=True))
    pending = output / "liquid-glass.so.pending"
    result = subprocess.run(["g++", "-std=c++23", "-O2", "-shared", "-fPIC", "-fno-gnu-unique", "-Wall", "-Wextra",
                             "-I", str(output), str(source / "desktop.cpp"), "-o", str(pending),
                             *flags], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    pending.replace(output / "liquid-glass.so")
    return output / "liquid-glass.so"


if __name__ == "__main__":
    import sys

    print(build(Path(__file__).resolve().parent, Path(sys.argv[1])))
