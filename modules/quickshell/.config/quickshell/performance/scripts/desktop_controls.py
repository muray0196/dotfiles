#!/usr/bin/env python3
"""Read and update the interactive desktop-control state for Quickshell."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

from desktop_automation import (
    AutomationSettings,
    DEFAULT_SETTINGS,
    DisplaySchedule,
    load_automation_settings,
)


def save_automation_settings(path: Path, settings: AutomationSettings) -> None:
    """Atomically persist validated desktop automation settings."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as settings_file:
            json.dump(
                {
                    "display_off_hour": settings.display_schedule.off_hour,
                    "display_on_hour": settings.display_schedule.on_hour,
                    "waywallen_link_enabled": settings.waywallen_link_enabled,
                },
                settings_file,
                separators=(",", ":"),
            )
            settings_file.write("\n")
            settings_file.flush()
            os.fsync(settings_file.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def current_state(settings_path: Path) -> dict[str, object]:
    settings = load_automation_settings(settings_path)
    return {
        "waywallen_link_enabled": settings.waywallen_link_enabled,
        "display_off_hour": settings.display_schedule.off_hour,
        "display_on_hour": settings.display_schedule.on_hour,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--settings", type=Path, default=DEFAULT_SETTINGS)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")

    waywallen_link = commands.add_parser("waywallen-link")
    waywallen_link.add_argument("action", choices=("on", "off", "toggle"))

    schedule = commands.add_parser("schedule")
    schedule.add_argument("off_hour", type=int)
    schedule.add_argument("on_hour", type=int)
    args = parser.parse_args()

    try:
        settings = load_automation_settings(args.settings)
        if args.command == "waywallen-link":
            enabled = (
                not settings.waywallen_link_enabled
                if args.action == "toggle"
                else args.action == "on"
            )
            save_automation_settings(
                args.settings,
                AutomationSettings(
                    display_schedule=settings.display_schedule,
                    waywallen_link_enabled=enabled,
                ),
            )
        elif args.command == "schedule":
            save_automation_settings(
                args.settings,
                AutomationSettings(
                    display_schedule=DisplaySchedule(
                        off_hour=args.off_hour,
                        on_hour=args.on_hour,
                    ),
                    waywallen_link_enabled=settings.waywallen_link_enabled,
                ),
            )
        print(json.dumps(current_state(args.settings), separators=(",", ":")))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
