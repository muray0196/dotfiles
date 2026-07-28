#!/usr/bin/env bash

collect_native_packages() {
  local output_array_name="$1"
  local -n output_array="$output_array_name"
  local group file line

  output_array=()
  for group in "${NATIVE_GROUPS[@]}"; do
    file="$DOTFILES_ROOT/packages/native/$PLATFORM_ID/$group.txt"
    [[ -f "$file" ]] || die "Native package group is missing: $PLATFORM_ID/$group"

    while IFS= read -r line; do
      add_unique "$output_array_name" "$line"
    done < <(read_definition_lines "$file")
  done
}

install_native_packages() {
  local packages=()
  collect_native_packages packages
  ((${#packages[@]} > 0)) || return 0

  info "Installing native packages for $PLATFORM_ID $PLATFORM_VERSION"
  case "$PLATFORM_ID" in
    ubuntu)
      run sudo apt-get update
      run sudo apt-get install -y "${packages[@]}"
      ;;
    fedora)
      run sudo dnf install -y "${packages[@]}"
      ;;
  esac
}

ensure_homebrew() {
  if load_brew_environment; then
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "Homebrew is not installed; it would be installed non-interactively"
    printf '[dry-run] NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
    BREW_BIN="brew"
    return 0
  fi

  require_command curl
  info "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew_environment || die "Homebrew installation completed, but brew could not be found"
}

install_brew_packages() {
  ((${#BREW_GROUPS[@]} > 0)) || return 0
  ensure_homebrew

  local group file
  for group in "${BREW_GROUPS[@]}"; do
    file="$DOTFILES_ROOT/packages/brew/$group.Brewfile"
    [[ -f "$file" ]] || die "Brewfile is missing: $group"
    info "Applying Brewfile: $group"
    run "$BREW_BIN" bundle --file="$file"
  done
}

update_brew_packages() {
  ((${#BREW_GROUPS[@]} > 0)) || return 0
  if ! load_brew_environment; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      BREW_BIN="brew"
    else
      die "Homebrew is not installed"
    fi
  fi

  run "$BREW_BIN" update

  local group file
  for group in "${BREW_GROUPS[@]}"; do
    file="$DOTFILES_ROOT/packages/brew/$group.Brewfile"
    [[ -f "$file" ]] || die "Brewfile is missing: $group"
    info "Upgrading Brewfile: $group"
    run "$BREW_BIN" bundle upgrade --file="$file"
  done
}
