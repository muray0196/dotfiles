import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: desktop
  PersistentProperties {
    id: preference
    reloadableId: "liquid-glass-widgets"
    property bool shown: true
    property bool darkText: Quickshell.env("WIDGET_TEXT") === "dark"
  }
  property alias shown: preference.shown
  property alias darkText: preference.darkText
  readonly property bool snapshotMode: !!Quickshell.env("WIDGET_SNAPSHOT")
  property var frozen: null
  property var readings: ({demo: false, holidays: {}})
  property date clockDate: frozen ? new Date(frozen.clockDate) : clock.date
  property double receivedAt: 0
  DesktopPanel { id: localPanel; state: desktop; kind: "local" }
  DesktopPanel { id: mainPanel; state: desktop; kind: "main" }
  DesktopPanel { id: clockPanel; state: desktop; kind: "clock" }
  DesktopPanel { id: dayPanel; state: desktop; kind: "day" }
  DesktopPanel { id: radarPanel; state: desktop; kind: "radar" }
  SystemClock { id: clock; precision: SystemClock.Seconds }
  FileView {
    path: Quickshell.env("WIDGET_SNAPSHOT")
    onLoaded: {
      const snapshot = JSON.parse(text());
      desktop.frozen = snapshot;
      desktop.readings = snapshot.readings;
      desktop.darkText = snapshot.darkText;
      desktop.receivedAt = Date.now();
    }
  }
  Process {
    id: collector
    command: ["/usr/bin/python3", "-B", Quickshell.env("WIDGET_SOURCE") + "/runtime.py"].concat(Quickshell.env("WIDGET_AUTOMATION") === "1" ? ["--automation"] : [])
    running: !desktop.snapshotMode
    stdout: SplitParser {
      onRead: line => {
        try { desktop.readings = JSON.parse(line); desktop.receivedAt = Date.now(); }
        catch (error) { console.warn("Widget runtime returned invalid data"); }
      }
    }
    onExited: if (!desktop.snapshotMode) restart.restart()
  }
  Timer { id: restart; interval: 5000; onTriggered: collector.running = true }
  Timer {
    interval: 2000; running: !desktop.snapshotMode; repeat: true
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
    function snapshot(): string {
      return JSON.stringify({readings: desktop.readings, clockDate: desktop.clockDate.toISOString(),
        darkText: desktop.darkText, radar: radarPanel.radarState(),
        panels: [localPanel, mainPanel, clockPanel, dayPanel, radarPanel].map(panel => panel.layout())});
    }
    function state(): string {
      return JSON.stringify({visible: desktop.shown, darkText: desktop.darkText,
        receivedAt: desktop.receivedAt, local: (desktop.readings.local || {})._status,
        main: (desktop.readings.main || {})._status, indoor: (desktop.readings.indoor || {})._status,
        outdoor: (desktop.readings.outdoor || {})._status, radar: (desktop.readings.radar || {})._status,
        snapshot: desktop.snapshotMode && desktop.frozen !== null,
        automation: !desktop.snapshotMode && Quickshell.env("WIDGET_AUTOMATION") === "1"});
    }
  }
}
