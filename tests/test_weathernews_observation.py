#!/usr/bin/env python3

from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


SCRIPT_DIR = (
    Path(__file__).resolve().parents[1]
    / "modules/quickshell/.config/quickshell/clock/scripts"
)
sys.path.insert(0, str(SCRIPT_DIR))

import weathernews_observation as weather  # noqa: E402


class HourlyForecastTests(unittest.TestCase):
    def parse(self, code: int) -> dict:
        # The live source uses a blank alt attribute; the icon code carries
        # the condition, including the sunny 500 code seen at 09:00/10:00.
        parser = weather.WeatherPageParser()
        parser.feed(f"""
          <div id="flick_list_1hour"><div class="group">
            <div class="date">18日</div><div class="wx1h_content">
              <ul class="list">
                <li class="time">09</li>
                <li class="weather"><figure><img class="wx__icon"
                  src="https://gvs.weathernews.jp/onebox/img/wxicon/{code}.png"
                  width="152" height="112" alt=""></figure></li>
                <li class="rain">0.0 mm</li><li class="temp">18℃</li>
              </ul>
            </div>
          </div></div>
        """)
        reference = datetime(2026, 10, 18, 5, tzinfo=timezone(timedelta(hours=9)))
        forecasts = weather.parse_hourly_forecast(
            parser.roots["flick_list_1hour"], reference
        )
        self.assertEqual(len(forecasts), 1)
        return forecasts[0]

    def test_source_sunny_icon_500_preserves_forecast_condition(self) -> None:
        forecast = self.parse(500)
        self.assertEqual(forecast["state"], "sunny")
        self.assertEqual(forecast["hour"], "09")
        self.assertEqual(forecast["temperature"], 18)
        self.assertEqual(forecast["precipitation"], 0)

    def test_unrecognized_code_keeps_measurements_without_guessing_condition(self) -> None:
        forecast = self.parse(9999)
        self.assertEqual(forecast["state"], "unknown")
        self.assertEqual(forecast["temperature"], 18)
        self.assertEqual(forecast["precipitation"], 0)


if __name__ == "__main__":
    unittest.main()
