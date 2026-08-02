#!/usr/bin/env bash

set -euo pipefail

DOTFILES_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_ROOT
# shellcheck source=../lib/common.sh
source "$DOTFILES_ROOT/lib/common.sh"
# shellcheck source=../lib/platform.sh
source "$DOTFILES_ROOT/lib/platform.sh"

detect_platform

install_ubuntu() {
  local conflicts=(
    docker.io docker-compose docker-compose-v2 docker-doc docker-buildx
    podman-docker containerd runc
  )
  local installed=()
  local package
  for package in "${conflicts[@]}"; do
    dpkg -s "$package" >/dev/null 2>&1 && installed+=("$package")
  done
  ((${#installed[@]} == 0)) || sudo apt-get remove -y "${installed[@]}"

  sudo apt-get update
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # shellcheck disable=SC1091
  source /etc/os-release
  cat <<SOURCES | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
SOURCES

  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_arch() {
  sudo pacman -S --needed --noconfirm docker docker-buildx docker-compose
}

case "$PLATFORM_ID" in
  ubuntu) install_ubuntu ;;
  arch) install_arch ;;
esac

sudo systemctl enable --now docker

if [[ "${DOCKER_ADD_USER_TO_GROUP:-1}" == "1" ]]; then
  current_user="${USER:-$(id -un)}"
  sudo usermod -aG docker "$current_user"
  warn "Membership in the docker group grants root-equivalent privileges"
  info "Log out and back in before running Docker without sudo"
fi

info "Docker Engine installation complete"
