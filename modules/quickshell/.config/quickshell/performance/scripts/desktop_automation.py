#!/usr/bin/env python3
"""Coordinate brightness, Waywallen, and scheduled DPMS with Main PC availability."""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from machine_config import DISABLED_MACHINE_CONFIG, MachineConfig


OFFLINE_AFTER_SECONDS = 10.0
DEFAULT_SETTINGS = Path.home() / ".config/quickshell/performance/automation.json"
DEFAULT_RUNTIME_STATE = (
    Path.home() / ".cache/quickshell/performance/automation-state.json"
)
BOOT_ID_PATH = Path("/proc/sys/kernel/random/boot_id")
HYPRCTL = "/usr/bin/hyprctl"
DPMS_OFF_DISPATCH = 'hl.dsp.dpms("off")'
DPMS_ON_DISPATCH = 'hl.dsp.dpms("on")'
DDCUTIL = "/usr/bin/ddcutil"
DISPLAY_STATE_POLL_SECONDS = 1.0
HYPRLAND_SOCKET_TIMEOUT = 0.5

CommandRunner = Callable[[Sequence[str]], bool]
DisplayPowerReader = Callable[[], bool]


@dataclass(frozen=True)
class DisplaySchedule:
    off_hour: int
    on_hour: int

    def __post_init__(self) -> None:
        hours = (("display off", self.off_hour), ("display on", self.on_hour))
        for label, hour in hours:
            if (
                isinstance(hour, bool)
                or not isinstance(hour, int)
                or not 0 <= hour <= 23
            ):
                raise ValueError(f"{label} hour must be an integer from 0 to 23")
        if self.off_hour == self.on_hour:
            raise ValueError("display off and on hours must differ")


DEFAULT_DISPLAY_SCHEDULE = DisplaySchedule(off_hour=0, on_hour=7)


@dataclass(frozen=True)
class AutomationSettings:
    display_schedule: DisplaySchedule
    waywallen_link_enabled: bool

    def __post_init__(self) -> None:
        if not isinstance(self.waywallen_link_enabled, bool):
            raise ValueError("Waywallen linkage setting must be a boolean")


DEFAULT_AUTOMATION_SETTINGS = AutomationSettings(
    display_schedule=DEFAULT_DISPLAY_SCHEDULE,
    waywallen_link_enabled=True,
)


def load_automation_settings(path: Path = DEFAULT_SETTINGS) -> AutomationSettings:
    """Read desktop settings, falling back to the original behavior."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return DEFAULT_AUTOMATION_SETTINGS

    if not isinstance(data, dict):
        raise ValueError("desktop automation settings must be a JSON object")
    return AutomationSettings(
        display_schedule=DisplaySchedule(
            off_hour=data.get("display_off_hour"),
            on_hour=data.get("display_on_hour"),
        ),
        waywallen_link_enabled=data.get("waywallen_link_enabled", True),
    )


def load_display_schedule(path: Path = DEFAULT_SETTINGS) -> DisplaySchedule:
    return load_automation_settings(path).display_schedule


@dataclass(frozen=True)
class AutomationRuntimeState:
    main_pc_online: bool | None
    off_window: bool | None
    waywallen_applied: bool | None
    display_power_off: bool | None
    display_off_pending: bool
    display_on_pending: bool

    def __post_init__(self) -> None:
        optional_values = (
            ("Main PC state", self.main_pc_online),
            ("display window state", self.off_window),
            ("Waywallen state", self.waywallen_applied),
            ("display power state", self.display_power_off),
        )
        for label, value in optional_values:
            if value is not None and not isinstance(value, bool):
                raise ValueError(f"{label} must be a boolean or null")
        for label, value in (
            ("display off pending", self.display_off_pending),
            ("display on pending", self.display_on_pending),
        ):
            if not isinstance(value, bool):
                raise ValueError(f"{label} must be a boolean")


def current_boot_id() -> str:
    boot_id = BOOT_ID_PATH.read_text(encoding="utf-8").strip()
    if not boot_id:
        raise ValueError("system boot ID is empty")
    return boot_id


def load_runtime_state(
    path: Path, boot_id: str
) -> AutomationRuntimeState | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None

    if not isinstance(data, dict):
        raise ValueError("desktop automation runtime state must be a JSON object")
    if data.get("schema_version") != 1 or data.get("boot_id") != boot_id:
        return None
    return AutomationRuntimeState(
        main_pc_online=data.get("main_pc_online"),
        off_window=data.get("off_window"),
        waywallen_applied=data.get("waywallen_applied"),
        display_power_off=data.get("display_power_off"),
        display_off_pending=data.get("display_off_pending"),
        display_on_pending=data.get("display_on_pending"),
    )


def save_runtime_state(
    path: Path, boot_id: str, state: AutomationRuntimeState
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent, text=True
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as state_file:
            json.dump(
                {
                    "schema_version": 1,
                    "boot_id": boot_id,
                    "main_pc_online": state.main_pc_online,
                    "off_window": state.off_window,
                    "waywallen_applied": state.waywallen_applied,
                    "display_power_off": state.display_power_off,
                    "display_off_pending": state.display_off_pending,
                    "display_on_pending": state.display_on_pending,
                },
                state_file,
                separators=(",", ":"),
            )
            state_file.write("\n")
            state_file.flush()
            os.fsync(state_file.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def read_display_power_off() -> bool:
    """Return true when every active Hyprland monitor has DPMS off."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        raise OSError("HYPRLAND_INSTANCE_SIGNATURE is not set")

    socket_path = Path(runtime_dir) / "hypr" / signature / ".socket.sock"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(HYPRLAND_SOCKET_TIMEOUT)
        connection.connect(str(socket_path))
        connection.sendall(b"j/monitors")
        chunks: list[bytes] = []
        while chunk := connection.recv(65536):
            chunks.append(chunk)

    monitors = json.loads(b"".join(chunks))
    if not isinstance(monitors, list):
        raise ValueError("Hyprland monitor response must be a JSON array")

    active_statuses: list[bool] = []
    for monitor in monitors:
        if not isinstance(monitor, dict):
            raise ValueError("Hyprland monitor entry must be a JSON object")
        if monitor.get("disabled") is True:
            continue
        dpms_status = monitor.get("dpmsStatus")
        if not isinstance(dpms_status, bool):
            raise ValueError("Hyprland monitor DPMS state is missing")
        active_statuses.append(dpms_status)

    return not any(active_statuses)


def waywallen_dispatch(action: str, control_path: Path) -> str:
    if action not in {"on", "off"}:
        raise ValueError("Waywallen action must be on or off")
    return f'hl.dsp.exec_cmd("{control_path} {action}")'


def run_command(command: Sequence[str]) -> bool:
    """Run a desktop command without feeding output into Quickshell."""
    try:
        result = subprocess.run(
            command,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except OSError as error:
        print(
            f"desktop automation command failed: {command[0]}: {error}",
            file=sys.stderr,
            flush=True,
        )
        return False

    if result.returncode != 0:
        detail = result.stderr.strip() or f"exit status {result.returncode}"
        print(
            f"desktop automation command failed: {command[0]}: {detail}",
            file=sys.stderr,
            flush=True,
        )
        return False
    return True


def is_display_off_window(
    moment: datetime, schedule: DisplaySchedule = DEFAULT_DISPLAY_SCHEDULE
) -> bool:
    if schedule.off_hour < schedule.on_hour:
        return schedule.off_hour <= moment.hour < schedule.on_hour
    return moment.hour >= schedule.off_hour or moment.hour < schedule.on_hour


class DesktopAutomation:
    """Apply state transitions without issuing duplicate desktop commands."""

    def __init__(
        self,
        offline_after: float = OFFLINE_AFTER_SECONDS,
        *,
        settings_path: Path = DEFAULT_SETTINGS,
        runtime_state_path: Path = DEFAULT_RUNTIME_STATE,
        boot_id: str | None = None,
        monotonic: Callable[[], float] = time.monotonic,
        now: Callable[[], datetime] = datetime.now,
        command_runner: CommandRunner = run_command,
        display_power_reader: DisplayPowerReader = read_display_power_off,
        machine_config: MachineConfig = DISABLED_MACHINE_CONFIG,
    ) -> None:
        if offline_after <= 0:
            raise ValueError("offline timeout must be greater than zero")

        self.offline_after = offline_after
        self.settings_path = settings_path
        self.runtime_state_path = runtime_state_path
        self._boot_id = current_boot_id() if boot_id is None else boot_id
        self._monotonic = monotonic
        self._now = now
        self._command_runner = command_runner
        self._display_power_reader = display_power_reader
        self._machine_config = machine_config
        self._started_at = monotonic()
        self._last_heartbeat: float | None = None
        self._main_pc_online: bool | None = None
        self._off_window: bool | None = None
        self._display_schedule = DEFAULT_DISPLAY_SCHEDULE
        self._waywallen_link_enabled = True
        self._waywallen_applied: bool | None = None
        self._brightness_applied: int | None = None
        self._brightness_retry_at = 0.0
        self._settings_error: str | None = None
        self._runtime_error: str | None = None
        self._display_state_error: str | None = None
        self._display_state_poll_at = 0.0
        self._display_power_off: bool | None = None
        self._display_off_pending = False
        self._display_on_pending = False
        self._restore_runtime_state()

    def _restore_runtime_state(self) -> None:
        try:
            state = load_runtime_state(self.runtime_state_path, self._boot_id)
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            print(
                f"desktop automation runtime state failed: {error}",
                file=sys.stderr,
                flush=True,
            )
            return
        if state is None:
            return

        self._main_pc_online = state.main_pc_online
        self._off_window = state.off_window
        self._waywallen_applied = state.waywallen_applied
        self._display_power_off = state.display_power_off
        self._display_off_pending = state.display_off_pending
        self._display_on_pending = state.display_on_pending

    def _persist_runtime_state(self) -> None:
        state = AutomationRuntimeState(
            main_pc_online=self._main_pc_online,
            off_window=self._off_window,
            waywallen_applied=self._waywallen_applied,
            display_power_off=self._display_power_off,
            display_off_pending=self._display_off_pending,
            display_on_pending=self._display_on_pending,
        )
        try:
            save_runtime_state(self.runtime_state_path, self._boot_id, state)
        except OSError as error:
            detail = str(error)
            if detail != self._runtime_error:
                print(
                    f"desktop automation runtime state failed: {detail}",
                    file=sys.stderr,
                    flush=True,
                )
                self._runtime_error = detail
            return
        self._runtime_error = None

    def heartbeat(self) -> None:
        """Record a successful JSON response from the Main PC."""
        self._last_heartbeat = self._monotonic()
        self._sync_display_window()
        self._set_main_pc_online(True)

    def tick(self) -> None:
        """Reconcile time transitions and heartbeat expiry."""
        current = self._monotonic()
        self._sync_display_window()
        self._sync_display_power_state(current)

        if self._last_heartbeat is None:
            if current - self._started_at >= self.offline_after:
                self._set_main_pc_online(False)
        elif current - self._last_heartbeat >= self.offline_after:
            self._set_main_pc_online(False)

        self._apply_waywallen()
        self._apply_brightness()
        self._retry_display_command()

    def _set_main_pc_online(self, online: bool) -> None:
        previous = self._main_pc_online
        if previous is online:
            self._apply_brightness()
            return

        self._main_pc_online = online
        self._brightness_retry_at = 0.0
        self._apply_waywallen(force=True)
        self._apply_brightness()
        self._persist_runtime_state()

        if self._off_window is not True:
            return
        if online:
            # A Main PC recovery rearms the next shutdown without waking a
            # display that is already off. This also makes a manual DPMS-on a
            # temporary override instead of cancelling later shutdowns.
            self._request_display_off()
        elif previous is None:
            self._request_display_off()
        elif previous and self._display_off_pending:
            self._turn_display_off()

    def _apply_waywallen(self, *, force: bool = False) -> None:
        control_path = self._machine_config.waywallen_control
        if control_path is None:
            return

        if self._display_power_off is True:
            desired = False
        elif not self._waywallen_link_enabled:
            return
        else:
            desired = self._main_pc_online

        if desired is None or (not force and desired == self._waywallen_applied):
            return

        action = "on" if desired else "off"
        command = [
            HYPRCTL,
            "dispatch",
            waywallen_dispatch(action, control_path),
        ]
        if self._command_runner(command):
            self._waywallen_applied = desired
            self._persist_runtime_state()

    def _apply_brightness(self) -> None:
        machine = self._machine_config
        if not machine.ddc_enabled:
            return
        if self._main_pc_online is None or self._display_power_off is True:
            return

        desired = (
            machine.online_brightness
            if self._main_pc_online
            else machine.offline_brightness
        )
        if desired == self._brightness_applied:
            return

        current = self._monotonic()
        if current < self._brightness_retry_at:
            return

        command = [
            DDCUTIL,
            "--bus",
            str(machine.ddc_bus),
            "setvcp",
            machine.brightness_feature,
            str(desired),
        ]
        if self._command_runner(command):
            self._brightness_applied = desired
            self._brightness_retry_at = 0.0
        else:
            self._brightness_retry_at = (
                current + machine.brightness_retry_seconds
            )

    def _sync_display_window(self) -> None:
        self._refresh_automation_settings()
        off_window = is_display_off_window(self._now(), self._display_schedule)
        if off_window == self._off_window:
            return

        self._off_window = off_window
        if off_window:
            self._display_on_pending = False
            if self._main_pc_online is not None:
                self._request_display_off()
        else:
            self._display_off_pending = False
            self._display_on_pending = True
            self._turn_display_on()
        self._persist_runtime_state()

    def _sync_display_power_state(self, current: float) -> None:
        if current < self._display_state_poll_at:
            return
        self._display_state_poll_at = current + DISPLAY_STATE_POLL_SECONDS

        try:
            display_power_off = self._display_power_reader()
            if not isinstance(display_power_off, bool):
                raise ValueError("display power state must be a boolean")
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            detail = str(error)
            if detail != self._display_state_error:
                print(
                    f"display power state failed: {detail}",
                    file=sys.stderr,
                    flush=True,
                )
                self._display_state_error = detail
            return

        self._display_state_error = None
        if display_power_off == self._display_power_off:
            return

        self._display_power_off = display_power_off
        if not display_power_off:
            self._brightness_retry_at = 0.0
        self._persist_runtime_state()
        self._apply_waywallen(force=True)

    def _refresh_automation_settings(self) -> None:
        try:
            settings = load_automation_settings(self.settings_path)
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
            detail = str(error)
            if detail != self._settings_error:
                print(
                    f"desktop automation settings failed: {detail}",
                    file=sys.stderr,
                    flush=True,
                )
                self._settings_error = detail
            return

        self._settings_error = None
        self._display_schedule = settings.display_schedule
        if self._waywallen_link_enabled != settings.waywallen_link_enabled:
            self._waywallen_link_enabled = settings.waywallen_link_enabled
            self._waywallen_applied = None
            self._persist_runtime_state()

    def _request_display_off(self) -> None:
        self._display_off_pending = True
        self._persist_runtime_state()
        if self._main_pc_online is False:
            self._turn_display_off()

    def _turn_display_off(self) -> None:
        if self._main_pc_online is False:
            self._apply_brightness()
        if self._command_runner([HYPRCTL, "dispatch", DPMS_OFF_DISPATCH]):
            self._display_power_off = True
            self._display_off_pending = False
            self._persist_runtime_state()
            self._apply_waywallen(force=True)

    def _turn_display_on(self) -> None:
        if self._command_runner([HYPRCTL, "dispatch", DPMS_ON_DISPATCH]):
            self._display_power_off = False
            self._display_on_pending = False
            self._brightness_retry_at = 0.0
            self._apply_brightness()
            self._persist_runtime_state()
            self._apply_waywallen(force=True)

    def _retry_display_command(self) -> None:
        if self._off_window is True:
            if self._display_off_pending and self._main_pc_online is False:
                self._turn_display_off()
        elif self._display_on_pending:
            self._turn_display_on()
