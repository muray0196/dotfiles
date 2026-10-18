pragma ComponentBehavior: Bound
import QtQuick
import "widget" as Widget
import "TintPalette.js" as Tints

Rectangle {
  id: playground
  width: 1120; height: 800
  color: "#fafbfc"
  focus: true
  property int shape: 5
  property int background: 0
  property int clarity: 1
  property int tint: 0
  readonly property var tintPresets: Tints.presets
  property bool animated: false
  property bool showContent: true
  property bool darkText: false
  property bool compare: false
  property real phase: 0
  property string detail: ""
  readonly property var shapeNames: ["Circle", "Pill", "Card", "Wide panel", "Tall panel", "Collection"]
  readonly property var backgroundNames: ["Flower", "Desert", "Color", "Grid", "Type", "Split", "White", "Dark"]
  signal closeRequested()
  signal recenter()

  function showDetail(text, item) { detail = text; }
  function hideDetail() { detail = ""; }
  function reset() {
    phase = 0;
    compare = false;
    recenter();
  }
  onShapeChanged: recenter()
  onWidthChanged: recenter()
  onHeightChanged: recenter()
  FrameAnimation {
    running: playground.animated && playground.visible
    onTriggered: playground.phase += frameTime * 0.35
  }
  Keys.onPressed: event => {
    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_6) playground.shape = event.key - Qt.Key_1;
    else if (event.key === Qt.Key_B) playground.background = (playground.background + 1) % 8;
    else if (event.key === Qt.Key_Space) playground.animated = !playground.animated;
    else if (event.key === Qt.Key_G) playground.compare = !playground.compare;
    else if (event.key === Qt.Key_R) playground.reset();
    else if (event.key === Qt.Key_Escape) playground.closeRequested();
    else return;
    event.accepted = true;
  }

  Text {
    x: 26; y: 19
    text: "Glass Playground"
    color: "#182335"; font { family: "Adwaita Sans"; pixelSize: 25; weight: Font.DemiBold }
  }
  Text {
    x: 27; y: 54
    text: "Drag the glass. Explore its shape, light, and the view beneath it."
    color: "#6b7584"; font.pixelSize: 12
  }
  Row {
    x: 26; y: 86; spacing: 6
    Text { width: 84; height: 34; verticalAlignment: Text.AlignVCenter; text: "SHAPE"; color: "#6b7584"; font { pixelSize: 10; weight: Font.DemiBold; letterSpacing: 1 } }
    Repeater {
      model: playground.shapeNames
      LabButton {
        required property int index
        required property string modelData
        objectName: "shapeButton" + index
        text: modelData; selected: playground.shape === index
        onClicked: playground.shape = index
      }
    }
  }
  Row {
    x: 26; y: 128; spacing: 6
    Text { width: 84; height: 34; verticalAlignment: Text.AlignVCenter; text: "BACKGROUND"; color: "#6b7584"; font { pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.5 } }
    Repeater {
      model: playground.backgroundNames
      LabButton {
        required property int index
        required property string modelData
        objectName: "backgroundButton" + index
        text: modelData; selected: playground.background === index
        onClicked: playground.background = index
      }
    }
  }

  Item {
    id: stage
    objectName: "playgroundStage"
    x: 20; y: 180
    width: playground.width - 40; height: playground.height - 336
    clip: true
    PlaygroundBackdrop {
      id: backdrop
      anchors.fill: parent
      selection: playground.background
      phase: playground.phase
    }
    BackdropSource {
      id: pool
      sourceItem: backdrop
      // The desktop's shared half-resolution analysis filter uses sigma 2.8.
      // One source pool for every shape and every appearance.
      blurRadius: 6 * 2.8
    }
    Repeater {
      id: samples
      model: playground.shape === 5 ? 3 : 1
      Item {
        id: specimen
        required property int index
        readonly property int kind: playground.shape === 5 ? index : playground.shape
        readonly property bool round: kind <= 1
        property real offsetX: 0
        property real offsetY: 0
        Connections {
          target: playground
          function onRecenter() { specimen.offsetX = 0; specimen.offsetY = 0; }
        }
        width: kind === 0 ? 212 : kind === 1 ? 380 : kind === 2 ? 340 : kind === 3 ? Math.min(680, stage.width - 80) : 350
        height: kind === 0 ? 212 : kind === 1 ? 112 : kind === 2 ? 246 : kind === 3 ? Math.min(380, stage.height - 64) : stage.height - 64
        readonly property real centerX: playground.shape === 5 ? stage.width * [0.17, 0.60, 0.66][index] : stage.width / 2
        readonly property real centerY: playground.shape === 5 ? stage.height * [0.5, 0.23, 0.66][index] : stage.height / 2
        x: Math.max(28, Math.min(stage.width - width - 28, centerX - width / 2 + offsetX))
        y: Math.max(28, Math.min(stage.height - height - 28, centerY - height / 2 + offsetY))

        Glass {
          id: glass
          objectName: "playgroundGlass" + specimen.index
          anchors.fill: parent
          // Geometry is the only shape-specific input. All optical laws remain
          // inherited from the current Glass component and its shared shader.
          radius: specimen.round ? Math.min(width, height) / 2 : Math.min(56, Math.min(width, height) / 2)
          backdrop: pool.sharp
          softenedBackdrop: pool.soft
          backdropSize: Qt.size(stage.width, stage.height)
          backdropPosition: Qt.point(specimen.x, specimen.y)
          transmissionRoughness: playground.clarity === 1 ? 0.008 : 0
          diffusion: playground.clarity === 2 ? 1 : 0
          tintColor: playground.tintPresets[playground.tint].color
          presence: playground.compare ? 0 : 1
        }
        Column {
          id: sampleContent
          anchors.centerIn: parent
          width: parent.width - (specimen.round ? 48 : 64)
          spacing: 8
          visible: playground.showContent
          Widget.Label {
            scene: playground; width: sampleContent.width
            text: specimen.round ? "09:41" : "Today"
            align: specimen.round ? Text.AlignHCenter : Text.AlignLeft
            size: specimen.kind === 0 ? 42 : specimen.kind === 1 ? 32 : 21
            weight: specimen.round ? Font.Normal : Font.DemiBold
          }
          Widget.Label {
            scene: playground; width: sampleContent.width
            text: specimen.round ? "Sunday, October 18" : "24°"
            align: specimen.round ? Text.AlignHCenter : Text.AlignLeft
            size: specimen.round ? 12 : 52
          }
          Widget.Label {
            scene: playground; width: sampleContent.width
            visible: !specimen.round
            text: "Clear skies · Feels like 25°"; size: 14
          }
          Rectangle {
            visible: !specimen.round
            width: parent.width; height: 1
            color: playground.darkText ? "#21344857" : "#44d2e0e8"
          }
          Widget.Label {
            scene: playground; width: sampleContent.width
            visible: !specimen.round
            text: "Humidity  48%       Wind  2 m/s"
            size: 12; muted: true
          }
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          property point down
          property point start
          onPressed: mouse => {
            down = mapToItem(stage, mouse.x, mouse.y);
            start = Qt.point(specimen.x, specimen.y);
          }
          onPositionChanged: mouse => {
            if (!pressed) return;
            const point = mapToItem(stage, mouse.x, mouse.y);
            const x = Math.max(28, Math.min(stage.width - specimen.width - 28, start.x + point.x - down.x));
            const y = Math.max(28, Math.min(stage.height - specimen.height - 28, start.y + point.y - down.y));
            specimen.offsetX = x - specimen.centerX + specimen.width / 2;
            specimen.offsetY = y - specimen.centerY + specimen.height / 2;
          }
        }
      }
    }
  }
  Row {
    x: 25; y: playground.height - 139; spacing: 7
    Text { text: "CLARITY"; width: 65; anchors.verticalCenter: parent.verticalCenter; color: "#64748b"; font.pixelSize: 10; font.weight: Font.DemiBold }
    Repeater {
      model: ["Clear", "Soft", "Diffused"]
      LabButton {
        required property int index
        required property string modelData
        objectName: "clarityButton" + index
        text: modelData; selected: playground.clarity === index
        onClicked: playground.clarity = index
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: 12
      color: "#64748b"; font.pixelSize: 11
      text: ["Full background detail", "Gentle detail smoothing", "Stronger background separation"][playground.clarity]
    }
  }
  Row {
    x: 25; y: playground.height - 98; spacing: 7
    Text { text: "TINT"; width: 65; anchors.verticalCenter: parent.verticalCenter; color: "#64748b"; font.pixelSize: 10; font.weight: Font.DemiBold }
    Repeater {
      model: playground.tintPresets
      LabButton {
        id: tintButton
        required property int index
        required property var modelData
        objectName: "tintButton" + index
        text: modelData.label; selected: playground.tint === index
        onClicked: playground.tint = index
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom; anchors.bottomMargin: 3
          width: 14; height: 3; radius: 1.5
          visible: tintButton.modelData.name !== "off"
          color: tintButton.modelData.swatch
          border.color: tintButton.modelData.name === "white" ? "#aeb7c3" : "transparent"
        }
      }
    }
  }
  Row {
    x: 25; y: playground.height - 57; spacing: 7
    Text { text: "PREVIEW"; width: 65; anchors.verticalCenter: parent.verticalCenter; color: "#64748b"; font.pixelSize: 10; font.weight: Font.DemiBold }
    LabButton { text: "Content"; selected: playground.showContent; onClicked: playground.showContent = !playground.showContent }
    LabButton { text: "Dark text"; selected: playground.darkText; onClicked: playground.darkText = !playground.darkText }
    LabButton { text: "Motion"; selected: playground.animated; onClicked: playground.animated = !playground.animated }
    LabButton { objectName: "compareButton"; text: "Compare"; selected: playground.compare; onClicked: playground.compare = !playground.compare }
    LabButton { text: "Recenter"; onClicked: playground.reset() }
  }
  LabButton {
    objectName: "closeButton"
    anchors.right: parent.right; anchors.rightMargin: 25
    y: playground.height - 57
    text: "Close"; onClicked: playground.closeRequested()
  }
  Text {
    x: 27; y: playground.height - 22
    text: playground.detail || "Sample content · 1–6 shape · B background · Space motion · G compare · R recenter · Esc close"
    color: "#768190"; font.pixelSize: 11
  }
}
