pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F

Item {
  id: today
  required property var scene
  readonly property date date: scene.clockDate
  readonly property var cells: F.calendar(date, scene.readings.holidays)
  readonly property int calendarRows: Math.ceil(cells.length / 7)
  readonly property int calendarRowHeight: Math.floor(156 / calendarRows)
  readonly property bool darkInk: scene.darkText
  readonly property color sundayInk: darkInk ? "#a43c35" : "#ffaaa2"
  readonly property color saturdayInk: darkInk ? "#245f9e" : "#a9cdff"
  implicitHeight: 388
  Label { id: dateLabel; scene: today.scene; text: Qt.formatDateTime(today.date, "yyyy/MM/dd (dddd)"); size: 15; weight: Font.Medium; width: Math.min(implicitWidth, parent.width - 64) }
  Label {
    scene: today.scene; x: dateLabel.width + 12; width: parent.width - x
    anchors.baseline: dateLabel.baseline
    text: today.scene.readings.zone || "Local time"; size: 12; muted: true; align: Text.AlignRight
  }
  Label { id: time; scene: today.scene; y: 110 - baselineOffset; text: Qt.formatDateTime(today.date, "HH:mm"); size: 94; tracking: -2; weight: Font.Normal }
  Label { scene: today.scene; anchors { left: time.right; leftMargin: 6; baseline: time.baseline } text: Qt.formatDateTime(today.date, "ss"); size: 28; weight: Font.Medium; muted: true }
  Label { id: monthTitle; scene: today.scene; y: 146; text: Qt.formatDateTime(today.date, "MMMM"); size: 21; weight: Font.DemiBold }
  Label { scene: today.scene; anchors { left: monthTitle.right; leftMargin: 12; baseline: monthTitle.baseline } width: parent.width - x; align: Text.AlignRight; text: "W" + F.week(today.date) + " · Day " + F.dayOfYear(today.date) + "/" + F.dayOfYear(new Date(today.date.getFullYear(), 11, 31)); size: 12; muted: true }
  Row {
    y: 183; width: parent.width
    Repeater {
      model: ["S", "M", "T", "W", "T", "F", "S"]
      Label {
        required property string modelData
        required property int index
        scene: today.scene; width: today.width / 7; text: modelData; size: 12; align: Text.AlignHCenter
        ink: index === 0 ? today.sundayInk : index === 6 ? today.saturdayInk : today.darkInk ? "#455563" : "#e6ebf2"
      }
    }
  }
  Grid {
    id: calendarGrid
    y: 204; width: parent.width; columns: 7
    Repeater {
      model: today.cells
      Item {
        id: calendarCell
        required property var modelData
        width: today.width / 7; height: today.calendarRowHeight
        Rectangle {
          anchors.centerIn: parent; width: 26; height: 26; radius: 13
          color: today.darkInk ? "#d7dce1" : "#424a54"
          opacity: 0.6
          visible: calendarCell.modelData.today
        }
        Label {
          scene: today.scene; anchors.fill: parent
          text: calendarCell.modelData.day; size: 15; weight: Font.Medium
          align: Text.AlignHCenter; verticallyCentered: true
          ink: calendarCell.modelData.holiday || calendarCell.modelData.sunday ? today.sundayInk
            : calendarCell.modelData.saturday ? today.saturdayInk
            : today.darkInk ? "#172331" : "#fafbff"
          accessibleText: calendarCell.modelData.day + (calendarCell.modelData.holiday ? " · " + calendarCell.modelData.holiday : "")
        }
        MouseArea {
          anchors.fill: parent; hoverEnabled: true
          onEntered: if (calendarCell.modelData.day && calendarCell.modelData.holiday) today.scene.showDetail(calendarCell.modelData.holiday, calendarCell)
          onExited: today.scene.hideDetail()
        }
      }
    }
  }
  Label { scene: today.scene; y: calendarGrid.y + calendarGrid.implicitHeight + 6; width: parent.width; size: 12; text: (today.scene.readings.holiday_status === "Cached" ? "Cached · " : "") + F.nextHoliday(today.date, today.scene.readings.holidays); muted: true }
}
