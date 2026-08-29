"""Hermes staged web retrieval backed by local SearXNG and Crawl4AI."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .provider import (
    Crawl4AIClient,
    Crawl4AIWebSearchProvider,
    FastSearXNGWebSearchProvider,
)
from .tools import register_tools


_WEB_RETRIEVAL_POLICY = """Web retrieval:
- Ordinary/current lookup: use web_search with limit 3. Treat snippets as sufficient unless exact verification needs page content.
- If needed, web_open one selected URL; use two only to corroborate.
- Use web_research only for explicit deep/exhaustive requests, high-stakes claims, or insufficient/conflicting quick evidence. It includes search; do not pre-search.
- Prefer web_open to web_extract. Load deferred tools through tool_search.
"""


def _number_setting(
    ctx: Any,
    name: str,
    default: float,
    minimum: float,
    maximum: float,
) -> float:
    try:
        value = float(ctx.get_config(name, default=default))
    except (TypeError, ValueError):
        value = default
    return max(minimum, min(value, maximum))


def register(ctx) -> None:
    """Register fast search, compact extraction, and staged retrieval tools."""
    base_url = ctx.get_config("base_url", default="http://127.0.0.1:11235")
    searxng_url = ctx.get_config("searxng_url", default="http://127.0.0.1:8888")
    env_file = ctx.get_config(
        "env_file",
        default=str(Path.home() / "services/search-stack/.env"),
    )

    search_provider = FastSearXNGWebSearchProvider(
        base_url=str(searxng_url),
        engines=str(ctx.get_config("fast_engines", default="google cse")),
        snippet_char_limit=int(
            _number_setting(ctx, "snippet_char_limit", 360, 120, 800)
        ),
        timeout_seconds=_number_setting(ctx, "search_timeout_seconds", 3, 1, 15),
    )
    crawl_client = Crawl4AIClient(
        base_url=str(base_url),
        env_file=Path(str(env_file)),
        timeout_seconds=_number_setting(ctx, "crawl_timeout_seconds", 30, 5, 90),
    )
    extract_provider = Crawl4AIWebSearchProvider(crawl_client)
    legacy_extract_provider = Crawl4AIWebSearchProvider(
        crawl_client,
        provider_name="crawl4ai",
        provider_display_name="Crawl4AI Compact (compatibility alias)",
    )

    ctx.register_web_search_provider(search_provider)
    ctx.register_web_search_provider(extract_provider)
    # Keep the v1.0 name live while setup atomically migrates the configured
    # backend. It uses the same bounded implementation and shared HTTP client.
    ctx.register_web_search_provider(legacy_extract_provider)
    ctx.on_unload(search_provider.close)
    ctx.on_unload(crawl_client.close)
    register_tools(
        ctx,
        open_available=extract_provider.is_available,
        research_available=lambda: (
            search_provider.is_available() and extract_provider.is_available()
        ),
    )
    ctx.register_system_prompt_section(
        "local-web.retrieval-policy",
        _WEB_RETRIEVAL_POLICY,
        position="after_memory",
        max_chars=600,
    )
