pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Format.js" as F

Item {
  id: icon
  required property var scene
  required property bool cpu
  required property string description
  width: 18; height: width
  Accessible.role: Accessible.StaticText
  Accessible.name: description
  MultiEffect {
    anchors.fill: glyph; anchors.topMargin: 1; anchors.bottomMargin: -1; z: -1
    source: glyph; colorization: 1
    colorizationColor: icon.scene.darkText ? "#ffffff" : "#0d1620"
    opacity: icon.scene.darkText ? 0.6 : 0.85
    blurEnabled: true; blur: 1; blurMax: 4
  }
  Image {
    id: glyph
    anchors.fill: parent
    source: F.deviceIcon(icon.cpu, icon.scene.darkText)
    sourceSize: Qt.size(width * 2, height * 2)
  }
  MouseArea {
    anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton
    onEntered: icon.scene.showDetail(icon.description, icon)
    onExited: icon.scene.hideDetail()
  }
}
