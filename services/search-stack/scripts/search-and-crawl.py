#!/usr/bin/env python3
"""Search with SearXNG, then crawl the top results with Crawl4AI."""

import argparse
import json
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request_json(url: str, *, payload: dict | None = None) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"

    request = Request(url, data=data, headers=headers)
    with urlopen(request, timeout=180) as response:
        return json.load(response)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("query", help="Search query")
    parser.add_argument("-n", "--limit", type=int, default=3)
    parser.add_argument("-o", "--output", type=Path, default=Path("crawl-results.json"))
    parser.add_argument("--language", default="ja")
    args = parser.parse_args()

    params = urlencode({"q": args.query, "format": "json", "language": args.language})
    try:
        search = request_json(f"http://localhost:8080/search?{params}")
        results = search.get("results", [])[: args.limit]
        urls = [result["url"] for result in results if result.get("url")]
        if not urls:
            print("No search results were returned.", file=sys.stderr)
            return 1

        print("Crawling:")
        for result in results:
            if result.get("url"):
                print(f"- {result.get('title', '(untitled)')}: {result['url']}")
        crawled = request_json(
            "http://localhost:11235/crawl",
            payload={"urls": urls, "priority": 10},
        )
        args.output.write_text(
            json.dumps(crawled, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"Saved Crawl4AI response to {args.output}")
        return 0
    except (HTTPError, URLError, TimeoutError) as error:
        print(f"Request failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
