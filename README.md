# dotfiles

Linux dotfiles shared across Ubuntu, Arch Linux, and WSL.
Choose a profile to build anything from a minimal shell setup to a full development environment.

## Supported environments

- Ubuntu
- Arch Linux
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

Starship and tmux keep Ubuntu and Arch Linux color variants under `~/.config/`.
During installation or profile reapplication, Arch Linux selects the Arch
variants; Ubuntu and the selector fallback use the Ubuntu variants. The active
files are linked at `~/.config/starship.toml` and `~/.config/tmux/theme.conf`.

## Routine operations

Start a new Zsh session after installation. The unified command is then available from anywhere.

```bash
# Show the active repository, revision, and profile
dotfiles status

# Preview and synchronize the repository, packages, plugins, and configuration
dotfiles sync --dry-run
dotfiles sync

# Validate the saved selection
dotfiles doctor
```

`dotfiles sync` requires a clean repository and uses `git pull --ff-only` before reconciling the saved selection.

The `up` abbreviation upgrades pacman/AUR and Homebrew packages, then runs
`hermes update` when Hermes is installed. Waywallen is intentionally separate:
`wwup` checks the official AppImage release, verifies its published SHA-256,
installs it beside the current version, and retains only the immediately
previous version for rollback. Locally patched llama.cpp builds are not updated
by either command.

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

## Quickshell desktop widgets (opt-in)

The `quickshell` module contains the Arch/Hyprland desktop widgets and is kept
out of the shared profiles. Preview and install it explicitly:

```bash
./install.sh --module quickshell --dry-run --plan
./install.sh --module quickshell
```

Real credentials, location data, BLE identifiers, display hardware settings,
and mutable automation state are local files and are never tracked. Create only
the files needed for this machine from the adjacent `*.example.json` templates:

```text
~/.config/quickshell/clock/local.json
~/.config/quickshell/performance/remote.json
~/.config/quickshell/performance/machine.json
~/.config/quickshell/performance/automation.json
```

Keep those files mode `0600`. A missing or disabled `machine.json` leaves desktop
automation off, while the performance widget can continue without it. Each
loader requires the complete current fields for the section it consumes; partial
legacy config shapes are not accepted. The current visual direction and experiment
boundaries are recorded in
[`docs/quickshell-ui-plan.md`](docs/quickshell-ui-plan.md).

Additional setup for GitHub authentication, Docker, SearXNG, and similar tools must be run explicitly from `scripts/`.

## Package ownership

System integration and Homebrew prerequisites are installed with `apt` or `pacman`.
User-facing CLI tools are installed with Homebrew, while language runtimes are managed by mise.

| Owner | Packages |
|---|---|
| `apt` / `pacman` | Zsh, Git, Stow, tmux, OpenSSH, Python, and Homebrew build prerequisites |
| Homebrew | Starship, Sheldon, Neovim, fzf, ripgrep, fastfetch, uv, Stylua, gh, and mise |
| mise | Node.js 24 |

Normal profile application uses `brew bundle --no-upgrade`; Homebrew and mise upgrades remain explicit through `dotfiles sync`.
The Arch Linux Homebrew bootstrap installs the `base-devel` package.

## Repository layout

```text
profiles/   Profile definitions
manifests/  Module dependencies and installation definitions
packages/   apt, pacman, and Homebrew package definitions
modules/    Configuration deployed with GNU Stow
lib/        Shared installation, package, and state implementation
scripts/    Explicit additional setup tasks
services/   Optional services
tests/      Validation
```

See [`AGENTS.md`](AGENTS.md) for repository maintenance and contribution rules.
