#!/usr/bin/env python3
"""Choose glass clarity or tint without changing the other attribute."""

import json
from pathlib import Path
import subprocess
import sys


def main():
    runner = str(Path(__file__).with_name("desktop.py"))
    status = json.loads(subprocess.check_output([sys.executable, "-B", runner, "status"], text=True))
    tints = tuple(json.loads((Path(__file__).parent.parent / "liquid-glass-lab/tints.json").read_text()))
    choices = {}
    for attribute, values in (("clarity", ("clear", "soft", "diffused")), ("tint", tints)):
        for value in values:
            label = f"{attribute.title()} · {value.title()}" + ("  ✓" if status[attribute] == value else "")
            choices[label] = (attribute, value)
    result = subprocess.run(["wofi", "--dmenu", "--prompt", "Glass appearance", "--width", "340",
                             "--height", "480"], input="\n".join(choices) + "\n", text=True, capture_output=True)
    if result.returncode or result.stdout.strip() not in choices:
        return 0
    attribute, value = choices[result.stdout.strip()]
    subprocess.run([sys.executable, "-B", runner, attribute, value], check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Widget appearance: {error}", file=sys.stderr)
        raise SystemExit(1)
