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
# shellcheck source=lib/packages.sh
source "$DOTFILES_ROOT/lib/packages.sh"
# shellcheck source=lib/state.sh
source "$DOTFILES_ROOT/lib/state.sh"

PROFILE=""
MODULE_ARGS=()
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: ./update.sh [--profile NAME] [--module NAME ...] [--dry-run]

Updates only Homebrew packages selected by the profile/module and Sheldon
plugins. It deliberately does not run apt upgrade or dnf upgrade.
Without an explicit selection, the last successfully applied selection is used.
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
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ -z "$PROFILE" && ${#MODULE_ARGS[@]} -eq 0 ]]; then
  load_installation_selection PROFILE MODULE_ARGS ||
    die "No saved installation selection. Run install.sh or specify --profile."
fi

reset_resolution
[[ -n "$PROFILE" ]] && resolve_profile "$PROFILE"
for module in "${MODULE_ARGS[@]}"; do
  resolve_module "$module"
done

detect_platform
update_brew_packages

if array_contains sheldon "${SELECTED_MODULES[@]}"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    print_command sheldon lock --update
  elif command -v sheldon >/dev/null 2>&1; then
    info "Updating Sheldon plugins"
    sheldon lock --update
  else
    warn "Sheldon is unavailable; plugin update was skipped"
  fi
fi

info "Managed user-space tools are up to date"
info "Native OS packages were not upgraded"
