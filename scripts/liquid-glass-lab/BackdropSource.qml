import QtQuick

Item {
  id: pool
  required property Item sourceItem
  property real blurRadius: 14
  readonly property alias sharp: sharpTexture
  readonly property alias soft: verticalTexture

  ShaderEffectSource {
    id: sharpTexture
    sourceItem: pool.sourceItem
    live: true
    visible: false
    smooth: true
    // Refracted coordinates can compress many source pixels into one output
    // pixel. Filter that footprint instead of aliasing it into a hard ring.
    mipmap: true
  }

  ShaderEffect {
    id: horizontal
    width: Math.ceil(pool.sourceItem.width / 2)
    height: Math.ceil(pool.sourceItem.height / 2)
    visible: false
    property Item source: sharpTexture
    property vector2d stepUV: Qt.vector2d(1 / width, 0)
    property real sigma: Math.max(0.5, Math.min(pool.blurRadius / 6, 3.3))
    fragmentShader: "blur.frag.qsb"
  }

  ShaderEffectSource {
    id: horizontalTexture
    sourceItem: horizontal
    live: true
    visible: false
    smooth: true
  }

  ShaderEffect {
    id: vertical
    width: horizontal.width
    height: horizontal.height
    visible: false
    property Item source: horizontalTexture
    property vector2d stepUV: Qt.vector2d(0, 1 / height)
    property real sigma: horizontal.sigma
    fragmentShader: "blur.frag.qsb"
  }

  ShaderEffectSource {
    id: verticalTexture
    sourceItem: vertical
    live: true
    visible: false
    smooth: true
    // The softened source is also minified by strong lensing; blur alone is
    // not an antialiasing filter for an arbitrarily compressed footprint.
    mipmap: true
  }
}
