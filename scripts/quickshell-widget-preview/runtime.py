#!/usr/bin/env python3
"""Continuous desktop data using the existing collectors and metric contracts."""

import argparse
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import sys
import tempfile
import time

from collect import CONFIG, WIDGETS, History, commands, finite, machine_status

CACHE = Path(os.environ.get("WIDGET_RUNTIME_CACHE", str(Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "quickshell-widgets")))
sys.path.insert(0, str(WIDGETS / "clock/scripts"))
from jma_nowcast import decode_png_alpha, download_radar_tile  # noqa: E402


def parse(name, line):
    def invalid(value):
        raise ValueError(f"Non-finite JSON number: {value}")
    value = json.loads(line, parse_constant=invalid)
    if not isinstance(value, dict):
        raise ValueError("Expected object")
    if name in ("local", "main"):
        if (value.get("schema_version") != 2 or not isinstance(value.get("gpus"), list)
                or any(not isinstance(value.get(k), dict) for k in ("cpu", "memory"))):
            raise ValueError("Invalid machine schema")
    if name == "indoor" and any(not finite(value.get(k)) for k in ("temperature", "humidity", "timestamp")):
        raise ValueError("Invalid indoor reading")
    if name == "outdoor" and (any(not finite(value.get(k)) for k in ("temperature", "humidity"))
                              or any(not isinstance(value.get(k), str) for k in ("condition", "observed_at"))):
        raise ValueError("Invalid weather observation")
    if name == "holidays" and not isinstance(value.get("holidays"), dict):
        raise ValueError("Invalid holidays")
    value.pop("address", None)
    value["_received_at"] = time.time()
    return value


def continuous_commands(automation=False):
    scripts = WIDGETS / "performance/scripts"
    local = [str(scripts / "system_metrics.py"), "--interval", "2", "--machine-config", str(CONFIG / "performance/machine.json")]
    remote = [str(scripts / "remote_metrics.py"), "--interval", "2", "--config", str(CONFIG / "performance/remote.json")]
    if automation:
        remote += ["--automation", "--automation-settings", str(CONFIG / "performance/automation.json"),
                   "--machine-config", str(CONFIG / "performance/machine.json")]
    return {"local": local, "main": remote,
            "indoor": [str(WIDGETS / "clock/scripts/switchbot_meter.py"), "--config", str(CONFIG / "clock/local.json")]}


def radar_next(now, cycle, after, current, enrich):
    """Original five-minute cycle: +50s, +110s retry, +170s forecast enrichment."""
    offsets = (170,) if current and enrich else (50, 110, 170)
    if not current or enrich:
        for offset in offsets:
            if offset > after and cycle + offset > now:
                return cycle + offset
    boundary = int(now // 300) * 300 + 50
    return boundary if boundary > now else boundary + 300


def cache_radar(reading, directory, download=download_radar_tile):
    """Publish a complete, verified tile set; keep the previous set until handoff."""
    frames = reading.get("frames", [])
    if (not finite(reading.get("reference_time")) or not frames
            or not any(f.get("offset_minutes") == 0 for f in frames)):
        raise ValueError("Radar has no current frame")
    urls = sorted({t["url"] for f in frames for t in f.get("radar_tiles", [])})
    if not urls or len(urls) > 128:
        raise ValueError("Invalid radar tile count")
    digest = hashlib.sha256(json.dumps(urls).encode()).hexdigest()[:24]
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / ("set-" + digest)
    names = {url: hashlib.sha256(url.encode()).hexdigest() + ".png" for url in urls}
    if not target.exists():
        with tempfile.TemporaryDirectory(prefix="pending-", dir=directory) as temporary:
            pending = Path(temporary)
            def fetch(url):
                payload = download(url, 8)
                width, height, _ = decode_png_alpha(payload)
                if width != reading.get("tile_size") or height != reading.get("tile_size"):
                    raise ValueError("Unexpected radar tile dimensions")
                (pending / names[url]).write_bytes(payload)
            with ThreadPoolExecutor(max_workers=4) as pool:
                list(pool.map(fetch, urls))
            # The final directory is immutable. QML loads verified local images
            # synchronously and cannot display a partially downloaded frame set.
            pending.rename(target)
    target.touch()
    result = dict(reading)
    result["frames"] = [dict(f, radar_tiles=[dict(t, url=(target / names[t["url"]]).as_uri())
                                           for t in f["radar_tiles"]]) for f in frames]
    sets = sorted(directory.glob("set-*"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in sets[2:]:
        if old.is_dir() and len(old.name) == 28 and all(c in "0123456789abcdef" for c in old.name[4:]):
            shutil.rmtree(old)
    return result


class Runtime:
    def __init__(self, automation=False):
        self.automation = automation
        self.data = {}
        self.history = History()
        self.last_sensor_commit = 0
        self.sensor_pending = None
        self.sensor_seen = 0
        self.radar_nearby = False

    def receive(self, name, value, now):
        if name == "indoor":
            self.sensor_seen = value["timestamp"]
            if now - self.last_sensor_commit < 30 and "indoor" in self.data:
                self.sensor_pending = value
                return
            self.last_sensor_commit = now
            self.sensor_pending = None
        self.data[name] = value

    def snapshot(self, now):
        if self.sensor_pending and now - self.last_sensor_commit >= 30:
            self.receive("indoor", self.sensor_pending, now)
        data = dict(self.data)
        data.update(demo=False, clock=datetime.now().astimezone().isoformat(),
                    zone=datetime.now().astimezone().strftime("%Z · UTC%z"))
        for name in ("local", "main"):
            data[name] = dict(data.get(name, {}))
            data[name]["_status"] = machine_status(data[name], now, name == "main")
        indoor = dict(data.get("indoor", {}))
        indoor["_status"] = "Live" if self.sensor_seen and now - self.sensor_seen <= 60 else "Stale" if indoor else "No data"
        if indoor.get("timestamp"):
            indoor["observed_at"] = datetime.fromtimestamp(indoor["timestamp"]).strftime("%H:%M")
        data["indoor"] = indoor
        outdoor = dict(data.get("outdoor", {}))
        outdoor["_status"] = ("Live" if now - outdoor.get("_received_at", 0) <= 360 and not outdoor.get("_failed")
                              else "Cached" if outdoor.get("_received_at") else "Error" if outdoor.get("_failed") else "Fetching")
        data["outdoor"] = outdoor
        holidays = data.get("holidays", {})
        data["holidays"] = holidays.get("holidays", {})
        data["holiday_status"] = "Cached" if holidays.get("stale") else "Live" if data["holidays"] else "No data"
        data["history"] = self.history.capture(data, now)
        return data

    async def streaming(self, name, args):
        while True:
            process = None
            try:
                process = await asyncio.create_subprocess_exec(sys.executable, "-B", *args,
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
                async for line in process.stdout:
                    try:
                        self.receive(name, parse(name, line), time.time())
                    except (ValueError, TypeError):
                        print(f"{name}: rejected invalid reading", file=sys.stderr)
                await process.wait()
            finally:
                if process and process.returncode is None:
                    process.terminate()
                    try:
                        await asyncio.wait_for(process.wait(), 3)
                    except asyncio.TimeoutError:
                        process.kill()
                        await process.wait()
            await asyncio.sleep(5)

    async def once(self, name, args=None):
        process = await asyncio.create_subprocess_exec(sys.executable, "-B", *(args or commands()[name]),
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        try:
            stdout, _ = await asyncio.wait_for(process.communicate(), 25)
            if process.returncode:
                raise ValueError("collector failed")
            return parse(name, stdout)
        finally:
            if process.returncode is None:
                process.kill()
                await process.wait()

    async def periodic(self, name, interval):
        while True:
            try:
                args = commands()[name]
                if name == "holidays":
                    args[args.index("--cache") + 1] = str(CACHE / "holidays.json")
                self.data[name] = await self.once(name, args)
            except (OSError, ValueError, asyncio.TimeoutError):
                self.data.setdefault(name, {})["_failed"] = True
                print(f"{name}: refresh failed; retaining last reading", file=sys.stderr)
            # Weather stays aligned to the existing two-minute boundaries.
            delay = interval - time.time() % interval if name == "outdoor" else interval
            await asyncio.sleep(max(1, delay))

    async def radar(self):
        while True:
            now = time.time()
            cycle = int(now // 300) * 300
            after = max((v for v in (50, 110, 170) if cycle + v <= now), default=-1)
            current = enrich = False
            try:
                args = commands()["radar"]
                if not self.radar_nearby:
                    args.remove("--animation-frames")
                reading = await self.once("radar", args)
                new_reference = reading.get("reference_time", 0)
                if new_reference >= self.data.get("radar", {}).get("reference_time", 0):
                    cached = await asyncio.to_thread(cache_radar, reading, CACHE / "radar")
                    cached["_status"] = "Live" if new_reference >= cycle else "Cached"
                    self.data["radar"] = cached
                    previous = self.radar_nearby
                    self.radar_nearby = reading.get("nearby_precipitation") is True
                    # A newly wet observation requests animation frames immediately.
                    if self.radar_nearby and not previous:
                        continue
                current = new_reference >= cycle
                enrich = self.radar_nearby and not any(f.get("forecast") for f in reading.get("frames", []))
            except (OSError, ValueError, KeyError, TypeError, asyncio.TimeoutError):
                self.data.setdefault("radar", {})["_status"] = "Cached" if self.data.get("radar", {}).get("frames") else "Unavailable"
                print("radar: refresh failed; retaining the complete previous set", file=sys.stderr)
            await asyncio.sleep(max(1, radar_next(time.time(), cycle, after, current, enrich) - time.time()))

    async def run(self):
        tasks = [asyncio.create_task(self.streaming(name, args)) for name, args in continuous_commands(self.automation).items()]
        tasks += [asyncio.create_task(self.periodic("outdoor", 120)),
                  asyncio.create_task(self.periodic("holidays", 86400)), asyncio.create_task(self.radar())]
        try:
            while True:
                for task in tasks:
                    if task.done():
                        task.result()
                        raise RuntimeError("collector task ended unexpectedly")
                print(json.dumps(self.snapshot(time.time()), ensure_ascii=False, separators=(",", ":"), allow_nan=False), flush=True)
                await asyncio.sleep(2)
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)


async def main(automation):
    runtime = asyncio.create_task(Runtime(automation).run())
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(signum, runtime.cancel)
    try:
        await runtime
    except asyncio.CancelledError:
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--automation", action="store_true", help="preserve existing remote automation settings; never used by validation")
    args = parser.parse_args()
    os.umask(0o077)
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    asyncio.run(main(args.automation))
