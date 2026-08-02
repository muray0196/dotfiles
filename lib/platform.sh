#!/usr/bin/env bash

PLATFORM_ID=""
PLATFORM_VERSION=""
IS_WSL=0
BREW_BIN=""

is_wsl() {
  [[ "$IS_WSL" == "1" ]]
}

detect_platform() {
  if [[ -n "${DOTFILES_DISTRO_OVERRIDE:-}" ]]; then
    PLATFORM_ID="$DOTFILES_DISTRO_OVERRIDE"
    PLATFORM_VERSION="override"
  else
    [[ -r /etc/os-release ]] || die "/etc/os-release is missing"
    # shellcheck disable=SC1091
    source /etc/os-release
    PLATFORM_ID="${ID:-}"
    PLATFORM_VERSION="${VERSION_ID:-unknown}"
  fi

  case "$PLATFORM_ID" in
    ubuntu | arch) ;;
    *) die "Unsupported distribution: ${PLATFORM_ID:-unknown}. Supported: Ubuntu, Arch Linux" ;;
  esac

  if [[ -n "${WSL_DISTRO_NAME:-}" ]] ||
    grep -qiE '(microsoft|wsl)' /proc/sys/kernel/osrelease 2>/dev/null; then
    IS_WSL=1
  fi
}

find_brew() {
  local candidate

  if command -v brew >/dev/null 2>&1; then
    BREW_BIN="$(command -v brew)"
    return 0
  fi

  for candidate in \
    /home/linuxbrew/.linuxbrew/bin/brew \
    "$HOME/.linuxbrew/bin/brew" \
    /opt/homebrew/bin/brew; do
    if [[ -x "$candidate" ]]; then
      BREW_BIN="$candidate"
      return 0
    fi
  done

  return 1
}

load_brew_environment() {
  find_brew || return 1
  eval "$("$BREW_BIN" shellenv)"
  BREW_BIN="$(command -v brew)"
}
