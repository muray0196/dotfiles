.pragma library

// Category accents stay fixed within each explicit foreground appearance.
function temperatureInk(dark) { return dark ? "#a64435" : "#ffab97"; }
function powerInk(dark) { return dark ? "#6e47a6" : "#ceb7ff"; }
function machineSymbol(remote) { return remote ? "\uf088" : "\ueb8e"; }

// Different silhouettes identify hardware without relying on CPU/GPU lettering.
function deviceIcon(cpu, dark) {
  const shape = cpu
    ? '<rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9" y="9" width="6" height="6" rx="1"/><path d="M9 3v3m6-3v3M9 18v3m6-3v3M3 9h3m-3 6h3m12-6h3m-3 6h3"/>'
    : '<path d="M2 5v15m0-12h2m0-1h16a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4Zm3 10v2h5v-2"/><circle cx="9" cy="12" r="2.5"/><circle cx="17" cy="12" r="2.5"/>';
  return "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="'
    + (dark ? "#172331" : "#fafbff") + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + shape + '</svg>');
}

function number(v, digits) {
  return typeof v === "number" && isFinite(v) ? v.toFixed(digits || 0) : "—";
}
function capacity(v) {
  return v && v.available !== false && typeof v.used_bytes === "number"
    ? number(v.used_bytes / 1073741824, 1) + " / " + number(v.total_bytes / 1073741824, 1) + " GiB"
    : "— / — GiB";
}
function rate(v) {
  if (typeof v !== "number" || !isFinite(v)) return "—";
  if (v >= 1048576) return number(v / 1048576, 1) + " MiB/s";
  if (v >= 1024) return number(v / 1024, 1) + " KiB/s";
  return number(v) + " B/s";
}
function deviceName(model) {
  return model ? model.replace(/\(R\)|\(TM\)|®|™/g, "")
    .replace(/^\d+(st|nd|rd|th) Gen /, "")
    .replace(/\s+@\s*[\d.]+\s*GHz$/i, "")
    .replace(/\s+\d+-Core Processor$/i, "") : "Sensor unavailable";
}
function observation(reading, indoor) {
  const state = reading._status || "No data";
  const time = reading.observed_at;
  if (state === "Live") return time ? (indoor ? "Updated " : "Observed ") + time : "Time unavailable";
  if (state === "Stale") return "No recent reading";
  if (state === "Error") return "Unavailable";
  return state + (time ? " · " + time : "");
}
function radarStamp(frame, reading, clock) {
  if (!frame.frame_time) return "";
  const time = new Date(frame.frame_time * 1000);
  const age = Math.max(0, Math.floor((clock.getTime() - time.getTime()) / 60000));
  return (reading._status === "Cached" ? "Cached" + (frame.forecast ? " · " : " ") : "")
    + (frame.forecast ? "Forecast " : "")
    + Qt.formatDateTime(time, "HH:mm") + (!frame.forecast && age > 0 ? " · " + age + "m ago" : "");
}
function uptime(v) {
  if (typeof v !== "number") return "Uptime unavailable";
  return Math.floor(v / 86400) + "d " + Math.floor(v % 86400 / 3600) + "h " + Math.floor(v % 3600 / 60) + "m uptime";
}
function dateKey(d) {
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}
function calendar(d, holidays) {
  const first = new Date(d.getFullYear(), d.getMonth(), 1);
  const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  const rows = Math.ceil((days + first.getDay()) / 7);
  const result = [];
  for (let i = 0; i < rows * 7; ++i) {
    const day = i - first.getDay() + 1;
    const cell = new Date(d.getFullYear(), d.getMonth(), day);
    result.push({day: day > 0 && day <= days ? String(day) : "", today: day === d.getDate(),
      holiday: (holidays || {})[dateKey(cell)] || "", sunday: i % 7 === 0, saturday: i % 7 === 6});
  }
  return result;
}
function dayOfYear(d) {
  return Math.floor((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(d.getFullYear(), 0, 1)) / 86400000) + 1;
}
function week(d) {
  const dt = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  dt.setUTCDate(dt.getUTCDate() + 4 - (dt.getUTCDay() || 7));
  return Math.ceil((((dt - new Date(Date.UTC(dt.getUTCFullYear(), 0, 1))) / 86400000) + 1) / 7);
}
function nextHoliday(d, holidays) {
  const key = dateKey(d);
  const next = Object.keys(holidays || {}).sort().find(k => k >= key);
  if (!next) return "Holiday data unavailable";
  const count = Math.round((Date.parse(next + "T00:00:00Z") - Date.parse(key + "T00:00:00Z")) / 86400000);
  return holidays[next] + " · " + (count === 0 ? "Today" : "in " + count + " days");
}
function symbol(state) {
  return ({sunny: "\ue81a", clear: "\ue81a", cloudy: "\uf15c", light_rain: "\uf61e",
    rain: "\uf176", rainy: "\uf176", storm: "\uf61f", thunder: "\uebdb",
    snow: "\ue80f", sleet: "\uf61d", blizzard: "\uf61c", fog: "\ue818",
    extreme_heat: "\uf537"})[state] || "—";
}
function weatherDescription(state) {
  return ({sunny: "Sunny", clear: "Clear", cloudy: "Cloudy", light_rain: "Light rain",
    rain: "Rain", rainy: "Rain", storm: "Storm", thunder: "Thunderstorms",
    snow: "Snow", sleet: "Sleet", blizzard: "Blizzard", fog: "Fog",
    extreme_heat: "Extreme heat"})[state] || "Condition unavailable";
}
function weatherInk(state, dark) {
  if (["sunny", "clear", "extreme_heat"].includes(state)) return dark ? "#8c570d" : "#ffd68a";
  if (["light_rain", "rain", "rainy", "storm", "snow", "sleet", "blizzard"].includes(state)) return dark ? "#245f9e" : "#a9cdff";
  if (state === "thunder") return dark ? "#6e479f" : "#dec1ff";
  return dark ? "#455563" : "#e6ebf2";
}
