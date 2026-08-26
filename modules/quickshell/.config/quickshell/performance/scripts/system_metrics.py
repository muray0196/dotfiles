#!/usr/bin/env python3
"""Stream local hardware and system metrics as JSON lines."""

from __future__ import annotations

import argparse
import json
import shutil
import signal
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from machine_config import DEFAULT_CONFIG, LocalStorageConfig, load_local_storage


HWMON_ROOT = Path("/sys/class/hwmon")
DRM_ROOT = Path("/sys/class/drm")
RAPL_ROOT = Path("/sys/class/powercap/intel-rapl:0")
PCI_IDS = Path("/usr/share/hwdata/pci.ids")
PROC_NET_ROUTE = Path("/proc/net/route")
PROC_NET_DEV = Path("/proc/net/dev")
PROC_UPTIME = Path("/proc/uptime")
HARDWARE_DISCOVERY_INTERVAL_SECONDS = 60.0


@dataclass(frozen=True)
class AmdGpuDevice:
    id: str
    device: Path
    display_connected: bool
    model: str | None
    temperature_input: Path | None
    hotspot_temperature_input: Path | None
    power_input: Path | None


@dataclass(frozen=True)
class LocalHardware:
    cpu_model: str | None
    cpu_temperature_input: Path | None
    gpu_devices: tuple[AmdGpuDevice, ...]
    rapl_max_energy: int | None


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None


def read_int(path: Path | None) -> int | None:
    if path is None:
        return None
    value = read_text(path)
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def find_hwmon(name: str) -> Path | None:
    for hwmon in sorted(HWMON_ROOT.glob("hwmon*")):
        if read_text(hwmon / "name") == name:
            return hwmon
    return None


def find_amdgpu_devices() -> tuple[AmdGpuDevice, ...]:
    devices: list[AmdGpuDevice] = []
    for card in DRM_ROOT.glob("card*"):
        if not card.name.removeprefix("card").isdigit():
            continue
        device_link = card / "device"
        try:
            device = device_link.resolve(strict=True)
            driver = (device / "driver").resolve(strict=True).name
        except OSError:
            continue
        if driver != "amdgpu":
            continue

        hwmon = None
        for candidate in sorted((device / "hwmon").glob("hwmon*")):
            if read_text(candidate / "name") == "amdgpu":
                hwmon = candidate
                break

        display_connected = any(
            read_text(connector / "status") == "connected"
            for connector in DRM_ROOT.glob(f"{card.name}-*")
        )
        devices.append(
            AmdGpuDevice(
                id=device.name,
                device=device,
                display_connected=display_connected,
                model=read_pci_model(device),
                temperature_input=find_labeled_input_path(
                    hwmon, "temp", "edge"
                ),
                hotspot_temperature_input=find_labeled_input_path(
                    hwmon, "temp", "junction"
                ),
                power_input=find_labeled_input_path(
                    hwmon, "power", "PPT", "average"
                ),
            )
        )

    return tuple(sorted(devices, key=lambda gpu: gpu.id))


def read_cpu_model() -> str | None:
    try:
        with Path("/proc/cpuinfo").open(encoding="utf-8") as cpuinfo:
            for line in cpuinfo:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except (OSError, UnicodeError, IndexError):
        return None
    return None


def read_pci_model(device: Path | None) -> str | None:
    if device is None:
        return None
    vendor_id = read_text(device / "vendor")
    device_id = read_text(device / "device")
    if vendor_id is None or device_id is None:
        return None
    wanted_vendor = vendor_id.removeprefix("0x").casefold()
    wanted_device = device_id.removeprefix("0x").casefold()

    in_vendor = False
    try:
        with PCI_IDS.open(encoding="utf-8", errors="replace") as pci_ids:
            for line in pci_ids:
                if not line.strip() or line.startswith("#"):
                    continue
                if not line.startswith("\t"):
                    fields = line.split(maxsplit=1)
                    in_vendor = bool(fields and fields[0].casefold() == wanted_vendor)
                    continue
                if in_vendor and not line.startswith("\t\t"):
                    fields = line.strip().split(maxsplit=1)
                    if fields and fields[0].casefold() == wanted_device:
                        name = fields[1] if len(fields) > 1 else None
                        if name and "[" in name and name.endswith("]"):
                            return name.rsplit("[", 1)[1][:-1]
                        return name
    except OSError:
        return None
    return None


def find_labeled_input_path(
    hwmon: Path | None,
    prefix: str,
    wanted_label: str,
    value_suffix: str = "input",
) -> Path | None:
    if hwmon is None:
        return None
    for label_path in sorted(hwmon.glob(f"{prefix}*_label")):
        if read_text(label_path) != wanted_label:
            continue
        input_path = label_path.with_name(
            label_path.name.removesuffix("_label") + f"_{value_suffix}"
        )
        return input_path
    return None


def discover_hardware() -> LocalHardware:
    cpu_hwmon = find_hwmon("coretemp")
    return LocalHardware(
        cpu_model=read_cpu_model(),
        cpu_temperature_input=find_labeled_input_path(
            cpu_hwmon, "temp", "Package id 0"
        ),
        gpu_devices=find_amdgpu_devices(),
        rapl_max_energy=read_int(RAPL_ROOT / "max_energy_range_uj"),
    )


def read_cpu_times() -> tuple[int, int]:
    with Path("/proc/stat").open(encoding="utf-8") as stat_file:
        fields = stat_file.readline().split()
    if not fields or fields[0] != "cpu" or len(fields) < 9:
        raise ValueError("aggregate CPU counters were not found")

    counters = [int(value) for value in fields[1:]]
    # guest and guest_nice are already included in user and nice.
    total = sum(counters[:8])
    idle = counters[3] + counters[4]
    return total, idle


def usage_percent(
    previous: tuple[int, int], current: tuple[int, int]
) -> float | None:
    total_delta = current[0] - previous[0]
    idle_delta = current[1] - previous[1]
    if total_delta <= 0:
        return None
    usage = 100.0 * (total_delta - idle_delta) / total_delta
    return round(min(100.0, max(0.0, usage)), 1)


def read_meminfo() -> dict[str, int]:
    values: dict[str, int] = {}
    with Path("/proc/meminfo").open(encoding="utf-8") as meminfo:
        for line in meminfo:
            name, raw_value = line.split(":", 1)
            fields = raw_value.split()
            if fields:
                values[name] = int(fields[0]) * 1024
    return values


def read_storage() -> tuple[int | None, int | None]:
    try:
        usage = shutil.disk_usage("/")
    except OSError:
        return None, None
    return usage.used, usage.total


def read_storage_volumes(
    volumes: tuple[LocalStorageConfig, ...],
) -> list[dict[str, Any]]:
    readings: list[dict[str, Any]] = []
    for volume in volumes:
        available = False
        used: int | None = None
        total: int | None = None
        try:
            if volume.path.is_mount():
                usage = shutil.disk_usage(volume.path)
                available = True
                used = usage.used
                total = usage.total
        except OSError:
            pass

        readings.append(
            {
                "label": volume.label,
                "kind": volume.kind,
                "available": available,
                "used_bytes": used,
                "total_bytes": total,
                "usage_percent": bytes_usage(used, total),
            }
        )
    return readings


def read_uptime_seconds() -> float | None:
    value = read_text(PROC_UPTIME)
    if value is None:
        return None
    try:
        return float(value.split(maxsplit=1)[0])
    except (IndexError, ValueError):
        return None


def read_default_interface() -> str | None:
    try:
        with PROC_NET_ROUTE.open(encoding="utf-8") as routes:
            next(routes, None)
            for line in routes:
                fields = line.split()
                if len(fields) < 4 or fields[1] != "00000000":
                    continue
                try:
                    flags = int(fields[3], 16)
                except ValueError:
                    continue
                if flags & 0x2:
                    return fields[0]
    except (OSError, UnicodeError):
        return None
    return None


def read_network_counters() -> tuple[str, int, int] | None:
    interface = read_default_interface()
    if interface is None:
        return None

    try:
        with PROC_NET_DEV.open(encoding="utf-8") as devices:
            for line in devices:
                if ":" not in line:
                    continue
                name, values = line.split(":", 1)
                if name.strip() != interface:
                    continue
                fields = values.split()
                if len(fields) < 9:
                    return None
                return interface, int(fields[0]), int(fields[8])
    except (OSError, UnicodeError, ValueError):
        return None
    return None


def network_rates(
    previous: tuple[str, int, int] | None,
    current: tuple[str, int, int] | None,
    elapsed: float,
) -> tuple[float | None, float | None]:
    if (
        previous is None
        or current is None
        or previous[0] != current[0]
        or elapsed <= 0
    ):
        return None, None

    received = current[1] - previous[1]
    transmitted = current[2] - previous[2]
    if received < 0 or transmitted < 0:
        return None, None
    return round(received / elapsed, 1), round(transmitted / elapsed, 1)


def bytes_usage(used: int | None, total: int | None) -> float | None:
    if used is None or total is None or total <= 0:
        return None
    return round(min(100.0, max(0.0, 100.0 * used / total)), 1)


def temperature_c(value: int | None) -> float | None:
    return round(value / 1000.0, 1) if value is not None else None


def power_w(value: int | None) -> float | None:
    return round(value / 1_000_000.0, 1) if value is not None else None


def rapl_power_w(
    previous_energy: int | None,
    current_energy: int | None,
    elapsed: float,
    max_energy: int | None,
) -> float | None:
    if previous_energy is None or current_energy is None or elapsed <= 0:
        return None

    if current_energy >= previous_energy:
        energy_delta = current_energy - previous_energy
    elif max_energy is not None:
        energy_delta = max_energy - previous_energy + current_energy
    else:
        return None

    watts = energy_delta / 1_000_000.0 / elapsed
    if not 0 <= watts <= 1000:
        return None
    return round(watts, 1)


def read_gpu(gpu: AmdGpuDevice) -> dict[str, Any]:
    gpu_usage = read_int(gpu.device / "gpu_busy_percent")
    vram_total = read_int(gpu.device / "mem_info_vram_total")
    vram_used = read_int(gpu.device / "mem_info_vram_used")
    return {
        "id": gpu.id,
        "display_connected": gpu.display_connected,
        "runtime_status": read_text(gpu.device / "power/runtime_status"),
        "model": gpu.model,
        "usage_percent": float(gpu_usage) if gpu_usage is not None else None,
        "temperature_c": temperature_c(read_int(gpu.temperature_input)),
        "hotspot_temperature_c": temperature_c(
            read_int(gpu.hotspot_temperature_input)
        ),
        "power_w": power_w(read_int(gpu.power_input)),
        "vram": {
            "used_bytes": vram_used,
            "total_bytes": vram_total,
            "usage_percent": bytes_usage(vram_used, vram_total),
        },
    }


def read_snapshot(
    previous_cpu: tuple[int, int],
    previous_energy: int | None,
    previous_network: tuple[str, int, int] | None,
    previous_time: float,
    hardware: LocalHardware,
    local_storage: tuple[LocalStorageConfig, ...],
) -> tuple[
    dict[str, Any],
    tuple[int, int],
    int | None,
    tuple[str, int, int] | None,
    float,
]:
    now = time.monotonic()
    current_cpu = read_cpu_times()
    current_energy = read_int(RAPL_ROOT / "energy_uj")
    current_network = read_network_counters()
    elapsed = now - previous_time
    download_rate, upload_rate = network_rates(
        previous_network, current_network, elapsed
    )
    storage_used, storage_total = read_storage()

    meminfo = read_meminfo()
    memory_total = meminfo.get("MemTotal")
    memory_available = meminfo.get("MemAvailable")
    memory_used = (
        memory_total - memory_available
        if memory_total is not None and memory_available is not None
        else None
    )
    gpus = [read_gpu(gpu) for gpu in hardware.gpu_devices]

    reading: dict[str, Any] = {
        "schema_version": 2,
        "host": "local",
        "cpu": {
            "model": hardware.cpu_model,
            "usage_percent": usage_percent(previous_cpu, current_cpu),
            "temperature_c": temperature_c(
                read_int(hardware.cpu_temperature_input)
            ),
            "power_w": rapl_power_w(
                previous_energy,
                current_energy,
                elapsed,
                hardware.rapl_max_energy,
            ),
        },
        "gpus": gpus,
        "memory": {
            "used_bytes": memory_used,
            "total_bytes": memory_total,
            "usage_percent": bytes_usage(memory_used, memory_total),
        },
        "storage": {
            "used_bytes": storage_used,
            "total_bytes": storage_total,
            "usage_percent": bytes_usage(storage_used, storage_total),
        },
        "storage_volumes": read_storage_volumes(local_storage),
        "network": {
            "interface": current_network[0] if current_network else None,
            "download_bytes_per_second": download_rate,
            "upload_bytes_per_second": upload_rate,
        },
        "uptime_seconds": read_uptime_seconds(),
    }
    return reading, current_cpu, current_energy, current_network, now


def stream(interval: float, once: bool, machine_config: Path) -> int:
    if interval <= 0:
        print("interval must be greater than zero", file=sys.stderr)
        return 2

    hardware = discover_hardware()
    try:
        local_storage = load_local_storage(machine_config)
    except FileNotFoundError:
        print(
            "system metrics warning: machine config not found; "
            "extra storage disabled",
            file=sys.stderr,
        )
        local_storage = ()
    except (OSError, UnicodeError, ValueError):
        print(
            "system metrics warning: machine config could not be loaded; "
            "extra storage disabled",
            file=sys.stderr,
        )
        local_storage = ()

    try:
        previous_cpu = read_cpu_times()
    except (OSError, ValueError) as error:
        print(f"system metrics failed: {error}", file=sys.stderr)
        return 1
    previous_energy = read_int(RAPL_ROOT / "energy_uj")
    previous_network = read_network_counters()
    previous_time = time.monotonic()
    hardware_refresh_at = (
        previous_time + HARDWARE_DISCOVERY_INTERVAL_SECONDS
    )
    finished = False

    def stop(*_: object) -> None:
        nonlocal finished
        finished = True

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    next_sample = time.monotonic() + interval
    while not finished:
        remaining = next_sample - time.monotonic()
        if remaining > 0:
            time.sleep(remaining)
        if finished:
            break
        next_sample += interval
        if time.monotonic() >= hardware_refresh_at:
            hardware = discover_hardware()
            hardware_refresh_at = (
                time.monotonic() + HARDWARE_DISCOVERY_INTERVAL_SECONDS
            )
        try:
            (
                reading,
                previous_cpu,
                previous_energy,
                previous_network,
                previous_time,
            ) = read_snapshot(
                previous_cpu,
                previous_energy,
                previous_network,
                previous_time,
                hardware,
                local_storage,
            )
        except (OSError, ValueError) as error:
            print(f"system metrics failed: {error}", file=sys.stderr, flush=True)
            if once:
                return 1
        else:
            print(json.dumps(reading, separators=(",", ":")), flush=True)
            if once:
                break
        if next_sample <= time.monotonic():
            next_sample = time.monotonic() + interval

    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--interval",
        type=float,
        default=2.0,
        help="seconds between readings (default: 2)",
    )
    parser.add_argument("--once", action="store_true", help="print one reading")
    parser.add_argument(
        "--machine-config",
        type=Path,
        default=DEFAULT_CONFIG,
        help="path to private machine settings",
    )
    args = parser.parse_args()
    return stream(args.interval, args.once, args.machine_config)


if __name__ == "__main__":
    raise SystemExit(main())
