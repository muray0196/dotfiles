#!/usr/bin/env python3
"""Load private, machine-local settings for the clock widget."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit


DEFAULT_CONFIG = Path.home() / ".config/quickshell/clock/local.json"
BLE_ADDRESS_PATTERN = re.compile(r"(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")


@dataclass(frozen=True)
class ClockConfig:
    switchbot_address: str
    weathernews_url: str
    latitude: float
    longitude: float


def _required_string(data: dict[str, object], field: str) -> str:
    value = data.get(field)
    if not isinstance(value, str) or not value:
        raise ValueError(f"clock config field {field!r} must be a non-empty string")
    return value


def _required_number(data: dict[str, object], field: str) -> float:
    value = data.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"clock config field {field!r} must be a number")
    return float(value)


def load_clock_config(path: Path = DEFAULT_CONFIG) -> ClockConfig:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("clock config must be a JSON object")

    switchbot_address = _required_string(data, "switchbot_address")
    if BLE_ADDRESS_PATTERN.fullmatch(switchbot_address) is None:
        raise ValueError("clock config field 'switchbot_address' is invalid")

    weathernews_url = _required_string(data, "weathernews_url")
    parsed_url = urlsplit(weathernews_url)
    if parsed_url.scheme != "https" or not parsed_url.hostname:
        raise ValueError("clock config field 'weathernews_url' must be an HTTPS URL")

    latitude = _required_number(data, "latitude")
    longitude = _required_number(data, "longitude")
    if not -85.05112878 <= latitude <= 85.05112878:
        raise ValueError("clock config field 'latitude' is out of range")
    if not -180 <= longitude <= 180:
        raise ValueError("clock config field 'longitude' is out of range")

    return ClockConfig(
        switchbot_address=switchbot_address.upper(),
        weathernews_url=weathernews_url,
        latitude=latitude,
        longitude=longitude,
    )
