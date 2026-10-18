pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "Format.js" as F

Item {
  id: machine
  required property var scene
  required property var reading
  property bool remote: false
  readonly property var gpus: reading.gpus || []
  readonly property var volumes: {
    const list = reading.storage_volumes || [];
    return list.some(v => v.label.toUpperCase() === "ROOT") ? list
      : [Object.assign({}, reading.storage || {}, {label: "ROOT", available: typeof (reading.storage || {}).used_bytes === "number"}), ...list];
  }
  readonly property int gpuCount: Math.max(1, gpus.length)
  readonly property string state: reading._status || "No data"
  readonly property bool readingsUnavailable: ["No signal", "No data"].includes(state)
  layer.enabled: readingsUnavailable
  layer.effect: MultiEffect {
    saturation: -1
    brightness: machine.scene.darkText ? 0.16 : -0.18
  }
  readonly property string statusDescription: {
    const meanings = {
      "Live": "Readings are current. Updates every 2 seconds.",
      "Partial": "Readings are current, but some values are unavailable.",
      "Stale": "No new readings for over 6 seconds. Displayed values may be out of date.",
      "No signal": "No recent readings from this PC. Displayed values may be out of date.",
      "No data": "No current readings available.",
      "Snapshot": "Saved reading; not being refreshed."
    };
    return machineTitle.text + ": " + (meanings[state] || state);
  }
  readonly property real deviceEnd: 44 + (1 + gpuCount) * 88
  implicitHeight: remote ? deviceEnd : deviceEnd + 29 + volumes.length * 24 + 56
  Label { scene: machine.scene; text: F.machineSymbol(machine.remote); family: "Material Symbols Rounded"; size: 24; width: 24; y: machineTitle.y + machineTitle.capCenterY - inkCenterY; accessibleText: machine.remote ? "Windows PC" : "Arch Linux PC" }
  Label { id: machineTitle; scene: machine.scene; x: 32; text: machine.remote ? "Main PC" : "Local PC"; accessibleText: machine.statusDescription; size: 21; weight: Font.DemiBold; width: Math.min(implicitWidth, parent.width - x - 110) }
  Label {
    scene: machine.scene; x: machineTitle.x + machineTitle.width + 12; width: parent.width - x
    anchors.baseline: machineTitle.baseline
    text: machine.state; size: 12; muted: true; visible: machine.state !== "Live"
    ink: ["Partial", "Stale"].includes(machine.state) ? (machine.scene.darkText ? "#916011" : "#f0c77f")
      : machine.scene.darkText ? "#455563" : "#e6ebf2"
    accessibleText: machine.statusDescription
  }
  Label { x: 32; y: 27; width: parent.width - x; scene: machine.scene; size: 12; weight: Font.Normal; muted: true; text: machine.remote ? "Windows · " + (machine.reading.host || "Waiting for host") : "Arch Linux · " + F.uptime(machine.reading.uptime_seconds) }
  MetricRow { x: 8; y: 44; width: parent.width - x; scene: machine.scene; label: "CPU"; metric: machine.reading.cpu || {} }
  component UsageRing: Item {
    id: ring
    required property var percentage
    required property color ink
    required property string description
    property bool available: true
    readonly property bool validUsage: available && typeof percentage === "number" && isFinite(percentage)
    width: 16; height: 16; visible: validUsage
    Accessible.ignored: true
    // Match the adjacent text's fixed soft shadow, without a hard rim.
    MultiEffect {
      y: 1; z: -1; width: parent.width; height: parent.height
      source: ringStroke
      colorization: 1; colorizationColor: machine.scene.darkText ? "#ffffff" : "#0d1620"
      opacity: machine.scene.darkText ? 0.6 : 0.85
      blurEnabled: true; blur: 1; blurMax: 4
    }
    Shape {
      id: ringStroke
      anchors.fill: parent; preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"; strokeWidth: 1.8
        strokeColor: Qt.rgba(ring.ink.r, ring.ink.g, ring.ink.b, 0.22)
        PathAngleArc { centerX: 8; centerY: 8; radiusX: 6.5; radiusY: 6.5; startAngle: -90; sweepAngle: 360 }
      }
      ShapePath {
        fillColor: "transparent"; strokeWidth: 1.8; capStyle: ShapePath.RoundCap
        strokeColor: ring.validUsage && ring.percentage > 0 ? ring.ink : "transparent"
        PathAngleArc {
          centerX: 8; centerY: 8; radiusX: 6.5; radiusY: 6.5; startAngle: -90
          sweepAngle: ring.validUsage ? Math.max(0, Math.min(100, ring.percentage)) * 3.6 : 0
        }
      }
    }
    MouseArea {
      anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton
      onEntered: machine.scene.showDetail(ring.description, ring)
      onExited: machine.scene.hideDetail()
    }
  }
  component MemoryLine: Item {
    required property string name
    required property var value
    id: memoryLine
    readonly property string description: name + ": " + F.capacity(value) + ", " + F.number(value.usage_percent) + "% used"
    height: 20
    Label { id: memoryName; scene: machine.scene; text: memoryLine.name; size: 14; weight: Font.Medium }
    Label { id: capacity; scene: machine.scene; text: F.capacity(memoryLine.value); accessibleText: memoryLine.description; size: 14; x: memoryName.width + 8; width: Math.min(implicitWidth, Math.max(0, parent.width - x - (memoryRing.visible ? memoryRing.width + 6 : 0))) }
    UsageRing {
      id: memoryRing
      x: capacity.x + capacity.width + 6; y: capacity.y + capacity.capCenterY - height / 2
      available: memoryLine.value.available !== false
      percentage: memoryLine.value.usage_percent; ink: capacity.ink
      description: memoryLine.description
    }
  }
  MemoryLine { x: 34; y: 110; width: parent.width - x; name: "Memory"; value: machine.reading.memory || {} }
  Repeater {
    model: machine.gpuCount
    Item {
      id: gpu
      required property int index
      readonly property var metric: machine.gpus[index] || {}
      x: 8; y: 132 + index * height; width: machine.width - x; height: 88
      MetricRow { width: parent.width; scene: machine.scene; label: machine.remote ? "GPU" : "GPU " + (gpu.index + 1); metric: gpu.metric }
      MemoryLine { x: 26; y: 66; width: parent.width - x; name: "VRAM"; value: gpu.metric.vram || {} }
    }
  }
  Label { visible: !machine.remote; scene: machine.scene; y: machine.deviceEnd + 5; text: "Storage"; size: 14; weight: Font.DemiBold }
  Repeater {
    model: machine.remote ? [] : machine.volumes
    Item {
      id: volumeRow
      required property var modelData
      required property int index
      readonly property string usageDescription: modelData.label + " storage: " + F.number(modelData.usage_percent) + "% used (" + F.capacity(modelData) + ")"
      y: machine.deviceEnd + 29 + index * 24; width: machine.width; height: 24
      Label { scene: machine.scene; width: 44; text: volumeRow.modelData.label; size: 13; weight: Font.Medium }
      Label { scene: machine.scene; x: 52; width: volumeRow.modelData.available ? usageRing.x - x - 12 : parent.width - x; size: 13; text: volumeRow.modelData.available ? F.capacity(volumeRow.modelData) : volumeRow.modelData.label === "ROOT" ? "Unavailable" : "Not mounted"; muted: !volumeRow.modelData.available }
      UsageRing {
        id: usageRing
        x: usageLabel.x - width - 6; y: Math.round((usageLabel.height - height) / 2)
        available: !!volumeRow.modelData.available
        percentage: volumeRow.modelData.usage_percent; ink: usageLabel.ink
        description: volumeRow.usageDescription
      }
      Label { id: usageLabel; scene: machine.scene; x: parent.width - width; width: Math.min(implicitWidth, 44); align: Text.AlignRight; size: 13; text: F.number(volumeRow.modelData.usage_percent) + "%"; accessibleText: volumeRow.usageDescription; muted: true; visible: volumeRow.modelData.available }
    }
  }
  Label { id: networkTitle; visible: !machine.remote; scene: machine.scene; y: machine.deviceEnd + 32 + machine.volumes.length * 24; text: "Network"; size: 14; weight: Font.DemiBold }
  Label {
    visible: !machine.remote; scene: machine.scene
    anchors { left: networkTitle.right; leftMargin: 12; baseline: networkTitle.baseline }
    width: parent.width - x; align: Text.AlignRight; size: 12; weight: Font.Normal; muted: true
    text: (machine.reading.network || {}).interface || "Unavailable"
  }
  Row {
    visible: !machine.remote; y: machine.deviceEnd + 50 + machine.volumes.length * 24; width: parent.width
    Repeater {
      model: [
        {symbol: "↓", name: "Download", rate: F.rate((machine.reading.network || {}).download_bytes_per_second)},
        {symbol: "↑", name: "Upload", rate: F.rate((machine.reading.network || {}).upload_bytes_per_second)}
      ]
      Item {
        id: traffic
        required property var modelData
        readonly property var parts: modelData.rate.split(" ")
        readonly property string description: modelData.name + ": " + modelData.rate
        width: machine.width / 2; height: 28
        Label {
          scene: machine.scene; text: traffic.modelData.symbol; accessibleText: traffic.description
          y: rate.y + rate.capCenterY - inkCenterY; width: 16; size: 16
          ink: machine.scene.darkText ? "#245f9e" : "#a9cdff"
        }
        Label {
          id: rate
          scene: machine.scene; text: traffic.parts[0]; accessibleText: traffic.description
          x: 22; width: Math.min(implicitWidth, parent.width - x - rateUnit.implicitWidth - 4)
          size: 20; weight: Font.Medium
        }
        Label {
          id: rateUnit
          scene: machine.scene; text: traffic.parts[1] || ""; accessibleText: traffic.description
          anchors { left: rate.right; leftMargin: 4; baseline: rate.baseline }
          size: 13; weight: Font.Normal; muted: true
        }
      }
    }
  }
}
