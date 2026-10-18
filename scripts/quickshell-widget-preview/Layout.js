.pragma library

// Logical desktop geometry shared by the foreground and material study.
var panelWidth = 350;
var panelHeight = 1024;
var sideInset = 12;
var topInset = 28;
var contentInset = 24;
var shadowPadding = 28;
var daySectionGap = 20;
var panelKinds = ["local", "main", "clock", "day", "radar"];

function weatherHeight(readings) {
  var indoor = readings.indoor || {};
  var outdoor = readings.outdoor || {};
  return indoor._status !== "Live" || outdoor._status !== "Live" || !outdoor.observed_at ? 276 : 252;
}

function panel(kind, readings) {
  // All three right-hand surfaces share the same width and horizontal inset.
  var rightInset = 20;
  var rightGap = 20;
  var clockHeight = 118 + 2 * rightInset;
  var dayHeight = 238 + daySectionGap + weatherHeight(readings) + 2 * rightInset;
  var dayY = clockHeight + rightGap;
  var radarY = dayY + dayHeight + rightGap;
  var geometry = {
    local: {left: true, y: 0, height: 624, inset: 20},
    main: {left: true, y: 644, height: 380, inset: 20},
    clock: {left: false, y: 0, height: clockHeight, inset: rightInset},
    day: {left: false, y: dayY, height: dayHeight, inset: rightInset},
    radar: {left: false, y: radarY, height: panelHeight - radarY, inset: rightInset}
  };
  return geometry[kind];
}
