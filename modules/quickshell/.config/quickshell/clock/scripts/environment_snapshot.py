#!/usr/bin/env python3
"""Fetch indoor (SwitchBot) and outdoor (Weathernews) readings as JSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS_DIR))

from clock_config import DEFAULT_CONFIG, load_clock_config  # noqa: E402
from switchbot_meter import scan as switchbot_scan  # noqa: E402
from weathernews_observation import (  # noqa: E402
    fetch_html,
    parse_observation,
)


def fetch_indoor(address: str, timeout: float) -> dict[str, Any]:
    import asyncio

    result: dict[str, Any] = {}

    async def _scan() -> None:
        finished = asyncio.Event()

        def on_advertisement(device: Any, advertisement: Any) -> None:
            from switchbot_meter import decode_advertisement

            reading = decode_advertisement(device, advertisement)
            if reading and reading["address"] == address:
                del reading["address"]
                result.update(reading)
                finished.set()

        from bleak import BleakScanner

        async with BleakScanner(on_advertisement):
            await asyncio.wait_for(finished.wait(), timeout)

    try:
        asyncio.run(_scan())
    except TimeoutError:
        result = {"error": "timeout"}
    except Exception as error:
        result = {"error": str(error)}

    return result


def fetch_outdoor(url: str, timeout: float) -> dict[str, Any]:
    try:
        html = fetch_html(url, timeout)
        return parse_observation(html)
    except Exception as error:
        return {"error": str(error)}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--indoor-timeout", type=float, default=20)
    parser.add_argument("--outdoor-timeout", type=float, default=15)
    parser.add_argument("--indoor-only", action="store_true")
    parser.add_argument("--outdoor-only", action="store_true")
    args = parser.parse_args()

    config = load_clock_config(args.config)

    results: dict[str, Any] = {}

    if not args.outdoor_only:
        results["indoor"] = fetch_indoor(
            config.switchbot_address, args.indoor_timeout
        )
    if not args.indoor_only:
        results["outdoor"] = fetch_outdoor(
            config.weathernews_url, args.outdoor_timeout
        )

    print(json.dumps(results, ensure_ascii=False, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
