import QtQuick

Item {
  id: study
  // 0: moving capsule / fixed boundary; 1: fixed capsule / moving light;
  // 2: moving large panel / fixed monochrome dunes.
  property int mode: 0
  property real phase: 0
  property real presence: 1
  property bool bend: true
  property bool scatter: true
  property bool illuminate: true
  property bool dark: false
  property int diagnostic: 0
  readonly property real unit: width / 1920
  readonly property real angle: -2.4 + phase * Math.PI / 3
  readonly property vector2d light: mode === 1 ? Qt.vector2d(Math.cos(angle), Math.sin(angle))
                                                           : Qt.vector2d(-0.2, 1)
  readonly property string motionDescription: [
    "vertical capsule translation over a fixed horizontal boundary",
    "rotating light field around a stationary capsule",
    "vertical rounded-panel translation over a fixed monochrome desert image"
  ][mode]

  Item {
    id: background
    anchors.fill: parent
    Image {
      id: dunes
      source: "desert.png"
      visible: false
      smooth: true
    }
    ShaderEffect {
      anchors.fill: parent
      property Item source: dunes
      property vector2d viewSize: Qt.vector2d(width, height)
      property real mode: study.mode
      property vector2d lightDirection: study.light
      property real dark: study.dark ? 1 : 0
      fragmentShader: "study.frag.qsb"
    }
  }
  BackdropSource {
    id: pool
    sourceItem: background
    blurRadius: study.mode === 2 ? 8 : 3
  }
  Glass {
    id: glass
    objectName: "referenceGlass"
    width: (study.mode === 2 ? 1550 : 760) * study.unit
    height: (study.mode === 2 ? 1200 : 430) * study.unit
    x: (study.width - width) / 2
    y: study.mode === 0 ? (study.height - height) / 2 + (-60 + 160 * Math.sin(study.phase * Math.PI / 3)) * study.unit
       : study.mode === 1 ? (study.height - height) / 2
       : study.height * 0.83 - height + 80 * study.unit * Math.sin(study.phase * Math.PI / 3)
    radius: (study.mode === 2 ? 220 : 215) * study.unit
    backdrop: pool.sharp
    softenedBackdrop: pool.soft
    backdropSize: Qt.size(study.width, study.height)
    backdropPosition: Qt.point(x, y)
    // Native-reference lengths, scaled into the preview. Boundary parameters
    // constrain the observed dark-pocket contour; Panel remains qualitative
    // because its unobstructed reference background is unavailable.
    edgeWidth: [120, 35, 180][study.mode] * study.unit
    surfaceHeight: [150, 30, 150][study.mode] * study.unit
    thickness: [180, 75, 440][study.mode] * study.unit
    crownHeight: 0
    transmissionRoughness: 0
    refraction: study.bend ? 1 : 0
    softness: study.scatter ? [0.15, 0, 0.75][study.mode] : 0
    edgeSoftness: study.scatter && study.mode === 2 ? 0.75 : 0
    lighting: study.illuminate ? 1 : 0
    ambientReflection: 0
    adaptation: 0
    shadowStrength: study.mode === 1 ? 0 : 0.08
    lightDirection: study.light
    presence: study.presence
    diagnostic: study.diagnostic
    Rectangle {
      objectName: "foregroundBar"
      visible: study.mode === 2 && study.diagnostic === 0
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - 52 * study.unit
      width: 550 * study.unit
      height: 18 * study.unit
      radius: height / 2
      color: "white"
    }
  }
}
