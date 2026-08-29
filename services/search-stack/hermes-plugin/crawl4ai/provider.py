"""Fast local search and compact Crawl4AI extraction for Hermes."""

from __future__ import annotations

import json
import logging
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Sequence, Tuple
from urllib.parse import urlsplit, urlunsplit

from agent.web_search_provider import WebSearchProvider

logger = logging.getLogger(__name__)

_SEARCH_RESPONSE_BYTES = 1 * 1024 * 1024
_MARKDOWN_RESPONSE_BYTES = 4 * 1024 * 1024
_HTML_RESPONSE_BYTES = 8 * 1024 * 1024
_NORMAL_SEARCH_CONTEXT_CHARS = 6000
_ADVANCED_SEARCH_CONTEXT_CHARS = 18000
_CAPITALIZED_PHRASE_RE = re.compile(
    r'(?<![\w"])([A-Z][\w.+-]*(?:\s+[A-Z][\w.+-]*)+)'
)


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


def _clean_inline_text(value: Any, limit: int) -> str:
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def _bounded_error(value: Any, limit: int = 300) -> str:
    return _clean_inline_text(value, limit) or type(value).__name__


def _score(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _uses_engine(result: Dict[str, Any], engine_name: str) -> bool:
    if result.get("engine") == engine_name:
        return True
    engines = result.get("engines", [])
    return isinstance(engines, list) and engine_name in engines


def _unresponsive_summary(value: Any) -> str:
    if not isinstance(value, list):
        return ""
    items = []
    for entry in value[:5]:
        if isinstance(entry, (list, tuple)) and entry:
            name = _clean_inline_text(entry[0], 80)
            reason = _clean_inline_text(entry[1] if len(entry) > 1 else "failed", 120)
            items.append(f"{name}: {reason}")
        elif entry:
            items.append(_clean_inline_text(entry, 160))
    return "; ".join(items)


def _canonical_url(value: Any) -> str:
    raw = str(value or "").strip()
    try:
        parsed = urlsplit(raw)
    except ValueError:
        return raw
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return raw
    # Preserve userinfo, port, and exact path semantics in cache/dedup keys.
    return urlunsplit(
        (parsed.scheme.lower(), parsed.netloc, parsed.path or "/", parsed.query, "")
    )


def _prioritize_named_phrase(query: str) -> str:
    """Move the first two-word capitalized phrase to the front for Bing."""
    def prioritize(match: re.Match[str]) -> str:
        words = match.group(1).split()
        if len(words) < 2:
            return match.group(1)
        phrase = f"{words[0]} {words[1]}"
        remainder = " ".join(words[2:])
        before = query[: match.start()].strip()
        after = query[match.end() :].strip()
        return " ".join(part for part in (phrase, before, remainder, after) if part)

    match = _CAPITALIZED_PHRASE_RE.search(query)
    return prioritize(match) if match else query


def _log_host(value: Any) -> str:
    try:
        return (urlsplit(str(value or "")).hostname or "unknown")[:255]
    except ValueError:
        return "invalid"


def _title_from_markdown(markdown: str) -> str:
    for line in markdown.splitlines()[:40]:
        if not line.startswith("#"):
            continue
        title = line.lstrip("#").strip()
        if title:
            return _clean_inline_text(title, 240)
    return ""


def _make_http_client(timeout_seconds: float) -> Any:
    import httpx

    timeout = httpx.Timeout(
        timeout_seconds,
        connect=min(1.0, timeout_seconds),
        pool=min(1.0, timeout_seconds),
    )
    limits = httpx.Limits(max_connections=12, max_keepalive_connections=8)
    return httpx.Client(
        timeout=timeout,
        limits=limits,
        trust_env=False,
        follow_redirects=False,
    )


def _request_json(
    client: Any,
    method: str,
    url: str,
    *,
    max_bytes: int,
    deadline_seconds: float,
    **kwargs: Any,
) -> Dict[str, Any]:
    """Stream and decode a bounded JSON response under a wall-clock deadline."""
    started = time.monotonic()
    with client.stream(method, url, **kwargs) as response:
        response.raise_for_status()
        content_length = response.headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > max_bytes:
                    raise ValueError(f"response exceeds {max_bytes} bytes")
            except ValueError as exc:
                if str(exc).startswith("response exceeds"):
                    raise

        body = bytearray()
        for chunk in response.iter_bytes():
            body.extend(chunk)
            if len(body) > max_bytes:
                raise ValueError(f"response exceeds {max_bytes} bytes")
            if time.monotonic() - started > deadline_seconds:
                raise TimeoutError(
                    f"response exceeded the {deadline_seconds:g}s deadline"
                )
    payload = json.loads(bytes(body))
    if not isinstance(payload, dict):
        raise ValueError("response JSON is not an object")
    return payload


class FastSearXNGWebSearchProvider(WebSearchProvider):
    """SearXNG provider with a measured fast engine and bounded snippets."""

    def __init__(
        self,
        *,
        base_url: str,
        engines: str = "bing",
        snippet_char_limit: int = 360,
        timeout_seconds: float = 3.0,
        http_client: Any = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._engines = engines.strip()
        self._snippet_char_limit = max(120, min(int(snippet_char_limit), 800))
        self._timeout_seconds = max(1.0, min(float(timeout_seconds), 15.0))
        self._client = http_client or _make_http_client(self._timeout_seconds + 1.0)
        self._owns_client = http_client is None

    @property
    def name(self) -> str:
        return "searxng-fast"

    @property
    def display_name(self) -> str:
        return "SearXNG Fast"

    def is_available(self) -> bool:
        return bool(self._base_url)

    def supports_search(self) -> bool:
        return True

    def supports_extract(self) -> bool:
        return False

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def search(self, query: str, limit: int = 5) -> Dict[str, Any]:
        clean_query = _clean_inline_text(query, 1000)
        if not clean_query:
            return {"success": False, "error": "Search query is empty"}
        if not self._base_url:
            return {"success": False, "error": "SearXNG URL is not configured"}
        advanced = bool(re.search(r"(?:^|\s)!\S+", clean_query))
        try:
            requested_limit = max(1, min(int(limit), 10))
        except (TypeError, ValueError):
            requested_limit = 5
        # Hermes asks providers for a bucket of ten even when the model asked
        # for three. Keep normal searches at three; explicit SearX bangs remain
        # an intentional engine-selection escape hatch.
        result_limit = requested_limit if advanced else min(requested_limit, 3)

        params: Dict[str, Any] = {
            "q": (
                _prioritize_named_phrase(clean_query)
                if not advanced and self._engines == "bing"
                else clean_query
            ),
            "format": "json",
            "pageno": 1,
            "timeout_limit": self._timeout_seconds,
        }
        # Valid SearX bangs override this selector. Keeping the fast selector
        # present also prevents an unknown/literal bang from falling through
        # to every default engine and recreating the slow tail.
        if self._engines:
            params["engines"] = self._engines

        started = time.monotonic()
        try:
            payload = _request_json(
                self._client,
                "GET",
                f"{self._base_url}/search",
                max_bytes=_SEARCH_RESPONSE_BYTES,
                deadline_seconds=self._timeout_seconds + 1.0,
                params=params,
                headers={"Accept": "application/json"},
            )
        except Exception as exc:  # network boundary: normalize client failures
            logger.warning("SearXNG fast search failed: %s", _bounded_error(exc))
            return {
                "success": False,
                "error": f"Local SearXNG search failed: {_bounded_error(exc)}",
            }

        raw_results = payload.get("results", []) if isinstance(payload, dict) else []
        if not isinstance(raw_results, list):
            raw_results = []
        raw_results = [item for item in raw_results if isinstance(item, dict)]
        if not advanced and self._engines and raw_results:
            attributed = [
                item for item in raw_results if _uses_engine(item, self._engines)
            ]
            if not attributed:
                return {
                    "success": False,
                    "error": (
                        "Local SearXNG did not activate the configured fast "
                        f"engine profile '{self._engines}'"
                    ),
                }
            raw_results = attributed
        unresponsive = _unresponsive_summary(
            payload.get("unresponsive_engines") if isinstance(payload, dict) else []
        )
        if not raw_results and unresponsive:
            return {
                "success": False,
                "error": f"Local SearXNG engines were unresponsive: {unresponsive}",
            }
        sorted_results = sorted(
            raw_results,
            key=lambda item: _score(item.get("score")),
            reverse=True,
        )

        web_results: List[Dict[str, Any]] = []
        seen_urls = set()
        returned_chars = 0
        context_budget = (
            _ADVANCED_SEARCH_CONTEXT_CHARS
            if advanced
            else _NORMAL_SEARCH_CONTEXT_CHARS
        )
        for raw in sorted_results:
            url = str(raw.get("url") or "").strip()
            # Do not turn an unusually long URL into a syntactically invalid
            # ellipsis-truncated URL, and do not let URL metadata dominate the
            # model context.
            if len(url) > 2048:
                continue
            canonical = _canonical_url(url)
            if not url or canonical in seen_urls:
                continue
            seen_urls.add(canonical)
            candidate = {
                "title": _clean_inline_text(raw.get("title"), 240),
                "url": url,
                "description": _clean_inline_text(
                    raw.get("content"), self._snippet_char_limit
                ),
                "position": len(web_results) + 1,
            }
            candidate_chars = sum(
                len(str(candidate[field]))
                for field in ("title", "url", "description")
            )
            if returned_chars + candidate_chars > context_budget:
                continue
            web_results.append(candidate)
            returned_chars += candidate_chars
            if len(web_results) >= result_limit:
                break

        logger.info(
            "SearXNG fast search: results=%d raw=%d elapsed_ms=%d chars=%d engines=%s",
            len(web_results),
            len(raw_results),
            round((time.monotonic() - started) * 1000),
            returned_chars,
            (
                f"{self._engines} plus query bangs"
                if advanced and self._engines
                else (self._engines or "default")
            ),
        )
        return {"success": True, "data": {"web": web_results}}

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "SearXNG Fast",
            "badge": "local · bounded",
            "tag": "Compact results through a measured low-latency engine profile.",
            "env_vars": [],
        }


class Crawl4AIClient:
    """Compact authenticated client for Crawl4AI's ``/md`` endpoint."""

    def __init__(
        self,
        *,
        base_url: str,
        env_file: Path,
        timeout_seconds: float = 30.0,
        http_client: Any = None,
    ) -> None:
        self._base_url = base_url.rstrip("/")
        self._env_file = env_file
        self._timeout_seconds = max(5.0, min(float(timeout_seconds), 90.0))
        self._client = http_client or _make_http_client(self._timeout_seconds)
        self._owns_client = http_client is None

    def is_available(self) -> bool:
        return bool(self._base_url) and bool(
            _read_env_value(self._env_file, "CRAWL4AI_API_TOKEN")
        )

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def fetch_many(
        self,
        requests: Sequence[Tuple[str, str, str]],
    ) -> List[Dict[str, Any]]:
        requests = list(requests)[:5]
        if not requests:
            return []
        keys: List[Tuple[str, str, str]] = []
        unique: Dict[Tuple[str, str, str], Tuple[str, str, str]] = {}
        for url, query, filter_type in requests:
            key = (_canonical_url(url), query.casefold(), filter_type)
            keys.append(key)
            unique.setdefault(key, (url, query, filter_type))

        if len(unique) == 1:
            result = self.fetch_markdown(*next(iter(unique.values())))
            return [dict(result) for _key in keys]

        completed: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
        with ThreadPoolExecutor(max_workers=min(5, len(unique))) as executor:
            futures = {
                executor.submit(self.fetch_markdown, *request): key
                for key, request in unique.items()
            }
            for future in as_completed(futures):
                key = futures[future]
                try:
                    completed[key] = future.result()
                except Exception as exc:
                    completed[key] = {
                        "url": unique[key][0],
                        "title": "",
                        "content": "",
                        "raw_content": "",
                        "error": f"Crawl4AI extraction failed: {_bounded_error(exc)}",
                    }
        return [dict(completed[key]) for key in keys]

    def fetch_markdown(
        self,
        url: str,
        query: str = "",
        filter_type: str = "fit",
    ) -> Dict[str, Any]:
        selected_filter = filter_type if filter_type in {"fit", "bm25", "raw"} else "fit"
        clean_query = _clean_inline_text(query, 1000) if selected_filter == "bm25" else ""

        token = _read_env_value(self._env_file, "CRAWL4AI_API_TOKEN")
        if not token:
            return {
                "url": url,
                "title": "",
                "content": "",
                "raw_content": "",
                "error": f"CRAWL4AI_API_TOKEN is missing from {self._env_file}",
            }

        body: Dict[str, Any] = {
            "url": url,
            "f": selected_filter,
            # v0.9.2's derived cache is not filter/query-aware; Hermes provides
            # the correctly keyed read cache instead.
            "c": "0",
        }
        if clean_query:
            body["q"] = clean_query

        started = time.monotonic()
        try:
            payload = _request_json(
                self._client,
                "POST",
                f"{self._base_url}/md",
                max_bytes=_MARKDOWN_RESPONSE_BYTES,
                deadline_seconds=self._timeout_seconds,
                json=body,
                headers={
                    "Accept": "application/json",
                    "Authorization": f"Bearer {token}",
                },
            )
        except Exception as exc:  # network boundary: normalize client failures
            logger.warning("Crawl4AI Markdown extraction failed: %s", _bounded_error(exc))
            return {
                "url": url,
                "title": "",
                "content": "",
                "raw_content": "",
                "error": f"Crawl4AI extraction failed: {_bounded_error(exc)}",
            }

        if payload.get("success") is not True:
            return {
                "url": url,
                "title": "",
                "content": "",
                "raw_content": "",
                "error": "Crawl4AI did not report a successful Markdown extraction",
            }
        markdown = payload.get("markdown", "")
        reported_filter = selected_filter
        # Crawl4AI 0.9.2 can produce successful-but-blank fit Markdown for
        # sparse pages (for example, link lists and tables) while its raw
        # Markdown is useful. Retry only that shape so normal pages never pay
        # a second request and transport failures do not trigger extra load.
        if (
            selected_filter == "fit"
            and (not isinstance(markdown, str) or not markdown.strip())
        ):
            fallback_body = {**body, "f": "raw"}
            try:
                fallback_payload = _request_json(
                    self._client,
                    "POST",
                    f"{self._base_url}/md",
                    max_bytes=_MARKDOWN_RESPONSE_BYTES,
                    deadline_seconds=self._timeout_seconds,
                    json=fallback_body,
                    headers={
                        "Accept": "application/json",
                        "Authorization": f"Bearer {token}",
                    },
                )
            except Exception as exc:
                logger.warning(
                    "Crawl4AI raw Markdown fallback failed: %s",
                    _bounded_error(exc),
                )
            else:
                fallback_markdown = fallback_payload.get("markdown", "")
                if (
                    fallback_payload.get("success") is True
                    and isinstance(fallback_markdown, str)
                    and fallback_markdown.strip()
                ):
                    payload = fallback_payload
                    markdown = fallback_markdown
                    reported_filter = "raw-fallback"
        if not isinstance(markdown, str) or not markdown.strip():
            return {
                "url": url,
                "title": "",
                "content": "",
                "raw_content": "",
                "error": "Crawl4AI returned no Markdown for this URL",
            }

        result = {
            "url": str(payload.get("url") or url),
            "title": _title_from_markdown(markdown),
            "content": markdown,
            # Hermes prefers raw_content when caching and returning extracts.
            # Both fields must therefore carry the selected Markdown.
            "raw_content": markdown,
            "metadata": {},
        }
        logger.info(
            "Crawl4AI Markdown: filter=%s elapsed_ms=%d chars=%d host=%s",
            reported_filter,
            round((time.monotonic() - started) * 1000),
            len(markdown),
            _log_host(url),
        )
        return result

    def fetch_html_many(self, urls: Sequence[str]) -> List[Dict[str, Any]]:
        """Compatibility path for explicit HTML requests; normal calls use /md."""
        urls = list(urls)[:5]
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
        if len(urls) == 1:
            try:
                return [self._fetch_html_one(urls[0], token)]
            except Exception as exc:
                return [
                    {
                        "url": urls[0],
                        "title": "",
                        "content": "",
                        "raw_content": "",
                        "error": (
                            "Crawl4AI HTML extraction failed: "
                            f"{_bounded_error(exc)}"
                        ),
                    }
                ]

        ordered: List[Dict[str, Any] | None] = [None] * len(urls)
        with ThreadPoolExecutor(max_workers=min(5, len(urls))) as executor:
            futures = {
                executor.submit(self._fetch_html_one, url, token): index
                for index, url in enumerate(urls)
            }
            for future in as_completed(futures):
                index = futures[future]
                try:
                    ordered[index] = future.result()
                except Exception as exc:
                    ordered[index] = {
                        "url": urls[index],
                        "title": "",
                        "content": "",
                        "raw_content": "",
                        "error": (
                            "Crawl4AI HTML extraction failed: "
                            f"{_bounded_error(exc)}"
                        ),
                    }
        return [item or {} for item in ordered]

    def _fetch_html_one(self, url: str, token: str) -> Dict[str, Any]:
        payload = _request_json(
            self._client,
            "POST",
            f"{self._base_url}/crawl",
            max_bytes=_HTML_RESPONSE_BYTES,
            deadline_seconds=self._timeout_seconds,
            json={"urls": [url]},
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {token}",
            },
        )
        raw_results = payload.get("results", [])
        raw = raw_results[0] if isinstance(raw_results, list) and raw_results else {}
        if not isinstance(raw, dict):
            raw = {}
        metadata = raw.get("metadata") if isinstance(raw.get("metadata"), dict) else {}
        html = raw.get("cleaned_html") or raw.get("html") or ""
        if not isinstance(html, str):
            html = ""
        error = raw.get("error_message") or ""
        if not raw:
            error = "Crawl4AI returned no result for this URL"
        elif raw.get("success") is False and not error:
            error = "Crawl4AI reported an unsuccessful crawl"
        item: Dict[str, Any] = {
            "url": str(raw.get("redirected_url") or raw.get("url") or url),
            "title": str(metadata.get("title") or ""),
            "content": html,
            "raw_content": html,
            "metadata": metadata,
        }
        if error:
            item["error"] = str(error)
        return item


class Crawl4AIWebSearchProvider(WebSearchProvider):
    """Hermes extraction provider backed by compact Crawl4AI Markdown."""

    def __init__(
        self,
        client: Crawl4AIClient,
        *,
        provider_name: str = "crawl4ai-compact",
        provider_display_name: str = "Crawl4AI Compact",
    ) -> None:
        self._client = client
        self._provider_name = provider_name
        self._provider_display_name = provider_display_name

    @property
    def name(self) -> str:
        return self._provider_name

    @property
    def display_name(self) -> str:
        return self._provider_display_name

    def is_available(self) -> bool:
        return self._client.is_available()

    def supports_search(self) -> bool:
        return False

    def supports_extract(self) -> bool:
        return True

    def extract(self, urls: List[str], **kwargs: Any) -> List[Dict[str, Any]]:
        requested_format = str(kwargs.get("format") or "markdown").lower()
        if requested_format == "html":
            return self._client.fetch_html_many(urls)
        return self._client.fetch_many([(url, "", "fit") for url in urls])

    def get_setup_schema(self) -> Dict[str, Any]:
        return {
            "name": "Crawl4AI Compact",
            "badge": "local · authenticated",
            "tag": "Compact fit Markdown through the local Crawl4AI service.",
            "env_vars": [],
        }
