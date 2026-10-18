import QtQuick

Item {
  id: fixture
  width: 640; height: 420
  property real glassX: 132
  property real glassY: 70
  property real glassWidth: 300
  property real glassHeight: 250
  property real glassRadius: 40
  property real bevel: 24
  property real surfaceHeight: 24
  property real crownHeight: 0
  property real backingDistance: 36
  property real optics: 0
  property real transmissionRoughness: 0
  property bool filterInterior: true
  property real softness: 0
  property real edgeSoftness: 0
  property real lighting: 0
  property real ambientReflection: 0
  property real lightAngle: -2.2
  property real adaptation: 0
  property real presence: 1
  property real phase: 0
  property real pattern: 0
  property bool showGlass: true
  property bool foreground: false
  property bool inkProbe: false

  ShaderEffect {
    id: background
    anchors.fill: parent
    property vector2d sceneSize: Qt.vector2d(width, height)
    property real phase: fixture.phase
    property real pattern: fixture.pattern
    fragmentShader: "fixture.frag.qsb"
  }
  BackdropSource { id: pool; sourceItem: background }
  Glass {
    x: fixture.glassX; y: fixture.glassY
    width: fixture.glassWidth; height: fixture.glassHeight
    visible: fixture.showGlass
    backdrop: pool.sharp
    softenedBackdrop: pool.soft
    backdropSize: Qt.size(fixture.width, fixture.height)
    backdropPosition: Qt.point(x, y)
    radius: fixture.glassRadius
    edgeWidth: fixture.bevel
    surfaceHeight: fixture.surfaceHeight
    crownHeight: fixture.crownHeight
    thickness: fixture.backingDistance
    refraction: fixture.optics
    transmissionRoughness: fixture.transmissionRoughness
    filterInterior: fixture.filterInterior
    softness: fixture.softness
    edgeSoftness: fixture.edgeSoftness
    lighting: fixture.lighting
    ambientReflection: fixture.ambientReflection
    lightDirection: Qt.vector2d(Math.cos(fixture.lightAngle), Math.sin(fixture.lightAngle))
    adaptation: fixture.adaptation
    presence: fixture.presence
    shadowStrength: 0
  }
  Text {
    x: 118; y: 166
    text: "Foreground 0123"
    font.pixelSize: 24
    font.weight: Font.Bold
    color: "#ffffff"
    visible: fixture.foreground
  }
  AdaptiveInk {
    x: 450; y: 330; width: 20; height: 20
    backdrop: pool.soft
    sampleRegion: Qt.rect(0, 0, 1, 1)
    visible: fixture.inkProbe
    Rectangle { anchors.fill: parent; color: "white" }
  }
}
