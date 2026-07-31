#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

printf '== Bash syntax ==\n'
while IFS= read -r -d '' script; do
  bash -n "$script"
  printf 'ok  %s\n' "${script#"$ROOT"/}"
done < <(find "$ROOT" -type f -name '*.sh' -print0 | sort -z)
bash -n "$ROOT/modules/dotfiles-cli/.local/bin/dotfiles"
printf 'ok  modules/dotfiles-cli/.local/bin/dotfiles\n'
for entrypoint in cleanup.sh modules/dotfiles-cli/.local/bin/dotfiles; do
  [[ -x "$ROOT/$entrypoint" ]] || {
    printf 'entry point is not executable: %s\n' "$entrypoint" >&2
    exit 1
  }
done
printf 'ok  new command entry points are executable\n'

printf '\n== Structured configuration ==\n'
python3 - "$ROOT" <<'PY'
import json
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
for path in root.rglob("*.toml"):
    with path.open("rb") as stream:
        tomllib.load(stream)
    print("ok ", path.relative_to(root))

json_path = root / "modules/fastfetch/.config/fastfetch/config.jsonc"
with json_path.open(encoding="utf-8") as stream:
    json.load(stream)
print("ok ", json_path.relative_to(root))

python_path = root / "services/search-stack/scripts/search-and-crawl.py"
compile(python_path.read_text(encoding="utf-8"), str(python_path), "exec")
print("ok ", python_path.relative_to(root))


def definition_lines(path: Path) -> list[str]:
    lines: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    return lines


profiles = {path.name for path in (root / "profiles").iterdir() if path.is_file()}
manifests = {path.name for path in (root / "manifests").iterdir() if path.is_file()}
actions = {"mise-install", "sheldon-lock", "win32yank"}

for name in sorted(profiles):
    for line in definition_lines(root / "profiles" / name):
        if line.startswith("profile:"):
            dependency = line.removeprefix("profile:")
            assert dependency in profiles, f"unknown profile dependency: {name} -> {dependency}"
        else:
            assert line in manifests, f"unknown module in profile {name}: {line}"

for name in sorted(manifests):
    for line in definition_lines(root / "manifests" / name):
        kind, separator, value = line.partition(":")
        assert separator, f"invalid manifest line: {name}: {line}"
        if kind == "require":
            assert value in manifests, f"unknown module dependency: {name} -> {value}"
        elif kind == "native":
            for distro in ("ubuntu", "fedora"):
                path = root / "packages" / "native" / distro / f"{value}.txt"
                assert path.is_file(), f"missing native group: {distro}/{value}"
        elif kind == "brew":
            path = root / "packages" / "brew" / f"{value}.Brewfile"
            assert path.is_file(), f"missing Brewfile: {value}"
        elif kind == "stow":
            path = root / "modules" / value
            assert path.is_dir(), f"missing Stow module: {value}"
        elif kind == "action":
            assert value in actions, f"unknown action: {value}"
        else:
            raise AssertionError(f"unknown manifest directive: {kind}")

for path in root.rglob("*"):
    if path.is_symlink():
        assert path.exists(), f"broken repository symlink: {path.relative_to(root)}"

print("ok  profile, manifest, package, module, and action consistency")
PY

printf '\n== Profile resolution ==\n'
DOTFILES_ROOT="$ROOT" bash <<'BASH'
set -euo pipefail
source "$DOTFILES_ROOT/lib/common.sh"
source "$DOTFILES_ROOT/lib/profile.sh"

assert_contains() {
  local needle="$1"
  shift
  array_contains "$needle" "$@" || {
    printf 'missing %s in: %s\n' "$needle" "$*" >&2
    exit 1
  }
}

assert_not_contains() {
  local needle="$1"
  shift
  if array_contains "$needle" "$@"; then
    printf 'unexpected %s in: %s\n' "$needle" "$*" >&2
    exit 1
  fi
}

brew_formula_is_resolved() {
  local formula="$1"
  local group

  for group in "${BREW_GROUPS[@]}"; do
    grep -Fqx "brew \"$formula\"" "$DOTFILES_ROOT/packages/brew/$group.Brewfile" && return 0
  done
  return 1
}

baseline_modules=(zsh starship sheldon zsh-abbr git nvim dotfiles-cli)

for profile_file in "$DOTFILES_ROOT"/profiles/*; do
  [[ -f "$profile_file" ]] || continue
  profile="$(basename "$profile_file")"
  reset_resolution
  resolve_profile "$profile"
  for module in "${baseline_modules[@]}"; do
    assert_contains "$module" "${SELECTED_MODULES[@]}"
  done
  ((${#BREW_GROUPS[@]} > 0)) || {
    printf 'profile must resolve Homebrew packages: %s\n' "$profile" >&2
    exit 1
  }
  if brew_formula_is_resolved stylua; then
    assert_contains dev-tools "${SELECTED_MODULES[@]}"
  else
    assert_not_contains dev-tools "${SELECTED_MODULES[@]}"
  fi
  printf 'ok  %-16s %s\n' "$profile" "${SELECTED_MODULES[*]}"
done
printf 'ok  every profile resolves the shared Linux baseline and Homebrew packages\n'

for manifest in "$DOTFILES_ROOT"/manifests/*; do
  module="$(basename "$manifest")"
  reset_resolution
  resolve_module "$module"
  if ((${#BREW_GROUPS[@]} > 0)); then
    assert_contains brew-bootstrap "${NATIVE_GROUPS[@]}"
  fi
  if ((${#STOW_MODULES[@]} > 0)); then
    assert_contains stow "${NATIVE_GROUPS[@]}"
  fi
done
printf 'ok  every Brew/Stow module resolves its native bootstrap group\n'

reset_resolution
resolve_module zsh-abbr
assert_contains sheldon "${SELECTED_MODULES[@]}"
assert_contains sheldon-lock "${ACTIONS[@]}"
printf 'ok  zsh-abbr resolves Sheldon dependency\n'

reset_resolution
resolve_module nvim
assert_contains brew-bootstrap "${NATIVE_GROUPS[@]}"
assert_contains stow "${NATIVE_GROUPS[@]}"
assert_not_contains development "${NATIVE_GROUPS[@]}"
assert_contains nvim "${BREW_GROUPS[@]}"
brew_formula_is_resolved neovim
if brew_formula_is_resolved stylua; then
  printf 'the nvim module must not resolve Stylua\n' >&2
  exit 1
fi
printf 'ok  nvim resolves only Homebrew/Stow native prerequisites\n'

reset_resolution
resolve_module fastfetch
assert_contains brew-bootstrap "${NATIVE_GROUPS[@]}"
assert_contains stow "${NATIVE_GROUPS[@]}"
for group in zsh git server development win32yank; do
  assert_not_contains "$group" "${NATIVE_GROUPS[@]}"
done
printf 'ok  standalone fastfetch does not pull unrelated native groups\n'

reset_resolution
resolve_profile server
assert_not_contains dev-tools "${SELECTED_MODULES[@]}"
assert_not_contains dev-abbr "${SELECTED_MODULES[@]}"
brew_formula_is_resolved neovim
if brew_formula_is_resolved stylua; then
  printf 'server must not include Stylua\n' >&2
  exit 1
fi

for profile in development wsl-development; do
  reset_resolution
  resolve_profile "$profile"
  assert_contains dev-tools "${SELECTED_MODULES[@]}"
  assert_contains dev-abbr "${SELECTED_MODULES[@]}"
  assert_contains dev-tools "${STOW_MODULES[@]}"
  assert_contains mise-install "${ACTIONS[@]}"
  brew_formula_is_resolved neovim
  brew_formula_is_resolved mise
  brew_formula_is_resolved stylua
  if brew_formula_is_resolved node; then
    printf 'development must manage Node.js through mise, not Homebrew\n' >&2
    exit 1
  fi
done
printf 'ok  development uses mise for Node.js and keeps its tools profile-only\n'
BASH

printf '\n== Installer listing ==\n'
output="$("$ROOT/install.sh" --list-modules)"
grep -Fq 'MODULE' <<<"$output"
grep -Fq 'DESCRIPTION' <<<"$output"
if grep -Fq 'Profiles:' <<<"$output"; then
  printf '%s\n' '--list-modules must not include profiles' >&2
  exit 1
fi
for manifest in "$ROOT"/manifests/*; do
  module="$(basename "$manifest")"
  description="$(sed -n '1s/^#[[:space:]]*//p' "$manifest")"
  [[ -n "$description" ]] || {
    printf 'module description is missing: %s\n' "$module" >&2
    exit 1
  }
  module_line="$(grep -F "  $module" <<<"$output")"
  grep -Fq "$description" <<<"$module_line"
done
printf 'ok  module list is generated from manifest descriptions\n'

printf '\n== Installer dry-runs ==\n'
for distro in ubuntu fedora; do
  for profile in shell server development; do
    test_home="$(mktemp -d)"
    output="$(
      HOME="$test_home" DOTFILES_DISTRO_OVERRIDE="$distro" \
        "$ROOT/install.sh" --profile "$profile" --dry-run --plan
    )"
    grep -Fq '[dotfiles] Installation complete' <<<"$output"
    grep -Fq 'stow --restow --no-folding' <<<"$output"
    grep -Fq 'brew bundle --no-upgrade' <<<"$output"
    grep -Fq 'nvim.Brewfile' <<<"$output"
    if [[ "$distro" == "fedora" ]]; then
      grep -Fq 'sudo dnf group install -y development-tools' <<<"$output"
    fi
    if [[ "$profile" == "development" ]]; then
      grep -Fq 'mise install node' <<<"$output"
    fi
    printf 'ok  %s/%s\n' "$distro" "$profile"
    rm -rf "$test_home"
  done

  test_home="$(mktemp -d)"
  output="$(
    HOME="$test_home" DOTFILES_DISTRO_OVERRIDE="$distro" \
      "$ROOT/install.sh" --module nvim --dry-run --plan
  )"
  grep -Fq 'Native groups:    brew-bootstrap stow' <<<"$output"
  grep -Fq 'nvim.Brewfile' <<<"$output"
  if grep -Fq 'development' <<<"$(grep -F 'Native groups:' <<<"$output")"; then
    printf 'direct nvim install must not resolve development native packages\n' >&2
    exit 1
  fi
  printf 'ok  %s/nvim module prerequisites\n' "$distro"
  rm -rf "$test_home"
done

test_home="$(mktemp -d)"
output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu WSL_DISTRO_NAME=Ubuntu \
    "$ROOT/install.sh" --profile wsl-development --dry-run --plan
)"
if grep -Fq 'install-win32yank.sh' <<<"$output"; then
  printf 'win32yank must remain opt-in\n' >&2
  exit 1
fi
grep -Fq 'brew bundle --no-upgrade' <<<"$output"
printf 'ok  ubuntu/wsl-development (interop-safe default)\n'

output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu WSL_DISTRO_NAME=Ubuntu \
    "$ROOT/install.sh" --module win32yank --dry-run --plan
)"
grep -Fq 'install-win32yank.sh' <<<"$output"
grep -Fq 'Native groups:    win32yank' <<<"$output"
printf 'ok  explicit win32yank module\n'
rm -rf "$test_home"

printf '\n== Update dry-run ==\n'
test_home="$(mktemp -d)"
output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/update.sh" --profile development --dry-run
)"
grep -Fq 'brew bundle upgrade' <<<"$output"
grep -Fq 'mise upgrade node' <<<"$output"
grep -Fq 'sheldon lock --update' <<<"$output"
if grep -Eq '(apt(-get)?|dnf)[[:space:]]+upgrade' <<<"$output"; then
  printf 'unexpected native OS upgrade in update output\n' >&2
  exit 1
fi
printf 'ok  selected Homebrew/mise/Sheldon update only\n'
rm -rf "$test_home"

printf '\n== Conflict backup ==\n'
test_home="$(mktemp -d)"
printf 'legacy-zshrc\n' >"$test_home/.zshrc"
HOME="$test_home" DOTFILES_ROOT="$ROOT" bash <<'BASH'
set -euo pipefail
DRY_RUN=0
source "$DOTFILES_ROOT/lib/common.sh"
source "$DOTFILES_ROOT/lib/deploy.sh"
backup_module_conflicts zsh
[[ ! -e "$HOME/.zshrc" ]]
backup="$(find "$HOME/.local/state/dotfiles-linux/backups" -type f -name .zshrc -print -quit)"
[[ -n "$backup" ]]
grep -Fqx 'legacy-zshrc' "$backup"
BASH
printf 'ok  conflicting file is preserved under the backup tree\n'
rm -rf "$test_home"

test_home="$(mktemp -d)"
legacy_dir="$(mktemp -d)"
mkdir -p "$test_home/.config" "$legacy_dir/sheldon"
printf 'legacy-sheldon\n' >"$legacy_dir/sheldon/plugins.toml"
ln -s "$legacy_dir/sheldon" "$test_home/.config/sheldon"
LEGACY_TARGET="$legacy_dir/sheldon" HOME="$test_home" DOTFILES_ROOT="$ROOT" bash <<'BASH'
set -euo pipefail
DRY_RUN=0
source "$DOTFILES_ROOT/lib/common.sh"
source "$DOTFILES_ROOT/lib/deploy.sh"
backup_module_conflicts sheldon
[[ ! -e "$HOME/.config/sheldon" && ! -L "$HOME/.config/sheldon" ]]
backup="$(find "$HOME/.local/state/dotfiles-linux/backups" -type l -path '*/.config/sheldon' -print -quit)"
[[ -n "$backup" ]]
[[ "$(readlink "$backup")" == "$LEGACY_TARGET" ]]
BASH
printf 'ok  legacy parent-directory symlink is preserved\n'
rm -rf "$test_home" "$legacy_dir"

printf '\n== Installation state ==\n'
test_home="$(mktemp -d)"
HOME="$test_home" DOTFILES_ROOT="$ROOT" bash <<'BASH'
set -euo pipefail
source "$DOTFILES_ROOT/lib/common.sh"
source "$DOTFILES_ROOT/lib/state.sh"

STOW_MODULES=(dotfiles-cli)
record_installation_state server
grep -Fqx 'profile:server' "$DOTFILES_SELECTION_FILE"
grep -Fqx '.local/bin/dotfiles' "$DOTFILES_MANAGED_PATHS_FILE"

STOW_MODULES=()
record_installation_state "" win32yank
grep -Fqx 'profile:server' "$DOTFILES_SELECTION_FILE"
grep -Fqx 'module:win32yank' "$DOTFILES_SELECTION_FILE"
grep -Fqx '.local/bin/dotfiles' "$DOTFILES_MANAGED_PATHS_FILE"

mkdir -p "$HOME/.local/bin"
ln -s "$DOTFILES_ROOT/modules/dotfiles-cli/.local/bin/dotfiles" "$HOME/.local/bin/dotfiles"
expected_paths=()
reconcile_stale_managed_links 1 expected_paths
[[ -L "$HOME/.local/bin/dotfiles" ]]
reconcile_stale_managed_links 0 expected_paths
[[ ! -e "$HOME/.local/bin/dotfiles" && ! -L "$HOME/.local/bin/dotfiles" ]]

printf 'user-owned\n' >"$HOME/.local/bin/dotfiles"
reconcile_stale_managed_links 0 expected_paths
grep -Fqx 'user-owned' "$HOME/.local/bin/dotfiles"
BASH

old_backup="$test_home/.local/state/dotfiles-linux/backups/20000101-000000-1"
mkdir -p "$old_backup"
touch -d '40 days ago' "$old_backup"
output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/cleanup.sh" --dry-run --backups-older-than 30d
)"
grep -Fq "remove old backup $old_backup" <<<"$output"
[[ -d "$old_backup" ]]
HOME="$test_home" DOTFILES_ROOT="$ROOT" bash <<'BASH'
set -euo pipefail
source "$DOTFILES_ROOT/lib/common.sh"
source "$DOTFILES_ROOT/lib/state.sh"
prune_old_backups 30d 0
BASH
[[ ! -d "$old_backup" ]]
printf 'ok  saved state, safe link cleanup, and guarded backup pruning\n'
rm -rf "$test_home"

if command -v stow >/dev/null 2>&1; then
  printf '\n== GNU Stow integration ==\n'
  test_home="$(mktemp -d)"
  printf 'legacy-zshrc\n' >"$test_home/.zshrc"
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/install.sh" --profile shell --no-packages >/dev/null

  for relative in \
    .zshrc \
    .zshprofile \
    .config/starship.toml \
    .config/sheldon/plugins.toml \
    .config/zsh-abbr/user-abbreviations \
    .config/nvim/init.lua \
    .local/bin/dotfiles \
    .gitconfig; do
    [[ -L "$test_home/$relative" ]] || {
      printf 'expected managed symlink: %s\n' "$relative" >&2
      exit 1
    }
  done

  grep -Fqx 'profile:shell' "$test_home/.local/state/dotfiles-linux/selection"
  grep -Fqx '.local/bin/dotfiles' "$test_home/.local/state/dotfiles-linux/managed-paths"
  status_output="$(HOME="$test_home" "$test_home/.local/bin/dotfiles" status)"
  grep -Fq 'Profile:    shell' <<<"$status_output"
  printf 'ok  installation selection and managed paths are recorded\n'

  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/install.sh" --profile shell --unstow >/dev/null
  [[ ! -e "$test_home/.zshrc" && ! -L "$test_home/.zshrc" ]]
  [[ ! -e "$test_home/.config/starship.toml" && ! -L "$test_home/.config/starship.toml" ]]
  [[ ! -e "$test_home/.config/nvim/init.lua" && ! -L "$test_home/.config/nvim/init.lua" ]]
  backup="$(find "$test_home/.local/state/dotfiles-linux/backups" -type f -name .zshrc -print -quit)"
  grep -Fqx 'legacy-zshrc' "$backup"
  printf 'ok  apply, backup, link verification, and unstow\n'
  rm -rf "$test_home"

  printf '\n== Managed state and CLI ==\n'
  test_home="$(mktemp -d)"
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/install.sh" --profile development --no-packages >/dev/null
  [[ -L "$test_home/.codex/config.toml" ]]
  [[ -L "$test_home/.config/zsh-abbr/extra/development.zsh" ]]
  [[ -L "$test_home/.config/mise/config.toml" ]]

  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/install.sh" --profile server --no-packages >/dev/null
  [[ ! -e "$test_home/.codex/config.toml" && ! -L "$test_home/.codex/config.toml" ]]
  [[ ! -e "$test_home/.config/zsh-abbr/extra/development.zsh" &&
    ! -L "$test_home/.config/zsh-abbr/extra/development.zsh" ]]
  [[ ! -e "$test_home/.config/mise/config.toml" &&
    ! -L "$test_home/.config/mise/config.toml" ]]
  grep -Fqx 'profile:server' "$test_home/.local/state/dotfiles-linux/selection"
  printf 'ok  applying a smaller profile removes stale managed links\n'

  output="$(
    HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
      "$test_home/.local/bin/dotfiles" update --dry-run --no-pull
  )"
  grep -Fq 'Selected modules:' <<<"$output"
  grep -Fq 'brew bundle upgrade' <<<"$output"
  if grep -Fq 'mise upgrade node' <<<"$output"; then
    printf 'server update must not include mise-managed Node.js\n' >&2
    exit 1
  fi
  grep -Fq "$ROOT/doctor.sh" <<<"$output"
  printf 'ok  unified update uses the saved profile\n'

  output="$(
    HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
      "$test_home/.local/bin/dotfiles" cleanup --dry-run --system-cache
  )"
  grep -Fq 'brew cleanup' <<<"$output"
  grep -Fq 'sudo apt-get clean' <<<"$output"
  printf 'ok  cleanup previews selected Homebrew and system cache operations\n'

  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$test_home/.local/bin/dotfiles" uninstall --dry-run >/dev/null
  [[ -f "$test_home/.local/state/dotfiles-linux/selection" ]]

  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$test_home/.local/bin/dotfiles" uninstall >/dev/null
  [[ ! -e "$test_home/.local/bin/dotfiles" && ! -L "$test_home/.local/bin/dotfiles" ]]
  [[ ! -e "$test_home/.local/state/dotfiles-linux/selection" ]]
  printf 'ok  uninstall removes links and state while preserving packages\n'
  rm -rf "$test_home"
fi

if command -v zsh >/dev/null 2>&1; then
  printf '\n== Zsh syntax ==\n'
  zsh -n "$ROOT/modules/zsh/.zshrc"
  printf 'ok  modules/zsh/.zshrc\n'
fi

lua_compiler=""
for candidate in luac luac5.4 luac5.3; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_compiler="$candidate"
    break
  fi
done
if [[ -n "$lua_compiler" ]]; then
  printf '\n== Lua syntax ==\n'
  while IFS= read -r -d '' lua_file; do
    "$lua_compiler" -p "$lua_file"
    printf 'ok  %s\n' "${lua_file#"$ROOT"/}"
  done < <(find "$ROOT/modules/nvim" -type f -name '*.lua' -print0 | sort -z)
fi

if command -v shellcheck >/dev/null 2>&1; then
  printf '\n== ShellCheck ==\n'
  mapfile -d '' scripts < <(
    find "$ROOT" -type f -name '*.sh' ! -path "$ROOT/lib/*" -print0 | sort -z
  )
  scripts+=("$ROOT/modules/dotfiles-cli/.local/bin/dotfiles")
  shellcheck -x "${scripts[@]}"
  printf 'ok  shellcheck\n'
fi

printf '\nAll smoke tests passed.\n'
