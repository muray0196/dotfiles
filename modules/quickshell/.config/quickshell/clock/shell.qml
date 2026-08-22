import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: shell

    property int widgetWidth: 312
    property bool widgetsVisible: true
    readonly property string clockScriptsDir: Quickshell.shellDir + "/scripts"
    readonly property string clockConfigPath: Quickshell.shellDir + "/local.json"
    property var weekdayNames: ["日", "月", "火", "水", "木", "金", "土"]
    property var holidayEntries: ({})
    property bool holidayDataAvailable: false
    property date calendarDate: new Date()
    property int currentYear: calendarDate.getFullYear()
    property int currentMonth: calendarDate.getMonth() + 1
    property int currentDay: calendarDate.getDate()
    property int currentWeekday: calendarDate.getDay()
    property string currentDateKey: dateKey(currentYear, currentMonth, currentDay)
    property string currentDateLabel: currentYear + "年" + currentMonth + "月"
        + currentDay + "日（" + weekdayNames[currentWeekday] + "）"

    function padded(value) {
        return value < 10 ? "0" + value : value.toString();
    }

    function dateKey(year, month, day) {
        return year + "-" + padded(month) + "-" + padded(day);
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

    function millisecondsUntilNextRadarFetch() {
        const now = new Date();
        const nextFetch = new Date(
            now.getFullYear(), now.getMonth(), now.getDate(),
            now.getHours(), now.getMinutes(), 30, 0
        );
        if (nextFetch <= now)
            nextFetch.setMinutes(nextFetch.getMinutes() + 1);
        return Math.max(1, nextFetch.getTime() - now.getTime());
    }

    function requestRadarFetch() {
        if (radarProcess.running) {
            radarFetchPending = true;
            return;
        }
        radarFetchPending = false;
        radarIncludeAnimationFrames = observedWeatherIsRain();
        radarUpdateReceived = false;
        radarProcess.running = true;
    }

    function scheduleNextRadarFetch() {
        radarTimer.interval = millisecondsUntilNextRadarFetch();
        radarTimer.restart();
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
            if (day < 1 || day > daysInMonth) {
                cells.push({
                    day: 0,
                    key: "",
                    weekday: index % 7,
                    holiday: "",
                    isToday: false
                });
                continue;
            }

            const key = dateKey(currentYear, currentMonth, day);
            cells.push({
                day: day,
                key: key,
                weekday: index % 7,
                holiday: holidayName(key),
                isToday: key === currentDateKey
            });
        }
        return cells;
    }

    function calendarDayColor(cell) {
        if (cell.holiday !== "" || cell.weekday === 0)
            return "#efa0ad";
        if (cell.weekday === 6)
            return "#9bd7ff";
        return "#f5f7ff";
    }

    function nextHolidayText() {
        if (!holidayDataAvailable)
            return "祝日データ未取得";

        const dates = Object.keys(holidayEntries).sort();
        for (const key of dates) {
            if (key < currentDateKey)
                continue;
            if (key === currentDateKey)
                return "今日　" + holidayEntries[key];

            const month = Number(key.slice(5, 7));
            const day = Number(key.slice(8, 10));
            return "次の祝日　" + month + "/" + day + " " + holidayEntries[key];
        }
        return "次の祝日　未掲載";
    }

    component IconCaption: Item {
        property string symbol: ""
        property string caption: ""
        property string changeCaption: ""
        property int symbolSize: 21
        property int captionSize: 15
        property int changeSize: 12
        property color symbolColor: "#c7cad5"
        property color captionColor: "#c7cad5"
        property color changeColor: "#aeb3c2"

        implicitWidth: iconRow.implicitWidth
        implicitHeight: iconRow.implicitHeight

        Row {
            id: iconRow
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: symbol
                color: symbolColor
                font.family: "Material Symbols Rounded"
                font.pixelSize: symbolSize
                font.weight: Font.Normal
            }

            Text {
                id: captionText
                text: caption
                color: captionColor
                font.family: "Noto Sans JP"
                font.pixelSize: captionSize
                font.weight: Font.Normal
            }

            Item {
                visible: changeCaption !== ""
                width: changeText.implicitWidth
                height: captionText.implicitHeight

                Text {
                    id: changeText
                    anchors {
                        top: parent.top
                        topMargin: 1
                    }
                    text: changeCaption
                    color: changeColor
                    font.family: "Noto Sans JP"
                    font.pixelSize: changeSize
                    font.weight: Font.Medium
                }
            }
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
                    id: radarTileImage

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
    property bool sensorAvailable: false
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
    property var radarFrameSetA: []
    property var radarFrameSetB: []
    property int radarActiveSet: -1
    property int radarPendingSet: -1
    property int radarPendingGeneration: 0
    property int radarPendingTileCount: 0
    property var radarPendingReadyUrls: ({})
    property double radarPendingReferenceEpoch: 0
    property double radarReferenceEpoch: 0
    property int radarFrameIndex: 0
    property var radarActiveFrames: radarActiveSet === 0
        ? radarFrameSetA : radarActiveSet === 1 ? radarFrameSetB : []
    property var radarDisplayedFrame: radarFrameIndex >= 0
            && radarFrameIndex < radarActiveFrames.length
        ? radarActiveFrames[radarFrameIndex] : null
    property real radarMetersPerPixel: radarDisplayedFrame !== null
        ? radarDisplayedFrame.metersPerPixel : 1
    property string radarFrameAt: radarDisplayedFrame !== null
        ? radarDisplayedFrame.frameAt : ""
    property int radarFrameOffset: radarDisplayedFrame !== null
        ? radarDisplayedFrame.offsetMinutes : 0
    property bool radarFrameForecast: radarDisplayedFrame !== null
        ? radarDisplayedFrame.forecast : false
    property bool radarAvailable: false
    property bool radarFetchPending: false
    property bool radarFetchFailed: false
    property bool radarIncludeAnimationFrames: false
    property bool radarUpdateReceived: false

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
            return "#ffd166";
        if (state === "snow" || state === "blizzard")
            return "#dff6ff";
        if (state === "sleet")
            return "#b9e8ff";
        if (state === "light_rain")
            return "#9bd7ff";
        if (state === "rain")
            return "#78c8ff";
        if (state === "fog")
            return "#d4d8e3";
        if (state === "extreme_heat")
            return "#ff9f43";
        if (state === "sunny")
            return "#ffd166";
        if (state === "cloudy")
            return "#d9dde8";
        return "#f5f7ff";
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
            return "#f5f7ff";
        if (value < 5)
            return "#a0d2ff";
        if (value < 10)
            return "#4d9cff";
        if (value < 20)
            return "#718cff";
        if (value < 30)
            return "#e8df45";
        if (value < 50)
            return "#ff9e3d";
        if (value < 80)
            return "#ff5c4a";
        return "#e65aa5";
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

    function differenceColor(indoor, outdoor, decimals) {
        const difference = differenceValue(indoor, outdoor, decimals);
        if (difference > 0)
            return "#9ece6a";
        if (difference < 0)
            return "#f7768e";
        return "#aeb3c2";
    }

    function updateSensor(line) {
        try {
            const reading = JSON.parse(line);
            if (typeof reading.temperature !== "number"
                    || typeof reading.humidity !== "number")
                return;

            temperature = reading.temperature;
            humidity = reading.humidity;
            sensorAvailable = true;
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

            const wasRaining = observedWeatherIsRain();
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
                        && typeof forecast.condition === "string"
                        && typeof forecast.temperature === "number"
                        && typeof forecast.precipitation === "number"
                ).slice(0, 5)
                : [];
            rainOutlook = typeof observation.rain_outlook === "string"
                ? observation.rain_outlook
                : "";
            weatherUpdateReceived = true;
            weatherAvailable = true;
            weatherFetchFailed = false;
            syncRadarAnimation(true);
            if (wasRaining !== observedWeatherIsRain())
                requestRadarFetch();
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

    function currentRadarFrameIndex(frames) {
        for (let index = 0; index < frames.length; index++) {
            if (frames[index].offsetMinutes === 0)
                return index;
        }
        return 0;
    }

    function syncRadarAnimation(resetSequence) {
        const shouldAnimate = radarAvailable
            && observedWeatherIsRain()
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
        if (radarFrameForecast)
            return radarFrameOffset + "分後予測 · " + radarFrameAt;
        if (radarFrameOffset < 0)
            return Math.abs(radarFrameOffset) + "分前 · " + radarFrameAt;
        return "最新 · " + radarFrameAt;
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
                    frameTime: frame.frame_time,
                    offsetMinutes: frame.offset_minutes,
                    forecast: frame.forecast
                });
            }
            if (!hasCurrentFrame || pendingFrames.length < 1)
                return;

            radarUpdateReceived = true;
            pendingFrames.sort((left, right) =>
                left.offsetMinutes - right.offsetMinutes
            );

            const pendingFrameSet = radarPendingSet === 0
                ? radarFrameSetA : radarPendingSet === 1
                    ? radarFrameSetB : [];
            const activeIsNewer = radarAvailable
                && radar.reference_time < radarReferenceEpoch;
            const activeAlreadyHasFrames = radarAvailable
                && radar.reference_time === radarReferenceEpoch
                && (radarIncludeAnimationFrames
                    ? !radarFramesAddInformation(
                        pendingFrames, radarActiveFrames
                    ) : radarActiveFrames.length === 1);
            const pendingIsNewer = radarPendingSet !== -1
                && radar.reference_time < radarPendingReferenceEpoch;
            const pendingAlreadyHasFrames = radarPendingSet !== -1
                && radar.reference_time === radarPendingReferenceEpoch
                && (radarIncludeAnimationFrames
                    ? !radarFramesAddInformation(
                        pendingFrames, pendingFrameSet
                    ) : pendingFrameSet.length === 1);
            if (activeIsNewer || activeAlreadyHasFrames
                    || pendingIsNewer || pendingAlreadyHasFrames) {
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
        radarActiveSet = setIndex;
        if (setIndex === 0)
            radarFrameSetB = [];
        else
            radarFrameSetA = [];
        radarPendingSet = -1;
        radarPendingTileCount = 0;
        radarPendingReadyUrls = {};
        radarPendingReferenceEpoch = 0;
        radarAvailable = true;
        radarFetchFailed = false;
        syncRadarAnimation(true);
    }

    function radarTileFailed(setIndex, generation) {
        if (setIndex !== radarPendingSet
                || generation !== radarPendingGeneration)
            return;

        radarPendingSet = -1;
        radarPendingReferenceEpoch = 0;
        radarFetchFailed = true;
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

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: "#b5181822"
            border.width: 1
            border.color: "#805c606b"

            Column {
                id: clockContent
                anchors.centerIn: parent
                spacing: -2

                Row {
                    id: timeRow
                    spacing: 8

                    Text {
                        id: hourText
                        text: Qt.formatDateTime(clock.date, "HH")
                        color: "#f5f7ff"
                        font.family: "Adwaita Mono"
                        font.pixelSize: 90
                        font.weight: Font.Normal
                    }

                    Item {
                        width: 16
                        height: hourText.implicitHeight

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: "#f5f7ff"
                            anchors {
                                horizontalCenter: parent.horizontalCenter
                                verticalCenter: parent.verticalCenter
                                verticalCenterOffset: -18
                            }
                        }

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: "#f5f7ff"
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
                            color: "#f5f7ff"
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
                            color: "#f5f7ff"
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
                    color: "#f5f7ff"
                    font.family: "Noto Sans JP"
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
            top: clockWindow.margins.top + clockWindow.implicitHeight + 10
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: calendarContent.implicitHeight + 22
        color: "transparent"
        exclusiveZone: 0
        focusable: false

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: "#b5181822"
            border.width: 1
            border.color: "#805c606b"

            Column {
                id: calendarContent
                anchors.centerIn: parent
                width: 280
                spacing: 4

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: shell.currentYear + "年" + shell.currentMonth + "月"
                    color: "#f5f7ff"
                    font.family: "Noto Sans JP"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }

                Row {
                    width: parent.width

                    Repeater {
                        model: shell.weekdayNames

                        delegate: Text {
                            required property int index
                            required property string modelData

                            width: calendarContent.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: index === 0 ? "#efa0ad"
                                : index === 6 ? "#9bd7ff"
                                : "#c7cad5"
                            font.family: "Noto Sans JP"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: "#40f5f7ff"
                }

                Grid {
                    id: calendarGrid

                    property var cells: shell.calendarCells()
                    property int weekCount: Math.ceil(cells.length / 7)

                    width: parent.width
                    height: weekCount * 26 + Math.max(0, weekCount - 1) * rowSpacing
                    columns: 7
                    rowSpacing: 1

                    Repeater {
                        model: calendarGrid.cells

                        delegate: Item {
                            required property var modelData

                            width: calendarContent.width / 7
                            height: 26

                            Rectangle {
                                anchors.centerIn: parent
                                visible: modelData.isToday
                                width: 26
                                height: 26
                                radius: 0
                                color: "#55f5f7ff"
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: modelData.day > 0
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

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: shell.nextHolidayText()
                    color: "#c7cad5"
                    font.family: "Noto Sans JP"
                    font.pixelSize: 13
                    font.weight: Font.Normal
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
            top: calendarWindow.margins.top + calendarWindow.implicitHeight + 10
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: weatherContent.implicitHeight + 20
        color: "transparent"
        exclusiveZone: 0
        focusable: false

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: "#b5181822"
            border.width: 1
            border.color: "#805c606b"

            Column {
                id: weatherContent
                anchors.centerIn: parent
                width: 280
                spacing: 3

                Text {
                    id: indoorLabel
                    width: parent.width
                    horizontalAlignment: Text.AlignLeft
                    text: "室内"
                    color: "#f5f7ff"
                    font.family: "Noto Sans JP"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }

                Row {
                    width: parent.width
                    spacing: 20

                    IconCaption {
                        width: (parent.width - 20) / 2
                        symbol: "\uf076"
                        caption: shell.sensorAvailable
                            ? shell.temperature.toFixed(1) + "°C"
                            : "--.-°C"
                        changeCaption: shell.sensorAvailable && shell.weatherAvailable
                            ? shell.differenceText(
                                shell.temperature,
                                shell.weatherTemperature,
                                1
                            )
                            : ""
                        changeColor: shell.differenceColor(
                            shell.temperature,
                            shell.weatherTemperature,
                            1
                        )
                        symbolSize: 22
                        captionSize: 26
                    }

                    IconCaption {
                        width: (parent.width - 20) / 2
                        symbol: "\uf87e"
                        caption: shell.sensorAvailable
                            ? shell.humidity + "%"
                            : "--%"
                        changeCaption: shell.sensorAvailable && shell.weatherAvailable
                            ? shell.differenceText(
                                shell.humidity,
                                shell.weatherHumidity,
                                0
                            )
                            : ""
                        changeColor: shell.differenceColor(
                            shell.humidity,
                            shell.weatherHumidity,
                            0
                        )
                        symbolSize: 22
                        captionSize: 26
                    }
                }

                Item {
                    width: parent.width
                    height: 15

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 1
                        color: "#55f5f7ff"
                    }
                }

                Item {
                    width: parent.width
                    height: Math.max(
                        outdoorLabel.implicitHeight,
                        weatherObservedTime.implicitHeight
                    )

                    Text {
                        id: outdoorLabel
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        text: "屋外"
                        color: "#f5f7ff"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 20
                        font.weight: Font.Medium
                    }

                    Text {
                        id: weatherObservedTime
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        visible: shell.weatherAvailable
                        text: shell.weatherObservedAt + "観測"
                        color: "#aeb3c2"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 12
                        font.weight: Font.Normal
                    }
                }

                IconCaption {
                    width: parent.width
                    symbol: shell.weatherAvailable
                        ? shell.weatherSymbol(shell.weatherState)
                        : "\uf172"
                    caption: shell.weatherAvailable
                        ? shell.weatherCondition
                        : shell.weatherFetchFailed ? "取得失敗" : "取得中…"
                    symbolSize: 30
                    captionSize: 20
                    symbolColor: shell.weatherAvailable
                        ? shell.weatherColor(shell.weatherState)
                        : "#f5f7ff"
                    captionColor: "#f5f7ff"
                }

                Row {
                    width: parent.width
                    visible: shell.weatherAvailable
                    spacing: 20

                    IconCaption {
                        width: (weatherContent.width - 20) / 2
                        symbol: "\uf076"
                        caption: shell.weatherTemperature.toFixed(1) + "°C"
                        symbolSize: 22
                        captionSize: 26
                    }

                    IconCaption {
                        width: (weatherContent.width - 20) / 2
                        symbol: "\uf87e"
                        caption: shell.weatherHumidity + "%"
                        symbolSize: 22
                        captionSize: 26
                    }
                }

                Column {
                    width: parent.width
                    visible: shell.hourlyForecast.length > 0
                    spacing: 3

                    Item {
                        width: parent.width
                        height: 11

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: 1
                            color: "#55f5f7ff"
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
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.hour + "時"
                                        color: "#f5f7ff"
                                        font.family: "Noto Sans JP"
                                        font.pixelSize: 14
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: shell.forecastSymbol(modelData)
                                        color: shell.forecastColor(modelData)
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 26
                                        font.weight: Font.Normal
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: "#55f5f7ff"
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: shell.forecastNumber(modelData.precipitation) + "mm"
                                        color: shell.precipitationColor(
                                            modelData.precipitation
                                        )
                                        font.family: "Adwaita Sans"
                                        font.pixelSize: 13
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 1
                                        color: "#55f5f7ff"
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: shell.forecastNumber(modelData.temperature) + "°"
                                        color: "#f5f7ff"
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
                                    visible: index < shell.hourlyForecast.length - 1
                                    width: 1
                                    color: "#55f5f7ff"
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: shell.rainOutlook !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: "雨の見通し　" + shell.rainOutlook
                    color: "#f5f7ff"
                    font.family: "Noto Sans JP"
                    font.pixelSize: 14
                    font.weight: Font.Normal
                }

            }
        }
    }

    PanelWindow {
        id: radarWindow
        visible: shell.widgetsVisible

        anchors {
            bottom: true
            right: true
        }

        margins {
            bottom: 12
            right: 12
        }

        implicitWidth: shell.widgetWidth
        implicitHeight: radarContent.implicitHeight + 20
        color: "transparent"
        exclusiveZone: 0
        focusable: false

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: "#b5181822"
            border.width: 1
            border.color: "#805c606b"

            Column {
                id: radarContent
                anchors.centerIn: parent
                width: 280
                spacing: 5

                Item {
                    width: parent.width
                    height: Math.max(
                        radarTitle.implicitHeight,
                        radarFrameTime.implicitHeight
                    )

                    Text {
                        id: radarTitle
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        text: "雨雲レーダー"
                        color: "#f5f7ff"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 18
                        font.weight: Font.Medium
                    }

                    Text {
                        id: radarFrameTime
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        text: shell.radarAvailable
                            ? shell.radarFrameLabel()
                                + (shell.radarFetchFailed ? " · 更新失敗" : "")
                            : shell.radarFetchFailed ? "取得失敗" : "取得中…"
                        color: shell.radarFetchFailed ? "#efa0ad" : "#c7cad5"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 12
                        font.weight: Font.Normal
                    }
                }

                Rectangle {
                    id: radarViewport
                    width: parent.width
                    height: 192
                    color: "#0b0d12"
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
                        color: "#20f5f7ff"
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: shell.radarAvailable
                        width: 1
                        height: parent.height
                        color: "#20f5f7ff"
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
                            border.color: "#42f5f7ff"
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !shell.radarAvailable
                        text: shell.radarFetchFailed ? "レーダーを取得できません" : "取得中…"
                        color: "#555862"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 13
                    }

                    Item {
                        id: radarMarker
                        anchors.centerIn: parent
                        visible: shell.radarAvailable
                        width: 14
                        height: 14

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: 6
                            color: "#e6ffffff"
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 2.5
                            color: "#e85d75"
                        }
                    }

                    Text {
                        anchors {
                            left: radarMarker.right
                            leftMargin: 4
                            verticalCenter: radarMarker.verticalCenter
                        }
                        visible: shell.radarAvailable
                        text: "仲宿"
                        color: "#d8dbe5"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 9
                    }

                    Text {
                        anchors {
                            left: parent.left
                            bottom: parent.bottom
                            leftMargin: 5
                            bottomMargin: 3
                        }
                        visible: shell.radarAvailable
                        text: "2 / 5 km"
                        color: "#7f8492"
                        font.family: "Adwaita Sans"
                        font.pixelSize: 8
                    }

                    Text {
                        id: radarAttribution
                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                            rightMargin: 5
                            bottomMargin: 3
                        }
                        textFormat: Text.StyledText
                        text: "<a href='https://www.jma.go.jp/bosai/nowc/'>気象庁(加工)</a>"
                        color: "#7f8492"
                        linkColor: "#aeb3c2"
                        font.family: "Noto Sans JP"
                        font.pixelSize: 8
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                }
            }
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

        onExited: (exitCode, exitStatus) => {
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

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || !shell.radarUpdateReceived)
                shell.radarFetchFailed = true;
        }

        onRunningChanged: {
            if (!running && shell.radarFetchPending)
                shell.requestRadarFetch();
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
            shell.requestRadarFetch();
            shell.scheduleNextRadarFetch();
        }
    }

    Timer {
        id: radarAnimationTimer
        interval: 1600
        repeat: true
        onTriggered: {
            if (!shell.observedWeatherIsRain()
                    || shell.radarActiveFrames.length <= 1) {
                shell.syncRadarAnimation(false);
                return;
            }
            shell.radarFrameIndex = (shell.radarFrameIndex + 1)
                % shell.radarActiveFrames.length;
        }
    }

    Component.onCompleted: {
        shell.requestWeatherFetch();
        shell.scheduleNextWeatherFetch();
        shell.requestRadarFetch();
        shell.scheduleNextRadarFetch();
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
