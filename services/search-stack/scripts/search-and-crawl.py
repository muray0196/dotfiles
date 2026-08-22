#!/usr/bin/env python3
"""Search with SearXNG, then crawl the top results with Crawl4AI."""

import argparse
import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return values

    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        name, separator, value = line.partition("=")
        if separator:
            values[name] = value
    return values


def request_json(
    url: str,
    *,
    payload: dict | None = None,
    bearer_token: str = "",
) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode()
        headers["Content-Type"] = "application/json"
    if bearer_token:
        headers["Authorization"] = f"Bearer {bearer_token}"

    request = Request(url, data=data, headers=headers)
    with urlopen(request, timeout=180) as response:
        return json.load(response)


def main() -> int:
    stack_env = read_env_file(Path(__file__).resolve().parent.parent / ".env")
    searxng_host_port = os.environ.get(
        "SEARXNG_HOST_PORT",
        stack_env.get("SEARXNG_HOST_PORT", "8888"),
    )
    crawl4ai_token = os.environ.get(
        "CRAWL4AI_API_TOKEN",
        stack_env.get("CRAWL4AI_API_TOKEN", ""),
    )

    parser = argparse.ArgumentParser()
    parser.add_argument("query", help="Search query")
    parser.add_argument("-n", "--limit", type=int, default=3)
    parser.add_argument("-o", "--output", type=Path, default=Path("crawl-results.json"))
    parser.add_argument("--language", default="ja")
    parser.add_argument(
        "--searxng-url",
        default=f"http://localhost:{searxng_host_port}",
    )
    parser.add_argument("--crawl4ai-url", default="http://localhost:11235")
    args = parser.parse_args()

    params = urlencode({"q": args.query, "format": "json", "language": args.language})
    try:
        search = request_json(f"{args.searxng_url.rstrip('/')}/search?{params}")
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
            f"{args.crawl4ai_url.rstrip('/')}/crawl",
            payload={"urls": urls, "priority": 10},
            bearer_token=crawl4ai_token,
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
