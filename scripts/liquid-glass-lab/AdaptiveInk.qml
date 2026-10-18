import QtQuick

Item {
  id: ink
  required property Item backdrop
  // Normalized background region used for one shared contrast decision.
  required property rect sampleRegion
  default property alias content: textContent.data

  Item { id: textContent; anchors.fill: parent }
  ShaderEffectSource {
    id: mask
    sourceItem: textContent
    hideSource: true
    live: true
    visible: false
  }
  ShaderEffect {
    anchors.fill: parent
    property Item glyphs: mask
    property Item backdrop: ink.backdrop
    property rect sampleRegion: ink.sampleRegion
    fragmentShader: "ink.frag.qsb"
  }
}
