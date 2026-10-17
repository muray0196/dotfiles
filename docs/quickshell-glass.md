# Optional Quickshell glass materials

The two everyday modes are **Clear** and **Blurred**. Clear is the accepted
appearance previously called `rounded`; Blurred adds background softness while
preserving its geometry, refraction, highlights, tint, and foreground treatment.
These are local modes, not Apple's Regular/Clear material variants.

Clear is the baseline for optical refinement; interaction-driven movement is
outside the scope of these passive desktop widgets. The optics22 build keeps
the same panel sizes, spacing, content, and dividers:

| Treatment | Appearance | Corner radius |
| --- | --- | --- |
| `clear` | Accepted clear glass volume and rolled rim (`rounded` alias) | 44 px |
| `blurred` | Same glass with a softer transmitted background | 44 px |
| `soft` | More scattering, gentler refraction | 22 px |
| `sculpted` | Stronger lensing and more defined highlights | 22 px |

The older `liquid` experiment retains its square geometry and material parameters.
The previous square `clear` fallback is now named `legacy-clear`.
The approximation does not implement Apple's fluid control morphing or interaction lights.

The current `clear` treatment prioritizes clearer transmission. It uses a
single light blur pass, restrained adaptive scattering, no coloured tint, and
less background dimming. The broad specular sheen is disabled. The rim reflects
softened nearby colour, with separate fixed neutral highlights at the silhouette.
Their width follows the surface normal and their position follows the light
direction. A broader, faint shoulder fades continuously into the face,
without a separate inner border. The optical model traces transmission through curved front
and back surfaces. Its shallower back cap and closer background plane restrain
excessive focusing at the outer corners. The roll still compresses and locally
reverses background detail before joining the flat centre smoothly. The front uses a fifth-order radial cap; the tapered rear retains power 9/4. The
highlights account for the pixel's surface-angle footprint, and reflected
colour receives the same tone response as transmission without a separate white
lift. Compressed
fine detail receives bounded footprint filtering at the clear rim. A bounded internal-reflection
approximation returns colour from the next surface hit, so the outer lip can
differ from the adjacent transmitted band. Local dimming follows the rendered
text and separators, leaving empty regions clearer.
`blurred` changes only `blur_strength` from 0.32 to 1.15 and `blur_iterations`
from 1 to 2. The sharp rim mix, local dimming, adaptive scattering, and colour
parameters are inherited unchanged. `soft` remains an older experiment with
different geometry and lighting, rather than the everyday blur mode.

Run `./scripts/quickshell-glass.py` (or `choose`) for the two-choice `wofi` picker.
It marks the current saved mode; Escape leaves the selection and desktop alone.
Direct `clear` / `blurred` commands do not require `wofi`. The choice applies to
both columns and is remembered for the existing startup restoration. No widget
input regions change, so desktop clicks still pass through the widgets.
An optional local Hyprland shortcut can open the picker:

```lua
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("/absolute/path/to/dotfiles/scripts/quickshell-glass.py choose"))
```

Old `rounded` commands and saved selections resolve to Clear without changing
its appearance. Explicit `clear` now selects the accepted curved material;
use `legacy-clear` to request the earlier square fallback.

Mode validation on the running desktop: both choices and Escape were exercised
through the actual picker. The resolved Clear preset matches the previous
rounded preset in every field; Blurred differs only in its two blur settings.
All three blank white captures (previous / Clear / Blurred) were pixel-identical.
Both modes were also inspected on fixed photographic and window-pattern
backgrounds. Blurred restored correctly after unloading the renderer and
removing the runtime selection, using the saved choice; an actual reboot was
not performed. Widget geometry and the wallpaper process stayed unchanged.
The mode-selection/restoration tests and repository smoke checks passed.

This direction follows Apple's distinction between transparent Clear material
and adaptive Regular material in the [Materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).
Apple also describes a separate highlight layer whose lighting follows the
geometry and defines the silhouette in [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).
The local approximation uses a fixed light direction; it does not reproduce
Apple's moving environment lights or device-motion response.

Apple also describes colour informed by surrounding content, including reflected
wallpaper around sidebars, in its [design introduction](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/).
The optics5 rim follows that direction: surrounding colour supplies the broad
reflection and localized light supplies the bright highlights. This is a local
approximation, not a reconstruction of Apple's unpublished colour formula.

The foreground is treated separately from the accepted clear material. The
six information widgets use flat Adwaita Sans lettering with tabular figures,
stronger headings, quieter single-line separators, and rounded status markers
and progress tracks. The calendar and forecast rely on aligned columns instead
of cell borders; average and maximum compute power sit side by side. Every data
field is retained. Panel widths, current heights, and positions remain unchanged.

`GlassText.qml` leaves normal text flat; the existing renderer still provides
soft local dimming behind foreground alpha. It adds no new offscreen effect.
Rain Radar uses its own `Theme` instance with `legacyContent: true`, preserving
its earlier glyph shadow, paired separator, colours, and layout. No renderer or
glass-preset changes are needed for the content redesign.

Apple's Regular material automatically adapts foreground colours; its Clear
variant instead calls for bright, substantial labels and sufficient dimming,
which can be localized for small elements. The local contrast treatment does
not reproduce Apple's automatic vibrancy or foreground colour switching.

## Renderer change

[The patch](../scripts/patches/hyprglass-0.10.0-edge-clarity.patch) applies to
[HyprGlass v0.10.0](https://github.com/hyprnux/hyprglass/releases/tag/v0.10.0),
commit `84c1a5ab217101a317d4edaab7fba2efcc1bf346`, for Hyprland 0.56.2.
The upstream [BSD license](../scripts/patches/hyprglass-LICENSE) is retained.

- Adds a preset-only `edge_clarity` value, clamped to 0–1 and defaulting to 0.
- For opted-in layers, captures the actual background at full resolution before
  blur, alongside the existing blurred sample. Both share the refraction field.
- Blends the clear rim into the scattered interior over 1.8 times the configured
  edge thickness. Both use the same brightness and colour response, avoiding
  a bright coloured band around the panel. Window rendering and
  presets without `edge_clarity` keep their original material.
- Invalidates remaining layer samples when another layer closes, addressing
  the stale bottom-layer image seen during this trial.

[The additional curved-surface patch](../scripts/patches/hyprglass-0.10.0-curved-surface.patch)
applies after the edge-clarity patch. Its preset-only controls default to zero,
so existing presets retain their rendering:

- `layer_radius` matches the QML fill in logical pixels (0–48). It applies only
  to alpha-mask layers; protocol-region shapes keep their existing geometry.
- `rim_width` selects a consistent logical width (0–40), capped at a quarter
  of the panel's smaller dimension. Zero preserves the original proportional rim.
- `surface_curve` controls a smooth rounded cap (0–3). Its contour gradient
  drives the refracted ray, angular reflection, and directional highlights.
  Refraction uses Snell's law with an index of 1.45 and an adjustable effective
  thickness. Reflection uses Schlick's angular response; this remains a
  screen-space approximation, not a reproduction of Apple's implementation.
- `shadow_strength` (0–0.3) and `shadow_size` (0–20 logical pixels) add a neutral
  shadow using Hyprland's existing renderer. The shadow is drawn after background
  capture to avoid feedback and stays within the layer's padded damage bounds.

The curved presets replace the client's straight border lines with the renderer's
continuous highlights. They keep the sharp rim and centre on the same colour
response, with no chromatic fringing. Native window shadows remain unchanged.

The older curved model uses a fixed effective thickness: at scale 1 on a straight
edge, `rounded` previously displaced the sample by approximately 63 px at the
boundary and 33 px at 16 px inward. This created a broad reversed-image band.
The optics6 integrated lens below replaces that profile for `rounded`;
`liquid`, `soft`, and `sculpted` keep their previous refraction.

[The adaptive-material patch](../scripts/patches/hyprglass-0.10.0-adaptive-motion.patch)
applies after both earlier patches and adds two preset-only controls, defaulting
to zero:

- `adaptive_scatter` (0–1) measures local contrast in the softened background.
  Detail that survives the normal blur blends toward a broader Gaussian sample
  and gains a small neutral dim. Smooth spatial weights protect the outer rim
  and leave uniform backgrounds unchanged. This is spatial adaptation; it does
  not classify content or temporally average the wallpaper.
- `material_motion` (0–1) enables the widget visibility controller. The complete
  premultiplied composite, including text and opaque radar content, fades over
  220 ms on entry and 180 ms on exit. Refraction settles through the last 18% of
  its depth, highlights develop, and the shadow follows the same progress.
  At full visibility, the calibrated refraction is unchanged.

Quickshell sends one visibility request per toggle, using the native Lua callback
or legacy dispatcher according to the session type. A temporary 16 ms compositor
timer damages only the matching widget surfaces and disarms when settled. The
client keeps exiting surfaces mapped for 260 ms, cancels that delay on reversal,
and preserves requested visibility across QML reloads. No global animation
setting is changed. `hyprctl hyprglass motion` reports progress and timer state.

This adds one background copy and one cached full-resolution texture per glass
panel. The seven panels retain 312 px widths, 12 px screen margins, and 10 px
vertical gaps. It reuses the existing damage-driven update path and does not enable
continuous refresh. No fixed power or frame-rate claim is made.
Adaptive materials additionally cache a quarter-resolution broad-scatter texture
per panel, refreshed through the same background-damage path, with two separable
blur iterations and five additional background samples per shaded pixel.

[The adaptive-rim patch](../scripts/patches/hyprglass-0.10.0-adaptive-rim.patch)
applies fourth. Its preset-only `adaptive_rim` control (0–1, default 0) reuses the
cached broad background for one additional sample near the contour. It gives
the thin reflection a bounded colour influence and smoothly adjusts its strength
with local brightness. It never normalizes dark colours to full intensity. A
soft inner dark edge grows on bright backgrounds, strongest opposite the light.
With the current 2 px bevel, the effect ends within 3.8 logical pixels of the
contour. It leaves the Fresnel response, transmission, refraction, foreground,
and broad sheen setting unchanged. Only `rounded` opts in, at 0.85; `soft` and
`sculpted` explicitly retain their prior lighting. No extra texture, timer, or
GPU readback is added to the current adaptive material.

[The shaped-light patch](../scripts/patches/hyprglass-0.10.0-shaped-light.patch)
applies fifth and adds two preset-only controls, both disabled by default:

- `shaped_reflection` (0–1) uses the existing softened background sample for
  reflection colour in both the thin bevel and the Fresnel layer. It retains
  local brightness and colour instead of normalizing dark saturated colours or
  clamping reflection channels close to white. A separate fixed light produces
  narrow bright cores with soft shoulders, concentrated by the curved normal.
  It adds no light movement or pointer response. The old broad specular control
  remains at zero in `rounded`.
- `local_dimming` (0–0.8) creates a half-resolution copy of the current client
  surface, applies one separable Gaussian blur, and samples only its alpha for
  the backing. The faint panel fill is ignored. Text, separators, and content
  are then composited unchanged. This permits reduced whole-panel dimming while
  keeping a soft backing near foreground content. The scratch texture is reused
  but refreshed on each glass composite to avoid stale text silhouettes; it adds
  one copy and two blur passes per drawn panel, without introducing a timer or
  GPU readback. At scale 1 the blur sigma is approximately 4 logical pixels.

Only `rounded` enables these controls. `soft` and `sculpted` explicitly retain
their previous reflection and dimming behavior. Background refraction, panel
shape, and visibility transitions are unchanged.

[The integrated-lens patch](../scripts/patches/hyprglass-0.10.0-integrated-lens.patch)
applies sixth and adds the preset-only `integrated_lens` control (0–1, default 0).
Only `rounded` enables it. The new cap is a product of two smooth axial height
profiles, each obtained by integrating the slope into `1 - (1 - t)^3`. Its
analytic gradient supplies the refracted ray and the existing directional
lighting. Both slope and curvature reach zero at the flat centre, and the corner
joins have no piecewise contour transition. A thin basal layer retains a small
sample offset at the silhouette; optical thickness then grows with the cap.

At the optics6 settings, straight-edge displacement peaks at approximately 16 px,
12 px inside the edge, and fades smoothly to zero at 45 px. The old broad image
reversal is removed while magnification and compression remain visible. A native
grid capture and numerical mapping checks cover the straight edges and corners
of the 162–527 px-high panels. These are appearance and mapping checks, not a
frame-rate benchmark or a claim to reproduce Apple's shader. The implementation
adds arithmetic only, with no new texture, render pass, timer, or dependency.
The existing colour response, foreground backing, visibility motion, panel sizes,
and separate-panel spacing are retained.

[The edge-balance patch](../scripts/patches/hyprglass-0.10.0-edge-balance.patch)
applies after the integrated lens. It fixes a foreground-alpha sampling bug:
the original layer buffer cleared only the panel rectangle, while the new local
backing copied an additional 32 px of padding before blurring it. Uninitialized
or previous surface pixels in that padding could become a dark outline around
any widget. When local backing is enabled, the clear now covers the entire
padded sampling footprint, clipped to the framebuffer. Text backing is retained.
This adds a bounded padded clear, with no new texture, timer, or render pass.

For integrated lenses, the patch also broadens the angular coverage of the
existing highlight without widening its contour core or adding a surface sheen.
The light includes 8% of the surrounding reflected colour; its brightest corner
remains a specular highlight.

The `rounded` preset reduces `adaptive_rim` from 0.85 to 0.18, removes the separate
`bevel_shadow`, and reduces the outer shadow from 0.16/10 px to 0.06/8 px. These
changes keep the edge from reading as a dark frame. `soft` and `sculpted` retain
their earlier shadow values. Refraction, scattering, and foreground backing are
unchanged. Apple's [2026 design update](https://developer.apple.com/videos/play/wwdc2026/102/)
describes a darkened edge paired with brighter highlights; the balance here is
an approximation tuned for these desktop panels, not Apple's internal formula.

[The contour-light patch](../scripts/patches/hyprglass-0.10.0-contour-light.patch)
applies eighth. It replaces the overlapping bevel and corner-glint treatments
when both `integrated_lens` and `shaped_reflection` are enabled. The narrow lip
uses the actual silhouette normal; the broader integrated cap continues to drive
transmission without changing its displacement. Two fixed area-light lobes extend
along the top and bottom and fade around the corners into quieter side edges.
A narrow crest and a soft inward shoulder add reflected radiance coloured by the
nearby background, with a bounded neutral contribution. The subdued dark return
is confined to the lip. This replaces the older broad directional inner shadow.

This was informed by direct visual inspection of Apple's [lensing and highlights
close-ups](https://developer.apple.com/videos/play/wwdc2025/219/) at 2:46 and 11:13:
the crest, inward shoulder, quiet sections, and local colour work together. The
new shader is an approximation of those visible cues, not Apple's implementation.
It adds no texture, render pass, timer, moving light, or dependency. Refraction,
foreground backing, layouts, and the padded-clear fix remain unchanged; the
other styles retain their previous lighting.

[The edge-volume patch](../scripts/patches/hyprglass-0.10.0-edge-volume.patch)
applies ninth. For integrated lenses, it replaces the product of two axial ramps
with a smooth fourth-power cap. The analytic surface gradient drives refraction,
the highlight direction, and the inward reflection shoulder. A small minimum
optical thickness keeps transmission bounded near the clipped silhouette.

The reflected colour comes from three softened background samples just outside
the silhouette, spread along its tangent. The footprint stays within the existing
32 physical-pixel padding, including at higher monitor scales. Fresnel reflection
blends with transmission instead of adding brightness to a uniform background.
The narrow crest and restrained return edge are retained; no broad surface sheen
or moving light is added. This adds two background reads near the rim, with no
new texture, render pass, dependency, or foreground effect.

The rounded preset uses refraction strength 1.6 instead of 2.1: the new corner
profile otherwise compresses the background enough to reverse its mapping.
Straight-edge displacement now peaks at about 12.3 px, still fades to zero at
45 px, and remains visible in the grid capture. This trades some displacement
for a smoother corner bend. `soft`, `sculpted`, and non-integrated styles retain
their earlier optical model. Panel geometry, clear-centre settings, and content
remain unchanged.

The supplied Control Center and capsule-toolbar images informed this refinement,
alongside Apple's discussion of lensing, size-dependent material depth, and
geometry-dependent highlights in [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).
Those references establish visual behaviour, not Apple's private shader formula.
This remains an approximation with fixed lights and screen-space transmission.

[The edge-return patch](../scripts/patches/hyprglass-0.10.0-edge-return.patch)
applies tenth. The supplied volume-slider reference shows a lavender outer lip
beside a blue transmitted band, even though the immediately adjacent exterior
is blue. Copying only that exterior colour cannot reproduce this distinction.

The new return reflection samples the softened background farther inward along
the curved surface direction. Three tangential samples soften the footprint;
the reach is limited by the panel dimensions. A narrow profile transfers that
colour to the lip, and the existing bright crest stays a separate light response.
There is no fixed lavender colour or per-widget tint. Colour transport is relative
to the transmitted scene, preserving the material's tone on uniform backgrounds.
A bounded neutral lift limits unintended dark framing without clipping colours.

This is an inferred screen-space model for the visible colour separation, not
evidence of Apple's internal reflection algorithm. It follows the distinction
between adaptive environment colour and geometry-dependent highlights described
in [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).
It adds three background reads only within 12 logical pixels of the silhouette,
with no new texture, render pass, moving light, or dependency. The optics9
refraction field and all material settings, foreground, and geometry are retained.

[The coherent-rim patch](../scripts/patches/hyprglass-0.10.0-coherent-rim.patch)
applies eleventh. It replaces the fixed 3.5-rim-width return footprint with one
derived from the same refracted direction and effective cap thickness as the
main lens. Three depth traversals approximate a return trip plus transmission;
the existing panel-size bound remains. The footprint contracts with the existing
visibility transition's optical depth. The cap's angular Fresnel term controls
the return's inward roll-off, with a smooth cutoff before 12 logical pixels.

At the current `rounded` settings, straight-edge reach varies from about 88 px
at the silhouette to 76 px at 5 px inward, instead of the fixed 105 px. Peak
colour replacement drops from 96% to about 55%, retaining a separate coloured
lip without letting distant background colour dominate it. Uniform backgrounds,
main transmission, the narrow bright crest, foreground, and panel geometry retain
their existing treatment. No new texture reads, render pass, timer, or dependency
is added.

This is a geometry-constrained screen-space approximation. The three traversals
are not intersections traced through front and rear surfaces, and the normalized
angular response and 0.72 ceiling are artistic controls, not physical reflectance.
It does not simulate fluid dynamics. The shared curvature and coherent response
to changing backgrounds provide the material cues; there is no idle ripple or
moving sheen. See [PBRT's reflection and transmission discussion](https://www.pbr-book.org/4ed/Reflection_Models/Specular_Reflection_and_Transmission)
for the physical direction and Fresnel principles that inform this approximation.

[The rounded-meniscus patch](../scripts/patches/hyprglass-0.10.0-rounded-meniscus.patch)
applies twelfth. The integrated cap now follows the rounded depth contours all
the way to the silhouette. Its height rises as `sqrt(1 - (1 - t)^4)` and joins
the flat centre with zero slope and curvature. A half-logical-pixel regularizer
keeps the outer slope finite. The unnormalized contour gradient provides the
surface normal, retaining the corner-dependent spacing of those contours.
This replaces the very thin outer corners of the previous fourth-power cap.

The same normal controls transmission, the return colour's angular falloff,
and a restrained inner reflection from two fixed area lights. That reflection
sits on the curved shoulder, changes width around corners, and fades completely
before the flat centre. The existing narrow crest remains. Broad sheen and
idle motion remain disabled; this does not simulate fluid dynamics.

`rounded` uses refraction strength 1.85 with this profile. The maximum sampled
displacement is about 19.4 logical pixels, concentrated near the outer rim.
Local image reversals are allowed inside the corner optical band to form
compressed, curved pockets of background detail. The flat centre keeps zero
lens displacement. `soft`, `sculpted`, and non-integrated materials retain their
previous optical profiles. The `rounded` corner radius increases from 20 to
28 logical pixels in both QML and the renderer. Panel widths, heights, spacing,
foreground, scattering settings, and the padded-alpha clear fix are unchanged. The shader
adds arithmetic only, with no additional texture reads, render passes, timers,
or dependencies.

The supplied capsule and circular-control references informed the fuller edge
profile. This is a local interpretation of their visible lensing, not Apple's
unpublished shader or a physically traced front-and-rear-surface model.

[The rolled-volume patch](../scripts/patches/hyprglass-0.10.0-rolled-volume.patch)
applies thirteenth and replaces the integrated meniscus's single-surface sample
offset. In optics13, `rounded` has a 44 logical pixel roll and matching QML corner
radius. Panel dimensions, spacing, content, and foreground contrast stay the same.

For the distance `q` outside the rounded rectangle's inner box, the front and
back heights are `+/- rise * radius * sqrt(1 - (length(q)/radius)^4)`. This cap
joins the flat centre with zero slope and curvature. Its analytic normal bends
an incoming ray using IOR 1.45. Twelve bisection steps locate the back surface;
a second refraction then projects the ray onto a background plane eight logical
pixels below the solid. The flat centre skips intersections and has zero offset.
The wider volume produces visible curved pockets and compressed background bands.

Near the exit's critical angle, one reflected ray is intersected with the front
surface. Its hit point supplies a softened screen-space colour footprint. This
replaces the arbitrary three-traversal return distance. Further internal bounces,
off-screen scenery, and energy transport are not simulated: the returned colour
is a UI approximation, with a luminance floor to prevent a heavy dark frame.
The exit projection also caps grazing-ray slope. This is not a general-purpose
physical renderer or a reconstruction of Apple's unpublished implementation.

A fixed, azimuth-weighted light follows the surface elevation around straight
sides as well as corners. Its subdued reflection stays on the roll; broad sheen
and idle motion remain off. Non-integrated styles retain their previous optics.
The shader uses bounded arithmetic loops and at most one internal-return texture
sample, without adding passes, persistent timers, or dependencies.

[The soft-join patch](../scripts/patches/hyprglass-0.10.0-soft-join.patch)
applies fourteenth. It keeps the optics13 geometry, refraction, internal return,
and highlight peak. The inner reflection previously faded over cap depths
0.3–0.45 but was abruptly skipped at 0.4, leaving a nonzero light discontinuity.
Optics14 evaluates that light across the whole roll, allowing its angular lobe
to decay naturally before a smooth final taper over depths 0.75–1.0. Both the
light and its slope reach zero at the flat centre. This removes the inner-frame
appearance on uniform backgrounds without adding blur or altering transmission.

[The clear-roll patch](../scripts/patches/hyprglass-0.10.0-clear-roll.patch)
applies fifteenth. It removes both the added shoulder radiance and the inner
area-light lobe from integrated materials. Those lighting cues emphasized volume
but still produced a separate bright band on uniform backgrounds after optics14
softened their transition. The thin outer crest, Fresnel response, internal-return
colour, front/back refraction, and 44 px shape are unchanged. On uniform white,
the body now has nearly uniform tone; background detail supplies the visible
rolled-edge distortion. No additional blur, samples, or rendering passes are used.

[The fixed-light patch](../scripts/patches/hyprglass-0.10.0-fixed-light.patch)
applies sixteenth. For integrated materials, two fixed neutral lights now provide
the narrow crest independently of the scene-coloured reflection. Their lobes
follow the rolled surface normal, with opposing azimuths and slightly different
strengths. The elevation response decays within the outer lip and reaches zero
before the flat centre. This keeps the highlight visible over uniform saturated
backgrounds without adding a broad inner band or moving sheen.

The internal-return weight now follows dielectric Fresnel reflectance at the back
surface, with its normal-incidence floor removed. Colour develops gradually before
total internal reflection instead of being gated by a narrow critical-angle ramp.
The existing traced hit point supplies the returned colour; it does not copy a
fixed point from the opposite side. Uniform-background colour differences remain
zero. The bounded screen-space return and luminance floor are still approximations;
this is not full light transport or a reconstruction of Apple's renderer.

Transmission geometry, refraction strength, centre colour, foreground treatment,
layout and non-integrated styles are unchanged. The same optional reflection
intersection and texture sample run over a wider portion of the lip; no new
textures, passes, timers or dependencies are introduced. The expanded branch has
not been GPU-benchmarked. Native checks cover white, dark, saturated blue, detailed
wallpaper and architectural patterns, including the padded-alpha resize case.

[The corner-finish patch](../scripts/patches/hyprglass-0.10.0-corner-finish.patch)
applies seventeenth. The integrated solid retains its front height profile and
44 px outline. Its back cap uses 85% of the front rise, and the background plane
sits four logical pixels below the back instead of eight. Both interfaces still
participate in refraction. This reduces over-focused outer curls while retaining
rounded image folds and the smooth join into the flat centre. At the current
settings, sampled maximum displacement falls from about 95 to 63 logical pixels.
The front normal, fixed highlights, and uniform-background body tone are retained.

The sharp-rim sampler now accounts for the projected background footprint of an
output pixel. Where detail is compressed, four symmetric extra taps blend with
the centre sample, with bounded support. Extremely compressed regions fall back
to the existing softened sample. There is no dominant-axis switch at diagonal
corners, and resolved detail and the flat centre keep their existing sampling.
The filtering is enabled only for the integrated, non-chromatic clear-rim path.
It adds conditional texture reads but no render pass, texture allocation, timer,
or dependency; GPU frame time has not been benchmarked.

Native checks use five phases of a coarse grid, six phases of a fine grid, colour
boundaries, detailed wallpaper, and uniform white/blue/dark backgrounds. Numerical
checks cover all seven panel heights and scales 1, 1.25, 1.5 and 2. Rotated corner
rays remain continuous and symmetric. Natural image folds remain part of the
lens; this is a bounded UI optical model, not a claim of exact Apple parity.

[The continuous-rim patch](../scripts/patches/hyprglass-0.10.0-continuous-rim.patch)
applies eighteenth. Three separately captured experiments refine the Clear
baseline without changing material settings or widget geometry:

- The radial height changes from `sqrt(1-u^4)` to `sqrt(1-u^3)`. Its analytic
  normal changes with it. Height, slope and curvature still join the flat centre
  continuously, while refraction spreads more gradually across the rounded rim.
- Reflected and transmitted scene samples mix before the shared tone and local
  foreground contrast operations. This removes the return-specific channel
  clipping and white lift, keeping reflected hues more coherent.
- The fixed highlight has a narrow core and a weak soft shoulder, filtered over
  the pixel's surface-normal footprint. Gaussian widening preserves each lobe's
  integrated energy; light positions remain fixed and the broad sheen stays off.

Native comparisons cover split colours, high contrast, a diagonal stripe, coarse
and fine grids, white, blue, dark, a photo, and architectural patterns. The flat
centre is pixel-identical to optics17 in all seven checked probe scenes. The
colour-only experiment leaves all three uniform probe images pixel-identical;
subsequent curve/highlight changes affect the narrow rim on those backgrounds.
The six-phase fine-grid variation at outer corners decreased slightly (39.94 to
39.19 mean luminance standard deviation), while the flat centre was unchanged.
That is a pattern diagnostic, not a motion-quality or frame-rate benchmark.

The numerical ray check covers 2,548 positions across all seven panel heights and
four scales for each profile. Sampled primary displacement falls from 63.25 to
48.73 logical pixels; the approximate internal-return footprint can reach farther
(118.41 versus 109.24), so not every colour path becomes shorter. The back-surface
intersection residual stays below 0.01 logical pixels, and mirrored rays agree.
The reflection still approximates off-screen radiance using screen content.
No render passes, textures, timers, or dependencies are added; GPU frame time and
live fractional monitor scales have not been benchmarked. This remains a local
optical approximation, not a reconstruction of Apple's unpublished renderer.

The installed optics18 binary matches its build receipt, and applying all
eighteen patches to the pinned upstream reconstructs all 64 source files.
Restoration with the plugin unloaded and runtime choice absent recovered
optics18/Clear from the persistent selection; no actual reboot was performed.
The seven widget rectangles and process IDs, wallpaper process, and disabled
global blur/animations/shadows were preserved. Forced continuous resampling is
off. The mode/restoration tests and repository smoke checks passed.

## Wider optical rim

[The wide-rim patch](../scripts/patches/hyprglass-0.10.0-wide-rim.patch)
keeps the sharp outer light crest and broadens its faint shoulder. Both follow
the same rolled surface normal and fixed light directions, including around
corners. The shoulder fades into the clear face rather than ending at an inner
stroke. This changes the light response, not panel geometry or refracted rays.

The nearby-colour reflection also spreads farther across the roll. Its extended
angular envelope is an artistic approximation, separate from the unchanged
dielectric internal-return calculation. Environment colour now mixes with
transmission before their shared tone and local foreground contrast response;
widening that reflection therefore does not add a pale band to a uniform
background. The independent highlight remains visible on uniform backgrounds.

Two shoulder widths were compared in native captures, keeping the broader
version. All nine controlled scenes have pixel-identical flat centres compared
with optics18. The seven actual widgets were inspected on light, white, blue,
dark, photographic, and architectural backgrounds. No blur, refraction geometry,
layout, information, render passes, textures, or dependencies were changed.
This is a visual refinement of the approximation, not proof of Apple parity.

The installed optics19 binary matches its receipt; all nineteen patches
reconstruct the same 64 source files from pinned upstream. Restoration with the
plugin unloaded and runtime selection absent recovered Clear on both columns.
Widget rectangles and process IDs, the wallpaper process, and disabled global
blur/animations/shadows remained unchanged. The eleven mode/restoration tests
and repository smoke checks passed. An actual reboot and GPU timing were not
tested.

## Rolled shoulder geometry

[The rolled-shoulder patch](../scripts/patches/hyprglass-0.10.0-rolled-shoulder.patch)
applies twentieth. It changes the optical cross-section, leaving Clear's colour,
blur, foreground treatment, highlight strengths, and widget geometry unchanged.
The front uses a fifth-order radial cap; the rear keeps the gentler cubic cap.
This concentrates the stronger bend near the perimeter and settles sooner into
the flat face, while retaining the rear surface's coloured return. Refraction
and lighting use the same analytic surface normals around straight edges and
corners. Both surfaces join the centre with zero slope and curvature.

Outline radius no longer dictates unbounded optical depth. The roll width is
`r / (1 + (r / (6 * rim_width))^4)^(1/4)`, a smooth upper limit that changes the
desktop's 44 px roll by less than 0.1%. Large circles retain a clearer centre
without turning into increasingly deep lenses. The limit and surface profile
are design choices for this approximation, not measurements of Apple's shader.

Four candidates were compared using native circular controls and 312 px panels.
A tighter thickness limit and a much shallower rear cap were rejected because
they weakened the rolled edge. The selected version was checked on the flower,
grid, diagonal band, shifted colour boundaries, blue, white, and dark backgrounds.
All nine controlled panel scenes retain pixel-identical flat centres compared
with optics19. Numerical checks cover 4,032 positions per version across seven
panel heights, two circle sizes, and scales 1, 1.25, 1.5, and 2. Rays remain finite
and symmetric; sampled back-hit residual is below 0.029 logical pixels. Primary
displacement is redistributed rather than uniformly reduced: its sampled
maximum at 44 px rises from 48.73 to 51.62 px, while at 217 px it falls from
190.96 to 167.55 px. Internal returns still use a screen-space approximation.

No render passes, textures, or dependencies were added. These comparisons show
an edge-shape refinement, not exact Liquid Glass reproduction or a GPU timing
benchmark. Colour and foreground differences in the reference scene remain for
separate work. Both optics20 builds were reconstructed from pinned upstream
and their installed hashes recorded; 50 C/C++/assembly source files matched
after accounting for the reference-only radius ceiling. Clear restoration was
checked with the renderer unloaded and runtime selection absent, preserving
the user's hidden-widget state. The mode/restoration tests and repository smoke
checks passed. An actual reboot was not performed.

## Internal-return band width

[The return-band patch](../scripts/patches/hyprglass-0.10.0-return-band.patch)
applies twenty-first. The centre reference circle exposed a gap in optics20:
its right edge reduced the reflected background to a thin wire. At five rows
around the horizontal centre, the red-dominant band measured about 1 px, against
9 px in the supplied image. Broader front highlights had not addressed this.

The rear radial cap now uses power 9/4 and half the front's rise. This changes
the incidence at the rear surface and broadens the actual internal-return band;
the same shape drives transmission and reflection. Both caps still join the
flat centre with zero slope and curvature. The front profile, light strengths,
tone, blur, content, and panel dimensions are retained. The selected native
comparison gives a 7–8 px band in that region. These are image diagnostics on a
reconstructed backdrop, not measurements of Apple's private material settings.

The thicker return also exposed an intersection assumption: a grazing reflected
ray can encounter the rear cap again before reaching the front. The tracer now
finds the next boundary of the solid, choosing the appropriate cap by ray height,
with a finite box-diagonal upper bound. Surface height reaches zero outside the
outline, preventing an extrapolated hit from sampling beyond the glass. The
existing single-bounce projection of that hit into screen colour remains an
approximation; it does not reconstruct a full scene or subsequent reflections.

Native comparisons covered the reference circles and nine panel scenes. Flat
centres are pixel-identical to optics20, including on white, blue, and dark.
Numerical checks covered 5,004 positions per version across seven panel heights,
two circle sizes, and four scales. Rays remain finite and symmetric; the selected
back-hit residual is below 0.024 logical pixels, and return hits exceed the
outline by at most 0.01 px from numerical intersection tolerance. Some valid
returns travel much farther across the glass, especially at grazing corners;
they are bounded by the solid rather than by an arbitrary nearby-colour radius.

No render pass, texture, or dependency was added. GPU timing, a physical reboot,
and exact Apple parity are not established by these checks.

## Surface transport and variable apparent rim

[The surface-transport patch](../scripts/patches/hyprglass-0.10.0-surface-transport.patch)
applies twenty-second. Optics21 widened the internal return but made it read as
a nearly uniform coloured strip. This revision changes both its optical weight
and the continuous rear surface. It does not add a varying-width border mask.

The front interface now uses exact dielectric Fresnel reflectance, with the
normal-incidence floor removed to retain the clear face. Its local environment
sample is kept separate from the far-side internal return; the latter no longer
feeds back into front reflection. The next surface hit also supplies an escape
reflectance, reducing the weight of a return that would remain inside the solid.
Clear's existing `fresnel_strength = 0.42` gives the full front response; lower
values scale it down. This follows the interface energy split described in
[Physically Based Rendering](https://www.pbr-book.org/4ed/Reflection_Models/Specular_Reflection_and_Transmission),
while retaining UI-specific normalization and screen-space radiance sampling.

The rear cap retains power 9/4, multiplied by `1 - 0.5 * (y / halfHeight) * u^3`,
where `u` runs from the flat-face join to the silhouette. This smooth taper changes
the incidence and focusing around the shape. Its analytic normal includes both
the radial and vertical derivatives; the flat centre and its first two derivatives
are unchanged. It is a chosen material shape, not a recovered Apple parameter.
The silhouette, front geometry, lighting, colour settings, blur, and UI are retained.

Numerical checks cover 6,912 positions over four panel heights, two circles,
all quadrants, and scales 1, 1.25, 1.5, and 2. The analytic rear normals agree with
independent height differences within 0.000040 in gradient. Back-hit residual is
below 0.024 logical pixels. Sixteen return-intersection steps keep the steepest
sampled surface-height residual below 0.268 px and returned points inside the
outline. Left/right symmetry and scale equivalence are preserved. On the 434 px
circle the return contribution above 35% reaches roughly 4.5 px inward at the
top, 7.5 px at the sides, and 10.8 px at the bottom. These are model diagnostics,
not measurements of Apple's rim.

A small oblique viewing angle, an extended exit-direction environment probe,
and alternative rear profiles were evaluated. The selected taper and energy
split retain the bounded surface-hit colour projection. This remains a single
internal-bounce approximation: further trapped energy falls back to the existing
transmitted-background sample, and unseen environment radiance is unavailable.
It is not a complete light-transport solution. In particular, the much broader
lensing visible in the supplied left reference circle is not reproduced fully.
No texture, render pass, dependency, or interaction was added; GPU timing has
not been benchmarked.

Native comparisons cover the three circles and nine panel backgrounds, including
shifted colour boundaries, grid, diagonal bands, blue, dark, and white. All nine
flat panel centres are pixel-identical to optics21. Both installed builds match
48 source files reconstructed from the pinned upstream and all 22 patches.
The reference launcher and unloaded-renderer Clear restoration were checked;
saved choice, visibility, and the physical display setup were preserved. The
11 mode tests and repository smoke suite passed. An actual reboot was not run.

## Build explicitly

Use the matching Hyprland headers and the build dependencies documented by
upstream. Standard dotfiles profiles do not download, build, or load this plugin.
Run from the dotfiles repository in Bash; the temporary checkout is removed on
exit, and the stock binary is retained:

```bash
(
  set -eu
  glass_repo="$PWD"
  glass_variant="${GLASS_VARIANT:-optics22}"
  case "$glass_variant" in
    optics22|optics22-reference) ;;
    *) echo "Unknown glass build variant: $glass_variant" >&2; exit 1 ;;
  esac
  glass_build=$(mktemp -d)
  trap 'rm -rf -- "$glass_build"' EXIT
  git clone --quiet --depth 1 --branch v0.10.0 \
    https://github.com/hyprnux/hyprglass.git "$glass_build/source"
  cd "$glass_build/source"
  test "$(git rev-parse HEAD)" = 84c1a5ab217101a317d4edaab7fba2efcc1bf346
  test "$(pkg-config --modversion hyprland)" = 0.56.2
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-clarity.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-clarity.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-curved-surface.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-curved-surface.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-adaptive-motion.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-adaptive-motion.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-adaptive-rim.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-adaptive-rim.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-shaped-light.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-shaped-light.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-integrated-lens.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-integrated-lens.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-balance.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-balance.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-contour-light.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-contour-light.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-volume.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-volume.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-return.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-edge-return.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-coherent-rim.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-coherent-rim.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-rounded-meniscus.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-rounded-meniscus.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-rolled-volume.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-rolled-volume.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-soft-join.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-soft-join.patch"
  git apply --check "$glass_repo/scripts/patches/hyprglass-0.10.0-clear-roll.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-clear-roll.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-fixed-light.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-corner-finish.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-continuous-rim.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-wide-rim.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-rolled-shoulder.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-return-band.patch"
  git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-surface-transport.patch"
  if [ "$glass_variant" = optics22-reference ]; then
    git apply "$glass_repo/scripts/patches/hyprglass-0.10.0-reference-radius.patch"
  fi
  make -j2 HYPRGLASS_VERSION="0.10.0-$glass_variant"
  strip --strip-debug hyprglass.so
  glass_dest="$HOME/.local/lib/quickshell-glass"
  install -d "$glass_dest"
  install -m 755 hyprglass.so "$glass_dest/hyprglass-0.10.0-$glass_variant-0.56.2.so.new"
  mv "$glass_dest/hyprglass-0.10.0-$glass_variant-0.56.2.so.new" \
    "$glass_dest/hyprglass-0.10.0-$glass_variant-0.56.2.so"
  install -m 644 LICENSE "$glass_dest/LICENSE"
)
```

The binary is replaced atomically; an already loaded copy remains unchanged
until it is unloaded and loaded again. Do not overwrite a mapped plugin in place.
After a Hyprland upgrade, recheck upstream compatibility before rebuilding.

## Reference comparison scene

`./scripts/quickshell-glass-reference.py` opens a separate native Quickshell scene
on the focused monitor. Three circular controls use the existing Clear preset,
including its foreground contrast, with circle geometry instead of the desktop
widgets' 44 px corners. At native size the stage is 1531 × 611, with 304 / 434 /
304 px circles placed to match the supplied reference; smaller displays scale
the entire scene down. The actual glass is rendered by HyprGlass, not baked into
an image or drawn by a browser filter.

The scene needs a separate `optics22-reference` build. It applies the same
twenty-two optical patches, followed by
[reference-radius](../scripts/patches/hyprglass-0.10.0-reference-radius.patch),
which only raises the preset radius ceiling from 48 to 1024 logical pixels.
The renderer still clamps each radius to half its surface size. No shader,
refraction, blur, or lighting formula changes. To build it, set
`export GLASS_VARIANT=optics22-reference`, run the build recipe above, then
`unset GLASS_VARIANT`. Keep the ordinary optics22 binary too: the launcher
temporarily switches to the reference build and restores the ordinary build on
Close, Escape, `--stop`, terminal interruption, or scene-process exit.

The launcher requires an already active optics22 desktop renderer. It does not
save a different material, replace the wallpaper, modify panel geometry, or
install an autostart/service. An exclusive runtime lock prevents two launchers
from swapping the same plugin.

For internal capture, `--screen OUTPUT` selects an existing display. An unfocused
display does not grab keyboard input. The launcher does not create or reconfigure
outputs. Hidden desktop widgets can leave shaders pending until glass is drawn;
this is accepted during restoration, while an actual shader failure is rejected.

Scene controls:

- **Live glass / Original** switches between the native scene and the supplied
  Apple screenshot (`R` also toggles).
- **Flower / Blue / White / Dark / Grid** changes the test backdrop.
- **Icons / Glass** hides the foreground or the entire optical surface.
- **← / →** moves the flower or grid behind stationary glass; **Reset** recentres it.
- **Space** toggles icons; **Escape / Close** exits.

The flower is an AI reconstruction of the unobstructed background from the
user-supplied screenshot. It preserves the broad colour arrangement, but the
petals and hidden detail are approximate. Compare geometry, colour flow, and
highlight behaviour; this is not a pixel-accurate reconstruction of Apple's
original photograph. Asset provenance is recorded alongside the scene.

The native surfaces stay mapped while toggling views; their rendered alpha mask
changes instead. An opaque plate covers native shadows in Original and
background-only views. This avoids stale render targets when comparing repeatedly.
Native checks covered all five backdrops, background shifts, six visibility
round trips, duplicate-launch rejection, normal exit, and SIGTERM restoration.
The Original view is pixel-identical to the supplied screenshot at native size.
Restoration preserved the seven widget rectangles/processes, wallpaper process,
saved Clear mode, and global rendering settings. The normal and reference
builds share the same optical shader.


## Use

Source `modules/quickshell/.config/quickshell/glass.lua` from the local Hyprland
Lua configuration as described in the repository README. This source statement
does not load the plugin. The helper prefers the optics binary when installed.

If an older HyprGlass build is already loaded, first restore the widgets and
unload that known binary from the active desktop session (use its actual path):

```bash
./scripts/quickshell-glass.py off
hyprctl plugin unload "$HOME/.local/lib/quickshell-glass/hyprglass-0.10.0-0.56.2.so"
```

Then select a material:

```bash
./scripts/quickshell-glass.py choose  # Clear / Blurred picker
./scripts/quickshell-glass.py clear
./scripts/quickshell-glass.py blurred
./scripts/quickshell-glass.py soft
./scripts/quickshell-glass.py sculpted
./scripts/quickshell-glass.py liquid  # previous square optical material
./scripts/quickshell-glass.py legacy-clear  # previous square fallback
./scripts/quickshell-glass.py off     # original dark material
```

Selecting a material reloads Hyprland's configuration because custom presets
become active in the plugin's configuration-reloaded callback. The helper
checks the resulting preset, configuration errors, widget acknowledgements,
and shader readiness. `liquid` refuses the stock build rather than silently
falling back to a blurred approximation. Adaptive curved styles require optics22.
Each successful selection, including `off`, is saved in the user's persistent
state directory. The runtime selection remains separate so a failed renderer
can fall back to ordinary widgets without erasing the last successful choice.

To use the selected material by default after login, add an explicit restoration
command to the existing `hyprland.start` callback after the widget launch lines:

```lua
hl.exec_cmd("/absolute/path/to/dotfiles/scripts/quickshell-glass.py restore")
```

The helper waits for both widgets' IPC endpoints, then loads the installed
plugin and reapplies the saved material with the same renderer checks. It does
not start duplicate widgets, install software, or add a background service.
`restore` without a saved choice does nothing; an invalid choice or startup
timeout reports an error without loading the plugin. The saved choice survives
failed restoration. A compatibility failure still requires a matching plugin
build after a Hyprland update. Standard profiles do not add the startup command.

## Validation limits

The local build, shader compilation, the original 312 × 1080 layer geometries, QML
reload, material rollback, and repository smoke suite were checked on the
current display. A temporary moving stripe pattern showed sharp, displaced
edges and softened central detail. Removing it refreshed both columns without
reapplying a material. The test did not change the wallpaper selection.

After restoring separate panels, all seven live panel geometries, spacing,
visibility toggling, and the retained material were checked again.

For optics2, both patches applied successfully, the curved patch reproduced
the built sources, and the live shaders compiled. All three curved treatments
kept the seven panel rectangles unchanged. A temporary moving stripe layer
exercised the curved rim; solid-background pixel checks found the exterior
shadow and confirmed its removal when the widgets hid. Removing the test layer
restored the wallpaper, and `off` → `liquid` → `rounded` restored the selected
material without configuration errors. The repository smoke suite passed.

For optics3, the three patches reproduced the built sources and the shaders
compiled on the live desktop. On a fixed stripe pattern, adaptive scattering
reduced the blank panel's interior contrast from 19.87 to 9.67 (8-bit channel
standard deviation). The sampled outer rim and the uniform-background interior
were unchanged. Captured native frames confirmed intermediate opacity on both
entry and exit, including widget content and shadows. Reversing a transition
kept its current progress, and the animation timer stopped after settling.
Hidden widgets stayed hidden through a QML reload and an `off` → `liquid` →
`rounded` round trip. All seven panel rectangles remained unchanged, with global
animations, blur, and shadows still disabled. The repository smoke suite passed.

The later clear-transmission tuning was compared on the same blank panel and
fixed backgrounds. On the solid background, the mean interior channel value
rose from 69.67 to 114.33. The lit edge exceeded the interior by 28.33 instead of
11.00, excluding the boundary pixel that also mixes the unfiltered background
through antialiasing. Stripe contrast rose from 9.61 to 43.09, showing more
background detail. Refraction parameters, live geometry, and motion were
preserved, and the smoke suite passed. These are 8-bit image measurements, not
physical transmission percentages or a match score against Apple's material.

The foreground follow-up was checked on solid light, solid dark, and patterned
backgrounds. Representative text kept identical width and height, all seven
panel rectangles were unchanged, and sampled areas away from the foreground
were pixel-identical. The separator contrast improved on both solid backgrounds.
QML reload and smoke checks passed; the accepted glass configuration was
verified byte-for-byte unchanged.

For optics4, all four patches reproduced the built sources and the live shaders
compiled successfully. Six fixed backgrounds (light, dark, blue, green, pink,
and stripes) were captured before, after, and with `adaptive_rim` disabled.
Disabling the new response reproduced optics3 pixel-for-pixel. When enabled,
all pixels at least 4 px inside the contour and all exterior pixels remained
identical; the light background showed the strongest edge adjustment. The broad
sheen stayed disabled. All seven native panel rectangles and processes were
preserved, visibility timers settled correctly, and global animations, blur,
and shadows remained disabled. The repository smoke suite passed.

Startup restoration was checked with the plugin unloaded, both widgets reset
to ordinary material, and the runtime selection removed. The exact desktop
startup command restored `rounded` from the private persistent selection,
loaded the matching renderer, and reached ready shaders without restarting
widgets or changing their rectangles or global rendering flags. No actual
reboot was performed during this check. Tests also cover delayed widget IPC,
startup timeout, failed-renderer rollback, remembered `off`, and absent or
invalid saved selections. The smoke suite passed; ShellCheck was unavailable.

For optics5, all five patches reproduced the compiled sources and the live
shaders loaded successfully. Six backgrounds were compared before and after,
and with each new treatment disabled. With both controls disabled and the old
tone settings, differences from optics4 were limited to one 8-bit channel level
at four pixels per capture. On the blue background, a straight rim sample
changed from RGB (60, 73, 150) to (19, 34, 127), retaining more of the underlying
blue instead of adding a pale outline. The light-background empty-area mean
rose from 161.48 to 201.48; enabling local backing left the sampled empty area
pixel-identical and darkened the region below the header. Removing foreground
text cleared its backing on the next captured update, with no stale silhouette.
The final build restored from persistent state with the runtime selection absent.
All seven native panel rectangles and processes, refraction settings, and global
rendering flags were preserved. The added lighting has no time or pointer input.

For optics6, the integrated cap was checked on a native grid and six fixed
backgrounds. After reloading both builds with identical settings, disabling the
new lens matched optics5 within two 8-bit channel levels; the maximum mean
channel difference was 0.00023. The flat centre stayed within one channel level.
The original warm-session capture had different edge shading that did not
reproduce after reloading optics5, so it was not used as the equivalence baseline.
Numerical samples across the corners and straight edges of 162, 300, and 527 px
panels showed no reversed mapping at the selected settings; the old model did.

For optics7, checks were expanded from centre-screen samples to all seven actual
widgets at their native screen positions, on six backgrounds. Disabling local
backing isolated the unintended dark frame; disabling the outer shadow did not.
A resize regression then deliberately left an opaque border outside a smaller
panel: optics6 reproduced the dark frame, while optics7 cleared it and retained
the same centre pixels. Six samples per actual panel verify that the border
remains light over a uniform light background. Refraction, scattering, and
foreground-backing strengths remain unchanged.

The earlier centre-screen samples missed allocation-dependent alpha outside the
surface and were insufficient to validate this case. Static and repeated-colour
checks are supplemental; the actual widgets and resize reproduction provide the
relevant regression evidence.

For optics8, the actual seven widgets were captured on light, dark, blue, green,
pink, and striped backgrounds. The narrow highlights retain the surrounding hue
and extend onto the long edges. Empty side-edge samples remain above 202/255 in
mean RGB on the light background, with no return of the stale-alpha frame. The
resize regression retains exactly the same flat interior pixels as optics7.
All eight patches reconstruct the built source from the pinned upstream, and
the installed binary matches the build. Startup restoration with the plugin
unloaded and runtime selection removed restores optics8/`rounded`, preserving
panel rectangles, widget processes, and global rendering flags. This tests the
startup command, not an actual reboot. Repository smoke checks pass.

For optics9, all seven live panels were compared on light, dark, blue, green,
pink, grid, and diagonal-colour backgrounds. Numerical mapping samples across
the seven panel heights at scales 1, 1.25, 1.5, and 2 found no reversed mapping
at the selected settings (minimum sampled Jacobian determinant 0.08658).
Higher scales were checked numerically, not on additional physical displays.
The padded-alpha resize case retained a light edge without the old dark frame.
All nine patches reconstruct the 64 tracked source files in the built tree.
The installed optics9 build restored `rounded` from persistent selection with
the plugin unloaded and runtime selection absent; this was not an actual reboot.
All seven panel rectangles and process IDs, QML files, and disabled global
animation/blur/shadow flags were preserved. Repository smoke checks passed.

For optics10, all seven panels were captured on nine backgrounds, including a
lavender-to-blue field matching the reference's colour relationship and a
green-to-magenta counterexample. Every panel's sampled side rim gains lavender
over blue and green over magenta; the adjacent transmitted band retains its
original colour. On five uniform backgrounds, sampled side-rim mean differences
from optics9 are at most one 8-bit channel level. This tests colour separation
and scene response, not pixel equality with an unknown original backdrop.
The padded-alpha resize case remains clean, all ten patches reconstruct the
64 tracked source files, and the installed binary matches the build receipt.
Restoration from unloaded state with no runtime selection restores optics10 and
`rounded`. QML, material parameters, panel geometry/process IDs, and disabled
global rendering flags are unchanged. Repository smoke checks passed.

For optics11, all seven actual panels were compared with optics10 on nine
backgrounds. The probe repaints steadily to exclude stale cached frames during
rapid scene changes. The coloured lip remains in both lavender/blue and
green/magenta cases, with a smaller contribution from the distant colour.
Sampled uniform rims and adjacent transmission differ by at most one 8-bit
channel level. Fifteen discrete positions of a moving gradient produce a
monotonic rim-colour response; these samples do not measure frame pacing.
The padded-alpha resize case retains exactly the same flat centre pixels.
All eleven patches reconstruct the 64 source files, and the installed binary
matches the build receipt. The startup command restores optics11/`rounded`
from an unloaded renderer with no runtime selection; no actual reboot was
performed. Intermediate visibility states were captured, and the update timer
disarmed after settling. UI/material files, panel rectangles/processes, the
wallpaper process, and disabled global animation/blur/shadow settings are
preserved. Repository smoke checks passed.

For optics12, all seven actual panels were captured on eleven backgrounds,
including a fixed wallpaper frame and an architectural test pattern. Two optical
depths and 20/28 px corner radii were compared before selecting 1.85/28 px.
The seven sampled light-background side rims stay within two 8-bit mean channel
levels of optics11; the padded-alpha resize case retains a pixel-identical flat
centre. All information fields remain present with the larger corners.
Numerical samples across seven panel heights at scales 1, 1.25, 1.5, and 2 find
a maximum displacement of 19.36 logical pixels and a minimum mapping Jacobian
of -1.18971. The reversals are intentional local lensing; at scale 1 the sampled
reversed region lies about 1.3–14.3 px into the corner band. Flat-centre samples
retain zero displacement. Higher scales were checked numerically only.

Ten subpixel positions of a moving grid, including a return to its initial
position, reproduce the sampled upper rim exactly at the repeated position.
These are discrete visual/continuity checks, not a frame-pacing benchmark.
All twelve patches reconstruct the 64 source files, and the installed binary
matches its receipt. Startup-command restoration from an unloaded plugin and
absent runtime choice restores optics12/`rounded`; no actual reboot was performed.
Visibility transitions reach intermediate states and disarm their timer after
settling. Panel rectangles/processes, the wallpaper process, foreground content,
and disabled global animation/blur/shadow settings are preserved. QML reloaded
successfully, and repository smoke checks passed.

Screenshots and these bounded tests establish those rendering behaviors. They
do not establish Apple's visual fidelity, long-duration smoothness, or support
for every display scale/rotation. Final appearance still needs user judgment.

For optics13, all seven panels were inspected on eleven fixed backgrounds,
including a grid, a window pattern, gradients, saturated colours, and the same
wallpaper snapshot used for the before capture. The wider roll and the second
surface produce curled background pockets; this is a visual improvement target,
not a claim of parity with Apple. Widths, heights, gaps, panel processes, and the
wallpaper process are preserved. The blank-panel resize centre is pixel-identical
to optics12, with no stale foreground-alpha rectangle.

A numerical sweep of all seven heights at scales 1, 1.25, 1.5, and 2 found finite
transmission coordinates and back-intersection residuals below 0.01 logical
pixel. Maximum sampled displacement is about 95.6 logical pixels at grazing
angles; the flat centre has zero displacement. Ten subpixel grid positions
returned an identical upper-rim crop when revisiting the initial position.
This establishes repeatability, not frame pacing or an FPS target.

All thirteen patches reconstruct the 64 source files, and the installed binary
matches the build receipt. Restoring with the plugin unloaded and runtime choice
absent reloads optics13/`rounded`, preserving the saved selection; an actual
reboot was not performed. Smoke tests pass, the shaders are ready, temporary
probes are closed, and force-live sampling and global animation/blur/shadow flags
are off. The previous optics12 binary remains available for rollback.

For optics14, all seven panels were checked on pure white, light grey, dark,
blue, the fixed wallpaper, and the window-pattern background. A blank glass
panel on pure white isolates the inner transition from text backing. Its largest
adjacent-pixel mean-channel change at depths 9–24 px fell from 9 to 4 on top,
12 to 6 on the bottom, 5 to 3 on the left, and 6 to 3 on the right. The flat-centre
crop is pixel-identical, and the highlight peak and refraction code are preserved.
These measurements concern the inner light transition, not the outer silhouette.

All fourteen patches reconstruct the 64 source files and the installed binary
matches its receipt. Native panel geometry, processes, QML, material parameters,
and wallpaper remain unchanged. The shaders are ready, smoke tests pass, and
restoring after unload with no runtime selection reloads optics14/`rounded`
without changing the saved choice. No actual reboot was performed. Temporary
backgrounds are closed and force-live sampling is off.

For optics15, all seven panels were captured on pure white, light grey, dark,
blue, the fixed wallpaper, and a window-pattern background. On the blank white
probe, the maximum mean-channel difference from the centre at depths 6–30 px
fell from 28/29/17/20 levels (top/bottom/left/right) to one level on every side.
The flat-centre crop is pixel-identical. The thin silhouette remains visible,
while the broad inner band is absent. Refraction, internal-return colour, and
Fresnel code are byte-identical to optics14; the wallpaper retains its curved
background pockets.

All fifteen patches reconstruct the 64 source files, and the installed binary
matches its receipt. Smoke tests pass. Restoring after unload with no runtime
selection reloads optics15/`rounded`, preserving the saved choice; no actual
reboot was performed. Panel geometry, processes, QML, material parameters, and
wallpaper are unchanged. Shaders are ready, temporary probes are closed, and
force-live sampling is off. The optics14 binary is retained for rollback.
