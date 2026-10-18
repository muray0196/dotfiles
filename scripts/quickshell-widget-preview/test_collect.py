#!/usr/bin/env python3
"""Check missing-data and rolling-window semantics without touching collectors."""

import unittest

from collect import History, commands, machine_status


def reading(now=1000):
    return {"_received_at": now, "cpu": {"usage_percent": 0, "temperature_c": 40, "power_w": 20},
            "gpus": [{"usage_percent": 0, "temperature_c": 30, "power_w": 10, "vram": {"usage_percent": 0}},
                     {"usage_percent": 0, "temperature_c": 35, "power_w": 5, "vram": {"usage_percent": 0}}],
            "memory": {"usage_percent": 20}, "storage": {"usage_percent": 30}, "uptime_seconds": 40,
            "network": {"download_bytes_per_second": 0, "upload_bytes_per_second": 0}}


class CollectorContract(unittest.TestCase):
    def test_zero_is_live_but_null_is_partial(self):
        value = reading()
        self.assertEqual(machine_status(value, 1000), "Live")
        value["gpus"][1]["power_w"] = None
        self.assertEqual(machine_status(value, 1000), "Partial")

    def test_staleness_is_not_zero(self):
        value = reading()
        self.assertEqual(machine_status(value, 1007), "Stale")
        self.assertEqual(machine_status(value, 1007, remote=True), "No signal")
        self.assertEqual(machine_status(value, 1031), "No data")
        self.assertEqual(value["cpu"]["temperature_c"], 40)

    def test_power_requires_every_expected_component(self):
        data = {"local": reading(), "main": reading()}
        history = History()
        summary = history.capture(data, 1000)
        self.assertEqual(summary["local_average"], 35)
        self.assertEqual(summary["main_average"], 30)
        data["local"]["gpus"][1]["power_w"] = None
        summary = History().capture(data, 1000)
        self.assertIsNone(summary["local_average"])
        self.assertEqual(summary["main_average"], 30)

    def test_stale_data_expires_and_backwards_clock_resets(self):
        history = History()
        data = {"local": reading()}
        history.capture(data, 1000)
        self.assertEqual(history.capture(data, 1008)["local_cpu"], 40)
        self.assertIsNone(history.capture(data, 1600)["local_cpu"])
        data["local"] = reading(900)
        self.assertEqual(history.capture(data, 900)["local_cpu"], 40)
        self.assertEqual(len(history.samples), 1)

    def test_same_bucket_replaces_instead_of_double_counting(self):
        history = History()
        data = {"local": reading()}
        history.capture(data, 1000)
        data["local"]["cpu"]["power_w"] = 40
        self.assertEqual(history.capture(data, 1001)["local_average"], 55)
        self.assertEqual(len(history.samples), 1)

    def test_preview_cannot_enable_remote_automation(self):
        for args in commands().values():
            self.assertNotIn("--automation", args)
            self.assertNotIn("--automation-settings", args)


if __name__ == "__main__":
    unittest.main()
