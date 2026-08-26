#!/usr/bin/env python3
"""Load private, host-specific settings for desktop automation."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_CONFIG = Path.home() / ".config/quickshell/performance/machine.json"
LOCAL_STORAGE_KINDS = frozenset({"ssd", "hdd", "other"})


@dataclass(frozen=True)
class LocalStorageConfig:
    label: str
    path: Path
    kind: str


@dataclass(frozen=True)
class MachineConfig:
    automation_enabled: bool
    waywallen_control: Path | None
    ddc_enabled: bool
    ddc_bus: int | None
    physical_power_detection_enabled: bool
    brightness_feature: str
    online_brightness: int
    offline_brightness: int
    brightness_retry_seconds: float


def _load_config_object(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("machine config must be a JSON object")
    return data


def _required(data: dict[str, Any], field: str) -> Any:
    if field not in data:
        raise ValueError(f"machine config field {field!r} is required")
    return data[field]


def _local_storage(data: dict[str, Any]) -> tuple[LocalStorageConfig, ...]:
    raw_volumes = _required(data, "local_storage")
    if not isinstance(raw_volumes, list):
        raise ValueError("machine config field 'local_storage' must be a list")

    volumes: list[LocalStorageConfig] = []
    labels: set[str] = set()
    paths: set[Path] = set()
    for index, raw_volume in enumerate(raw_volumes):
        field = f"local_storage[{index}]"
        if not isinstance(raw_volume, dict):
            raise ValueError(f"machine config field '{field}' must be an object")

        label = raw_volume.get("label")
        if not isinstance(label, str) or not label.strip():
            raise ValueError(
                f"machine config field '{field}.label' must be a non-empty string"
            )
        label = label.strip()

        raw_path = raw_volume.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            raise ValueError(
                f"machine config field '{field}.path' must be an absolute path"
            )
        volume_path = Path(raw_path)
        if not volume_path.is_absolute():
            raise ValueError(
                f"machine config field '{field}.path' must be an absolute path"
            )
        volume_path = volume_path.resolve(strict=False)
        if volume_path == Path("/"):
            raise ValueError(
                f"machine config field '{field}.path' must not resolve to root"
            )

        kind = raw_volume.get("kind")
        if kind not in LOCAL_STORAGE_KINDS:
            raise ValueError(
                f"machine config field '{field}.kind' must be one of "
                "'ssd', 'hdd', or 'other'"
            )
        if label in labels:
            raise ValueError("machine config local storage labels must be unique")
        if volume_path in paths:
            raise ValueError("machine config local storage paths must be unique")

        labels.add(label)
        paths.add(volume_path)
        volumes.append(
            LocalStorageConfig(label=label, path=volume_path, kind=kind)
        )

    return tuple(volumes)


def load_local_storage(path: Path) -> tuple[LocalStorageConfig, ...]:
    """Load only local storage settings, independently of automation fields."""
    return _local_storage(_load_config_object(path))


def _brightness(data: dict[str, Any], field: str) -> int:
    value = _required(data, field)
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 100:
        raise ValueError(f"machine config field {field!r} must be 0 through 100")
    return value


def load_machine_config(path: Path) -> MachineConfig:
    data = _load_config_object(path)

    automation_enabled = _required(data, "automation_enabled")
    if not isinstance(automation_enabled, bool):
        raise ValueError(
            "machine config field 'automation_enabled' must be a boolean"
        )

    waywallen_value = _required(data, "waywallen_control")
    if waywallen_value is not None and (
        not isinstance(waywallen_value, str) or not waywallen_value
    ):
        raise ValueError(
            "machine config field 'waywallen_control' must be a path or null"
        )
    waywallen_control = (
        Path(waywallen_value).expanduser()
        if isinstance(waywallen_value, str)
        else None
    )

    ddc_enabled = _required(data, "ddc_enabled")
    if not isinstance(ddc_enabled, bool):
        raise ValueError("machine config field 'ddc_enabled' must be a boolean")

    ddc_bus = _required(data, "ddc_bus")
    if ddc_enabled and (
        isinstance(ddc_bus, bool) or not isinstance(ddc_bus, int) or ddc_bus < 0
    ):
        raise ValueError(
            "machine config field 'ddc_bus' must be a non-negative integer"
        )
    if not ddc_enabled and ddc_bus is not None and (
        isinstance(ddc_bus, bool) or not isinstance(ddc_bus, int) or ddc_bus < 0
    ):
        raise ValueError(
            "machine config field 'ddc_bus' must be a non-negative integer or null"
        )

    physical_power_detection_enabled = _required(
        data, "physical_power_detection_enabled"
    )
    if not isinstance(physical_power_detection_enabled, bool):
        raise ValueError(
            "machine config field 'physical_power_detection_enabled' "
            "must be a boolean"
        )
    if physical_power_detection_enabled and not ddc_enabled:
        raise ValueError(
            "machine config field 'physical_power_detection_enabled' "
            "requires 'ddc_enabled'"
        )

    brightness_feature = _required(data, "brightness_feature")
    if not isinstance(brightness_feature, str) or not brightness_feature:
        raise ValueError(
            "machine config field 'brightness_feature' must be a non-empty string"
        )

    retry_seconds = _required(data, "brightness_retry_seconds")
    if (
        isinstance(retry_seconds, bool)
        or not isinstance(retry_seconds, (int, float))
    ):
        raise ValueError(
            "machine config field 'brightness_retry_seconds' must be positive"
        )
    retry_seconds_value = float(retry_seconds)
    if not math.isfinite(retry_seconds_value) or retry_seconds_value <= 0:
        raise ValueError(
            "machine config field 'brightness_retry_seconds' must be positive"
        )

    return MachineConfig(
        automation_enabled=automation_enabled,
        waywallen_control=waywallen_control,
        ddc_enabled=ddc_enabled,
        ddc_bus=ddc_bus if isinstance(ddc_bus, int) else None,
        physical_power_detection_enabled=physical_power_detection_enabled,
        brightness_feature=brightness_feature,
        online_brightness=_brightness(data, "online_brightness"),
        offline_brightness=_brightness(data, "offline_brightness"),
        brightness_retry_seconds=retry_seconds_value,
    )
