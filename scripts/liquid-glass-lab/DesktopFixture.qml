pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
  id: shell
  property bool moving: false
  property real phase: 0
  property int pattern: 0
  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    color: "#164b76"
  }
  FloatingWindow {
    title: "Independent Liquid Glass desktop fixture"
    implicitWidth: 1000
    implicitHeight: 700
    visible: true
    color: "#264665"
    Item {
      anchors.fill: parent
      clip: true
      Image {
        width: parent.width + 80
        height: parent.height
        source: "flower.png"
        fillMode: Image.PreserveAspectCrop
        visible: shell.pattern === 0
        x: -40 + Math.sin(shell.phase) * 30
      }
      Rectangle {
        anchors.fill: parent
        visible: shell.pattern !== 0
        color: shell.pattern === 1 ? "#b8c3d0" : "#19354d"
        Repeater {
          model: 24
          Rectangle {
            required property int index
            x: index * 90 + Math.sin(shell.phase) * 40
            width: 12; height: parent.height
            color: "#f5ab28"
          }
        }
      }
    }
    FrameAnimation {
      running: shell.moving
      onTriggered: shell.phase += frameTime * 1.2
    }
  }
  IpcHandler {
    target: "fixture"
    function motion(value: bool): void { shell.moving = value; }
    function phase(value: real): void { shell.phase = value; }
    function pattern(value: int): void { shell.pattern = value; }
  }
}
