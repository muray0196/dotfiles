pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: backdrop
  property int selection: 0
  property real phase: 0

  Image {
    anchors.fill: parent
    source: backdrop.selection === 1 ? "desert.png" : "flower.png"
    fillMode: Image.PreserveAspectCrop
    visible: backdrop.selection < 2
    scale: 1.12
    transform: Translate { x: 24 * Math.sin(backdrop.phase); y: 10 * Math.sin(backdrop.phase * 0.6) }
  }
  ShaderEffect {
    anchors.fill: parent
    visible: backdrop.selection >= 2 && backdrop.selection <= 5
    property vector2d sceneSize: Qt.vector2d(width, height)
    property real phase: backdrop.phase
    property real pattern: backdrop.selection - 2
    property real dark: 0
    fragmentShader: "backdrop.frag.qsb"
  }
  Column {
    x: 40 + 24 * Math.sin(backdrop.phase); y: 18
    spacing: 16
    visible: backdrop.selection === 4
    Repeater {
      model: 14
      Text {
        required property int index
        text: index % 2 ? "Typography / 0123456789 / Field notes / 09:41"
                       : "The landscape moves. The details stay in focus."
        color: "#25354b"
        font.family: "Adwaita Sans"
        font.pixelSize: index % 3 === 0 ? 28 : 18
      }
    }
  }
  Rectangle {
    anchors.fill: parent
    visible: backdrop.selection >= 6
    color: backdrop.selection === 6 ? "#ffffff" : "#10151d"
  }
}
