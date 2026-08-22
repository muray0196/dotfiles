#!/usr/bin/env python3
"""Stream local hardware and system metrics as JSON lines."""

from __future__ import annotations

import argparse
import json
import shutil
import signal
import sys
import time
from pathlib import Path
from typing import Any


HWMON_ROOT = Path("/sys/class/hwmon")
DRM_ROOT = Path("/sys/class/drm")
RAPL_ROOT = Path("/sys/class/powercap/intel-rapl:0")
PCI_IDS = Path("/usr/share/hwdata/pci.ids")
PROC_NET_ROUTE = Path("/proc/net/route")
PROC_NET_DEV = Path("/proc/net/dev")
PROC_UPTIME = Path("/proc/uptime")


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None


def read_int(path: Path) -> int | None:
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


def find_amdgpu_device() -> Path | None:
    for card in sorted(DRM_ROOT.glob("card*")):
        if not card.name.removeprefix("card").isdigit():
            continue
        device = card / "device"
        try:
            driver = (device / "driver").resolve(strict=True).name
        except OSError:
            continue
        if driver == "amdgpu":
            return device
    return None


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


def find_labeled_input(
    hwmon: Path | None,
    prefix: str,
    wanted_label: str,
    value_suffix: str = "input",
) -> int | None:
    if hwmon is None:
        return None
    for label_path in sorted(hwmon.glob(f"{prefix}*_label")):
        if read_text(label_path) != wanted_label:
            continue
        input_path = label_path.with_name(
            label_path.name.removesuffix("_label") + f"_{value_suffix}"
        )
        return read_int(input_path)
    return None


def read_cpu_times() -> tuple[int, int]:
    with Path("/proc/stat").open(encoding="utf-8") as stat_file:
        fields = stat_file.readline().split()
    if not fields or fields[0] != "cpu" or len(fields) < 6:
        raise ValueError("aggregate CPU counters were not found")

    counters = [int(value) for value in fields[1:]]
    total = sum(counters)
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


def read_snapshot(
    previous_cpu: tuple[int, int],
    previous_energy: int | None,
    previous_network: tuple[str, int, int] | None,
    previous_time: float,
    cpu_hwmon: Path | None,
    gpu_hwmon: Path | None,
    gpu_device: Path | None,
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
    max_energy = read_int(RAPL_ROOT / "max_energy_range_uj")
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

    gpu_usage = (
        read_int(gpu_device / "gpu_busy_percent")
        if gpu_device is not None
        else None
    )
    vram_total = (
        read_int(gpu_device / "mem_info_vram_total")
        if gpu_device is not None
        else None
    )
    vram_used = (
        read_int(gpu_device / "mem_info_vram_used")
        if gpu_device is not None
        else None
    )

    reading: dict[str, Any] = {
        "schema_version": 1,
        "host": "local",
        "timestamp": int(time.time()),
        "cpu": {
            "model": read_cpu_model(),
            "usage_percent": usage_percent(previous_cpu, current_cpu),
            "temperature_c": temperature_c(
                find_labeled_input(cpu_hwmon, "temp", "Package id 0")
            ),
            "power_w": rapl_power_w(
                previous_energy,
                current_energy,
                elapsed,
                max_energy,
            ),
        },
        "gpu": {
            "model": read_pci_model(gpu_device),
            "usage_percent": float(gpu_usage) if gpu_usage is not None else None,
            "temperature_c": temperature_c(
                find_labeled_input(gpu_hwmon, "temp", "edge")
            ),
            "power_w": power_w(
                find_labeled_input(gpu_hwmon, "power", "PPT", "average")
            ),
        },
        "memory": {
            "used_bytes": memory_used,
            "total_bytes": memory_total,
            "usage_percent": bytes_usage(memory_used, memory_total),
        },
        "vram": {
            "used_bytes": vram_used,
            "total_bytes": vram_total,
            "usage_percent": bytes_usage(vram_used, vram_total),
        },
        "storage": {
            "used_bytes": storage_used,
            "total_bytes": storage_total,
            "usage_percent": bytes_usage(storage_used, storage_total),
        },
        "network": {
            "interface": current_network[0] if current_network else None,
            "download_bytes_per_second": download_rate,
            "upload_bytes_per_second": upload_rate,
        },
        "uptime_seconds": read_uptime_seconds(),
    }
    return reading, current_cpu, current_energy, current_network, now


def stream(interval: float, once: bool) -> int:
    if interval <= 0:
        print("interval must be greater than zero", file=sys.stderr)
        return 2

    cpu_hwmon = find_hwmon("coretemp")
    gpu_hwmon = find_hwmon("amdgpu")
    gpu_device = find_amdgpu_device()

    try:
        previous_cpu = read_cpu_times()
    except (OSError, ValueError) as error:
        print(f"system metrics failed: {error}", file=sys.stderr)
        return 1
    previous_energy = read_int(RAPL_ROOT / "energy_uj")
    previous_network = read_network_counters()
    previous_time = time.monotonic()
    finished = False

    def stop(*_: object) -> None:
        nonlocal finished
        finished = True

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    while not finished:
        time.sleep(interval)
        if finished:
            break
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
                cpu_hwmon,
                gpu_hwmon,
                gpu_device,
            )
        except (OSError, ValueError) as error:
            print(f"system metrics failed: {error}", file=sys.stderr, flush=True)
            continue

        print(json.dumps(reading, separators=(",", ":")), flush=True)
        if once:
            break

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
    args = parser.parse_args()
    return stream(args.interval, args.once)


if __name__ == "__main__":
    raise SystemExit(main())
