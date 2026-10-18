#!/usr/bin/env python3
"""Read existing collectors for the isolated preview; never enable automation."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
WIDGETS = ROOT / "modules/quickshell/.config/quickshell"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "quickshell"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-widget-preview"


def commands():
    clock = WIDGETS / "clock/scripts"
    performance = WIDGETS / "performance/scripts"
    return {
        "local": [str(performance / "system_metrics.py"), "--once", "--machine-config", str(CONFIG / "performance/machine.json")],
        "main": [str(performance / "remote_metrics.py"), "--once", "--timeout", "1.5", "--config", str(CONFIG / "performance/remote.json")],
        "indoor": [str(clock / "switchbot_meter.py"), "--once", "--timeout", "12", "--config", str(CONFIG / "clock/local.json")],
        "outdoor": [str(clock / "weathernews_observation.py"), "--timeout", "12", "--config", str(CONFIG / "clock/local.json")],
        "radar": [str(clock / "jma_nowcast.py"), "--timeout", "8", "--animation-frames", "--viewport-width", "344", "--viewport-height", "252", "--config", str(CONFIG / "clock/local.json")],
        "holidays": [str(clock / "japanese_holidays.py"), "--timeout", "8", "--cache", str(CACHE / "holidays.json")],
    }


def read(name):
    try:
        result = subprocess.run([sys.executable, "-B", *commands()[name]], capture_output=True, text=True, timeout=25)
        if result.returncode:
            # The old collector's stderr can include private endpoint details.
            raise ValueError(f"collector exited {result.returncode}")
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise ValueError("collector returned a non-object")
        value.pop("address", None)
        value["_received_at"] = time.time()
        value["_status"] = "Snapshot"
        return value
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"{name}: {type(error).__name__}; no replacement reading generated", file=sys.stderr)
        return {"_status": "No signal" if name == "main" else "No data"}


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and float("-inf") < value < float("inf")


def machine_status(reading, now, remote=False):
    age = now - reading.get("_received_at", 0)
    if age > 6:
        return "No signal" if remote else "No data" if age > 30 else "Stale"
    cpu = reading.get("cpu", {})
    memory = reading.get("memory", {})
    gpus = reading.get("gpus", [])
    if not any(finite(v) for v in [cpu.get("usage_percent"), memory.get("usage_percent"), *[g.get("usage_percent") for g in gpus]]):
        return "No signal" if remote else "No data"
    metrics = [cpu, *gpus]
    partial = not gpus or any(not finite(m.get(k)) for m in metrics for k in ("usage_percent", "temperature_c", "power_w"))
    partial |= not finite(memory.get("usage_percent")) or any(not finite(g.get("vram", {}).get("usage_percent")) for g in gpus)
    if not remote:
        partial |= not finite(reading.get("uptime_seconds")) or not finite(reading.get("storage", {}).get("usage_percent"))
        partial |= any(not finite(reading.get("network", {}).get(k)) for k in ("download_bytes_per_second", "upload_bytes_per_second"))
    return "Partial" if partial else "Live"


class History:
    """The same 300 two-second buckets and complete-component power sums as the widget."""

    def __init__(self):
        self.samples = []
        self.started_bucket = None

    def capture(self, data, now):
        bucket = int(now // 2)
        values = {}
        for name, prefix, count in (("local", "local", 2), ("main", "main", 1)):
            machine = data.get(name, {})
            fresh = now - machine.get("_received_at", 0) <= 6
            cpu = machine.get("cpu", {})
            gpus = machine.get("gpus", [])
            values[prefix + "_cpu"] = cpu.get("temperature_c") if fresh else None
            for index in range(count):
                gpu = gpus[index] if index < len(gpus) else {}
                suffix = str(index + 1) if name == "local" else ""
                values[prefix + "_gpu" + suffix] = gpu.get("temperature_c") if fresh else None
                if name == "local":
                    values[prefix + "_hotspot" + suffix] = gpu.get("hotspot_temperature_c") if fresh else None
            powers = [cpu.get("power_w"), *[g.get("power_w") for g in gpus[:count]]]
            values[prefix + "_power"] = sum(powers) if fresh and len(powers) == count + 1 and all(finite(p) and p >= 0 for p in powers) else None
        if self.samples and bucket < self.samples[-1][0]:
            self.samples.clear()
            self.started_bucket = None
        if self.started_bucket is None:
            self.started_bucket = bucket
        self.samples = [(b, v) for b, v in self.samples if bucket - 300 < b < bucket]
        self.samples.append((bucket, values))
        summary = {"window_seconds": min(600, (bucket - self.started_bucket) * 2)}
        for key in values:
            valid = [v[key] for _, v in self.samples if finite(v.get(key))]
            if key.endswith("_power"):
                prefix = key.removesuffix("_power")
                summary[prefix + "_average"] = sum(valid) / len(valid) if valid else None
                summary[prefix + "_peak"] = max(valid) if valid else None
            else:
                summary[key] = max(valid) if valid else None
        return summary


def emit(data, history):
    now = time.time()
    data["demo"] = False
    data["clock"] = datetime.now().astimezone().isoformat()
    data["zone"] = datetime.now().astimezone().strftime("%Z · UTC%z")
    for name in ("local", "main"):
        data.setdefault(name, {})["_status"] = machine_status(data.get(name, {}), now, name == "main")
    for name, ttl in (("indoor", 60), ("outdoor", 360)):
        reading = data.setdefault(name, {})
        if reading.get("_received_at"):
            reading["_status"] = "Snapshot" if now - reading["_received_at"] <= ttl else "Stale" if name == "indoor" else "Cached"
            if name == "indoor":
                reading["observed_at"] = datetime.fromtimestamp(reading.get("timestamp", reading["_received_at"])).strftime("%H:%M")
    data["history"] = history.capture(data, now)
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stream", action="store_true", help="read local/remote every two seconds; other sources once per launch")
    parser.add_argument("--output", type=Path, help="write a private snapshot instead of stdout")
    args = parser.parse_args()
    os.umask(0o077)
    CACHE.mkdir(parents=True, exist_ok=True)
    if hasattr(time, "tzset"):
        time.tzset()
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {name: pool.submit(read, name) for name in commands()}
        data = {name: future.result() for name, future in futures.items()}
    holiday_payload = data["holidays"]
    data["holidays"] = holiday_payload.get("holidays", {})
    data["holiday_status"] = "Cached" if holiday_payload.get("stale") else holiday_payload.get("_status", "No data")
    history = History()
    text = emit(data, history)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n")
        args.output.chmod(0o600)
        print(f"Saved snapshot: {args.output}")
    else:
        print(text, flush=True)
    finished = False

    def stop(*_):
        nonlocal finished
        finished = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    while args.stream and not finished:
        started = time.monotonic()
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = {name: pool.submit(read, name) for name in ("local", "main")}
            for name, future in futures.items():
                value = future.result()
                if value.get("_received_at"):
                    data[name] = value
        print(emit(data, history), flush=True)
        time.sleep(max(0, 2 - (time.monotonic() - started)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
