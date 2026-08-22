import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: shell

    property bool widgetsVisible: true
    readonly property string performanceScriptsDir:
        Quickshell.shellDir + "/scripts"
    readonly property string remoteConfigPath:
        Quickshell.shellDir + "/remote.json"
    readonly property string automationSettingsPath:
        Quickshell.shellDir + "/automation.json"
    readonly property string machineConfigPath:
        Quickshell.shellDir + "/machine.json"

    function updateMetrics(target, line) {
        try {
            const reading = JSON.parse(line);
            if (!reading.cpu || !reading.gpu || !reading.memory || !reading.vram)
                return;
            if (typeof reading.cpu.usage_percent !== "number"
                    || typeof reading.gpu.usage_percent !== "number"
                    || typeof reading.memory.usage_percent !== "number"
                    || typeof reading.vram.usage_percent !== "number")
                return;

            target.cpuUsage = reading.cpu.usage_percent;
            target.cpuModel = typeof reading.cpu.model === "string"
                ? reading.cpu.model : "";
            target.cpuTemperature = reading.cpu.temperature_c;
            target.cpuPower = reading.cpu.power_w;
            target.gpuUsage = reading.gpu.usage_percent;
            target.gpuModel = typeof reading.gpu.model === "string"
                ? reading.gpu.model : "";
            target.gpuTemperature = reading.gpu.temperature_c;
            target.gpuPower = reading.gpu.power_w;
            target.memoryUsed = reading.memory.used_bytes;
            target.memoryTotal = reading.memory.total_bytes;
            target.memoryUsage = reading.memory.usage_percent;
            target.vramUsed = reading.vram.used_bytes;
            target.vramTotal = reading.vram.total_bytes;
            target.vramUsage = reading.vram.usage_percent;
            target.storageAvailable = reading.storage !== null
                && typeof reading.storage === "object"
                && typeof reading.storage.used_bytes === "number"
                && typeof reading.storage.total_bytes === "number"
                && typeof reading.storage.usage_percent === "number";
            if (target.storageAvailable) {
                target.storageUsed = reading.storage.used_bytes;
                target.storageTotal = reading.storage.total_bytes;
                target.storageUsage = reading.storage.usage_percent;
            }
            target.networkAvailable = reading.network !== null
                && typeof reading.network === "object"
                && typeof reading.network.download_bytes_per_second === "number"
                && typeof reading.network.upload_bytes_per_second === "number";
            if (target.networkAvailable) {
                target.networkDownload = reading.network.download_bytes_per_second;
                target.networkUpload = reading.network.upload_bytes_per_second;
            }
            target.uptimeAvailable = typeof reading.uptime_seconds === "number";
            if (target.uptimeAvailable)
                target.uptimeSeconds = reading.uptime_seconds;
            target.lastUpdateMs = Date.now();
            target.available = true;
            target.fresh = true;
        } catch (error) {
            console.warn("Invalid system metrics:", error);
        }
    }

    function percent(value, available) {
        return available ? value.toFixed(0) + "%" : "--%";
    }

    function compactModelName(value) {
        if (typeof value !== "string")
            return "";

        return value
            .replace(/\(R\)|\(TM\)/gi, "")
            .replace(/^\d+(?:st|nd|rd|th) Gen\s+/i, "")
            .replace(/\s+@\s+\d+(?:\.\d+)?GHz$/i, "")
            .replace(/\s+\d+-Core Processor$/i, "")
            .replace(/\s+Processor$/i, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function temperature(value) {
        return typeof value === "number" ? value.toFixed(0) + "°C" : "--°C";
    }

    function power(value) {
        return typeof value === "number" ? value.toFixed(0) + " W" : "-- W";
    }

    function gibibytes(value) {
        return (value / 1073741824).toFixed(1);
    }

    function memoryAmount(used, total, available) {
        return available
            ? gibibytes(used) + " / " + gibibytes(total) + " GiB"
            : "-- / -- GiB";
    }

    function storageAmount(used, total, available) {
        return available
            ? gibibytes(used).replace(".0", "") + " / "
                + gibibytes(total).replace(".0", "") + " GiB"
            : "-- / -- GiB";
    }

    function byteRate(value, available) {
        if (!available)
            return "-- B/s";
        if (value >= 1073741824)
            return (value / 1073741824).toFixed(1) + " GiB/s";
        if (value >= 1048576)
            return (value / 1048576).toFixed(1) + " MiB/s";
        if (value >= 1024)
            return (value / 1024).toFixed(1) + " KiB/s";
        return value.toFixed(0) + " B/s";
    }

    function uptime(value, available) {
        if (!available)
            return "UP --";
        const hours = Math.floor(value / 3600);
        const days = Math.floor(hours / 24);
        const remainingHours = hours % 24;
        return days > 0
            ? "UP " + days + "d " + remainingHours + "h"
            : "UP " + hours + "h";
    }

    component MetricsData: QtObject {
        property bool available: false
        property bool fresh: false
        property double lastUpdateMs: 0
        property real cpuUsage: 0
        property string cpuModel: ""
        property var cpuTemperature: null
        property var cpuPower: null
        property real gpuUsage: 0
        property string gpuModel: ""
        property var gpuTemperature: null
        property var gpuPower: null
        property real memoryUsed: 0
        property real memoryTotal: 0
        property real memoryUsage: 0
        property real vramUsed: 0
        property real vramTotal: 0
        property real vramUsage: 0
        property bool storageAvailable: false
        property real storageUsed: 0
        property real storageTotal: 0
        property real storageUsage: 0
        property bool networkAvailable: false
        property real networkDownload: 0
        property real networkUpload: 0
        property bool uptimeAvailable: false
        property real uptimeSeconds: 0
    }

    MetricsData {
        id: localData
    }

    MetricsData {
        id: remoteData
    }

    IpcHandler {
        target: "widgets"

        property bool visible: shell.widgetsVisible

        function showWidgets(): void {
            shell.widgetsVisible = true;
        }

        function hideWidgets(): void {
            shell.widgetsVisible = false;
        }

        function toggle(): void {
            shell.widgetsVisible = !shell.widgetsVisible;
        }
    }

    component UsageBar: Rectangle {
        id: usageBar

        property real value: 0
        property color accent: "#7dcfff"
        readonly property int segmentCount: 20
        readonly property int segmentSpacing: 2

        implicitHeight: 7
        radius: 0
        color: "transparent"

        Row {
            anchors.fill: parent
            spacing: usageBar.segmentSpacing

            Repeater {
                model: usageBar.segmentCount

                delegate: Rectangle {
                    required property int index

                    width: (
                        usageBar.width
                        - (usageBar.segmentCount - 1) * usageBar.segmentSpacing
                    ) / usageBar.segmentCount
                    height: usageBar.height
                    color: "#30f5f7ff"

                    Rectangle {
                        width: parent.width * Math.min(1, Math.max(0,
                            (usageBar.value - index * 5) / 5
                        ))
                        height: parent.height
                        color: usageBar.accent
                    }
                }
            }
        }
    }

    component IconValue: Item {
        property string symbol: ""
        property string value: ""

        implicitWidth: valueRow.implicitWidth
        implicitHeight: valueRow.implicitHeight

        Row {
            id: valueRow
            anchors.centerIn: parent
            spacing: 5

            Text {
                text: symbol
                color: "#c7cad5"
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
            }

            Text {
                text: value
                color: "#f5f7ff"
                font.family: "Noto Sans JP"
                font.pixelSize: 16
            }
        }
    }

    component ComputeSection: Column {
        property bool available: false
        property string symbol: ""
        property string label: ""
        property string modelName: ""
        property real usage: 0
        property var temperatureValue: null
        property var powerValue: null
        property color accent: "#7dcfff"

        spacing: 4

        Item {
            width: parent.width
            height: 27

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Text {
                    text: symbol
                    color: accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 23
                }

                Text {
                    text: label
                    color: "#f5f7ff"
                    font.family: "Adwaita Sans"
                    font.pixelSize: 18
                    font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: shell.percent(usage, available)
                color: "#f5f7ff"
                font.family: "Adwaita Sans"
                font.pixelSize: 23
                font.weight: Font.Medium
            }
        }

        Text {
            width: parent.width
            text: modelName.length > 0
                ? shell.compactModelName(modelName)
                : "Model unavailable"
            color: "#f5f7ff"
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Row {
            width: parent.width

            IconValue {
                width: parent.width / 2
                symbol: "\uf076"
                value: shell.temperature(temperatureValue)
            }

            IconValue {
                width: parent.width / 2
                symbol: "\uea0b"
                value: shell.power(powerValue)
            }
        }

        UsageBar {
            width: parent.width
            value: parent.available ? parent.usage : 0
            accent: parent.accent
        }
    }

    component MemorySection: Column {
        property bool available: false
        property string symbol: ""
        property string label: ""
        property real used: 0
        property real total: 0
        property real usage: 0
        property color accent: "#9ece6a"

        spacing: 4

        Item {
            width: parent.width
            height: 25

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Text {
                    text: symbol
                    color: accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 22
                }

                Text {
                    text: label
                    color: "#f5f7ff"
                    font.family: "Adwaita Sans"
                    font.pixelSize: 17
                    font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: shell.memoryAmount(used, total, available) + "  "
                    + shell.percent(usage, available)
                color: "#f5f7ff"
                font.family: "Adwaita Sans"
                font.pixelSize: 14
            }
        }

        UsageBar {
            width: parent.width
            value: parent.available ? parent.usage : 0
            accent: parent.accent
        }
    }

    component FreshnessStatus: Row {
        property MetricsData metrics

        spacing: 7

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 11
            height: 11
            radius: 0
            color: metrics.fresh ? "#9ece6a" : "#f7768e"
        }

        Text {
            text: metrics.fresh ? "LIVE" : "NO SIGNAL"
            color: metrics.fresh ? "#b9d99d" : "#efa0ad"
            font.family: "Adwaita Sans"
            font.pixelSize: 12
            font.weight: Font.Medium
            font.letterSpacing: 0.7
        }
    }

    component PerformanceCard: Rectangle {
        id: performanceCard

        property string deviceName: ""
        property string platform: ""
        property MetricsData metrics
        property Component statusComponent: null
        property bool zeroValuesWhenStale: false
        readonly property bool showingZeroValues:
            zeroValuesWhenStale && !metrics.fresh
        readonly property bool valuesAvailable:
            metrics.available || showingZeroValues

        function displayedValue(value) {
            return showingZeroValues ? 0 : value;
        }

        implicitWidth: 312
        implicitHeight: cardContent.implicitHeight + 28
        radius: 0
        color: "#b5181822"
        border.width: 1
        border.color: "#805c606b"

        Column {
            id: cardContent
            anchors.centerIn: parent
            width: 280
            spacing: 11

            Item {
                width: parent.width
                height: 37

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: deviceName
                        color: "#f5f7ff"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 19
                        font.weight: Font.Medium
                    }

                    Text {
                        text: platform
                        color: "#f5f7ff"
                        font.family: "Adwaita Sans"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.letterSpacing: 0.8
                    }
                }

                Loader {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: performanceCard.statusComponent
                }
            }

            ComputeSection {
                width: parent.width
                available: performanceCard.valuesAvailable
                symbol: "\ue322"
                label: "CPU"
                modelName: metrics.cpuModel
                usage: performanceCard.displayedValue(metrics.cpuUsage)
                temperatureValue: performanceCard.displayedValue(
                    metrics.cpuTemperature
                )
                powerValue: performanceCard.displayedValue(metrics.cpuPower)
                accent: "#7dcfff"
            }

            ComputeSection {
                width: parent.width
                available: performanceCard.valuesAvailable
                symbol: "\ue30d"
                label: "GPU"
                modelName: metrics.gpuModel
                usage: performanceCard.displayedValue(metrics.gpuUsage)
                temperatureValue: performanceCard.displayedValue(
                    metrics.gpuTemperature
                )
                powerValue: performanceCard.displayedValue(metrics.gpuPower)
                accent: "#c099ff"
            }

            MemorySection {
                width: parent.width
                available: performanceCard.valuesAvailable
                symbol: "\uf7a3"
                label: "RAM"
                used: performanceCard.displayedValue(metrics.memoryUsed)
                total: performanceCard.displayedValue(metrics.memoryTotal)
                usage: performanceCard.displayedValue(metrics.memoryUsage)
                accent: "#9ece6a"
            }

            MemorySection {
                width: parent.width
                available: performanceCard.valuesAvailable
                symbol: "\ue875"
                label: "VRAM"
                used: performanceCard.displayedValue(metrics.vramUsed)
                total: performanceCard.displayedValue(metrics.vramTotal)
                usage: performanceCard.displayedValue(metrics.vramUsage)
                accent: "#ff9e64"
            }
        }
    }

    component SystemSummarySection: Column {
        property MetricsData metrics
        property string title: "SYSTEM"
        property string platform: ""

        spacing: 7

        Item {
            width: parent.width
            height: 33

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: title
                    color: "#f5f7ff"
                    font.family: "Adwaita Sans"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.letterSpacing: 0.9
                }

                Text {
                    text: platform
                    color: "#f5f7ff"
                    font.family: "Adwaita Sans"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: 0.8
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: shell.uptime(metrics.uptimeSeconds, metrics.uptimeAvailable)
                color: "#c7cad5"
                font.family: "Adwaita Sans"
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 0.6
            }
        }

        Item {
            width: parent.width
            height: 25

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Text {
                    text: "\ue1db"
                    color: "#e0af68"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 21
                }

                Text {
                    text: "ROOT"
                    color: "#f5f7ff"
                    font.family: "Adwaita Sans"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: shell.storageAmount(
                    metrics.storageUsed,
                    metrics.storageTotal,
                    metrics.storageAvailable
                ) + "  " + shell.percent(
                    metrics.storageUsage,
                    metrics.storageAvailable
                )
                color: "#f5f7ff"
                font.family: "Adwaita Sans"
                font.pixelSize: 13
            }
        }

        UsageBar {
            width: parent.width
            value: metrics.storageAvailable ? metrics.storageUsage : 0
            accent: "#e0af68"
        }

        Item {
            width: parent.width
            height: 25

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "NETWORK"
                color: "#c7cad5"
                font.family: "Adwaita Sans"
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 0.7
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "↓ " + shell.byteRate(
                    metrics.networkDownload,
                    metrics.networkAvailable
                ) + "    ↑ " + shell.byteRate(
                    metrics.networkUpload,
                    metrics.networkAvailable
                )
                color: "#f5f7ff"
                font.family: "Adwaita Sans"
                font.pixelSize: 13
            }
        }
    }

    component LocalSystemCard: Rectangle {
        id: localSystemCard

        property MetricsData metrics

        implicitWidth: 312
        implicitHeight: localSystemContent.implicitHeight + 28
        radius: 0
        color: "#b5181822"
        border.width: 1
        border.color: "#805c606b"

        Column {
            id: localSystemContent

            anchors.centerIn: parent
            width: 280
            spacing: 11

            SystemSummarySection {
                width: parent.width
                metrics: localSystemCard.metrics
                title: "LOCAL SYSTEM"
                platform: "LINUX · ARCH"
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#805c606b"
            }

            ComputeSection {
                width: parent.width
                available: localSystemCard.metrics.available
                symbol: "\ue322"
                label: "CPU"
                modelName: localSystemCard.metrics.cpuModel
                usage: localSystemCard.metrics.cpuUsage
                temperatureValue: localSystemCard.metrics.cpuTemperature
                powerValue: localSystemCard.metrics.cpuPower
                accent: "#7dcfff"
            }

            ComputeSection {
                width: parent.width
                available: localSystemCard.metrics.available
                symbol: "\ue30d"
                label: "GPU"
                modelName: localSystemCard.metrics.gpuModel
                usage: localSystemCard.metrics.gpuUsage
                temperatureValue: localSystemCard.metrics.gpuTemperature
                powerValue: localSystemCard.metrics.gpuPower
                accent: "#c099ff"
            }

            MemorySection {
                width: parent.width
                available: localSystemCard.metrics.available
                symbol: "\uf7a3"
                label: "RAM"
                used: localSystemCard.metrics.memoryUsed
                total: localSystemCard.metrics.memoryTotal
                usage: localSystemCard.metrics.memoryUsage
                accent: "#9ece6a"
            }

            MemorySection {
                width: parent.width
                available: localSystemCard.metrics.available
                symbol: "\ue875"
                label: "VRAM"
                used: localSystemCard.metrics.vramUsed
                total: localSystemCard.metrics.vramTotal
                usage: localSystemCard.metrics.vramUsage
                accent: "#ff9e64"
            }
        }
    }

    PanelWindow {
        visible: shell.widgetsVisible

        anchors {
            top: true
            bottom: true
            left: true
        }

        margins {
            top: 12
            bottom: 12
            left: 12
        }

        implicitWidth: cards.implicitWidth
        color: "transparent"
        exclusiveZone: 0
        focusable: false

        Column {
            id: cards

            readonly property real cardSpacing: Math.max(0,
                height
                - localSystem.implicitHeight
                - mainPerformance.implicitHeight
            )

            anchors.fill: parent
            spacing: 0

            LocalSystemCard {
                id: localSystem
                metrics: localData
            }

            Item {
                width: parent.width
                height: cards.cardSpacing
            }

            PerformanceCard {
                id: mainPerformance
                deviceName: "Main PC"
                platform: "WINDOWS"
                metrics: remoteData
                zeroValuesWhenStale: true
                statusComponent: Component {
                    FreshnessStatus {
                        metrics: remoteData
                    }
                }
            }
        }
    }

    Process {
        command: [
            "/usr/bin/python3",
            "-B",
            shell.performanceScriptsDir + "/system_metrics.py",
            "--interval",
            "2"
        ]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateMetrics(localData, line)
        }
    }

    // The heartbeat drives automation and resumes its state across config reloads.
    Process {
        command: [
            "/usr/bin/python3",
            "-B",
            shell.performanceScriptsDir + "/remote_metrics.py",
            "--config",
            shell.remoteConfigPath,
            "--interval",
            "2",
            "--automation",
            "--automation-settings",
            shell.automationSettingsPath,
            "--machine-config",
            shell.machineConfigPath
        ]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateMetrics(remoteData, line)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (localData.available && Date.now() - localData.lastUpdateMs > 6000)
                localData.fresh = false;
            if (remoteData.available && Date.now() - remoteData.lastUpdateMs > 6000)
                remoteData.fresh = false;
        }
    }
}
