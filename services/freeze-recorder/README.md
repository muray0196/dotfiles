# Freeze recorder

Optional Linux user service for investigating partial desktop stalls. Install
explicitly from this checkout; normal dotfiles profiles do not enable it:

```sh
python3 scripts/setup-freeze-recorder.py
systemctl --user status freeze-recorder.service
```

Requires Python 3, Linux `/proc`, and user systemd. No packages are installed.
The installer preserves conflicting files in the dotfiles backup directory.
The service starts with the user manager and survives SSH disconnection and
graphical-session exit. It does not change the user's linger setting; an existing
linger setting also permits recording before graphical login.

Every five seconds it records memory/swap, memory and I/O pressure, load,
network counters, the ten largest memory users and ten busiest processes,
Clock/Performance and their collectors, Hyprland, Waywallen, SSH, and llama-server.
It records process identity, state, CPU counters, thread counts, wait channels,
blocked threads in watched processes, and observed appearances/disappearances.
It stores no full process command lines or environment variables. A disappearance
means absent from a later sample, not a known exit code or cause. Wait channels
for other users' processes can be unavailable without root.

Existing text logs under `/run/user/<uid>/quickshell/by-id/` and
`/run/user/<uid>/hypr/` are copied incrementally into `desktop_log` events with
the original source and byte offset. Replacement, truncation, and new instances
are detected. A source backlog larger than 256 KiB is skipped to its latest
256 KiB and explicitly marked `log_gap`. Restarting the recorder may copy source
text again; source offsets identify overlap.

The compositor's small in-memory log is also captured through `hyprctl rollinglog`
when it changes, covering messages still buffered in its file. This read-only
query has a one-second timeout; a stalled compositor is recorded as a timeout
and does not prevent subsequent process samples. Rolling snapshots can overlap.

Hyprland normally disables disk logging after startup. For ongoing compositor
logs, add this to the local Lua configuration, then run
`hyprctl -i 0 reload config-only`:

```lua
hl.config({ debug = { disable_logs = false, disable_time = false } })
```

Hyprland 0.56.2 updates its logger on the configuration-reloaded event; setting
the values through `eval` alone does not update that logger. See the
[versioned logger source](https://github.com/hyprwm/Hyprland/blob/efb50993780079460b0cbed1363e2166a2de1d9f/src/debug/log/Logger.cpp).
This changes diagnostic verbosity only. The recorder itself does not change
Hyprland options, restart applications, query GPUs, or send network probes.

Logs are private to the user under
`~/.local/state/freeze-diagnostics/recorder/boot-<boot-id>/`. Each boot retains
eight segments of at most 8 MiB: `events.jsonl` is current, `.1` is the previous
segment, through `.7` oldest. Four boots are retained, totaling up to 256 MiB of
saved event data; application-owned source logs in `/run` are separate.
Retention removes only recorder-owned boot directories in this
dedicated folder; other incident reports are untouched. High-volume logs shorten
the retained time window.

Every completed sampling cycle calls `fdatasync`; segment changes also sync the
directory. A sudden power cut may still lose the unfinished cycle, and a kernel
or storage stall can prevent the recorder from running or flushing. This is
diagnostic evidence, not a guarantee of recovery or complete crash capture.

Read the most recent events with `tail`, or parse the JSON lines with Python.
Each event includes UTC and monotonic time. `scan_ms` records collector cost;
per-process CPU ticks use the `clock_ticks_per_second` in `recorder_started`.

```sh
journalctl --user -u freeze-recorder.service
systemctl --user disable --now freeze-recorder.service
```

Stopping leaves saved evidence intact. Remove the added Hyprland debug setting
and run `hyprctl -i 0 reload config-only` to restore its defaults.

For a bounded diagnostic run without installation:

```sh
python3 services/freeze-recorder/recorder.py --state-dir /tmp/freeze-recorder-check --samples 2
python3 tests/test_freeze_recorder.py
```
