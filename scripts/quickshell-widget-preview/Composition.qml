pragma ComponentBehavior: Bound
import QtQuick
import "material" as Material
import "Fixture.js" as Fixture
import "Layout.js" as Layout

Item {
  id: composition
  width: 1920; height: 1080
  focus: true
  property bool darkText: false
  property int direction: 0
  property int background: 0
  property int scenario: 0
  property bool animated: false
  property real phase: 0
  property bool showTools: true
  property bool showForeground: true
  property string detail: ""
  function showDetail(text, item) { detail = text; }
  function hideDetail() { detail = ""; }
  property var readings: Fixture.normal()
  readonly property string dataProvenance: readings.demo ? "DEMONSTRATION DATA" : readings.frozen ? "COLLECTOR SNAPSHOT" : "LIVE MACHINES · ENVIRONMENT SNAPSHOT"
  property date clockDate: new Date(readings.clock || "2026-10-18T09:41:32")
  property alias pool: pool
  readonly property real leftX: direction === 0 ? Layout.sideInset : 36
  readonly property real rightX: width - (direction === 0 ? Layout.sideInset + Layout.panelWidth : 436)
  readonly property int inset: 28
  readonly property real contentWidth: 344
  onScenarioChanged: readings = Fixture.scenario(scenario)
  FrameAnimation { running: composition.animated; onTriggered: { composition.phase += frameTime; if (composition.readings.demo) composition.readings = Fixture.changing(composition.phase, composition.scenario); } }
  Keys.onPressed: event => {
    if (event.key === Qt.Key_F) composition.darkText = !composition.darkText;
    else if (event.key === Qt.Key_B) composition.background = (composition.background + 1) % 5;
    else if (event.key === Qt.Key_D) composition.direction = (composition.direction + 1) % 3;
    else if (event.key === Qt.Key_E) composition.scenario = (composition.scenario + 1) % 3;
    else if (event.key === Qt.Key_Space) composition.animated = !composition.animated;
    else if (event.key === Qt.Key_H) composition.showTools = !composition.showTools;
    else return;
    event.accepted = true;
  }
  Item {
    id: backdrop
    anchors.fill: parent
    clip: true
    Rectangle { anchors.fill: parent; color: composition.background === 3 ? "#121821" : "#eff1f3" }
    Image {
      x: -48 + 44 * Math.sin(composition.phase * Math.PI / 3)
      y: -12 + 8 * Math.sin(composition.phase * Math.PI / 3)
      width: parent.width + 96; height: parent.height + 24
      source: "material/flower.png"; fillMode: Image.PreserveAspectCrop
      visible: composition.background === 0
    }
    Image { id: desert; source: "material/desert.png"; visible: false }
    ShaderEffect {
      anchors.fill: parent; visible: composition.background === 1
      property Item source: desert
      property vector2d viewSize: Qt.vector2d(width, height)
      property real sourceScale: 1.01 / (1 + 0.02 * (1 - Math.cos(composition.phase * Math.PI / 3)))
      fragmentShader: "material/desert.frag.qsb"
    }
    Grid {
      visible: composition.background === 4
      x: -40 + 30 * Math.sin(composition.phase); y: -40
      columns: 60
      Repeater {
        model: 60 * 36
        Rectangle { required property int index; width: 34; height: 34; color: (index + Math.floor(index / 60)) % 2 ? "#ced3d0" : "#27364a" }
      }
    }
  }
  Material.BackdropSource { id: pool; sourceItem: backdrop; blurRadius: 20 }
  // 0: two rails. 1: independent modules. 2: two staggered upper/lower pairs.
  Repeater {
    model: composition.direction === 0 ? [
      {x: composition.leftX, y: Layout.topInset, w: Layout.panelWidth, h: Layout.panelHeight}, {x: composition.rightX, y: Layout.topInset, w: Layout.panelWidth, h: Layout.panelHeight}
    ] : composition.direction === 1 ? [
      {x: composition.leftX, y: 36, w: 400, h: 553}, {x: composition.leftX, y: 605, w: 400, h: 270},
      {x: composition.leftX + 426, y: 753, w: 400, h: 291},
      {x: composition.rightX, y: 36, w: 400, h: 418}, {x: composition.rightX, y: 470, w: 400, h: 390},
      {x: composition.rightX - 426, y: 807, w: 400, h: 237}
    ] : [
      {x: composition.leftX, y: 36, w: 400, h: 553}, {x: composition.leftX, y: 607, w: 800, h: 287},
      {x: composition.rightX, y: 36, w: 400, h: 418}, {x: composition.rightX, y: 472, w: 400, h: 572}
    ]
    Surface { required property var modelData; scene: composition; x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h }
  }
  Item {
    objectName: "widgetForeground"
    anchors.fill: parent
    visible: composition.showForeground
    PanelContent { id: leftPanel; state: composition; leftSide: true; x: composition.leftX; y: Layout.topInset; visible: composition.direction === 0 }
    PanelContent { id: rightPanel; state: composition; x: composition.rightX; y: Layout.topInset; visible: composition.direction === 0 }
    Machine { id: local; visible: composition.direction !== 0; objectName: "localMachine"; scene: composition; x: composition.leftX + 28; y: 64; width: composition.contentWidth; reading: composition.readings.local || {} }
    Machine { id: main; visible: composition.direction !== 0; objectName: "mainMachine"; scene: composition; x: composition.leftX + 28; y: composition.direction === 0 ? 585 : 630; width: composition.contentWidth; reading: composition.readings.main || {}; remote: true }
    History { id: history; visible: composition.direction !== 0; scene: composition; x: composition.leftX + 28 + (composition.direction === 1 ? 426 : composition.direction === 2 ? 400 : 0); y: composition.direction === 2 ? 630 : 781; width: composition.contentWidth }
    Today { id: today; visible: composition.direction !== 0; scene: composition; x: composition.rightX + 28; y: 64; width: composition.contentWidth }
    Weather { id: weather; visible: composition.direction !== 0; scene: composition; x: composition.rightX + 28; y: composition.direction === 0 ? 446 : 490; width: composition.contentWidth }
    Radar { id: radar; visible: composition.direction !== 0; scene: composition; x: composition.rightX + 28 - (composition.direction === 1 ? 426 : 0); y: composition.direction === 0 ? 823 : 835; width: composition.contentWidth }

  }
  Rectangle {
    id: tools
    x: (composition.width - width) / 2; y: 29
    width: Math.max(controls.width + 32, studyTitle.implicitWidth + 32); height: 80; radius: 24
    visible: composition.showTools
    color: "#eceef1f3"
    Text { id: studyTitle; x: 16; y: 10; text: "WIDGET STUDY  /  " + ["Duet · continuous rails", "Islands · six surfaces", "Split · workstation shelf"][composition.direction] + "  /  " + composition.dataProvenance; color: "#435362"; font { family: "Adwaita Sans"; pixelSize: 10; weight: Font.DemiBold } }
    Row {
      id: controls
      x: 16; y: 34; spacing: 6
      Button { objectName: "foregroundButton"; scene: composition; text: composition.darkText ? "Dark text" : "Light text"; onClicked: composition.darkText = !composition.darkText }
      Button { scene: composition; text: ["Flower", "Desert", "Bright", "Dark", "Detail"][composition.background]; onClicked: composition.background = (composition.background + 1) % 5 }
      Button { scene: composition; text: ["Duet", "Islands", "Split"][composition.direction]; onClicked: composition.direction = (composition.direction + 1) % 3 }
      Button { scene: composition; text: ["Normal", "Long values", "Missing data"][composition.scenario]; onClicked: composition.scenario = (composition.scenario + 1) % 3 }
      Button { scene: composition; text: composition.animated ? "Pause" : "Motion"; onClicked: composition.animated = !composition.animated }
    }
  }
  Rectangle {
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
    width: Math.min(960, footer.implicitWidth + 30); height: footer.implicitHeight + 16; radius: 15; color: "#e9edf0f3"
    Text { id: footer; objectName: "previewProvenance"; anchors.centerIn: parent; width: parent.width - 30; wrapMode: Text.WordWrap; text: composition.showTools ? composition.detail || "F text   B backdrop   D composition   E data   Space motion   H controls" : composition.dataProvenance + (composition.detail ? " · " + composition.detail : ""); color: "#435362"; font { family: "Adwaita Sans"; pixelSize: 11 } }
  }
  // Used by the renderer to check that critical content remains inside the body.
  function audit() {
    if (direction === 0) return Object.assign({}, leftPanel.audit(), rightPanel.audit());
    return { localBottom: local.y + local.implicitHeight, mainBottom: main.y + main.implicitHeight,
      historyBottom: history.y + history.implicitHeight, todayBottom: today.y + today.implicitHeight,
      weatherBottom: weather.y + weather.implicitHeight, radarBottom: radar.y + radar.implicitHeight };
  }
  function updateDemo() { readings = Fixture.changing(phase, scenario); }
}
