import Quickshell
import Quickshell.Io

ShellRoot {
  DesktopWidget { id: widget }
  IpcHandler {
    target: "glass"
    function visible(value: bool): void { widget.visible = value; }
    function compact(value: bool): void { widget.compact = value; }
    function ink(value: bool): void { widget.showInk = value; }
    function move(x: real, y: real): void { widget.left = x; widget.top = y; }
    function fixedClock(): void { widget.liveClock = false; widget.clockText = "09:41"; }
  }
}
