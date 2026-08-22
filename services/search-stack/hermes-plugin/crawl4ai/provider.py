"""Crawl4AI extraction provider for Hermes Agent."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List

from agent.web_search_provider import WebSearchProvider

logger = logging.getLogger(__name__)


def _read_env_value(path: Path, name: str) -> str:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""

    prefix = f"{name}="
    for line in lines:
        if line.startswith(prefix):
            return line.removeprefix(prefix).strip()
    return ""


def _markdown_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if not isinstance(value, dict):
        return ""

    for key in ("fit_markdown", "raw_markdown", "markdown_with_citations"):
        text = value.get(key)
        if isinstance(text, str) and text:
            return text
    return ""


class Crawl4AIWebSearchProvider(WebSearchProvider):
    """Extract clean page content through the local Crawl4AI API."""

    def __init__(self, *, base_url: str, env_file: Path) -> None:
        self._base_url = base_url.rstrip("/")
        self._env_file = env_file

    @property
    def name(self) -> str:
        return "crawl4ai"

    @property
    def display_name(self) -> str:
        return "Crawl4AI"

    def is_available(self) -> bool:
        return bool(self._base_url) and self._env_file.is_file()

    def supports_search(self) -> bool:
        return False

    def supports_extract(self) -> bool:
        return True

    def extract(self, urls: List[str], **kwargs: Any) -> List[Dict[str, Any]]:
        import httpx

        token = _read_env_value(self._env_file, "CRAWL4AI_API_TOKEN")
        if not token:
            return [
                {
                    "url": url,
                    "title": "",
                    "content": "",
                    "raw_content": "",
                    "error": f"CRAWL4AI_API_TOKEN is missing from {self._env_file}",
                }
                for url in urls
            ]

        try:
            response = httpx.post(
                f"{self._base_url}/crawl",
                json={"urls": urls, "priority": 10},
                headers={"Authorization": f"Bearer {token}"},
                timeout=180,
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("Crawl4AI extraction failed: %s", exc)
            return [
                {
                    "url": url,
                    "title": "",
                    "content": "",
                    "raw_content": "",
                    "error": f"Crawl4AI extraction failed: {exc}",
                }
                for url in urls
            ]

        raw_results = payload.get("results", [])
        if not isinstance(raw_results, list):
            raw_results = []

        requested_format = kwargs.get("format")
        results: List[Dict[str, Any]] = []
        for index, requested_url in enumerate(urls):
            raw = raw_results[index] if index < len(raw_results) else {}
            if not isinstance(raw, dict):
                raw = {}

            metadata = raw.get("metadata")
            if not isinstance(metadata, dict):
                metadata = {}

            markdown = _markdown_text(raw.get("markdown"))
            cleaned_html = raw.get("cleaned_html")
            if not isinstance(cleaned_html, str):
                cleaned_html = ""
            html = raw.get("html")
            if not isinstance(html, str):
                html = ""

            if requested_format == "html":
                content = cleaned_html or html or markdown
            else:
                content = markdown or cleaned_html or html

            final_url = raw.get("redirected_url") or raw.get("url") or requested_url
            title = metadata.get("title", "")
            error = raw.get("error_message", "")
            if raw and raw.get("success") is False and not error:
                error = "Crawl4AI reported an unsuccessful crawl"
            if not raw:
                error = "Crawl4AI returned no result for this URL"

            item: Dict[str, Any] = {
                "url": str(final_url),
                "title": str(title or ""),
                "content": content,
                "raw_content": cleaned_html or html or markdown,
                "metadata": metadata,
            }
            if error:
                item["error"] = str(error)
            results.append(item)

        return results

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Crawl4AI",
            "badge": "local · authenticated",
            "tag": "Clean Markdown and HTML extraction through the local Crawl4AI service.",
            "env_vars": [],
        }
