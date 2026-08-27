#!/usr/bin/env python3
"""Build JMA nowcast tile URLs centered on a configured location."""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
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
FRAME_INTERVAL_MINUTES = 5
RAIN_DETECTION_RADIUS_METERS = 5_000.0
RAIN_DETECTION_MIN_AREA_SQUARE_METERS = 250_000.0
MAX_RADAR_TILE_BYTES = 2 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


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


def download_radar_tile(url: str, timeout: float) -> bytes:
    request = Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "image/png"},
    )
    with urlopen(request, timeout=timeout) as response:
        data = response.read(MAX_RADAR_TILE_BYTES + 1)
    if len(data) > MAX_RADAR_TILE_BYTES:
        raise ValueError("radar tile is unexpectedly large")
    return data


def decode_png_alpha(data: bytes) -> tuple[int, int, list[bytes]]:
    """Decode alpha values from a supported non-interlaced radar PNG."""
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("radar tile is not a PNG")

    header: tuple[int, int, int, int, int, int, int] | None = None
    palette_entries = 0
    transparency: bytes | None = None
    image_data: list[bytes] = []
    offset = len(PNG_SIGNATURE)
    found_end = False

    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            raise ValueError("radar PNG has a truncated chunk")
        chunk_type = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset = chunk_end

        if chunk_type == b"IHDR":
            if length != 13:
                raise ValueError("radar PNG has an invalid header")
            header = struct.unpack(">IIBBBBB", payload)
        elif chunk_type == b"PLTE":
            if length == 0 or length % 3 != 0:
                raise ValueError("radar PNG has an invalid palette")
            palette_entries = length // 3
        elif chunk_type == b"tRNS":
            transparency = payload
        elif chunk_type == b"IDAT":
            image_data.append(payload)
        elif chunk_type == b"IEND":
            found_end = True
            break

    if header is None or not found_end or not image_data:
        raise ValueError("radar PNG is incomplete")

    width, height, bit_depth, color_type, compression, filtering, interlace = (
        header
    )
    if width < 1 or height < 1:
        raise ValueError("radar PNG has invalid dimensions")
    indexed = color_type == 3 and bit_depth in (1, 2, 4, 8)
    rgba = color_type == 6 and bit_depth == 8
    if (
        not (indexed or rgba)
        or compression != 0
        or filtering != 0
        or interlace != 0
    ):
        raise ValueError("radar PNG uses an unsupported format")
    if indexed and (palette_entries < 1 or transparency is None):
        raise ValueError("radar PNG has no transparent indexed palette")

    bytes_per_pixel = 1 if indexed else 4
    row_bytes = (
        (width * bit_depth + 7) // 8
        if indexed
        else width * bytes_per_pixel
    )
    try:
        raw = zlib.decompress(b"".join(image_data))
    except zlib.error as error:
        raise ValueError("radar PNG image data is invalid") from error
    if len(raw) != height * (row_bytes + 1):
        raise ValueError("radar PNG image data has an unexpected size")

    rows: list[bytes] = []
    previous = bytearray(row_bytes)
    raw_offset = 0
    pixels_per_byte = 8 // bit_depth if indexed else 0
    index_mask = (1 << bit_depth) - 1 if indexed else 0

    for _ in range(height):
        filter_type = raw[raw_offset]
        raw_offset += 1
        scanline = raw[raw_offset : raw_offset + row_bytes]
        raw_offset += row_bytes
        decoded = bytearray(row_bytes)

        for index, value in enumerate(scanline):
            left = (
                decoded[index - bytes_per_pixel]
                if index >= bytes_per_pixel
                else 0
            )
            above = previous[index]
            upper_left = (
                previous[index - bytes_per_pixel]
                if index >= bytes_per_pixel
                else 0
            )
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                estimate = left + above - upper_left
                left_distance = abs(estimate - left)
                above_distance = abs(estimate - above)
                upper_left_distance = abs(estimate - upper_left)
                if left_distance <= above_distance and (
                    left_distance <= upper_left_distance
                ):
                    predictor = left
                elif above_distance <= upper_left_distance:
                    predictor = above
                else:
                    predictor = upper_left
            else:
                raise ValueError("radar PNG uses an invalid row filter")
            decoded[index] = (value + predictor) & 0xFF

        if indexed:
            alpha = bytearray(width)
            for pixel in range(width):
                packed = decoded[pixel // pixels_per_byte]
                shift = 8 - bit_depth * (pixel % pixels_per_byte + 1)
                palette_index = (packed >> shift) & index_mask
                if palette_index >= palette_entries:
                    raise ValueError(
                        "radar PNG references an invalid palette entry"
                    )
                alpha[pixel] = (
                    transparency[palette_index]
                    if palette_index < len(transparency)
                    else 255
                )
            rows.append(bytes(alpha))
        else:
            rows.append(bytes(decoded[3::4]))
        previous = decoded

    return width, height, rows


def frame_has_nearby_precipitation(
    frame: dict[str, Any],
    *,
    center_pixel_x: float,
    center_pixel_y: float,
    tile_size: int,
    source_pixel_meters: float,
    timeout: float,
    tile_loader: Callable[[str, float], bytes] = download_radar_tile,
) -> bool:
    radius_pixels = RAIN_DETECTION_RADIUS_METERS / source_pixel_meters
    radius_squared = radius_pixels * radius_pixels
    required_pixels = math.ceil(
        RAIN_DETECTION_MIN_AREA_SQUARE_METERS
        / (source_pixel_meters * source_pixel_meters)
    )
    precipitation_pixels = 0
    intersecting_tiles = 0

    for tile in frame["radar_tiles"]:
        tile_left = tile["column"] * tile_size
        tile_top = tile["row"] * tile_size
        nearest_x = min(
            max(center_pixel_x, tile_left), tile_left + tile_size
        )
        nearest_y = min(
            max(center_pixel_y, tile_top), tile_top + tile_size
        )
        if (
            (nearest_x - center_pixel_x) ** 2
            + (nearest_y - center_pixel_y) ** 2
            > radius_squared
        ):
            continue

        intersecting_tiles += 1
        width, height, alpha_rows = decode_png_alpha(
            tile_loader(tile["url"], timeout)
        )
        if width != tile_size or height != tile_size:
            raise ValueError("radar tile dimensions do not match the manifest")

        for local_y, alpha_row in enumerate(alpha_rows):
            pixel_y = tile_top + local_y + 0.5
            vertical_distance = pixel_y - center_pixel_y
            horizontal_extent_squared = (
                radius_squared - vertical_distance * vertical_distance
            )
            if horizontal_extent_squared < 0:
                continue
            horizontal_extent = math.sqrt(horizontal_extent_squared)
            first_x = max(
                0,
                math.ceil(center_pixel_x - horizontal_extent - tile_left - 0.5),
            )
            last_x = min(
                width - 1,
                math.floor(center_pixel_x + horizontal_extent - tile_left - 0.5),
            )
            if first_x > last_x:
                continue
            precipitation_pixels += sum(
                alpha > 0 for alpha in alpha_row[first_x : last_x + 1]
            )
            if precipitation_pixels >= required_pixels:
                return True

    if intersecting_tiles == 0:
        raise ValueError("radar frame does not cover the detection radius")
    return False


def detect_nearby_precipitation(
    radar: dict[str, Any],
    *,
    timeout: float,
    tile_loader: Callable[[str, float], bytes] = download_radar_tile,
) -> bool | None:
    source_pixel_meters = radar["meters_per_pixel"] * radar["radar_scale"]
    if source_pixel_meters <= 0:
        return None

    current = next(
        (
            frame
            for frame in radar["frames"]
            if frame["offset_minutes"] == 0
        ),
        None,
    )
    if current is None:
        return None

    try:
        return frame_has_nearby_precipitation(
            current,
            center_pixel_x=radar["radar_center_pixel_x"],
            center_pixel_y=radar["radar_center_pixel_y"],
            tile_size=radar["tile_size"],
            source_pixel_meters=source_pixel_meters,
            timeout=timeout,
            tile_loader=tile_loader,
        )
    except (OSError, ValueError) as error:
        print(
            f"JMA nearby precipitation detection unavailable for now: {error}",
            file=sys.stderr,
        )
        return None


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
        help="include the 5-minute past and forecast frames",
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
        animation_requested = (
            args.animation_frames or args.forecast_file is not None
        )
        radar = parse_manifests(
            observation_manifest,
            None,
            include_animation_frames=False,
            latitude=config.latitude,
            longitude=config.longitude,
        )
        nearby_precipitation = (
            None
            if args.file is not None
            else detect_nearby_precipitation(
                radar,
                timeout=args.timeout,
            )
        )
        if animation_requested or nearby_precipitation is True:
            forecast_manifest = None
            if args.forecast_file is not None:
                forecast_manifest = json.loads(
                    args.forecast_file.read_text(encoding="utf-8")
                )
            elif args.file is None:
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
                include_animation_frames=True,
                latitude=config.latitude,
                longitude=config.longitude,
            )
        radar["nearby_precipitation"] = nearby_precipitation
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
