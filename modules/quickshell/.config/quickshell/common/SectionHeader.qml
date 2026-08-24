import QtQuick

Item {
    id: sectionHeader

    required property string label
    property string metadata: ""
    property bool metadataVisible: metadata !== ""
    property color labelTone: sharedTheme.textPrimary
    property color metadataTone: sharedTheme.textMuted
    property int metadataSize: sharedTheme.observationMetadataSize
    property bool statusActive: false
    property string statusLabel: ""
    property color statusTone: sharedTheme.statusUnknown

    implicitHeight: 19

    Theme {
        id: sharedTheme
    }

    Text {
        id: sectionLabel

        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        text: sectionHeader.label
        color: sectionHeader.labelTone
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
        font.pixelSize: sectionHeader.metadataSize
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
