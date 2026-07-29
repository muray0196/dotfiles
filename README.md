# dotfiles-linux

Linux dotfiles shared across Ubuntu, Fedora, and WSL.
Choose a profile to build anything from a minimal shell setup to a full development environment.

## Supported environments

- Ubuntu
- Fedora
- Ubuntu on WSL
- x86-64 Linux

## Profiles

| Profile | Purpose |
|---|---|
| `shell` | Shared baseline with Zsh, Git, Neovim, and related tools |
| `server` | Adds tmux and general CLI tools to `shell` |
| `development` | Adds Node.js, uv, gh, Stylua, Codex configuration, and other development tools to `server` |
| `wsl-development` | Development environment for WSL |

## Installation

Preview the planned operations first.

```bash
git clone git@github.com:muray0196/dotfiles-linux.git ~/dotfiles-linux
cd ~/dotfiles-linux
./install.sh --profile server --dry-run --plan
```

Apply the profile after reviewing the plan.

```bash
./install.sh --profile server --set-shell
```

Use the WSL profile on WSL.

```bash
./install.sh --profile wsl-development --set-shell
```

Running `./install.sh` without arguments is equivalent to using `--profile shell`.

## Common commands

```bash
# List profiles and modules
./install.sh --list

# Install individual modules
./install.sh --module tmux --module fastfetch

# Update selected Homebrew packages and Sheldon plugins
./update.sh --profile development

# Check the installed environment
./doctor.sh --profile development

# Remove managed symlinks
./install.sh --profile server --unstow

# Validate the repository
./tests/smoke.sh
```

Configuration files are linked into the home directory with GNU Stow.
Conflicting files are preserved under `~/.local/state/dotfiles-linux/backups/`.

Place machine-specific settings in `~/.zshrc.local` and `~/.gitconfig.local`.

Additional setup for GitHub authentication, Docker, SearXNG, and similar tools must be run explicitly from `scripts/`.

## Repository layout

```text
profiles/   Profile definitions
manifests/  Module dependencies and installation definitions
packages/   apt, dnf, and Homebrew package definitions
modules/    Configuration deployed with GNU Stow
scripts/    Explicit additional setup tasks
services/   Optional services
tests/      Validation
```

See [`AGENTS.md`](AGENTS.md) for repository maintenance and contribution rules.
