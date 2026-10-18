#!/usr/bin/env python3
"""History window labels must reflect collection time without fabricating samples."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/quickshell-widget-preview"))

from collect import History  # noqa: E402


def readings(now, temperature=40, power=10):
    return {
        "local": {
            "_received_at": now,
            "cpu": {"temperature_c": temperature, "power_w": power},
            "gpus": [
                {"temperature_c": 30, "hotspot_temperature_c": 35, "power_w": 20},
                {"temperature_c": 25, "hotspot_temperature_c": 28, "power_w": 30},
            ],
        }
    }


class HistoryWindowTests(unittest.TestCase):
    def test_first_sample_is_not_ten_minutes_of_history(self):
        summary = History().capture(readings(1000), 1000)
        self.assertEqual(summary["window_seconds"], 0)
        self.assertEqual(summary["local_cpu"], 40)
        self.assertEqual(summary["local_average"], 60)
        self.assertIsNone(summary["main_average"])

    def test_full_window_expires_old_peaks_and_caps_elapsed_time(self):
        history = History()
        history.capture(readings(1000, temperature=90), 1000)
        for now in range(1002, 1600, 2):
            summary = history.capture(readings(now), now)
        self.assertEqual(summary["window_seconds"], 598)
        self.assertEqual(summary["local_cpu"], 90)
        summary = history.capture(readings(1600), 1600)
        self.assertEqual(summary["window_seconds"], 600)
        self.assertEqual(summary["local_cpu"], 40)
        self.assertEqual(len(history.samples), 300)
        self.assertEqual(history.capture(readings(1800), 1800)["window_seconds"], 600)

    def test_gaps_and_incomplete_power_do_not_add_zero_samples(self):
        history = History()
        history.capture(readings(1000, power=10), 1000)
        incomplete = readings(1020)
        incomplete["local"]["gpus"][1]["power_w"] = None
        history.capture(incomplete, 1020)
        summary = history.capture(readings(1040, power=30), 1040)
        self.assertEqual(summary["window_seconds"], 40)
        self.assertEqual(summary["local_average"], 70)
        self.assertEqual(summary["local_peak"], 80)
        self.assertEqual(len(history.samples), 3)

    def test_replacing_a_bucket_does_not_advance_collection(self):
        history = History()
        history.capture(readings(1000, temperature=90), 1000)
        summary = history.capture(readings(1001, temperature=50), 1001)
        self.assertEqual(summary["window_seconds"], 0)
        self.assertEqual(summary["local_cpu"], 50)
        self.assertEqual(len(history.samples), 1)

    def test_backwards_clock_restarts_collection_and_discards_old_values(self):
        history = History()
        history.capture(readings(1000, temperature=90), 1000)
        history.capture(readings(1120), 1120)
        summary = history.capture(readings(900, temperature=35), 900)
        self.assertEqual(summary["window_seconds"], 0)
        self.assertEqual(summary["local_cpu"], 35)
        self.assertEqual(len(history.samples), 1)


if __name__ == "__main__":
    unittest.main()
