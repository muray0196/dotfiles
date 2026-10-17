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
        radius: height / 2
        color: sectionHeader.healthTone
    }

    GlassText {
        palette: sectionHeader.palette
        anchors {
            left: parent.left
            leftMargin: sectionHeader.healthMarkerVisible ? 9 : 0
            verticalCenter: parent.verticalCenter
        }
        text: sectionHeader.label
        color: sectionHeader.palette.textPrimary
        font.family: sectionHeader.palette.labelFont
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }

    GlassText {
        palette: sectionHeader.palette
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        visible: sectionHeader.metadataVisible
            && !sectionHeader.statusActive
        text: sectionHeader.metadata
        color: sectionHeader.metadataTone
        font.family: sectionHeader.palette.labelFont
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
                radius: height / 2
                color: sectionHeader.statusTone
            }

            GlassText {
                palette: sectionHeader.palette
                text: sectionHeader.statusLabel
                color: sectionHeader.statusTone
                font.family: sectionHeader.palette.labelFont
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
    }
}
