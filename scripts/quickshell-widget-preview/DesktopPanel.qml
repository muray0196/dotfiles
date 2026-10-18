pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Layout.js" as Layout

PanelWindow {
  id: window
  required property var state
  property bool leftSide: false
  readonly property real contentScale: Math.min(1, (screen.height - 2 * Layout.topInset) / Layout.panelHeight, (screen.width - 144) / 1000)
  anchors { top: true; left: window.leftSide; right: !window.leftSide }
  // Keep the full shadow padding; only its outermost 16 px extend offscreen.
  margins { top: Layout.topInset - Layout.shadowPadding; left: Layout.sideInset - Layout.shadowPadding; right: Layout.sideInset - Layout.shadowPadding }
  implicitWidth: Math.round(Layout.panelWidth * contentScale) + 2 * Layout.shadowPadding
  implicitHeight: Math.round(Layout.panelHeight * contentScale) + 2 * Layout.shadowPadding
  color: "transparent"
  visible: state.shown
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "liquid-glass-v1"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: body }

  Item {
    id: body
    anchors.fill: parent
    anchors.margins: Layout.shadowPadding
    PanelContent {
      state: window.state
      leftSide: window.leftSide
      scale: window.contentScale
      transformOrigin: Item.TopLeft
    }
  }
}
