import QtQuick

Item {
  id: study
  property real phase: 0
  property real presence: 1
  property bool bend: true
  property bool illuminate: true
  property bool dark: false
  property int diagnostic: 0
  readonly property real growth: 0.5 - 0.5 * Math.cos(phase * Math.PI / 3)

  Item {
    id: background
    anchors.fill: parent
    Image {
      anchors.fill: parent
      source: "flower.png"
      fillMode: Image.PreserveAspectCrop
      smooth: true
    }
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: study.dark ? 0.65 : 0
    }
  }
  BackdropSource {
    id: pool
    objectName: "sizeBackdrop"
    sourceItem: background
    blurRadius: 4 + 12 * glass.sizeResponse
  }
  Glass {
    id: glass
    objectName: "sizeGlass"
    width: 240 + 500 * study.growth
    height: 112 + 320 * study.growth
    x: (study.width - width) / 2 + 100 * Math.sin(study.phase * Math.PI / 3)
    y: (study.height - height) / 2
    backdrop: pool.sharp
    softenedBackdrop: pool.soft
    backdropSize: Qt.size(study.width, study.height)
    backdropPosition: Qt.point(x, y)
    refraction: study.bend ? 1 : 0
    lighting: study.illuminate ? 1 : 0
    presence: study.presence
    diagnostic: study.diagnostic

    AdaptiveInk {
      objectName: "sizeInk"
      anchors.centerIn: parent
      width: parent.width - 64
      height: 62 + 160 * study.growth
      backdrop: pool.soft
      sampleRegion: Qt.rect((glass.x + 32) / study.width,
                            (glass.y + glass.height / 2 - height / 2) / study.height,
                            width / study.width, height / study.height)
      visible: study.diagnostic === 0
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        text: "Liquid Glass"
        color: "white"
        font.pixelSize: 21
        font.weight: Font.Medium
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 58
        text: "09:41"
        color: "white"
        font.pixelSize: 36 + 36 * study.growth
        font.weight: Font.Light
        opacity: Math.max(0, Math.min(1, (study.growth - 0.1) / 0.5))
      }
    }
  }
}
