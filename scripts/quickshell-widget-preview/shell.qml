import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  FloatingWindow {
    title: "Quickshell · Liquid Glass widget study"
    implicitWidth: 1920
    implicitHeight: 1080
    minimumSize: Qt.size(1280, 720)
    color: "#121821"
    visible: true
    Item {
      anchors.centerIn: parent
      width: 1920; height: 1080
      scale: Math.min(parent.width / width, parent.height / height)
      Composition {
        id: scene
        anchors.fill: parent
        darkText: Quickshell.env("WIDGET_PREVIEW_TEXT") === "dark"
        direction: Number(Quickshell.env("WIDGET_PREVIEW_DIRECTION") || "0")
        background: Number(Quickshell.env("WIDGET_PREVIEW_BACKGROUND") || "0")
      }
    }
  }
  Process {
    command: ["/usr/bin/python3", "-B", Quickshell.env("WIDGET_PREVIEW_SOURCE") + "/collect.py", "--stream"]
    running: Quickshell.env("WIDGET_PREVIEW_LIVE") === "1"
    stdout: SplitParser {
      onRead: line => {
        try { scene.readings = JSON.parse(line); } catch (error) { console.warn("Preview collector: invalid JSON"); }
      }
    }
  }
  IpcHandler {
    target: "preview"
    function foreground(dark: bool): void { scene.darkText = dark; }
    function backdrop(index: int): void { scene.background = Math.max(0, Math.min(4, index)); }
    function direction(index: int): void { scene.direction = Math.max(0, Math.min(2, index)); }
    function scenario(index: int): void { scene.scenario = Math.max(0, Math.min(2, index)); }
    function capture(path: string): void {
      scene.grabToImage(result => result.saveToFile(path));
    }
    function state(): string { return JSON.stringify({demo: scene.readings.demo, local: (scene.readings.local || {})._status, main: (scene.readings.main || {})._status, clock: scene.clockDate, darkText: scene.darkText, background: scene.background}); }
  }
  Timer {
    interval: 1000; repeat: true; running: Quickshell.env("WIDGET_PREVIEW_LIVE") === "1"
    onTriggered: scene.clockDate = new Date()
  }
}
