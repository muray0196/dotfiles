# Independent Clear material prototype

This is a separate optical renderer, not the next patch in the optics1–24
series. The accepted optics24 desktop remains the default and rollback point.
The prototype targets static Clear widgets; it is not wired into the everyday
mode picker or startup restoration.

## Design

The new [fragment shader](../scripts/quickshell-glass-rework/clear.frag) has three
independent responsibilities:

- **Transmission:** one continuous map moves background sample positions inward
  along the shape normal. A circular-sag profile occupies half the corner radius
  and reaches a flat centre with zero displacement and slope. Its maximum
  excursion is 1.3 times the radius. The coloured folds are transported image
  detail, not a separately coloured edge strip.
- **Lighting:** an elliptical roundover reflects two elongated virtual area lights. Two
  much weaker dark areas in that environment provide definition on pale
  backgrounds. Lighting is averaged over four subpixel positions. These normals
  are independent of the transmission map; no previous cap, Fresnel stack,
  environment-colour normalization, or rim-blending formula is included.
- **Foreground:** native text and dividers composite at full resolution. A
  filtered foreground coverage estimate supplies local backing. Empty areas
  receive no global tint, dimming, saturation change, or adaptive frosting.

The circular-sag family was retained because the measured Apple boundary
sequence supports it, not because the old renderer used it. That evidence does
not uniquely determine Apple's formula or parameters. Simple power profiles
also fit the two calibration frames, but performed worse on the other frames.

Refraction filters the actual source footprint. A small angular spread grows
with the ray's travel through the roundover; it is zero on the flat face. Mip
levels cover the footprint's short axis, with eight samples along its long axis.
This explicit filter needs no hardware anisotropy extension. Where the ray map
bends substantially within a pixel, four subpixel rays replace the single local
approximation, with a gradual transition between them.

The reflection's roundover width combines a small logical-pixel base with a
radius-relative term. Larger controls therefore carry a broader reflection;
small panels retain a restrained shoulder. Elongated lights let the reflection
wrap around corners without changing the outer contour or the refraction map.
The widgets still have circular corner arcs, not Apple's continuous corners.
Geometry and lighting use physical pixels and the compositor's monitor scale.

The [capture adapter](../scripts/quickshell-glass-rework/capture.patch) operates
directly on pinned HyprGlass v0.10.0. It captures the background, prepares mip
levels, supplies the client's radius, and draws a restrained shadow after
capture. The foreground clear includes the filter's neighbourhood: otherwise
uninitialized or old alpha outside the client can create a dark seam. No patch
from the previous optical series is applied.

Legacy optical settings in the desktop's Lua presets do not control this
prototype. The only material setting it consumes is coverage/opacity; radius
and the remaining uniforms describe geometry, texture mapping, or composition.
The optical constants live together in the new shader. This intentional break
keeps earlier tuning from silently influencing the experiment.

## Build

The builder requires the existing compiler/build tools and Hyprland **0.56.2**
headers. It uses Python's standard library, verifies the upstream commit, builds
in a temporary directory, and records source/library hashes. It does not install
or load a plugin, change the desktop, or enable startup behaviour. Existing
outputs are never overwritten.

```sh
python scripts/quickshell-glass-rework/build.py --output /tmp/clear-rework-build
```

The output version is `0.10.0-clear-rework2`. The same experimental binary permits
large reference circles and the 44 px widget corners. This is a widget-layer
prototype, not a replacement for HyprGlass's general window materials or the
existing Clear/Blurred picker. Keep the accepted binary available when running
temporary native comparisons.

## Evidence and limits

The optical reference is [Meet Liquid Glass, 2:18–3:38](https://developer.apple.com/videos/play/wwdc2025/219/),
especially the moving light/dark boundary, neutral capsule, and three flower
controls. Apple's separate discussion of geometry-responsive highlights in the
same video supports evaluating illumination separately from background folds.
This is an interpretation of the footage, not recovered Apple shader source.

Native comparisons cover photographic and grid backgrounds, uniform blue,
white and dark backgrounds, translated colour boundaries, circles, capsules,
widget-sized rounded rectangles, and foreground text/dividers. Analytical
checks cover source bounds at four display scales. The actual compositor
shader is compiled and rendered; a mock image is not used as implementation
proof.

### Rework 2 validation

The clean build was rendered in 30 native scenes: 22 at scale 1, plus four panel
scenes each at scales 1.25 and 2. The seven actual desktop widgets were also
rendered, and their foreground and layout were visually checked. Source and
library hashes matched the build receipt. The accepted renderer, saved and
runtime Clear selection, widget visibility, and monitor layout were restored
after the comparisons.

The flat centre was pixel-identical to rework 1 in grid, diagonal-boundary,
uniform-blue, and white panel captures. Filtering remains confined to travelled
rays. Five Apple moving-boundary frames still placed the transmitted crossings
within the approximate geometry measurement's precision: 9 of 2,092 binary
strip rows differed, versus 7 previously. This is a narrow calibration check,
not a visual similarity score or an improvement claim.

The selected explicit filter removed the small ripples seen with hardware
anisotropy in intermediate variants. Comparing scale-1 grid edges with scale-2
rendering averaged to logical pixels gave a mean channel difference of 0.84/255.
That check covers display-scale consistency, not fidelity to Apple. In a short
desktop probe, the seven layers' aggregate composite time increased from about
0.30 to 0.43 ms per measured frame; this is not a sustained performance benchmark.

The 11 focused glass tests and repository smoke suite passed. The smoke suite's
unrelated Node provisioning step was skipped because `mise` was unavailable;
the renderer needs neither tool, and its native build and rendering checks ran.

The prototype remains separate from the default. Apple's continuous corner
geometry and foreground treatment on bright or busy backgrounds still need
work. Matching a handful of boundary crossings does not establish overall
visual parity. Interaction, HDR output, and arbitrary window materials are
outside this experiment's current validation.
