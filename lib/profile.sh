#!/usr/bin/env bash

SELECTED_MODULES=()
NATIVE_GROUPS=()
BREW_GROUPS=()
STOW_MODULES=()
ACTIONS=()

declare -A PROFILE_STATE=()
declare -A MODULE_STATE=()

reset_resolution() {
  SELECTED_MODULES=()
  NATIVE_GROUPS=()
  BREW_GROUPS=()
  STOW_MODULES=()
  ACTIONS=()
  PROFILE_STATE=()
  MODULE_STATE=()
}

read_definition_lines() {
  local file="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(trim "$line")"
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done <"$file"
}

resolve_profile() {
  local name="$1"
  validate_name "$name"

  local file="$DOTFILES_ROOT/profiles/$name"
  [[ -f "$file" ]] || die "Unknown profile: $name"

  case "${PROFILE_STATE[$name]:-}" in
    done) return 0 ;;
    active) die "Profile dependency cycle detected at: $name" ;;
  esac
  PROFILE_STATE[$name]="active"

  local line dependency
  while IFS= read -r line; do
    if [[ "$line" == profile:* ]]; then
      dependency="${line#profile:}"
      validate_name "$dependency"
      resolve_profile "$dependency"
    else
      resolve_module "$line"
    fi
  done < <(read_definition_lines "$file")

  PROFILE_STATE[$name]="done"
}

resolve_module() {
  local name="$1"
  validate_name "$name"

  local manifest="$DOTFILES_ROOT/manifests/$name"
  [[ -f "$manifest" ]] || die "Unknown module: $name"

  case "${MODULE_STATE[$name]:-}" in
    done) return 0 ;;
    active) die "Module dependency cycle detected at: $name" ;;
  esac
  MODULE_STATE[$name]="active"

  add_unique SELECTED_MODULES "$name"

  local line kind value
  while IFS= read -r line; do
    [[ "$line" == *:* ]] || die "Invalid manifest entry in $name: $line"
    kind="${line%%:*}"
    value="${line#*:}"
    validate_name "$value"

    case "$kind" in
      require) resolve_module "$value" ;;
      native) add_unique NATIVE_GROUPS "$value" ;;
      brew) add_unique BREW_GROUPS "$value" ;;
      stow) add_unique STOW_MODULES "$value" ;;
      action) add_unique ACTIONS "$value" ;;
      *) die "Unknown manifest directive '$kind' in module '$name'" ;;
    esac
  done < <(read_definition_lines "$manifest")

  MODULE_STATE[$name]="done"
}

list_configurations() {
  local file

  printf 'Profiles:\n'
  for file in "$DOTFILES_ROOT"/profiles/*; do
    [[ -f "$file" ]] || continue
    printf '  %s\n' "$(basename "$file")"
  done

  printf '\nModules:\n'
  for file in "$DOTFILES_ROOT"/manifests/*; do
    [[ -f "$file" ]] || continue
    printf '  %s\n' "$(basename "$file")"
  done
}

print_resolution() {
  printf 'Selected modules: %s\n' "${SELECTED_MODULES[*]:-(none)}"
  printf 'Native groups:    %s\n' "${NATIVE_GROUPS[*]:-(none)}"
  printf 'Brew groups:      %s\n' "${BREW_GROUPS[*]:-(none)}"
  printf 'Stow modules:     %s\n' "${STOW_MODULES[*]:-(none)}"
  printf 'Actions:          %s\n' "${ACTIONS[*]:-(none)}"
}
