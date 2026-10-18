# Quickshell widget study

An isolated, working UI proposal using the accepted
[Liquid Glass implementation](../liquid-glass-lab/README.md). The ordinary preview
uses Soft; the desktop also offers Clear and Diffused, each with an independent optional tint. The ordinary preview never loads a plugin or changes persistent
configuration. A separate, explicitly invoked desktop runner is described below.

## Review

Use the actual desktop as the authority for placement, scale, typography, and
visual balance. Before reviewing, confirm the running widget files match the
source and capture the real left/right surfaces. Routine UI changes are reviewed
there; never reload the material plugin or compositor for a foreground edit.
The isolated lab below is for controlled backgrounds, long/missing values, and
interaction checks. Its in-scene background sampling and scaled window are not
proof of the desktop backend's appearance or placement.

From a graphical session in the repository:

```sh
python3 scripts/quickshell-widget-preview/preview.py run
python3 scripts/quickshell-widget-preview/preview.py run --live
python3 scripts/quickshell-widget-preview/preview.py run --background bright --text dark
python3 scripts/quickshell-widget-preview/preview.py stop
```

This opens a separate ordinary Quickshell window. The composition is designed at
1920 × 1080, the inspected desktop's resolution. A smaller preview window scales
the entire composition for inspection; it is not a responsive desktop layout.
The preview uses installed Adwaita Sans, Material Symbols Rounded, and the
system's Japanese fallback. No fonts or dependencies are installed.

Use the buttons or **F** text, **B** backdrop, **D** direction, **E** edge
case, **Space** motion, and **H** review controls. Buttons support Tab and
Enter/Space. In Lens and instruments, hover abbreviated or truncated labels to read their full text beside
the item, even when review controls are hidden. The older alternatives retain
the study footer. Hover a marked calendar date for its holiday name.
Radar supports previous/current/forecast selection, play/pause, and the original
external JMA link. Rain nearby starts radar playback when multiple frames exist.
Frame controls are hidden when only one frame is available; its observation time
and the JMA link remain visible. Radar controls are transparent at rest, with a
subtle fill for selection and separate hover, press, and keyboard-focus feedback.
Icon controls reveal their description on hover or keyboard focus.

Soft defaults to fixed light text. **Light text / Dark text** switches the whole
foreground explicitly; dark text is useful for a consistently bright wallpaper.
Background selection and motion never change that choice. The choice is
local to this preview run, with no persistent configuration changes.

The default data is explicitly labelled **demonstration data**, including the
device models and ten-minute summaries. Normal fixtures simulate `Live` and
display the outdoor observation time, exercising the same healthy-state UI as the
desktop. Provenance belongs outside the widgets: the demonstration/snapshot
label remains visible when review controls are hidden. A demo badge must not
substitute for reviewing the normal freshness indicator. Partial/missing states and
history collection are separate test cases, not the default daily appearance.
No invented radar image is supplied.
`--live` reuses the existing system and remote collectors every two seconds.
Weather, BLE, holidays, and JMA radar are fetched once per launch and labelled
as snapshots; indoor readings expire after 60 seconds, outdoor readings become
cached after 360 seconds. Relaunch to refresh environmental sources. No
`--automation` or automation settings are passed to the remote collector.
Private configuration is read from the existing XDG config locations and is
never copied into the repository. The snapshot collector removes BLE addresses.

## Composition decisions

Three directions are executable, not just sketches:

| Direction | Composition | Assessment |
| --- | --- | --- |
| **Lens and instruments**, selected | Five 350 px surfaces: Local PC/history and Main PC/history on the left; clock, calendar/environment, and radar on the right. All right-hand edges align. | Keeps the 1196 px central opening, every existing reading while separating the clock and shortening the continuous outlines. |
| **Islands** | Six separate surfaces; summaries and radar step inward at the bottom. | More independent modules, but the extra edges and lower inward surfaces occupy more of the desktop. |
| **Split** | Four surfaces, including a wide lower workstation shelf with remote and history side by side. | Opens the lower-left corner but gives operational data more horizontal weight. |

The selected layout replaces the two continuous rails. `--direction lens` selects it;
`duet` remains a command-line alias. All three right-hand surfaces have the same
350 px width and 302 px content width. Both sides have 20 px gaps between
surfaces and 20 px vertical content insets. Calendar and weather also have
20 px of separation, with their divider centered in the gap. The existing Soft renderer and every type size remain
unchanged.

The clock has its own 158 px surface. Its lower blank area is trimmed by 16 px
without moving or resizing the date, time, or seconds; that height goes to radar.
Calendar and weather share the middle
surface; radar uses a 200 px normal viewport or 176 px when environmental
status needs another line. The shorter map funds the right-hand spacing while
keeping all labels, readings, and controls. Its geographic scale stays fixed;
the kilometre label reflects the smaller vertical coverage. Each PC surface contains its own complete history,
so the redundant machine name inside history is removed. Its collection-window
heading and per-machine missing-data indicator remain visible.

A chip/board symbol and
CPU/GPU label identify each device, with utilization aligned directly below the
label. Temperature and power share the value baseline. A full-width utilization
track and compact Memory/VRAM label-value pairs complete the group. Device models
are small right-aligned captions on the identity line. Display connection and
runtime state are diagnostic hover details, not permanent rows.
Terminal and window symbols distinguish the Arch and Windows machine headings. These are installed interface symbols, not
OS logos. Device rows retain their 8 px inset.
The machine columns align utilization, temperature, and power, identified by
%, °C, and W. Units use neutral ink, with coral and lavender reserved for the
history's Peak temp and Compute category labels. Repeated
thermometer and bolt symbols are omitted; hardware silhouettes identify the
device, and units identify the metric. Hover a reading or unit for its full
metric name. Numbers, device names, and storage rings retain neutral ink.
The history label colors are category accents, not
temperature or power warnings: values and background motion never change them.
The explicit dark-text choice uses deeper variants of the same
two hues. Amber freshness warnings and blue network arrows keep their roles.
The redundant column-heading row is removed to give
device readings more vertical space. Healthy readings have no visible status
dot or label. Other states show a 12 px text label beside the PC name, aligned
to its baseline. Partial/Stale use amber text. No signal/No data gray out the
whole machine group with a fixed, opaque grayscale treatment; cached figures
remain visible and missing values remain dashes. These labels describe telemetry
availability, not proof that a PC is powered off. Hovering the PC name or status
label explains freshness and missing values; the same description is exposed
to accessibility tools. There are no status dots or blinking.
Capacities retain their used/total figures and units. Memory and VRAM replace
the visible percentage with a 16 px usage ring, 6 px after the capacity figure;
the exact percentage remains available on hover. Storage keeps its numeric
percentage and places the same ring 6 px beside it, filling
clockwise from the top to show used space. Its thin arc shares the percentage's
foreground ink and fixed soft shadow, with a faint remaining-capacity track.
There is no hard outline or separate colored badge; the arc and percentage
form one compact reading.
The ring uses the collector's existing percentage, with no new thresholds or
metric. Unknown percentages and unavailable volumes have no ring; zero usage
shows only the track, and full usage closes the circle. Hovering the ring or
capacity or percentage reveals the complete reading. Long-value fixtures include
empty and full volumes; missing-data fixtures include unknown usage and an
unmounted drive. Indoor and outdoor values sit side by side in equal columns with a
16 px gap. Outdoor observation time follows the condition heading with a 12 px
gap and shares its baseline, preceded by a 14 px clock symbol. Hover identifies
it as the Weathernews observation time.
Observed radar frames use the same 14 px clock symbol and 12 px timestamp,
followed by the frame's age. Forecast and Cached states use explicit words in
place of the clock; cached forecasts retain both meanings. Hover identifies
the JMA frame as an observation or forecast. These are source observation/frame
times, rather than download times.
Indoor and Outdoor use 14 px labels above their 38 px temperatures at the top of
the section. Below these readings, the current condition heads the Weathernews
block directly above “Next five hours”: 26 px semibold text beside a 30 px weather
symbol. One Weathernews attribution identifies current conditions and the hourly
forecast, with this scope explained on hover. The condition has the
available heading width after reserving the timestamp, with long descriptions
available on hover when elided.
Missing conditions use the neutral heading “Weather”; unknown symbols are omitted.
The requested temperature/humidity differences and BLE battery/RSSI row
are removed from the UI; values still come from the existing collectors.
Humidity uses a droplet and percentage, with “Relative humidity” available on
hover and through the accessible label. Forecast symbols have descriptive labels,
and all collector weather states have distinct appropriate symbols; unknown
forecast conditions use a dash with “Condition unavailable” on hover. Sunny, wet/snowy,
and thunder conditions have fixed warm, blue, and purple accents respectively.
These colors are shared by current conditions and hourly forecasts.
The Weathernews collector recognizes its sunny icon codes 100, 500, and 600;
code 500 must not become an unavailable condition. The forecast parser regression
test is included in the repository smoke checks.
Radar playback uses familiar play/pause symbols with descriptive accessible names
and hover labels. CPU/GPU names, units, observation times, and data-status labels
remain written out; an icon alone would lose useful distinctions. The symbols
reuse the installed Material Symbols Rounded font, with no new dependency.
The clock and calendar occupy separate aligned surfaces, retaining their reading order.

The clock uses 94 px regular Adwaita numerals followed by 28 px seconds, with a
6 px gap on the same baseline. Both use tabular features; seconds have no
preceding colon. The full timezone
and UTC offset share the date row, in 12 px text on the same baseline as the
19 px date. The complete time fits on one line inside the 350 px panel, without
a separate timezone row. Calendar dates use 15 px text, with 12 px weekday headings.
Calendar rows share a 156 px area: 26 px for six weeks, 31 px for five, and 39 px
for four. This avoids an unused row below shorter months while keeping the
weather and radar positions stable. Today uses a 15 px semibold numeral and a
4 px neutral dot below it. The marker fits within the cell even in six-row
months. The holiday summary follows the final row by 6 px.
The date uses `yyyy/MM/dd (ddd)` with an abbreviated English weekday so the
larger date and full timezone fit together. Its full weekday remains available
on hover and in the accessible label. The larger clock
uses space recovered from the former weather-condition footer, keeping the panel
dimensions and six-row calendar unchanged. Sundays and public
holidays use a fixed red text accent; Saturdays use blue. The weekday headings
use the same colors, with public holidays taking priority over Saturday blue.
Holiday names remain available on hover, without separate dots.
Every date uses the same centered text layout and foreground shadow. Ordinary
dates retain medium weight. Today's semibold numeral and small dot replace the
enclosing ring, keeping the normal weekday, weekend, and holiday text colors.
The dot has a fixed contrasting edge for visibility over the glass. The number
itself stays fully opaque, and its accessible label identifies it as today.
These colors never follow wallpaper changes.
The month and radar headings use 21 px text; their metadata aligns to the heading
baselines. The right-hand group keeps the 94 px clock, 38 px current temperatures,
26 px current weather condition, and a radar viewport filling the remaining
height as its main size hierarchy.
The performance panel consistently uses Local PC and Main PC. System memory
follows the CPU; each GPU groups its utilization, temperature, power, and VRAM.
The 16 px semibold CPU/GPU identity sits directly above 34 px medium-weight
utilization; temperature and power use 28 px, reducing to 22 px for values longer
than three characters. Units use 13 px on the same baseline and remain beside
every reading. The utilization track spans 268 px beneath the readings, with a
3 px stroke; Memory/VRAM values use 14 px text immediately below it. Missing utilization
hides its fill immediately. Network rates use 20 px numerals, 13 px units, and
restrained blue direction arrows. Model names use quieter 12 px regular text,
right-aligned on the identity line. Hover the device symbol, label, or model for
the full model name and available display/runtime diagnostics. Storage capacities follow their drive names instead of floating at the
opposite edge. Storage, Network, and forecast subheadings use 14 px semibold text;
interface and source names sit on the same baseline as their heading. Machine
and history section headings use 21 px type.
CPU uses a square chip icon; GPU uses a wide graphics-card silhouette with two
fans. These fixed-color vector icons appear beside the device labels in both
the live rows and history, so identity does not depend on similar CPU/GPU
lettering. They use the existing Qt SVG support and need no additional font.
History uses two machine summaries with 22 px readings. Each is now directly
beneath its owning machine, so the repeated 15 px machine heading is unnecessary.
Each summary has three fixed peak-temperature columns and a separate 80 px
average-compute-power column, divided by a faint vertical rule. CPU/GPU labels
and Avg sit directly above their values, with °C or W attached to every reading.
Peak temp and Compute category labels share a baseline and retain their warm
and lavender accents in 12 px text. The attached °C and W units use neutral
13 px text. Main PC has two temperature readings; its power column stays
aligned with Local PC. There are no nested card backgrounds.
The two 107 px history sections keep three-digit temperatures and four-digit power readable. Component composition
remains available on power-value hover. Peak power and Hotspot remain omitted
by request. This follows the emphasis on glanceable information and clear
typographic hierarchy in [Apple's widget guidance](https://developer.apple.com/design/human-interface-guidelines/widgets).
The complete left group fits the original 1024 px vertical span: a 624 px
Local PC surface, a 20 px gap, and a 380 px Main PC surface. The utilization column reserves 88 px; temperature
and power each have 90 px, with 3 px numeral/unit gaps. Removing the repeated
metric symbols makes the full column width available to long readings.
Long-value fixtures exercise GPU 1 at
100%, a three-digit temperature, and four-digit power alongside long model names.
History availability reflects only the displayed metrics.
AMD GPU model names prefer the installed libdrm `amdgpu.ids` device/revision
mapping over the generic PCI family name. This distinguishes RX 9060 XT from
other cards sharing its PCI device ID without hard-coding this host's hardware.
If that database or revision is unavailable, the existing PCI-name lookup remains
the fallback. Validate naming with `python3 -B tests/test_system_metrics.py`.
Across the five panels, section titles are 21 px,
readings 13–38 px, and source/unit metadata 11–14 px. Most supporting text uses
12 px; the radar scale uses 11 px. Small labels default to medium weight.
Symbols retain their native strokes and the fixed soft shadow, without the
raised text outline. Radar captions use the same foreground component and
explicit appearance palette as the rest of the panel.
The foreground is rendered after the
glass, without passing glyphs through blur or refraction.

The visual starting point is Apple's
[Meet Liquid Glass, 2:18–3:38](https://developer.apple.com/videos/play/wwdc2025/219/):
defined floating shapes, source visibility, and a distinct foreground layer.
This is a widget layout proposal, not a new optical model or Apple fidelity claim.

### Foreground design principles

Borrow the reasoning from established systems and adapt it to a stationary
desktop display. Apple's [design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
distinguish simplicity from minimalism: recognizable symbols, readable units,
and meaningful status stay visible. Its [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout)
informs baseline alignment and closer grouping within a device than between
sections. Its [color guidance](https://developer.apple.com/design/human-interface-guidelines/color)
supports consistent semantic accents with text or shape preserving their meaning.
Carbon's [direct-label guidance](https://www.carbondesignsystem.com/building-blocks/data-visualization/legends)
informs attached units and usage bars, so readings can be interpreted in place.

For these widgets, type size establishes importance; proximity identifies what
belongs together; color and symbols aid recognition. Interaction feedback belongs
to the control being used. Background motion never changes the foreground palette.
Review refinements on the actual desktop at native size; controlled previews
exercise extremes and interactions without replacing that visual check.

## Current information inventory and mapping

Inspected entry points: `modules/quickshell/.config/quickshell/clock/shell.qml`
and `modules/quickshell/.config/quickshell/performance/shell.qml`, plus their
Python collectors. The current files, rather than older UI notes, define scope.
They do not currently expose sunrise or sunset. By user request, the redesign
now omits indoor/outdoor differences, the BLE battery/RSSI row, the rain-outlook
footer (including “no rain forecast”), and GPU hotspot history.

| Existing information / meaning | Source | Place in Lens and instruments |
| --- | --- | --- |
| Local hours/minutes/seconds, date, timezone and UTC offset | System time, `date +%Z` in existing UI | Right, large clock and timezone line |
| Month grid, weekdays, today, holiday dates/names, ISO week, day of year/year length, next holiday/countdown; missing/cached holiday data | `japanese_holidays.py` and calendar calculations | Right, calendar; accented holiday dates and hover names, metadata, holiday footer |
| Indoor temperature °C, relative humidity %, last seen, fresh/stale/no data | `switchbot_meter.py` | Right, Indoor column and update/status line |
| Outdoor condition, temperature °C, relative humidity %, observation time, live/cached/error state | `weathernews_observation.py` | Right, Outdoor column |
| Five hourly times, conditions, temperature °C and precipitation mm | Same weather collector | Right, five-hour row |
| Radar time, observed versus forecast frame, −5/0/+5 min timeline, nearby rain, viewport km, 2/5 km rings, failed/unavailable tiles, JMA link | `jma_nowcast.py` | Right, radar panel, timeline controls and source link |
| Local platform and uptime days/hours/minutes; remote host and Windows platform | `system_metrics.py`, `remote_metrics.py` | Left, machine headings |
| CPU and each local GPU model, utilization %, temperature °C, power W; GPU display connection/runtime state | Same collectors | Left, each device group; display/runtime diagnostics on identity/model hover |
| Remote CPU/GPU models, utilization %, temperature °C and power W | Remote collector | Left, Main PC |
| RAM and each GPU's VRAM: used/total GiB and utilization % | Same collectors | Left, memory below CPU and VRAM inside each GPU group; used/total figures plus usage ring, exact percentage on hover |
| ROOT and configured SSD/HDD capacities used/total GiB, utilization %, not-mounted state | `storage` plus `storage_volumes` from local collector | Left, Storage; ROOT is preserved separately when absent from configured volumes |
| Network interface, receive/transmit rates in B/s, KiB/s or MiB/s | Local collector | Left, Network |
| Ten-minute CPU/GPU peak °C, each local GPU hotspot peak °C; local and main compute power average/peak W | Existing history contract, reproduced over preview samples | Left, “Last 10 minutes”; Local/Main groups with CPU/GPU peak-temperature pairs and average compute power. Hotspot and peak-power values are omitted by request. |

Storage percentages remain `used / total`, not `df`'s reserved-block-adjusted
percentage. Compute power remains CPU + GPU 1 + GPU 2 locally and CPU + GPU
remotely; it is **not whole-system or wall power**. Incomplete power components
make that sample unavailable. History retains 300 two-second buckets, ignores
missing samples, expires samples by time, and resets after backwards clock
adjustments. Live preview history starts at launch; a snapshot only contains its
observed sample, not ten minutes of fabricated history. The collector exposes
elapsed collection time, capped at ten minutes. Each machine history heading shows
“Since startup” for the first minute, then “Last minute” / “Last N minutes”,
settling at “Last 10 minutes”. There is no separate collected-time label; hovering
the heading reveals exact coverage. “No data” appears when no valid metrics
exist. This measures elapsed time, not completeness of every
sensor; missing samples remain excluded. A backwards clock adjustment also
resets this indicator. Validate these cases with
`python3 -B tests/test_quickshell_widget_history.py`.

`Live` means a recent complete machine sample; `Partial` means recent but missing
fields. After six seconds without a sample, local becomes `Stale` and remote
becomes `No signal`; after 30 seconds local becomes `No data`. Retained numbers
are marked by that status, never silently changed to zero. A real zero remains
zero. Stale indoor temperature/humidity are withheld; cached outdoor values keep
their cached label. Preview provenance is shown outside the widget content;
environmental readings collected once still carry their `Snapshot` status.

The old entry points primarily expose passive information, the JMA link, and
global show/hide IPC. This exploration adds data inspection and radar controls.
It intentionally does not take ownership of the installed show/hide command.

## Material reuse and integration boundary

`preview.py` copies `Glass.qml`, `BackdropSource.qml` and the required
accepted shaders from `scripts/liquid-glass-lab`, and compiles them in a separate
cache. `material-sha256.json` records their source hashes. Every glass property
other than geometry, source coordinates and the fixed Soft setting uses the
accepted component defaults. Flower uses the supplied translation study and
Desert the existing shader/zoom study. No superseded renderer is imported.

`Label.qml` uses directly rendered Qt Quick text: opaque near-white primary ink,
a slightly subdued secondary ink, and a constant soft shadow beneath the glyphs.
The installed Qt Quick MultiEffect blurs only a fixed-color copy of the text;
the foreground glyphs remain sharp. The explicit dark-text choice uses dark
primary/secondary ink and a light shadow.
Neither glyph colors nor their support
sample the background. Status capsules, today's marker, and controls retain
their fixed semantic colors. The old per-label adaptive shader is removed.

This favors temporal stability over maximizing contrast at each instant. On an
almost-white backdrop, light text remains too faint for comfortable reading;
use the explicit dark-text choice. A fixed palette cannot guarantee readability
over arbitrary video, and the severe checkerboard remains visually busy. These
are recorded limitations, not an accessibility contrast certification. Soft
retains this treatment. Desktop Diffused reduces broad background detail; the independent Black tint
supports light foreground colors with a dark backing. Dark text remains only
an isolated-preview diagnostic; it is not a desktop appearance option.

The radar viewport has no background fill: a subtle 1 px outline frames the
accepted glass, with soft white distance rings and light labels in both
foreground palettes. JMA precipitation tiles keep their original colors and opacity.
Map labels keep their fixed light palette even when the
surrounding widget uses dark text. Compact frame/playback controls and the JMA
link sit inside the map's upper corners. Reclaiming the separate button row makes
the viewport taller without increasing the panel height. The shared desktop/Lens
layout fills the remaining space inside a separate panel with 20 px vertical insets:
200 px in the normal state, or 176 px when weather needs an extra status line. The older
alternatives retain 157 px. The center marker and lower distance label remain
clear of the controls.
The collector is invoked with `--viewport-width 344 --viewport-height 252` so
tiles cover the complete displayed area at the existing geographic scale. This
includes overscan beyond the 302 × 200 px displayed viewport; its distance
label uses the actual visible dimensions.
These optional arguments retain the old collector's 280 × 192 defaults for
other callers; distance rings and kilometre labels use the original scale.

**Working here:** actual Quickshell window, both side compositions, all three
directions, Soft with light/dark text, Flower/Desert and bright/dark/detail studies, animated
metrics, long/missing cases, full-text hover, keyboard/pointer controls, existing
collectors, and radar tiles/selection/playback.

## Desktop integration

`DesktopShell.qml` and `DesktopPanel.qml` contain the five independent surfaces.
`PanelContent.qml` owns the selected section layout for production and preview;
`Layout.js` owns their shared dimensions, offsets, and weather status allowance.
`Clock.qml` and `Calendar.qml` preserve the existing contents as separate components;
`Today.qml` combines them for the historical Islands/Split studies.
There is no preview toolbar, keyboard-hint footer, demo data, or background image.
Desktop surfaces retain `WlrKeyboardFocus.None`: controls support the pointer,
while Tab/Enter/Space and their focus feedback are available in the ordinary
preview window. The desktop widgets do not take keyboard focus from applications.
Overflow and holiday hover text appears within the relevant panel. All five surfaces
use `liquid-glass-v1`, the top layer, and **28 logical pixels of shadow padding**
on every side. At 1920 × 1080, every body is 350 px wide, inset 12 px from its
screen edge. The complete group spans y=28–1052, preserving the 1196 px center.
The left bodies are 624 and 380 px high with a 20 px gap; their content has 20 px
vertical insets. The right clock is 158 px high; the calendar/weather surface is
550 px normally or 574 px with status; radar uses the remaining 276 or 252 px.
Both right-hand gaps and vertical content insets are 20 px, matching the left.
Every surface retains 24 px horizontal insets and all foreground type sizes.
The radar viewport is 200 or 176 px high, making room for the larger insets
and calendar/weather separation. Shadow padding may overlap in a
gap; the glass bodies and foreground never overlap.
Only the body accepts pointer input. Smaller logical outputs
scale the content to fit; the backend's padding stays at 28 logical pixels.
The foreground uses ordinary Qt Quick text and needs no backend extension.
History and network values have fixed columns; metric values share a baseline.
Hardware names omit typographic trademarks and redundant suffixes in the compact
view, with the exact collector string available on hover. Current outdoor weather
shows a compact clock and observation time beside the condition heading. Current indoor
readings omit the routine update timestamp. Stale, cached, unavailable, and
other non-live states retain an explicit status line; missing observation time
also remains explicit. The separate status row occupies 24 px only when needed,
so healthy weather moves the forecast and radar up by 24 px.
Radar says Latest and shows observation age.
No foreground palette samples the wallpaper.

Inline symbols align their drawn vertical center to the adjacent text's capital
height, rather than sharing the icon font's baseline. This applies to machine
and device identities, temperature/power, network arrows, history, and weather.
The reference center stays fixed as digits change; units retain text baselines.

`runtime.py` reuses the existing collectors, local configuration and history
contract. Machine metrics stream every two seconds. BLE stays connected, commits
display values every 30 seconds, and becomes stale after 60 seconds without a
reading. Weather refreshes at two-minute boundaries and retains its cached label
after failure or six minutes without a successful refresh. Holidays refresh
daily. Radar follows the original five-minute cycle with +50/+110/+170-second
attempts and forecast enrichment. All tiles are downloaded and PNG-validated
before publishing an immutable local set; failure retains the complete previous
set. At most two sets are retained. Radar playback keeps the original 1600 ms
interval and does not reset on unrelated metric updates.

Validation commands, with no changes to the normal session:

```sh
python3 -B scripts/quickshell-widget-preview/desktop.py check
python3 -B scripts/quickshell-widget-preview/test_runtime.py
```

Run this integration check when changing the desktop shell, surface geometry,
controller, data runtime, or accepted backend. Foreground-only edits to the
shared panel content and its components do not invalidate that integration
receipt. Every start parses all foreground QML before launching; review those UI
edits using the actual desktop and targeted foreground captures. The receipt
also records the complete source fingerprint of its original visual check.

The desktop check loads the unchanged, already validated material backend only
in disposable nested compositors at scales 1, 1.25, and 2. All three use the
running desktop's logical size: a 1920 × 1080 desktop is captured at 1920 × 1080,
2400 × 1350, and 3840 × 2160 pixels. Higher DPI must not shrink the widget layout.
A fixed virtual output inside each owned compositor prevents parent window
management from resizing the capture halfway through a test.
The check rejects a mismatch between the running foreground files and the test
source. It exports one private snapshot of the displayed readings, clock, and
radar frame, retaining its radar tiles, and replays it through the same desktop
shell at every scale. Independent collectors and freshness timers are disabled
during replay. Each run must reproduce the reference's five panel geometries and
snapshot exactly. Without running widgets, the check collects one reference
snapshot on the current monitor's logical size before testing all scales.

`desktop-matched.png` retains the desktop's selected clarity, tint, and foreground.
The Flower/Desert backgrounds remain controlled material fixtures; other named
captures deliberately exercise all 24 clarity/tint combinations. These checks
also cover show/hide, light-text selection, moving backgrounds, and zero pixel
changes in the desktop center. Remote automation is disabled in validation.
Actual compositor captures and a source-bound receipt are written to
`~/.cache/quickshell-widgets/check/`; optical source and binary fingerprints must
also match the accepted lab's full rendering/replacement validation receipt.

Normal-session commands are explicit and require validation of the current
compositor integration:

```sh
python3 scripts/quickshell-widget-preview/desktop.py start
# First load of the tested backend requires this explicit opt-in instead:
python3 scripts/quickshell-widget-preview/desktop.py start --load-backend
python3 scripts/quickshell-widget-preview/desktop.py toggle
python3 scripts/quickshell-widget-preview/desktop.py status
python3 scripts/quickshell-widget-preview/desktop.py clarity clear
python3 scripts/quickshell-widget-preview/desktop.py clarity soft
python3 scripts/quickshell-widget-preview/desktop.py clarity diffused
python3 scripts/quickshell-widget-preview/desktop.py tint off
python3 scripts/quickshell-widget-preview/desktop.py tint black
python3 scripts/quickshell-widget-preview/desktop.py tint white
python3 scripts/quickshell-widget-preview/desktop.py tint blue
python3 scripts/quickshell-widget-preview/choose.py
python3 scripts/quickshell-widget-preview/desktop.py stop
```

The picker groups **Clarity: Clear / Soft / Diffused** and
**Tint: Off / Black / White / Blue / Teal / Green / Amber / Rose**, marking each current selection.
Tint defaults to Off. Choosing one attribute
preserves the other. Escape leaves both unchanged. All combinations use stable
light text, matching the radar labels. The playground's text-color switch is a
preview control, separate from material tint.

Clear preserves detail without added smoothing. Soft adds restrained local
filtering and remains the default. Diffused uses broad diffusion with the narrow
filter disabled. Clear was previously named Sharp; Soft was previously named
Clear. The effects are unchanged, and CLI values use the new names. Black tint
mixes in black at approximately 64% opacity; White and the five color tints use
approximately 32%. The shared lab `tints.json` defines the palette for the playground,
desktop shader, and picker. Tint replaces the former Natural/Dark tone setting;
use `off` or `black` respectively. Geometry,
refraction, highlights, data, and typography remain consistent across choices.
The old `appearance` presets and independent `softness` toggle are removed.

`clarity` or `tint` without a value reads that attribute. `status` reports both.
Settings change immediately without a reload or saved preference. Startup uses
`--clarity soft --tint off`; either can be selected explicitly on `start`.
The existing picker command and shortcut continue to work. The backend must be
updated to the validated binary before using these commands; the controller
never automatically reloads the compositor plugin.

Desktop validation covers all 24 combinations at scales 1, 1.25, and 2,
including moving backgrounds and unchanged pixels outside the glass. Material
checks cover brightness and detail suppression, exact round trips, stationary
feedback, zero-presence identity, independent tint/clarity, invalid requests,
and defaults after a backend reload. Existing render captures provide regression
comparisons for the unchanged Clear, Soft, and Diffused appearances.

`start` defaults to Soft/light text and preserves the original remote collector's
automation flags and existing settings. Do not run it alongside the old clock
and performance processes. It never replaces or reloads an already loaded
backend; it checks the mapped binary before reuse. `stop` closes these widgets
and leaves the backend loaded. The appearance picker uses the existing `wofi` dependency.
No command changes the login configuration or logs out/restarts Hyprland.

For login cutover, replace the old clock/performance/legacy-glass startup trio
with `desktop.py start --load-backend`, point the visibility shortcut to
`desktop.py toggle`, and the appearance shortcut to `choose.py`. Remove the
superseded glass configuration include. Back up and review the local compositor
configuration before applying that separate step. Legacy entry points and
private configuration are retained for rollback. The existing `widgets-toggle`
helper routes to the new owner when its session is recorded and retains the old
clock/performance IPC fallback otherwise. Local cutover records and the original
configuration backup path are stored in `~/.cache/quickshell-widgets/cutover-applied.json`;
the machine-specific configuration itself is not committed to this repository.

## Evidence and validation

```sh
python3 scripts/quickshell-widget-preview/collect.py --output ~/.cache/quickshell-widget-preview/snapshot.json
python3 scripts/quickshell-widget-preview/preview.py capture --snapshot ~/.cache/quickshell-widget-preview/snapshot.json
python3 scripts/quickshell-widget-preview/preview.py check --live
python3 -B scripts/quickshell-widget-preview/test_collect.py
./tests/smoke.sh
```

`capture` and `check` require a graphical session (`WAYLAND_DISPLAY`), open their
own disposable nested Hyprland compositor, disable physical seat acquisition and
systemd environment export, identify the exact child PID/socket, and terminate
only owned processes. They contain no plugin load/reload call. `capture` uses the
actual Qt Quick renderer at 1920 × 1080; `check` runs the actual Quickshell entry
point and grabs its scene, excluding the nested compositor's startup banner.

Fixed-name artifacts live in `~/.cache/quickshell-widget-preview/captures/`:

- `quickshell-live-soft.png`, `quickshell-live-soft-dark-text.png`: actual Quickshell with
  collectors; `quickshell-live.json` records the observed state and scope.
- `direction-{0,1,2}-soft.png`: all three complete compositions.
- `soft-{flower,desert,bright,dark,detail}.png`: Soft background matrix.
- `soft-bright-dark-text.png`: bright case with the explicit dark-text choice.
- `soft-long-values.png`, `soft-missing-data.png`: deterministic stress cases.
  Stills wait for usage-bar transitions to settle before capture.
- `soft-motion.mp4`: six seconds, 1920 × 1080, 20 fps; Flower then Desert with
  changing metric values. Fixed-time rendering is not a real-time benchmark.
- `results.json`: dimensions, layout bounds, keyboard, pointer, overflow and
  animation checks. Also compares actual foreground-only RGBA renders with data
  held constant over five backgrounds and four motion phases for each of two
  palettes: Soft light and Soft dark. All 40 renders must remain
  pixel-identical to their palette's reference. `material-sha256.json` is one
  level above the captures.

The directory is bounded by those fixed names and overwritten on rerun. Private
collector snapshots stay outside the repository. No install, unstow, package
change, or real-home deployment is part of validation.

### Lens and instruments validation

The native foreground field inventory was compared with the previous two-panel
layout for normal, long-value, and missing-data fixtures. All existing readings,
units, metadata, and accessible descriptions remain. The only removed entries
are the repeated Local PC/Main PC labels within history; each history now belongs
to its machine surface and has its own collection-window heading. Rendered glyph
bounds fit every owning panel in all three fixtures. The unchanged material also
passed desktop integration at scales 1, 1.25, and 2, including show/hide, stable
foreground palettes, moving backgrounds, and a clear desktop center.
