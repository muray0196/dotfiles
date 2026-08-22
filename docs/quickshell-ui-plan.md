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

## Next experiment

Test a restrained section-header treatment independently. It should strengthen
the hierarchy of `STORAGE`, `GRAPHICS`, indoor/outdoor weather, and radar without
adding colored boxes or reducing the scan speed of the measurements.

## Later experiments

Once the shared structure feels coherent, test one variable at a time:

- a slightly more mechanical UI font for small labels while retaining readable
  Japanese text;
- flatter or more tactile section headers;
- denser alignment grids and numeric columns;
- subtle monochrome texture or stepped edges, only if they do not reduce
  contrast or scan speed.

Avoid decorative CRT effects, scanlines, excessive colored borders, or novelty
icons. They add retro styling but work against clarity.

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
