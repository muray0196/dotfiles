import QtQuick

Rectangle {
    required property color tone
    property bool compact: false

    width: compact ? 5 : 3
    height: compact ? 5 : 18
    radius: compact ? height / 2 : 0
    color: tone
}
