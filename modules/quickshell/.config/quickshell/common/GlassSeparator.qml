import QtQuick

Rectangle {
    id: separator

    required property QtObject palette
    property bool vertical: false
    color: palette.divider

    // The paired dark line keeps the separator visible over bright detail.
    // It occupies the existing spacing, leaving the layout's line size intact.
    Rectangle {
        x: separator.vertical ? 1 : 0
        y: separator.vertical ? 0 : 1
        width: parent.width
        height: parent.height
        visible: separator.palette.curvedGlass && separator.palette.legacyContent
        color: separator.palette.dividerShadow
    }
}
