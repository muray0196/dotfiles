import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: window
  property bool compact: false
  property bool showInk: true
  readonly property color inkColor: "#fafcff"
  property real left: 160
  property real top: 180
  property string clockText: "09:41"
  property string dateText: "Sunday, October 18"
  property bool liveClock: true
  property real bodyWidth: (compact ? 260 : 500) * (drag.pressed ? 0.985 : 1)
  property real bodyHeight: (compact ? 112 : 300) * (drag.pressed ? 0.985 : 1)
  readonly property real expansion: Math.max(0, Math.min(1, (bodyHeight - 112) / 188))
  anchors { top: true; left: true }
  margins { left: window.left; top: window.top }
  implicitWidth: Math.round(bodyWidth + 56)
  implicitHeight: Math.round(bodyHeight + 56)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "liquid-glass-v1"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: drag }
  Behavior on bodyWidth { SpringAnimation { spring: 4; damping: 0.42; mass: 1 } }
  Behavior on bodyHeight { SpringAnimation { spring: 4; damping: 0.42; mass: 1 } }
  Timer {
    interval: 1000
    running: window.liveClock
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      const now = new Date();
      window.clockText = Qt.formatDateTime(now, "HH:mm");
      window.dateText = Qt.formatDateTime(now, "dddd, MMMM d");
    }
  }
  Item {
    anchors.fill: parent
    anchors.margins: 28
    visible: window.showInk
    Text {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -12 * window.expansion
      text: window.clockText
      color: window.inkColor
      style: Text.Outline
      styleColor: "#700c1825"
      font.pixelSize: 42 + 36 * window.expansion
      font.weight: Font.Light
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height / 2 + 48
      text: window.dateText
      color: window.inkColor
      style: Text.Outline
      styleColor: "#800c1825"
      font.pixelSize: 18
      opacity: Math.max(0, Math.min(1, (window.bodyHeight - 140) / 100))
    }
  }
  MouseArea {
    id: drag
    anchors.fill: parent
    anchors.margins: 28
    property point start
    property point origin
    property real distance: 0
    onPressed: mouse => {
      start = mapToGlobal(mouse.x, mouse.y);
      origin = Qt.point(window.left, window.top);
      distance = 0;
    }
    onPositionChanged: mouse => {
      if (!pressed) return;
      const point = mapToGlobal(mouse.x, mouse.y);
      const dx = point.x - start.x, dy = point.y - start.y;
      distance = Math.max(distance, Math.hypot(dx, dy));
      if (distance > 4) {
        window.left = Math.max(0, Math.min(window.screen.width - 112, origin.x + dx));
        window.top = Math.max(0, Math.min(window.screen.height - 112, origin.y + dy));
      }
    }
    onReleased: if (distance <= 4) window.compact = !window.compact
  }
}
