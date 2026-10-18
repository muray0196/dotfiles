pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F

Item {
  id: history
  required property var scene
  readonly property var values: scene.readings.history || {}
  readonly property bool hasReadings: ["local_cpu", "local_gpu1", "local_gpu2", "main_cpu", "main_gpu", "local_average", "main_average"].some(key => typeof values[key] === "number" && isFinite(values[key]))
  readonly property real windowSeconds: typeof values.window_seconds === "number" ? values.window_seconds : 0
  implicitHeight: 243
  Label {
    id: historyTitle
    scene: history.scene; size: 21; weight: Font.DemiBold
    width: parent.width - (history.hasReadings ? 0 : 70)
    text: !history.hasReadings || history.windowSeconds >= 600 ? "Last 10 minutes"
      : history.windowSeconds < 60 ? "Since startup"
      : history.windowSeconds < 120 ? "Last minute"
      : "Last " + Math.floor(history.windowSeconds / 60) + " minutes"
    accessibleText: !history.hasReadings ? "Ten-minute history: no data available."
      : "History covers " + Math.floor(history.windowSeconds / 60) + " minutes and " + history.windowSeconds % 60 + " seconds of a ten-minute window. Missing readings are excluded."
  }
  Label {
    scene: history.scene; anchors.baseline: historyTitle.baseline
    x: parent.width - 70; width: 70; align: Text.AlignRight; size: 12; muted: true
    text: "No data"; visible: !history.hasReadings
  }
  component Readout: Item {
    id: readout
    required property string name
    required property var value
    required property string unit
    required property string description
    property bool device: false
    height: 49
    DeviceIcon {
      scene: history.scene; visible: readout.device; width: 16
      cpu: readout.name === "CPU"; description: readout.description
      y: nameLabel.y + nameLabel.capCenterY - height / 2
    }
    Label { id: nameLabel; scene: history.scene; text: readout.name; accessibleText: readout.description; size: 12; muted: true; x: readout.device ? 20 : 0; width: parent.width - x }
    Label {
      id: valueLabel
      scene: history.scene; y: 18
      text: F.number(readout.value); accessibleText: readout.description; size: 22; weight: Font.Medium
      width: Math.min(implicitWidth, Math.max(0, parent.width - unitLabel.width - 2))
    }
    Label {
      id: unitLabel
      scene: history.scene; text: readout.unit; accessibleText: readout.description; size: 13; muted: true
      x: valueLabel.width + 2; anchors.baseline: valueLabel.baseline
    }
  }
  Repeater {
    model: [
      {name: "Local PC", remote: false,
       temperatures: [{name: "CPU", value: history.values.local_cpu}, {name: "GPU 1", value: history.values.local_gpu1}, {name: "GPU 2", value: history.values.local_gpu2}],
       average: history.values.local_average, parts: "CPU + GPU 1 + GPU 2"},
      {name: "Main PC", remote: true,
       temperatures: [{name: "CPU", value: history.values.main_cpu}, {name: "GPU", value: history.values.main_gpu}],
       average: history.values.main_average, parts: "CPU + GPU"}
    ]
    Item {
      id: group
      required property var modelData
      required property int index
      readonly property real powerX: width - 80
      readonly property real temperatureWidth: powerX - 14
      y: 38 + index * 104; width: history.width; height: 98
      Label { scene: history.scene; text: F.machineSymbol(group.modelData.remote); family: "Material Symbols Rounded"; size: 18; width: 18; y: groupTitle.y + groupTitle.capCenterY - inkCenterY; accessibleText: group.modelData.name }
      Label { id: groupTitle; scene: history.scene; x: 24; text: group.modelData.name; size: 15; weight: Font.DemiBold }
      Label { scene: history.scene; y: 24; text: "Peak temp"; size: 12; ink: F.temperatureInk(history.scene.darkText) }
      Rectangle { x: group.temperatureWidth + 6; y: 24; width: 1; height: 70; color: history.scene.darkText ? "#21344857" : "#33d2e0e8" }
      Label { scene: history.scene; x: group.powerX; y: 24; text: "Compute"; size: 12; ink: F.powerInk(history.scene.darkText) }
      Repeater {
        model: group.modelData.temperatures
        Readout {
          required property var modelData
          required property int index
          x: index * width; y: 46; width: group.temperatureWidth / 3
          name: modelData.name; value: modelData.value; unit: "°C"
          device: true
          description: group.modelData.name + " " + name + " peak temperature: " + F.number(value) + " °C"
        }
      }
      Readout {
        x: group.powerX; y: 46; width: group.width - x
        name: "Avg"; value: group.modelData.average; unit: "W"
        description: group.modelData.name + " average compute power: " + F.number(value) + " W (" + group.modelData.parts + ")"
      }
    }
  }
}
