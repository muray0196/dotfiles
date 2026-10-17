import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
  id: root
  readonly property var display: Quickshell.screens.find(s => s.name === Quickshell.env("GLASS_REFERENCE_SCREEN")) || Quickshell.screens[0]
  readonly property real sceneScale: Math.min(1, (display.width - 64) / 1531, (display.height - 220) / 611)
  readonly property real sceneX: Math.round((display.width - 1531 * sceneScale) / 2)
  readonly property real sceneY: Math.round((display.height - 611 * sceneScale) / 2)
  property string backdrop: "flower"
  property bool original: false
  property bool glassVisible: true
  property bool iconsVisible: true
  property real offset: 0

  function moveBackground(amount: real): void {
    offset = Math.max(-350, Math.min(350, offset + amount));
  }

  IpcHandler {
    target: "reference"
    function quit(): void { Qt.quit(); }
    function background(value: string): void {
      if (["flower", "blue", "white", "dark", "grid"].indexOf(value) !== -1) {
        root.backdrop = value;
        root.original = false;
      }
    }
    function shift(value: real): void { root.offset = Math.max(-350, Math.min(350, value)); }
    function showOriginal(value: bool): void { root.original = value; }
    function showGlass(value: bool): void { root.glassVisible = value; }
    function showIcons(value: bool): void { root.iconsVisible = value; }
  }

  component Choice: Rectangle {
    required property string label
    property bool selected: false
    signal clicked()
    width: text.implicitWidth + 28
    height: 36
    radius: 18
    color: selected ? "#eef3fa" : area.containsMouse ? "#354253" : "#25303e"
    Text {
      id: text
      anchors.centerIn: parent
      text: parent.label
      font.pixelSize: 14
      color: parent.selected ? "#182331" : "#e7edf5"
    }
    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      onClicked: parent.clicked()
    }
  }

  component BackgroundPlate: Item {
    clip: true
    Rectangle {
      anchors.fill: parent
      color: ({ flower: "#579dc8", blue: "#579dc8", white: "#ffffff", dark: "#171c28", grid: "#dce5ee" })[root.backdrop]
    }
    Image {
      x: root.offset * root.sceneScale
      width: parent.width
      height: parent.height
      source: "flower.png"
      fillMode: Image.Stretch
      visible: root.backdrop === "flower"
    }
    Canvas {
      id: grid
      anchors.fill: parent
      visible: root.backdrop === "grid"
      onVisibleChanged: requestPaint()
      Connections { target: root; function onOffsetChanged() { grid.requestPaint(); } }
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.strokeStyle = "#365879";
        ctx.lineWidth = 2 * root.sceneScale;
        const step = 32 * root.sceneScale;
        const phase = root.offset * root.sceneScale % step;
        ctx.beginPath();
        for (let x = phase; x <= width; x += step) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
        for (let y = 0; y <= height; y += step) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
        ctx.stroke();
      }
    }
    Image {
      anchors.fill: parent
      source: "reference.png"
      fillMode: Image.Stretch
      visible: root.original
    }
  }

  PanelWindow {
    id: backgroundWindow
    screen: root.display
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-glass-reference-background"
    WlrLayershell.keyboardFocus: Quickshell.env("GLASS_REFERENCE_INTERACTIVE") === "0" ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusiveZone: 0
    color: "#141c27"

    Item {
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: Qt.quit()
      Keys.onLeftPressed: root.moveBackground(-40)
      Keys.onRightPressed: root.moveBackground(40)
      Keys.onSpacePressed: root.iconsVisible = !root.iconsVisible
      Keys.onPressed: event => {
        if (event.key === Qt.Key_R) { root.original = !root.original; event.accepted = true; }
      }

      Text {
        x: root.sceneX
        y: root.sceneY - 87
        text: root.original ? "Original reference" : "Clear · circular controls"
        color: "#f0f4fa"
        font.pixelSize: 25
        font.weight: Font.DemiBold
      }
      Text {
        x: root.sceneX
        y: root.sceneY - 51
        text: root.original ? "Apple reference supplied in this conversation" : "Reconstructed flower backdrop · current desktop glass"
        color: "#9cacc0"
        font.pixelSize: 14
      }
      Choice {
        x: root.sceneX + 1531 * root.sceneScale - width
        y: root.sceneY - 75
        label: "Close  ×"
        onClicked: Qt.quit()
      }

      BackgroundPlate {
        x: root.sceneX
        y: root.sceneY
        width: 1531 * root.sceneScale
        height: 611 * root.sceneScale
      }

      Row {
        x: root.sceneX
        y: root.sceneY + 611 * root.sceneScale + 24
        spacing: 8
        scale: root.sceneScale
        transformOrigin: Item.TopLeft
        Choice { label: "Live glass"; selected: !root.original; onClicked: root.original = false }
        Choice { label: "Original"; selected: root.original; onClicked: root.original = true }
        Item { width: 12; height: 1 }
        Repeater {
          model: ["flower", "blue", "white", "dark", "grid"]
          Choice {
            required property string modelData
            label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
            selected: !root.original && root.backdrop === modelData
            onClicked: { root.backdrop = modelData; root.original = false; }
          }
        }
        Item { width: 12; height: 1 }
        Choice { label: "Icons"; selected: root.iconsVisible; onClicked: root.iconsVisible = !root.iconsVisible }
        Choice { label: "Glass"; selected: root.glassVisible; onClicked: root.glassVisible = !root.glassVisible }
        Choice { label: "←"; onClicked: root.moveBackground(-40) }
        Choice { label: "Reset"; onClicked: root.offset = 0 }
        Choice { label: "→"; onClicked: root.moveBackground(40) }
      }
      Text {
        x: root.sceneX
        y: root.sceneY + 611 * root.sceneScale + 77
        text: "← →  Move background     Space  Toggle icons     R  Original / live     Esc  Close"
        font.pixelSize: 13
        color: "#9cacc0"
      }
    }
  }

  component GlassCircle: PanelWindow {
    id: circle
    required property real sourceX
    required property real sourceY
    required property real diameter
    required property string symbol
    screen: root.display
    anchors { top: true; left: true }
    margins { left: Math.round(root.sceneX + sourceX * root.sceneScale); top: Math.round(root.sceneY + sourceY * root.sceneScale) }
    implicitWidth: Math.round(diameter * root.sceneScale)
    implicitHeight: implicitWidth
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-glass-reference"
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}
    // Keep the native surfaces mapped while comparing; only their alpha mask
    // changes. This avoids destroying/recreating three render targets per toggle.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "#0c151a24"
      visible: root.glassVisible && !root.original
    }
    Canvas {
      id: icon
      anchors.fill: parent
      visible: root.iconsVisible && root.glassVisible && !root.original
      onVisibleChanged: if (visible) requestPaint()
      readonly property string symbol: circle.symbol
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.scale(width, height);
        ctx.fillStyle = "#fffff8";
        function bar(x, y, w, h, r) {
          ctx.beginPath(); ctx.moveTo(x+r,y); ctx.lineTo(x+w-r,y);
          ctx.quadraticCurveTo(x+w,y,x+w,y+r); ctx.lineTo(x+w,y+h-r);
          ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h); ctx.lineTo(x+r,y+h);
          ctx.quadraticCurveTo(x,y+h,x,y+h-r); ctx.lineTo(x,y+r);
          ctx.quadraticCurveTo(x,y,x+r,y); ctx.fill();
        }
        if (symbol === "pause") {
          bar(.318, .278, .14, .442, .035);
          bar(.516, .278, .14, .442, .035);
        } else {
          if (symbol === "next") { ctx.translate(1,0); ctx.scale(-1,1); }
          bar(.286, .334, .102, .328, .023);
          ctx.beginPath(); ctx.moveTo(.402,.48); ctx.lineTo(.644,.338);
          ctx.quadraticCurveTo(.678,.32,.678,.357); ctx.lineTo(.678,.645);
          ctx.quadraticCurveTo(.678,.68,.644,.661); ctx.lineTo(.402,.521);
          ctx.quadraticCurveTo(.369,.501,.402,.48); ctx.fill();
        }
      }
    }
  }

  GlassCircle { sourceX: 76; sourceY: 129; diameter: 304; symbol: "previous" }
  GlassCircle { sourceX: 481; sourceY: 65; diameter: 434; symbol: "pause" }
  GlassCircle { sourceX: 1027; sourceY: 129; diameter: 304; symbol: "next" }
  // An opaque comparison plate covers both the optical surface and its native
  // shadow. Glass surfaces stay mapped underneath to preserve their textures.
  PanelWindow {
    screen: root.display
    anchors { top: true; left: true }
    margins { left: root.sceneX; top: root.sceneY }
    implicitWidth: Math.round(1531 * root.sceneScale)
    implicitHeight: Math.round(611 * root.sceneScale)
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-glass-reference-cover"
    exclusiveZone: 0
    visible: root.original || !root.glassVisible
    color: "transparent"
    mask: Region {}
    BackgroundPlate { anchors.fill: parent }
  }
}
