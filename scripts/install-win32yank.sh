#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_ROOT
# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=../lib/platform.sh
source "$DOTFILES_ROOT/lib/platform.sh"

detect_platform
is_wsl || die "win32yank is only installed under WSL"

case "$(uname -m)" in
  x86_64) archive="win32yank-x64.zip" ;;
  *) die "Unsupported architecture for the inherited win32yank binary: $(uname -m)" ;;
esac

version="${WIN32YANK_VERSION:-0.1.1}"
url="https://github.com/equalsraf/win32yank/releases/download/v${version}/${archive}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

require_command curl
require_command unzip
mkdir -p "$HOME/.local/bin"

info "Installing win32yank v$version to ~/.local/bin"
curl -fL "$url" -o "$tmp_dir/$archive"
unzip -p "$tmp_dir/$archive" win32yank.exe >"$HOME/.local/bin/win32yank.exe"
chmod 0755 "$HOME/.local/bin/win32yank.exe"
