pragma ComponentBehavior: Bound
import QtQuick
import "Format.js" as F
import "Layout.js" as Layout

Item {
  id: weather
  required property var scene
  readonly property var indoor: scene.readings.indoor || {}
  readonly property var outdoor: scene.readings.outdoor || {}
  readonly property bool indoorCurrent: ["Live", "Demo", "Snapshot"].includes(indoor._status)
  readonly property bool indoorStatusVisible: indoor._status !== "Live"
  readonly property bool outdoorStatusVisible: outdoor._status !== "Live" || !outdoor.observed_at
  readonly property int forecastY: Layout.weatherHeight(scene.readings) - 110
  readonly property bool darkInk: scene.darkText
  readonly property string conditionSymbol: F.symbol(outdoor.state)
  implicitHeight: forecastY + 110
  Label {
    id: currentCondition
    scene: weather.scene; width: 30; size: 30
    y: conditionTitle.y + conditionTitle.capCenterY - inkCenterY
    visible: !!weather.outdoor.condition && weather.conditionSymbol !== "—"
    text: weather.conditionSymbol; family: "Material Symbols Rounded"
    ink: F.weatherInk(weather.outdoor.state, weather.darkInk)
    accessibleText: conditionTitle.accessibleText
  }
  Label {
    id: conditionTitle
    scene: weather.scene; x: currentCondition.visible ? 42 : 0; y: weather.forecastY - 40
    width: Math.min(implicitWidth, parent.width - x - (observationTime.visible ? observationIcon.width + 4 + observationTime.width + 12 : 0))
    text: weather.outdoor.condition || "Weather"; size: weather.outdoor.condition ? 26 : 21; weight: Font.DemiBold
    accessibleText: weather.outdoor.condition ? "Outdoor weather: " + weather.outdoor.condition : "Current outdoor condition unavailable"
  }
  Label {
    id: observationIcon
    scene: weather.scene; visible: observationTime.visible
    x: conditionTitle.x + conditionTitle.width + 12; width: 14; size: 14; muted: true
    y: observationTime.y + observationTime.capCenterY - inkCenterY
    family: "Material Symbols Rounded"; text: "\ue8b5"
    accessibleText: observationTime.accessibleText
  }
  Label {
    id: observationTime
    scene: weather.scene; visible: !weather.outdoorStatusVisible
    x: observationIcon.x + observationIcon.width + 4; width: Math.min(implicitWidth, 42)
    anchors.baseline: conditionTitle.baseline
    text: weather.outdoor.observed_at || ""; size: 12; muted: true
    accessibleText: "Outdoor observation at " + text + " · Weathernews"
  }
  Row {
    width: parent.width; spacing: 16
    Repeater {
      model: [weather.indoor, weather.outdoor]
      Item {
        id: environmentCell
        required property var modelData
        required property int index
        width: (weather.width - 16) / 2; height: weather.forecastY - 50
        readonly property var visibleValue: environmentCell.index === 0 && !weather.indoorCurrent ? {} : modelData
        Label {
          id: environmentTitle
          scene: weather.scene
          text: environmentCell.index === 0 ? "Indoor" : "Outdoor"
          size: 14; weight: Font.Medium
        }
        Label { scene: weather.scene; y: 22; text: F.number(parent.visibleValue.temperature, 1) + "°"; size: 38; tracking: -1; weight: Font.Normal; width: parent.width - 8 }
        Label {
          scene: weather.scene; y: humidity.y + humidity.capCenterY - inkCenterY; width: 18; size: 18; family: "Material Symbols Rounded"; text: "\ue798"
          ink: weather.darkInk ? "#245f9e" : "#a9cdff"
          accessibleText: "Relative humidity: " + F.number(environmentCell.visibleValue.humidity) + "%"
        }
        Label {
          id: humidity
          scene: weather.scene; x: 24; y: 70; size: 15
          width: parent.width - 32
          text: F.number(environmentCell.visibleValue.humidity) + "%"
          accessibleText: "Relative humidity: " + text
        }
        Label {
          scene: weather.scene; y: 94; size: 12; muted: true; width: parent.width - 8
          visible: environmentCell.index === 0 ? weather.indoorStatusVisible : weather.outdoorStatusVisible
          text: F.observation(environmentCell.modelData, environmentCell.index === 0)
        }
      }
    }
  }
  Label { scene: weather.scene; anchors { left: forecastTitle.right; leftMargin: 12; baseline: forecastTitle.baseline } width: parent.width - x; text: "Weathernews"; accessibleText: "Weathernews · current conditions and hourly forecast"; size: 12; muted: true; align: Text.AlignRight }
  Label { id: forecastTitle; scene: weather.scene; y: weather.forecastY; text: "Next five hours"; size: 14; weight: Font.DemiBold }
  Row {
    y: weather.forecastY + 24; width: parent.width
    Repeater {
      model: weather.outdoor.hourly_forecast || []
      Item {
        id: forecastCell
        required property var modelData
        readonly property string conditionSymbol: F.symbol(modelData.state)
        width: weather.width / 5; height: 79
        Label { scene: weather.scene; text: forecastCell.modelData.hour; size: 12; width: parent.width; align: Text.AlignHCenter }
        Label {
          scene: weather.scene; y: 20; text: forecastCell.conditionSymbol; family: forecastCell.conditionSymbol === "—" ? "Adwaita Sans" : "Material Symbols Rounded"; size: 22; width: parent.width; align: Text.AlignHCenter
          ink: F.weatherInk(forecastCell.modelData.state, weather.darkInk)
          accessibleText: forecastCell.modelData.hour + ": " + F.weatherDescription(forecastCell.modelData.state)
        }
        Label { scene: weather.scene; y: 46; text: F.number(forecastCell.modelData.temperature) + "°"; size: 18; weight: Font.Medium; width: parent.width; align: Text.AlignHCenter }
        Label { scene: weather.scene; y: 68; text: F.number(forecastCell.modelData.precipitation, 1) + " mm"; accessibleText: "Precipitation: " + text; size: 12; width: parent.width; align: Text.AlignHCenter; muted: true }
      }
    }
  }
  Label { scene: weather.scene; y: weather.forecastY + 40; width: parent.width; text: "Forecast unavailable"; size: 13; visible: !(weather.outdoor.hourly_forecast || []).length }
}
