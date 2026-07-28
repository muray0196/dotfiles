#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

printf '== Bash syntax ==\n'
while IFS= read -r -d '' script; do
  bash -n "$script"
  printf 'ok  %s\n' "${script#"$ROOT"/}"
done < <(find "$ROOT" -type f -name '*.sh' -print0 | sort -z)

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
actions = {"sheldon-lock", "win32yank"}

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

for profile in shell server development wsl-development; do
  reset_resolution
  resolve_profile "$profile"
  printf 'ok  %-16s %s\n' "$profile" "${SELECTED_MODULES[*]}"
done

reset_resolution
resolve_module zsh-abbr
assert_contains sheldon "${SELECTED_MODULES[@]}"
assert_contains sheldon-lock "${ACTIONS[@]}"
printf 'ok  zsh-abbr resolves Sheldon dependency\n'

reset_resolution
resolve_profile server
if array_contains dev-abbr "${SELECTED_MODULES[@]}"; then
  printf 'server must not include development abbreviations\n' >&2
  exit 1
fi

reset_resolution
resolve_profile development
assert_contains dev-abbr "${SELECTED_MODULES[@]}"
printf 'ok  development abbreviations remain profile-scoped\n'
BASH

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
    printf 'ok  %s/%s\n' "$distro" "$profile"
    rm -rf "$test_home"
  done
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
printf 'ok  ubuntu/wsl-development (interop-safe default)\n'

output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu WSL_DISTRO_NAME=Ubuntu \
    "$ROOT/install.sh" --module win32yank --dry-run --plan
)"
grep -Fq 'install-win32yank.sh' <<<"$output"
printf 'ok  explicit win32yank module\n'
rm -rf "$test_home"

printf '\n== Update dry-run ==\n'
test_home="$(mktemp -d)"
output="$(
  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/update.sh" --profile development --dry-run
)"
grep -Fq 'brew bundle upgrade' <<<"$output"
grep -Fq 'sheldon lock --update' <<<"$output"
if grep -Eq '(apt(-get)?|dnf)[[:space:]]+upgrade' <<<"$output"; then
  printf 'unexpected native OS upgrade in update output\n' >&2
  exit 1
fi
printf 'ok  selected Homebrew/Sheldon update only\n'
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
    .gitconfig; do
    [[ -L "$test_home/$relative" ]] || {
      printf 'expected managed symlink: %s\n' "$relative" >&2
      exit 1
    }
  done

  HOME="$test_home" DOTFILES_DISTRO_OVERRIDE=ubuntu \
    "$ROOT/install.sh" --profile shell --unstow >/dev/null
  [[ ! -e "$test_home/.zshrc" && ! -L "$test_home/.zshrc" ]]
  [[ ! -e "$test_home/.config/starship.toml" && ! -L "$test_home/.config/starship.toml" ]]
  backup="$(find "$test_home/.local/state/dotfiles-linux/backups" -type f -name .zshrc -print -quit)"
  grep -Fqx 'legacy-zshrc' "$backup"
  printf 'ok  apply, backup, link verification, and unstow\n'
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
  shellcheck -x "${scripts[@]}"
  printf 'ok  shellcheck\n'
fi

printf '\nAll smoke tests passed.\n'
