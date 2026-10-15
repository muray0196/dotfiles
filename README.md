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
installs it beside the current version, and retains the immediately previous
version for rollback, plus versions still running or referenced by another
Waywallen launcher on `PATH`. Custom launchers can delegate to a sibling
`waywallen-appimage` symlink pointing to the versioned `AppRun`; `wwup` updates
that link and preserves the launcher. It makes the extracted application
accessible to regular users and verifies the installed version before switching
the launcher.

The `clean` abbreviation non-interactively clears the complete pacman/AUR
package cache, removes stored systemd crash dumps, and runs Homebrew cleanup.
Pacman package archives are removed explicitly because `-Scc --noconfirm`
defaults to declining full cache removal; partial downloads are retained.
It requires administrator authentication for the system-owned cache and crash
dump files.

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

## Hermes persona and skills (opt-in)

The `hermes` module preserves the conversational persona in `~/.hermes/SOUL.md`
and the local `productivity/conversation-history-recovery` skill. It targets the
default `~/.hermes` home and is kept out of the shared profiles:

```bash
./install.sh --module hermes --dry-run --plan
./install.sh --module hermes
```

The module manages these files only; install Hermes separately. Credentials,
`config.yaml`, memories, sessions, and downloaded skills remain local. No
services are installed or started. Edits through the deployed symlinks update
the repository files.

## Quickshell desktop widgets (opt-in)

The `quickshell` module contains the Arch/Hyprland desktop widgets and is kept
out of the shared profiles. Preview and install it explicitly:

```bash
./install.sh --module quickshell --dry-run --plan
./install.sh --module quickshell
```

The module also provides `widgets-toggle`, which shows or hides the running
`clock` and `performance` widgets together using Quickshell IPC. It uses the
clock widget's visibility to choose the new state and requires `/usr/bin/qs`.

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

For recurring desktop stalls, the optional [freeze recorder](services/freeze-recorder/README.md)
preserves Quickshell/Hyprland logs and bounded process/pressure samples across
reboots. Install it explicitly with `python3 scripts/setup-freeze-recorder.py`.

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
