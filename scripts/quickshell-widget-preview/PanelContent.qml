pragma ComponentBehavior: Bound
import QtQuick
import "Layout.js" as Layout

Item {
  id: panel
  required property var state
  property bool leftSide: false
  width: Layout.panelWidth; height: Layout.panelHeight
  readonly property bool darkText: state.darkText
  readonly property var readings: state.readings
  readonly property date clockDate: state.clockDate
  readonly property real contentWidth: width - 2 * Layout.contentInset
  property string detail: ""
  property real detailY: 0
  function showDetail(text, item) {
    detail = text;
    const point = item.mapToItem(panel, 0, item.height);
    detailY = point.y + 6;
    if (detailY + detailBox.height > panel.height - 8)
      detailY = Math.max(8, point.y - item.height - detailBox.height - 6);
  }
  function hideDetail() { detail = ""; }
  Machine { id: local; scene: panel; x: Layout.contentInset; y: Layout.contentInset; width: panel.contentWidth; visible: panel.leftSide; reading: panel.readings.local || {} }
  Machine { id: main; scene: panel; x: Layout.contentInset; y: local.y + local.implicitHeight + 24; width: panel.contentWidth; visible: panel.leftSide; remote: true; reading: panel.readings.main || {} }
  History { id: history; scene: panel; x: Layout.contentInset; y: main.y + main.implicitHeight + 24; width: panel.contentWidth; visible: panel.leftSide }
  Today { id: today; scene: panel; x: Layout.contentInset; y: Layout.contentInset; width: panel.contentWidth; visible: !panel.leftSide }
  Weather { id: weather; scene: panel; x: Layout.contentInset; y: today.y + today.implicitHeight + 24; width: panel.contentWidth; visible: !panel.leftSide }
  Radar {
    id: radar
    scene: panel; x: Layout.contentInset; y: weather.y + weather.implicitHeight + 24
    width: panel.contentWidth; visible: !panel.leftSide
    viewportHeight: Math.max(0, panel.height - Layout.contentInset - y - headerHeight)
  }
  Repeater {
    model: panel.leftSide ? [main.y - 12, history.y - 12] : [weather.y - 12, radar.y - 12]
    Rectangle { required property real modelData; x: Layout.contentInset; y: modelData; width: panel.contentWidth; height: 1; color: panel.darkText ? "#21344857" : "#44d2e0e8" }
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
    return panel.leftSide ? {localBottom: y + local.y + local.implicitHeight, mainBottom: y + main.y + main.implicitHeight, historyBottom: y + history.y + history.implicitHeight}
      : {todayBottom: y + today.y + today.implicitHeight, weatherBottom: y + weather.y + weather.implicitHeight, radarBottom: y + radar.y + radar.implicitHeight};
  }
}
