"""Hermes staged web retrieval backed by local SearXNG and Crawl4AI."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .provider import (
    Crawl4AIClient,
    Crawl4AIWebSearchProvider,
    FastSearXNGWebSearchProvider,
)
from .tools import (
    build_extract_limit_middleware,
    build_extract_result_limiter,
    build_search_context_middleware,
    register_tools,
)


_WEB_RETRIEVAL_POLICY = """Web retrieval:
- Ordinary lookup: use web_search with limit 3. SearXNG discovers URLs; Crawl4AI concurrently returns bounded relevant page passages.
- For deep/thorough/exhaustive/しっかり/深く/multi-source requests, run up to three focused web_search queries. Each result is already Crawl4AI-optimized.
- For exact verification after search, invoke deferred web_open through tool_call; use two URLs only to corroborate.
- Never call direct web_extract; it is blocked for context safety.
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
        engines=str(ctx.get_config("fast_engines", default="bing")),
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
    extract_char_limit = int(
        _number_setting(ctx, "extract_char_limit", 4000, 2000, 20000)
    )
    ctx.register_middleware(
        "tool_request",
        build_extract_limit_middleware(extract_char_limit),
    )
    ctx.register_middleware(
        "tool_execution",
        build_search_context_middleware(
            ctx.dispatch_tool,
            max_results=int(
                _number_setting(ctx, "search_result_limit", 3, 1, 5)
            ),
            total_chars=int(
                _number_setting(ctx, "search_context_limit", 3600, 1200, 8000)
            ),
        ),
    )
    ctx.register_hook(
        "transform_tool_result",
        build_extract_result_limiter(extract_char_limit),
    )
    register_tools(
        ctx,
        open_available=extract_provider.is_available,
    )
    ctx.register_system_prompt_section(
        "local-web.retrieval-policy",
        _WEB_RETRIEVAL_POLICY,
        position="after_memory",
        max_chars=900,
    )
