#!/usr/bin/env python3
"""Fetch and cache Japan's official national-holiday calendar."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import tempfile
import time
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen


HOLIDAY_URL = "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv"
CACHE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
DEFAULT_CACHE = Path.home() / ".cache/quickshell/clock/jp_holidays.json"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) QuickshellHolidayWidget/1.0"


def parse_date(value: str) -> str:
    for date_format in ("%Y/%m/%d", "%Y-%m-%d"):
        try:
            return datetime.strptime(value.strip(), date_format).date().isoformat()
        except ValueError:
            continue
    raise ValueError(f"invalid holiday date: {value!r}")


def parse_holidays(data: bytes) -> dict[str, str]:
    text: str | None = None
    for encoding in ("utf-8-sig", "cp932"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        raise UnicodeError("holiday CSV encoding is unsupported")

    holidays: dict[str, str] = {}
    for row_number, row in enumerate(csv.reader(StringIO(text)), start=1):
        if not row or all(not value.strip() for value in row):
            continue
        if row_number == 1 and "月日" in row[0]:
            continue
        if len(row) < 2 or not row[1].strip():
            raise ValueError(f"holiday CSV row {row_number} is incomplete")
        holidays[parse_date(row[0])] = row[1].strip()

    if not holidays:
        raise ValueError("holiday CSV contains no entries")
    return dict(sorted(holidays.items()))


def validate_payload(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise ValueError("holiday cache has an unsupported schema")
    raw_holidays = value.get("holidays")
    if not isinstance(raw_holidays, dict) or not raw_holidays:
        raise ValueError("holiday cache contains no entries")

    holidays: dict[str, str] = {}
    for raw_date, raw_name in raw_holidays.items():
        if not isinstance(raw_date, str) or not isinstance(raw_name, str):
            raise ValueError("holiday cache contains an invalid entry")
        holidays[parse_date(raw_date)] = raw_name.strip()

    fetched_at_epoch = value.get("fetched_at_epoch")
    if not isinstance(fetched_at_epoch, (int, float)):
        raise ValueError("holiday cache has no fetch timestamp")

    return {
        "schema_version": 1,
        "source": HOLIDAY_URL,
        "fetched_at": value.get("fetched_at", ""),
        "fetched_at_epoch": fetched_at_epoch,
        "holidays": dict(sorted(holidays.items())),
    }


def read_cache(path: Path) -> dict[str, Any] | None:
    try:
        return validate_payload(json.loads(path.read_text(encoding="utf-8")))
    except FileNotFoundError:
        return None


def write_cache(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as temporary:
            json.dump(payload, temporary, ensure_ascii=False, separators=(",", ":"))
            temporary.write("\n")
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


def download_holidays(timeout: float) -> dict[str, str]:
    request = Request(
        HOLIDAY_URL,
        headers={"User-Agent": USER_AGENT, "Accept": "text/csv"},
    )
    with urlopen(request, timeout=timeout) as response:
        return parse_holidays(response.read())


def refreshed_payload(holidays: dict[str, str]) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    return {
        "schema_version": 1,
        "source": HOLIDAY_URL,
        "fetched_at": now.isoformat(timespec="seconds"),
        "fetched_at_epoch": time.time(),
        "holidays": holidays,
    }


def emit(payload: dict[str, Any], stale: bool = False) -> None:
    first_relevant_date = f"{datetime.now().year:04d}-01-01"
    holidays = {
        key: value
        for key, value in payload["holidays"].items()
        if key >= first_relevant_date
    }
    output = {"holidays": holidays, "stale": stale}
    print(json.dumps(output, ensure_ascii=False, separators=(",", ":")))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--max-age", type=float, default=CACHE_MAX_AGE_SECONDS)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    if args.timeout <= 0 or args.max_age < 0:
        parser.error("timeout must be positive and max-age cannot be negative")

    try:
        cached = read_cache(args.cache)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"holiday cache ignored: {error}", file=sys.stderr)
        cached = None

    if (
        cached is not None
        and not args.refresh
        and time.time() - cached["fetched_at_epoch"] < args.max_age
    ):
        emit(cached)
        return 0

    try:
        payload = refreshed_payload(download_holidays(args.timeout))
        write_cache(args.cache, payload)
        emit(payload)
    except (OSError, UnicodeError, csv.Error, ValueError) as error:
        print(f"holiday update failed: {error}", file=sys.stderr)
        if cached is not None:
            emit(cached, stale=True)
        else:
            emit(
                {
                    "schema_version": 1,
                    "source": HOLIDAY_URL,
                    "fetched_at": "",
                    "fetched_at_epoch": 0,
                    "holidays": {},
                },
                stale=True,
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
