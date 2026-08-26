#!/usr/bin/env python3
"""Build JMA nowcast tile URLs centered on a configured location."""

from __future__ import annotations

import argparse
import json
import math
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.request import Request, urlopen

from clock_config import DEFAULT_CONFIG, load_clock_config


OBSERVATION_MANIFEST_URL = (
    "https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json"
)
FORECAST_MANIFEST_URL = (
    "https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N2.json"
)
RADAR_TILE_URL = (
    "https://www.jma.go.jp/bosai/jmatile/data/nowc/"
    "{basetime}/none/{validtime}/surf/hrpns/{z}/{x}/{y}.png"
)
EARTH_RADIUS_METERS = 6378137.0
RADAR_ZOOM = 10
DISPLAY_ZOOM = 10
TILE_SIZE = 256
VIEWPORT_WIDTH = 280
VIEWPORT_HEIGHT = 192
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) QuickshellNowcastWidget/1.0"
FRAME_INTERVAL_MINUTES = 10


def web_mercator_position(
    latitude: float, longitude: float, zoom: int
) -> tuple[float, float]:
    latitude = max(-85.05112878, min(85.05112878, latitude))
    scale = 1 << zoom
    x = (longitude + 180.0) / 360.0 * scale
    latitude_radians = math.radians(latitude)
    y = (
        1.0
        - math.asinh(math.tan(latitude_radians)) / math.pi
    ) / 2.0 * scale
    return x, y


def intersecting_tile_range(
    position: float, viewport_size: float
) -> tuple[int, int]:
    center = position * TILE_SIZE
    half_viewport = viewport_size / 2
    first = math.floor((center - half_viewport) / TILE_SIZE)
    last = math.floor(
        math.nextafter(center + half_viewport, -math.inf) / TILE_SIZE
    )
    return first, last


def usable_frames(manifest: Any, label: str) -> list[dict[str, Any]]:
    if not isinstance(manifest, list) or not manifest:
        raise ValueError(f"{label} manifest has no nowcast frames")

    frames = [
        frame
        for frame in manifest
        if isinstance(frame, dict)
        and isinstance(frame.get("basetime"), str)
        and isinstance(frame.get("validtime"), str)
        and isinstance(frame.get("elements"), list)
        and "hrpns" in frame.get("elements", [])
    ]
    if not frames:
        raise ValueError(f"{label} manifest has no usable nowcast frame")
    return frames


def parse_frame_time(value: str) -> datetime:
    try:
        return datetime.strptime(value, "%Y%m%d%H%M%S").replace(
            tzinfo=timezone.utc
        )
    except ValueError as error:
        raise ValueError("manifest has an invalid frame time") from error


def parse_manifests(
    observation_manifest: Any,
    forecast_manifest: Any | None,
    *,
    include_animation_frames: bool,
    latitude: float,
    longitude: float,
) -> dict[str, Any]:
    observation_frames = usable_frames(
        observation_manifest, "observation"
    )
    current = max(
        observation_frames,
        key=lambda frame: frame["validtime"],
    )
    current_time = parse_frame_time(current["validtime"])
    past_time = current_time - timedelta(minutes=FRAME_INTERVAL_MINUTES)
    forecast_time = current_time + timedelta(minutes=FRAME_INTERVAL_MINUTES)

    selected_frames: list[tuple[dict[str, Any], int, bool]] = []
    if include_animation_frames:
        past = next(
            (
                frame
                for frame in observation_frames
                if parse_frame_time(frame["validtime"]) == past_time
            ),
            None,
        )
        if past is not None:
            selected_frames.append((past, -FRAME_INTERVAL_MINUTES, False))
    selected_frames.append((current, 0, False))

    if include_animation_frames and forecast_manifest is not None:
        try:
            forecast_frames = usable_frames(forecast_manifest, "forecast")
        except ValueError:
            forecast_frames = []
        forecast = next(
            (
                frame
                for frame in forecast_frames
                if parse_frame_time(frame["validtime"]) == forecast_time
            ),
            None,
        )
        if forecast is not None:
            selected_frames.append(
                (forecast, FRAME_INTERVAL_MINUTES, True)
            )

    radar_scale = 1 << (DISPLAY_ZOOM - RADAR_ZOOM)
    radar_x, radar_y = web_mercator_position(latitude, longitude, RADAR_ZOOM)
    radar_origin_x, radar_last_x = intersecting_tile_range(
        radar_x, VIEWPORT_WIDTH / radar_scale
    )
    radar_origin_y, radar_last_y = intersecting_tile_range(
        radar_y, VIEWPORT_HEIGHT / radar_scale
    )
    frames = []
    for frame, offset_minutes, is_forecast in selected_frames:
        radar_tiles = []
        for radar_tile_y in range(radar_origin_y, radar_last_y + 1):
            for radar_tile_x in range(radar_origin_x, radar_last_x + 1):
                radar_tiles.append(
                    {
                        "column": radar_tile_x - radar_origin_x,
                        "row": radar_tile_y - radar_origin_y,
                        "url": RADAR_TILE_URL.format(
                            basetime=frame["basetime"],
                            validtime=frame["validtime"],
                            z=RADAR_ZOOM,
                            x=radar_tile_x,
                            y=radar_tile_y,
                        ),
                    }
                )
        frames.append(
            {
                "frame_time": int(
                    parse_frame_time(frame["validtime"]).timestamp()
                ),
                "offset_minutes": offset_minutes,
                "forecast": is_forecast,
                "radar_tiles": radar_tiles,
            }
        )

    return {
        "reference_time": int(current_time.timestamp()),
        "radar_scale": radar_scale,
        "tile_size": TILE_SIZE,
        "grid_columns": radar_last_x - radar_origin_x + 1,
        "grid_rows": radar_last_y - radar_origin_y + 1,
        "meters_per_pixel": (
            math.cos(math.radians(latitude))
            * 2
            * math.pi
            * EARTH_RADIUS_METERS
            / (TILE_SIZE * (1 << DISPLAY_ZOOM))
        ),
        "radar_center_pixel_x": (radar_x - radar_origin_x) * TILE_SIZE,
        "radar_center_pixel_y": (radar_y - radar_origin_y) * TILE_SIZE,
        "frames": frames,
    }


def download_manifest(url: str, timeout: float) -> Any:
    request = Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    with urlopen(request, timeout=timeout) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument(
        "--file",
        type=Path,
        help="parse a saved JMA nowcast manifest instead of downloading",
    )
    parser.add_argument(
        "--forecast-file",
        type=Path,
        help="parse a saved JMA forecast manifest instead of downloading",
    )
    parser.add_argument(
        "--animation-frames",
        action="store_true",
        help="include the 10-minute past and forecast frames",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=15,
        help="download timeout in seconds (default: 15)",
    )
    parser.add_argument("--pretty", action="store_true", help="indent JSON output")
    args = parser.parse_args()

    try:
        config = load_clock_config(args.config)
        observation_manifest = (
            json.loads(args.file.read_text(encoding="utf-8"))
            if args.file is not None
            else download_manifest(OBSERVATION_MANIFEST_URL, args.timeout)
        )
        include_animation_frames = (
            args.animation_frames or args.forecast_file is not None
        )
        forecast_manifest = None
        if include_animation_frames and args.forecast_file is not None:
            forecast_manifest = json.loads(
                args.forecast_file.read_text(encoding="utf-8")
            )
        elif include_animation_frames and args.file is None:
            try:
                forecast_manifest = download_manifest(
                    FORECAST_MANIFEST_URL, args.timeout
                )
            except (OSError, ValueError, json.JSONDecodeError) as error:
                print(
                    f"JMA nowcast forecast unavailable: {error}",
                    file=sys.stderr,
                )
        radar = parse_manifests(
            observation_manifest,
            forecast_manifest,
            include_animation_frames=include_animation_frames,
            latitude=config.latitude,
            longitude=config.longitude,
        )
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"JMA nowcast fetch failed: {error}", file=sys.stderr)
        return 1

    print(
        json.dumps(
            radar,
            ensure_ascii=False,
            indent=2 if args.pretty else None,
            separators=None if args.pretty else (",", ":"),
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
