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
    fedora)
      sudo dnf install -y openssl
      ;;
  esac
fi
require_command openssl

docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is unavailable"

mkdir -p "$STACK_DIR"
cp -a "$SOURCE_DIR/." "$STACK_DIR/"

existing_secret=""
if [[ -r "$STACK_DIR/.env" ]]; then
  existing_secret="$(sed -n 's/^SEARXNG_SECRET=//p' "$STACK_DIR/.env" | head -n 1)"
fi
SEARXNG_SECRET="${SEARXNG_SECRET:-${existing_secret:-$(openssl rand -hex 32)}}"
printf 'SEARXNG_SECRET=%s\n' "$SEARXNG_SECRET" >"$STACK_DIR/.env"
chmod 0600 "$STACK_DIR/.env"
sed -i "s/__SEARXNG_SECRET__/$SEARXNG_SECRET/g" "$STACK_DIR/searxng/settings.yml"

cd "$STACK_DIR"
docker compose pull
docker compose up -d
docker compose ps

info "Search stack setup complete: $STACK_DIR"
