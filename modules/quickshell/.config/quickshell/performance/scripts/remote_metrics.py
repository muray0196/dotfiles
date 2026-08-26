#!/usr/bin/env python3
"""Stream normalized metrics from the Windows performance exporter."""

from __future__ import annotations

import argparse
import json
import math
import signal
import socket
import sys
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

from desktop_automation import DEFAULT_SETTINGS, DesktopAutomation
from machine_config import (
    DEFAULT_CONFIG as DEFAULT_MACHINE_CONFIG,
    load_machine_config,
)


DEFAULT_CONFIG = Path.home() / ".config/quickshell/performance/remote.json"
MEBIBYTE = 1024 * 1024


def load_config(path: Path) -> tuple[str, str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("remote config must be a JSON object")
    endpoint = data.get("endpoint")
    token = data.get("token")
    if not isinstance(endpoint, str):
        raise ValueError("remote endpoint must be an HTTP URL")
    try:
        parsed = urlsplit(endpoint)
        hostname = parsed.hostname
        port = parsed.port
    except ValueError as error:
        raise ValueError("remote endpoint must be an HTTP URL") from error
    if (
        parsed.scheme != "http"
        or not hostname
        or (port is not None and port <= 0)
        or any(character.isspace() for character in endpoint)
    ):
        raise ValueError("remote endpoint must be an HTTP URL")
    if not isinstance(token, str) or not token:
        raise ValueError("remote bearer token is missing")
    return endpoint, token


def ipv4_endpoints(endpoint: str) -> list[str]:
    """Resolve explicit IPv4 candidates without depending on AF_UNSPEC order."""
    parsed = urlsplit(endpoint)
    hostname = parsed.hostname
    if hostname is None:
        return []

    port = parsed.port or 80
    try:
        addresses = socket.getaddrinfo(
            hostname,
            port,
            family=socket.AF_INET,
            type=socket.SOCK_STREAM,
            proto=socket.IPPROTO_TCP,
        )
    except OSError:
        return []

    candidates: list[str] = []
    for address in addresses:
        ipv4_address = address[4][0]
        candidate = urlunsplit(parsed._replace(netloc=f"{ipv4_address}:{port}"))
        if candidate not in candidates and candidate != endpoint:
            candidates.append(candidate)
    return candidates


def fetch_snapshot(
    endpoint: str,
    token: str,
    timeout: float,
    preferred_endpoint: str | None = None,
) -> tuple[dict[str, Any], str]:
    parsed = urlsplit(endpoint)
    hostname = parsed.hostname
    port = parsed.port or 80
    host_header = hostname or ""
    if port != 80:
        host_header = f"{host_header}:{port}"

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "QuickshellPerformanceWidget/1.0",
        "Host": host_header,
    }
    last_error: OSError | None = None

    def fetch_candidate(candidate: str) -> tuple[dict[str, Any], str]:
        request = Request(candidate, headers=headers)
        with urlopen(request, timeout=timeout) as response:
            snapshot = json.load(response)
        if not isinstance(snapshot, dict):
            raise ValueError("remote response must be a JSON object")
        return snapshot, candidate

    if preferred_endpoint is not None:
        try:
            return fetch_candidate(preferred_endpoint)
        except HTTPError:
            raise
        except OSError as error:
            last_error = error

    candidates = [*ipv4_endpoints(endpoint), endpoint]
    for candidate in candidates:
        if candidate == preferred_endpoint:
            continue
        try:
            return fetch_candidate(candidate)
        except HTTPError:
            raise
        except OSError as error:
            last_error = error

    if last_error is not None:
        raise last_error
    raise OSError("remote endpoint has no usable address")


def metric_map(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    afterburner = snapshot.get("afterburner")
    if not isinstance(afterburner, dict) or not afterburner.get("available"):
        raise ValueError("MSI Afterburner data is unavailable")
    if afterburner.get("stale"):
        raise ValueError("MSI Afterburner data is stale")

    metrics = afterburner.get("metrics")
    if not isinstance(metrics, list):
        raise ValueError("MSI Afterburner metrics are missing")

    result: dict[str, dict[str, Any]] = {}
    for metric in metrics:
        if isinstance(metric, dict) and isinstance(metric.get("name"), str):
            result[metric["name"].casefold()] = metric
    return result


def numeric_metric(
    metrics: dict[str, dict[str, Any]], name: str, unit: str
) -> float | None:
    metric = metrics.get(name.casefold())
    if metric is None or metric.get("unit") != unit:
        return None
    value = metric.get("value")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric_value = float(value)
    return numeric_value if math.isfinite(numeric_value) else None


def discrete_gpu(snapshot: dict[str, Any]) -> dict[str, Any]:
    afterburner = snapshot.get("afterburner", {})
    gpus = afterburner.get("gpus", [])
    candidates = [
        gpu
        for gpu in gpus
        if isinstance(gpu, dict)
        and not isinstance(gpu.get("index"), bool)
        and isinstance(gpu.get("index"), int)
        and not isinstance(gpu.get("memory_bytes"), bool)
        and isinstance(gpu.get("memory_bytes"), int)
        and gpu["memory_bytes"] > 0
    ]
    if not candidates:
        raise ValueError("GPU memory totals are unavailable")
    return max(candidates, key=lambda gpu: gpu["memory_bytes"])


def usage_percent(used: float | None, total: float | None) -> float | None:
    if (
        used is None
        or total is None
        or not math.isfinite(used)
        or not math.isfinite(total)
        or used < 0
        or total <= 0
    ):
        return None
    return round(min(100.0, max(0.0, 100.0 * used / total)), 1)


def normalize(snapshot: dict[str, Any]) -> dict[str, Any]:
    metrics = metric_map(snapshot)
    gpu = discrete_gpu(snapshot)
    gpu_number = gpu["index"] + 1
    gpu_prefix = f"GPU{gpu_number}"

    memory = snapshot.get("memory")
    raw_memory_total = (
        memory.get("total_bytes") if isinstance(memory, dict) else None
    )
    memory_total = (
        float(raw_memory_total)
        if not isinstance(raw_memory_total, bool)
        and isinstance(raw_memory_total, (int, float))
        and math.isfinite(float(raw_memory_total))
        else None
    )
    memory_used_mb = numeric_metric(metrics, "RAM usage", "MB")
    memory_used = (
        memory_used_mb * MEBIBYTE if memory_used_mb is not None else None
    )

    vram_total = float(gpu["memory_bytes"])
    vram_used_mb = numeric_metric(metrics, f"{gpu_prefix} memory usage", "MB")
    vram_used = vram_used_mb * MEBIBYTE if vram_used_mb is not None else None

    cpu_info = snapshot.get("cpu")
    cpu_model = (
        cpu_info.get("model")
        if isinstance(cpu_info, dict) and isinstance(cpu_info.get("model"), str)
        else None
    )
    cpu_usage = numeric_metric(metrics, "CPU usage", "%")
    gpu_usage = numeric_metric(metrics, f"{gpu_prefix} usage", "%")
    memory_usage = usage_percent(memory_used, memory_total)
    vram_usage = usage_percent(vram_used, vram_total)
    if cpu_usage is None or not 0 <= cpu_usage <= 100:
        raise ValueError("required CPU usage metric is invalid")
    if gpu_usage is None or not 0 <= gpu_usage <= 100:
        raise ValueError("required GPU usage metric is invalid")
    if memory_usage is None:
        raise ValueError("required MEMORY metric is missing")
    if vram_usage is None:
        raise ValueError("required VRAM metric is missing")

    normalized: dict[str, Any] = {
        "schema_version": 2,
        "host": (
            snapshot["host"]
            if isinstance(snapshot.get("host"), str)
            else "main-pc"
        ),
        "cpu": {
            "model": cpu_model,
            "usage_percent": cpu_usage,
            "temperature_c": numeric_metric(metrics, "CPU temperature", "°C"),
            "power_w": numeric_metric(metrics, "CPU power", "W"),
        },
        "gpus": [
            {
                "model": gpu.get("device"),
                "usage_percent": gpu_usage,
                "temperature_c": numeric_metric(
                    metrics, f"{gpu_prefix} temperature", "°C"
                ),
                "power_w": numeric_metric(
                    metrics, f"{gpu_prefix} power", "W"
                ),
                "vram": {
                    "used_bytes": vram_used,
                    "total_bytes": vram_total,
                    "usage_percent": vram_usage,
                },
            }
        ],
        "memory": {
            "used_bytes": memory_used,
            "total_bytes": memory_total,
            "usage_percent": memory_usage,
        },
    }
    return normalized


def stream(
    config_path: Path,
    interval: float,
    timeout: float,
    once: bool,
    automation: DesktopAutomation | None = None,
) -> int:
    if interval <= 0 or timeout <= 0:
        print("interval and timeout must be greater than zero", file=sys.stderr)
        return 2

    try:
        endpoint, token = load_config(config_path)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"remote metrics configuration failed: {error}", file=sys.stderr)
        return 2

    finished = False
    last_error_log = 0.0
    preferred_endpoint: str | None = None

    def stop(*_: object) -> None:
        nonlocal finished
        finished = True

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    while not finished:
        started = time.monotonic()
        if automation is not None:
            automation.tick()
        try:
            snapshot, preferred_endpoint = fetch_snapshot(
                endpoint, token, timeout, preferred_endpoint
            )
            reading = normalize(snapshot)
            if automation is not None:
                automation.heartbeat()
            print(json.dumps(reading, separators=(",", ":")), flush=True)
        except (OSError, ValueError, json.JSONDecodeError) as error:
            preferred_endpoint = None
            now = time.monotonic()
            if now - last_error_log >= 60:
                print(f"remote metrics failed: {error}", file=sys.stderr, flush=True)
                last_error_log = now
            if once:
                return 1

        if automation is not None:
            automation.tick()

        if once:
            break

        remaining = interval - (time.monotonic() - started)
        if remaining > 0:
            time.sleep(remaining)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--timeout", type=float, default=1.5)
    parser.add_argument("--once", action="store_true")
    parser.add_argument("--automation", action="store_true")
    parser.add_argument(
        "--automation-settings",
        type=Path,
        default=DEFAULT_SETTINGS,
    )
    parser.add_argument(
        "--machine-config",
        type=Path,
        default=DEFAULT_MACHINE_CONFIG,
    )
    args = parser.parse_args()
    automation = None
    if args.automation:
        try:
            machine_config = load_machine_config(args.machine_config)
            if machine_config.automation_enabled:
                automation = DesktopAutomation(
                    settings_path=args.automation_settings,
                    machine_config=machine_config,
                )
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            print(
                f"desktop automation disabled: {error}",
                file=sys.stderr,
                flush=True,
            )
    return stream(args.config, args.interval, args.timeout, args.once, automation)


if __name__ == "__main__":
    raise SystemExit(main())
