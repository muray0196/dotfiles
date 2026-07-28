#!/usr/bin/env bash

# Shared helpers. The entry-point scripts enable strict mode before sourcing this file.

info() {
  printf '[dotfiles] %s\n' "$*"
}

warn() {
  printf '[dotfiles] warning: %s\n' "$*" >&2
}

die() {
  printf '[dotfiles] error: %s\n' "$*" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid name: $1"
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

add_unique() {
  local array_name="$1"
  local value="$2"
  local -n target_array="$array_name"
  local item

  for item in "${target_array[@]}"; do
    [[ "$item" == "$value" ]] && return 0
  done
  target_array+=("$value")
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}
