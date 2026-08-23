# Quickshell UI direction

## Goal

Build a desktop UI that has the crisp, slightly old-fashioned edge of older
software while remaining immediately understandable. The intended direction is
**retro framing with modern information design**.

The left and right widget groups serve different jobs and should not be forced
into identical layouts:

- The left side is a dense operational dashboard for controls and performance.
- The right side is an ambient information column for time, calendar, weather,
  sensors, and radar.

The current discomfort comes from inconsistent visual grammar between those two
groups, not from their different content.

## Accepted baseline

- Square panels with no corner radius.
- A restrained neutral border rather than a colored outline.
- Continuous square-ended utilization bars without percentage labels, plus
  square status indicators.
- Current fonts, Material Symbols icons, per-metric colors, content order, and
  behavior.
- Vertically center icons, labels, badges, and values within mixed-size rows;
  do not rely on the row positioner's default top alignment.
- Compact, legible information hierarchy with accurate status semantics.

This baseline is the rollback point before further design experiments.

## Current performance hierarchy

- `LOCAL SYSTEM` is one aggregate card for the current machine: uptime,
  platform, storage, network, CPU, RAM, and graphics.
- Local storage shows ROOT plus host-specific volumes defined in the ignored
  machine config. Missing mounts must be shown as unavailable, never as ROOT.
- Local graphics shows each physical GPU with its own load, temperature, power,
  and VRAM values. Mark the display GPU and explain a suspended GPU as `SLEEP`
  instead of making missing live sensors look like a fault.
- It is not presented as the local counterpart of Main PC; the former `This PC`
  identity and paired-card structure have been removed.
- Main PC remains a separate remote-status card with its existing LIVE/NO SIGNAL
  behavior and zeroed stale measurements. While stale, its identity and metric
  content are muted, but the `NO SIGNAL` indicator remains prominent.
- Desktop Control is no longer visible in the widget. Background heartbeat,
  Waywallen, brightness, and scheduled display automation remain independent of
  the visible card hierarchy.

## Shared visual grammar

Unify the chrome around the content while preserving the content itself:

1. Use one subtle old-style edge treatment on both sides. A restrained two-tone
   edge is a candidate: slightly lighter on the top/left and darker on the
   bottom/right, without a heavy 3D bevel.
2. Standardize title rows: common size, weight, alignment, and optional
   right-aligned status/update text. The large clock remains an intentional
   exception.
3. Use one 1 px divider treatment throughout.
4. Use shared spacing tokens as a starting point: 16 px outer padding, 10 px
   panel gaps, 7 px section gaps, and 4 px tight internal gaps.
5. Keep icons and semantic color because they improve recognition: green for
   good/live, red for faults, amber for schedule/caution, and stable colors for
   CPU/GPU/RAM/VRAM identity.
6. Keep the current fonts until the structural grammar is coherent. Typography
   can then be tested separately and rolled back independently.

## Experiment 1: shared panel chrome

Kept on top of pushed rollback baseline `c088bb2`:

- a one-pixel two-tone edge, lighter on the top/left and darker on the
  bottom/right;
- 18 px medium-weight panel titles, with the large clock retained as an
  intentional exception;
- one neutral divider tone across performance, calendar, and weather panels;
- shared 280 px content width, 10 px panel/major-section rhythm, and existing
  tighter spacing where dense content needs it.

The experiment changes no data, behavior, content order, font families, icons,
or semantic colors. It was evaluated with both widget columns visible at
1920x1080.

## Experiment 2: mechanical micro-labels

Kept on top of shared-chrome commit `f82f39d`:

- use the already-installed Adwaita Mono only for small Latin labels, platform
  names, status text, and compact metadata in the performance widget;
- retain the existing sans-serif faces for panel titles, metric names, models,
  measurements, and capacities;
- retain Noto Sans JP for all Japanese text;
- rely on the existing Adwaita Mono clock readout to connect the treatment
  across the two sides without forcing mono typography onto the right column.

This experiment changes typography only and was evaluated with both widget
columns visible at 1920x1080.

## Experiment 3: aligned instrument readouts

Kept on top of micro-label commit `bcd07ad`:

- use Adwaita Mono for compact numeric readings in the performance widget:
  temperatures, power, memory/storage capacities, GPU VRAM, and network rates;
- retain sans-serif typography for panel titles, metric names, and hardware
  models so the widget does not become a full terminal theme;
- make no changes to values, precision, units, geometry, or colors.

The fixed-width readings improve column alignment and add a restrained
instrument-panel character. The experiment was evaluated with both widget
columns visible at 1920x1080.

## Experiment 4: square clock colon

Kept on top of alignment commit `ec98aae`:

- replace the two 10 px circular clock separators with restrained 8 px square
  marks;
- preserve their position, spacing, color, and update behavior.

This removes the most prominent rounded detail from the primary clock without
altering its legibility or geometry.

## Experiment 5: lighter meter rails

Kept on top of clock-separator commit `95ad4ec`:

- reduce continuous utilization rails from 7 px to 5 px;
- preserve fill colors, empty-track contrast, values, and square ends.

The slimmer rails remain immediately readable while giving labels and numeric
readouts more visual priority.

## Experiment 6: weather subsection hierarchy

Kept on top of meter-rail commit `99fd954`:

- render `室内` and `屋外` as 16 px subsection titles;
- retain 18 px for actual panel titles such as the calendar month and radar;
- preserve font family, weight, alignment, color, and weather content.

The weather groups remain obvious, but no longer compete with panel-level
headings.

## Experiment 7: muted measurement units

Kept on top of weather-hierarchy commit `6af9a1c`:

- retain bright numeric readings while muting only `°C`, `W`, storage/memory
  units, and network-rate units;
- preserve font size, font family, precision, spacing, and value semantics;
- apply the treatment consistently to Local System and Main PC.

This separates values from units without adding columns or extra decoration.

## Experiment 8: clearer local GPU hierarchy

Kept on top of muted-unit commit `a22f8c4`:

- show `VRAM` once per GPU, beside its utilization rail, instead of repeating it
  on the capacity line;
- enlarge the Local System GPU titles, model names, readings, and micro-labels
  to use the available card space;
- leave the Main PC card unchanged.

This makes each GPU easier to scan without changing its data or adding visual
decoration.

## Reconstructed experiment sequence

This sequence incorporates external feedback only where it matches the live
1920x1080 screen and the already accepted behavior. Finish and visually validate
one experiment before starting the next.

### Experiment 9: neutral directional deltas

- render indoor/outdoor temperature and humidity differences in one muted
  neutral color;
- retain the explicit `+`, `−`, and `±` direction markers;
- leave actual state colors, calendar colors, and radar intensity colors alone.

The deltas describe direction, not good/bad health. Red and green currently make
the small readings look like warnings or success states.

Live result: retained as the current candidate. The direction remained clear
from the sign, while the small annotations stopped resembling alarms.

### Experiment 10: stronger panel backdrop

- test a small opacity increase for the shared dark panel background;
- change no geometry, type size, content, or edge treatment;
- compare the live result over both bright and dark wallpaper regions.

The real display shows wallpaper linework competing with microtext. Improve that
contrast before enlarging secondary labels throughout the UI.

Live result: retained `#c2181822` (about 76% opacity) instead of `#b5181822`
(about 71%). Frozen-frame captures on a bright, detailed wallpaper showed
cleaner microtext while preserving visible wallpaper texture.

### Experiment 11: selective section-header emphasis

- reassess `STORAGE` and `GRAPHICS` after the backdrop experiment;
- if they remain weak, test a restrained 11-12 px treatment on Local System;
- do not add redundant full-panel headers to the already clear right column.

Live result: retained 12 px `STORAGE` and `GRAPHICS` labels without adding new
chrome. The group boundaries became easier to scan while CPU, RAM, GPU, and
storage readings remained visually dominant; the full 1920x1080 layout still
fit without clipping.

### Source-specific freshness work

1. Weather: the first treatment retained cached observations and appended
   `更新失敗` when the latest fetch failed. A forced fetch failure proved that
   behavior and automatic recovery; Experiment 12 now presents the same
   distinction as `CACHED` or `ERROR` in the source row.
2. SwitchBot: consume its timestamp and show an exception-only stale state after
   60 seconds without a valid reading. A 168-second live sample produced 18
   readings with a 10.019-second median and 14.033-second maximum interval, so
   the timeout allows more than four observed worst-case intervals. A scoped
   scanner pause first showed `更新停止` with unavailable readings after the
   timeout. Experiment 12 folds that exception into the `INDOOR STALE` source
   row; resuming still restores the values on the next reading.
3. Local metrics: do not restore a permanent `LIVE` indicator. Consider a
   failure-only treatment separately if needed.
4. Main PC: preserve `NO SIGNAL`, dimmed identity/content, and zeroed stale
   measurements exactly as accepted.

### Experiment 12: ENVIRONMENT instrument module

- replace the stacked indoor/outdoor mini-widgets with one explicit comparison
  instrument while preserving every existing reading;
- use a factual `SOURCES n/2` header instead of one module-wide `LIVE` claim,
  because SwitchBot and Weathernews fail independently;
- give indoor data `LIVE / STALE / NO DATA` states and outdoor data
  `LIVE / CACHED / FETCHING / ERROR` states;
- align temperature and humidity into stable columns, label the forecast strip,
  and retain the optional rain outlook as a separate final row;
- hide indoor/outdoor deltas unless both sources are current, so a fresh sensor
  is never compared silently with cached weather;
- record successful weather receipt time separately and treat six minutes
  without a successful two-minute fetch as cached data.

Live result: retained as the current candidate. On the 1920x1080 display the
normal panel is 312x314 px instead of 312x343 px, leaving 47 px above the radar.
A rendered rain-outlook row increased it to 339 px and still left 22 px without
overlap. The bright-wallpaper capture kept the header, readings, states, and all
five forecast columns legible. Pausing only the managed SwitchBot child produced
`SOURCES 1/2`, `INDOOR STALE`, and placeholders while outdoor weather remained
current; resuming it restored `SOURCES 2/2` and the readings. A temporary rendered
`CACHED` state retained outdoor observations and the forecast, reduced the source
count, and suppressed the comparison deltas as intended.

### Experiment 13: semantic ENVIRONMENT palette

- use cyan-blue only for the single module-header rail and genuinely
  rain-related information;
- render body labels such as `TEMP`, `HUMIDITY`, `CONDITION`, and
  `NEXT 5 HOURS` in neutral gray;
- keep primary readings off-white and comparison deltas muted neutral;
- keep source state colors separate: green for current, amber for stale/cached,
  red for error, and gray for fetching or unavailable.

Live result: retained the `#7dcfff` header rail with a neutral body. It preserves
one clear color accent while preventing the small measurement labels from
visually rhyming with precipitation. `RAIN OUTLOOK`, rain icons, and precipitation
values initially kept their blue meaning; the isolated `RAIN OUTLOOK` label was
later neutralized because it read as an alert even when the message reported no
rain. Rain icons and precipitation values retain their blue meaning. A full
muted-violet label pass was rejected after the bright-wallpaper comparison
because it introduced a competing color family. Geometry and data are unchanged.

### Implementation: shared semantic palette

- keep all clock, calendar, environment, radar, and performance colors in
  `quickshell/common/Theme.qml`;
- consume named roles such as `environmentHeaderAccent`, `rainAccent`,
  `statusCaution`, and `ramAccent` instead of inline hex values;
- keep roles separate even when they currently share a value, so a future
  weather change cannot silently alter hardware or status meaning;
- expose the common component through each config's local `common` link because
  Quickshell rejects direct imports outside an individual config directory.

Live result: both configs reloaded successfully from the shared component. The
refactor changes palette ownership only; rendered colors, geometry, and data
semantics remain unchanged.

### Follow-up: OUTDOOR balance and alignment

The OUTDOOR metrics no longer reserve the indoor-only comparison footer, and
the CONDITION column no longer carries a matching empty spacer. The divider now
follows the actual outdoor readings while the indoor delta row remains stable.
The condition label is vertically centered against the weather icon instead of
sharing its top edge. The live panel is 312x327 px with 34 px remaining above
the radar.

### Experiment 14: calendar and radar instrument grammar

- give CALENDAR the same left-rail header structure with a neutral accent,
  right-aligned `YYYY / MM` metadata, and an explicit holiday footer;
- preserve the open seven-column grid, square today marker, and existing
  Sunday, holiday, and Saturday colors;
- give RAIN RADAR the rain-blue header rail and the same factual source states
  as weather: `LIVE / CACHED / FETCHING / ERROR`;
- keep the radar frame label as secondary header metadata while preserving the
  map, center, zoom, rings, attribution, source, and refresh behavior.

Live result: retained as the current candidate. CALENDAR is 312x266 px, one
pixel taller than before, and reads as a quiet reference panel. RAIN RADAR is
312x250 px, six pixels taller than before, and reads as a live instrument. The
312x327 px ENVIRONMENT panel retains 27 px above the radar. All three remain
clear over the bright animated wallpaper without introducing another accent
family.

### Follow-up: dense calendar metadata

- keep the calendar interface in English while preserving the Japanese holiday
  name supplied by the holiday data;
- add `TODAY MM/DD DDD`, ISO week, and day-of-year metadata to the header;
- expand the weekday row to unambiguous three-letter English labels;
- add the exact `IN nD` countdown to the existing next-holiday footer without
  placing more content inside the date grid.

Live result: retained. CALENDAR is now 312x273 px and reads as a compact
reference instrument while the date grid remains its visual center. The
312x327 px ENVIRONMENT panel shifts down by seven pixels and still retains
20 px above the unchanged RAIN RADAR panel. Both dark and bright wallpaper
checks preserve legibility and the existing Sunday, holiday, and Saturday
color semantics.

### Follow-up: calendar ghost grid

- extend the seven calendar columns through the weekday header and date area;
- draw each shared edge once so adjacent cells never create doubled borders;
- keep vertical divisions faint and make weekly horizontal rules slightly
  stronger for scanning;
- fill the complete current-day cell while preserving the open typography,
  colors, and all geometry;
- use the existing module divider as the grid's single lower edge.

Live result: retained. The calendar now reads more like an older ledger or
electronic organizer without becoming a heavy spreadsheet. The ghost grid
survives both dark and bright wallpaper checks, the date text remains dominant,
and CALENDAR stays 312x273 px with the existing 20 px gap above RAIN RADAR.

### Follow-up: dense radar telemetry

- keep the left header title on one line while retaining the factual source
  state and frame time on the right;
- overlay a compact `FRAME / timeline / mode` strip at the top of the map;
- show `FRAME 1/1 · NOW · STATIC` for the normal single-frame state and the
  existing `-10 OBS / NOW / +10 FCST` sequence when rain enables animation;
- place the calculated viewport coverage beside `RANGE 2 / 5 KM` in the map
  footer and retain `JMA NOWCAST`, without adding a redundant center label or
  another data source;
- preserve the 312x250 px panel, 192 px map, center, zoom, range rings, refresh
  schedule, and rain-triggered animation contract.

Live result: retained. The current 124.1 m/px scale produces a truthful
`VIEW 35x24 KM` footer value. Static, dark-wallpaper, bright-wallpaper, and
full-desktop checks remain legible, with the map still dominant and the
existing 20 px separation from ENVIRONMENT unchanged. A live animation-feed
probe returned the expected observation/current/forecast offsets of
`-10 / 0 / +10` minutes.

### Follow-up: source state and data time grammar

- use `OBS HH:mm` for Outdoor data because it identifies the external source's
  observation time more precisely than `AS OF`; omit it from the continuously
  received healthy Indoor sensor;
- retain `LIVE / CACHED` as source freshness and use `OBS` only as the Outdoor
  timestamp qualifier rather than another source state;
- reserve `OBS / FCST` for Rain Radar frame identity; the prefix already makes
  the timestamp's role clear, so a separate `VALID` qualifier is unnecessary.
- use green once per independently refreshed widget: `LIVE n/2` for the
  Environment aggregate and `LIVE` for Rain Radar;
- omit healthy Indoor and Outdoor markers entirely, instantiating section-level
  status only for `STALE`, `CACHED`, `NO DATA`, `FETCHING`, or `ERROR`.

Live result: retained. Healthy Indoor now needs no local status or timestamp;
its last receive time returns only with a `STALE` state. Outdoor retains its
useful observation time without repeating the aggregate `LIVE` state. Rain
Radar remains semantically distinct as
`OBS M/d HH:mm · n/N` or `FCST M/d HH:mm · n/N`. Both widget
sizes and all metric geometry remain unchanged.

### Follow-up: local-time instrument header

- preserve the accepted 90 px hours/minutes and 32 px baseline-aligned seconds;
- overlay a neutral `LOCAL TIME` rail and actual system timezone metadata in the
  clock's existing upper padding rather than increasing its height;
- derive the timezone abbreviation from the system and calculate the current
  UTC offset, rendering `JST · UTC+09` on this host;
- replace the Japanese date line in place with the structured English
  `YYYY / MM / DD · DDD` form;
- keep the original time/date group at its 5 px optical offset after adding the
  top header, then shift only the large time row down by 8 px to tighten its
  relationship with the date without changing either font size;
- avoid duplicating Calendar metadata, uptime, weather, or decorative clock
  internals.

Live result: retained. The clock remains 312x166 px, its time typography and
downstream widget positions are unchanged, and both dark and bright wallpaper
checks keep the new 9-11 px metadata legible without competing with the time.

### Follow-up: current-date ownership

- let the Clock own the single full textual current date;
- remove `TODAY MM/DD DDD` from the adjacent Calendar header because the filled
  current-day cell already carries that meaning;
- retain Calendar's month/year, ISO week, day-of-year, holiday footer, weekday
  labels, and grid semantics.

Live result: retained. The Calendar header now balances the single 17 px title
against the two-line right metadata block, while the filled current-day cell
remains unambiguous. Clock stays 312x166 px and Calendar stays 312x273 px; no
downstream geometry changes.

The holiday footer now keeps `NEXT HOLIDAY` as the left field label and groups
the date, holiday name, and countdown as one right-aligned value, for example
`09/21 敬老の日 · IN 28D`.

Environment's `RAIN OUTLOOK` footer now follows the same layout grammar: the
field label is anchored left, the complete forecast is anchored and aligned
right, and both share a vertically centered minimum 19 px row. Longer forecast
text may still wrap without overlapping the label. Calendar and Environment now
instantiate one shared footer-row component, which fixes both labels at muted
10 px monospace and both values at secondary 12 px Japanese-capable text with
identical weight, alignment, and wrapping behavior. The 10 px and 12 px sizes
are defined as shared `moduleFooterLabelSize` and `moduleFooterValueSize` roles
in `common/Theme.qml`, while the colors continue to use `textMuted`,
`textSecondary`, and `textDisabled`.

### Follow-up: unified module header rails

- replace the four independently sized Clock, Calendar, Environment, and Rain
  Radar header rails with one shared 18 px component;
- use Environment as the spacing reference, placing every rail approximately
  13 px below its panel's top edge and every left header on the same 22 px
  vertical center axis;
- standardize all four left module titles at 17 px, using Environment's 24 px
  internal header height for Clock as well;
- place the header divider container 34 px below every panel's top edge, using
  Environment as the reference, and add the previously missing Clock divider;
- keep every module title on one line at the left edge;
- preserve Rain Radar's frame metadata at the right;
- move Radar's calculated `VIEW` coverage beside `RANGE` in the map footer.

Live result: retained. The four rails now share length and top inset, all four
module titles share the same 17 px type size, and their horizontal dividers
occupy the same vertical position. Together they form a consistent visual
rhythm down the stack while their existing semantic colors remain intact. Radar
keeps its instrument density without being the only module with a subtitle
below its title. All four panel sizes and positions are unchanged, and the full
stack has no clipping.

### Follow-up: source-health header rails

- keep Clock and Calendar rails neutral because neither widget represents a
  polled external source;
- drive Environment and Rain Radar rails from source health: green when fully
  current, amber when partial/stale/cached data remains usable, red after a
  confirmed failure without usable data, and gray while initially fetching or
  otherwise unknown;
- remove the redundant healthy `LIVE 2/2` and `LIVE` header markers;
- retain explicit `STALE`, `CACHED`, `FETCHING`, and `ERROR` text in the relevant
  body section when abnormal, so color is not the only diagnostic;
- leave `OBS/FCST M/d HH:mm · n/N` as Rain Radar's sole right-side header
  metadata, align it with the title, and render it at the same shared 10 px
  observation-metadata size as Outdoor's `OBS HH:mm`.

Live result: retained. In the healthy state, Environment and Rain Radar use the
same green rail while Clock and Calendar remain neutral. Removing the two `LIVE`
markers gives Radar's frame metadata an unobstructed line and leaves all header
dividers aligned. Static state inspection confirms the amber, red, and gray
bindings above. All widget sizes and body geometry are unchanged.

### Follow-up: unified widget bottom inset

- anchor the final content stack in all four widgets 10 px above the panel's
  bottom edge;
- use Environment and Rain Radar as the existing 10 px references;
- move Clock and Calendar content by only 1 px to meet the shared inset;
- compensate Calendar's header chrome by 1 px so the unified rail and divider
  positions remain unchanged.

Live result: retained. Clock's date, Calendar's holiday footer, Environment's
rain-outlook footer, and Rain Radar's viewport now share the same 10 px content
boundary. All widget sizes, window positions, header rails, and header dividers
remain unchanged.

### Follow-up: Environment source metadata

- identify the two acquisition channels as `BLE · WEATHERNEWS` in the unused
  right side of the Environment header;
- consume the battery and RSSI values already emitted by the SwitchBot BLE
  reader and render them as `BAT n% · RSSI −n` on the healthy Indoor row;
- keep these values neutral because the header rail already owns aggregate
  source health;
- replace the link metadata with the existing `STALE · AS OF ...` or `NO DATA`
  message whenever Indoor is not current.

Live result: retained. The live sensor rendered `BAT 96% · RSSI −68` without
crowding the Indoor label or measurements, and `BLE · WEATHERNEWS` balances the
module title without duplicating health status. Widget size and geometry are
unchanged.

### Follow-up: elastic Rain Radar slot

- anchor Rain Radar 10 px below Environment and 12 px above the screen bottom
  instead of positioning it only from the bottom with a fixed height;
- calculate the map height from the resulting Radar window height after shared
  panel padding, header, and divider chrome;
- retain 192 px as the minimum usable map height while allowing available spare
  height to flow into the map automatically;
- continue deriving `VIEW width×height KM` from the live viewport geometry.

Live result: retained. The Environment-to-Radar gap fell from 24 px to the shared
10 px gap, Radar expanded from 250 px to 264 px, and its map expanded from 192 px
to 206 px while retaining the 12 px screen-bottom margin. A reversible probe that
added 10 px to Environment made Radar and its map shrink by exactly 10 px without
changing either boundary, confirming that future small widget edits no longer
require manual gap correction. The temporary probe was reverted.

The strongest next candidate for the same instrument-module treatment is Main PC:
its identity, `LIVE / NO SIGNAL` contract, CPU/GPU rows, and RAM/VRAM resources
already have validated semantics. Migrate one module at a time before extracting
shared cross-config components.

## Deferred ideas

Do not introduce a global four-state framework, threshold-colored bars,
percentage labels, severity aggregation, universal status headers, or a center
warning banner during these experiments. Those require independently agreed
semantics and would change the product more than the current visual weaknesses
justify.

Likewise, defer cross-config `Theme`, `StatusLamp`, or `DataFreshness`
abstractions until repeated accepted behavior makes a shared component useful.
Avoid decorative CRT effects, scanlines, excessive colored borders, and novelty
icons because they reduce clarity.

## Evaluation checklist

- Can the purpose and state of each section be understood at a glance?
- Do the left and right groups clearly belong to the same system?
- Are live, stale, warning, and fault states unambiguous?
- Does the treatment remain calm when every widget is visible?
- Is Japanese text readable at the normal viewing distance?
- Can the experiment be reverted as one narrow Git commit?

## Technical guardrails

- Keep private values in untracked local JSON files; commit only example files.
- Validate Python syntax and configuration parsing before a reload.
- Treat `qmllint` exit 255 with no diagnostics as inconclusive on this host.
- Verify each UI change through Quickshell reload logs and a live Wayland
  screenshot.
- Commit infrastructure and each visual experiment separately so rollback stays
  precise.
