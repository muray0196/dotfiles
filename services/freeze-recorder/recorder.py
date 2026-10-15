#!/usr/bin/env python3
"""Preserve desktop logs and bounded, passive Linux stall diagnostics."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


MIB = 1024 * 1024
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
WORKERS = ("system_metrics.py", "remote_metrics.py", "switchbot_meter.py")
WATCHED = {"qs", "quickshell", "Hyprland", "llama-server", "sshd", "sshd-session"}
MEMORY_KEYS = {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree", "Dirty", "Writeback", "AnonPages", "Slab"}


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def read_text(path, limit=65536):
    try:
        with Path(path).open() as stream:
            return stream.read(limit).strip()
    except (OSError, UnicodeError):
        return None


def parse_stat(text):
    # comm may contain spaces and parentheses; fields after its closing ')' are fixed.
    opening, closing = text.index("("), text.rindex(")")
    fields = text[closing + 2:].split()
    return {
        "pid": int(text[:opening].strip()), "comm": text[opening + 1:closing],
        "state": fields[0], "ppid": int(fields[1]),
        "cpu_ticks": int(fields[11]) + int(fields[12]), "threads": int(fields[17]),
        "start_ticks": int(fields[19]), "vsize_bytes": int(fields[20]),
        "rss_bytes": int(fields[21]) * PAGE_SIZE,
    }


def process_stat(directory):
    try:
        text = read_text(directory / "stat")
        return parse_stat(text) if text else None
    except (ValueError, IndexError):
        return None  # A process may exit during the scan.


def wait_channel(path):
    value = read_text(path)
    return value if value and value != "0" else None


class EventLog:
    def __init__(self, directory, max_bytes=8 * MIB, files=8):
        self.directory, self.max_bytes, self.files = directory, max_bytes, files
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = directory / "events.jsonl"
        # A killed recorder can leave a partial JSON line in this boot's segment.
        if self.path.exists():
            with self.path.open("r+b") as stream:
                data = stream.read()
                if data and not data.endswith(b"\n"):
                    stream.truncate(data.rfind(b"\n") + 1)
                    os.fdatasync(stream.fileno())
        self.stream = self.path.open("ab", buffering=0)

    def sync_directory(self):
        fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def write(self, kind, **payload):
        record = {"time": utc_now(), "monotonic_s": round(time.monotonic(), 3), "event": kind, **payload}
        encoded = (json.dumps(record, separators=(",", ":"), ensure_ascii=True) + "\n").encode()
        if len(encoded) > self.max_bytes:
            raise ValueError("Event exceeds log segment limit")
        if self.stream.tell() + len(encoded) > self.max_bytes:
            self.sync()
            self.stream.close()
            for index in range(self.files - 1, 0, -1):
                source = self.path if index == 1 else self.directory / f"events.jsonl.{index - 1}"
                if source.exists():
                    source.replace(self.directory / f"events.jsonl.{index}")
            self.stream = self.path.open("wb", buffering=0)
            self.sync_directory()
        self.stream.write(encoded)

    def sync(self):
        os.fdatasync(self.stream.fileno())

    def close(self):
        self.sync()
        self.stream.close()


def prune_boots(root, current, keep=4):
    owned = []
    for directory in root.iterdir():
        if directory.is_symlink() or not re.fullmatch(r"boot-[0-9a-f-]{36}", directory.name):
            continue
        marker = read_text(directory / "owner")
        if marker == "freeze-recorder-v1" and directory != current:
            owned.append(directory)
    for directory in sorted(owned, key=lambda p: p.stat().st_mtime, reverse=True)[keep - 1:]:
        shutil.rmtree(directory)


class RuntimeLogs:
    def __init__(self, runtime, sink):
        self.runtime, self.sink = runtime, sink
        self.positions = {}

    def poll(self):
        paths = list(self.runtime.glob("quickshell/by-id/*/log.log"))
        paths += list(self.runtime.glob("hypr/*/hyprland.log"))
        present = set()
        for path in sorted(paths):
            key = str(path.relative_to(self.runtime))
            present.add(key)
            try:
                with path.open("rb") as stream:
                    stat = os.fstat(stream.fileno())
                    identity = (stat.st_dev, stat.st_ino)
                    old_identity, offset = self.positions.get(key, (None, 0))
                    if identity != old_identity or stat.st_size < offset:
                        offset = 0
                    # Preserve the newest diagnostics if a source floods its log.
                    if stat.st_size - offset > 256 * 1024:
                        skipped = stat.st_size - offset - 256 * 1024
                        offset += skipped
                        self.sink.write("log_gap", source=key, skipped_bytes=skipped)
                    stream.seek(offset)
                    chunk = stream.read(256 * 1024)
                    if chunk:
                        self.sink.write("desktop_log", source=key, offset=offset,
                                        text=chunk.decode("utf-8", errors="replace"))
                    self.positions[key] = (identity, offset + len(chunk))
            except OSError as error:
                self.sink.write("log_unavailable", source=key, error=str(error))
        for key in self.positions.keys() - present:
            self.sink.write("log_disappeared", source=key)
            del self.positions[key]


class HyprlandRollingLogs:
    """Supplement buffered files with the compositor's small rolling log."""

    def __init__(self, runtime, sink):
        self.runtime, self.sink = runtime, sink
        self.previous = {}
        self.command = shutil.which("hyprctl")

    def poll(self):
        if not self.command:
            return
        for lock in self.runtime.glob("hypr/*/hyprland.lock"):
            instance = lock.parent.name
            try:
                result = subprocess.run([self.command, "-i", instance, "rollinglog"],
                                        capture_output=True, text=True, timeout=1)
                snapshot = (result.returncode, result.stdout, result.stderr)
            except subprocess.TimeoutExpired:
                snapshot = ("timeout", "", "Hyprland log query exceeded 1 second")
            except OSError as error:
                snapshot = ("unavailable", "", str(error))
            if snapshot != self.previous.get(instance):
                self.sink.write("hyprland_rolling_log", instance=instance,
                                status=snapshot[0], text=snapshot[1], error=snapshot[2])
                self.previous[instance] = snapshot


class Sampler:
    def __init__(self, proc=Path("/proc")):
        self.proc = proc
        self.previous = {}
        self.watched = {}
        self.tick = 0

    def sample(self):
        started = time.monotonic()
        processes = []
        watched = {}
        for directory in self.proc.iterdir():
            if not directory.name.isdigit():
                continue
            item = process_stat(directory)
            if item is None:
                continue
            key = (item["pid"], item["start_ticks"])
            item["cpu_delta_ticks"] = max(0, item["cpu_ticks"] - self.previous.get(key, item["cpu_ticks"]))
            command = item["comm"]
            label = command if command in WATCHED or command.startswith("waywallen") else None
            if label == "qs" or command.startswith("python"):
                args = (read_text(directory / "cmdline", 8192) or "").split("\0")
                for worker in WORKERS:
                    if any(arg.endswith("/" + worker) for arg in args):
                        label = worker
                if label == "qs" and "-c" in args:
                    index = args.index("-c") + 1
                    if index < len(args) and args[index] in {"clock", "performance"}:
                        label += ":" + args[index]
            if label:
                item["label"] = label
                watched[key] = label
            processes.append(item)

        self.previous = {(p["pid"], p["start_ticks"]): p["cpu_ticks"] for p in processes}
        selected = {p["pid"] for p in processes if "label" in p or p["state"] in {"D", "Z"}}
        for field in ("rss_bytes", "cpu_delta_ticks"):
            selected.update(p["pid"] for p in sorted(processes, key=lambda p: p[field], reverse=True)[:10])
        details = []
        for item in processes:
            if item["pid"] not in selected:
                continue
            directory = self.proc / str(item["pid"])
            item["wchan"] = wait_channel(directory / "wchan")
            if "label" in item:
                item["cgroup"] = read_text(directory / "cgroup", 4096)
                states, blocked = Counter(), []
                try:
                    for task in (directory / "task").iterdir():
                        thread = process_stat(task)
                        if thread:
                            states[thread["state"]] += 1
                            if thread["state"] == "D" and len(blocked) < 32:
                                blocked.append({"tid": thread["pid"], "comm": thread["comm"],
                                                "wchan": wait_channel(task / "wchan")})
                except OSError:
                    pass
                item["thread_states"], item["blocked_threads"] = dict(states), blocked
            details.append(item)

        changes = [{"kind": "appeared", "pid": key[0], "start_ticks": key[1], "label": watched[key]}
                   for key in watched.keys() - self.watched.keys()]
        changes += [{"kind": "disappeared", "pid": key[0], "start_ticks": key[1], "label": self.watched[key]}
                    for key in self.watched.keys() - watched.keys()]
        self.watched = watched
        memory = {}
        for line in (read_text(self.proc / "meminfo") or "").splitlines():
            key, _, value = line.partition(":")
            if key in MEMORY_KEYS:
                memory[key + "_kib"] = int(value.split()[0])
        vmstat = {}
        for line in (read_text(self.proc / "vmstat") or "").splitlines():
            key, value = line.split()
            if key in {"pgmajfault", "pswpin", "pswpout", "oom_kill"} or key.startswith(("allocstall", "pgscan", "pgsteal")):
                vmstat[key] = int(value)
        self.tick += 1
        return {
            "sample": self.tick, "uptime": read_text(self.proc / "uptime"),
            "loadavg": read_text(self.proc / "loadavg"), "memory": memory, "vmstat": vmstat,
            "pressure": {kind: read_text(self.proc / "pressure" / kind) for kind in ("cpu", "memory", "io")},
            "network_counters": read_text(self.proc / "net/dev"),
            "process_states": dict(Counter(p["state"] for p in processes)),
            "processes": sorted(details, key=lambda p: p["pid"]), "process_changes": changes,
            "scan_ms": round((time.monotonic() - started) * 1000, 2),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, default=Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "freeze-diagnostics/recorder")
    parser.add_argument("--interval", type=float, default=5, help="Sample and sync interval in seconds (default: 5)")
    parser.add_argument("--samples", type=int, default=0, help="Exit after N samples; zero runs continuously")
    args = parser.parse_args()
    if args.interval < 1 or args.samples < 0:
        parser.error("interval must be at least 1 second and samples must be nonnegative")
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = (args.state_dir / "recorder.lock").open("a")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    boot_id = read_text("/proc/sys/kernel/random/boot_id")
    if not boot_id or not re.fullmatch(r"[0-9a-f-]{36}", boot_id):
        raise RuntimeError("Cannot determine Linux boot ID")
    directory = args.state_dir / f"boot-{boot_id}"
    directory.mkdir(exist_ok=True, mode=0o700)
    (directory / "owner").write_text("freeze-recorder-v1\n")
    os.utime(directory, None)
    prune_boots(args.state_dir, directory)
    sink = EventLog(directory)
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    logs, sampler = RuntimeLogs(runtime, sink), Sampler()
    rolling = HyprlandRollingLogs(runtime, sink)
    stopping = False

    def stop(signum, frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    sink.write("recorder_started", boot_id=boot_id, kernel=os.uname().release,
               interval_s=args.interval, clock_ticks_per_second=os.sysconf("SC_CLK_TCK"),
               wait_channel_note="null means unavailable or no wait channel; root-owned tasks may be unreadable")
    sink.sync_directory()
    print(f"Recording every {args.interval:g}s to {directory}; retaining 4 boots, 64 MiB per boot", flush=True)
    try:
        while not stopping:
            started = time.monotonic()
            logs.poll()
            rolling.poll()
            sink.write("sample", **sampler.sample())
            sink.sync()
            if args.samples and sampler.tick >= args.samples:
                break
            delay = args.interval - (time.monotonic() - started)
            if delay > 0 and not stopping:
                time.sleep(delay)
        logs.poll()
        sink.write("recorder_stopped")
    finally:
        sink.close()
        lock.close()


if __name__ == "__main__":
    main()
