import QtQuick
import QtQuick.Effects

// Foreground only. The accepted optical components remain unchanged.
Item {
  id: label
  required property var scene
  property string text: ""
  property int size: 14
  property int weight: size <= 13 ? Font.Medium : Font.Normal
  property string family: "Adwaita Sans"
  property real tracking: 0
  property bool muted: false
  property bool wrap: false
  property int align: Text.AlignLeft
  property bool verticallyCentered: false
  property bool shadowed: true
  property color ink: scene.darkText ? (muted ? "#455563" : "#172331")
                                                   : (muted ? "#e6ebf2" : "#fafbff")
  implicitWidth: glyph.implicitWidth
  implicitHeight: wrap ? glyph.implicitHeight : Math.ceil(size * 1.4)
  height: implicitHeight
  baselineOffset: glyph.y + glyph.baselineOffset
  // Symbols use their drawn bounds; adjacent text uses a stable capital center.
  // Digit changes must not make an icon move vertically.
  readonly property real capCenterY: baselineOffset - metrics.capitalHeight / 2
  readonly property real inkCenterY: {
    const bounds = metrics.tightBoundingRect(text);
    return baselineOffset + bounds.y + bounds.height / 2;
  }
  FontMetrics { id: metrics; font: glyph.font }
  property alias truncated: glyph.truncated
  property string accessibleText: text
  Accessible.role: Accessible.StaticText
  Accessible.name: accessibleText

  // Blur only a fixed-color copy beneath the directly rendered glyphs.
  MultiEffect {
    x: glyph.x; y: glyph.y + 1; z: -1
    width: glyph.width; height: glyph.height
    source: glyph
    visible: label.shadowed && label.text !== ""
    colorization: 1
    colorizationColor: label.scene.darkText ? "#ffffff" : "#0d1620"
    opacity: label.scene.darkText ? 0.6 : 0.85
    blurEnabled: true
    blur: 1
    blurMax: 4
  }
  Text {
    id: glyph
    y: label.verticallyCentered ? (label.height - height) / 2 : 0
    width: label.width
    text: label.text
    textFormat: Text.PlainText
    // Opaque ink keeps the hierarchy stable over moving imagery. Only an
    // explicit appearance change selects a different foreground palette.
    color: label.ink
    // Styled text avoids LCD subpixel fringes on transparent foregrounds.
    // Symbols keep their drawn stroke weight; the soft shadow still separates
    // them from the wallpaper without a second, raised outline.
    style: label.shadowed && label.family !== "Material Symbols Rounded" ? Text.Raised : Text.Normal
    styleColor: label.scene.darkText ? "#33ffffff" : "#660d1620"
    font.family: label.family
    font.pixelSize: label.size
    font.weight: label.weight
    font.letterSpacing: label.tracking
    font.features: { "tnum": 1 }
    horizontalAlignment: label.align
    wrapMode: label.wrap ? Text.WordWrap : Text.NoWrap
    elide: label.wrap ? Text.ElideNone : Text.ElideRight
  }
  MouseArea {
    anchors.fill: parent
    enabled: glyph.truncated || label.accessibleText !== label.text
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: label.scene.showDetail(label.accessibleText, label)
    onExited: label.scene.hideDetail()
  }
}
