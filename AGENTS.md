# Repository Operations Guide

This file defines the operating rules for maintainers and coding agents working in this repository.

## Purpose and scope

- Treat this repository as the single source of truth for Linux dotfiles.
- Support Ubuntu, Fedora, Ubuntu on WSL, and x86-64 Linux.
- Do not assume support for macOS or other distributions unless it is added explicitly.
- Do not install or enable persistent services through standard profiles.

## Profile invariants

- Keep `shell` resolvable as the shared baseline of every profile.
- Keep Zsh, Starship, Sheldon, zsh-abbr, Git, Neovim, and the unified `dotfiles` command in `shell`.
- Add practical server CLI tools to `server`, but keep development-only tools out of it.
- Add development-only tools and configuration only to `development` and `wsl-development`.
- Keep Stylua and development-specific zsh-abbr entries limited to development profiles.
- Keep `wsl-development` independent of Windows interop by default. `win32yank` must remain an explicitly selected module.
- The Codex module manages configuration only. It must not install the Codex client.

## Directory responsibilities

- `profiles/`: Define profile inheritance and module composition.
- `manifests/`: Declare module dependencies, package groups, Stow targets, and actions.
- `packages/native/`: Manage OS-level packages separately for Ubuntu and Fedora.
- `packages/brew/`: Manage user-facing CLI tools in module-specific Brewfiles.
- `modules/`: Store feature-oriented GNU Stow packages relative to the home directory.
- `lib/`: Store shared implementation used by install, update, cleanup, and doctor commands.
- `scripts/`: Store authentication, service installation, and other explicitly invoked tasks.
- `services/`: Store optional service configuration and templates.
- `tests/`: Validate configuration consistency, dry-runs, links, and backups.

## Changing definitions

- Put one module name or `profile:<name>` entry on each profile line.
- Use only the existing `require:`, `native:`, `brew:`, `stow:`, and `action:` manifest directives.
- When adding a module, add its manifest and every referenced package group, Stow directory, and action together.
- Reference `native:brew-bootstrap` from every module that applies a Brewfile.
- Reference `native:stow` from modules that deploy configuration directly, unless a required module already resolves it.
- When adding a module to a profile, check its effect on every inheriting profile.
- Treat Homebrew as installation infrastructure that is provisioned before applying Brewfiles, not as a Stow module.
- Resolve dependencies required by standalone Neovim installation through the `nvim` module without implicitly adding development-only tools.
- Update the README and command help whenever behavior or usage changes.

## State and routine operations

- Record the last successful selection in `~/.local/state/dotfiles-linux/selection`.
- Record every deployed Stow file in `~/.local/state/dotfiles-linux/managed-paths`.
- Keep state files declarative, line-oriented, private to the current user, and safe to parse without `source`.
- Preserve a saved profile when an individual module is installed later; merge the additional module and managed paths into the existing state.
- When a full profile is reapplied, remove stale paths only if they are symlinks that still point inside this repository's `modules/` tree.
- Never remove a regular file, directory, or symlink with a non-repository target during state reconciliation.
- Keep `dotfiles update` limited to a clean worktree, `git pull --ff-only`, profile reconciliation, selected Homebrew and Sheldon updates, and validation.
- Keep `dotfiles cleanup` limited by default to stale managed links and old versions of selected Homebrew formulae.
- Require explicit options for native package cache cleanup and backup pruning.
- Keep uninstall separate from cleanup. Uninstall removes managed links and installation state but preserves packages and backups.

## Package and side-effect boundaries

- Manage Zsh, Git, Stow, tmux, and native dependencies with `apt` or `dnf`.
- Manage Starship, Sheldon, Neovim, and additional user-facing CLI tools with Linuxbrew.
- Manage Node.js with mise and keep its global version declaration in the development Stow module.
- Keep `update.sh` limited to selected Homebrew packages, mise runtimes, and Sheldon plugins. Do not add `apt upgrade` or `dnf upgrade`.
- Never run `apt autoremove` or `dnf autoremove` from cleanup.
- Do not mix system-wide upgrades, GitHub authentication, SSH key creation or registration, Docker installation, or systemd service activation into standard profile installation.
- Isolate tasks with additional side effects under `scripts/` and require users to invoke them explicitly.
- Never delete conflicting files or legacy dotfiles symlinks. Preserve them under `~/.local/state/dotfiles-linux/backups/`.
- Keep `--unstow` limited to managed symlinks. It must not remove packages or backups.
- Do not commit machine-specific values or secrets. Override Zsh through `~/.zshrc.local` and Git through `~/.gitconfig.local`.

## Changes and validation

- Review resolved operations with `./install.sh --profile <name> --dry-run --plan` before applying them to a real environment.
- Never run install or unstow against the real home directory while validating repository changes. Use dry-run mode or a temporary `HOME`.
- Run `./tests/smoke.sh` after making changes.
- At minimum, keep smoke coverage for shell syntax, TOML/JSON/Python syntax, profile-manifest-package-module-action references, all profile resolutions, Ubuntu/Fedora/WSL dry-runs, saved state, profile reconciliation, cleanup previews, and unified CLI uninstall.
- Resolve ShellCheck findings when changing shell scripts.
- Follow `.editorconfig`: UTF-8, LF, a final newline, two-space indentation by default, and four-space indentation for Python. Follow `stylua.toml` for Lua.
- If a test cannot be run, report the skipped test and the reason.
