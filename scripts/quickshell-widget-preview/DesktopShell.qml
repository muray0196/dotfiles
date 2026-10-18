import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: desktop
  PersistentProperties {
    id: preference
    reloadableId: "liquid-glass-widgets"
    property bool shown: true
  }
  property alias shown: preference.shown
  property bool darkText: Quickshell.env("WIDGET_TEXT") === "dark"
  property var readings: ({demo: false, holidays: {}})
  property date clockDate: clock.date
  property double receivedAt: 0
  DesktopPanel { state: desktop; leftSide: true }
  DesktopPanel { state: desktop }
  SystemClock { id: clock; precision: SystemClock.Seconds }
  Process {
    id: collector
    command: ["/usr/bin/python3", "-B", Quickshell.env("WIDGET_SOURCE") + "/runtime.py"].concat(Quickshell.env("WIDGET_AUTOMATION") === "1" ? ["--automation"] : [])
    running: true
    stdout: SplitParser {
      onRead: line => {
        try { desktop.readings = JSON.parse(line); desktop.receivedAt = Date.now(); }
        catch (error) { console.warn("Widget runtime returned invalid data"); }
      }
    }
    onExited: restart.restart()
  }
  Timer { id: restart; interval: 5000; onTriggered: collector.running = true }
  Timer {
    interval: 2000; running: true; repeat: true
    onTriggered: {
      if (desktop.receivedAt && Date.now() - desktop.receivedAt > 6000) {
        const next = Object.assign({}, desktop.readings);
        next.local = Object.assign({}, next.local || {}, {_status: "Stale"});
        next.main = Object.assign({}, next.main || {}, {_status: "No signal"});
        next.indoor = Object.assign({}, next.indoor || {}, {_status: "Stale"});
        next.outdoor = Object.assign({}, next.outdoor || {}, {_status: "Cached"});
        desktop.readings = next;
      }
    }
  }
  IpcHandler {
    target: "widgets"
    property bool visible: desktop.shown
    function showWidgets(): void { desktop.shown = true; }
    function hideWidgets(): void { desktop.shown = false; }
    function foreground(dark: bool): void { desktop.darkText = dark; }
    function state(): string {
      return JSON.stringify({visible: desktop.shown, darkText: desktop.darkText,
        receivedAt: desktop.receivedAt, local: (desktop.readings.local || {})._status,
        main: (desktop.readings.main || {})._status, indoor: (desktop.readings.indoor || {})._status,
        outdoor: (desktop.readings.outdoor || {})._status, radar: (desktop.readings.radar || {})._status,
        automation: Quickshell.env("WIDGET_AUTOMATION") === "1"});
    }
  }
}
