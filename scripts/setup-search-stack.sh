#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$DOTFILES_ROOT/services/search-stack"
STACK_DIR="${SEARCH_STACK_DIR:-$HOME/services/search-stack}"

# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=../lib/platform.sh
source "$DOTFILES_ROOT/lib/platform.sh"

detect_platform
require_command docker

if ! command -v openssl >/dev/null 2>&1; then
  info "Installing OpenSSL for search-stack secret generation"
  case "$PLATFORM_ID" in
    ubuntu)
      sudo apt-get update
      sudo apt-get install -y openssl
      ;;
    arch)
      sudo pacman -S --needed --noconfirm openssl
      ;;
  esac
fi
require_command openssl

docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is unavailable"

mkdir -p "$STACK_DIR"
cp -a "$SOURCE_DIR/." "$STACK_DIR/"

existing_searxng_secret=""
existing_crawl4ai_token=""
existing_crawl4ai_secret_key=""
existing_searxng_host_port=""
if [[ -r "$STACK_DIR/.env" ]]; then
  existing_searxng_secret="$(sed -n 's/^SEARXNG_SECRET=//p' "$STACK_DIR/.env" | head -n 1)"
  existing_crawl4ai_token="$(sed -n 's/^CRAWL4AI_API_TOKEN=//p' "$STACK_DIR/.env" | head -n 1)"
  existing_crawl4ai_secret_key="$(sed -n 's/^CRAWL4AI_SECRET_KEY=//p' "$STACK_DIR/.env" | head -n 1)"
  existing_searxng_host_port="$(sed -n 's/^SEARXNG_HOST_PORT=//p' "$STACK_DIR/.env" | head -n 1)"
fi
SEARXNG_SECRET="${SEARXNG_SECRET:-${existing_searxng_secret:-$(openssl rand -hex 32)}}"
CRAWL4AI_API_TOKEN="${CRAWL4AI_API_TOKEN:-${existing_crawl4ai_token:-$(openssl rand -hex 32)}}"
CRAWL4AI_SECRET_KEY="${CRAWL4AI_SECRET_KEY:-${existing_crawl4ai_secret_key:-$(openssl rand -hex 32)}}"
SEARXNG_HOST_PORT="${SEARXNG_HOST_PORT:-${existing_searxng_host_port:-8888}}"
{
  printf 'SEARXNG_SECRET=%s\n' "$SEARXNG_SECRET"
  printf 'CRAWL4AI_API_TOKEN=%s\n' "$CRAWL4AI_API_TOKEN"
  printf 'CRAWL4AI_SECRET_KEY=%s\n' "$CRAWL4AI_SECRET_KEY"
  printf 'SEARXNG_HOST_PORT=%s\n' "$SEARXNG_HOST_PORT"
} >"$STACK_DIR/.env"
chmod 0600 "$STACK_DIR/.env"
sed -i "s/__SEARXNG_SECRET__/$SEARXNG_SECRET/g" "$STACK_DIR/searxng/settings.yml"

cd "$STACK_DIR"
docker compose pull
docker compose up -d
docker compose ps

info "Search stack setup complete: $STACK_DIR"
