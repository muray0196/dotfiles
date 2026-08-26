#!/usr/bin/env python3
"""Measure when new JMA nowcast observation manifests become visible."""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

from jma_nowcast import (
    OBSERVATION_MANIFEST_URL,
    parse_frame_time,
    usable_frames,
)


DEFAULT_INTERVAL_SECONDS = 5.0
DEFAULT_DURATION_SECONDS = 3 * 60 * 60
DEFAULT_TIMEOUT_SECONDS = 10.0
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "QuickshellNowcastTimingProbe/1.0"
)


def utc_timestamp(epoch: float) -> str:
    return (
        datetime.fromtimestamp(epoch, timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def parsed_header_epoch(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return parsedate_to_datetime(value).timestamp()
    except (TypeError, ValueError, OverflowError):
        return None


def integer_header(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except ValueError:
        return None


def latest_observation(manifest: Any) -> dict[str, Any]:
    frames = usable_frames(manifest, "observation")
    latest = max(frames, key=lambda frame: frame["validtime"])
    frame_time = parse_frame_time(latest["validtime"])
    return {
        "basetime": latest["basetime"],
        "validtime": latest["validtime"],
        "frame_epoch": int(frame_time.timestamp()),
    }


def append_record(stream: Any, record: dict[str, Any]) -> None:
    stream.write(
        json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    stream.flush()


def fetch_sample(timeout: float) -> dict[str, Any]:
    started_epoch = time.time()
    started_monotonic = time.monotonic()
    request = Request(
        OBSERVATION_MANIFEST_URL,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )

    with urlopen(request, timeout=timeout) as response:
        body = response.read()
        received_epoch = time.time()
        latency_ms = round(
            (time.monotonic() - started_monotonic) * 1000,
            3,
        )
        manifest = json.loads(body)
        latest = latest_observation(manifest)
        http_date = response.headers.get("Date")
        last_modified = response.headers.get("Last-Modified")
        age_seconds = integer_header(response.headers.get("Age"))
        http_date_epoch = parsed_header_epoch(http_date)
        last_modified_epoch = parsed_header_epoch(last_modified)
        frame_epoch = latest["frame_epoch"]

        return {
            "kind": "sample",
            "request_started_at": utc_timestamp(started_epoch),
            "response_received_at": utc_timestamp(received_epoch),
            "latency_ms": latency_ms,
            "http_status": response.status,
            "response_bytes": len(body),
            "http_date": http_date,
            "last_modified": last_modified,
            "age_seconds": age_seconds,
            "etag": response.headers.get("ETag"),
            "cache_control": response.headers.get("Cache-Control"),
            "latest_basetime": latest["basetime"],
            "latest_validtime": latest["validtime"],
            "latest_frame_epoch": frame_epoch,
            "local_frame_age_seconds": round(received_epoch - frame_epoch, 3),
            "http_date_frame_age_seconds": (
                round(http_date_epoch - frame_epoch, 3)
                if http_date_epoch is not None
                else None
            ),
            "last_modified_delay_seconds": (
                round(last_modified_epoch - frame_epoch, 3)
                if last_modified_epoch is not None
                else None
            ),
        }


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Poll the JMA observation manifest and write timing samples as JSONL."
        )
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL_SECONDS,
        help="seconds between request starts (default: 5)",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=DEFAULT_DURATION_SECONDS,
        help="total run time in seconds (default: 10800)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help="per-request timeout in seconds (default: 10)",
    )
    args = parser.parse_args()
    if args.interval <= 0:
        parser.error("--interval must be greater than zero")
    if args.duration <= 0:
        parser.error("--duration must be greater than zero")
    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")
    return args


def main() -> int:
    args = parse_arguments()
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)

    stop_requested = False

    def request_stop(signum: int, frame: Any) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    started_epoch = time.time()
    started_monotonic = time.monotonic()
    deadline = started_monotonic + args.duration
    next_request = started_monotonic
    sample_count = 0
    success_count = 0
    error_count = 0
    advance_count = 0
    regression_count = 0
    latest_frame_epoch: int | None = None
    previous_etag: str | None = None

    with args.output.open("a", encoding="utf-8", buffering=1) as stream:
        os.chmod(args.output, 0o600)
        append_record(
            stream,
            {
                "kind": "run_start",
                "started_at": utc_timestamp(started_epoch),
                "interval_seconds": args.interval,
                "duration_seconds": args.duration,
                "timeout_seconds": args.timeout,
                "url": OBSERVATION_MANIFEST_URL,
            },
        )
        print(
            f"JMA timing probe started: output={args.output} "
            f"interval={args.interval:g}s duration={args.duration:g}s",
            flush=True,
        )

        while not stop_requested and time.monotonic() < deadline:
            wait_seconds = min(next_request, deadline) - time.monotonic()
            if wait_seconds > 0:
                time.sleep(wait_seconds)
            if stop_requested or time.monotonic() >= deadline:
                break

            sample_count += 1
            try:
                sample = fetch_sample(args.timeout)
                success_count += 1
                frame_epoch = sample["latest_frame_epoch"]
                etag = sample["etag"]
                sample["sample_number"] = sample_count
                sample["etag_changed"] = (
                    previous_etag is not None and etag != previous_etag
                )

                if latest_frame_epoch is None:
                    sample["frame_event"] = "baseline"
                    latest_frame_epoch = frame_epoch
                elif frame_epoch > latest_frame_epoch:
                    sample["frame_event"] = "advanced"
                    sample["previous_frame_epoch"] = latest_frame_epoch
                    latest_frame_epoch = frame_epoch
                    advance_count += 1
                elif frame_epoch < latest_frame_epoch:
                    sample["frame_event"] = "regressed"
                    sample["newest_seen_frame_epoch"] = latest_frame_epoch
                    regression_count += 1
                else:
                    sample["frame_event"] = "unchanged"

                previous_etag = etag
                append_record(stream, sample)
                if sample["frame_event"] != "unchanged":
                    print(
                        "frame_event=" + sample["frame_event"]
                        + " latest_validtime=" + sample["latest_validtime"]
                        + " received_at=" + sample["response_received_at"],
                        flush=True,
                    )
            except Exception as error:
                error_count += 1
                append_record(
                    stream,
                    {
                        "kind": "sample_error",
                        "sample_number": sample_count,
                        "observed_at": utc_timestamp(time.time()),
                        "error_type": type(error).__name__,
                        "error": str(error),
                    },
                )
                print(
                    f"sample_error={type(error).__name__}: {error}",
                    file=sys.stderr,
                    flush=True,
                )

            next_request += args.interval
            if next_request < time.monotonic():
                next_request = time.monotonic()

        ended_epoch = time.time()
        append_record(
            stream,
            {
                "kind": "run_end",
                "ended_at": utc_timestamp(ended_epoch),
                "elapsed_seconds": round(
                    time.monotonic() - started_monotonic,
                    3,
                ),
                "stop_requested": stop_requested,
                "sample_count": sample_count,
                "success_count": success_count,
                "error_count": error_count,
                "advance_count": advance_count,
                "regression_count": regression_count,
            },
        )

    print(
        f"JMA timing probe stopped: samples={sample_count} "
        f"successes={success_count} errors={error_count} "
        f"advances={advance_count} regressions={regression_count}",
        flush=True,
    )
    return 0 if success_count > 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
