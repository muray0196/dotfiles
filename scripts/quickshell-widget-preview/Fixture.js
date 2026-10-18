.pragma library

function memory(used, total) {
  return {used_bytes: used * 1073741824, total_bytes: total * 1073741824, usage_percent: used / total * 100};
}
function normal() {
  return {
    demo: true, clock: "2026-10-18T09:41:32", zone: "JST · UTC+09:00",
    local: {
      _status: "Live", schema_version: 2, host: "local", uptime_seconds: 183480,
      cpu: {model: "AMD Ryzen 9 9950X", usage_percent: 12, temperature_c: 49, power_w: 43},
      gpus: [
        {model: "Radeon RX 9070 XT", display_connected: true, runtime_status: "active", usage_percent: 32, temperature_c: 56, hotspot_temperature_c: 68, power_w: 82, vram: memory(8.6, 16)},
        {model: "Radeon RX 7900 XTX", display_connected: false, runtime_status: "suspended", usage_percent: 0, temperature_c: 34, hotspot_temperature_c: 37, power_w: 6, vram: memory(0.4, 24)}
      ],
      memory: memory(28.4, 125.5), storage: memory(165.2, 232.7),
      storage_volumes: [Object.assign(memory(165.2, 232.7), {label: "ROOT", available: true}), Object.assign(memory(412.8, 468.4), {label: "SSD", available: true}), {label: "HDD", available: false}],
      network: {interface: "enp6s0", download_bytes_per_second: 3600000, upload_bytes_per_second: 420000}
    },
    main: {_status: "Live", host: "Main workstation", schema_version: 2,
      cpu: {model: "Intel Core i9", usage_percent: 24, temperature_c: 58, power_w: 72},
      gpus: [{model: "GeForce RTX 4090", usage_percent: 46, temperature_c: 61, power_w: 186, vram: memory(10.8, 24)}], memory: memory(18.2, 64)},
    indoor: {_status: "Live", observed_at: "09:41", temperature: 25.3, humidity: 48, battery: 92, rssi: -63},
    outdoor: {_status: "Live", temperature: 21.7, humidity: 61, observed_at: "09:40", condition: "Partly cloudy", state: "cloudy", rain_outlook: "No rain expected in the next hour", hourly_forecast: [
      {hour: "10:00", state: "cloudy", temperature: 22, precipitation: 0}, {hour: "11:00", state: "sunny", temperature: 23, precipitation: 0}, {hour: "12:00", state: "sunny", temperature: 24, precipitation: 0}, {hour: "13:00", state: "cloudy", temperature: 24, precipitation: 0.2}, {hour: "14:00", state: "rain", temperature: 22, precipitation: 1.4}
    ]},
    holidays: {"2026-10-12": "スポーツの日", "2026-11-03": "文化の日", "2026-11-23": "勤労感謝の日"},
    radar: {},
    history: {window_seconds: 600, local_cpu: 63, local_gpu1: 68, local_gpu2: 42, local_hotspot1: 79, local_hotspot2: 48, main_cpu: 72, main_gpu: 67, local_average: 112, local_peak: 208, main_average: 243, main_peak: 386}
  };
}
function scenario(index) {
  const d = normal();
  if (index === 1) {
    d.local.cpu.model = "AMD Ryzen Threadripper PRO 7995WX 96-Core Processor";
    d.local.cpu.usage_percent = 100;
    d.local.cpu.power_w = 1234;
    d.local.memory = memory(1023.8, 2048);
    Object.assign(d.local.storage_volumes[0], memory(0, 232.7));
    Object.assign(d.local.storage_volumes[1], memory(16384, 16384));
    d.local.uptime_seconds = 999 * 86400;
    d.local.gpus[0].model = "A very long graphics adapter name with display and compute";
    d.local.gpus[0].usage_percent = 100;
    d.local.gpus[0].temperature_c = 105;
    d.history.local_gpu1 = 105;
    d.main.host = "Main workstation with an exceptionally long host name";
    d.local.network.download_bytes_per_second = 1234567890;
    d.history.window_seconds = 122;
    d.history.local_hotspot1 = 105;
    d.history.local_average = 987;
    d.history.local_peak = 1234;
    d.outdoor.rain_outlook = "非常に長い降水予報の表示を確認しています。午後から強い雨が降る可能性があります。";
    d.outdoor.condition = "晴れ時々曇り、夜遅くから雨";
    d.holidays["2026-10-18"] = "とても長い祝日名称を表示するテスト";
    d.clock = "2026-08-31T23:59:59"; // Six calendar rows, year/day metadata, long time.
  } else if (index === 2) {
    d.local._status = "Partial";
    d.local.cpu.temperature_c = null;
    d.local.gpus[1].power_w = null;
    d.local.gpus[1].vram = {};
    d.local.storage_volumes[0].usage_percent = null;
    d.local.storage_volumes[1].available = false;
    d.local.network = {};
    d.main = {_status: "No signal", cpu: {}, memory: {}, gpus: []};
    d.indoor = {_status: "Stale", temperature: 25.3, humidity: 48, battery: 92, rssi: -63};
    d.outdoor = {_status: "Error"}; d.holidays = {}; d.history = {};
  }
  return d;
}
function changing(phase, index) {
  const d = scenario(index);
  if (index !== 2) {
    d.local.cpu.usage_percent = 12 + 10 * Math.sin(phase * 1.2);
    d.local.gpus[0].usage_percent = 35 + 32 * Math.sin(phase * 0.8);
    d.local.network.download_bytes_per_second = (2 + Math.sin(phase)) * 2097152;
  }
  return d;
}
