pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F

Item {
  id: row
  required property var scene
  required property string label
  required property var metric
  readonly property string deviceDescription: {
    const details = [label, metric.model || "Model unavailable"];
    if (typeof metric.display_connected === "boolean")
      details.push(metric.display_connected ? "Display connected" : "No display connected");
    if (metric.runtime_status) details.push("Power state: " + metric.runtime_status);
    return details.join(" · ");
  }
  height: 66
  DeviceIcon {
    scene: row.scene; y: deviceTitle.y + deviceTitle.capCenterY - height / 2
    cpu: row.label === "CPU"; description: row.deviceDescription
  }
  Label { id: deviceTitle; scene: row.scene; text: row.label; accessibleText: row.deviceDescription; x: 26; y: 16 - baselineOffset; size: 16; weight: Font.DemiBold; width: 56 }
  Label { scene: row.scene; y: 16 - baselineOffset; x: 96; width: parent.width - x; text: F.deviceName(row.metric.model); accessibleText: row.deviceDescription; align: Text.AlignRight; size: 12; weight: Font.Normal; muted: true }
  Repeater {
    model: [
      {value: F.number(row.metric.usage_percent), unit: "%", name: "utilization"},
      {value: F.number(row.metric.temperature_c), unit: "°C", name: "temperature"},
      {value: F.number(row.metric.power_w), unit: "W", name: "power"}
    ]
    Item {
      id: metricCell
      required property var modelData
      required property int index
      readonly property string description: row.label + " " + modelData.name + ": " + modelData.value + " " + modelData.unit
      x: index === 0 ? 26 : 114 + (index - 1) * (row.width - 114) / 2
      width: index === 0 ? 88 : (row.width - 114) / 2; height: 60
      Item {
        id: readout
        x: metricCell.index === 0 ? 0 : parent.width - width
        width: Math.min(value.implicitWidth + unit.implicitWidth + 3, parent.width)
        height: parent.height
        Label {
          id: value
          scene: row.scene; text: metricCell.modelData.value; accessibleText: metricCell.description
          y: 50 - baselineOffset; width: Math.max(0, parent.width - unit.implicitWidth - 3)
          size: metricCell.index === 0 ? 34 : metricCell.modelData.value.length > 3 ? 22 : 28; weight: Font.Medium
          align: metricCell.index === 0 ? Text.AlignLeft : Text.AlignRight
        }
        Label {
          id: unit
          scene: row.scene; text: metricCell.modelData.unit; accessibleText: metricCell.description
          anchors { left: value.right; leftMargin: 3 }
          y: 50 - baselineOffset
          size: 13; muted: true
        }
      }
    }
  }
  Rectangle {
    x: 26; y: 58; width: parent.width - x; height: 3; radius: 1.5
    color: row.scene.darkText ? "#33404e5e" : "#33d2e0e8"
    Accessible.ignored: true
    Rectangle {
      visible: typeof row.metric.usage_percent === "number" && isFinite(row.metric.usage_percent)
      width: parent.width * Math.max(0, Math.min(100, row.metric.usage_percent || 0)) / 100
      height: parent.height; radius: parent.radius; color: row.scene.darkText ? "#3e667e" : "#9acaf1"
      Behavior on width { NumberAnimation { duration: 220 } }
    }
  }
}
