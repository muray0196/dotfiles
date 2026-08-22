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
- Segmented utilization bars and square status indicators.
- Current fonts, Material Symbols icons, per-metric colors, content order, and
  behavior.
- Compact, legible information hierarchy with accurate status semantics.

This baseline is the rollback point before further design experiments.

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

## Next experiment

The first experiment should change only the following:

- shared panel edge;
- title-row rules;
- divider rules;
- spacing tokens.

It must not change data, behavior, content order, fonts, icons, or semantic
colors. Evaluate both sides together on the live desktop before keeping it.

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
