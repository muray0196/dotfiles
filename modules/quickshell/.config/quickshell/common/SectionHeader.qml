import QtQuick

Item {
    id: sectionHeader

    required property QtObject palette
    required property string label
    property string metadata: ""
    property bool metadataVisible: metadata !== ""
    property color metadataTone: palette.textMuted
    property bool healthMarkerVisible: false
    property color healthTone: palette.statusUnknown
    property bool statusActive: false
    property string statusLabel: ""
    property color statusTone: palette.statusUnknown

    implicitHeight: 19

    Rectangle {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        visible: sectionHeader.healthMarkerVisible
        width: 5
        height: 5
        radius: 0
        color: sectionHeader.healthTone
    }

    Text {
        anchors {
            left: parent.left
            leftMargin: sectionHeader.healthMarkerVisible ? 9 : 0
            verticalCenter: parent.verticalCenter
        }
        text: sectionHeader.label
        color: sectionHeader.palette.textPrimary
        font.family: "Adwaita Mono"
        font.pixelSize: 14
        font.weight: Font.Medium
    }

    Text {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        visible: sectionHeader.metadataVisible
            && !sectionHeader.statusActive
        text: sectionHeader.metadata
        color: sectionHeader.metadataTone
        font.family: "Adwaita Mono"
        font.pixelSize: sectionHeader.palette.observationMetadataSize
        font.weight: Font.Medium
    }

    Loader {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        active: sectionHeader.statusActive

        sourceComponent: Row {
            spacing: 5

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 0
                color: sectionHeader.statusTone
            }

            Text {
                text: sectionHeader.statusLabel
                color: sectionHeader.statusTone
                font.family: "Adwaita Mono"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    }
}
