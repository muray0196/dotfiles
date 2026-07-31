#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

# shellcheck source=lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=lib/platform.sh
source "$DOTFILES_ROOT/lib/platform.sh"
# shellcheck source=lib/profile.sh
source "$DOTFILES_ROOT/lib/profile.sh"
# shellcheck source=lib/state.sh
source "$DOTFILES_ROOT/lib/state.sh"

PROFILE=""
MODULE_ARGS=()
FAILURES=0

usage() {
  cat <<'USAGE'
Usage: ./doctor.sh [--profile NAME] [--module NAME ...]

Without an explicit selection, the saved selection is used when available;
otherwise the shell profile is checked.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --profile)
      (($# >= 2)) || die "--profile requires a value"
      [[ -z "$PROFILE" ]] || die "Only one --profile may be specified"
      PROFILE="$2"
      shift 2
      ;;
    --module)
      (($# >= 2)) || die "--module requires a value"
      MODULE_ARGS+=("$2")
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ -z "$PROFILE" && ${#MODULE_ARGS[@]} -eq 0 ]]; then
  if ! load_installation_selection PROFILE MODULE_ARGS; then
    PROFILE="shell"
  fi
fi

reset_resolution
[[ -n "$PROFILE" ]] && resolve_profile "$PROFILE"
for module in "${MODULE_ARGS[@]}"; do
  resolve_module "$module"
done

detect_platform
export PATH="$HOME/.local/bin:$PATH"
load_brew_environment || true

pass() {
  printf '[ok]   %s\n' "$*"
}

fail() {
  printf '[fail] %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}

check_command() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    pass "command: $command_name"
  else
    fail "missing command: $command_name"
  fi
}

check_module_commands() {
  local module="$1"
  case "$module" in
    zsh) check_command zsh ;;
    starship) check_command starship ;;
    sheldon) check_command sheldon ;;
    git) check_command git ;;
    cli-tools)
      check_command fzf
      check_command rg
      ;;
    tmux) check_command tmux ;;
    fastfetch) check_command fastfetch ;;
    dev-tools)
      check_command mise
      if command -v mise >/dev/null 2>&1 && mise which node >/dev/null 2>&1; then
        pass "mise tool: node"
      else
        fail "missing mise tool: node"
      fi
      check_command uv
      check_command stylua
      ;;
    github) check_command gh ;;
    nvim) check_command nvim ;;
    win32yank) check_command win32yank.exe ;;
    zsh-abbr | dev-abbr | codex | dotfiles-cli) ;;
  esac
}

check_stow_module() {
  local module="$1"
  local module_dir="$DOTFILES_ROOT/modules/$module"
  local source relative target source_real target_real

  while IFS= read -r -d '' source; do
    relative="${source#"$module_dir"/}"
    target="$HOME/$relative"
    source_real="$(readlink -f -- "$source" 2>/dev/null || true)"
    target_real="$(readlink -f -- "$target" 2>/dev/null || true)"
    if [[ -n "$source_real" && "$source_real" == "$target_real" ]]; then
      pass "link: ~/$relative"
    else
      fail "unmanaged or incorrect link: ~/$relative"
    fi
  done < <(find "$module_dir" \( -type f -o -type l \) -print0)
}

check_starship_selection() {
  local variant="ubuntu"
  [[ "$PLATFORM_ID" == "fedora" ]] && variant="fedora"

  local target="$HOME/.config/starship.toml"
  local expected="$HOME/.config/starship/$variant.toml"
  local target_real expected_real
  target_real="$(readlink -f -- "$target" 2>/dev/null || true)"
  expected_real="$(readlink -f -- "$expected" 2>/dev/null || true)"

  if [[ -n "$expected_real" && "$target_real" == "$expected_real" ]]; then
    pass "Starship config selection: $variant"
  else
    fail "incorrect Starship config selection: expected $variant"
  fi
}

check_tmux_theme_selection() {
  local variant="ubuntu"
  [[ "$PLATFORM_ID" == "fedora" ]] && variant="fedora"

  local target="$HOME/.config/tmux/theme.conf"
  local expected="$HOME/.config/tmux/themes/$variant.conf"
  local target_real expected_real
  target_real="$(readlink -f -- "$target" 2>/dev/null || true)"
  expected_real="$(readlink -f -- "$expected" 2>/dev/null || true)"

  if [[ -n "$expected_real" && "$target_real" == "$expected_real" ]]; then
    pass "tmux theme selection: $variant"
  else
    fail "incorrect tmux theme selection: expected $variant"
  fi
}

platform_label="$PLATFORM_ID $PLATFORM_VERSION"
is_wsl && platform_label+=" (WSL)"
printf 'Platform: %s\n' "$platform_label"

if ((${#BREW_GROUPS[@]} > 0)); then
  check_command brew
fi

if ((${#STOW_MODULES[@]} > 0)); then
  check_command stow
fi

for module in "${SELECTED_MODULES[@]}"; do
  check_module_commands "$module"
done

for module in "${STOW_MODULES[@]}"; do
  check_stow_module "$module"
done

if array_contains starship-config "${ACTIONS[@]}"; then
  check_starship_selection
fi
if array_contains tmux-theme "${ACTIONS[@]}"; then
  check_tmux_theme_selection
fi

if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$DOTFILES_ROOT/modules/zsh/.zshrc"; then
    pass "zsh syntax"
  else
    fail "zsh syntax"
  fi
fi

if array_contains sheldon "${SELECTED_MODULES[@]}" && command -v sheldon >/dev/null 2>&1; then
  if sheldon source >/dev/null; then
    pass "Sheldon source generation"
  else
    fail "Sheldon source generation"
  fi
fi

if array_contains zsh-abbr "${SELECTED_MODULES[@]}" && command -v zsh >/dev/null 2>&1; then
  if zsh -lic 'whence -w abbr >/dev/null 2>&1'; then
    pass "zsh-abbr loaded"
  else
    fail "zsh-abbr did not load"
  fi
fi

if ((FAILURES > 0)); then
  printf '\nDoctor found %d problem(s).\n' "$FAILURES" >&2
  exit 1
fi

printf '\nAll checks passed.\n'
