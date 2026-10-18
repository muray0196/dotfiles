# dotfiles

Linux dotfiles shared across Ubuntu, Arch Linux, and WSL.
Choose a profile to build anything from a minimal shell setup to a full development environment.

The [Liquid Glass playground](scripts/liquid-glass-lab/README.md)
can be launched with `python3 scripts/liquid-glass-lab/lab.py run`. It opens a
separate Quickshell window and does not change installed desktop widgets.
Try different shapes and backgrounds with the current shared glass shader and
the desktop's Clear, Soft, and Diffused clarity settings plus optional color tint. Shapes change
geometry only; the playground has no background-specific optical tuning.
The same project includes an experimental GPU desktop backend. Use
`python3 scripts/liquid-glass-lab/lab.py desktop-check` to test it in isolated
compositors and `desktop-record` to export a preview. See its README before
using the optional `desktop` command in a normal session.
Use `python3 scripts/liquid-glass-lab/lab.py benchmark --device <render-node>`
for offscreen Clear filtering comparisons and GPU timings without loading a live plugin.
Desktop Clear uses up to 4× hardware anisotropic filtering on the source texture.
Clear and Soft limit their lighting blur to widget footprints and skip unused lighting
mipmaps, preserving the source filtering, image resolution, and refresh rate.
Diffused uses a linear half-float blur intermediate on supported GPUs, improving
precision and reducing color-conversion work while retaining the blur kernel.

The separate [widget UI study](scripts/quickshell-widget-preview/README.md)
redesigns the left/right composition using that accepted material. Run
`python3 scripts/quickshell-widget-preview/preview.py run` for an isolated window;
its Soft-only directions and screenshots are documented with the preview.
The selected preview and desktop share their panel layout and positioning.
`python3 scripts/quickshell-widget-preview/desktop.py check` validates the actual
five-surface desktop integration in disposable compositors. It replays the running
desktop's data, clock, radar frame, and logical layout at 1×, 1.25×, and 2× DPI,
and rejects mismatched foreground files or panel geometry. The separate desktop
launcher requires current integration validation and explicit opt-in to load
the backend. Foreground-only edits reuse that validation; each start checks QML
syntax before launching the widgets.
Its selected Lens and instruments layout uses five separate glass surfaces,
retains the existing information, and aligns all three right-hand panels at
350 px width.
The desktop picker separates **Clarity: Clear / Soft / Diffused** from
**Tint: Off / Black / White / Blue / Teal / Green / Amber / Rose**; all use light text.
Tint defaults to Off. Clear preserves background detail,
Soft adds gentle local smoothing, and Diffused uses broad smoothing without
stacking the narrow filter.
Use `python3 scripts/quickshell-widget-preview/desktop.py clarity diffused` and
`desktop.py tint black` to change these independently. Startup defaults to
Soft with tint Off; `start --clarity clear --tint blue` selects another combination.

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

The module deploys the shared collectors, configuration examples, and
`widgets-toggle`. The current desktop implementation lives in
[`scripts/quickshell-widget-preview`](scripts/quickshell-widget-preview/README.md)
and uses the independent
[Liquid Glass renderer](scripts/liquid-glass-lab/README.md). The earlier widget
shells and glass implementations have been retired.

The selected layout has five 350 px glass surfaces: Local PC and Main PC with
history on the left; clock, calendar/weather, and radar on the right.
`widgets-toggle` shows or hides all five through the current desktop runner.
It requires a recorded running widget session and does not start one itself.

Clarity (**Clear / Soft / Diffused**) and optional tint are independent runtime
choices. Startup defaults to Soft with tint Off; all desktop choices use light
text. The appearance picker uses the existing optional `wofi` command.

```bash
python3 scripts/quickshell-widget-preview/desktop.py status
python3 scripts/quickshell-widget-preview/desktop.py clarity clear
python3 scripts/quickshell-widget-preview/desktop.py tint off
python3 scripts/quickshell-widget-preview/choose.py
widgets-toggle
```

Follow the widget README to build and validate the renderer before explicitly
starting it with `desktop.py start --load-backend`. Keep the accepted native
build, validation receipts, and active widget cache available for startup.
Standard profiles do not load the compositor plugin, configure login startup,
or install persistent services. Startup and shortcuts remain local choices.

Continuous SwitchBot and remote-metrics collectors stop when their widget closes
the output pipe, including after an abrupt runtime exit and while no readings
are available. Repeated widget launches therefore do not leave these collectors
running without a consumer.

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
automation off, while metric collection can continue without it. Each loader
requires the complete current fields for the section it consumes; partial
legacy config shapes are not accepted. The current layout and field inventory
are documented in the [widget guide](scripts/quickshell-widget-preview/README.md).

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
