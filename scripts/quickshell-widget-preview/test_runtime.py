#!/usr/bin/env python3
"""Production freshness, scheduling and atomic radar publication contracts."""

import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from runtime import Runtime, cache_radar, continuous_commands, parse, radar_next


def png():
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0\0\0\0\0")) + chunk(b"IEND", b""))


def radar(reference):
    return {"reference_time": reference, "tile_size": 1, "frames": [{"offset_minutes": 0,
        "radar_tiles": [{"column": 0, "row": 0, "url": f"https://example.invalid/{reference}.png"}]}]}


class RuntimeContract(unittest.TestCase):
    def test_automation_is_explicit_and_uses_original_config(self):
        self.assertNotIn("--automation", continuous_commands()["main"])
        args = continuous_commands(True)["main"]
        self.assertIn("--automation", args)
        self.assertTrue(args[args.index("--automation-settings") + 1].endswith("performance/automation.json"))

    def test_invalid_data_does_not_become_a_reading(self):
        for line in ('null', '{"temperature":NaN}', '{"schema_version":1}'):
            with self.assertRaises(ValueError):
                parse("local", line)

    def test_indoor_display_throttles_without_losing_freshness(self):
        runtime = Runtime()
        first = {"timestamp": 1000, "temperature": 20, "humidity": 40}
        runtime.receive("indoor", first, 1000)
        runtime.receive("indoor", dict(first, timestamp=1020, temperature=21), 1020)
        self.assertEqual(runtime.snapshot(1021)["indoor"]["temperature"], 20)
        self.assertEqual(runtime.snapshot(1030)["indoor"]["temperature"], 21)
        self.assertEqual(runtime.snapshot(1081)["indoor"]["_status"], "Stale")

    def test_weather_failure_keeps_cached_values(self):
        runtime = Runtime()
        runtime.data["outdoor"] = {"temperature": 0, "humidity": 0, "_received_at": 1000}
        self.assertEqual(runtime.snapshot(1001)["outdoor"]["_status"], "Live")
        runtime.data["outdoor"]["_failed"] = True
        value = runtime.snapshot(1002)["outdoor"]
        self.assertEqual(value["_status"], "Cached")
        self.assertEqual(value["temperature"], 0)

    def test_radar_cycles_retry_and_enrich_at_original_offsets(self):
        self.assertEqual(radar_next(602, 600, -1, False, False), 650)
        self.assertEqual(radar_next(651, 600, 50, False, False), 710)
        self.assertEqual(radar_next(711, 600, 110, False, False), 770)
        self.assertEqual(radar_next(651, 600, 50, True, True), 770)
        self.assertEqual(radar_next(651, 600, 50, True, False), 950)

    def test_atomic_radar_failure_retains_previous_and_cache_is_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            first = cache_radar(radar(1), root, lambda *_: png())
            url = first["frames"][0]["radar_tiles"][0]["url"]
            self.assertTrue(url.startswith("file:///"))
            previous = list(root.glob("set-*"))
            with self.assertRaises(ValueError):
                cache_radar(radar(2), root, lambda *_: b"broken")
            self.assertEqual(list(root.glob("set-*")), previous)
            self.assertFalse(list(root.glob("pending-*")))
            for reference in (2, 3, 4):
                cache_radar(radar(reference), root, lambda *_: png())
            self.assertEqual(len(list(root.glob("set-*"))), 2)
            self.assertEqual(json.loads(json.dumps(first))["reference_time"], 1)


if __name__ == "__main__":
    unittest.main()
