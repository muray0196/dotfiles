#!/usr/bin/env bash

DOTFILES_STATE_ROOT="${DOTFILES_STATE_DIR:-$HOME/.local/state/dotfiles-linux}"
DOTFILES_SELECTION_FILE="$DOTFILES_STATE_ROOT/selection"
DOTFILES_MANAGED_PATHS_FILE="$DOTFILES_STATE_ROOT/managed-paths"

installation_state_exists() {
  [[ -f "$DOTFILES_SELECTION_FILE" ]]
}

load_installation_selection() {
  local output_profile_name="$1"
  local output_modules_name="$2"
  local -n output_profile="$output_profile_name"
  local -n output_modules="$output_modules_name"

  output_profile=""
  output_modules=()
  [[ -f "$DOTFILES_SELECTION_FILE" ]] || return 1

  local line kind value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == *:* ]] || die "Invalid installation state entry: $line"

    kind="${line%%:*}"
    value="${line#*:}"
    validate_name "$value"

    case "$kind" in
      profile)
        [[ -z "$output_profile" ]] || die "Installation state contains multiple profiles"
        output_profile="$value"
        ;;
      module) add_unique "$output_modules_name" "$value" ;;
      *) die "Unknown installation state entry: $kind" ;;
    esac
  done <"$DOTFILES_SELECTION_FILE"

  [[ -n "$output_profile" || ${#output_modules[@]} -gt 0 ]] ||
    die "Installation state is empty: $DOTFILES_SELECTION_FILE"
}

selection_to_args() {
  local output_array_name="$1"
  local -n output_array="$output_array_name"
  local saved_profile=""
  local saved_modules=()

  load_installation_selection saved_profile saved_modules || return 1

  output_array=()
  [[ -n "$saved_profile" ]] && output_array+=(--profile "$saved_profile")

  local module
  for module in "${saved_modules[@]}"; do
    output_array+=(--module "$module")
  done
}

collect_resolved_managed_paths() {
  local output_array_name="$1"
  local -n output_array="$output_array_name"
  local module module_dir source relative

  output_array=()
  for module in "${STOW_MODULES[@]}"; do
    module_dir="$DOTFILES_ROOT/modules/$module"
    [[ -d "$module_dir" ]] || die "Stow module is missing: $module"

    while IFS= read -r -d '' source; do
      relative="${source#"$module_dir"/}"
      add_unique "$output_array_name" "$relative"
    done < <(find "$module_dir" \( -type f -o -type l \) -print0 | sort -z)
  done
}

read_managed_paths() {
  local output_array_name="$1"
  local -n output_array="$output_array_name"
  local line

  output_array=()
  [[ -f "$DOTFILES_MANAGED_PATHS_FILE" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -n "$line" ]] && add_unique "$output_array_name" "$line"
  done <"$DOTFILES_MANAGED_PATHS_FILE"
}

write_state_lines() {
  local destination="$1"
  shift

  mkdir -p "$DOTFILES_STATE_ROOT"
  chmod 700 "$DOTFILES_STATE_ROOT"

  local temporary
  temporary="$(mktemp "$DOTFILES_STATE_ROOT/.state.XXXXXX")"
  printf '%s\n' "$@" >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$destination"
}

write_selection_state() {
  local profile="$1"
  shift
  local modules=("$@")
  local lines=()
  local module

  [[ -n "$profile" ]] && lines+=("profile:$profile")
  for module in "${modules[@]}"; do
    lines+=("module:$module")
  done

  ((${#lines[@]} > 0)) || die "Cannot write an empty installation selection"
  write_state_lines "$DOTFILES_SELECTION_FILE" "${lines[@]}"
}

write_managed_paths_state() {
  local paths=("$@")

  if ((${#paths[@]} > 0)); then
    write_state_lines "$DOTFILES_MANAGED_PATHS_FILE" "${paths[@]}"
  else
    mkdir -p "$DOTFILES_STATE_ROOT"
    chmod 700 "$DOTFILES_STATE_ROOT"
    : >"$DOTFILES_MANAGED_PATHS_FILE"
    chmod 600 "$DOTFILES_MANAGED_PATHS_FILE"
  fi
}

record_installation_state() {
  local profile="$1"
  shift
  local requested_modules=("$@")
  local managed_paths=()

  collect_resolved_managed_paths managed_paths

  if [[ -z "$profile" ]] && installation_state_exists; then
    local saved_profile=""
    local saved_modules=()
    local saved_paths=()
    local module path

    load_installation_selection saved_profile saved_modules
    read_managed_paths saved_paths

    for module in "${requested_modules[@]}"; do
      add_unique saved_modules "$module"
    done
    for path in "${managed_paths[@]}"; do
      add_unique saved_paths "$path"
    done

    write_selection_state "$saved_profile" "${saved_modules[@]}"
    write_managed_paths_state "${saved_paths[@]}"
    return 0
  fi

  write_selection_state "$profile" "${requested_modules[@]}"
  write_managed_paths_state "${managed_paths[@]}"
}

managed_target_points_into_repo() {
  local target="$1"
  [[ -L "$target" ]] || return 1

  local link resolved modules_root
  link="$(readlink -- "$target")"
  if [[ "$link" == /* ]]; then
    resolved="$(readlink -m -- "$link")"
  else
    resolved="$(readlink -m -- "$(dirname "$target")/$link")"
  fi
  modules_root="$(readlink -m -- "$DOTFILES_ROOT/modules")"

  [[ "$resolved" == "$modules_root"/* ]]
}

managed_relative_path_is_safe() {
  local relative="$1"
  [[ -n "$relative" ]] || return 1
  [[ "$relative" != /* ]] || return 1
  [[ "$relative" != ".." && "$relative" != ../* ]] || return 1
  [[ "$relative" != */.. && "$relative" != */../* ]] || return 1
}

reconcile_stale_managed_links() {
  local dry_run="$1"
  local expected_array_name="$2"
  local -n expected_paths_ref="$expected_array_name"
  local previous_paths=()
  local relative target

  read_managed_paths previous_paths

  for relative in "${previous_paths[@]}"; do
    array_contains "$relative" "${expected_paths_ref[@]}" && continue

    if ! managed_relative_path_is_safe "$relative"; then
      warn "Ignoring unsafe managed path from state: $relative"
      continue
    fi

    target="$HOME/$relative"
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      continue
    fi

    if managed_target_points_into_repo "$target"; then
      if [[ "$dry_run" == "1" ]]; then
        printf '[dry-run] remove stale managed link %q\n' "$target"
      else
        rm -- "$target"
        info "Removed stale managed link: ~/$relative"
      fi
    else
      warn "Leaving non-managed path untouched: ~/$relative"
    fi
  done
}

prune_old_backups() {
  local age="$1"
  local dry_run="${2:-${DRY_RUN:-0}}"
  local days="${age%d}"
  [[ "$age" =~ ^[0-9]+d?$ ]] || die "Invalid backup age: $age (expected a value such as 30d)"

  local backup_root="$DOTFILES_STATE_ROOT/backups"
  [[ -d "$backup_root" ]] || return 0

  local resolved_root resolved_home candidate resolved_candidate name
  resolved_root="$(readlink -m -- "$backup_root")"
  resolved_home="$(readlink -m -- "$HOME")"
  [[ "$resolved_root" != "/" && "$resolved_root" != "$resolved_home" ]] ||
    die "Refusing to prune unsafe backup root: $resolved_root"

  while IFS= read -r -d '' candidate; do
    resolved_candidate="$(readlink -m -- "$candidate")"
    [[ "$resolved_candidate" == "$resolved_root"/* ]] ||
      die "Refusing to prune a path outside the backup root: $resolved_candidate"

    name="$(basename "$resolved_candidate")"
    if [[ ! "$name" =~ ^[0-9]{8}-[0-9]{6}-[0-9]+$ ]]; then
      warn "Ignoring unrecognized backup directory: $resolved_candidate"
      continue
    fi

    if [[ "$dry_run" == "1" ]]; then
      printf '[dry-run] remove old backup %q\n' "$resolved_candidate"
    else
      rm -rf -- "$resolved_candidate"
      info "Removed old backup: $name"
    fi
  done < <(find "$resolved_root" -mindepth 1 -maxdepth 1 -type d -mtime "+$days" -print0)
}

clear_installation_state() {
  rm -f -- "$DOTFILES_SELECTION_FILE" "$DOTFILES_MANAGED_PATHS_FILE"
}
