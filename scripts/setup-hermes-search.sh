#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_SOURCE="$DOTFILES_ROOT/services/search-stack/hermes-plugin/crawl4ai"
STACK_DIR="${SEARCH_STACK_DIR:-$HOME/services/search-stack}"

# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"

require_command hermes
[[ -r "$STACK_DIR/.env" ]] || die "Search-stack environment is unavailable: $STACK_DIR/.env"
grep -q '^CRAWL4AI_API_TOKEN=.' "$STACK_DIR/.env" || die "Crawl4AI API token is missing"

searxng_host_port="$(sed -n 's/^SEARXNG_HOST_PORT=//p' "$STACK_DIR/.env" | head -n 1)"
[[ "$searxng_host_port" =~ ^[0-9]+$ ]] || die "Invalid SearXNG host port: $searxng_host_port"

hermes_config_path="$(hermes config path)"
hermes_home_dir="$(dirname -- "$hermes_config_path")"
hermes_python="$hermes_home_dir/hermes-agent/venv/bin/python"
plugin_target="$hermes_home_dir/plugins/web/crawl4ai"

[[ -x "$hermes_python" ]] || die "Hermes Python environment is unavailable: $hermes_python"

mkdir -p "$plugin_target"
cp -a "$PLUGIN_SOURCE/." "$plugin_target/"

hermes plugins enable web/crawl4ai --no-allow-tool-override
"$hermes_python" -c \
  'import sys; from hermes_cli.config import save_env_value; save_env_value("SEARXNG_URL", sys.argv[1])' \
  "http://127.0.0.1:$searxng_host_port"
# Remove the config.yaml form written by older versions of this setup script.
hermes config unset SEARXNG_URL >/dev/null 2>&1 || true
hermes config unset plugins.entries.web-crawl4ai >/dev/null 2>&1 || true
hermes config set web.search_backend searxng
hermes config set web.extract_backend crawl4ai
hermes config set --force plugins.entries.web/crawl4ai.settings.base_url "http://127.0.0.1:11235"
hermes config set --force plugins.entries.web/crawl4ai.settings.env_file "$STACK_DIR/.env"

hermes plugins doctor --ci web/crawl4ai
info "Hermes web search uses SearXNG; web extraction uses Crawl4AI"
