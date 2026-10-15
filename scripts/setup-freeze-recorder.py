#!/usr/bin/env python3
"""Install and start the optional user freeze recorder; no root access required."""

import argparse
from datetime import datetime
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    home_dir = Path.home()
    source = repo / "services/freeze-recorder"
    backup = home_dir / ".local/state/dotfiles-linux/backups" / (datetime.now().strftime("%Y%m%dT%H%M%S%f") + "-freeze-recorder")
    links = {
        home_dir / ".local/libexec/freeze-recorder.py": source / "recorder.py",
        home_dir / ".config/systemd/user/freeze-recorder.service": source / "freeze-recorder.service",
    }
    for target, origin in links.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink() and target.resolve() == origin:
            continue
        if target.exists() or target.is_symlink():
            backup.mkdir(parents=True, exist_ok=True, mode=0o700)
            target.rename(backup / target.name)
            print(f"Preserved previous {target.name} in {backup}")
        target.symlink_to(origin)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "enable", "freeze-recorder.service"], check=True)
    subprocess.run(["systemctl", "--user", "restart", "freeze-recorder.service"], check=True)
    subprocess.run(["systemctl", "--user", "is-active", "freeze-recorder.service"], check=True)
    print("Logs: ~/.local/state/freeze-diagnostics/recorder/boot-<boot-id>/events.jsonl*")


if __name__ == "__main__":
    main()
