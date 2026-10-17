import QtQuick

// Shared visual roles for every Quickshell config in this module.
QtObject {
    // Trial styles are selected through widget IPC and reset on process restart.
    property string glassStyle: "off"
    readonly property bool glassActive: glassStyle !== "off"
    readonly property bool curvedGlass: ["clear", "blurred", "rounded", "soft", "sculpted"].indexOf(glassStyle) !== -1
    // Rain Radar keeps its existing content treatment until its separate redesign.
    property bool legacyContent: false
    readonly property string labelFont: "Adwaita Sans"
    // Keep these logical radii matched to the corresponding compositor presets.
    readonly property real panelRadius: curvedGlass ? (["clear", "blurred", "rounded"].indexOf(glassStyle) !== -1 ? 44 : 22) : 0
    // Panel structure
    readonly property color panelBackground: glassActive
        ? (glassStyle === "liquid" || curvedGlass ? "#0c151a24"
           : glassStyle === "legacy-clear" ? "#18151a24" : "#30151a24")
        : "#c2181822"
    readonly property color panelEdgeLight: glassActive ? "#30f5f7ff" : "#8a717683"
    readonly property color panelEdgeDark: glassActive ? "#18000000" : "#8a30333d"
    readonly property color divider: legacyContent
        ? (curvedGlass ? "#8ceaf0fa" : "#665c606b") : "#38eaf0fa"
    readonly property color dividerShadow: "#80070a10"
    readonly property color usageTrack: "#20f5f7ff"
    readonly property color calendarTodayFill: "#edf3ff"
    readonly property color radarBackground: "#0b0d12"
    readonly property color radarTelemetryBackground: "#b30b0d12"
    readonly property color radarGrid: "#20f5f7ff"
    readonly property color radarRangeRing: "#42f5f7ff"

    // Text hierarchy
    readonly property color textPrimary: "#f5f7ff"
    readonly property color textSecondary: curvedGlass ? "#e8edf5" : "#c7cad5"
    readonly property color textMuted: curvedGlass ? (legacyContent ? "#dce3ed" : "#d2dce9")
        : glassActive ? "#c4cad6" : "#aeb3c2"
    readonly property color textDisabled: curvedGlass ? "#b5bfcc" : "#7f8492"
    readonly property color textTertiary: curvedGlass ? "#bbc5d3" : "#7f8492"
    readonly property color textShadow: "#99080b12"
    readonly property color radarUnavailableText: "#555862"

    // Shared module typography
    readonly property int moduleFooterLabelSize: 10
    readonly property int moduleFooterValueSize: 12
    readonly property int observationMetadataSize: 10
    readonly property int metricValueSize: 24
    readonly property int metricUnitSize: 13

    // Data state
    readonly property color statusOk: "#9ece6a"
    readonly property color statusCaution: "#e0af68"
    readonly property color statusError: "#f7768e"
    readonly property color statusUnknown: "#7f8492"

    // Resource identity
    readonly property color cpuAccent: "#7dcfff"
    readonly property color gpuAccent: "#c099ff"
    readonly property color ramAccent: "#9ece6a"
    readonly property color vramAccent: "#ff9e64"
    readonly property color storageAccent: "#e0af68"

    // Calendar meaning
    readonly property color calendarGridVertical: curvedGlass ? "#4adfe8f5" : "#20c7cad5"
    readonly property color calendarGridHorizontal: curvedGlass ? "#66e3ebf7" : "#32c7cad5"
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
