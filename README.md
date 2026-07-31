# dotfiles

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
| `development` | Adds Node.js 24 through mise, uv, gh, Stylua, Codex configuration, and other development tools to `server` |
| `wsl-development` | Development environment for WSL |

## Installation

Clone the repository and start the guided installer.

```bash
git clone git@github.com:muray0196/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

It asks which profile to install, whether to install packages, and whether to
change the login shell. The resolved plan is shown before anything is changed.

For a non-interactive installation, preview the planned operations first.

```bash
./install.sh --profile server --dry-run --plan
./install.sh --profile server --set-shell
```

Use the WSL profile on WSL.

```bash
./install.sh --profile wsl-development --set-shell
```

Without a terminal, running `./install.sh` without arguments remains equivalent
to using `--profile shell`.
The applied profile and managed links are recorded under `~/.local/state/dotfiles-linux/`.

Starship and tmux keep Ubuntu and Fedora color variants under `~/.config/`.
During installation or profile reapplication, Fedora selects the Fedora
variants; Ubuntu and the selector fallback use the Ubuntu variants. The active
files are linked at `~/.config/starship.toml` and `~/.config/tmux/theme.conf`.

## Routine operations

Start a new Zsh session after installation. The unified command is then available from anywhere.

```bash
# Show the active repository, revision, and profile
dotfiles status

# Preview and apply repository, package, plugin, and configuration updates
dotfiles update --dry-run
dotfiles update

# Preview and clean stale managed links and old selected Homebrew versions
dotfiles cleanup --dry-run
dotfiles cleanup

# Optionally clean the native package cache
dotfiles cleanup --system-cache

# Validate the saved selection
dotfiles doctor
```

`dotfiles update` requires a clean repository and uses `git pull --ff-only` before reconciling the saved selection.
`dotfiles cleanup` never runs `apt autoremove` or `dnf autoremove`, and it does not delete backups by default.
Backup pruning must be requested explicitly:

```bash
dotfiles cleanup --backups-older-than 30d
```

## Other commands

```bash
# List profiles and modules
./install.sh --list

# Apply another profile, or omit it to use the guided installer
dotfiles apply development
dotfiles apply

# Install individual modules
./install.sh --module tmux --module fastfetch

# Preview removal of managed links and installation state
dotfiles uninstall --dry-run

# Validate the repository
./tests/smoke.sh
```

Configuration files are linked into the home directory with GNU Stow.
Conflicting files are preserved under `~/.local/state/dotfiles-linux/backups/`.

Place machine-specific settings in `~/.zshrc.local` and `~/.gitconfig.local`.

Additional setup for GitHub authentication, Docker, SearXNG, and similar tools must be run explicitly from `scripts/`.

## Package ownership

System integration and Homebrew prerequisites are installed with `apt` or `dnf`.
User-facing CLI tools are installed with Homebrew, while language runtimes are managed by mise.

| Owner | Packages |
|---|---|
| `apt` / `dnf` | Zsh, Git, Stow, tmux, OpenSSH, Python, and Homebrew build prerequisites |
| Homebrew | Starship, Sheldon, Neovim, fzf, ripgrep, fastfetch, uv, Stylua, gh, and mise |
| mise | Node.js 24 |

Normal profile application uses `brew bundle --no-upgrade`; Homebrew and mise upgrades remain explicit through `dotfiles update`.
The Fedora Homebrew bootstrap installs the official `development-tools` package group.

## Repository layout

```text
profiles/   Profile definitions
manifests/  Module dependencies and installation definitions
packages/   apt, dnf, and Homebrew package definitions
modules/    Configuration deployed with GNU Stow
lib/        Shared installer, state, and cleanup implementation
scripts/    Explicit additional setup tasks
services/   Optional services
tests/      Validation
```

See [`AGENTS.md`](AGENTS.md) for repository maintenance and contribution rules.
