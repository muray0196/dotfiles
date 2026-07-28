#!/usr/bin/env bash

BACKUP_STAMP="$(date '+%Y%m%d-%H%M%S')-$$"
BACKUP_ROOT="${DOTFILES_BACKUP_DIR:-$HOME/.local/state/dotfiles-linux/backups}/$BACKUP_STAMP"
declare -A BACKED_UP_PATHS=()

relative_to_home() {
  local path="$1"
  [[ "$path" == "$HOME"/* ]] || die "Path is outside HOME: $path"
  printf '%s' "${path#"$HOME"/}"
}

same_target() {
  local target="$1"
  local source="$2"
  [[ -e "$target" || -L "$target" ]] || return 1
  [[ "$(readlink -f -- "$target" 2>/dev/null || true)" == "$(readlink -f -- "$source" 2>/dev/null || true)" ]]
}

find_conflict_path() {
  local relative="$1"
  local source="$2"
  local current="$HOME"
  local -a parts=()
  local index

  IFS='/' read -r -a parts <<<"$relative"

  for ((index = 0; index < ${#parts[@]} - 1; index++)); do
    current="$current/${parts[$index]}"
    if [[ -L "$current" ]] || [[ -e "$current" && ! -d "$current" ]]; then
      same_target "$current" "$source" && return 1
      printf '%s' "$current"
      return 0
    fi
  done

  current="$HOME/$relative"
  if [[ -e "$current" || -L "$current" ]]; then
    same_target "$current" "$source" && return 1
    printf '%s' "$current"
    return 0
  fi

  return 1
}

backup_path() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  [[ -z "${BACKED_UP_PATHS[$path]:-}" ]] || return 0

  local relative destination
  relative="$(relative_to_home "$path")"
  destination="$BACKUP_ROOT/$relative"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '[dry-run] backup %q -> %q\n' "$path" "$destination"
  else
    mkdir -p "$(dirname "$destination")"
    mv -- "$path" "$destination"
    info "Backed up $path to $destination"
  fi
  BACKED_UP_PATHS[$path]=1
}

backup_module_conflicts() {
  local module="$1"
  local module_dir="$DOTFILES_ROOT/modules/$module"
  [[ -d "$module_dir" ]] || die "Stow module is missing: $module"

  local source relative conflict
  while IFS= read -r -d '' source; do
    relative="${source#"$module_dir"/}"
    conflict="$(find_conflict_path "$relative" "$source" || true)"
    [[ -n "$conflict" ]] && backup_path "$conflict"
  done < <(find "$module_dir" \( -type f -o -type l \) -print0)
  return 0
}

deploy_modules() {
  ((${#STOW_MODULES[@]} > 0)) || return 0

  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    require_command stow
  fi

  local module
  for module in "${STOW_MODULES[@]}"; do
    backup_module_conflicts "$module"
    info "Deploying module: $module"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      print_command stow --restow --no-folding --dir="$DOTFILES_ROOT/modules" --target="$HOME" "$module"
    else
      stow --restow --no-folding --dir="$DOTFILES_ROOT/modules" --target="$HOME" "$module"
    fi
  done
}

unstow_modules() {
  ((${#STOW_MODULES[@]} > 0)) || return 0

  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    require_command stow
  fi

  local module
  for module in "${STOW_MODULES[@]}"; do
    info "Removing links for module: $module"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      print_command stow --delete --no-folding --dir="$DOTFILES_ROOT/modules" --target="$HOME" "$module"
    else
      stow --delete --no-folding --dir="$DOTFILES_ROOT/modules" --target="$HOME" "$module"
    fi
  done
}
