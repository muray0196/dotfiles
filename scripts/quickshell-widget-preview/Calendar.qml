pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F

Item {
  id: calendar
  required property var scene
  readonly property date date: scene.clockDate
  readonly property var cells: F.calendar(date, scene.readings.holidays)
  readonly property int calendarRows: Math.ceil(cells.length / 7)
  readonly property int calendarRowHeight: Math.floor(156 / calendarRows)
  readonly property bool darkInk: scene.darkText
  readonly property color sundayInk: darkInk ? "#a43c35" : "#ffaaa2"
  readonly property color saturdayInk: darkInk ? "#245f9e" : "#a9cdff"
  implicitHeight: 238
  Label { id: monthTitle; scene: calendar.scene; y: 0; text: Qt.formatDateTime(calendar.date, "MMMM"); size: 21; weight: Font.DemiBold }
  Label { scene: calendar.scene; anchors { left: monthTitle.right; leftMargin: 12; baseline: monthTitle.baseline } width: parent.width - x; align: Text.AlignRight; text: "W" + F.week(calendar.date) + " · Day " + F.dayOfYear(calendar.date) + "/" + F.dayOfYear(new Date(calendar.date.getFullYear(), 11, 31)); size: 12; muted: true }
  Row {
    y: 37; width: parent.width
    Repeater {
      model: ["S", "M", "T", "W", "T", "F", "S"]
      Label {
        required property string modelData
        required property int index
        scene: calendar.scene; width: calendar.width / 7; text: modelData; size: 12; align: Text.AlignHCenter
        ink: index === 0 ? calendar.sundayInk : index === 6 ? calendar.saturdayInk : calendar.darkInk ? "#455563" : "#e6ebf2"
      }
    }
  }
  Grid {
    id: calendarGrid
    y: 58; width: parent.width; columns: 7
    Repeater {
      model: calendar.cells
      Item {
        id: calendarCell
        required property var modelData
        width: calendar.width / 7; height: calendar.calendarRowHeight
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height / 2 + 7; width: 6; height: 6; radius: 3
          color: calendar.darkInk ? "#99ffffff" : "#990d1620"
          visible: calendarCell.modelData.today
          Accessible.ignored: true
          Rectangle {
            anchors.centerIn: parent; width: 4; height: 4; radius: 2
            color: calendar.darkInk ? "#172331" : "#fafbff"
          }
        }
        Label {
          scene: calendar.scene; anchors.fill: parent
          text: calendarCell.modelData.day; size: 15
          weight: calendarCell.modelData.today ? Font.DemiBold : Font.Medium
          align: Text.AlignHCenter; verticallyCentered: true
          ink: calendarCell.modelData.holiday || calendarCell.modelData.sunday ? calendar.sundayInk
            : calendarCell.modelData.saturday ? calendar.saturdayInk
            : calendar.darkInk ? "#172331" : "#fafbff"
          accessibleText: calendarCell.modelData.day + (calendarCell.modelData.today ? " · Today" : "")
            + (calendarCell.modelData.holiday ? " · " + calendarCell.modelData.holiday : "")
        }
        MouseArea {
          anchors.fill: parent; hoverEnabled: true
          onEntered: if (calendarCell.modelData.day && calendarCell.modelData.holiday) calendar.scene.showDetail(calendarCell.modelData.holiday, calendarCell)
          onExited: calendar.scene.hideDetail()
        }
      }
    }
  }
  Label { scene: calendar.scene; y: calendarGrid.y + calendarGrid.implicitHeight + 6; width: parent.width; size: 12; text: (calendar.scene.readings.holiday_status === "Cached" ? "Cached · " : "") + F.nextHoliday(calendar.date, calendar.scene.readings.holidays); muted: true }
}
