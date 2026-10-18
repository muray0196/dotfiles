#!/usr/bin/env python3
"""Build the independent Clear prototype; never install or activate it."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


UPSTREAM = "84c1a5ab217101a317d4edaab7fba2efcc1bf346"
VERSION = "0.10.0-clear-rework2"
HYPRLAND = "0.56.2"
HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output):
    shader_bytes = (HERE / "clear.frag").read_bytes()
    patch_bytes = (HERE / "capture.patch").read_bytes()
    for command in ("git", "make", "pkg-config", "strip"):
        if not shutil.which(command):
            raise RuntimeError(f"Required build tool is unavailable: {command}")
    version = subprocess.check_output(
        ["pkg-config", "--modversion", "hyprland"], text=True
    ).strip()
    if version != HYPRLAND:
        raise RuntimeError(f"This prototype requires Hyprland {HYPRLAND} headers; found {version}")

    output.mkdir(parents=True, exist_ok=True)
    stem = f"hyprglass-{VERSION}-{HYPRLAND}"
    library = output / f"{stem}.so"
    receipt = output / f"{stem}.json"
    log_path = output / f"{stem}.log"
    for path in (library, receipt, log_path):
        if path.exists():
            raise RuntimeError(f"Refusing to overwrite an existing build: {path}")

    with tempfile.TemporaryDirectory(prefix="glass-clear-build-") as temporary:
        source = Path(temporary) / "source"
        patch = Path(temporary) / "capture.patch"
        patch.write_bytes(patch_bytes)
        with log_path.open("x") as log:
            def run(*command, cwd=None, timeout=600):
                subprocess.run(
                    command, cwd=cwd, stdout=log, stderr=log,
                    check=True, timeout=timeout,
                )

            run(
                "git", "clone", "--quiet", "--depth", "1", "--branch", "v0.10.0",
                "https://github.com/hyprnux/hyprglass.git", str(source), timeout=90,
            )
            revision = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=source, text=True
            ).strip()
            if revision != UPSTREAM:
                raise RuntimeError(f"Upstream tag no longer matches the audited source: {revision}")
            run("git", "apply", str(patch), cwd=source)

            header = source / "src/Shaders.hpp"
            original = header.read_text()
            start = original.index("#version 300 es")
            end = original.index(')GLSL"},', start)
            header.write_text(
                original[:start] + shader_bytes.decode("utf-8") + "\n" + original[end:]
            )
            # Only the capture adapter and fresh shader are applied. No patch
            # from the previous optical series is an input to this build.
            run("make", "-j2", f"HYPRGLASS_VERSION={VERSION}", cwd=source)
            run("strip", "--strip-debug", str(source / "hyprglass.so"))
            inputs = {
                str(path.relative_to(source)): digest(path)
                for path in sorted(source.glob("src/*"))
                if path.suffix in (".cpp", ".hpp", ".S")
            }
            shutil.copy2(source / "hyprglass.so", library)
            receipt.write_text(json.dumps({
                "version": VERSION,
                "hyprland": HYPRLAND,
                "upstream": UPSTREAM,
                "shader_sha256": hashlib.sha256(shader_bytes).hexdigest(),
                "capture_patch_sha256": hashlib.sha256(patch_bytes).hexdigest(),
                "source_inputs": inputs,
                "library_sha256": digest(library),
                "prior_optical_patches": 0,
                "full_clean_build": True,
                "activated": False,
            }, indent=2) + "\n")
    return {"library": str(library), "receipt": str(receipt), "activated": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="Directory for the library, receipt, and build log")
    args = parser.parse_args()
    try:
        result = build(args.output.expanduser().resolve())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Build failed: {error}\nSee the build log in {args.output} for compiler output.\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
