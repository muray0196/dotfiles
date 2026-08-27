import Quickshell
import Quickshell.Io
import QtQuick
import "common" as UI

Scope {
    id: shell

    UI.Theme {
        id: theme
    }

    readonly property int widgetWidth: 312
    property bool widgetsVisible: true
    readonly property string clockScriptsDir: Quickshell.shellDir + "/scripts"
    readonly property string clockConfigPath: Quickshell.shellDir + "/local.json"
    readonly property int panelContentWidth: 280
    readonly property int panelGap: 10
    readonly property int panelBottomInset: 10
    readonly property int moduleDividerHeight: 7
    readonly property int radarHeaderHeight: 31
    readonly property var calendarWeekdayLabels:
        ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    property var holidayEntries: ({})
    property bool holidayDataAvailable: false
    property bool holidayDataStale: false
    property date calendarDate: new Date()
    readonly property int currentYear: calendarDate.getFullYear()
    readonly property int currentMonth: calendarDate.getMonth() + 1
    readonly property int currentDay: calendarDate.getDate()
    readonly property int currentWeekday: calendarDate.getDay()
    readonly property string currentDateKey:
        dateKey(currentYear, currentMonth, currentDay)
    readonly property string currentDateLabel: currentYear + " / "
        + padded(currentMonth) + " / " + padded(currentDay) + " · "
        + calendarWeekdayLabels[currentWeekday]
    property string currentTimeZoneAbbreviation: ""
    readonly property string currentTimeZoneLabel:
        (currentTimeZoneAbbreviation !== ""
            ? currentTimeZoneAbbreviation + " · " : "")
        + utcOffsetLabel(clock.date)
    readonly property int currentIsoWeek: isoWeekNumber(calendarDate)
    readonly property int currentDayOfYear: dayOfYear(calendarDate)
    readonly property int currentYearLength: daysInYear(currentYear)
    readonly property var nextHolidaySummary: nextHolidayDetails()
    readonly property bool localTimeSourceCurrent: validDate(clock.date)
    readonly property color localTimeSourceTone: !localTimeSourceCurrent
        ? theme.statusError : currentTimeZoneAbbreviation !== ""
        ? theme.statusOk : theme.statusCaution
    readonly property bool calendarSourceCurrent: validDate(calendarDate)
    readonly property color calendarSourceTone: !calendarSourceCurrent
        ? theme.statusError : holidayDataAvailable && !holidayDataStale
        ? theme.statusOk : theme.statusCaution

    function padded(value) {
        return value < 10 ? "0" + value : value.toString();
    }

    function validDate(value) {
        return value !== null && typeof value.getTime === "function"
            && isFinite(value.getTime());
    }

    function utcOffsetLabel(date) {
        const totalMinutes = -date.getTimezoneOffset();
        const sign = totalMinutes >= 0 ? "+" : "−";
        const absoluteMinutes = Math.abs(totalMinutes);
        const hours = Math.floor(absoluteMinutes / 60);
        const minutes = absoluteMinutes % 60;
        return "UTC" + sign + padded(hours)
            + (minutes === 0 ? "" : ":" + padded(minutes));
    }

    function dateKey(year, month, day) {
        return year + "-" + padded(month) + "-" + padded(day);
    }

    function dayOfYear(date) {
        const start = Date.UTC(date.getFullYear(), 0, 1);
        const current = Date.UTC(
            date.getFullYear(), date.getMonth(), date.getDate()
        );
        return Math.floor((current - start) / 86400000) + 1;
    }

    function daysInYear(year) {
        return new Date(year, 1, 29).getMonth() === 1 ? 366 : 365;
    }

    function isoWeekNumber(date) {
        const target = new Date(Date.UTC(
            date.getFullYear(), date.getMonth(), date.getDate()
        ));
        const weekday = target.getUTCDay() || 7;
        target.setUTCDate(target.getUTCDate() + 4 - weekday);
        const yearStart = new Date(Date.UTC(target.getUTCFullYear(), 0, 1));
        return Math.ceil(((target - yearStart) / 86400000 + 1) / 7);
    }

    function daysUntilDateKey(key) {
        const target = Date.UTC(
            Number(key.slice(0, 4)),
            Number(key.slice(5, 7)) - 1,
            Number(key.slice(8, 10))
        );
        const current = Date.UTC(currentYear, currentMonth - 1, currentDay);
        return Math.round((target - current) / 86400000);
    }

    function millisecondsUntilNextDay() {
        const now = new Date();
        const nextDay = new Date(
            now.getFullYear(), now.getMonth(), now.getDate() + 1,
            0, 0, 0, 100
        );
        return Math.max(1000, nextDay.getTime() - now.getTime());
    }

    function updateCalendarDate() {
        calendarDate = new Date();
        calendarDateTimer.interval = millisecondsUntilNextDay();
        calendarDateTimer.restart();
    }

    function millisecondsUntilNextWeatherFetch() {
        const now = new Date();
        const minutesUntilBoundary = 2 - now.getMinutes() % 2;
        const nextFetch = new Date(
            now.getFullYear(), now.getMonth(), now.getDate(),
            now.getHours(), now.getMinutes() + minutesUntilBoundary,
            0, 0
        );
        return Math.max(1, nextFetch.getTime() - now.getTime());
    }

    function requestWeatherFetch() {
        if (weatherProcess.running) {
            weatherFetchPending = true;
            return;
        }
        weatherFetchPending = false;
        weatherUpdateReceived = false;
        weatherProcess.running = true;
    }

    function scheduleNextWeatherFetch() {
        weatherTimer.interval = millisecondsUntilNextWeatherFetch();
        weatherTimer.restart();
    }

    function radarCycleEpochMs(timestampMs) {
        return Math.floor(timestampMs / radarCycleDurationMs)
            * radarCycleDurationMs;
    }

    function radarAttemptOffsetAt(cycleEpochMs, timestampMs) {
        let currentOffset = -1;
        for (const offset of radarAttemptOffsetsSeconds) {
            if (cycleEpochMs + offset * 1000 > timestampMs)
                break;
            currentOffset = offset;
        }
        return currentOffset;
    }

    function scheduleRadarFetchAt(cycleEpochMs, offsetSeconds) {
        const targetEpochMs = cycleEpochMs + offsetSeconds * 1000;
        radarScheduledCycleEpochMs = cycleEpochMs;
        radarScheduledAttemptOffsetSeconds = offsetSeconds;
        radarTimer.interval = Math.max(1, targetEpochMs - Date.now());
        radarTimer.restart();
        console.info(
            "Rain radar fetch scheduled:",
            new Date(targetEpochMs).toISOString(),
            "offset +" + offsetSeconds + "s"
        );
    }

    function scheduleNextRadarCycle() {
        const nowMs = Date.now();
        let cycleEpochMs = radarCycleEpochMs(nowMs);
        const firstOffset = radarAttemptOffsetsSeconds[0];
        if (cycleEpochMs + firstOffset * 1000 <= nowMs)
            cycleEpochMs += radarCycleDurationMs;
        radarRetrying = false;
        scheduleRadarFetchAt(cycleEpochMs, firstOffset);
    }

    function scheduleRadarRetryForCycle(cycleEpochMs, afterOffsetSeconds) {
        const nowMs = Date.now();
        for (const offset of radarAttemptOffsetsSeconds) {
            const targetEpochMs = cycleEpochMs + offset * 1000;
            if (offset <= afterOffsetSeconds || targetEpochMs <= nowMs)
                continue;
            radarRetrying = true;
            scheduleRadarFetchAt(cycleEpochMs, offset);
            return;
        }
        scheduleNextRadarCycle();
    }

    function scheduleRadarForecastEnrichment(
        cycleEpochMs, afterOffsetSeconds
    ) {
        const targetOffset = radarForecastEnrichmentOffsetSeconds;
        const targetEpochMs = cycleEpochMs + targetOffset * 1000;
        if (afterOffsetSeconds < targetOffset && targetEpochMs > Date.now()) {
            radarRetrying = true;
            scheduleRadarFetchAt(cycleEpochMs, targetOffset);
            return;
        }
        scheduleRadarRetryForCycle(cycleEpochMs, afterOffsetSeconds);
    }

    function requestRadarFetch(cycleEpochMs, attemptOffsetSeconds) {
        if (radarProcess.running)
            return false;
        radarRequestCycleEpochMs = cycleEpochMs;
        radarRequestAttemptOffsetSeconds = attemptOffsetSeconds;
        radarIncludeAnimationFrames = radarRainDetected();
        radarUpdateReceived = false;
        radarResponseReferenceEpoch = 0;
        radarResponseHasForecast = false;
        radarRequestTileFailed = false;
        radarProcess.running = true;
        return true;
    }

    function requestRadarRefreshNow() {
        if (radarProcess.running) {
            radarImmediateFetchPending = true;
            return;
        }
        const nowMs = Date.now();
        const cycleEpochMs = radarCycleEpochMs(nowMs);
        radarTimer.stop();
        radarImmediateFetchPending = false;
        requestRadarFetch(
            cycleEpochMs,
            radarAttemptOffsetAt(cycleEpochMs, nowMs)
        );
    }

    function finishRadarFetch(exitCode) {
        const succeeded = exitCode === 0 && radarUpdateReceived;
        const expectedReferenceEpoch = radarRequestCycleEpochMs / 1000;
        const observationCurrent = succeeded
            && radarResponseReferenceEpoch >= expectedReferenceEpoch;

        if (radarRequestTileFailed) {
            radarFetchFailed = true;
            scheduleRadarRetryForCycle(
                radarRequestCycleEpochMs,
                radarRequestAttemptOffsetSeconds
            );
            return;
        }

        if (!succeeded)
            radarFetchFailed = true;

        if (!observationCurrent) {
            if (radarRequestAttemptOffsetSeconds >= 50) {
                console.warn(
                    "Rain radar observation not current; retrying:",
                    "expected", expectedReferenceEpoch,
                    "received", radarResponseReferenceEpoch
                );
            }
            scheduleRadarRetryForCycle(
                radarRequestCycleEpochMs,
                radarRequestAttemptOffsetSeconds
            );
            return;
        }

        if (radarResponseReferenceEpoch > radarLastLoggedReferenceEpoch) {
            radarLastLoggedReferenceEpoch = radarResponseReferenceEpoch;
            console.info(
                "Rain radar manifest advanced:",
                new Date(radarResponseReferenceEpoch * 1000).toISOString(),
                "attempt +" + radarRequestAttemptOffsetSeconds + "s"
            );
        }

        if (radarIncludeAnimationFrames && !radarResponseHasForecast) {
            scheduleRadarForecastEnrichment(
                radarRequestCycleEpochMs,
                radarRequestAttemptOffsetSeconds
            );
            return;
        }

        scheduleNextRadarCycle();
    }

    function holidayName(key) {
        const value = holidayEntries[key];
        return typeof value === "string" ? value : "";
    }

    function calendarCells() {
        const firstWeekday = new Date(currentYear, currentMonth - 1, 1).getDay();
        const daysInMonth = new Date(currentYear, currentMonth, 0).getDate();
        const cellCount = Math.ceil((firstWeekday + daysInMonth) / 7) * 7;
        const cells = [];

        for (let index = 0; index < cellCount; index++) {
            const day = index - firstWeekday + 1;
            const date = new Date(currentYear, currentMonth - 1, day);
            const cellYear = date.getFullYear();
            const cellMonth = date.getMonth() + 1;
            const cellDay = date.getDate();
            const key = dateKey(cellYear, cellMonth, cellDay);
            cells.push({
                day: cellDay,
                key: key,
                weekday: index % 7,
                holiday: holidayName(key),
                isToday: key === currentDateKey,
                isCurrentMonth: cellYear === currentYear
                    && cellMonth === currentMonth
            });
        }
        return cells;
    }

    function calendarDayColor(cell) {
        if (!cell.isCurrentMonth)
            return theme.textDisabled;
        if (cell.holiday !== "" || cell.weekday === 0)
            return theme.calendarSundayHoliday;
        if (cell.weekday === 6)
            return theme.calendarSaturday;
        return theme.textPrimary;
    }

    function nextHolidayDetails() {
        if (!holidayDataAvailable) {
            return {
                label: "HOLIDAY DATA",
                value: "NO DATA",
                countdown: "",
                known: false
            };
        }

        const dates = Object.keys(holidayEntries).sort();
        for (const key of dates) {
            if (key < currentDateKey)
                continue;
            if (key === currentDateKey) {
                return {
                    label: "HOLIDAY TODAY",
                    value: holidayEntries[key],
                    countdown: "",
                    known: true
                };
            }

            const month = Number(key.slice(5, 7));
            const day = Number(key.slice(8, 10));
            return {
                label: "NEXT HOLIDAY",
                value: padded(month) + "/" + padded(day)
                    + " " + holidayEntries[key],
                countdown: "IN " + daysUntilDateKey(key) + "D",
                known: true
            };
        }
        return {
            label: "NEXT HOLIDAY",
            value: "UNLISTED",
            countdown: "",
            known: true
        };
    }

    component EnvironmentMetric: Column {
        required property string label
        required property string valueText
        required property string unitText
        property string comparison: ""
        property bool reserveComparisonSpace: true
        property color valueColor: theme.textPrimary
        property color unitColor: theme.textSecondary

        spacing: -1

        Item {
            width: parent.width
            height: 11

            Text {
                anchors.centerIn: parent
                text: label
                color: theme.textMuted
                font.family: "Adwaita Mono"
                font.pixelSize: 9
                font.weight: Font.Medium
            }
        }

        Item {
            width: parent.width
            height: environmentValueRow.implicitHeight

            Row {
                id: environmentValueRow
                anchors.centerIn: parent
                spacing: 2

                Text {
                    id: environmentValue
                    text: valueText
                    color: valueColor
                    font.family: "Adwaita Sans"
                    font.pixelSize: theme.metricValueSize
                    font.weight: Font.Normal
                }

                Text {
                    anchors.baseline: environmentValue.baseline
                    text: unitText
                    color: unitColor
                    font.family: "Adwaita Sans"
                    font.pixelSize: theme.metricUnitSize
                    font.weight: Font.Normal
                }
            }
        }

        Item {
            width: parent.width
            height: 13
            visible: reserveComparisonSpace || comparison !== ""

            Text {
                anchors.centerIn: parent
                text: comparison
                color: theme.textMuted
                font.family: "Adwaita Mono"
                font.pixelSize: 10
                font.weight: Font.Normal
            }
        }
    }

    component ModuleDivider: Item {
        property real lineOffsetY: 0

        implicitHeight: shell.moduleDividerHeight

        Rectangle {
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: lineOffsetY
            }
            width: parent.width
            height: 1
            color: theme.divider
        }
    }

    component ModuleFooterRow: Item {
        required property string fieldLabel
        required property string fieldValue
        property color valueTone: theme.textSecondary

        implicitHeight: Math.max(19, footerValue.implicitHeight)
        height: implicitHeight

        Text {
            id: footerLabel
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            text: fieldLabel
            color: theme.textMuted
            font.family: "Adwaita Mono"
            font.pixelSize: theme.moduleFooterLabelSize
            font.weight: Font.Medium
        }

        Text {
            id: footerValue
            anchors {
                left: footerLabel.right
                leftMargin: 8
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            horizontalAlignment: Text.AlignRight
            text: fieldValue
            color: valueTone
            font.family: "Noto Sans JP"
            font.pixelSize: theme.moduleFooterValueSize
            font.weight: Font.Normal
            wrapMode: Text.Wrap
        }
    }

    component RadarFrameLayer: Item {
        required property var frameData
        required property int setIndex
        required property int frameIndex

        width: frameData.gridColumns * frameData.tileSize * frameData.scale
        height: frameData.gridRows * frameData.tileSize * frameData.scale
        x: radarViewport.width / 2
            - frameData.centerPixelX * frameData.scale
        y: radarViewport.height / 2
            - frameData.centerPixelY * frameData.scale
        opacity: shell.radarFrameIndex === frameIndex ? 1 : 0

        Repeater {
            model: frameData.tiles

            delegate: Item {
                required property var modelData

                x: modelData.column * frameData.tileSize * frameData.scale
                y: modelData.row * frameData.tileSize * frameData.scale
                width: frameData.tileSize * frameData.scale
                height: frameData.tileSize * frameData.scale

                Image {
                    function reportStatus() {
                        if (status === Image.Ready) {
                            shell.radarTileReady(
                                setIndex,
                                modelData.generation,
                                modelData.url
                            );
                        } else if (status === Image.Error) {
                            shell.radarTileFailed(
                                setIndex,
                                modelData.generation
                            );
                        }
                    }

                    anchors.fill: parent
                    source: modelData.url
                    sourceSize.width: frameData.tileSize
                    sourceSize.height: frameData.tileSize
                    asynchronous: true
                    cache: false
                    retainWhileLoading: true
                    smooth: true
                    onStatusChanged: reportStatus()
                    Component.onCompleted: reportStatus()
                }
            }
        }
    }

    component RadarFrameSet: Item {
        id: radarFrameSet

        required property var frameSetData
        required property int setIndex

        opacity: shell.radarAvailable
            && shell.radarActiveSet === setIndex ? 1 : 0

        Repeater {
            model: frameSetData

            delegate: RadarFrameLayer {
                required property var modelData
                required property int index

                frameData: modelData
                frameIndex: index
                setIndex: radarFrameSet.setIndex
            }
        }
    }

    property real temperature: 0
    property int humidity: 0
    property int sensorBattery: -1
    property int sensorRssi: 0
    property bool sensorAvailable: false
    property bool sensorFresh: false
    readonly property int sensorDisplayUpdateIntervalMs: 30000
    property var sensorPendingReading: null
    property double sensorLastSeenMs: 0
    property double sensorLastUpdateMs: 0
    property double sensorLastDisplayCommitMs: 0
    readonly property string sensorObservedAt: sensorAvailable
            && sensorLastUpdateMs > 0
        ? Qt.formatDateTime(new Date(sensorLastUpdateMs), "HH:mm") : ""
    readonly property string sensorLinkSummary:
        (sensorBattery >= 0 ? "BAT " + sensorBattery + "%" : "BAT --")
        + " · "
        + (sensorRssi !== 0
            ? "RSSI " + (sensorRssi < 0 ? "−" + Math.abs(sensorRssi)
                : sensorRssi)
            : "RSSI --")
    property string weatherObservedAt: ""
    property string weatherState: "unknown"
    property string weatherCondition: ""
    property real weatherTemperature: 0
    property int weatherHumidity: 0
    property var hourlyForecast: []
    property string rainOutlook: ""
    property bool weatherAvailable: false
    property bool weatherFetchPending: false
    property bool weatherFetchFailed: false
    property bool weatherUpdateReceived: false
    property bool weatherFresh: false
    property double weatherLastUpdateMs: 0
    readonly property bool indoorSourceCurrent: sensorAvailable && sensorFresh
    readonly property bool outdoorSourceCurrent: weatherAvailable
        && weatherFresh && !weatherFetchFailed
    readonly property int currentEnvironmentSourceCount:
        (indoorSourceCurrent ? 1 : 0) + (outdoorSourceCurrent ? 1 : 0)
    readonly property string indoorSourceState: indoorSourceCurrent
        ? "LIVE" : sensorAvailable ? "STALE" : "NO DATA"
    readonly property color indoorSourceTone: indoorSourceCurrent
        ? theme.textSecondary
        : sensorAvailable ? theme.statusCaution : theme.statusUnknown
    readonly property string outdoorSourceState: outdoorSourceCurrent
        ? "LIVE" : weatherAvailable ? "CACHED"
        : weatherFetchFailed ? "ERROR" : "FETCHING"
    readonly property color outdoorSourceTone: outdoorSourceCurrent
        ? theme.textSecondary : weatherAvailable ? theme.statusCaution
        : weatherFetchFailed ? theme.statusError : theme.statusUnknown
    readonly property color environmentSourceTone:
        currentEnvironmentSourceCount === 2 ? theme.statusOk
        : currentEnvironmentSourceCount === 1 ? theme.statusCaution
        : sensorAvailable || weatherAvailable ? theme.statusCaution
        : weatherFetchFailed ? theme.statusError : theme.statusUnknown
    property var radarFrameSetA: []
    property var radarFrameSetB: []
    property int radarActiveSet: -1
    property int radarPendingSet: -1
    property int radarPendingGeneration: 0
    property int radarPendingTileCount: 0
    property var radarPendingReadyUrls: ({})
    property double radarPendingReferenceEpoch: 0
    property double radarPendingCycleEpochMs: 0
    property int radarPendingAttemptOffsetSeconds: -1
    property var radarPendingNearbyPrecipitation: null
    property double radarReferenceEpoch: 0
    property bool radarNearbyPrecipitation: false
    property int radarNearbyDrySamples: 0
    property double radarNearbyLastSampleReferenceEpoch: 0
    property int radarFrameIndex: 0
    readonly property var radarActiveFrames: radarActiveSet === 0
        ? radarFrameSetA : radarActiveSet === 1 ? radarFrameSetB : []
    readonly property var radarDisplayedFrame: radarFrameIndex >= 0
            && radarFrameIndex < radarActiveFrames.length
        ? radarActiveFrames[radarFrameIndex] : null
    readonly property real radarMetersPerPixel: radarDisplayedFrame !== null
        ? radarDisplayedFrame.metersPerPixel : 1
    readonly property string radarFrameAt: radarDisplayedFrame !== null
        ? radarDisplayedFrame.frameAt : ""
    property bool radarAvailable: false
    property bool radarFetchFailed: false
    property bool radarRetrying: false
    property bool radarIncludeAnimationFrames: false
    property bool radarUpdateReceived: false
    property double radarResponseReferenceEpoch: 0
    property bool radarResponseHasForecast: false
    property bool radarRequestTileFailed: false
    property bool radarImmediateFetchPending: false
    property double radarRequestCycleEpochMs: 0
    property int radarRequestAttemptOffsetSeconds: -1
    property double radarScheduledCycleEpochMs: 0
    property int radarScheduledAttemptOffsetSeconds: 50
    property double radarLastLoggedReferenceEpoch: 0
    readonly property int radarCycleDurationMs: 5 * 60 * 1000
    readonly property var radarAttemptOffsetsSeconds: [50, 110, 170, 230]
    readonly property int radarForecastEnrichmentOffsetSeconds: 170
    readonly property int radarNearbyDryReleaseSamples: 2
    readonly property int radarMinimumViewportHeight: 192
    readonly property int radarViewportHeight: Math.max(
        radarMinimumViewportHeight,
        Math.round(radarWindow.height) - panelBottomInset * 2
            - radarHeaderHeight - moduleDividerHeight
    )
    readonly property int radarViewWidthKm: radarAvailable
        ? Math.round(panelContentWidth * radarMetersPerPixel / 1000) : 0
    readonly property int radarViewHeightKm: radarAvailable
        ? Math.round(radarViewportHeight * radarMetersPerPixel / 1000) : 0
    readonly property string radarViewSummary: radarAvailable
        ? "VIEW " + radarViewWidthKm + "×"
            + radarViewHeightKm + " KM"
        : "VIEW --"
    readonly property color radarSourceTone: !radarAvailable
        ? (radarFetchFailed ? theme.statusError : theme.statusUnknown)
        : radarFetchFailed || radarRetrying
        ? theme.statusCaution : theme.statusOk
    readonly property string radarFrameStatusText: radarAvailable
        ? radarFrameLabel() : radarFetchFailed ? "NO FRAME" : "WAITING FOR FRAME"

    function weatherSymbol(state) {
        switch (state) {
        case "thunder":
        case "storm":
            return "\uebdb";
        case "snow":
        case "sleet":
        case "blizzard":
            return "\ue2cd";
        case "light_rain":
        case "rain":
            return "\uf176";
        case "fog":
            return "\ue818";
        case "sunny":
        case "extreme_heat":
            return "\ue81a";
        case "cloudy":
            return "\uf15c";
        default:
            return "\uf172";
        }
    }

    function weatherColor(state) {
        if (state === "thunder" || state === "storm")
            return theme.weatherThunder;
        if (state === "snow" || state === "blizzard")
            return theme.weatherSnow;
        if (state === "sleet")
            return theme.weatherSleet;
        if (state === "light_rain")
            return theme.weatherLightRain;
        if (state === "rain")
            return theme.weatherRain;
        if (state === "fog")
            return theme.weatherFog;
        if (state === "extreme_heat")
            return theme.weatherExtremeHeat;
        if (state === "sunny")
            return theme.weatherSunny;
        if (state === "cloudy")
            return theme.weatherCloudy;
        return theme.weatherUnknown;
    }

    function forecastDisplayState(forecast) {
        if (forecast.precipitation > 0
                && forecast.state !== "snow"
                && forecast.state !== "sleet"
                && forecast.state !== "blizzard"
                && forecast.state !== "storm")
            return "rain";
        return forecast.state;
    }

    function forecastSymbol(forecast) {
        return weatherSymbol(forecastDisplayState(forecast));
    }

    function forecastColor(forecast) {
        return weatherColor(forecastDisplayState(forecast));
    }

    function forecastNumber(value) {
        const rounded = Math.round(value * 10) / 10;
        return Math.abs(rounded - Math.round(rounded)) < 0.01
            ? Math.round(rounded).toString()
            : rounded.toFixed(1);
    }

    function precipitationColor(value) {
        if (value < 1)
            return theme.precipitationTrace;
        if (value < 5)
            return theme.precipitationLight;
        if (value < 10)
            return theme.precipitationModerate;
        if (value < 20)
            return theme.precipitationHeavy;
        if (value < 30)
            return theme.precipitationVeryHeavy;
        if (value < 50)
            return theme.precipitationIntense;
        if (value < 80)
            return theme.precipitationSevere;
        return theme.precipitationExtreme;
    }

    function differenceValue(indoor, outdoor, decimals) {
        const factor = Math.pow(10, decimals);
        return Math.round((indoor - outdoor) * factor) / factor;
    }

    function differenceText(indoor, outdoor, decimals) {
        const difference = differenceValue(indoor, outdoor, decimals);
        const magnitude = Math.abs(difference).toFixed(decimals);
        if (difference === 0)
            return "±" + magnitude;
        return (difference > 0 ? "+" : "−") + magnitude;
    }

    function applySensorReading(reading) {
        temperature = reading.temperature;
        humidity = reading.humidity;
        sensorBattery = reading.battery;
        sensorRssi = reading.rssi;
        sensorLastUpdateMs = reading.timestamp * 1000;
        sensorLastDisplayCommitMs = Date.now();
        sensorPendingReading = null;
        sensorAvailable = true;
    }

    function updateSensor(line) {
        try {
            const reading = JSON.parse(line);
            if (typeof reading.temperature !== "number"
                    || typeof reading.humidity !== "number"
                    || typeof reading.timestamp !== "number")
                return;

            const normalizedReading = {
                temperature: reading.temperature,
                humidity: reading.humidity,
                battery: typeof reading.battery === "number"
                        && reading.battery >= 0 && reading.battery <= 100
                    ? Math.round(reading.battery) : -1,
                rssi: typeof reading.rssi === "number"
                    ? Math.round(reading.rssi) : 0,
                timestamp: reading.timestamp
            };
            const receivedAt = Date.now();

            sensorLastSeenMs = reading.timestamp * 1000;
            sensorFresh = true;

            const displayUpdateDue = !sensorAvailable
                || sensorLastDisplayCommitMs <= 0
                || receivedAt - sensorLastDisplayCommitMs
                    >= sensorDisplayUpdateIntervalMs;
            if (displayUpdateDue) {
                sensorDisplayTimer.stop();
                applySensorReading(normalizedReading);
                return;
            }

            sensorPendingReading = normalizedReading;
            if (!sensorDisplayTimer.running) {
                sensorDisplayTimer.interval = Math.max(1,
                    sensorDisplayUpdateIntervalMs
                        - (receivedAt - sensorLastDisplayCommitMs));
                sensorDisplayTimer.start();
            }
        } catch (error) {
            console.warn("Invalid SwitchBot reading:", error);
        }
    }

    function updateHolidays(line) {
        try {
            const data = JSON.parse(line);
            if (data === null || typeof data.holidays !== "object"
                    || Array.isArray(data.holidays))
                return;

            const holidays = {};
            for (const key of Object.keys(data.holidays)) {
                const name = data.holidays[key];
                if (/^\d{4}-\d{2}-\d{2}$/.test(key)
                        && typeof name === "string" && name !== "")
                    holidays[key] = name;
            }
            holidayEntries = holidays;
            holidayDataAvailable = Object.keys(holidays).length > 0;
            holidayDataStale = data.stale === true;
        } catch (error) {
            console.warn("Invalid Japanese holiday data:", error);
        }
    }

    function updateWeather(line) {
        try {
            const observation = JSON.parse(line);
            if (typeof observation.observed_at !== "string"
                    || typeof observation.condition !== "string"
                    || typeof observation.temperature !== "number"
                    || typeof observation.humidity !== "number")
                return;

            const radarWasActive = radarRainDetected();
            weatherObservedAt = observation.observed_at;
            weatherState = typeof observation.state === "string"
                ? observation.state
                : "unknown";
            weatherCondition = observation.condition;
            weatherTemperature = observation.temperature;
            weatherHumidity = observation.humidity;
            hourlyForecast = Array.isArray(observation.hourly_forecast)
                ? observation.hourly_forecast.filter(forecast =>
                    forecast !== null
                        && typeof forecast.hour === "string"
                        && typeof forecast.state === "string"
                        && typeof forecast.temperature === "number"
                        && typeof forecast.precipitation === "number"
                ).slice(0, 5)
                : [];
            rainOutlook = typeof observation.rain_outlook === "string"
                ? observation.rain_outlook
                : "";
            weatherUpdateReceived = true;
            weatherAvailable = true;
            weatherFresh = true;
            weatherLastUpdateMs = Date.now();
            weatherFetchFailed = false;
            syncRadarAnimation(true);
            if (radarWasActive !== radarRainDetected())
                requestRadarRefreshNow();
        } catch (error) {
            console.warn("Invalid Weathernews observation:", error);
        }
    }

    function observedWeatherIsRain() {
        return weatherAvailable
            && (weatherState === "light_rain"
                || weatherState === "rain"
                || weatherState === "storm"
                || weatherCondition.indexOf("雨") !== -1);
    }

    function radarRainDetected() {
        return observedWeatherIsRain() || radarNearbyPrecipitation;
    }

    function applyRadarNearbyPrecipitation(value, referenceEpoch) {
        if (value === null
                || referenceEpoch <= radarNearbyLastSampleReferenceEpoch)
            return;

        radarNearbyLastSampleReferenceEpoch = referenceEpoch;
        const wasNearby = radarNearbyPrecipitation;
        if (value) {
            radarNearbyPrecipitation = true;
            radarNearbyDrySamples = 0;
        } else if (radarNearbyPrecipitation) {
            radarNearbyDrySamples++;
            if (radarNearbyDrySamples >= radarNearbyDryReleaseSamples) {
                radarNearbyPrecipitation = false;
                radarNearbyDrySamples = 0;
            }
        } else {
            radarNearbyDrySamples = 0;
        }

        if (wasNearby !== radarNearbyPrecipitation) {
            console.info(
                "Rain radar nearby precipitation:",
                radarNearbyPrecipitation ? "detected" : "clear"
            );
        }
    }

    function currentRadarFrameIndex(frames) {
        for (let index = 0; index < frames.length; index++) {
            if (frames[index].offsetMinutes === 0)
                return index;
        }
        return 0;
    }

    function syncRadarAnimation(resetSequence) {
        const shouldAnimate = radarAvailable
            && radarRainDetected()
            && radarActiveFrames.length > 1;

        if (resetSequence || !shouldAnimate)
            radarFrameIndex = shouldAnimate
                ? 0 : currentRadarFrameIndex(radarActiveFrames);

        if (shouldAnimate) {
            if (resetSequence || !radarAnimationTimer.running)
                radarAnimationTimer.restart();
        } else {
            radarAnimationTimer.stop();
        }
    }

    function radarFrameLabel() {
        if (!radarAvailable || radarDisplayedFrame === null)
            return "";
        return radarTimeframeLabel(radarDisplayedFrame) + " · "
            + radarFrameAt;
    }

    function radarTimeframeLabel(frame) {
        return radarTimeframeLabelForOffset(frame.offsetMinutes);
    }

    function radarTimeframeLabelForOffset(offsetMinutes) {
        if (offsetMinutes > 0)
            return "IN " + offsetMinutes + " MIN";
        if (offsetMinutes < 0)
            return Math.abs(offsetMinutes) + " MIN AGO";
        return "NOW";
    }

    function radarFrameForOffset(offsetMinutes) {
        for (const frame of radarActiveFrames) {
            if (frame.offsetMinutes === offsetMinutes)
                return frame;
        }
        return null;
    }

    function radarFramesAddInformation(candidateFrames, existingFrames) {
        for (const candidate of candidateFrames) {
            let alreadyPresent = false;
            for (const existing of existingFrames) {
                if (candidate.offsetMinutes === existing.offsetMinutes) {
                    alreadyPresent = true;
                    break;
                }
            }
            if (!alreadyPresent)
                return true;
        }
        return false;
    }

    function updateRadar(line) {
        try {
            const radar = JSON.parse(line);
            if (typeof radar.reference_time !== "number"
                    || typeof radar.tile_size !== "number"
                    || typeof radar.radar_scale !== "number"
                    || typeof radar.grid_columns !== "number"
                    || typeof radar.grid_rows !== "number"
                    || typeof radar.meters_per_pixel !== "number"
                    || typeof radar.radar_center_pixel_x !== "number"
                    || typeof radar.radar_center_pixel_y !== "number"
                    || (radar.nearby_precipitation !== null
                        && typeof radar.nearby_precipitation !== "boolean")
                    || !Array.isArray(radar.frames))
                return;

            const generation = radarPendingGeneration + 1;
            const pendingFrames = [];
            let pendingTileCount = 0;
            let hasCurrentFrame = false;

            for (const frame of radar.frames) {
                if (frame === null
                        || typeof frame.frame_time !== "number"
                        || typeof frame.offset_minutes !== "number"
                        || typeof frame.forecast !== "boolean"
                        || !Array.isArray(frame.radar_tiles))
                    continue;

                const frameDate = new Date(frame.frame_time * 1000);
                if (isNaN(frameDate.getTime()))
                    continue;

                const pendingTiles = frame.radar_tiles.filter(tile =>
                    tile !== null
                        && typeof tile.column === "number"
                        && typeof tile.row === "number"
                        && typeof tile.url === "string"
                ).map(tile => ({
                    column: tile.column,
                    row: tile.row,
                    url: tile.url,
                    generation: generation
                }));
                if (pendingTiles.length < 1)
                    continue;

                pendingTileCount += pendingTiles.length;
                hasCurrentFrame = hasCurrentFrame
                    || frame.offset_minutes === 0;
                pendingFrames.push({
                    tiles: pendingTiles,
                    tileSize: radar.tile_size,
                    scale: radar.radar_scale,
                    gridColumns: radar.grid_columns,
                    gridRows: radar.grid_rows,
                    centerPixelX: radar.radar_center_pixel_x,
                    centerPixelY: radar.radar_center_pixel_y,
                    metersPerPixel: radar.meters_per_pixel,
                    frameAt: Qt.formatDateTime(frameDate, "M/d HH:mm"),
                    offsetMinutes: frame.offset_minutes,
                    forecast: frame.forecast
                });
            }
            if (!hasCurrentFrame || pendingFrames.length < 1)
                return;

            radarUpdateReceived = true;
            radarResponseReferenceEpoch = radar.reference_time;
            radarResponseHasForecast = pendingFrames.some(frame =>
                frame.forecast
            );
            pendingFrames.sort((left, right) =>
                left.offsetMinutes - right.offsetMinutes
            );

            const pendingFrameSet = radarPendingSet === 0
                ? radarFrameSetA : radarPendingSet === 1
                    ? radarFrameSetB : [];
            const candidateOlderThanActive = radarAvailable
                && radar.reference_time < radarReferenceEpoch;
            const activeAlreadyHasFrames = radarAvailable
                && radar.reference_time === radarReferenceEpoch
                && (radarIncludeAnimationFrames
                    ? !radarFramesAddInformation(
                        pendingFrames, radarActiveFrames
                    ) : radarActiveFrames.length === 1);
            const candidateOlderThanPending = radarPendingSet !== -1
                && radar.reference_time < radarPendingReferenceEpoch;
            const pendingAlreadyHasFrames = radarPendingSet !== -1
                && radar.reference_time === radarPendingReferenceEpoch
                && (radarIncludeAnimationFrames
                    ? !radarFramesAddInformation(
                        pendingFrames, pendingFrameSet
                    ) : pendingFrameSet.length === 1);
            if (candidateOlderThanActive || activeAlreadyHasFrames
                    || candidateOlderThanPending || pendingAlreadyHasFrames) {
                radarFetchFailed = false;
                return;
            }

            const pendingSet = radarAvailable
                && radarActiveSet === 0 ? 1 : 0;

            radarPendingGeneration = generation;
            radarPendingSet = pendingSet;
            radarPendingTileCount = pendingTileCount;
            radarPendingReadyUrls = {};
            radarPendingReferenceEpoch = radar.reference_time;
            radarPendingCycleEpochMs = radarRequestCycleEpochMs;
            radarPendingAttemptOffsetSeconds =
                radarRequestAttemptOffsetSeconds;
            radarPendingNearbyPrecipitation =
                radar.nearby_precipitation;
            if (pendingSet === 0)
                radarFrameSetA = pendingFrames;
            else
                radarFrameSetB = pendingFrames;
        } catch (error) {
            console.warn("Invalid JMA nowcast data:", error);
        }
    }

    function radarTileReady(setIndex, generation, url) {
        if (setIndex !== radarPendingSet
                || generation !== radarPendingGeneration
                || radarPendingReadyUrls[url] === true)
            return;

        const readyUrls = {};
        for (const readyUrl in radarPendingReadyUrls)
            readyUrls[readyUrl] = true;
        readyUrls[url] = true;
        radarPendingReadyUrls = readyUrls;

        if (Object.keys(readyUrls).length !== radarPendingTileCount)
            return;

        radarReferenceEpoch = radarPendingReferenceEpoch;
        applyRadarNearbyPrecipitation(
            radarPendingNearbyPrecipitation,
            radarReferenceEpoch
        );
        radarActiveSet = setIndex;
        if (setIndex === 0)
            radarFrameSetB = [];
        else
            radarFrameSetA = [];
        radarPendingSet = -1;
        radarPendingTileCount = 0;
        radarPendingReadyUrls = {};
        radarPendingReferenceEpoch = 0;
        radarPendingCycleEpochMs = 0;
        radarPendingAttemptOffsetSeconds = -1;
        radarPendingNearbyPrecipitation = null;
        radarAvailable = true;
        radarFetchFailed = false;
        syncRadarAnimation(true);
    }

    function radarTileFailed(setIndex, generation) {
        if (setIndex !== radarPendingSet
                || generation !== radarPendingGeneration)
            return;

        const failedCycleEpochMs = radarPendingCycleEpochMs;
        const failedAttemptOffsetSeconds =
            radarPendingAttemptOffsetSeconds;
        radarPendingSet = -1;
        radarPendingTileCount = 0;
        radarPendingReadyUrls = {};
        radarPendingReferenceEpoch = 0;
        radarPendingCycleEpochMs = 0;
        radarPendingAttemptOffsetSeconds = -1;
        radarPendingNearbyPrecipitation = null;
        radarFetchFailed = true;
        radarRequestTileFailed = true;
        console.warn("Rain radar tile load failed; retrying");
        if (failedCycleEpochMs > 0) {
            scheduleRadarRetryForCycle(
                failedCycleEpochMs,
                failedAttemptOffsetSeconds
            );
        } else {
            scheduleNextRadarCycle();
        }
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

    PanelWindow {
        id: clockWindow
        visible: shell.widgetsVisible

        anchors {
            top: true
            right: true
        }

        margins {
            top: 12
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: clockContent.implicitHeight + 28
        color: "transparent"
        exclusiveZone: 0
        focusable: false
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: theme.panelBackground
            border.width: 0

            PanelEdge {
                anchors.fill: parent
            }

            Item {
                anchors {
                    top: parent.top
                    topMargin: 10
                    horizontalCenter: parent.horizontalCenter
                }
                width: shell.panelContentWidth
                height: 24

                UI.ModuleHeaderRail {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    tone: shell.localTimeSourceTone
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "LOCAL TIME"
                    color: theme.textPrimary
                    font.family: "Adwaita Mono"
                    font.pixelSize: 17
                    font.weight: Font.Medium
                }

                Text {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: shell.currentTimeZoneLabel
                    color: theme.textMuted
                    font.family: "Adwaita Mono"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
            }

            ModuleDivider {
                anchors {
                    top: parent.top
                    topMargin: 34
                    horizontalCenter: parent.horizontalCenter
                }
                width: shell.panelContentWidth
                height: implicitHeight
            }

            Column {
                id: clockContent
                anchors {
                    bottom: parent.bottom
                    bottomMargin: shell.panelBottomInset
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: -2

                Row {
                    id: timeRow
                    spacing: 8
                    transform: Translate { y: 8 }

                    Text {
                        id: hourText
                        text: Qt.formatDateTime(clock.date, "HH")
                        color: theme.textPrimary
                        font.family: "Adwaita Mono"
                        font.pixelSize: 90
                        font.weight: Font.Normal
                    }

                    Item {
                        width: 16
                        height: hourText.implicitHeight

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 0
                            color: theme.textPrimary
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                verticalCenter: parent.verticalCenter
                                verticalCenterOffset: -18
                            }
                        }

                        Rectangle {
                            width: 8
                            height: 8
                            radius: 0
                            color: theme.textPrimary
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                verticalCenter: parent.verticalCenter
                                verticalCenterOffset: 11
                            }
                        }
                    }

                    Item {
                        implicitWidth: minuteText.implicitWidth + 2 + secondText.implicitWidth
                        implicitHeight: minuteText.implicitHeight

                        Text {
                            id: minuteText
                            anchors.left: parent.left
                            text: Qt.formatDateTime(clock.date, "mm")
                            color: theme.textPrimary
                            font.family: "Adwaita Mono"
                            font.pixelSize: 90
                            font.weight: Font.Normal
                        }

                        Text {
                            id: secondText
                            anchors {
                                left: minuteText.right
                                leftMargin: 2
                                baseline: minuteText.baseline
                            }
                            text: Qt.formatDateTime(clock.date, "ss")
                            color: theme.textPrimary
                            font.family: "Adwaita Mono"
                            font.pixelSize: 32
                            font.weight: Font.Normal
                        }
                    }
                }

                Text {
                    width: timeRow.width
                    horizontalAlignment: Text.AlignHCenter
                    text: shell.currentDateLabel
                    color: theme.textPrimary
                    font.family: "Adwaita Mono"
                    font.pixelSize: 18
                    font.weight: Font.Normal
                }
            }
        }
    }

    PanelWindow {
        id: calendarWindow
        visible: shell.widgetsVisible

        anchors {
            top: true
            right: true
        }

        margins {
            top: clockWindow.margins.top + clockWindow.implicitHeight
                + shell.panelGap
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: calendarContent.implicitHeight + 22
        color: "transparent"
        exclusiveZone: 0
        focusable: false
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: theme.panelBackground
            border.width: 0

            PanelEdge {
                anchors.fill: parent
            }

            Column {
                id: calendarContent
                anchors {
                    bottom: parent.bottom
                    bottomMargin: shell.panelBottomInset
                    horizontalCenter: parent.horizontalCenter
                }
                width: shell.panelContentWidth
                spacing: 0

                Item {
                    width: parent.width
                    height: 31

                    UI.ModuleHeaderRail {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -6
                        }
                        tone: shell.calendarSourceTone
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -6
                        }
                        text: "CALENDAR"
                        color: theme.textPrimary
                        font.family: "Adwaita Mono"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Column {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -6
                        }
                        width: 150
                        spacing: -1

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: shell.currentYear + " / "
                                + shell.padded(shell.currentMonth)
                            color: theme.textSecondary
                            font.family: "Adwaita Mono"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            text: "ISO W" + shell.currentIsoWeek + " · DAY "
                                + shell.currentDayOfYear + "/"
                                + shell.currentYearLength
                            color: theme.textMuted
                            font.family: "Adwaita Mono"
                            font.pixelSize: 9
                            font.weight: Font.Normal
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                    lineOffsetY: -8
                }

                Item {
                    width: parent.width
                    height: 19

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width

                        Repeater {
                            model: shell.calendarWeekdayLabels

                            delegate: Text {
                                required property int index
                                required property string modelData

                                width: calendarContent.width / 7
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData
                                color: index === 0
                                    ? theme.calendarSundayHoliday
                                    : index === 6 ? theme.calendarSaturday
                                    : theme.textSecondary
                                font.family: "Adwaita Mono"
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        z: 1

                        Repeater {
                            model: 8

                            delegate: Rectangle {
                                required property int index

                                x: index === 7
                                    ? parent.width - 1
                                    : Math.round(index * parent.width / 7)
                                width: 1
                                height: parent.height
                                color: theme.calendarGridVertical
                            }
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: calendarGrid.height

                    Grid {
                        id: calendarGrid

                        property var cells: shell.calendarCells()
                        property int weekCount: Math.ceil(cells.length / 7)
                        property int cellHeight: 26

                        width: parent.width
                        height: weekCount * cellHeight
                            + Math.max(0, weekCount - 1) * rowSpacing
                        columns: 7
                        rowSpacing: 1

                        Repeater {
                            model: calendarGrid.cells

                            delegate: Item {
                                required property var modelData

                                width: calendarContent.width / 7
                                height: calendarGrid.cellHeight

                                Rectangle {
                                    anchors.fill: parent
                                    visible: modelData.isToday
                                    radius: 0
                                    color: theme.calendarTodayFill
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.day
                                    color: shell.calendarDayColor(modelData)
                                    font.family: "Adwaita Sans"
                                    font.pixelSize: 15
                                    font.weight: modelData.isToday
                                        ? Font.Medium : Font.Normal
                                }
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        z: 1

                        Repeater {
                            model: 8

                            delegate: Rectangle {
                                required property int index

                                x: index === 7
                                    ? parent.width - 1
                                    : Math.round(index * parent.width / 7)
                                width: 1
                                height: parent.height
                                color: theme.calendarGridVertical
                            }
                        }

                        Repeater {
                            model: calendarGrid.weekCount

                            delegate: Rectangle {
                                required property int index

                                y: index === 0 ? 0
                                    : index * (calendarGrid.cellHeight
                                        + calendarGrid.rowSpacing) - 1
                                width: parent.width
                                height: 1
                                color: theme.calendarGridHorizontal
                            }
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                }

                ModuleFooterRow {
                    width: parent.width
                    fieldLabel: shell.nextHolidaySummary.label
                    fieldValue: shell.nextHolidaySummary.value
                        + (shell.nextHolidaySummary.countdown !== ""
                            ? " · " + shell.nextHolidaySummary.countdown
                            : "")
                    valueTone: shell.nextHolidaySummary.known
                        ? theme.textSecondary : theme.textDisabled
                }
            }
        }
    }

    PanelWindow {
        id: weatherWindow
        visible: shell.widgetsVisible

        anchors {
            top: true
            right: true
        }

        margins {
            top: calendarWindow.margins.top + calendarWindow.implicitHeight
                + shell.panelGap
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: weatherContent.implicitHeight + 20
        color: "transparent"
        exclusiveZone: 0
        focusable: false
        mask: Region {}

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: theme.panelBackground
            border.width: 0

            PanelEdge {
                anchors.fill: parent
            }

            Column {
                id: weatherContent
                anchors {
                    bottom: parent.bottom
                    bottomMargin: shell.panelBottomInset
                    horizontalCenter: parent.horizontalCenter
                }
                width: shell.panelContentWidth
                spacing: 0

                Item {
                    width: parent.width
                    height: 24

                    UI.ModuleHeaderRail {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        tone: shell.environmentSourceTone
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: "ENVIRONMENT"
                        color: theme.textPrimary
                        font.family: "Adwaita Mono"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        text: "BLE · WEATHERNEWS"
                        color: theme.textMuted
                        font.family: "Adwaita Mono"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                    }
                }

                ModuleDivider {
                    width: parent.width
                }

                Column {
                    width: parent.width
                    spacing: 0

                    UI.SectionHeader {
                        width: parent.width
                        palette: theme
                        label: "INDOOR"
                        healthMarkerVisible: true
                        healthTone: shell.indoorSourceCurrent
                            ? theme.statusOk : shell.indoorSourceTone
                        metadata: shell.sensorLinkSummary
                        metadataVisible: shell.indoorSourceCurrent
                        statusActive: !shell.indoorSourceCurrent
                        statusLabel: shell.indoorSourceState
                            + (shell.sensorObservedAt !== ""
                                ? " · AS OF " + shell.sensorObservedAt
                                : "")
                        statusTone: shell.indoorSourceTone
                    }

                    Row {
                        width: parent.width

                        EnvironmentMetric {
                            width: parent.width / 2
                            label: "TEMP"
                            valueText: shell.indoorSourceCurrent
                                ? shell.temperature.toFixed(1) : "--.-"
                            unitText: "°C"
                            comparison: shell.indoorSourceCurrent
                                    && shell.outdoorSourceCurrent
                                ? "OUT Δ "
                                    + shell.differenceText(
                                        shell.temperature,
                                        shell.weatherTemperature,
                                        1
                                    ) + "°"
                                : ""
                        }

                        EnvironmentMetric {
                            width: parent.width / 2
                            label: "HUMIDITY"
                            valueText: shell.indoorSourceCurrent
                                ? shell.humidity.toString() : "--"
                            unitText: "%"
                            comparison: shell.indoorSourceCurrent
                                    && shell.outdoorSourceCurrent
                                ? "OUT Δ "
                                    + shell.differenceText(
                                        shell.humidity,
                                        shell.weatherHumidity,
                                        0
                                    ) + "%"
                                : ""
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                }

                Column {
                    width: parent.width
                    spacing: 0

                    UI.SectionHeader {
                        width: parent.width
                        palette: theme
                        label: "OUTDOOR"
                        healthMarkerVisible: true
                        healthTone: shell.outdoorSourceCurrent
                            ? theme.statusOk : shell.outdoorSourceTone
                        metadata: "OBS " + shell.weatherObservedAt
                        metadataVisible: shell.outdoorSourceCurrent
                        statusActive: !shell.outdoorSourceCurrent
                        statusLabel: shell.outdoorSourceState
                            + (shell.weatherAvailable
                                ? " · OBS " + shell.weatherObservedAt
                                : "")
                        statusTone: shell.outdoorSourceTone
                    }

                    Row {
                        width: parent.width

                        Column {
                            width: 80
                            spacing: -1

                            Item {
                                width: parent.width
                                height: 11

                                Text {
                                    anchors.centerIn: parent
                                    text: "CONDITION"
                                    color: theme.textMuted
                                    font.family: "Adwaita Mono"
                                    font.pixelSize: 9
                                    font.weight: Font.Medium
                                }
                            }

                            Item {
                                width: parent.width
                                height: 31

                                Text {
                                    anchors.centerIn: parent
                                    text: shell.weatherAvailable
                                        ? shell.weatherSymbol(shell.weatherState)
                                        : "\uf172"
                                    color: shell.weatherAvailable
                                        ? shell.weatherColor(shell.weatherState)
                                        : theme.textDisabled
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 28
                                    font.weight: Font.Normal
                                }
                            }

                        }

                        EnvironmentMetric {
                            width: 100
                            label: "TEMP"
                            reserveComparisonSpace: false
                            valueText: shell.weatherAvailable
                                ? shell.weatherTemperature.toFixed(1) : "--.-"
                            unitText: "°C"
                            valueColor: shell.weatherAvailable
                                ? theme.textPrimary : theme.textDisabled
                            unitColor: shell.weatherAvailable
                                ? theme.textSecondary : theme.textDisabled
                        }

                        EnvironmentMetric {
                            width: 100
                            label: "HUMIDITY"
                            reserveComparisonSpace: false
                            valueText: shell.weatherAvailable
                                ? shell.weatherHumidity.toString() : "--"
                            unitText: "%"
                            valueColor: shell.weatherAvailable
                                ? theme.textPrimary : theme.textDisabled
                            unitColor: shell.weatherAvailable
                                ? theme.textSecondary : theme.textDisabled
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                    visible: forecastBlock.visible
                }

                Column {
                    id: forecastBlock
                    width: parent.width
                    visible: shell.hourlyForecast.length > 0
                    spacing: 0

                    Item {
                        width: parent.width
                        height: 19

                        Text {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                            }
                            text: "NEXT 5 HOURS"
                            color: theme.textMuted
                            font.family: "Adwaita Mono"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }

                        Text {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            text: "PRECIP / TEMP"
                            color: theme.textTertiary
                            font.family: "Adwaita Mono"
                            font.pixelSize: 9
                            font.weight: Font.Normal
                        }
                    }

                    Row {
                        width: parent.width

                        Repeater {
                            model: shell.hourlyForecast

                            delegate: Item {
                                required property int index
                                required property var modelData

                                width: weatherContent.width / 5
                                height: forecastCell.implicitHeight

                                Column {
                                    id: forecastCell

                                    width: parent.width
                                    spacing: 0

                                    Text {
                                        width: parent.width
                                        horizontalAlignment:
                                            Text.AlignHCenter
                                        text: modelData.hour
                                        color: theme.textPrimary
                                        font.family: "Adwaita Mono"
                                        font.pixelSize: 13
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment:
                                            Text.AlignHCenter
                                        text: shell.forecastSymbol(modelData)
                                        color: shell.forecastColor(modelData)
                                        font.family:
                                            "Material Symbols Rounded"
                                        font.pixelSize: 25
                                        font.weight: Font.Normal
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: theme.divider
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment:
                                            Text.AlignHCenter
                                        text: shell.forecastNumber(
                                            modelData.precipitation
                                        ) + "mm"
                                        color: shell.precipitationColor(
                                            modelData.precipitation
                                        )
                                        font.family: "Adwaita Sans"
                                        font.pixelSize: 13
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: theme.divider
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment:
                                            Text.AlignHCenter
                                        text: shell.forecastNumber(
                                            modelData.temperature
                                        ) + "°"
                                        color: theme.textPrimary
                                        font.family: "Adwaita Sans"
                                        font.pixelSize: 17
                                    }
                                }

                                Rectangle {
                                    anchors {
                                        top: parent.top
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    visible: index
                                        < shell.hourlyForecast.length - 1
                                    width: 1
                                    color: theme.divider
                                }
                            }
                        }
                    }
                }

                ModuleDivider {
                    width: parent.width
                    visible: rainOutlookRow.visible
                }

                ModuleFooterRow {
                    id: rainOutlookRow
                    width: parent.width
                    visible: shell.rainOutlook !== ""
                    fieldLabel: "RAIN OUTLOOK"
                    fieldValue: shell.rainOutlook
                }
            }
        }
    }

    PanelWindow {
        id: radarWindow
        visible: shell.widgetsVisible

        anchors {
            top: true
            bottom: true
            right: true
        }

        margins {
            top: weatherWindow.margins.top + weatherWindow.height
                + shell.panelGap
            bottom: 12
            right: 12
        }

        implicitWidth: shell.widgetWidth
        color: "transparent"
        exclusiveZone: 0
        focusable: false
        mask: Region {
            item: jmaNowcastLink
        }

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: theme.panelBackground
            border.width: 0

            PanelEdge {
                anchors.fill: parent
            }

            Column {
                anchors {
                    bottom: parent.bottom
                    bottomMargin: shell.panelBottomInset
                    horizontalCenter: parent.horizontalCenter
                }
                width: shell.panelContentWidth
                spacing: 0

                Item {
                    width: parent.width
                    height: shell.radarHeaderHeight

                    UI.ModuleHeaderRail {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -4
                        }
                        tone: shell.radarSourceTone
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -4
                        }
                        text: "RAIN RADAR"
                        color: theme.textPrimary
                        font.family: "Adwaita Mono"
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }

                    Text {
                        width: 150
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            verticalCenterOffset: -4
                        }
                        horizontalAlignment: Text.AlignRight
                        text: shell.radarFrameStatusText
                        color: theme.textSecondary
                        font.family: "Adwaita Mono"
                        font.pixelSize: theme.observationMetadataSize
                        font.weight: Font.Normal
                    }
                }

                ModuleDivider {
                    width: parent.width
                    lineOffsetY: -6
                }

                Rectangle {
                    id: radarViewport
                    width: parent.width
                    height: shell.radarViewportHeight
                    color: theme.radarBackground
                    clip: true

                    RadarFrameSet {
                        anchors.fill: parent
                        frameSetData: shell.radarFrameSetA
                        setIndex: 0
                    }

                    RadarFrameSet {
                        anchors.fill: parent
                        frameSetData: shell.radarFrameSetB
                        setIndex: 1
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: shell.radarAvailable
                        width: parent.width
                        height: 1
                        color: theme.radarGrid
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: shell.radarAvailable
                        width: 1
                        height: parent.height
                        color: theme.radarGrid
                    }

                    Repeater {
                        model: [2000, 5000]

                        delegate: Rectangle {
                            required property int modelData

                            anchors.centerIn: radarViewport
                            visible: shell.radarAvailable
                            width: modelData * 2 / shell.radarMetersPerPixel
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: theme.radarRangeRing
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !shell.radarAvailable
                        text: shell.radarFetchFailed
                            ? "RADAR UNAVAILABLE" : "FETCHING RADAR…"
                        color: theme.radarUnavailableText
                        font.family: "Adwaita Mono"
                        font.pixelSize: 13
                    }

                    Text {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            leftMargin: 5
                            bottomMargin: 3
                        }
                        visible: shell.radarAvailable
                        text: shell.radarViewSummary + " · RANGE 2 / 5 KM"
                        color: theme.textTertiary
                        font.family: "Adwaita Mono"
                        font.pixelSize: 8
                    }

                    Text {
                        id: jmaNowcastLink

                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                            rightMargin: 5
                            bottomMargin: 3
                        }
                        textFormat: Text.StyledText
                        text: "<a href='https://www.jma.go.jp/bosai/nowc/'>JMA NOWCAST</a>"
                        color: theme.textTertiary
                        linkColor: theme.textMuted
                        font.family: "Adwaita Mono"
                        font.pixelSize: 8
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }

                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        visible: shell.radarAvailable
                        height: 22
                        color: theme.radarTelemetryBackground
                        z: 2

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            height: 1
                            color: theme.radarGrid
                        }

                        Row {
                            id: radarTimelineSegments

                            anchors.fill: parent

                            Repeater {
                                model: [-5, 0, 5]

                                delegate: Item {
                                    required property int index
                                    required property int modelData

                                    width: radarTimelineSegments.width / 3
                                    height: radarTimelineSegments.height

                                    readonly property var frameData:
                                        shell.radarFrameForOffset(modelData)
                                    readonly property bool available:
                                        frameData !== null
                                    readonly property string label:
                                        shell.radarTimeframeLabelForOffset(
                                            modelData
                                        )
                                    readonly property bool active:
                                        shell.radarDisplayedFrame !== null
                                            && shell.radarDisplayedFrame
                                                .offsetMinutes === modelData

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        color: parent.active
                                            ? theme.textPrimary
                                            : "transparent"
                                    }

                                    Rectangle {
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        visible: index < 2
                                        width: 1
                                        height: parent.height - 10
                                        color: theme.radarGrid
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.label
                                        color: parent.active
                                            ? theme.radarBackground
                                            : parent.available
                                                ? theme.textSecondary
                                                : theme.textDisabled
                                        font.family: "Adwaita Mono"
                                        font.pixelSize: 9
                                        font.weight: parent.active
                                            ? Font.Bold : Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Process {
        command: ["/usr/bin/date", "+%Z"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.currentTimeZoneAbbreviation = line.trim()
        }
    }

    Process {
        command: [
            "/usr/bin/python3",
            "-B",
            shell.clockScriptsDir + "/switchbot_meter.py",
            "--config",
            shell.clockConfigPath
        ]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateSensor(line)
        }
    }

    Process {
        id: weatherProcess
        command: [
            "/usr/bin/python3",
            "-B",
            shell.clockScriptsDir + "/weathernews_observation.py",
            "--config",
            shell.clockConfigPath
        ]

        onExited: exitCode => {
            if (exitCode !== 0 || !shell.weatherUpdateReceived)
                shell.weatherFetchFailed = true;
        }

        onRunningChanged: {
            if (!running && shell.weatherFetchPending)
                shell.requestWeatherFetch();
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateWeather(line)
        }
    }

    Process {
        id: holidayProcess
        command: [
            "/usr/bin/python3",
            "-B",
            shell.clockScriptsDir + "/japanese_holidays.py"
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateHolidays(line)
        }
    }

    Process {
        id: radarProcess
        command: shell.radarIncludeAnimationFrames
            ? [
                "/usr/bin/python3",
                "-B",
                shell.clockScriptsDir + "/jma_nowcast.py",
                "--config",
                shell.clockConfigPath,
                "--animation-frames"
            ] : [
                "/usr/bin/python3",
                "-B",
                shell.clockScriptsDir + "/jma_nowcast.py",
                "--config",
                shell.clockConfigPath
            ]

        onExited: exitCode => {
            shell.finishRadarFetch(exitCode);
            if (shell.radarImmediateFetchPending) {
                radarTimer.stop();
                radarImmediateTimer.restart();
            }
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => shell.updateRadar(line)
        }
    }

    Timer {
        id: weatherTimer
        repeat: false
        onTriggered: {
            shell.requestWeatherFetch();
            shell.scheduleNextWeatherFetch();
        }
    }

    Timer {
        id: radarTimer
        repeat: false
        onTriggered: {
            if (!shell.requestRadarFetch(
                    shell.radarScheduledCycleEpochMs,
                    shell.radarScheduledAttemptOffsetSeconds
                )) {
                shell.scheduleRadarRetryForCycle(
                    shell.radarScheduledCycleEpochMs,
                    shell.radarScheduledAttemptOffsetSeconds
                );
            }
        }
    }

    Timer {
        id: radarImmediateTimer
        interval: 1
        repeat: false
        onTriggered: shell.requestRadarRefreshNow()
    }

    Timer {
        id: radarAnimationTimer
        interval: 1600
        repeat: true
        onTriggered: {
            if (!shell.radarRainDetected()
                    || shell.radarActiveFrames.length <= 1) {
                shell.syncRadarAnimation(false);
                return;
            }
            shell.radarFrameIndex = (shell.radarFrameIndex + 1)
                % shell.radarActiveFrames.length;
        }
    }

    Timer {
        id: sensorDisplayTimer
        repeat: false
        onTriggered: {
            if (shell.sensorPendingReading !== null)
                shell.applySensorReading(shell.sensorPendingReading);
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            if (shell.sensorAvailable)
                shell.sensorFresh = shell.sensorLastSeenMs > 0
                    && Date.now() - shell.sensorLastSeenMs
                    <= 60000;
            if (shell.weatherAvailable)
                shell.weatherFresh = Date.now() - shell.weatherLastUpdateMs
                    <= 360000;
        }
    }

    Component.onCompleted: {
        shell.requestWeatherFetch();
        shell.scheduleNextWeatherFetch();
        shell.requestRadarRefreshNow();
    }

    Timer {
        id: calendarDateTimer
        interval: shell.millisecondsUntilNextDay()
        running: true
        repeat: false
        onTriggered: shell.updateCalendarDate()
    }

    Timer {
        interval: 86400000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!holidayProcess.running)
                holidayProcess.running = true;
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
}
