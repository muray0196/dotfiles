#!/usr/bin/env python3
"""Open the existing desktop picker for stable Clear text colors."""

from pathlib import Path
import subprocess
import sys


def main():
    choices = {"Light text": "light", "Dark text": "dark"}
    result = subprocess.run(["wofi", "--dmenu", "--prompt", "Widget text", "--width", "340",
                             "--height", "180"], input="\n".join(choices) + "\n", text=True, capture_output=True)
    if result.returncode or result.stdout.strip() not in choices:
        return 0
    foreground = choices[result.stdout.strip()]
    runner = str(Path(__file__).with_name("desktop.py"))
    subprocess.run([sys.executable, "-B", runner, "text", foreground], check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"Widget text: {error}", file=sys.stderr)
        raise SystemExit(1)
