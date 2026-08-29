import Quickshell
import Quickshell.Io
import QtQuick
import "common" as UI

Scope {
    id: shell

    UI.Theme {
        id: theme
    }

    property bool widgetsVisible: true
    readonly property string performanceScriptsDir:
        Quickshell.shellDir + "/scripts"
    readonly property string remoteConfigPath:
        Quickshell.shellDir + "/remote.json"
    readonly property string automationSettingsPath:
        Quickshell.shellDir + "/automation.json"
    readonly property string machineConfigPath:
        Quickshell.shellDir + "/machine.json"
    readonly property int panelWidth: 312
    readonly property int panelContentWidth: 280
    readonly property int moduleDividerHeight: 7
    readonly property int panelInset: 10
    readonly property int pollIntervalSeconds: 2
    readonly property int historySampleIntervalMs:
        pollIntervalSeconds * 1000
    readonly property int historySampleCapacity:
        600000 / historySampleIntervalMs
    readonly property int performancePanelGap: 10
    readonly property int freshnessCautionMs: 6000
    readonly property int freshnessErrorMs: 30000
    readonly property string smallLabelFont: "Adwaita Mono"
    readonly property string numericFont: "Adwaita Sans"
    property double nowMs: Date.now()

    function updateMetrics(target, line) {
        try {
            const reading = JSON.parse(line);
            if (!reading || typeof reading !== "object")
                return;
            if (reading.schema_version !== 2
                    || !Array.isArray(reading.gpus)
                    || reading.cpu === null
                    || typeof reading.cpu !== "object"
                    || reading.memory === null
                    || typeof reading.memory !== "object")
                return;

            const receivedAt = Date.now();
            const cpu = reading.cpu;
            const memory = reading.memory;

            target.host = typeof reading.host === "string"
                ? reading.host : "";

            target.cpuAvailable = typeof cpu.usage_percent === "number";
            if (target.cpuAvailable)
                target.cpuUsage = cpu.usage_percent;
            if (typeof cpu.model === "string")
                target.cpuModel = cpu.model;
            target.cpuTemperature = typeof cpu.temperature_c === "number"
                ? cpu.temperature_c : null;
            target.cpuPower = typeof cpu.power_w === "number"
                ? cpu.power_w : null;

            target.memoryAvailable =
                typeof memory.used_bytes === "number"
                && typeof memory.total_bytes === "number"
                && typeof memory.usage_percent === "number";
            if (target.memoryAvailable) {
                target.memoryUsed = memory.used_bytes;
                target.memoryTotal = memory.total_bytes;
                target.memoryUsage = memory.usage_percent;
            }

            const gpuEntries = [];
            const sourceGpus = reading.gpus;
            for (let index = 0; index < sourceGpus.length; index++) {
                const sourceGpu = sourceGpus[index];
                if (!sourceGpu || typeof sourceGpu !== "object")
                    continue;
                const gpuVram = sourceGpu.vram
                        && typeof sourceGpu.vram === "object"
                    ? sourceGpu.vram : {};
                const gpuAvailable =
                    typeof sourceGpu.usage_percent === "number";
                const gpuVramAvailable =
                    typeof gpuVram.used_bytes === "number"
                    && typeof gpuVram.total_bytes === "number"
                    && typeof gpuVram.usage_percent === "number";
                gpuEntries.push({
                    displayConnected:
                        sourceGpu.display_connected === true,
                    model: typeof sourceGpu.model === "string"
                        ? sourceGpu.model : "",
                    runtimeStatus:
                        typeof sourceGpu.runtime_status === "string"
                        ? sourceGpu.runtime_status : "",
                    available: gpuAvailable,
                    usage: gpuAvailable ? sourceGpu.usage_percent : 0,
                    temperature:
                        typeof sourceGpu.temperature_c === "number"
                        ? sourceGpu.temperature_c : null,
                    hotspotTemperature:
                        typeof sourceGpu.hotspot_temperature_c === "number"
                        ? sourceGpu.hotspot_temperature_c : null,
                    power: typeof sourceGpu.power_w === "number"
                        ? sourceGpu.power_w : null,
                    vram: {
                        available: gpuVramAvailable,
                        used: gpuVramAvailable ? gpuVram.used_bytes : 0,
                        total: gpuVramAvailable ? gpuVram.total_bytes : 0,
                        usage: gpuVramAvailable
                            ? gpuVram.usage_percent : 0
                    }
                });
            }
            target.gpus = gpuEntries;
            const primaryGpu = gpuEntries.length > 0
                ? gpuEntries[0] : null;
            target.gpuAvailable = primaryGpu !== null
                && primaryGpu.available;
            target.gpuUsage = target.gpuAvailable ? primaryGpu.usage : 0;
            target.gpuModel = primaryGpu !== null ? primaryGpu.model : "";
            target.gpuTemperature = primaryGpu !== null
                ? primaryGpu.temperature : null;
            target.gpuPower = primaryGpu !== null
                ? primaryGpu.power : null;

            const primaryVram = primaryGpu !== null
                ? primaryGpu.vram : null;
            target.vramAvailable = primaryVram !== null
                && primaryVram.available;
            target.vramUsed = target.vramAvailable ? primaryVram.used : 0;
            target.vramTotal = target.vramAvailable ? primaryVram.total : 0;
            target.vramUsage = target.vramAvailable ? primaryVram.usage : 0;

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

            const storageEntries = [];
            if (Array.isArray(reading.storage_volumes)) {
                for (let index = 0;
                        index < reading.storage_volumes.length;
                        index++) {
                    const volume = reading.storage_volumes[index];
                    if (!volume || typeof volume !== "object"
                            || typeof volume.label !== "string")
                        continue;
                    const volumeAvailable = volume.available === true
                        && typeof volume.used_bytes === "number"
                        && typeof volume.total_bytes === "number"
                        && typeof volume.usage_percent === "number";
                    storageEntries.push({
                        label: volume.label,
                        kind: typeof volume.kind === "string"
                            ? volume.kind : "",
                        available: volumeAvailable,
                        used: volumeAvailable ? volume.used_bytes : 0,
                        total: volumeAvailable ? volume.total_bytes : 0,
                        usage: volumeAvailable
                            ? volume.usage_percent : 0
                    });
                }
            }
            target.storageVolumes = storageEntries;

            target.networkAvailable = reading.network !== null
                && typeof reading.network === "object"
                && typeof reading.network
                    .download_bytes_per_second === "number"
                && typeof reading.network
                    .upload_bytes_per_second === "number";
            if (target.networkAvailable) {
                target.networkInterface =
                    typeof reading.network.interface === "string"
                    ? reading.network.interface : "";
                target.networkDownload =
                    reading.network.download_bytes_per_second;
                target.networkUpload =
                    reading.network.upload_bytes_per_second;
            } else {
                target.networkInterface = "";
            }

            target.uptimeAvailable =
                typeof reading.uptime_seconds === "number";
            if (target.uptimeAvailable)
                target.uptimeSeconds = reading.uptime_seconds;

            target.partial = !target.cpuAvailable
                || !target.gpuAvailable
                || !target.memoryAvailable
                || !target.vramAvailable
                || target.cpuTemperature === null
                || target.cpuPower === null
                || target.gpuTemperature === null
                || target.gpuPower === null
                || (target.expectsSystemDetails
                    && (!target.storageAvailable
                        || !target.networkAvailable
                        || target.networkInterface === ""
                        || !target.uptimeAvailable
                        || gpuEntries.length === 0));
            target.unavailable = !target.cpuAvailable
                && !target.gpuAvailable
                && !target.memoryAvailable
                && !target.vramAvailable;
            target.lastUpdateMs = receivedAt;
            target.available = true;
            // Keep the current reading inside the advertised peak window.
            historyStore.capture(localData, remoteData, receivedAt);
        } catch (error) {
            console.warn("Invalid system metrics:", error);
        }
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

    function localGpuDetail(gpu) {
        if (!gpu || typeof gpu !== "object")
            return "SENSOR --";
        const fields = [];
        if (gpu.displayConnected === true)
            fields.push("DISPLAY");
        if (typeof gpu.runtimeStatus === "string"
                && gpu.runtimeStatus !== ""
                && gpu.runtimeStatus.toLowerCase() !== "active")
            fields.push(gpu.runtimeStatus.toUpperCase());
        if (typeof gpu.model === "string" && gpu.model !== "")
            fields.push(compactModelName(gpu.model));
        return fields.length > 0 ? fields.join(" · ") : "MODEL --";
    }

    function percentageValue(value, available) {
        return available && typeof value === "number"
            ? value.toFixed(0) : "--";
    }

    function metricValue(value) {
        return typeof value === "number"
            ? value.toFixed(0) : "--";
    }

    function gibibytes(value) {
        return (value / 1073741824).toFixed(1);
    }

    function capacitySummary(used, total, available) {
        return available
            ? gibibytes(used) + " / " + gibibytes(total) + " GiB"
            : "-- / -- GiB";
    }

    function byteRateValue(value, available) {
        if (!available || typeof value !== "number")
            return "--";
        if (value >= 1073741824)
            return (value / 1073741824).toFixed(1);
        if (value >= 1048576)
            return (value / 1048576).toFixed(1);
        if (value >= 1024)
            return (value / 1024).toFixed(1);
        return value.toFixed(0);
    }

    function byteRateUnit(value, available) {
        if (!available || typeof value !== "number")
            return "B/s";
        if (value >= 1073741824)
            return "GiB/s";
        if (value >= 1048576)
            return "MiB/s";
        if (value >= 1024)
            return "KiB/s";
        return "B/s";
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

    function sampleAgeMs(metrics) {
        return metrics.available
            ? Math.max(0, nowMs - metrics.lastUpdateMs) : -1;
    }

    function moduleHealth(metrics, staleIsUnknown) {
        if (!metrics.available)
            return 0;
        const age = sampleAgeMs(metrics);
        if (metrics.unavailable)
            return 3;
        if (staleIsUnknown && age > freshnessCautionMs)
            return 0;
        if (age > freshnessErrorMs)
            return 3;
        if (age > freshnessCautionMs || metrics.partial)
            return 2;
        return 1;
    }

    function healthTone(health) {
        switch (health) {
        case 1:
            return theme.statusOk;
        case 2:
            return theme.statusCaution;
        case 3:
            return theme.statusError;
        default:
            return theme.statusUnknown;
        }
    }

    function moduleTone(metrics, staleIsUnknown) {
        return healthTone(moduleHealth(metrics, staleIsUnknown));
    }

    function combinedModuleTone(firstMetrics, secondMetrics) {
        const first = moduleHealth(firstMetrics, false);
        const second = moduleHealth(secondMetrics, true);
        if (first === 0 && second === 0)
            return theme.statusUnknown;
        if (first === 1 && second === 1)
            return theme.statusOk;
        const firstUsable = first === 1 || first === 2;
        const secondUsable = second === 1 || second === 2;
        if (!firstUsable && !secondUsable)
            return theme.statusError;
        return theme.statusCaution;
    }

    component MetricsData: QtObject {
        property bool expectsSystemDetails: false
        property bool available: false
        property bool partial: false
        property bool unavailable: false
        property double lastUpdateMs: 0
        property string host: ""
        property bool cpuAvailable: false
        property real cpuUsage: 0
        property string cpuModel: ""
        property var cpuTemperature: null
        property var cpuPower: null
        property bool gpuAvailable: false
        property real gpuUsage: 0
        property string gpuModel: ""
        property var gpuTemperature: null
        property var gpuPower: null
        property bool memoryAvailable: false
        property real memoryUsed: 0
        property real memoryTotal: 0
        property real memoryUsage: 0
        property bool vramAvailable: false
        property real vramUsed: 0
        property real vramTotal: 0
        property real vramUsage: 0
        property var gpus: []
        property bool storageAvailable: false
        property real storageUsed: 0
        property real storageTotal: 0
        property real storageUsage: 0
        property var storageVolumes: []
        property bool networkAvailable: false
        property string networkInterface: ""
        property real networkDownload: 0
        property real networkUpload: 0
        property bool uptimeAvailable: false
        property real uptimeSeconds: 0
    }

    component HistoryStore: QtObject {
        property var localCpuTemperature: []
        property var localGpu1Temperature: []
        property var localGpu1Hotspot: []
        property var localGpu2Temperature: []
        property var localGpu2Hotspot: []
        property var localComputePower: []
        property var mainCpuTemperature: []
        property var mainGpuTemperature: []
        property var mainComputePower: []
        property double lastSampleBucket: -1

        function sourceFresh(metrics, sampledAt) {
            if (!metrics || !metrics.available
                    || metrics.lastUpdateMs <= 0)
                return false;
            return Math.max(0, sampledAt - metrics.lastUpdateMs)
                <= shell.freshnessCautionMs;
        }

        function sensorValue(value, fresh) {
            return fresh && typeof value === "number" && isFinite(value)
                ? value : null;
        }

        function gpuSensorValue(metrics, index, field, fresh) {
            if (!fresh || !metrics || !Array.isArray(metrics.gpus)
                    || index < 0 || index >= metrics.gpus.length)
                return null;
            const gpu = metrics.gpus[index];
            const value = gpu ? gpu[field] : null;
            return typeof value === "number" && isFinite(value)
                ? value : null;
        }

        function localComputePowerValue(metrics, fresh) {
            if (!metrics)
                return null;
            const cpu = sensorValue(metrics.cpuPower, fresh);
            const gpu1 = gpuSensorValue(metrics, 0, "power", fresh);
            const gpu2 = gpuSensorValue(metrics, 1, "power", fresh);
            if (cpu === null || gpu1 === null || gpu2 === null
                    || cpu < 0 || gpu1 < 0 || gpu2 < 0)
                return null;
            return cpu + gpu1 + gpu2;
        }

        function mainComputePowerValue(metrics, fresh) {
            if (!metrics)
                return null;
            const cpu = sensorValue(metrics.cpuPower, fresh);
            const gpu = sensorValue(metrics.gpuPower, fresh);
            if (cpu === null || gpu === null || cpu < 0 || gpu < 0)
                return null;
            return cpu + gpu;
        }

        function appendTimedSample(samples, value, missingSamples) {
            const capacity = Math.max(1, shell.historySampleCapacity);
            const incoming = Math.min(capacity,
                Math.max(0, missingSamples) + 1);
            const keep = Math.max(0, capacity - incoming);
            const start = Math.max(0, samples.length - keep);
            const next = samples.slice(start);

            for (let index = 1; index < incoming; index++)
                next.push(null);
            next.push(value);
            return next;
        }

        function recordSample(samples, value, bucketAdvance) {
            if (bucketAdvance > 0)
                return appendTimedSample(samples, value,
                    bucketAdvance - 1);

            const next = samples.slice();
            if (next.length === 0)
                next.push(value);
            else
                next[next.length - 1] = value;
            return next;
        }

        function capture(localMetrics, mainMetrics, sampledAt) {
            const localFresh = sourceFresh(localMetrics, sampledAt);
            const mainFresh = sourceFresh(mainMetrics, sampledAt);
            const bucket = Math.floor(
                sampledAt / shell.historySampleIntervalMs);
            let bucketAdvance = lastSampleBucket < 0
                ? 1 : bucket - lastSampleBucket;

            // A backward wall-clock adjustment starts a new honest timeline.
            if (bucketAdvance < 0) {
                localCpuTemperature = [];
                localGpu1Temperature = [];
                localGpu1Hotspot = [];
                localGpu2Temperature = [];
                localGpu2Hotspot = [];
                localComputePower = [];
                mainCpuTemperature = [];
                mainGpuTemperature = [];
                mainComputePower = [];
                bucketAdvance = 1;
            }

            localCpuTemperature = recordSample(
                localCpuTemperature,
                sensorValue(localMetrics.cpuTemperature, localFresh),
                bucketAdvance
            );
            localGpu1Temperature = recordSample(
                localGpu1Temperature,
                gpuSensorValue(localMetrics, 0, "temperature", localFresh),
                bucketAdvance
            );
            localGpu1Hotspot = recordSample(
                localGpu1Hotspot,
                gpuSensorValue(
                    localMetrics, 0, "hotspotTemperature", localFresh),
                bucketAdvance
            );
            localGpu2Temperature = recordSample(
                localGpu2Temperature,
                gpuSensorValue(localMetrics, 1, "temperature", localFresh),
                bucketAdvance
            );
            localGpu2Hotspot = recordSample(
                localGpu2Hotspot,
                gpuSensorValue(
                    localMetrics, 1, "hotspotTemperature", localFresh),
                bucketAdvance
            );
            localComputePower = recordSample(
                localComputePower,
                localComputePowerValue(localMetrics, localFresh),
                bucketAdvance
            );
            mainCpuTemperature = recordSample(
                mainCpuTemperature,
                sensorValue(mainMetrics.cpuTemperature, mainFresh),
                bucketAdvance
            );
            mainGpuTemperature = recordSample(
                mainGpuTemperature,
                sensorValue(mainMetrics.gpuTemperature, mainFresh),
                bucketAdvance
            );
            mainComputePower = recordSample(
                mainComputePower,
                mainComputePowerValue(mainMetrics, mainFresh),
                bucketAdvance
            );
            lastSampleBucket = bucket;
        }

        function peak(samples) {
            let result = null;
            for (let index = 0; index < samples.length; index++) {
                const value = samples[index];
                if (typeof value === "number" && isFinite(value)
                        && (result === null || value > result))
                    result = value;
            }
            return result;
        }

        function average(samples) {
            let total = 0;
            let count = 0;
            for (let index = 0; index < samples.length; index++) {
                const value = samples[index];
                if (typeof value === "number" && isFinite(value)) {
                    total += value;
                    count++;
                }
            }
            return count === 0 ? null : total / count;
        }

        function temperaturePeakText(samples) {
            const value = peak(samples);
            return value === null ? "--" : Math.round(value).toString();
        }

        function powerAverageText(samples) {
            const value = average(samples);
            return value === null ? "--" : Math.round(value).toString();
        }

        function powerPeakText(samples) {
            const value = peak(samples);
            return value === null ? "--" : Math.round(value).toString();
        }
    }

    MetricsData {
        id: localData
        expectsSystemDetails: true
    }

    MetricsData {
        id: remoteData
    }

    HistoryStore {
        id: historyStore
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

    }

    component PanelEdge: Item {
        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            height: 1
            color: theme.panelEdgeLight
        }

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: 1
            color: theme.panelEdgeLight
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: theme.panelEdgeDark
        }

        Rectangle {
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
            }
            width: 1
            color: theme.panelEdgeDark
        }
    }

    component ModuleDivider: Item {
        implicitHeight: shell.moduleDividerHeight

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 1
            color: theme.divider
        }
    }

    component UsageBar: Rectangle {
        id: usageBar

        property real value: 0
        property color accent: theme.cpuAccent
        property bool available: false

        implicitHeight: 4
        radius: 0
        color: theme.usageTrack
        opacity: available ? 1.0 : 0.3

        Rectangle {
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: usageBar.available
                ? parent.width * Math.min(1, Math.max(0,
                    usageBar.value / 100))
                : 0
            radius: 0
            color: usageBar.accent
        }
    }

    component MetricCell: Column {
        id: metricCell

        required property string label
        required property string valueText
        property string unitText: ""

        spacing: -1

        Item {
            width: parent.width
            height: 11

            Text {
                anchors.centerIn: parent
                text: metricCell.label
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Medium
                font.letterSpacing: 0.5
            }
        }

        Item {
            width: parent.width
            height: metricValueRow.implicitHeight

            Row {
                id: metricValueRow
                anchors.centerIn: parent
                spacing: 2

                Text {
                    id: metricValue
                    text: metricCell.valueText
                    color: theme.textPrimary
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricValueSize
                    font.weight: Font.Normal
                }

                Text {
                    anchors.baseline: metricValue.baseline
                    text: metricCell.unitText
                    color: theme.textSecondary
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricUnitSize
                    font.weight: Font.Normal
                }
            }
        }
    }

    component ModuleHeader: Item {
        id: moduleHeader

        required property MetricsData metrics
        required property string title
        required property string platform
        required property string detail
        property bool staleIsUnknown: false

        implicitHeight: 24

        UI.ModuleHeaderRail {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            tone: shell.moduleTone(
                moduleHeader.metrics, moduleHeader.staleIsUnknown)
        }

        Text {
            anchors {
                left: parent.left
                leftMargin: 10
                verticalCenter: parent.verticalCenter
            }
            text: moduleHeader.title
            color: theme.textPrimary
            font.family: shell.smallLabelFont
            font.pixelSize: 17
            font.weight: Font.Medium
        }

        Column {
            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            width: 138
            spacing: -1

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: moduleHeader.platform
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Medium
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: moduleHeader.detail
                color: theme.textSecondary
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Normal
                elide: Text.ElideLeft
            }
        }
    }

    component SummaryTemperatureMetric: Item {
        id: summaryTemperatureMetric

        required property string label
        required property var samples

        implicitHeight: 31

        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: -1

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: summaryTemperatureMetric.label
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Medium
            }

            Item {
                width: parent.width
                height: 22

                Row {
                    anchors.centerIn: parent
                    spacing: 1

                    Text {
                        id: summaryTemperatureValue

                        text: historyStore.temperaturePeakText(
                            summaryTemperatureMetric.samples)
                        color: theme.textPrimary
                        font.family: shell.numericFont
                        font.pixelSize: 21
                        font.weight: Font.Normal
                    }

                    Text {
                        anchors.baseline: summaryTemperatureValue.baseline
                        text: "°C"
                        color: theme.textMuted
                        font.family: shell.smallLabelFont
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }

    component SummaryTemperatureRow: Item {
        id: summaryTemperatureRow

        required property string label
        required property var samples
        property bool primaryValue: false

        implicitHeight: 19

        Text {
            anchors {
                left: parent.left
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: summaryTemperatureRow.label
            color: summaryTemperatureRow.primaryValue
                ? theme.textSecondary : theme.textMuted
            font.family: shell.smallLabelFont
            font.pixelSize: 10
            font.weight: summaryTemperatureRow.primaryValue
                ? Font.Medium : Font.Normal
        }

        Row {
            anchors {
                right: parent.right
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            spacing: 1

            Text {
                id: summaryTemperatureRowValue

                text: historyStore.temperaturePeakText(
                    summaryTemperatureRow.samples)
                color: summaryTemperatureRow.primaryValue
                    ? theme.textPrimary : theme.textSecondary
                font.family: shell.numericFont
                font.pixelSize: summaryTemperatureRow.primaryValue ? 19 : 14
                font.weight: Font.Normal
            }

            Text {
                anchors.baseline: summaryTemperatureRowValue.baseline
                text: "°C"
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: summaryTemperatureRow.primaryValue ? 10 : 9
                font.weight: Font.Medium
            }
        }
    }

    component SummaryDeviceMetric: Item {
        id: summaryDeviceMetric

        required property string label
        required property var temperatureSamples
        required property color accent
        property bool hotspotVisible: false
        property var hotspotSamples: []

        implicitHeight: 52

        Column {
            anchors.fill: parent
            spacing: 0

            Text {
                width: parent.width
                height: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: summaryDeviceMetric.label
                color: summaryDeviceMetric.accent
                font.family: shell.smallLabelFont
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            Item {
                width: parent.width
                height: parent.height - 14

                SummaryTemperatureMetric {
                    anchors.fill: parent
                    visible: !summaryDeviceMetric.hotspotVisible
                    label: "TEMP"
                    samples: summaryDeviceMetric.temperatureSamples
                }

                Column {
                    id: temperaturePair

                    anchors.fill: parent
                    visible: summaryDeviceMetric.hotspotVisible
                    spacing: 0

                    SummaryTemperatureRow {
                        width: parent.width
                        height: Math.round(temperaturePair.height * 0.58)
                        label: "EDGE"
                        samples: summaryDeviceMetric.temperatureSamples
                        primaryValue: true
                    }

                    SummaryTemperatureRow {
                        width: parent.width
                        height: temperaturePair.height
                            - Math.round(temperaturePair.height * 0.58)
                        label: "HOTSPOT"
                        samples: summaryDeviceMetric.hotspotSamples
                    }
                }
            }
        }
    }

    component SummaryPowerValue: Item {
        id: summaryPowerValue

        required property string label
        required property var samples
        property bool peakValue: false
        property bool primaryValue: false

        implicitHeight: 19

        Text {
            anchors {
                left: parent.left
                leftMargin: 10
                verticalCenter: parent.verticalCenter
            }
            text: summaryPowerValue.label
            color: summaryPowerValue.primaryValue
                ? theme.textSecondary : theme.textMuted
            font.family: shell.smallLabelFont
            font.pixelSize: 10
            font.weight: summaryPowerValue.primaryValue
                ? Font.Medium : Font.Normal
        }

        Row {
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 1

            Text {
                id: aggregatePowerValue

                text: summaryPowerValue.peakValue
                    ? historyStore.powerPeakText(summaryPowerValue.samples)
                    : historyStore.powerAverageText(
                        summaryPowerValue.samples)
                color: summaryPowerValue.primaryValue
                    ? theme.textPrimary : theme.textSecondary
                font.family: shell.numericFont
                font.pixelSize: summaryPowerValue.primaryValue ? 21 : 15
                font.weight: Font.Normal
            }

            Text {
                anchors.baseline: aggregatePowerValue.baseline
                text: "W"
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: summaryPowerValue.primaryValue ? 10 : 9
                font.weight: Font.Medium
            }
        }
    }

    component SummaryPowerMachine: Item {
        id: summaryPowerMachine

        required property string machineLabel
        required property string sourceLabel
        required property var samples
        required property color labelTone

        implicitHeight: 57

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: 18

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: summaryPowerMachine.machineLabel
                    color: summaryPowerMachine.labelTone
                    font.family: shell.smallLabelFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                Text {
                    anchors {
                        right: parent.right
                        rightMargin: 6
                        verticalCenter: parent.verticalCenter
                    }
                    text: summaryPowerMachine.sourceLabel
                    color: theme.textMuted
                    font.family: shell.smallLabelFont
                    font.pixelSize: 9
                    font.weight: Font.Normal
                }
            }

            Column {
                id: powerPair

                width: parent.width
                height: parent.height - 18
                spacing: 0

                SummaryPowerValue {
                    width: parent.width
                    height: Math.round(powerPair.height * 0.59)
                    label: "AVG"
                    samples: summaryPowerMachine.samples
                    primaryValue: true
                }

                SummaryPowerValue {
                    width: parent.width
                    height: powerPair.height
                        - Math.round(powerPair.height * 0.59)
                    label: "MAX"
                    samples: summaryPowerMachine.samples
                    peakValue: true
                }
            }
        }
    }

    component PerformanceSummaryPanel: Rectangle {
        id: performanceSummaryPanel

        property MetricsData localMetrics
        property MetricsData mainMetrics
        property real bodyExtraHeight: 0
        readonly property bool localFresh: historyStore.sourceFresh(
            localMetrics, shell.nowMs)
        readonly property bool mainFresh: historyStore.sourceFresh(
            mainMetrics, shell.nowMs)
        readonly property color summaryTone: shell.combinedModuleTone(
            localMetrics, mainMetrics)
        readonly property int headerHeight: 24
        readonly property int sectionHeaderHeight: 19
        readonly property int minimumLocalTemperatureHeight: 52
        readonly property int minimumMainTemperatureHeight: 46
        readonly property int minimumPowerHeight: 57
        readonly property real rowExtraHeight:
            Math.max(0, bodyExtraHeight) / 3

        implicitWidth: shell.panelWidth
        implicitHeight: headerHeight
            + sectionHeaderHeight * 2
            + minimumLocalTemperatureHeight
            + minimumMainTemperatureHeight
            + minimumPowerHeight
            + shell.moduleDividerHeight * 2
            + shell.panelInset * 2
        radius: 0
        color: theme.panelBackground
        border.width: 0

        Column {
            anchors {
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                topMargin: shell.panelInset
                bottomMargin: shell.panelInset
            }
            width: shell.panelContentWidth
            spacing: 0

            Item {
                width: parent.width
                height: performanceSummaryPanel.headerHeight

                UI.ModuleHeaderRail {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    tone: performanceSummaryPanel.summaryTone
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "PERFORMANCE SUMMARY"
                    color: theme.textPrimary
                    font.family: shell.smallLabelFont
                    font.pixelSize: 17
                    font.weight: Font.Medium
                }

                Text {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: "10 MIN"
                    color: theme.textMuted
                    font.family: shell.smallLabelFont
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
            }

            ModuleDivider {
                width: parent.width
            }

            UI.SectionHeader {
                width: parent.width
                palette: theme
                height: performanceSummaryPanel.sectionHeaderHeight
                label: "PEAK TEMPERATURE"
                metadata: "10 MIN MAX"
            }

            Item {
                width: parent.width
                height: performanceSummaryPanel.minimumLocalTemperatureHeight
                    + performanceSummaryPanel.rowExtraHeight

                Row {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        width: 44
                        height: parent.height

                        Rectangle {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: 5
                            height: 5
                            color: performanceSummaryPanel.localFresh
                                ? theme.statusOk : theme.textDisabled
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 9
                                verticalCenter: parent.verticalCenter
                            }
                            text: "LOCAL"
                            color: performanceSummaryPanel.localFresh
                                ? theme.textPrimary : theme.textDisabled
                            font.family: shell.smallLabelFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    SummaryDeviceMetric {
                        width: 56
                        height: parent.height
                        label: "CPU"
                        temperatureSamples:
                            historyStore.localCpuTemperature
                        accent: theme.cpuAccent
                    }

                    SummaryDeviceMetric {
                        width: (parent.width - 100) / 2
                        height: parent.height
                        label: "GPU 1"
                        temperatureSamples:
                            historyStore.localGpu1Temperature
                        hotspotVisible: true
                        hotspotSamples:
                            historyStore.localGpu1Hotspot
                        accent: theme.gpuAccent
                    }

                    SummaryDeviceMetric {
                        width: (parent.width - 100) / 2
                        height: parent.height
                        label: "GPU 2"
                        temperatureSamples:
                            historyStore.localGpu2Temperature
                        hotspotVisible: true
                        hotspotSamples:
                            historyStore.localGpu2Hotspot
                        accent: theme.gpuAccent
                    }
                }
            }

            Item {
                width: parent.width
                height: performanceSummaryPanel.minimumMainTemperatureHeight
                    + performanceSummaryPanel.rowExtraHeight

                Row {
                    anchors.fill: parent
                    spacing: 0

                    Item {
                        width: 44
                        height: parent.height

                        Rectangle {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            width: 5
                            height: 5
                            color: performanceSummaryPanel.mainFresh
                                ? theme.statusOk : theme.textDisabled
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 9
                                verticalCenter: parent.verticalCenter
                            }
                            text: "MAIN"
                            color: performanceSummaryPanel.mainFresh
                                ? theme.textPrimary : theme.textDisabled
                            font.family: shell.smallLabelFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }

                    SummaryDeviceMetric {
                        width: (parent.width - 44) / 2
                        height: parent.height
                        label: "CPU"
                        temperatureSamples:
                            historyStore.mainCpuTemperature
                        accent: theme.cpuAccent
                    }

                    SummaryDeviceMetric {
                        width: (parent.width - 44) / 2
                        height: parent.height
                        label: "GPU"
                        temperatureSamples:
                            historyStore.mainGpuTemperature
                        accent: theme.gpuAccent
                    }
                }
            }

            ModuleDivider {
                width: parent.width
            }

            UI.SectionHeader {
                width: parent.width
                palette: theme
                height: performanceSummaryPanel.sectionHeaderHeight
                label: "COMPUTE POWER"
                metadata: "AVG / MAX"
            }

            Item {
                width: parent.width
                height: performanceSummaryPanel.minimumPowerHeight
                    + performanceSummaryPanel.rowExtraHeight

                Row {
                    anchors.fill: parent

                    SummaryPowerMachine {
                        width: parent.width / 2
                        height: parent.height
                        machineLabel: "LOCAL"
                        sourceLabel: "CPU + GPU1 + GPU2"
                        samples: historyStore.localComputePower
                        labelTone: performanceSummaryPanel.localFresh
                            ? theme.textPrimary : theme.textDisabled
                    }

                    SummaryPowerMachine {
                        width: parent.width / 2
                        height: parent.height
                        machineLabel: "MAIN"
                        sourceLabel: "CPU + GPU"
                        samples: historyStore.mainComputePower
                        labelTone: performanceSummaryPanel.mainFresh
                            ? theme.textPrimary : theme.textDisabled
                    }
                }

                Rectangle {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        verticalCenter: parent.verticalCenter
                    }
                    width: 1
                    height: parent.height - 10
                    color: theme.divider
                }
            }
        }

        PanelEdge {
            anchors.fill: parent
            z: 10
        }
    }

    component ComputeSection: Column {
        id: computeSection

        required property string label
        property bool available: false
        property string modelName: ""
        property real usage: 0
        property var temperatureValue: null
        property var powerValue: null
        property color accent: theme.cpuAccent

        spacing: 2

        UI.SectionHeader {
            width: parent.width
            palette: theme
            label: computeSection.label
            metadata: computeSection.modelName !== ""
                ? shell.compactModelName(computeSection.modelName)
                : "MODEL --"
        }

        Row {
            width: parent.width

            MetricCell {
                width: parent.width / 3
                label: "LOAD"
                valueText: shell.percentageValue(
                    computeSection.usage,
                    computeSection.available
                )
                unitText: "%"
            }

            MetricCell {
                width: parent.width / 3
                label: "TEMP"
                valueText: shell.metricValue(computeSection.temperatureValue)
                unitText: "°C"
            }

            MetricCell {
                width: parent.width / 3
                label: "POWER"
                valueText: shell.metricValue(computeSection.powerValue)
                unitText: "W"
            }
        }

        UsageBar {
            width: parent.width
            value: Math.round(computeSection.usage)
            accent: computeSection.accent
            available: computeSection.available
        }
    }

    component LocalComputeDevice: Column {
        id: localComputeDevice

        required property string label
        property string detail: ""
        property bool divided: false
        property bool available: false
        property real usage: 0
        property var temperatureValue: null
        property var powerValue: null
        property color accent: theme.cpuAccent

        spacing: 0

        ModuleDivider {
            width: parent.width
            visible: localComputeDevice.divided
        }

        Column {
            width: parent.width
            spacing: 2

            UI.SectionHeader {
                width: parent.width
                palette: theme
                label: localComputeDevice.label
                metadata: localComputeDevice.detail !== ""
                    ? localComputeDevice.detail : "MODEL --"
                metadataTone: localComputeDevice.available
                    ? theme.textMuted : theme.textDisabled
            }

            Row {
                width: parent.width

                MetricCell {
                    width: parent.width / 3
                    label: "LOAD"
                    valueText: shell.percentageValue(
                        localComputeDevice.usage,
                        localComputeDevice.available
                    )
                    unitText: "%"
                }

                MetricCell {
                    width: parent.width / 3
                    label: "TEMP"
                    valueText: shell.metricValue(
                        localComputeDevice.temperatureValue)
                    unitText: "°C"
                }

                MetricCell {
                    width: parent.width / 3
                    label: "POWER"
                    valueText: shell.metricValue(
                        localComputeDevice.powerValue)
                    unitText: "W"
                }
            }

            UsageBar {
                width: parent.width
                value: Math.round(localComputeDevice.usage)
                accent: localComputeDevice.accent
                available: localComputeDevice.available
            }
        }
    }

    component LocalComputeSection: Column {
        id: localComputeSection

        property MetricsData metrics
        readonly property int gpuCount:
            metrics && Array.isArray(metrics.gpus)
                ? metrics.gpus.length : 0

        spacing: 0

        LocalComputeDevice {
            width: parent.width
            label: "CPU"
            detail: localComputeSection.metrics.cpuModel !== ""
                ? shell.compactModelName(
                    localComputeSection.metrics.cpuModel)
                : "MODEL --"
            available: localComputeSection.metrics.cpuAvailable
            usage: localComputeSection.metrics.cpuUsage
            temperatureValue:
                localComputeSection.metrics.cpuTemperature
            powerValue: localComputeSection.metrics.cpuPower
            accent: theme.cpuAccent
        }

        LocalComputeDevice {
            width: parent.width
            visible: localComputeSection.gpuCount === 0
            label: "GPU 1"
            detail: "SENSOR --"
            divided: true
            accent: theme.gpuAccent
        }

        Repeater {
            model: localComputeSection.gpuCount

            delegate: LocalComputeDevice {
                required property int index

                readonly property var gpu:
                    localComputeSection.metrics.gpus[index]

                width: localComputeSection.width
                label: "GPU " + (index + 1)
                detail: shell.localGpuDetail(gpu)
                divided: true
                available: gpu && gpu.available === true
                usage: gpu ? gpu.usage : 0
                temperatureValue: gpu ? gpu.temperature : null
                powerValue: gpu ? gpu.power : null
                accent: theme.gpuAccent
            }
        }
    }

    component LocalMemoryMetric: Column {
        id: localMemoryMetric

        required property string label
        property bool available: false
        property real used: 0
        property real total: 0
        property real usage: 0
        property color accent: theme.ramAccent

        spacing: -1

        Item {
            width: parent.width
            height: 11

            Text {
                anchors.centerIn: parent
                text: localMemoryMetric.label
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Medium
            }
        }

        Item {
            width: parent.width
            height: localMemoryValueRow.implicitHeight

            Row {
                id: localMemoryValueRow
                anchors.centerIn: parent
                spacing: 2

                Text {
                    id: localMemoryValue
                    text: shell.percentageValue(
                        localMemoryMetric.usage,
                        localMemoryMetric.available
                    )
                    color: localMemoryMetric.available
                        ? theme.textPrimary : theme.textDisabled
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricValueSize
                    font.weight: Font.Normal
                }

                Text {
                    anchors.baseline: localMemoryValue.baseline
                    text: "%"
                    color: localMemoryMetric.available
                        ? theme.textSecondary : theme.textDisabled
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricUnitSize
                    font.weight: Font.Normal
                }
            }
        }

        Item {
            width: parent.width
            height: 13

            Text {
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: shell.capacitySummary(
                    localMemoryMetric.used,
                    localMemoryMetric.total,
                    localMemoryMetric.available
                )
                color: localMemoryMetric.available
                    ? theme.textSecondary : theme.textDisabled
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Normal
                elide: Text.ElideRight
            }
        }

        Item {
            width: parent.width
            height: 4

            UsageBar {
                anchors {
                    fill: parent
                    leftMargin: 6
                    rightMargin: 6
                }
                value: Math.round(localMemoryMetric.usage)
                accent: localMemoryMetric.accent
                available: localMemoryMetric.available
            }
        }
    }

    component LocalMemorySection: Column {
        id: localMemorySection

        property MetricsData metrics
        readonly property int gpuCount:
            metrics && Array.isArray(metrics.gpus)
                ? metrics.gpus.length : 0

        spacing: 0

        UI.SectionHeader {
            width: parent.width
            palette: theme
            label: "MEMORY"
        }

        Flow {
            id: localMemoryFlow

            width: parent.width
            spacing: 0

            LocalMemoryMetric {
                width: localMemoryFlow.width / 3
                label: "RAM"
                available: localMemorySection.metrics.memoryAvailable
                used: localMemorySection.metrics.memoryUsed
                total: localMemorySection.metrics.memoryTotal
                usage: localMemorySection.metrics.memoryUsage
                accent: theme.ramAccent
            }

            LocalMemoryMetric {
                width: localMemoryFlow.width / 3
                visible: localMemorySection.gpuCount === 0
                label: "VRAM 1"
                accent: theme.vramAccent
            }

            Repeater {
                model: localMemorySection.gpuCount

                delegate: LocalMemoryMetric {
                    required property int index

                    readonly property var gpu:
                        localMemorySection.metrics.gpus[index]
                    readonly property bool vramAvailable:
                        gpu && gpu.vram && gpu.vram.available === true

                    width: localMemoryFlow.width / 3
                    label: "VRAM " + (index + 1)
                    available: vramAvailable
                    used: vramAvailable ? gpu.vram.used : 0
                    total: vramAvailable ? gpu.vram.total : 0
                    usage: vramAvailable ? gpu.vram.usage : 0
                    accent: theme.vramAccent
                }
            }
        }
    }

    component LocalCapacityRow: Column {
        id: localCapacityRow

        required property string label
        property bool available: false
        property real used: 0
        property real total: 0
        property string unavailableText: "-- / -- GiB"
        property real usage: 0
        property color accent: theme.ramAccent

        spacing: 2

        Item {
            width: parent.width
            height: 18

            Text {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                text: localCapacityRow.label
                color: localCapacityRow.available
                    ? theme.textSecondary : theme.textDisabled
                font.family: shell.smallLabelFont
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            Text {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                text: localCapacityRow.available
                    ? shell.capacitySummary(
                        localCapacityRow.used,
                        localCapacityRow.total,
                        true
                    )
                    : localCapacityRow.unavailableText
                color: localCapacityRow.available
                    ? theme.textPrimary : theme.textDisabled
                font.family: shell.smallLabelFont
                font.pixelSize: 10
                font.weight: Font.Normal
            }
        }

        UsageBar {
            width: parent.width
            value: localCapacityRow.usage
            accent: localCapacityRow.accent
            available: localCapacityRow.available
            opacity: localCapacityRow.available ? 1.0 : 0.0
        }
    }

    component LocalStorageSection: Column {
        id: localStorageSection

        required property MetricsData metrics
        readonly property int volumeCount:
            Array.isArray(metrics.storageVolumes)
                ? metrics.storageVolumes.length : 0

        spacing: 3

        UI.SectionHeader {
            width: parent.width
            palette: theme
            label: "STORAGE"
        }

        LocalCapacityRow {
            width: parent.width
            label: "ROOT"
            available: localStorageSection.metrics.storageAvailable
            used: localStorageSection.metrics.storageUsed
            total: localStorageSection.metrics.storageTotal
            unavailableText: "SENSOR --"
            usage: localStorageSection.metrics.storageUsage
            accent: theme.storageAccent
        }

        Repeater {
            model: localStorageSection.volumeCount

            delegate: LocalCapacityRow {
                required property int index
                readonly property var volume:
                    localStorageSection.metrics.storageVolumes[index]

                width: localStorageSection.width
                label: volume.label
                    + (volume.kind !== ""
                            && volume.kind.toUpperCase()
                                !== volume.label.toUpperCase()
                        ? " · " + volume.kind.toUpperCase()
                        : "")
                available: volume.available
                used: volume.used
                total: volume.total
                unavailableText: "NOT MOUNTED"
                usage: volume.usage
                accent: theme.storageAccent
            }
        }
    }

    component NetworkSection: Column {
        id: networkSection

        property MetricsData metrics

        spacing: 2

        UI.SectionHeader {
            width: parent.width
            palette: theme
            label: "NETWORK"
            metadata: networkSection.metrics.networkInterface !== ""
                ? networkSection.metrics.networkInterface
                : "INTERFACE --"
        }

        Row {
            width: parent.width

            MetricCell {
                width: parent.width / 2
                label: "DOWNLOAD"
                valueText: "↓ " + shell.byteRateValue(
                    networkSection.metrics.networkDownload,
                    networkSection.metrics.networkAvailable
                )
                unitText: shell.byteRateUnit(
                    networkSection.metrics.networkDownload,
                    networkSection.metrics.networkAvailable
                )
            }

            MetricCell {
                width: parent.width / 2
                label: "UPLOAD"
                valueText: "↑ " + shell.byteRateValue(
                    networkSection.metrics.networkUpload,
                    networkSection.metrics.networkAvailable
                )
                unitText: shell.byteRateUnit(
                    networkSection.metrics.networkUpload,
                    networkSection.metrics.networkAvailable
                )
            }
        }
    }

    component MemoryPair: Column {
        id: memoryPair

        required property string label
        property bool available: false
        property real used: 0
        property real total: 0
        property real usage: 0
        property color accent: theme.ramAccent

        spacing: 2

        Item {
            width: parent.width
            height: 30

            Text {
                anchors {
                    left: parent.left
                    top: parent.top
                }
                text: memoryPair.label
                color: theme.textMuted
                font.family: shell.smallLabelFont
                font.pixelSize: 10
                font.weight: Font.Medium
            }

            Row {
                anchors {
                    right: parent.right
                    top: parent.top
                    topMargin: -3
                }
                spacing: 2

                Text {
                    id: memoryPercent
                    text: shell.percentageValue(
                        memoryPair.usage,
                        memoryPair.available
                    )
                    color: theme.textPrimary
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricValueSize
                    font.weight: Font.Normal
                }

                Text {
                    anchors.baseline: memoryPercent.baseline
                    text: "%"
                    color: theme.textSecondary
                    font.family: shell.numericFont
                    font.pixelSize: theme.metricUnitSize
                }
            }

            Text {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                }
                text: shell.capacitySummary(
                    memoryPair.used,
                    memoryPair.total,
                    memoryPair.available
                )
                color: theme.textSecondary
                font.family: shell.smallLabelFont
                font.pixelSize: 9
                font.weight: Font.Normal
            }
        }

        UsageBar {
            width: parent.width
            value: Math.round(memoryPair.usage)
            accent: memoryPair.accent
            available: memoryPair.available
        }
    }

    component MemoryComparisonSection: Column {
        id: memoryComparisonSection

        property MetricsData metrics
        property bool forceZero: false

        spacing: 2

        UI.SectionHeader {
            width: parent.width
            palette: theme
            label: "MEMORY"
            metadata: "RAM · VRAM"
        }

        Row {
            width: parent.width
            spacing: 12

            MemoryPair {
                width: (parent.width - 12) / 2
                label: "RAM"
                available: memoryComparisonSection.forceZero
                    || memoryComparisonSection.metrics.memoryAvailable
                used: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.memoryUsed
                total: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.memoryTotal
                usage: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.memoryUsage
                accent: theme.ramAccent
            }

            MemoryPair {
                width: (parent.width - 12) / 2
                label: "VRAM"
                available: memoryComparisonSection.forceZero
                    || memoryComparisonSection.metrics.vramAvailable
                used: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.vramUsed
                total: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.vramTotal
                usage: memoryComparisonSection.forceZero ? 0
                    : memoryComparisonSection.metrics.vramUsage
                accent: theme.vramAccent
            }
        }
    }

    component LocalSystemPanel: Rectangle {
        id: localSystemPanel

        property MetricsData metrics

        implicitWidth: shell.panelWidth
        implicitHeight: localSystemContent.implicitHeight
            + shell.panelInset * 2
        radius: 0
        color: theme.panelBackground
        border.width: 0

        Column {
            id: localSystemContent
            anchors.centerIn: parent
            width: shell.panelContentWidth
            spacing: 0

            ModuleHeader {
                width: parent.width
                metrics: localSystemPanel.metrics
                title: "LOCAL SYSTEM"
                platform: "ARCH LINUX"
                detail: shell.uptime(
                    localSystemPanel.metrics.uptimeSeconds,
                    localSystemPanel.metrics.uptimeAvailable
                )
            }

            ModuleDivider {
                width: parent.width
            }

            LocalComputeSection {
                width: parent.width
                metrics: localSystemPanel.metrics
            }

            ModuleDivider {
                width: parent.width
            }

            LocalMemorySection {
                width: parent.width
                metrics: localSystemPanel.metrics
            }

            ModuleDivider {
                width: parent.width
            }

            LocalStorageSection {
                width: parent.width
                metrics: localSystemPanel.metrics
            }

            ModuleDivider {
                width: parent.width
            }

            NetworkSection {
                width: parent.width
                metrics: localSystemPanel.metrics
            }
        }

        PanelEdge {
            anchors.fill: parent
            z: 10
        }
    }

    component RemoteSystemPanel: Rectangle {
        id: remoteSystemPanel

        property MetricsData metrics
        // Current stale values read as zero; history keeps the outage as a gap.
        readonly property bool showingZeroValues: metrics.available
            && !historyStore.sourceFresh(metrics, shell.nowMs)

        implicitWidth: shell.panelWidth
        implicitHeight: remoteSystemContent.implicitHeight
            + shell.panelInset * 2
        radius: 0
        color: theme.panelBackground
        border.width: 0

        Column {
            id: remoteSystemContent
            anchors.centerIn: parent
            width: shell.panelContentWidth
            spacing: 0

            ModuleHeader {
                width: parent.width
                metrics: remoteSystemPanel.metrics
                staleIsUnknown: true
                title: "MAIN PC"
                platform: "WINDOWS"
                detail: remoteSystemPanel.metrics.available
                    ? "HOST "
                        + (remoteSystemPanel.metrics.host !== ""
                            ? remoteSystemPanel.metrics.host.toUpperCase()
                            : "--")
                    : "HOST --"
            }

            ModuleDivider {
                width: parent.width
            }

            ComputeSection {
                width: parent.width
                label: "CPU"
                available: remoteSystemPanel.showingZeroValues
                    || remoteSystemPanel.metrics.cpuAvailable
                modelName: remoteSystemPanel.metrics.cpuModel
                usage: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.cpuUsage
                temperatureValue: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.cpuTemperature
                powerValue: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.cpuPower
                accent: theme.cpuAccent
            }

            ModuleDivider {
                width: parent.width
            }

            ComputeSection {
                width: parent.width
                label: "GPU"
                available: remoteSystemPanel.showingZeroValues
                    || remoteSystemPanel.metrics.gpuAvailable
                modelName: remoteSystemPanel.metrics.gpuModel
                usage: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.gpuUsage
                temperatureValue: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.gpuTemperature
                powerValue: remoteSystemPanel.showingZeroValues ? 0
                    : remoteSystemPanel.metrics.gpuPower
                accent: theme.gpuAccent
            }

            ModuleDivider {
                width: parent.width
            }

            MemoryComparisonSection {
                width: parent.width
                metrics: remoteSystemPanel.metrics
                forceZero: remoteSystemPanel.showingZeroValues
            }
        }

        PanelEdge {
            anchors.fill: parent
            z: 10
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

        implicitWidth: shell.panelWidth
        color: "transparent"
        exclusiveZone: 0
        focusable: false
        mask: Region {}

        Item {
            id: cards

            anchors.fill: parent

            LocalSystemPanel {
                id: localSystem

                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                metrics: localData
            }

            RemoteSystemPanel {
                id: mainSystem

                anchors {
                    top: localSystem.bottom
                    topMargin: shell.performancePanelGap
                    left: parent.left
                    right: parent.right
                }
                metrics: remoteData
            }

            PerformanceSummaryPanel {
                anchors {
                    top: mainSystem.bottom
                    topMargin: shell.performancePanelGap
                    bottom: parent.bottom
                    left: parent.left
                    right: parent.right
                }
                localMetrics: localData
                mainMetrics: remoteData
                bodyExtraHeight: Math.max(0,
                    cards.height
                    - localSystem.implicitHeight
                    - mainSystem.implicitHeight
                    - shell.performancePanelGap * 2
                    - implicitHeight
                )
            }
        }
    }

    Process {
        command: [
            "/usr/bin/python3",
            "-B",
            shell.performanceScriptsDir + "/system_metrics.py",
            "--interval",
            shell.pollIntervalSeconds.toString(),
            "--machine-config",
            shell.machineConfigPath
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
            shell.pollIntervalSeconds.toString(),
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

    // Continue advancing the timeline when either collector stops producing.
    Timer {
        interval: shell.historySampleIntervalMs
        running: true
        repeat: true
        onTriggered: historyStore.capture(
            localData, remoteData, Date.now())
    }

    Timer {
        interval: shell.pollIntervalSeconds * 1000
        running: true
        repeat: true
        onTriggered: shell.nowMs = Date.now()
    }
}
