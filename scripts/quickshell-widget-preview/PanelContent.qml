pragma ComponentBehavior: Bound
import QtQuick
import "Layout.js" as Layout

Item {
  id: panel
  required property var state
  required property string kind
  objectName: "panel-" + kind
  readonly property var geometry: Layout.panel(kind, state.readings)
  width: Layout.panelWidth; height: geometry.height
  readonly property bool darkText: state.darkText
  readonly property var readings: state.readings
  readonly property date clockDate: state.clockDate
  readonly property real contentWidth: width - 2 * Layout.contentInset
  property string detail: ""
  property real detailY: 0
  property var frozenRadar: null
  function radarState() {
    return kind === "radar" && content.item ? content.item.snapshot() : null;
  }
  function showDetail(text, item) {
    detail = text;
    const point = item.mapToItem(panel, 0, item.height);
    detailY = point.y + 6;
    if (detailY + detailBox.height > panel.height - 8)
      detailY = Math.max(8, point.y - item.height - detailBox.height - 6);
  }
  function hideDetail() { detail = ""; }
  Loader {
    id: content
    x: Layout.contentInset; y: panel.geometry.inset
    width: panel.contentWidth; height: panel.height - 2 * y
    sourceComponent: panel.geometry.left ? machineContent
      : panel.kind === "clock" ? clockContent : panel.kind === "day" ? dayContent : radarContent
  }
  Component {
    id: machineContent
    Item {
      Machine {
        id: machine
        scene: panel; width: parent.width
        remote: panel.kind === "main"
        reading: panel.readings[panel.kind] || {}
      }
      History {
        id: history
        scene: panel; width: parent.width; y: parent.height - implicitHeight
        machineFilter: panel.kind
      }
      Rectangle { y: history.y - 6; width: parent.width; height: 1; color: panel.darkText ? "#21344857" : "#44d2e0e8" }
      function audit() {
        const result = {};
        result[panel.kind + "Bottom"] = machine.y + machine.implicitHeight;
        result[panel.kind + "HistoryBottom"] = history.y + history.implicitHeight;
        return result;
      }
    }
  }
  Component {
    id: clockContent
    Clock {
      scene: panel
      function audit() { return {clockBottom: implicitHeight}; }
    }
  }
  Component {
    id: dayContent
    Item {
      Calendar { id: calendar; scene: panel; width: parent.width }
      Weather { id: weather; scene: panel; width: parent.width; y: calendar.implicitHeight + Layout.daySectionGap }
      Rectangle { y: weather.y - Layout.daySectionGap / 2; width: parent.width; height: 1; color: panel.darkText ? "#21344857" : "#44d2e0e8" }
      function audit() { return {calendarBottom: calendar.implicitHeight, weatherBottom: weather.y + weather.implicitHeight}; }
    }
  }
  Component {
    id: radarContent
    Radar {
      scene: panel
      frozenState: panel.frozenRadar
      viewportHeight: height - headerHeight
      function audit() { return {radarBottom: implicitHeight}; }
    }
  }
  Rectangle {
    id: detailBox
    x: 20; y: panel.detailY; z: 10
    width: panel.width - 40; height: detailText.implicitHeight + 24; radius: 12
    visible: panel.detail !== ""
    color: panel.darkText ? "#f2eef1f4" : "#ed172331"
    Text { id: detailText; x: 12; y: 12; width: parent.width - 24; text: panel.detail; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: panel.darkText ? "#172331" : "#fafbff"; font { family: "Adwaita Sans"; pixelSize: 13 } }
  }
  function audit() {
    const result = content.item ? content.item.audit() : {};
    for (const key of Object.keys(result)) result[key] += y + content.y;
    return result;
  }
}
