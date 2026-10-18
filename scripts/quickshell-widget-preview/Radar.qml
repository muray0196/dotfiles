pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F

Item {
  id: radar
  required property var scene
  readonly property var incoming: scene.readings.radar || {}
  readonly property string incomingKey: JSON.stringify([incoming.reference_time, incoming.frames || []])
  property var reading: ({})
  onIncomingKeyChanged: reading = incoming
  Component.onCompleted: reading = incoming
  readonly property var frames: reading.frames || []
  property int frameIndex: 0
  property bool playing: false
  readonly property var frame: frames[frameIndex] || {}
  property bool tileFailed: false
  onFramesChanged: {
    frameIndex = Math.max(0, frames.findIndex(f => f.offset_minutes === 0));
    playing = reading.nearby_precipitation === true && frames.length > 1;
    tileFailed = false;
  }
  property real viewportHeight: 157
  readonly property real headerHeight: 36
  implicitHeight: viewportHeight + headerHeight
  Label { id: radarTitle; scene: radar.scene; text: "Rain radar"; size: 21; weight: Font.DemiBold }
  Label {
    id: radarTime
    scene: radar.scene; anchors { right: parent.right; baseline: radarTitle.baseline }
    width: Math.min(implicitWidth, Math.max(0, parent.width - radarTitle.width - 12 - (radarTimeIcon.visible ? 18 : 0)))
    text: F.radarStamp(radar.frame, radar.incoming, radar.scene.clockDate)
    accessibleText: (radar.frame.forecast ? "Forecast frame · " : "Observed frame · ") + text + " · JMA"
    size: 12; muted: true; align: Text.AlignRight
  }
  Label {
    id: radarTimeIcon
    scene: radar.scene; visible: !!radar.frame.frame_time && !radar.frame.forecast && radar.incoming._status !== "Cached"
    x: radarTime.x - width - 4; width: 14; size: 14; muted: true
    y: radarTime.y + radarTime.capCenterY - inkCenterY
    family: "Material Symbols Rounded"; text: "\ue8b5"
    accessibleText: radarTime.accessibleText
  }
  Rectangle {
    id: viewport
    // Leave the glass visible through the map; precipitation keeps its source colors.
    y: radar.headerHeight; width: parent.width; height: radar.viewportHeight; radius: 14; color: "transparent"; clip: true
    border { width: 1; color: radar.scene.darkText ? "#21344857" : "#44d2e0e8" }
    Item {
      anchors.centerIn: parent
      width: 0; height: 0
      Repeater {
        model: radar.frame.radar_tiles || []
        Image {
          required property var modelData
          x: (modelData.column * radar.reading.tile_size - radar.reading.radar_center_pixel_x) * radar.reading.radar_scale
          y: (modelData.row * radar.reading.tile_size - radar.reading.radar_center_pixel_y) * radar.reading.radar_scale
          width: radar.reading.tile_size * radar.reading.radar_scale; height: width
          source: modelData.url; smooth: false
          onStatusChanged: if (status === Image.Error) radar.tileFailed = true
        }
      }
    }
    Repeater {
      model: [2000, 5000]
      Rectangle {
        required property int modelData
        anchors.centerIn: parent
        width: radar.reading.meters_per_pixel ? 2 * modelData / radar.reading.meters_per_pixel : 0
        height: width; radius: width / 2; color: "transparent"; border { width: 1; color: "#55ffffff" }
      }
    }
    Rectangle {
      anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: "#fafbff"
      border { width: 1; color: "#80000000" }
      visible: radar.frames.length > 0
    }
    Label {
      scene: radar.scene
      anchors.centerIn: parent
      width: parent.width - 16; align: Text.AlignHCenter; size: 13
      text: radar.tileFailed ? "Radar tiles unavailable" : "Radar unavailable"
      visible: !radar.frames.length || radar.tileFailed
    }
    Label {
      scene: radar.scene
      anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
      width: parent.width - 16; size: 11; muted: true
      text: radar.frames.length ? Math.round(viewport.width * radar.reading.meters_per_pixel / 1000) + " × " + Math.round(viewport.height * radar.reading.meters_per_pixel / 1000) + " km · rings 2 / 5 km" : "JMA precipitation · waiting for data"
    }
    Row {
      visible: radar.frames.length > 1
      anchors { top: parent.top; left: parent.left; margins: 8 }
      spacing: 4
      Repeater {
        model: radar.frames
        Button {
          required property var modelData
          required property int index
          scene: radar.scene; overlay: true
          text: modelData.offset_minutes === 0 ? "Latest" : (modelData.offset_minutes > 0 ? "+" : "") + modelData.offset_minutes + "m"
          selected: radar.frameIndex === index
          onClicked: { radar.frameIndex = index; radar.playing = false; radar.tileFailed = false; }
        }
      }
      Button { scene: radar.scene; overlay: true; text: radar.playing ? "Pause radar animation" : "Play radar animation"; icon: radar.playing ? "\ue034" : "\ue037"; visible: radar.frames.length > 1; onClicked: radar.playing = !radar.playing }
    }
    Button {
      anchors { top: parent.top; right: parent.right; margins: 8 }
      scene: radar.scene; overlay: true; text: "JMA ↗"
      onClicked: Qt.openUrlExternally("https://www.jma.go.jp/bosai/nowc/")
    }
  }
  Timer { interval: 1600; running: radar.playing && radar.frames.length > 1; repeat: true; onTriggered: { radar.frameIndex = (radar.frameIndex + 1) % radar.frames.length; radar.tileFailed = false; } }
}
