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
# shellcheck source=lib/deploy.sh
source "$DOTFILES_ROOT/lib/deploy.sh"
# shellcheck source=lib/state.sh
source "$DOTFILES_ROOT/lib/state.sh"

PROFILE=""
MODULE_ARGS=()
DRY_RUN=0
NO_PACKAGES=0
SET_SHELL=0
UNSTOW=0
SHOW_LIST=0
SHOW_PLAN=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --profile NAME      Install a profile (default: shell)
  --module NAME       Install one module; repeatable and combinable with --profile
  --dry-run           Show package, backup, link, and action operations
  --no-packages       Do not install native or Homebrew packages
  --set-shell         Change the login shell to zsh after installation
  --unstow            Remove managed symlinks; do not uninstall packages
  --plan              Print the resolved modules and package groups
  --list              List available profiles and modules
  -h, --help          Show this help

Examples:
  ./install.sh --profile server --dry-run
  ./install.sh --profile server --set-shell
  ./install.sh --profile wsl-development
  ./install.sh --module starship --module tmux
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
    --no-packages)
      NO_PACKAGES=1
      shift
      ;;
    --set-shell)
      SET_SHELL=1
      shift
      ;;
    --unstow)
      UNSTOW=1
      shift
      ;;
    --plan)
      SHOW_PLAN=1
      shift
      ;;
    --list)
      SHOW_LIST=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

if [[ "$SHOW_LIST" == "1" ]]; then
  list_configurations
  exit 0
fi

if [[ -z "$PROFILE" && ${#MODULE_ARGS[@]} -eq 0 ]]; then
  PROFILE="shell"
fi

reset_resolution
if [[ -n "$PROFILE" ]]; then
  resolve_profile "$PROFILE"
fi
for module in "${MODULE_ARGS[@]}"; do
  resolve_module "$module"
done

if [[ "$SHOW_PLAN" == "1" ]]; then
  print_resolution
  [[ "$DRY_RUN" == "1" ]] || exit 0
fi

detect_platform
platform_label="$PLATFORM_ID $PLATFORM_VERSION"
is_wsl && platform_label+=" (WSL)"
info "Platform: $platform_label"

if array_contains win32yank "${ACTIONS[@]}" && ! is_wsl; then
  die "The win32yank action requires WSL. Use the development profile on native Linux."
fi

if [[ "$UNSTOW" == "1" ]]; then
  unstow_modules
  info "Managed links removed. Packages and backups were left untouched."
  exit 0
fi

if [[ "$NO_PACKAGES" != "1" ]]; then
  install_native_packages
  install_brew_packages
else
  info "Package installation skipped"
fi

# shellcheck disable=SC2034  # Read through a nameref in reconcile_stale_managed_links.
expected_managed_paths=()
collect_resolved_managed_paths expected_managed_paths
if [[ -n "$PROFILE" ]] && installation_state_exists; then
  reconcile_stale_managed_links "$DRY_RUN" expected_managed_paths
fi

deploy_modules

run_action() {
  local action="$1"
  case "$action" in
    sheldon-lock)
      if [[ "$DRY_RUN" == "1" ]]; then
        print_command sheldon lock
      elif command -v sheldon >/dev/null 2>&1; then
        info "Locking Sheldon plugins"
        sheldon lock
      else
        warn "Sheldon is unavailable; plugin lock was skipped"
      fi
      ;;
    mise-install)
      if [[ "$DRY_RUN" == "1" ]]; then
        print_command mise install node
      elif command -v mise >/dev/null 2>&1; then
        if mise which node >/dev/null 2>&1; then
          info "Configured Node.js is already installed"
        else
          info "Installing configured Node.js with mise"
          mise install node
        fi
      else
        warn "mise is unavailable; Node.js installation was skipped"
      fi
      ;;
    win32yank)
      if [[ "$DRY_RUN" == "1" ]]; then
        print_command "$DOTFILES_ROOT/scripts/install-win32yank.sh"
      else
        "$DOTFILES_ROOT/scripts/install-win32yank.sh"
      fi
      ;;
    *) die "Unknown action: $action" ;;
  esac
}

for action in "${ACTIONS[@]}"; do
  run_action "$action"
done

if [[ "$DRY_RUN" != "1" ]]; then
  record_installation_state "$PROFILE" "${MODULE_ARGS[@]}"
fi

if [[ "$SET_SHELL" == "1" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    print_command chsh -s /usr/bin/zsh
  else
    require_command zsh
    zsh_path="$(command -v zsh)"
    current_user="${USER:-$(id -un)}"
    current_shell="$(getent passwd "$current_user" | cut -d: -f7)"
    if [[ "$current_shell" == "$zsh_path" ]]; then
      info "Login shell is already $zsh_path"
    else
      info "Changing login shell to $zsh_path"
      chsh -s "$zsh_path"
    fi
  fi
fi

info "Installation complete"
if [[ "$SET_SHELL" != "1" ]]; then
  info "Start zsh manually, or rerun with --set-shell when ready"
fi
validation_args=()
[[ -n "$PROFILE" ]] && validation_args+=(--profile "$PROFILE")
for module in "${MODULE_ARGS[@]}"; do
  validation_args+=(--module "$module")
done
printf '[dotfiles] Validate with:'
printf ' %q' "$DOTFILES_ROOT/doctor.sh" "${validation_args[@]}"
printf '\n'
