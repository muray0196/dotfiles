import QtQuick

Text {
    required property QtObject palette

    // The compositor supplies soft local backing. Flat glyphs keep the content
    // visually distinct from the reflective glass; Radar retains its old style.
    style: palette.curvedGlass && palette.legacyContent ? Text.Raised : Text.Normal
    styleColor: palette.textShadow
    font.features: palette.legacyContent ? ({}) : ({ "tnum": 1 })
}
