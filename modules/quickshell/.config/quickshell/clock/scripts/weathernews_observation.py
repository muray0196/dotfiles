#!/usr/bin/env python3
"""Fetch Weathernews data for a configured location."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from clock_config import DEFAULT_CONFIG, load_clock_config


USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) QuickshellWeatherWidget/1.0"
RETRY_DELAYS = (10, 30)
RETRYABLE_HTTP_STATUSES = {408, 425, 429, 500, 502, 503, 504}

HOURLY_WEATHER = {
    100: "sunny",
    200: "cloudy",
    300: "rain",
    400: "snow",
    430: "sleet",
    550: "extreme_heat",
    600: "sunny",
    650: "light_rain",
    850: "storm",
    950: "blizzard",
}
PRECIPITATION_STATES = {
    "light_rain",
    "rain",
    "storm",
    "sleet",
    "snow",
    "blizzard",
}


@dataclass
class Element:
    tag: str
    attrs: dict[str, str]
    children: list[Element | str] = field(default_factory=list)

    def has_class(self, name: str) -> bool:
        return name in self.attrs.get("class", "").split()

    def text(self) -> str:
        parts: list[str] = []
        for child in self.children:
            parts.append(child if isinstance(child, str) else child.text())
        return " ".join(" ".join(parts).split())

    def descendants(self) -> Iterable[Element]:
        for child in self.children:
            if isinstance(child, Element):
                yield child
                yield from child.descendants()


class WeatherPageParser(HTMLParser):
    """Build tiny element trees for the observation and hourly forecast."""

    TARGET_IDS = {"flick_list_1hour", "todayDetails"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.roots: dict[str, Element] = {}
        self._stack: list[Element] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        attributes = {key: value or "" for key, value in attrs}
        if not self._stack:
            element_id = attributes.get("id")
            if element_id not in self.TARGET_IDS:
                return
            root = Element(tag, attributes)
            self.roots[element_id] = root
            self._stack.append(root)
            return

        element = Element(tag, attributes)
        self._stack[-1].children.append(element)
        if tag not in {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}:
            self._stack.append(element)

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if self._stack:
            attributes = {key: value or "" for key, value in attrs}
            self._stack[-1].children.append(Element(tag, attributes))

    def handle_endtag(self, tag: str) -> None:
        if not self._stack:
            return

        for index in range(len(self._stack) - 1, -1, -1):
            if self._stack[index].tag == tag:
                del self._stack[index:]
                return

    def handle_data(self, data: str) -> None:
        if self._stack and data.strip():
            self._stack[-1].children.append(data)


def find_first(
    root: Element, tag: str, class_name: str | None = None
) -> Element | None:
    for element in root.descendants():
        if element.tag == tag and (
            class_name is None or element.has_class(class_name)
        ):
            return element
    return None


def find_children(
    root: Element, tag: str, class_name: str | None = None
) -> Iterable[Element]:
    for child in root.children:
        if isinstance(child, Element) and child.tag == tag and (
            class_name is None or child.has_class(class_name)
        ):
            yield child


def parse_number(value: str, field_name: str) -> float:
    match = re.fullmatch(r"[-+]?\d+(?:\.\d+)?", value.strip())
    if not match:
        raise ValueError(f"invalid {field_name}: {value!r}")
    return float(value)


def parse_measurement(value: str, field_name: str) -> float:
    match = re.search(r"[-+]?\d+(?:\.\d+)?", value)
    if not match:
        raise ValueError(f"invalid {field_name}: {value!r}")
    return float(match.group())


def month_candidate(reference: date, month_offset: int, day: int) -> date | None:
    month_index = reference.year * 12 + reference.month - 1 + month_offset
    year, zero_based_month = divmod(month_index, 12)
    try:
        return date(year, zero_based_month + 1, day)
    except ValueError:
        return None


def resolve_forecast_date(
    day: int, reference: date, previous: date | None
) -> date:
    candidates = [
        candidate
        for offset in (-1, 0, 1)
        if (candidate := month_candidate(reference, offset, day)) is not None
    ]
    if previous is not None:
        forward = [candidate for candidate in candidates if candidate >= previous]
        if forward:
            return min(forward, key=lambda candidate: candidate - previous)
    return min(candidates, key=lambda candidate: abs(candidate - reference))


def observation_state(condition: str) -> str:
    if "雷" in condition:
        return "thunder"
    if "大雪" in condition or "吹雪" in condition:
        return "blizzard"
    if any(label in condition for label in ("大雨", "豪雨", "嵐", "暴風雨")):
        return "storm"
    if "みぞれ" in condition:
        return "sleet"
    if any(label in condition for label in ("小雨", "霧雨", "弱い雨")):
        return "light_rain"
    if "雪" in condition:
        return "snow"
    if "雨" in condition:
        return "rain"
    if "猛暑" in condition:
        return "extreme_heat"
    if "霧" in condition:
        return "fog"
    if "晴" in condition or "快晴" in condition:
        return "sunny"
    if "くもり" in condition or "ぐもり" in condition or "曇" in condition:
        return "cloudy"
    return "unknown"


def forecast_weather(weather_code: int) -> str:
    return HOURLY_WEATHER.get(weather_code, "unknown")


def parse_forecast_item(
    item: Element, forecast_date: date, reference: datetime
) -> dict[str, Any]:
    time_element = find_first(item, "li", "time")
    weather_element = find_first(item, "li", "weather")
    rain_element = find_first(item, "li", "rain")
    temperature_element = find_first(item, "li", "temp")
    if any(
        element is None
        for element in (
            time_element,
            weather_element,
            rain_element,
            temperature_element,
        )
    ):
        raise ValueError("hourly forecast item is incomplete")

    time_match = re.fullmatch(r"(\d{1,2})", time_element.text())
    image = find_first(weather_element, "img")
    code_match = (
        re.search(r"/wxicon/(\d+)(?:@2x)?\.png", image.attrs.get("src", ""))
        if image is not None
        else None
    )
    if time_match is None or code_match is None:
        raise ValueError("hourly forecast time or weather icon is invalid")

    hour = int(time_match.group(1))
    if not 0 <= hour <= 23:
        raise ValueError(f"hourly forecast hour is out of range: {hour}")

    temperature = parse_measurement(temperature_element.text(), "temperature")
    precipitation = parse_measurement(rain_element.text(), "precipitation")
    if not -50 <= temperature <= 60:
        raise ValueError(f"forecast temperature is out of range: {temperature}")
    if not 0 <= precipitation <= 500:
        raise ValueError(f"forecast precipitation is out of range: {precipitation}")

    forecast_at = reference.replace(
        year=forecast_date.year,
        month=forecast_date.month,
        day=forecast_date.day,
        hour=hour,
        minute=0,
        second=0,
        microsecond=0,
    )
    weather_code = int(code_match.group(1))
    state = forecast_weather(weather_code)
    return {
        "at": forecast_at.isoformat(timespec="minutes"),
        "hour": f"{hour:02d}",
        "state": state,
        "temperature": temperature,
        "precipitation": precipitation,
    }


def parse_hourly_forecast(
    root: Element | None, reference: datetime
) -> list[dict[str, Any]]:
    if root is None:
        return []

    forecasts: list[dict[str, Any]] = []
    previous_date: date | None = None
    limit = reference + timedelta(hours=72)
    for group in root.descendants():
        if group.tag != "div" or not group.has_class("group"):
            continue

        date_element = find_first(group, "div", "date")
        date_match = (
            re.search(r"(\d{1,2})日", date_element.text())
            if date_element is not None
            else None
        )
        if date_match is None:
            continue
        forecast_date = resolve_forecast_date(
            int(date_match.group(1)), reference.date(), previous_date
        )
        previous_date = forecast_date

        content = find_first(group, "div", "wx1h_content")
        if content is None:
            continue
        for item in find_children(content, "ul", "list"):
            if item.has_class("past"):
                continue
            try:
                forecast = parse_forecast_item(item, forecast_date, reference)
                forecast_at = datetime.fromisoformat(forecast["at"])
            except ValueError:
                continue
            if reference < forecast_at <= limit:
                forecasts.append(forecast)

    forecasts.sort(key=lambda forecast: forecast["at"])
    return forecasts


WEEKDAYS = "月火水木金土日"


def forecast_day_label(forecast_date: date, reference_date: date) -> str:
    offset = (forecast_date - reference_date).days
    if offset == 0:
        return "今日"
    if offset == 1:
        return "明日"
    if offset == 2:
        return "明後日"
    return f"{forecast_date.month}/{forecast_date.day}"


def forecast_period(hour: int) -> str:
    if hour < 6:
        return "未明"
    if hour < 12:
        return "朝"
    if hour < 18:
        return "午後"
    return "夜"


def format_precipitation(value: float) -> str:
    return f"{value:g}"


def build_rain_outlook(
    forecasts: list[dict[str, Any]], reference: datetime
) -> str:
    if not forecasts:
        return ""

    rainy_index = next(
        (
            index
            for index, forecast in enumerate(forecasts)
            if forecast["precipitation"] > 0
            or forecast["state"] in PRECIPITATION_STATES
        ),
        None,
    )
    if rainy_index is not None:
        if rainy_index < 5:
            return ""

        forecast = forecasts[rainy_index]
        forecast_at = datetime.fromisoformat(forecast["at"])
        hours_ahead = (forecast_at - reference).total_seconds() / 3600
        if forecast["state"] in {"snow", "blizzard"}:
            phenomenon = "雪"
        elif forecast["state"] == "sleet":
            phenomenon = "みぞれ"
        else:
            phenomenon = "雨"
        if hours_ahead <= 15:
            day_label = forecast_day_label(forecast_at.date(), reference.date())
            prefix = "" if day_label == "今日" else day_label
            amount = ""
            if forecast["precipitation"] > 0:
                amount = (
                    " · "
                    + format_precipitation(forecast["precipitation"])
                    + "mm/h"
                )
            return f"{prefix}{forecast_at.hour}時頃から{phenomenon}{amount}"
        if hours_ahead <= 48:
            return (
                forecast_day_label(forecast_at.date(), reference.date())
                + forecast_period(forecast_at.hour)
                + f"に{phenomenon}の可能性"
            )
        return (
            f"{forecast_at.month}/{forecast_at.day}"
            f"({WEEKDAYS[forecast_at.weekday()]}) {phenomenon}の可能性"
        )

    last_forecast = datetime.fromisoformat(forecasts[-1]["at"])
    if (last_forecast - reference).total_seconds() < 60 * 60 * 60:
        return ""
    return (
        f"{last_forecast.month}/{last_forecast.day}"
        f"({WEEKDAYS[last_forecast.weekday()]})まで雨予報なし"
    )


def parse_observation(html: str) -> dict[str, Any]:
    reference = datetime.now().astimezone()
    parser = WeatherPageParser()
    parser.feed(html)
    root = parser.roots.get("todayDetails")
    if root is None:
        raise ValueError("Weathernews observation section was not found")

    time_element = find_first(root, "p", "time")
    condition_element = find_first(root, "figcaption")
    if time_element is None or condition_element is None:
        raise ValueError("Weathernews observation header is incomplete")

    observed_label = time_element.text()
    time_match = re.fullmatch(r"(\d{1,2}:\d{2})時点", observed_label)
    if not time_match:
        raise ValueError(f"invalid observation time: {observed_label!r}")

    measurements: dict[str, tuple[str, str]] = {}
    for element in root.descendants():
        if element.tag != "li" or not element.has_class("obs_block"):
            continue
        title = find_first(element, "p", "title")
        value = find_first(element, "p", "value")
        unit = find_first(element, "p", "unit")
        if title is not None and value is not None and unit is not None:
            measurements[title.text()] = (value.text(), unit.text())

    expected_units = {
        "気温": "℃",
        "湿度": "%",
    }
    for label, unit in expected_units.items():
        if label not in measurements:
            raise ValueError(f"Weathernews observation is missing {label}")
        if measurements[label][1] != unit:
            raise ValueError(
                f"unexpected unit for {label}: {measurements[label][1]!r}"
            )

    temperature = parse_number(measurements["気温"][0], "temperature")
    humidity = parse_number(measurements["湿度"][0], "humidity")

    if not -50 <= temperature <= 60:
        raise ValueError(f"temperature is out of range: {temperature}")
    if not 0 <= humidity <= 100:
        raise ValueError(f"humidity is out of range: {humidity}")

    forecasts = parse_hourly_forecast(
        parser.roots.get("flick_list_1hour"), reference
    )
    condition = condition_element.text()
    display_forecasts = [
        {
            "hour": forecast["hour"],
            "state": forecast["state"],
            "temperature": forecast["temperature"],
            "precipitation": forecast["precipitation"],
        }
        for forecast in forecasts[:5]
    ]
    return {
        "observed_at": time_match.group(1),
        "state": observation_state(condition),
        "condition": condition,
        "temperature": temperature,
        "humidity": int(humidity),
        "hourly_forecast": display_forecasts,
        "rain_outlook": build_rain_outlook(forecasts, reference),
    }


def download_html(url: str, timeout: float) -> str:
    request = Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html"},
    )
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def fetch_html(url: str, timeout: float) -> str:
    total_attempts = len(RETRY_DELAYS) + 1

    for attempt in range(total_attempts):
        try:
            return download_html(url, timeout)
        except HTTPError as error:
            if (
                error.code not in RETRYABLE_HTTP_STATUSES
                or attempt == total_attempts - 1
            ):
                raise
            retry_error: OSError = error
        except OSError as error:
            if attempt == total_attempts - 1:
                raise
            retry_error = error

        delay = RETRY_DELAYS[attempt]
        print(
            "Weathernews download failed "
            f"(attempt {attempt + 1}/{total_attempts}); "
            f"retrying in {delay}s: {retry_error}",
            file=sys.stderr,
            flush=True,
        )
        time.sleep(delay)

    raise RuntimeError("unreachable")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--url", help="override the configured Weathernews URL")
    parser.add_argument(
        "--file",
        type=Path,
        help="parse a saved Weathernews HTML file instead of downloading",
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
        if args.file is not None:
            html = args.file.read_text(encoding="utf-8")
        else:
            source_url = (
                args.url
                if args.url is not None
                else load_clock_config(args.config).weathernews_url
            )
            html = fetch_html(source_url, args.timeout)
        observation = parse_observation(html)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"Weathernews fetch failed: {error}", file=sys.stderr)
        return 1

    print(
        json.dumps(
            observation,
            ensure_ascii=False,
            indent=2 if args.pretty else None,
            separators=None if args.pretty else (",", ":"),
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
