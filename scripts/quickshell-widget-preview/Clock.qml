pragma ComponentBehavior: Bound
import QtQuick

Item {
  id: clock
  required property var scene
  readonly property date date: scene.clockDate
  implicitHeight: 118
  Label { id: dateLabel; scene: clock.scene; text: Qt.formatDateTime(clock.date, "yyyy/MM/dd (ddd)"); accessibleText: Qt.formatDateTime(clock.date, "yyyy/MM/dd (dddd)"); size: 19; weight: Font.Medium; width: Math.min(implicitWidth, parent.width - 64) }
  Label {
    scene: clock.scene; x: dateLabel.width + 12; width: parent.width - x
    anchors.baseline: dateLabel.baseline
    text: clock.scene.readings.zone || "Local time"; size: 12; muted: true; align: Text.AlignRight
  }
  Label { id: time; scene: clock.scene; y: 110 - baselineOffset; text: Qt.formatDateTime(clock.date, "HH:mm"); size: 94; tracking: -2; weight: Font.Normal }
  Label { scene: clock.scene; anchors { left: time.right; leftMargin: 6; baseline: time.baseline } text: Qt.formatDateTime(clock.date, "ss"); size: 28; weight: Font.Medium; muted: true }
}
