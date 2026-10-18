import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
  id: fixture
  property int background: 0
  property bool moving: false
  property real phase: 0
  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "widget-validation-background"
    color: "#121821"
    Item {
      anchors.fill: parent
      clip: true
      Image {
        x: -48 + 44 * Math.sin(fixture.phase); y: -12
        width: parent.width + 96; height: parent.height + 24
        source: "flower.png"; fillMode: Image.PreserveAspectCrop
        visible: fixture.background === 0
      }
      Image { id: desert; source: "desert.png"; visible: false }
      ShaderEffect {
        anchors.fill: parent; visible: fixture.background === 1
        property Item source: desert
        property vector2d viewSize: Qt.vector2d(width, height)
        property real sourceScale: 1.01 / (1 + 0.02 * (1 - Math.cos(fixture.phase)))
        fragmentShader: "desert.frag.qsb"
      }
      FrameAnimation { running: fixture.moving; onTriggered: fixture.phase += frameTime }
    }
  }
  IpcHandler {
    target: "fixture"
    function background(value: int): void { fixture.background = value; }
    function moving(value: bool): void { fixture.moving = value; }
  }
}
