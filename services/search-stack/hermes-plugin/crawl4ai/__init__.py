"""Hermes web-extract provider backed by the local Crawl4AI service."""

from __future__ import annotations

from pathlib import Path

from .provider import Crawl4AIWebSearchProvider


def register(ctx) -> None:
    """Register Crawl4AI as a Hermes web extraction backend."""
    base_url = ctx.get_config("base_url", default="http://127.0.0.1:11235")
    env_file = ctx.get_config(
        "env_file",
        default=str(Path.home() / "services/search-stack/.env"),
    )
    ctx.register_web_search_provider(
        Crawl4AIWebSearchProvider(
            base_url=str(base_url),
            env_file=Path(str(env_file)),
        )
    )
