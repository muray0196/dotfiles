import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#194c77"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "liquid-glass-probe-background"
  }
  FloatingWindow {
    title: "Liquid Glass backdrop probe"
    implicitWidth: 640
    implicitHeight: 400
    color: "#edaa32"
    visible: true
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 40
      text: "Independent Wayland window beneath the marker"
      color: "#281e0a"
      font.pixelSize: 20
    }
    // This tiny animated surface schedules frames after the plugin is loaded.
    Rectangle {
      width: 10
      height: 10
      color: "#29b687"
      SequentialAnimation on x {
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 20; duration: 500 }
        NumberAnimation { from: 20; to: 0; duration: 500 }
      }
    }
  }
  PanelWindow {
    implicitWidth: 160
    implicitHeight: 160
    color: "#ff00ff"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "liquid-glass-probe-marker"
  }
}
