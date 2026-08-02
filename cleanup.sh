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
SYSTEM_CACHE=0
BACKUP_MAX_AGE=""

usage() {
  cat <<'USAGE'
Usage: ./cleanup.sh [--profile NAME] [--module NAME ...] [options]

Options:
  --profile NAME              Clean resources for a profile
  --module NAME               Include one module; repeatable
  --dry-run                   Show cleanup operations without applying them
  --system-cache              Clean the apt or pacman package cache
  --backups-older-than AGE    Delete managed backups older than AGE (for example, 30d)
  -h, --help                  Show this help

Without --profile or --module, the last successfully applied selection is used.
Native packages are never autoremoved.
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
    --system-cache)
      SYSTEM_CACHE=1
      shift
      ;;
    --backups-older-than)
      (($# >= 2)) || die "--backups-older-than requires a value"
      BACKUP_MAX_AGE="$2"
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
  load_installation_selection PROFILE MODULE_ARGS ||
    die "No saved installation selection. Run install.sh or specify --profile."
fi

reset_resolution
[[ -n "$PROFILE" ]] && resolve_profile "$PROFILE"
for module in "${MODULE_ARGS[@]}"; do
  resolve_module "$module"
done

detect_platform
info "Platform: $PLATFORM_ID $PLATFORM_VERSION"

expected_paths=()
collect_resolved_managed_paths expected_paths
reconcile_stale_managed_links "$DRY_RUN" expected_paths

cleanup_brew_packages

if [[ "$SYSTEM_CACHE" == "1" ]]; then
  info "Cleaning the native package cache"
  case "$PLATFORM_ID" in
    ubuntu) run sudo apt-get clean ;;
    arch) run sudo pacman -Sc --noconfirm ;;
  esac
fi

if [[ -n "$BACKUP_MAX_AGE" ]]; then
  prune_old_backups "$BACKUP_MAX_AGE" "$DRY_RUN"
fi

if [[ "$DRY_RUN" != "1" && -f "$DOTFILES_MANAGED_PATHS_FILE" ]]; then
  write_managed_paths_state "${expected_paths[@]}"
fi

info "Cleanup complete"
