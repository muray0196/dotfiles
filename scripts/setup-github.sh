#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_ROOT
# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"

require_command gh
require_command git
require_command ssh-keygen

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"
GITHUB_REMOTE="${GITHUB_REMOTE:-git@github.com:muray0196/dotfiles.git}"

mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  [[ ! -f "$SSH_KEY_PATH.pub" ]] || die "Public key exists but private key is missing: $SSH_KEY_PATH"
  info "Creating SSH key: $SSH_KEY_PATH"
  if [[ -v SSH_KEY_PASSPHRASE ]]; then
    ssh-keygen -t ed25519 -C "${USER:-user}@$(hostname)" -f "$SSH_KEY_PATH" -N "$SSH_KEY_PASSPHRASE"
  else
    ssh-keygen -t ed25519 -C "${USER:-user}@$(hostname)" -f "$SSH_KEY_PATH"
  fi
elif [[ ! -f "$SSH_KEY_PATH.pub" ]]; then
  ssh-keygen -y -f "$SSH_KEY_PATH" >"$SSH_KEY_PATH.pub"
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
fi

SSH_PUBLIC_KEY="$(cut -d ' ' -f 1-2 "$SSH_KEY_PATH.pub")"
REGISTERED_KEYS="$(gh api user/keys --paginate --jq '.[].key')"
if printf '%s\n' "$REGISTERED_KEYS" | grep -Fqx "$SSH_PUBLIC_KEY"; then
  info "SSH key is already registered with GitHub"
else
  gh ssh-key add "$SSH_KEY_PATH.pub" --title "$(hostname)-dotfiles"
fi

if git -C "$DOTFILES_ROOT" remote get-url origin >/dev/null 2>&1; then
  git -C "$DOTFILES_ROOT" remote set-url origin "$GITHUB_REMOTE"
else
  git -C "$DOTFILES_ROOT" remote add origin "$GITHUB_REMOTE"
fi

info "GitHub authentication and origin remote are configured"
