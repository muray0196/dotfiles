#!/usr/bin/env python3

from __future__ import annotations

import binascii
import io
import json
import struct
import sys
import unittest
import zlib
from contextlib import redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SCRIPT_DIR = (
    Path(__file__).resolve().parents[1]
    / "modules/quickshell/.config/quickshell/clock/scripts"
)
sys.path.insert(0, str(SCRIPT_DIR))

import jma_nowcast  # noqa: E402


def png_chunk(chunk_type: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + chunk_type
        + payload
        + struct.pack(">I", checksum)
    )


def indexed_png(rows: list[list[int]]) -> bytes:
    height = len(rows)
    width = len(rows[0])
    packed_rows = []
    for row in rows:
        packed = bytearray()
        for index in range(0, width, 2):
            high = row[index]
            low = row[index + 1] if index + 1 < width else 0
            packed.append((high << 4) | low)
        packed_rows.append(b"\x00" + bytes(packed))

    header = struct.pack(">IIBBBBB", width, height, 4, 3, 0, 0, 0)
    palette = b"\xff\xff\xff\xff\xff\xff\xa0\xd2\xff"
    transparency = b"\x00\x00\xff"
    return (
        jma_nowcast.PNG_SIGNATURE
        + png_chunk(b"IHDR", header)
        + png_chunk(b"PLTE", palette)
        + png_chunk(b"tRNS", transparency)
        + png_chunk(b"IDAT", zlib.compress(b"".join(packed_rows)))
        + png_chunk(b"IEND", b"")
    )


def rgba_png(alpha_rows: list[list[int]]) -> bytes:
    height = len(alpha_rows)
    width = len(alpha_rows[0])
    raw_rows = []
    for alpha_row in alpha_rows:
        pixels = b"".join(bytes((0, 0, 0, alpha)) for alpha in alpha_row)
        raw_rows.append(b"\x00" + pixels)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        jma_nowcast.PNG_SIGNATURE
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(b"".join(raw_rows)))
        + png_chunk(b"IEND", b"")
    )


def radar_rows(opaque_pixels: set[tuple[int, int]]) -> list[list[int]]:
    rows = [[1] * 256 for _ in range(256)]
    for x, y in opaque_pixels:
        rows[y][x] = 2
    return rows


class PngAlphaTests(unittest.TestCase):
    def test_decodes_transparent_and_opaque_palette_entries(self) -> None:
        png = indexed_png([[0, 1, 2, 1]])

        width, height, alpha_rows = jma_nowcast.decode_png_alpha(png)

        self.assertEqual((width, height), (4, 1))
        self.assertEqual(alpha_rows, [b"\x00\x00\xff\x00"])

    def test_decodes_transparent_rgba_tiles(self) -> None:
        png = rgba_png([[0, 0], [0, 255]])

        width, height, alpha_rows = jma_nowcast.decode_png_alpha(png)

        self.assertEqual((width, height), (2, 2))
        self.assertEqual(alpha_rows, [b"\x00\x00", b"\x00\xff"])


class NearbyPrecipitationTests(unittest.TestCase):
    frame = {
        "radar_tiles": [
            {"column": 0, "row": 0, "url": "tile"},
        ]
    }

    def detect(self, opaque_pixels: set[tuple[int, int]]) -> bool:
        png = indexed_png(radar_rows(opaque_pixels))
        return jma_nowcast.frame_has_nearby_precipitation(
            self.frame,
            center_pixel_x=128,
            center_pixel_y=128,
            tile_size=256,
            source_pixel_meters=100,
            timeout=1,
            tile_loader=lambda _url, _timeout: png,
        )

    def test_requires_quarter_square_kilometer_of_echo(self) -> None:
        cluster = {
            (x, y)
            for y in range(126, 131)
            for x in range(126, 131)
        }

        self.assertTrue(self.detect(cluster))
        self.assertFalse(self.detect(cluster - {(130, 130)}))

    def test_ignores_echo_outside_five_kilometer_radius(self) -> None:
        outside_cluster = {
            (x, y)
            for y in range(126, 131)
            for x in range(198, 203)
        }

        self.assertFalse(self.detect(outside_cluster))

    def test_accepts_transparent_rgba_tile_as_dry(self) -> None:
        png = rgba_png([[0] * 256 for _ in range(256)])

        detected = jma_nowcast.frame_has_nearby_precipitation(
            self.frame,
            center_pixel_x=128,
            center_pixel_y=128,
            tile_size=256,
            source_pixel_meters=100,
            timeout=1,
            tile_loader=lambda _url, _timeout: png,
        )

        self.assertFalse(detected)

    def test_uses_only_current_frame_for_detection(self) -> None:
        dry_png = indexed_png(radar_rows(set()))
        wet_cluster = {
            (x, y)
            for y in range(126, 131)
            for x in range(126, 131)
        }
        wet_png = indexed_png(radar_rows(wet_cluster))
        radar = {
            "meters_per_pixel": 100,
            "radar_scale": 1,
            "radar_center_pixel_x": 128,
            "radar_center_pixel_y": 128,
            "tile_size": 256,
            "frames": [
                {
                    "offset_minutes": 0,
                    "radar_tiles": [
                        {"column": 0, "row": 0, "url": "current"},
                    ],
                },
                {
                    "offset_minutes": 5,
                    "radar_tiles": [
                        {"column": 0, "row": 0, "url": "forecast"},
                    ],
                },
            ],
        }
        loaded_urls = []

        def load(url: str, _timeout: float) -> bytes:
            loaded_urls.append(url)
            return dry_png if url == "current" else wet_png

        detected = jma_nowcast.detect_nearby_precipitation(
            radar,
            timeout=1,
            tile_loader=load,
        )

        self.assertFalse(detected)
        self.assertEqual(loaded_urls, ["current"])

    def test_returns_unknown_when_current_frame_cannot_be_read(self) -> None:
        radar = {
            "meters_per_pixel": 100,
            "radar_scale": 1,
            "radar_center_pixel_x": 128,
            "radar_center_pixel_y": 128,
            "tile_size": 256,
            "frames": [
                {
                    "offset_minutes": 0,
                    "radar_tiles": [
                        {"column": 0, "row": 0, "url": "current"},
                    ],
                },
            ],
        }

        def fail(_url: str, _timeout: float) -> bytes:
            raise OSError("current unavailable")

        detected = jma_nowcast.detect_nearby_precipitation(
            radar,
            timeout=1,
            tile_loader=fail,
        )

        self.assertIsNone(detected)


class MainFetchTests(unittest.TestCase):
    observation_manifest = [
        {
            "basetime": "20251231235500",
            "validtime": "20251231235500",
            "elements": ["hrpns"],
        },
        {
            "basetime": "20260101000000",
            "validtime": "20260101000000",
            "elements": ["hrpns"],
        },
    ]
    forecast_manifest = [
        {
            "basetime": "20260101000000",
            "validtime": "20260101000500",
            "elements": ["hrpns"],
        },
    ]

    def run_main(self, nearby: bool) -> tuple[dict[str, object], list[str]]:
        requested_urls = []

        def download(url: str, _timeout: float) -> list[dict[str, object]]:
            requested_urls.append(url)
            if url == jma_nowcast.OBSERVATION_MANIFEST_URL:
                return self.observation_manifest
            if url == jma_nowcast.FORECAST_MANIFEST_URL:
                return self.forecast_manifest
            raise AssertionError(f"unexpected manifest URL: {url}")

        output = io.StringIO()
        with (
            mock.patch.object(sys, "argv", ["jma_nowcast.py"]),
            mock.patch.object(
                jma_nowcast,
                "load_clock_config",
                return_value=SimpleNamespace(latitude=35.0, longitude=139.0),
            ),
            mock.patch.object(
                jma_nowcast,
                "download_manifest",
                side_effect=download,
            ),
            mock.patch.object(
                jma_nowcast,
                "detect_nearby_precipitation",
                return_value=nearby,
            ),
            redirect_stdout(output),
        ):
            self.assertEqual(jma_nowcast.main(), 0)

        return json.loads(output.getvalue()), requested_urls

    def test_dry_path_fetches_and_returns_only_current_frame(self) -> None:
        radar, requested_urls = self.run_main(False)

        self.assertEqual(
            requested_urls,
            [jma_nowcast.OBSERVATION_MANIFEST_URL],
        )
        self.assertEqual(
            [frame["offset_minutes"] for frame in radar["frames"]],
            [0],
        )

    def test_rain_path_uses_five_minute_animation_frames(self) -> None:
        radar, requested_urls = self.run_main(True)

        self.assertEqual(
            requested_urls,
            [
                jma_nowcast.OBSERVATION_MANIFEST_URL,
                jma_nowcast.FORECAST_MANIFEST_URL,
            ],
        )
        self.assertEqual(
            [frame["offset_minutes"] for frame in radar["frames"]],
            [-5, 0, 5],
        )

    def test_unavailable_side_frames_are_omitted(self) -> None:
        radar = jma_nowcast.parse_manifests(
            [self.observation_manifest[-1]],
            None,
            include_animation_frames=True,
            latitude=35.0,
            longitude=139.0,
        )

        self.assertEqual(
            [frame["offset_minutes"] for frame in radar["frames"]],
            [0],
        )


if __name__ == "__main__":
    unittest.main()
