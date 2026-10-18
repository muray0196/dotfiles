pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "Layout.js" as Layout

PanelWindow {
  id: window
  required property var state
  required property string kind
  readonly property var geometry: Layout.panel(kind, state.readings)
  readonly property real contentScale: Math.min(1, (screen.height - 2 * Layout.topInset) / Layout.panelHeight, (screen.width - 144) / 1000)
  anchors { top: true; left: window.geometry.left; right: !window.geometry.left }
  // Keep the full shadow padding; only its outermost 16 px extend offscreen.
  margins { top: Layout.topInset + Math.round(window.geometry.y * window.contentScale) - Layout.shadowPadding; left: Layout.sideInset - Layout.shadowPadding; right: Layout.sideInset - Layout.shadowPadding }
  implicitWidth: Math.round(Layout.panelWidth * contentScale) + 2 * Layout.shadowPadding
  implicitHeight: Math.round(geometry.height * contentScale) + 2 * Layout.shadowPadding
  color: "transparent"
  visible: state.shown
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "liquid-glass-v1"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region { item: body }
  function layout() {
    return {kind: kind, width: implicitWidth, height: implicitHeight, top: margins.top,
      left: geometry.left, side: geometry.left ? margins.left : margins.right,
      contentScale: contentScale, screen: {width: screen.width, height: screen.height}};
  }
  function radarState() { return content.radarState(); }

  Item {
    id: body
    anchors.fill: parent
    anchors.margins: Layout.shadowPadding
    PanelContent {
      id: content
      state: window.state
      kind: window.kind
      frozenRadar: window.state.frozen ? window.state.frozen.radar : null
      scale: window.contentScale
      transformOrigin: Item.TopLeft
    }
  }
}
