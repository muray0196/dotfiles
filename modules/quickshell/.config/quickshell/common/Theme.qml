import QtQuick

// Shared visual roles for every Quickshell config in this module.
QtObject {
    // Panel structure
    readonly property color panelBackground: "#c2181822"
    readonly property color panelEdgeLight: "#8a717683"
    readonly property color panelEdgeDark: "#8a30333d"
    readonly property color divider: "#665c606b"
    readonly property color usageTrack: "#30f5f7ff"
    readonly property color calendarTodayFill: "#55f5f7ff"
    readonly property color radarBackground: "#0b0d12"
    readonly property color radarTelemetryBackground: "#b30b0d12"
    readonly property color radarGrid: "#20f5f7ff"
    readonly property color radarRangeRing: "#42f5f7ff"
    readonly property color radarMarkerHalo: "#e6ffffff"
    readonly property color radarMarkerCore: "#e85d75"

    // Text hierarchy
    readonly property color textPrimary: "#f5f7ff"
    readonly property color textSecondary: "#c7cad5"
    readonly property color textMuted: "#aeb3c2"
    readonly property string textDimHex: "#8b8e99"
    readonly property color textDim: textDimHex
    readonly property color textDisabled: "#7f8492"
    readonly property color textTertiary: "#7f8492"
    readonly property color radarUnavailableText: "#555862"
    readonly property color radarPlaceText: "#d8dbe5"

    // Shared module typography
    readonly property int moduleFooterLabelSize: 10
    readonly property int moduleFooterValueSize: 12
    readonly property int observationMetadataSize: 10
    readonly property int metricValueSize: 25
    readonly property int metricUnitSize: 16

    // Data state
    readonly property color statusOk: "#9ece6a"
    readonly property color statusCaution: "#e0af68"
    readonly property color statusError: "#f7768e"
    readonly property color statusUnknown: "#7f8492"
    readonly property color statusOkText: "#b9d99d"
    readonly property color statusErrorText: "#efa0ad"

    // Resource identity
    readonly property color cpuAccent: "#7dcfff"
    readonly property color gpuAccent: "#c099ff"
    readonly property color ramAccent: "#9ece6a"
    readonly property color vramAccent: "#ff9e64"
    readonly property color storageAccent: "#e0af68"

    // Calendar meaning
    readonly property color calendarGridVertical: "#20c7cad5"
    readonly property color calendarGridHorizontal: "#32c7cad5"
    readonly property color calendarSundayHoliday: "#efa0ad"
    readonly property color calendarSaturday: "#9bd7ff"

    // Weather condition meaning
    readonly property color weatherThunder: "#ffd166"
    readonly property color weatherSunny: "#ffd166"
    readonly property color weatherSnow: "#dff6ff"
    readonly property color weatherSleet: "#b9e8ff"
    readonly property color weatherLightRain: "#9bd7ff"
    readonly property color weatherRain: "#78c8ff"
    readonly property color weatherFog: "#d4d8e3"
    readonly property color weatherExtremeHeat: "#ff9f43"
    readonly property color weatherCloudy: "#d9dde8"
    readonly property color weatherUnknown: "#f5f7ff"

    // Precipitation intensity
    readonly property color precipitationTrace: "#f5f7ff"
    readonly property color precipitationLight: "#a0d2ff"
    readonly property color precipitationModerate: "#4d9cff"
    readonly property color precipitationHeavy: "#718cff"
    readonly property color precipitationVeryHeavy: "#e8df45"
    readonly property color precipitationIntense: "#ff9e3d"
    readonly property color precipitationSevere: "#ff5c4a"
    readonly property color precipitationExtreme: "#e65aa5"
}
