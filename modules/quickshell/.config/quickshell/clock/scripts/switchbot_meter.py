#!/usr/bin/env python3
"""Stream SwitchBot Indoor/Outdoor Meter BLE advertisements as JSON lines."""

from __future__ import annotations

import argparse
import asyncio
import json
import signal
import sys
import time
from pathlib import Path
from typing import Any

from clock_config import DEFAULT_CONFIG, load_clock_config


SERVICE_UUID = "0000fd3d-0000-1000-8000-00805f9b34fb"
SWITCHBOT_COMPANY_ID = 0x0969
OUTDOOR_METER_MODEL_BYTES = {ord("w"), ord("W")}


def decode_advertisement(device: Any, advertisement: Any) -> dict[str, Any] | None:
    """Decode a W3400010 advertisement, or return None for another device."""
    service_data = advertisement.service_data.get(SERVICE_UUID)
    if not service_data or service_data[0] & 0x7F not in OUTDOOR_METER_MODEL_BYTES:
        return None

    manufacturer_data = advertisement.manufacturer_data.get(SWITCHBOT_COMPANY_ID)
    temperature_data: bytes | None = None

    if manufacturer_data and len(manufacturer_data) >= 11:
        temperature_data = manufacturer_data[8:11]
    elif len(service_data) >= 6:
        temperature_data = service_data[3:6]

    if not temperature_data:
        return None

    sign = 1 if temperature_data[1] & 0x80 else -1
    temperature = sign * (
        (temperature_data[1] & 0x7F) + (temperature_data[0] & 0x0F) / 10
    )
    humidity = temperature_data[2] & 0x7F
    battery = service_data[2] & 0x7F if len(service_data) >= 3 else None

    if not -20 <= temperature <= 60 or not 0 <= humidity <= 99:
        return None

    return {
        "address": device.address.upper(),
        "temperature": temperature,
        "humidity": humidity,
        "battery": battery,
        "rssi": advertisement.rssi,
        "timestamp": int(time.time()),
    }


async def scan(address: str | None, once: bool, timeout: float) -> int:
    try:
        from bleak import BleakScanner
    except ImportError:
        print(
            "python-bleak is required: sudo pacman -S python-bleak",
            file=sys.stderr,
        )
        return 2

    expected_address = address.upper() if address else None
    finished = asyncio.Event()

    def on_advertisement(device: Any, advertisement: Any) -> None:
        reading = decode_advertisement(device, advertisement)
        if not reading or (
            expected_address and reading["address"] != expected_address
        ):
            return

        print(json.dumps(reading, ensure_ascii=False), flush=True)
        if once:
            finished.set()

    loop = asyncio.get_running_loop()
    if not once:
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, finished.set)

    try:
        async with BleakScanner(on_advertisement):
            if once:
                await asyncio.wait_for(finished.wait(), timeout)
            else:
                await finished.wait()
    except TimeoutError:
        print("W3400010 advertisement not found", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"Bluetooth scan failed: {error}", file=sys.stderr)
        return 1

    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="limit readings to one BLE MAC address")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--once", action="store_true", help="exit after one reading")
    parser.add_argument(
        "--timeout",
        type=float,
        default=30,
        help="seconds to wait with --once (default: 30)",
    )
    args = parser.parse_args()
    try:
        address = (
            args.address
            if args.address is not None
            else load_clock_config(args.config).switchbot_address
        )
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"SwitchBot config failed: {error}", file=sys.stderr)
        return 2
    return asyncio.run(scan(address, args.once, args.timeout))


if __name__ == "__main__":
    raise SystemExit(main())
