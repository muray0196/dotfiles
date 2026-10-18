pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
  id: scene
  width: 1120
  height: 760
  color: "#fafbfc"
  focus: true
  property int pattern: 4
  readonly property bool flowerStudy: pattern === 4
  readonly property bool desertStudy: pattern === 5
  readonly property bool photoStudy: flowerStudy || desertStudy
  readonly property bool classicStudy: pattern < 4
  readonly property bool referenceStudy: pattern >= 6 && pattern <= 8
  readonly property bool sizeStudy: pattern === 9
  readonly property real desertScale: Math.max(stage.width / 1920, stage.height / 1080)
  property bool animated: true
  property bool dark: false
  property bool compare: false
  property real materialAmount: compare ? 0 : 1
  Behavior on materialAmount { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
  property bool bend: true
  property bool scatter: true
  property bool illuminate: true
  property int diagnostic: 0
  property real phase: 0
  readonly property real flowerBevel: 36
  readonly property real flowerHeight: 48
  readonly property real flowerDepth: 240
  property real lensX: flowerStudy ? 390 : 718
  property real lensY: flowerStudy ? 185 : 204
  readonly property color ink: dark ? "#f7f9ff" : "#152238"
  onPatternChanged: {
    placeLens();
    if (pattern >= 6) phase = 0;
  }

  function placeLens() {
    // Read the changed property directly; dependent bindings may update later.
    lensX = pattern === 4 ? 390 : 718;
    lensY = pattern === 4 ? 185 : 204;
    if (pattern === 5) {
      lensX = stage.width / 2 - 236 * desertScale;
      lensY = stage.height / 2 - 231 * desertScale;
    }
  }

  FrameAnimation {
    running: scene.animated && scene.visible
    onTriggered: scene.phase += frameTime
  }

  Keys.onPressed: event => {
    if (event.key === Qt.Key_Space) scene.animated = !scene.animated;
    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) scene.pattern = event.key - Qt.Key_1;
    else if (event.key === Qt.Key_0) scene.pattern = 9;
    else if (event.key === Qt.Key_G) scene.compare = !scene.compare;
    else if (event.key === Qt.Key_R) scene.reset();
    else return;
    event.accepted = true;
  }

  function reset() {
    placeLens();
    phase = 0;
    diagnostic = 0;
    compare = false;
    bend = true;
    scatter = true;
    illuminate = true;
  }

  Text {
    x: 30; y: 22
    text: "Liquid Glass"
    color: "#182335"
    font.pixelSize: 25
    font.weight: Font.DemiBold
  }
  Text {
    x: 31; y: 54
    text: scene.flowerStudy ? "Flower · drag the large lens · Space pauses motion"
          : scene.desertStudy ? "Desert study · drag across the dunes · Compare dissolves the lens"
          : scene.pattern === 6 ? "Boundary · moving glass, fixed background · Space pauses motion"
          : scene.pattern === 7 ? "Lighting · fixed glass, travelling highlights · Space pauses motion"
          : scene.pattern === 8 ? "Panel · moving rounded surface · monochrome dune study"
          : scene.sizeStudy ? "Size · a control grows into a surface · Space pauses motion"
                           : "A new material study · drag the lens across the scene"
    color: "#6b7584"
    font.pixelSize: 12
  }
  Row {
    x: scene.width - width - 30; y: 31
    spacing: 6
    Repeater {
      model: ["Color", "Grid", "Type", "Contrast", "Flower", "Desert", "Boundary", "Lighting", "Panel", "Size"]
      LabButton {
        required property int index
        required property string modelData
        text: modelData
        selected: scene.pattern === index
        onClicked: scene.pattern = index
      }
    }
  }

  Item {
    id: stage
    x: 20; y: 90
    width: scene.width - 40
    height: scene.height - 170
    clip: true

    Item {
      id: background
      anchors.fill: parent
      visible: !scene.referenceStudy && !scene.sizeStudy
      ShaderEffect {
        anchors.fill: parent
        visible: scene.classicStudy
        property vector2d sceneSize: Qt.vector2d(width, height)
        property real phase: scene.phase
        property real pattern: scene.pattern
        property real dark: scene.dark ? 1 : 0
        fragmentShader: "backdrop.frag.qsb"
      }
      Image {
        objectName: "flowerImage"
        // Repeatable source motion, not a simulation of the reference's wind.
        // Overscan covers the whole path without moving the glass geometry.
        x: -48 + 44 * Math.sin(scene.phase * Math.PI / 3)
        y: -12 + 8 * Math.sin(scene.phase * Math.PI / 3)
        width: parent.width + 96
        height: parent.height + 24
        source: "flower.png"
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: scene.flowerStudy
      }
      Image {
        id: desertImage
        objectName: "desertImage"
        source: "desert.png"
        smooth: true
        visible: false
      }
      ShaderEffect {
        anchors.fill: parent
        visible: scene.desertStudy
        property Item source: desertImage
        property vector2d viewSize: Qt.vector2d(width, height)
        // At phase zero, reproduce the earlier 177s/179.8s alignment.
        // Motion is a gentle repeatable zoom of the still, not the source video.
        property real sourceScale: 1.01 / (1 + 0.02 * (1 - Math.cos(scene.phase * Math.PI / 3)))
        fragmentShader: "desert.frag.qsb"
      }
      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.65
        visible: scene.photoStudy && scene.dark
      }
      Column {
        x: 48 + 30 * Math.sin(scene.phase * 0.25)
        y: 56
        spacing: 2
        visible: scene.pattern === 2
        Repeater {
          model: ["Light in", "motion.", "0123456789", "Aa Bb Cc Dd"]
          Text {
            required property string modelData
            text: modelData
            color: scene.dark ? "#eef2fa" : "#27354c"
            font.pixelSize: 96
            font.weight: Font.Bold
            font.letterSpacing: -4
          }
        }
      }
      Text {
        x: 38; y: stage.height - 56
        visible: scene.classicStudy
        text: "THE SCENE BEHIND THE GLASS"
        color: scene.dark ? "#e8edf8" : "#334255"
        font.pixelSize: 11
        font.letterSpacing: 2.4
      }
    }

    BackdropSource {
      id: source
      sourceItem: background
      blurRadius: scene.flowerStudy ? 12 : 14
    }

    Glass {
      id: panel
      objectName: "panel"
      visible: scene.classicStudy
      x: 88; y: 118
      width: 366; height: 286
      backdrop: source.sharp
      softenedBackdrop: source.soft
      backdropSize: Qt.size(stage.width, stage.height)
      backdropPosition: Qt.point(x, y)
      radius: 46
      edgeWidth: radius * 180 / 220
      surfaceHeight: radius * 150 / 220
      thickness: radius * 2
      refraction: scene.bend ? 1 : 0
      softness: scene.scatter ? 0.88 : 0
      transmissionRoughness: 0
      edgeSoftness: scene.scatter ? 0.55 : 0
      lighting: scene.illuminate ? 1 : 0
      adaptation: 1
      shadowStrength: 0.14
      presence: scene.materialAmount
      diagnostic: scene.diagnostic
    }

    AdaptiveInk {
      x: panel.x + 32; y: panel.y + 32
      width: panel.width - 64; height: panel.height - 64
      backdrop: source.soft
      sampleRegion: Qt.rect(panel.x / stage.width, panel.y / stage.height,
                            panel.width / stage.width, panel.height / stage.height)
      visible: scene.diagnostic === 0 && scene.classicStudy
      Column {
        anchors.fill: parent
        spacing: 14
        Text { text: "SATURDAY"; color: "white"; font.pixelSize: 11; font.letterSpacing: 2.2 }
        Text { text: "09:41"; color: "white"; font.pixelSize: 72; font.weight: Font.Light }
        Text { text: "Light, shaped."; color: "white"; font.pixelSize: 22; font.weight: Font.Medium }
        Text {
          text: "A quiet surface. A living edge.\nThe content stays in focus."
          color: "white"; opacity: 0.8
          font.pixelSize: 13; lineHeight: 1.45
        }
      }
    }

    Glass {
      id: lens
      objectName: "lens"
      visible: scene.pattern < 6
      readonly property real restWidth: scene.flowerStudy ? 220 : scene.desertStudy ? 466 * scene.desertScale : 184
      readonly property real restHeight: scene.flowerStudy ? 220 : scene.desertStudy ? restWidth : 126
      property real press: lensPointer.pressed ? 1 : 0
      Behavior on press { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      x: scene.lensX - (width - restWidth) * 0.5
      y: scene.lensY - (height - restHeight) * 0.5
      width: restWidth + press * 18
      height: restHeight - press * 5
      backdrop: source.sharp
      softenedBackdrop: source.soft
      backdropSize: Qt.size(stage.width, stage.height)
      backdropPosition: Qt.point(x, y)
      radius: height * 0.5
      // Flower needs rays that cross the circle's center near the boundary.
      // Both sizes share optical lengths; scaling every length with diameter
      // suppressed the smaller circle's stronger wrapping in the reference.
      edgeWidth: scene.flowerStudy ? scene.flowerBevel : scene.desertStudy ? 26 * scene.desertScale : 32
      surfaceHeight: scene.flowerStudy ? scene.flowerHeight : scene.desertStudy ? 36 * scene.desertScale : 24
      thickness: (scene.flowerStudy ? scene.flowerDepth : scene.desertStudy ? 200 * scene.desertScale : 34) + press * 8
      magnification: (scene.photoStudy ? 0 : 0.10) + press * 0.025
      crownHeight: 0
      transmissionRoughness: 0
      refraction: scene.bend ? 1 : 0
      softness: scene.photoStudy && scene.scatter ? 1 : 0
      edgeSoftness: 0
      lighting: scene.illuminate ? 1 + press * 0.25 : 0
      ambientReflection: 0
      adaptation: scene.photoStudy ? 0 : 0.45
      shadowStrength: scene.photoStudy ? 0.08 : 0.18
      presence: scene.materialAmount
      diagnostic: scene.diagnostic

      AdaptiveInk {
        anchors.centerIn: parent
        width: 140; height: 36
        backdrop: source.soft
        sampleRegion: Qt.rect(lens.x / stage.width, lens.y / stage.height,
                              lens.width / stage.width, lens.height / stage.height)
        visible: scene.diagnostic === 0 && scene.classicStudy
        Text {
          anchors.centerIn: parent
          text: lensPointer.pressed ? "Move" : "Drag me"
          color: "white"
          font.pixelSize: 15
          font.weight: Font.Medium
        }
      }

      MouseArea {
        id: lensPointer
        objectName: "lensPointer"
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point down
        property point start
        onPressed: mouse => {
          down = mapToItem(stage, mouse.x, mouse.y);
          start = Qt.point(scene.lensX, scene.lensY);
        }
        onPositionChanged: mouse => {
          if (!pressed) return;
          const position = mapToItem(stage, mouse.x, mouse.y);
          scene.lensX = Math.max(30, Math.min(stage.width - lens.width - 30, start.x + position.x - down.x));
          scene.lensY = Math.max(30, Math.min(stage.height - lens.height - 30, start.y + position.y - down.y));
        }
      }
    }

    Glass {
      objectName: "smallLens"
      crownHeight: 0
      transmissionRoughness: 0
      visible: scene.flowerStudy
      x: 130; y: 310
      width: 152; height: 152
      radius: 76
      backdrop: source.sharp
      softenedBackdrop: source.soft
      backdropSize: Qt.size(stage.width, stage.height)
      backdropPosition: Qt.point(x, y)
      edgeWidth: scene.flowerBevel
      surfaceHeight: scene.flowerHeight
      thickness: scene.flowerDepth
      refraction: scene.bend ? 1 : 0
      softness: scene.scatter ? 1 : 0
      edgeSoftness: 0
      lighting: scene.illuminate ? 1 : 0
      ambientReflection: 0
      adaptation: 0
      shadowStrength: 0.08
      presence: scene.materialAmount
      diagnostic: scene.diagnostic
    }

    Text {
      x: panel.x; y: stage.height - 90
      visible: scene.classicStudy
      text: "ROUNDED SURFACE"
      color: scene.ink; opacity: 0.6
      font.pixelSize: 10; font.letterSpacing: 1.6
    }
    Text {
      x: 718; y: stage.height - 90
      visible: scene.classicStudy
      text: "INTERACTIVE LENS"
      color: scene.ink; opacity: 0.6
      font.pixelSize: 10; font.letterSpacing: 1.6
    }

    ReferenceStudy {
      objectName: "referenceStudy"
      anchors.fill: parent
      visible: scene.referenceStudy
      mode: Math.max(0, Math.min(2, scene.pattern - 6))
      phase: scene.phase
      presence: scene.materialAmount
      bend: scene.bend
      scatter: scene.scatter
      illuminate: scene.illuminate
      dark: scene.dark
      diagnostic: scene.diagnostic
    }
    SizeStudy {
      objectName: "sizeStudy"
      anchors.fill: parent
      visible: scene.sizeStudy
      phase: scene.phase
      presence: scene.materialAmount
      bend: scene.bend
      illuminate: scene.illuminate
      dark: scene.dark
      diagnostic: scene.diagnostic
    }
  }

  Row {
    x: 25; y: scene.height - 61
    spacing: 6
    LabButton { text: "Motion"; selected: scene.animated; onClicked: scene.animated = !scene.animated }
    LabButton { text: "Dark"; selected: scene.dark; onClicked: scene.dark = !scene.dark }
    LabButton { text: "Refraction"; selected: scene.bend; onClicked: scene.bend = !scene.bend }
    LabButton { text: "Softness"; visible: !scene.sizeStudy; selected: scene.scatter; onClicked: scene.scatter = !scene.scatter }
    LabButton { text: "Light"; selected: scene.illuminate; onClicked: scene.illuminate = !scene.illuminate }
    LabButton { text: "Compare"; selected: scene.compare; onClicked: scene.compare = !scene.compare }
    LabButton {
      text: ["Inspect", "Distance", "Direction"][scene.diagnostic]
      selected: scene.diagnostic !== 0
      onClicked: scene.diagnostic = (scene.diagnostic + 1) % 3
    }
    LabButton { text: "Reset"; onClicked: scene.reset() }
  }
  Text {
    anchors.right: parent.right; anchors.rightMargin: 27
    y: scene.height - 22
    text: "1–9, 0 scene · Space pause · G compare"
    color: "#768190"; font.pixelSize: 11
  }
}
