#!/usr/bin/env bash

definition_description() {
  local file="$1"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -n "$line" ]] || continue

    if [[ "$line" == \#* ]]; then
      line="$(trim "${line#\#}")"
      printf '%s\n' "${line:-(no description)}"
    else
      printf '%s\n' '(no description)'
    fi
    return 0
  done <"$file"

  printf '%s\n' '(no description)'
}

ordered_profiles() {
  local name file
  local preferred=(shell server development wsl-development)
  local emitted=()

  for name in "${preferred[@]}"; do
    file="$DOTFILES_ROOT/profiles/$name"
    [[ -f "$file" ]] || continue
    emitted+=("$name")
    printf '%s\n' "$name"
  done

  for file in "$DOTFILES_ROOT"/profiles/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    array_contains "$name" "${emitted[@]}" || printf '%s\n' "$name"
  done
}

prompt_yes_no() {
  local prompt="$1"
  local default_answer="$2"
  local output_name="$3"
  local answer suffix
  local -n output="$output_name"

  if [[ "$default_answer" == "yes" ]]; then
    suffix='[Y/n]'
  else
    suffix='[y/N]'
  fi

  while true; do
    printf '%s %s ' "$prompt" "$suffix"
    IFS= read -r answer || die "Interactive input ended"
    answer="$(trim "$answer")"
    [[ -n "$answer" ]] || answer="$default_answer"

    case "${answer,,}" in
      y | yes)
        output=1
        return 0
        ;;
      n | no)
        output=0
        return 0
        ;;
      *) printf 'Enter y or n.\n' ;;
    esac
  done
}

interactive_select_options() {
  local profile_names=()
  local file description answer choice index
  local install_packages=0

  mapfile -t profile_names < <(ordered_profiles)
  ((${#profile_names[@]} > 0)) || die "No profiles are available"

  printf 'Dotfiles installer\n\n'
  printf 'Select a profile:\n'
  for index in "${!profile_names[@]}"; do
    file="$DOTFILES_ROOT/profiles/${profile_names[$index]}"
    description="$(definition_description "$file")"
    printf '  %d) %-16s %s\n' \
      "$((index + 1))" "${profile_names[$index]}" "$description"
  done

  while true; do
    printf 'Profile [1]: '
    IFS= read -r answer || die "Interactive input ended"
    answer="$(trim "$answer")"
    [[ -n "$answer" ]] || answer=1

    if [[ "$answer" =~ ^[0-9]+$ ]]; then
      choice=$((10#$answer))
      if ((choice >= 1 && choice <= ${#profile_names[@]})); then
        PROFILE="${profile_names[$((choice - 1))]}"
        break
      fi
    fi
    printf 'Enter a number from 1 to %d.\n' "${#profile_names[@]}"
  done

  printf '\n'
  prompt_yes_no 'Install required native and Homebrew packages?' yes install_packages
  [[ "$install_packages" == "1" ]] || NO_PACKAGES=1
  prompt_yes_no 'Change the login shell to Zsh after installation?' no SET_SHELL
}

interactive_confirm() {
  local confirmed=0

  printf '\nResolved plan:\n'
  printf 'Profile:           %s\n' "$PROFILE"
  print_resolution
  if [[ "$NO_PACKAGES" == "1" ]]; then
    printf 'Packages:          skip\n'
  else
    printf 'Packages:          install missing packages\n'
  fi
  if [[ "$SET_SHELL" == "1" ]]; then
    printf 'Login shell:       change to Zsh\n'
  else
    printf 'Login shell:       leave unchanged\n'
  fi
  printf '\n'

  prompt_yes_no 'Apply this plan?' no confirmed
  if [[ "$confirmed" != "1" ]]; then
    info "Installation cancelled; no changes were made"
    exit 0
  fi
}
