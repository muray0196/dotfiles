import QtQuick

Item {
  id: glass
  required property Item backdrop
  required property Item softenedBackdrop
  required property size backdropSize
  // Position is in the backdrop's logical coordinate system. This prototype
  // deliberately has no rotated/scaled ancestors or cross-window sampling.
  required property point backdropPosition
  readonly property real normalizedSize: Math.max(0, Math.min(1, (Math.min(width, height) - 96) / 324))
  readonly property real sizeResponse: normalizedSize * normalizedSize * (3 - 2 * normalizedSize)
  // Independent starting profile for controls that grow into larger surfaces.
  // Reference studies can still supply their measured/selected optical lengths.
  property real radius: Math.min(56, Math.min(width, height) / 2)
  property real edgeWidth: radius * (0.38 + 0.44 * sizeResponse)
  property real thickness: radius * (0.6 + 1.4 * sizeResponse)
  property real surfaceHeight: radius * (0.5 + 0.18 * sizeResponse)
  // A shallow whole-body lens, continuous with the rounded perimeter.
  property real crownHeight: Math.min(width, height) * 0.055 * sizeResponse
  property real magnification: 0
  // Soft uses restrained local smoothing; Clear explicitly sets this to zero.
  property real transmissionRoughness: 0.008
  // Interior-only perceptual filtering; false retains the checkpoint's kernel.
  property bool filterInterior: true
  // Reference studies may explicitly opt into broader diffusion.
  property real softness: 0
  property real edgeSoftness: 0
  property real lighting: 1
  property real ambientReflection: 0
  property real adaptation: 0
  property real diffusion: 0
  property color tintColor: "transparent"
  property real refraction: 1
  property real shadowStrength: 0.08 + 0.1 * sizeResponse
  // Optical strength, never item opacity: zero must reproduce the backdrop.
  property real presence: 1
  property real diagnostic: 0
  property vector2d lightDirection: Qt.vector2d(-0.6, -0.8)
  readonly property int padding: 28

  ShaderEffect {
    objectName: "glassShader"
    x: -glass.padding
    y: -glass.padding
    width: glass.width + 2 * glass.padding
    height: glass.height + 2 * glass.padding
    property Item backdrop: glass.backdrop
    property Item softenedBackdrop: glass.softenedBackdrop
    property vector2d bodySize: Qt.vector2d(glass.width, glass.height)
    property vector2d backdropSize: Qt.vector2d(glass.backdropSize.width, glass.backdropSize.height)
    property rect sampleRect: Qt.rect(glass.backdropPosition.x - glass.padding,
                                     glass.backdropPosition.y - glass.padding, width, height)
    property real padding: glass.padding
    property real cornerRadius: glass.radius
    property real edgeWidth: glass.edgeWidth
    property real thickness: glass.thickness
    property real surfaceHeight: glass.surfaceHeight
    property real crownHeight: glass.crownHeight
    property real magnification: glass.magnification
    property real transmissionRoughness: glass.transmissionRoughness * glass.presence
    property real interiorFiltering: glass.filterInterior ? 1 : 0
    property real softness: glass.softness * glass.presence
    property real edgeSoftness: glass.edgeSoftness * glass.presence
    property real lighting: glass.lighting * glass.presence
    property real ambientReflection: glass.ambientReflection * glass.presence
    property real adaptation: glass.adaptation * glass.presence
    property real diffusion: glass.diffusion * glass.presence
    property vector4d tint: Qt.vector4d(glass.tintColor.r, glass.tintColor.g,
                                      glass.tintColor.b, glass.tintColor.a * glass.presence)
    property real refraction: glass.refraction * glass.presence
    property real shadowStrength: glass.shadowStrength * glass.presence
    property vector2d lightDirection: glass.lightDirection
    property vector2d lightPosition: {
      const length = Math.max(0.0001, Math.hypot(glass.lightDirection.x, glass.lightDirection.y));
      const reach = Math.hypot(glass.backdropSize.width, glass.backdropSize.height) / 2;
      return Qt.vector2d(glass.backdropSize.width / 2 + glass.lightDirection.x / length * reach,
                        glass.backdropSize.height / 2 + glass.lightDirection.y / length * reach);
    }
    property real diagnostic: glass.diagnostic
    fragmentShader: "glass.frag.qsb"
  }
}
