"""Compile the compositor backend from the same optical shaders as the Qt lab."""

import re
import shlex
import subprocess
import hashlib
import os
import tempfile
from pathlib import Path


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


def build(source, output):
    output.mkdir(parents=True, exist_ok=True)

    def glsl(name):
        text = (source / "shaders" / name).read_text()
        text = text.replace("#version 440", "#version 300 es\nprecision highp float;")
        text = re.sub(r"layout\(std140, binding = 0\) uniform \w+ \{(.*?)\};",
                      lambda m: "\n".join("uniform " + line.strip() for line in m[1].splitlines() if line.strip()),
                      text, flags=re.S)
        text = re.sub(r"layout\(binding = \d+\) ", "", text)
        return text.replace("layout(location = 0) in", "in")

    header = "\n".join(f'static constexpr char {variable}[] = R"GLSL({glsl(name)})GLSL";'
                       for variable, name in (("materialSource", "glass.frag"), ("blurSource", "blur.frag")))
    (output / "desktop-shaders.hpp").write_text("namespace IndependentGlassShaders {\n" + header + "\n}\n")
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
