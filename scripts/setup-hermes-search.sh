#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_SOURCE="$DOTFILES_ROOT/services/search-stack/hermes-plugin/crawl4ai"
STACK_DIR="${SEARCH_STACK_DIR:-$HOME/services/search-stack}"

# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"

require_command hermes
require_command flock
[[ -r "$STACK_DIR/.env" ]] || die "Search-stack environment is unavailable: $STACK_DIR/.env"
grep -q '^CRAWL4AI_API_TOKEN=.' "$STACK_DIR/.env" || die "Crawl4AI API token is missing"

searxng_host_port="$(sed -n 's/^SEARXNG_HOST_PORT=//p' "$STACK_DIR/.env" | head -n 1)"
[[ "$searxng_host_port" =~ ^[0-9]+$ ]] || die "Invalid SearXNG host port: $searxng_host_port"

hermes_config_path="$(hermes config path)"
hermes_home_dir="$(dirname -- "$hermes_config_path")"
hermes_python="$hermes_home_dir/hermes-agent/venv/bin/python"
plugin_target="$hermes_home_dir/plugins/web/crawl4ai"

[[ -x "$hermes_python" ]] || die "Hermes Python environment is unavailable: $hermes_python"

# Serialize the full preflight/install/config transaction. Directory exchange
# is atomic for readers, but a second installer must not snapshot or roll back
# across the first installer's in-flight config changes.
exec {search_setup_lock_fd}>"$hermes_home_dir/.search-setup.lock"
flock -n "$search_setup_lock_fd" || die "Another Hermes search setup is running"

# Validate the source package before replacing the working installation.
hermes plugins doctor --ci "$PLUGIN_SOURCE"

# Prove the live alias before replacing plugin files or changing Hermes config.
# SearXNG silently falls back to its default engines for an unknown engine name,
# so both the configured name and per-result engine attribution are required.
"$hermes_python" - "http://127.0.0.1:$searxng_host_port" <<'PY'
import json
import sys
from urllib.parse import urlencode
from urllib.request import urlopen

base_url = sys.argv[1].rstrip("/")
fast_engine = "google"
fallback_engine = "duckduckgo web"
fallback_shortcut = "ddgw"
with urlopen(f"{base_url}/config", timeout=5) as response:
    config = json.load(response)
loaded_engines = {
    engine.get("name"): engine.get("shortcut")
    for engine in config.get("engines", [])
    if isinstance(engine, dict)
}
missing = {fast_engine, fallback_engine} - loaded_engines.keys()
if missing:
    raise SystemExit(
        f"SearXNG required engines are not loaded: {', '.join(sorted(missing))}"
    )


def search_engine(engine_name):
    params = urlencode(
        {
            "q": "Example Domain",
            "format": "json",
            "engines": engine_name,
        }
    )
    with urlopen(f"{base_url}/search?{params}", timeout=10) as response:
        search = json.load(response)
    return search.get("results", [])


fast_results = search_engine(fast_engine)
if not fast_results:
    raise SystemExit("SearXNG Google fast engine returned no preflight results")
for engine_name, results in ((fast_engine, fast_results),):
    for result in results:
        engines = result.get("engines", []) if isinstance(result, dict) else []
        engine = result.get("engine") if isinstance(result, dict) else None
        if engine_name != engine and engine_name not in engines:
            raise SystemExit(
                f"SearXNG {engine_name} preflight returned another engine"
            )
if loaded_engines[fallback_engine] != fallback_shortcut:
    raise SystemExit(
        "SearXNG DuckDuckGo Web fallback shortcut is not !ddgw"
    )
PY

plugin_parent="$(dirname -- "$plugin_target")"
plugin_stage=""
plugin_backup=""
transaction_dir=""
config_backup=""
plugin_installed=0
plugin_exchanged=0
transaction_started=0
transaction_committed=0
preserve_transaction_dir=0

restore_hermes_config() {
  local restore_stage="$transaction_dir/config.yaml.restore"
  cp -p -- "$config_backup" "$restore_stage"
  mv -f -- "$restore_stage" "$hermes_config_path"
}

remove_transaction_temp() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  case "$path" in
    "$hermes_home_dir"/.search-setup-*) rm -rf -- "$path" ;;
    *) warn "Refusing to remove unexpected transaction path: $path" ;;
  esac
}

exchange_plugin_dirs() {
  "$hermes_python" - "$1" "$2" <<'PY'
import ctypes
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [
    ctypes.c_int,
    ctypes.c_char_p,
    ctypes.c_int,
    ctypes.c_char_p,
    ctypes.c_uint,
]
renameat2.restype = ctypes.c_int
at_fdcwd = -100
rename_exchange = 2
if renameat2(
    at_fdcwd,
    os.fsencode(sys.argv[1]),
    at_fdcwd,
    os.fsencode(sys.argv[2]),
    rename_exchange,
) != 0:
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
PY
}

finish_transaction() {
  local status=$?
  trap - EXIT INT TERM
  if ((transaction_started == 1 && transaction_committed == 0)); then
    warn "Hermes search setup failed; restoring the previous plugin and config"
    if ((plugin_exchanged == 1)) && \
      [[ -e "$plugin_target" || -L "$plugin_target" ]] && \
      [[ -e "$plugin_backup" || -L "$plugin_backup" ]]; then
      if ! exchange_plugin_dirs "$plugin_backup" "$plugin_target"; then
        warn "Could not restore the previous plugin; it remains at: $plugin_backup"
        # Preserve the only known-good copy for manual recovery.
        preserve_transaction_dir=1
      fi
    elif ((plugin_installed == 1)) && \
      [[ -e "$plugin_target" || -L "$plugin_target" ]]; then
      rm -rf -- "$plugin_target"
    fi
    if ! restore_hermes_config; then
      warn "Could not restore Hermes config; backup remains at: $config_backup"
      preserve_transaction_dir=1
    fi
  fi
  if ((preserve_transaction_dir == 0)); then
    remove_transaction_temp "$transaction_dir"
  fi
  exit "$status"
}

trap finish_transaction EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$plugin_parent"
transaction_dir="$(mktemp -d "$hermes_home_dir/.search-setup-XXXXXX")"
plugin_stage="$transaction_dir/crawl4ai-new"
config_backup="$transaction_dir/config.yaml.before"
mkdir -p "$plugin_stage"
cp -a "$PLUGIN_SOURCE/." "$plugin_stage/"
cp -p -- "$hermes_config_path" "$config_backup"
transaction_started=1

if [[ -e "$plugin_target" || -L "$plugin_target" ]]; then
  # renameat2(RENAME_EXCHANGE) makes the old/new package swap indivisible to
  # concurrent Hermes processes. Signals stay masked across the syscall and
  # bookkeeping assignments so rollback state cannot observe a half-step.
  trap '' INT TERM
  if exchange_plugin_dirs "$plugin_stage" "$plugin_target"; then
    plugin_backup="$plugin_stage"
    plugin_stage=""
    plugin_installed=1
    plugin_exchanged=1
    trap 'exit 130' INT
    trap 'exit 143' TERM
  else
    exchange_status=$?
    trap 'exit 130' INT
    trap 'exit 143' TERM
    exit "$exchange_status"
  fi
else
  trap '' INT TERM
  if mv -- "$plugin_stage" "$plugin_target"; then
    plugin_stage=""
    plugin_installed=1
    trap 'exit 130' INT
    trap 'exit 143' TERM
  else
    install_status=$?
    trap 'exit 130' INT
    trap 'exit 143' TERM
    exit "$install_status"
  fi
fi

# Validate the exact installed directory before changing any backend selection.
hermes plugins doctor --ci "$plugin_target"

hermes plugins enable web/crawl4ai --no-allow-tool-override
hermes config set --force plugins.entries.web/crawl4ai.settings.base_url "http://127.0.0.1:11235"
hermes config set --force plugins.entries.web/crawl4ai.settings.searxng_url "http://127.0.0.1:$searxng_host_port"
hermes config set --force plugins.entries.web/crawl4ai.settings.fast_engines "google"
hermes config set --force plugins.entries.web/crawl4ai.settings.fallback_query_prefix "!ddgw"
hermes config set --force plugins.entries.web/crawl4ai.settings.extract_char_limit 4000
hermes config set --force plugins.entries.web/crawl4ai.settings.search_result_limit 3
hermes config set --force plugins.entries.web/crawl4ai.settings.env_file "$STACK_DIR/.env"
hermes config unset plugins.entries.web/crawl4ai.settings.search_context_limit >/dev/null 2>&1 || true

hermes plugins doctor --ci web/crawl4ai

# Switch active backends only after the plugin and live SearXNG profile pass.
hermes config set web.extract_char_limit 4000
hermes config set web.keyless_rescue false
hermes config set web.extract_backend crawl4ai-compact
hermes config set web.search_backend searxng-fast

transaction_committed=1
remove_transaction_temp "$transaction_dir"
transaction_dir=""
plugin_backup=""

# Maintain legacy environment compatibility only after the new route is live.
if ! "$hermes_python" -c \
  'import sys; from hermes_cli.config import save_env_value; save_env_value("SEARXNG_URL", sys.argv[1])' \
  "http://127.0.0.1:$searxng_host_port"; then
  warn "Could not save the legacy SEARXNG_URL environment value"
fi
# Remove config.yaml forms written by older versions of this setup script.
hermes config unset SEARXNG_URL >/dev/null 2>&1 || true
hermes config unset plugins.entries.web-crawl4ai >/dev/null 2>&1 || true
info "Hermes uses fast SearXNG discovery with Crawl4AI page retrieval"
