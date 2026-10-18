# Liquid Glass optical prototype

An independent Quickshell prototype containing a glass panel and a draggable
lens, two Flower circles, three animated reference studies, and a size study. All material, scene,
interaction, and verification code in this directory
is newly written. It has no imports from the existing widget or glass code.

The optical lab samples its own animated scene. The separate **desktop backend**
renders the same material directly from Hyprland's current GPU framebuffer,
under a newly written Quickshell clock. Neither path imports the old widget or
glass implementation. The desktop commands below are explicit experimental
operations; they do not install a service or modify persistent compositor
configuration. Device-matched native Apple captures are still required before
claiming a match to a particular Apple material. The WWDC demonstration is a
qualitative visual reference.

## Run

From the repository root, in the graphical session:

```bash
python3 scripts/liquid-glass-lab/lab.py run
python3 scripts/liquid-glass-lab/lab.py run --paused
python3 scripts/liquid-glass-lab/lab.py run --scene boundary
python3 scripts/liquid-glass-lab/lab.py run --scene size
python3 scripts/liquid-glass-lab/lab.py stop
```

Requirements: Python 3, Quickshell, Qt 6 Quick, and Qt Shader Tools (`qsb`).
The runner finds `qsb` on `PATH` or at Arch's `/usr/lib/qt6/bin/qsb`.
It installs nothing. The demo is a separate fixed-size 1120 × 760 window.

The lab opens on the supplied flower image. Drag the lens, switch between
Color/Grid/Type/Contrast/Flower/Desert/Boundary/Lighting/Panel/Size, and use the controls to
isolate refraction, softness, and light. Compare removes the material treatment.
Its transition modulates the optics over 650 ms while leaving item opacity at
one. Inspect displays distance and direction fields. Keys 1–9 and 0 switch studies,
Space pauses motion, G toggles Compare, and R resets the lens and optical controls.

### Clear material

The lab and desktop backend use one material: Clear. The optical controls
isolate refraction, softness, and illumination without selecting another mode.

Here, Clear combines curved refraction, narrow transmission softness, and
directional highlights. A small spread around each refracted ray softens local
detail; its footprint depends on optical depth and ray angle. It does not blend
in the broad analysis blur, an adaptive neutral fill, or averaged surrounding
colors at the rim. Texture filtering also follows the refracted pixel footprint
to avoid aliasing. The broadly softened scene remains available for lighting
analysis and explicit reference profiles.
The desktop backend uses the same defaults. Flower and Desert
retain their explicitly tuned optical settings. These are independent
approximations of the visual behavior, not fitted Apple values. Compare removes
the optical treatment, preserving exact source sampling at zero strength.
Foreground glyphs remain separate.

Large default surfaces also have a shallow, continuous body lens. A quartic
height field adds gentle curvature across the broad interior and joins the
rounded perimeter through the existing cap profile. Its analytic surface normal
and height drive the same refraction calculation; it adds no color fill or blur.
The maximum additional height is 5.5% of the short side, eased down for small
controls. Uniform backgrounds remain uniform under refraction, and the exact
optical center stays aligned. This is an independent single-interface optical
approximation, not a two-surface ray trace or a physical fluid simulation.
Flower, Desert, and the explicit reference studies retain their original
profiles with this additional curvature disabled.

Flower uses unlabelled circles of diameter 220 and 152. It omits the panel and
tint adaptation to expose refraction and source color. Drag the larger circle;
the smaller circle stays across the petal silhouette. Softness controls source
smoothing. Motion translates the supplied still by ±44 horizontal and ±8
vertical pixels over a six-second cycle. The circles and their optical settings
stay fixed, so changing folds come from the source movement. This repeatable
stress case does not reconstruct the wind or petal deformation in Apple's video.
Dark is an optional dimming stress case. The image uses an aspect-preserving
center crop with overscan to cover its movement.

Desert (key **6**) uses the unobstructed dune frame from the earlier comparison,
with a single draggable circular lens. It retains that study's shallower optical
profile: diameter 466, bevel 26, height 36, and backing distance 200, all scaled
from the 1920 × 1080 reference into the preview. At phase zero the source uses
the same 1.010 alignment correction. Motion gently zooms the still over a
six-second cycle; Space pauses it and Reset returns to the reference placement.
The existing Refraction, Softness, Light, Dark, Compare, and Inspect controls work
in this scene too.

The additional studies isolate the three newly selected reference behaviors:

- **Boundary (7):** a capsule moves across a stationary light/dark split. Watch
  the enclosed dark pocket and the returning light band beneath it. Its blue-grey
  source gradients approximate unobstructed margins of the 2:34 reference frame;
  the source is synthetic, and this fit does not change the glass material.
- **Lighting (8):** the capsule stays still while the light field and paired
  highlights rotate. Dark contour segments separate the concentrated glints.
- **Panel (9):** a large rounded surface moves over monochrome dunes, with a
  sharp white foreground bar. This uses the Desert asset, which is a **different
  background** from the panel reference; it is a qualitative geometry study.

These three studies animate automatically; Space pauses them. Their six-second
periodic paths are diagnostic cycles, not reconstructions of Apple's motion.
Compare and the optical controls also work here. They do not support dragging.

**Size (0)** expands a 240 × 112 control into a 740 × 432 surface and back over
six seconds. Its background stays still. Bevel width, optical depth, body
curvature, and shadow grow together; transmitted content retains its contrast
and the foreground remains sharp. This exercises the automatic Clear defaults
rather than a separately tuned large-panel preset. The broad-diffusion control
is hidden here; narrow transmission softness follows the default optical depth.
The size law and timing are
independent choices, not recovered Apple behavior.

To export a cycle through the actual Qt renderer:

```bash
python3 scripts/liquid-glass-lab/lab.py record
python3 scripts/liquid-glass-lab/lab.py record --scene lighting
```

This additionally requires the same compiler/Qt development tools as `check`,
plus `ffmpeg` with libx264. Choose `flower` (default), `desert`, `boundary`,
`lighting`, `panel`, or `size`. It writes `<scene>-motion.mp4` (six seconds, 30 fps),
four phase snapshots, and provenance in `<scene>-motion.json` to the lab cache.
Rendering advances in fixed time steps; the clip is not a real-time performance
measurement. Existing artifacts at those fixed names are overwritten.

## Visual reference

Primary reference: Apple's [Meet Liquid Glass, WWDC25 session 219](https://developer.apple.com/videos/play/wwdc2025/219/).
The user selected **2:18–3:38** for design and **2:33–3:09** for appearance.
The timestamped transcript and sampled video frames were inspected, including
the flower controls through approximately 2:49–2:55, with closer inspection of
2:49.0 and 2:49.6. This is qualitative inspection, not frame-matched native-device
measurement.

- **2:18–2:55:** lensing supplies shape and separation while retaining the
  background content. Judge the bent petal boundary and preserved center detail.
- **2:55–3:09:** appearance and disappearance change the optical treatment.
  Compare therefore changes refraction, scattering, lighting, adaptation, and
  shadow together. It never animates glass opacity.
- **3:10–3:38:** movement and appearance belong to one material. Press deformation
  and optical response must stay coordinated during dragging.

### Additional motion references

The user also selected **2:33–2:35**, **2:37–2:40**, and **2:41–2:43**.
These intervals were inspected as quarter-second frame sequences, with full-size
stills at 2:34.0, 2:34.75, 2:38.5, and 2:42.0. Contact sheets and a provenance
manifest are retained as `reference-153-155.png`, `reference-157-160.png`,
`reference-161-163.png`, and `motion-references.json` in the lab cache.

| Interval | Observed behavior | What to evaluate in this prototype |
| --- | --- | --- |
| 2:33–2:35 | A capsule descends across a stationary horizontal light/dark boundary. The dark region first appears as an enclosed rounded pocket, then expands toward the outline as the capsule settles. | Track the background contour through the curved ends and straight lower edge while moving the glass itself. Evaluate the whole crossing, including the quiet settled state. |
| 2:37–2:40 | A dark capsule stays in place while bright and dark edge segments travel around its perimeter with the changing light field. Much of the interior remains subtle. | Separate moving illumination from background translation. Check highlight position, width, falloff, and opposing dark edges on a low-detail source. |
| 2:41–2:43 | A large rounded surface descends over monochrome dunes. The dune ridge bends strongly through the lower corners and bottom region, while the white foreground bar remains crisp. | Evaluate a widget-sized rounded rectangle: straight edges, corners, the extent of the warped region, and foreground stability throughout its motion. |

These observations do not establish Apple's rendering equations. In particular,
the first sequence's changing bright band can result from a fixed sampling field
crossing the boundary; it is not evidence by itself for animated opacity or lens
depth. The second sequence does not uniquely separate reflected environment
light from direct lighting. The third lacks an aligned unobstructed source for
a numerical displacement fit.

For widget work, prioritize the large rounded surface as the geometry reference,
the boundary crossing as the diagnostic for refraction, and the dark capsule as
the diagnostic for lighting. Keep Flower and Desert as complementary checks for
color wrapping and textured detail. These comparisons led to three changes:

- The Boundary profile uses a wider curved section and a longer optical path
  than the original generic panel. An approximate dark-pocket contour at 2:34
  constrains its inward sampling. Native-reference lengths are bevel 120,
  height 150, and backing distance 180, scaled into the preview. Several profiles
  can produce a similar contour; these values are not uniquely recovered optics.
- Lighting has a concentrated core and a softer inward reflection, with a darker
  unlit contour. The opposing reflection weakens on bright backgrounds, so the
  outline does not remain uniformly pale. A finite light source is positioned in
  backdrop coordinates; highlights can travel along straight edges as well as
  around corners. Lighting (8) rotates this source over time.
- Panel uses native-reference lengths 180/150/440 for bevel/height/backing
  distance, with radius 220. Its curved region also samples a softened source to
  temper stretched dune texture. The generic widget panel uses these ratios as
  an initial profile. A matching unobstructed background was not found at the
  reference entrance, so neither panel is numerically calibrated to that scene.

The comparison board `additional-reference-comparison.png` in the cache places
Apple stills beside the initial and revised studies. Its final row explicitly
labels the different source image. `comparison-studies.mp4` shows the three
revised six-second cycles through the actual Qt renderer. These comparisons
remain qualitative: trajectory, light-field shape, shadow, and material response
still differ, and they do not establish desktop integration or Apple fidelity.

### Highlight falloff

A closer inspection of the 2:38.5 capsule separated two features: a sharp edge
highlight and a weaker reflection extending inward. A smooth polynomial fitted
to the visible background outside the capsule provided an approximate baseline
(outside-fit RGB RMSE about 0.77 on a 0–255 scale). At two diagonal highlights,
the reference retains roughly 11–18 luminance levels above that baseline at
12–16 native pixels inward. The previous shader had almost no corresponding
falloff by six native pixels. These residuals include lensing and estimation
error; they do not isolate a physical reflection layer or recover Apple shaders.

The revised model pairs a narrow Gaussian core with a directional shoulder that
decays inward and reaches zero at the flat interior. Its width is limited by both
the bevel and the corner radius. Opposing reflections diminish over bright
content, and energy is redistributed from the core to avoid merely whitening
the edge. The finite source also removes the former uniform illumination along
a straight edge. The underlying Flower/Desert refraction profiles are unchanged.

`surface-light-profiles.json` retains the sampled reference and before/after
profiles in the lab cache. `surface-light-comparison.png` and
`surface-light-comparison.mp4` show this lighting revision. The images and motion
are actual Qt renders. Source framing, light-field shape, light color, and the
reference's precise geometry still limit the comparison. Inspection of the
panel sequence's entrance and exit found no unobstructed matching background;
the exit cuts directly to the flower toolbar.

The center and left Flower circles expose more than a narrow refracted border.
Petal colors wrap around a blue interior pocket; the smaller circle has a
stronger fold relative to its diameter. In successive frames, a modest flower
movement changes the large circle from a surrounding orange edge to a mostly
blue surface with an orange island. The outer circles stay in place. A constant
optical field acting on moving content can produce this qualitative change;
the prototype does not animate a painted rim or pulse refraction to imitate it.
The circle over quiet sky remains subtle.

A separate comparison uses the sand scene at **2:57**, with
the unobstructed background from **2:59.8**. The video zooms between those frames:
a 1.010 source-coordinate scale around (960, 540) aligns the background. Ignoring
that motion would attribute camera movement to the glass.

The approximate reference circle is centered at (957, 542), radius 233, in the
1920 × 1080 frame. A local luminance fit outside the play glyph selected a cubic
superellipse with bevel width 26, surface height 36, and virtual backing distance
200. Scaling those three lengths directly into Flower was insufficient: the
sampled rays mostly stayed on their own side of the circle's center. Flower now
uses bevel width 36, surface height 48, and backing distance 240 for **both**
circle sizes. The longer path and taller, wider curved section allow the rim
to sample across the center while preserving the upright interior. Keeping the
optical lengths fixed gives the smaller circle a stronger relative fold. These
are independently chosen study parameters, not measured Apple constants or a
general size-adaptation law. Center magnification is zero.

The original 20-pixel linear-slope band and fixed depth 310 have been
removed: they compressed the image into an excessive hard ring and joined the
interior with a visible kink.

The sand fit is to one demonstration, not recovery of Apple's constants. Geometry,
video compression, residual camera motion, lighting, and source smoothing limit
its accuracy. The fit excluded the foreground glyph and used a circular radial
model; it is not an overall similarity score. The flower background remains a
separate visual check, not a matching source frame. Lighting, shadow, arbitrary
size adaptation, interaction motion, and the reference's deforming source video
still need further comparison.

`assets/flower.png` is the unchanged 1985 × 792 image supplied by the user on
2026-10-17, not a frame extracted from Apple's video. Different subject framing
prevents direct pixel-error comparisons against that video. Its SHA-256 is
`ba21aafca6eeb8241f1ef4852b0926de962e653cee4490042c7ba56a01b91697`.
`assets/desert.png` is the unchanged unobstructed 1920 × 1080 frame at **2:59.8**
from the Apple video linked above, added as the requested local Desert study
background. It is Apple reference imagery, not an original asset of this project.
Its SHA-256 is
`dd8391e89fc1c8de87517630f974e4dce7ffe57c2c94bc480ba40ebdf7b8f8c8`.
The remaining sampled video frames stay in the bounded local research cache.

## Rendering

- `BackdropSource.qml` captures only the owned background. One half-resolution
  separable Gaussian blur is shared by the pieces of glass. Contiguous samples
  prevent the repeated-line artifacts of a sparse blur kernel. Both source
  textures have mipmaps: compressed refracted coordinates select a filtered source
  footprint instead of aliasing fine detail into a jagged rim. This adds texture
  generation cost; full desktop performance has not been measured.
- `Glass.qml` supplies explicit geometry and sample coordinates. Its shader
  computes rounded-rectangle distance and boundary direction. For inward depth
  `d` and bevel width `w`, set `q = 1 - clamp(d / w, 0, 1)`. Surface height is
  `(H + C) * (1 - q^3)^(1/3)`, where `C` is the optional broad quartic crown.
  The full height gradient determines the Snell refraction normal. The refracted
  ray travels the backing distance plus local surface height. The cap's slope
  and slope derivative vanish toward the core, joining the crown smoothly.
  A small numerical bound keeps the outermost normal finite. Other diagnostic
  scenes retain an optional artistic center magnification term.
- Edge and interior scattering remain available for explicit reference profiles.
  Both are disabled in default Clear. Flower and Desert retain their tuned
  scattering and disable the additional narrow transmission spread.
- Default Clear uses `transmissionRoughness = 0.008`, a small angular spread in
  radians. Projecting a ray cone onto the background gives a footprint growing
  with optical travel and obliquity, elongated along the refracted ray. A smooth
  screen-basis projection avoids a direction seam at the optical center. A
  normalized 5-by-5 binomial kernel averages nearby transmitted colors in linear
  light. The largest standard deviation is capped at two logical source pixels;
  this bounds extra softness independently of the existing minification filter.
  Uniform colors remain unchanged, and bright regions cannot spread through a
  broad blurred-image blend. The kernel does soften narrow dark details: it is
  not contrast-preserving sharpening. Zero presence removes the spread exactly.
  This is an independent rough-transmission approximation, not recovered Apple
  code or a complete simulation of two refracting surfaces.
- Lighting and shadows are analytic approximations. A finite projected light
  sits half the backdrop diagonal from its center in `lightDirection`. Incident
  directions vary over the surface, so translation through the scene and light
  movement affect the highlights coherently. A core plus an inward shoulder and
  luminance-dependent edge shading are empirical, not measured Apple equations.
  The opaque sampled material
  is composited once inside its antialiased coverage mask; it is not an alpha
  overlay of the same scene. Labels are rendered after the glass.
- `ambientReflection` samples three positions just outside the boundary from the
  softened source. Their color affects only the perimeter, fading to zero
  toward the interior. Reflection strength is capped at 25%; it follows Light
  and Compare and never samples already rendered glass. This is a local color
  response, not a reconstruction of an environment map or Apple's reflection
  method. It is disabled in default Clear: averaging unrelated surroundings
  into the rim washed out its transmitted colors. Directional highlights remain.
  Flower, Desert, and the three reference studies also keep this blend disabled.
- Default material dimensions use a smooth size response based on the shorter
  side, from 96 to 420 logical pixels. Bevel/radius increases from 0.38 to 0.82,
  backing distance/radius from 0.6 to 2.0, and surface height/radius from 0.5 to
  0.68. Narrow transmission softness grows with the resulting optical travel;
  the broad diffuse-image blend stays disabled at every size.
  Explicit profile overrides still take precedence. The Size study's shared
  analysis blur grows from 4 to 16 pixels; it does not blur Clear transmission.
  Callers own that buffer's resolution and padding.
- `AdaptiveInk.qml` makes one light/dark decision for a label group using nine
  samples from the softened backdrop. This is a simple prototype threshold,
  without temporal hysteresis or Apple's proprietary adaptation rules.
- Pressing the lens changes its dimensions and optical depth. Dragging updates
  its source position without scaling or rotating its ancestors.

The model is not extracted Apple shader code. Circular corners, analytic lighting,
the chosen bevel, and label adaptation remain calibration candidates. The
material currently expects an opaque source scene and axis-aligned geometry in
one coordinate system. Arbitrary shape merging is not implemented. The optical
lab's buffers follow Qt's graphics backend. Desktop composition has its own
buffer ownership and restrictions, described below.

## Verify

```bash
python3 scripts/liquid-glass-lab/lab.py build
python3 scripts/liquid-glass-lab/lab.py check
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml scripts/liquid-glass-lab/*.qml
./tests/smoke.sh
```

`check` additionally requires a C++20 compiler, pkg-config, Qt Quick development
files, Qt Test, and a graphical display. It opens temporary Qt windows, renders
the actual shaders through OpenGL, and repeats at scale factors 1 and 2. It does
not use screenshots of the desktop as the rendering source.

The checks cover identity sampling, refraction direction, an undistorted center,
shape bounds, fractional movement, resizing, background updates, feedback,
blur, foreground integrity, adaptive ink, keyboard input, pointer dragging,
press/release geometry, animation, flower loading/placement, and optical
materialization endpoints. Additional coordinate-encoded probes verify that the
Flower rim samples across the circle center while its interior stays upright,
and that the small circle folds more strongly with the shared optical lengths.
Temporal checks verify both stationary lenses respond to moving content and
return to the initial image after a full cycle without feedback. Flower captures
cover the central petal boundary, the petal silhouette, and quiet sky.
Additional checks cover rotating light without disturbing the flat center,
illumination inside the curved region, a highlight moving along a straight edge,
light refracted beneath the boundary's dark pocket, the three reference cycles,
fixed geometry during illumination changes, moving geometry in Boundary/Panel,
scene switching, and the moving panel's foreground bar. The surrounding-color
fixture holds the interior gray while changing the outside from red to blue;
checks require a curved-surface response, a stable center, and an unchanged
surface when reflection is disabled. Size checks cover geometry and depth,
Compare at an intermediate size, restrained detail softening and stable broad
colors under the actual Clear defaults, and returning to the initial image.
Narrow-transmission checks cover fine-detail contrast, dark and saturated regions
next to bright content, the bounded reach at long optical paths, unchanged
foreground pixels, and unchanged background outside the glass.
Body-lens checks cover interior refraction on
both axes, the aligned optical center, continuous upright core sampling, exact
zero-presence and disabled-crown behavior, and no color veil on uniform black,
gray, or white.
Screenshots and `results.json` record
the result and graphics driver for each scale. These are functional checks, not
GPU benchmarks or proof of Apple fidelity. The separate desktop checks measure
the material's GPU pass; neither suite establishes full desktop frame pacing.

## Desktop clock

Start with isolated validation and a preview from a Hyprland graphical session:

```bash
python3 scripts/liquid-glass-lab/lab.py desktop-check
python3 scripts/liquid-glass-lab/lab.py desktop-record
```

`desktop-check` creates disposable nested compositors at scales 1, 1.25, and 2.
It uses separate Wayland clients for the background window and the transparent
Quickshell widget, with ordinary partial damage tracking enabled. The rendering checks
must pass: actual background refraction, stationary feedback, identity sampling,
fractional coordinates, movement cleanup, hide/resize cleanup, crisp foreground,
real pointer press/click/drag/release, live updates, idle behavior, and unloading.
Comparisons score the fixture window, excluding the compositor's independently
timed startup notice. The test records pixel differences, ABI details, source
and binary fingerprints, and asynchronous GPU timer results. Duplicate success
captures are discarded; failed comparisons retain their images.

At normal scale it also tests unload/reload and replacement within the **same**
compositor. A second compiled backend has a different initial strength, proving
that the replacement code actually executes. It checks address-space mappings,
state reset, pixel equivalence after restoring strength, repeated reloads, and
cleanup. The launcher and tests use the same immutable-file publishing function.

The optional normal-session commands are:

```bash
python3 scripts/liquid-glass-lab/lab.py desktop
python3 scripts/liquid-glass-lab/lab.py desktop-stop
```

`desktop` requires passing normal-scale rendering **and replacement** results for
the exact source and binary, and the same ABI in the running compositor.
It loads the tested backend and opens
a new clock. Drag the clock to move it; click to switch between compact and
expanded sizes. Pressing deforms the actual surface geometry and optical depth,
and the type size follows expansion. Its transparent outer padding does not
intercept pointer input. `desktop-stop` closes this clock and unloads its backend
from the recorded compositor instance. Existing widget processes remain separate.

**Development incident:** an earlier launcher crashed the normal compositor on
its second load after a rebuild. It copied over the same shared-library inode
after unloading; the crash stack ended in the dynamic loader's `dlsym`. The old
binary contained GNU unique symbols, which can keep a library resident after
`dlclose` ([GCC documentation](https://gcc.gnu.org/onlinedocs/gcc-13.4.0/gcc/Code-Gen-Options.html#index-fno-gnu-unique)).
This is the leading cause supported by the code and crash report, rather than a
reproduction of the old crash. The desktop was recovered through Hyprland's Safe
Mode dialog. The corrected launcher publishes complete files named by their
SHA-256 hash without replacing an existing inode; the backend is built with
`-fno-gnu-unique`. The replacement tests above cover the formerly missing
lifecycle case. The corrected loader has only been exercised in isolated
compositors; it has not been reloaded in the recovered normal desktop.

The expanded test also exposed a separate unload bug: the compositor can retain
the last frame's custom pass after drawing it. The backend now removes its own
pass objects before the library is unmapped, in addition to disconnecting its
callbacks and releasing GPU resources. Tests unload with the widget still visible
so hiding it first cannot conceal this lifetime error.

`desktop-record` records six seconds of the actual nested compositor with a
moving background, resize transitions, and repositioning. The 20 fps encoded
clip, capture timestamps, and material timing are saved under `desktop-record/`
in the cache. External screenshot capture is used only to export this evidence;
it is never the material's input. Capture overhead makes this a visual recording,
not a frame-pacing benchmark.

Requirements: Hyprland 0.56.2 with matching development headers, its OpenGL
renderer, Quickshell, a C++23 compiler, GLES, pkg-config, grim, and ffmpeg. Nothing
is installed by these commands. Native integration currently accepts unrotated
SDR outputs using sRGB or gamma-2.2 work buffers. It skips mirrored, rotated,
HDR/linear outputs and the locked session. Those configurations need separate
color/coordinate validation; they are not silently treated as SDR. The clock's
foreground uses white outlined text;
the owned-scene lab's adaptive ink is not yet provided by the desktop backend.

### GPU ownership and redraw behavior

The backend is `desktop.cpp` plus `desktop-gpu.hpp`. `desktop_build.py` adapts
the **same** `glass.frag` and `blur.frag` used by Qt into standalone GL programs;
there is no second copy of the refraction or lighting equations. The crop's
light position is converted from monitor coordinates so moving the crop does
not move the light source with it.

Only mapped top-layer surfaces with namespace `liquid-glass-v1` opt in. Each
surface reserves 28 logical pixels on each side for its shadow; the inner
rectangle is the glass body. Quickshell owns text, input, placement, and sizing.
Hyprland owns the material. A pass after ordinary windows makes a GPU-to-GPU
copy of their composed pixels, builds two shared blur targets, then renders
the material before Quickshell's foreground. Several disjoint surfaces share
the same snapshot. Overlapping shapes do not yet merge into one surface.
There is no CPU image readback, exported backdrop, recurring output screencopy,
or cross-process graphics synchronization in this path.

The copy includes a conservative 220-logical-pixel source margin, covering
refraction, blur, reflection, and shadow under the bounded default profile.
Only real monitor edges clamp samples. The pass declares a backdrop dependency
to preserve source pixels during occlusion analysis. Before an already scheduled
frame, current and previous source regions are added to the damage ring so
movement/hiding cannot leave glass in the next background sample. This does not
schedule another frame and therefore does not create an idle redraw loop.
The implementation conservatively redraws the region on each scheduled frame;
finer dependency tracking is an optimization, not a prerequisite for correctness.

GL state is restored after each pass, timer results are read only when available,
and buffers are released on monitor removal and plugin unload. The final
compositor output still performs its normal SDR color handling. The backend's
material timings cover copy, mipmaps, blur, and glass drawing, not all compositor
or Quickshell work. Inspect current counters with `hyprctl liquidglass`. Optical
strength can be set with `hyprctl liquidglass presence 0` through `1` for comparison.

## Desktop render-order probe

```bash
python3 scripts/liquid-glass-lab/lab.py desktop-probe
```

This optional diagnostic additionally requires Hyprland development headers
matching the installed compositor, a C++23 compiler, GLES, and ffmpeg. It opens
a temporary nested Hyprland window, then closes it and its Quickshell fixture.
It builds and loads only the newly written `desktop-probe.cpp` in that child.
An explicitly invalid libseat backend prevents acquisition of the physical
seat; systemd environment export and notification are disabled. The launcher
selects the child's exact PID/signature and verifies a nested Wayland output.
The plugin independently requires that PID and the restricted environment and
rejects an ABI mismatch. The installed compositor is not a plugin target.

The fixture is a blue background layer, an amber ordinary Wayland window, and a
magenta top-layer marker. A custom render-pass element reads the framebuffer
after ordinary windows and another reads it after the top layers. The proof
requires the amber window in the first image, the marker in the final image,
no marker pixels in the first image, and the same outside background. A small
asymmetric indicator verifies the framebuffer's vertical orientation. Captures,
version metadata, and assertions are overwritten in `desktop-probe/` in the
lab cache.

The stage event assembles the render pass; it is **not** itself a safe point to
read current pixels. The custom element's `draw()` executes in the proper GPU
order. This diagnostic uses two CPU readbacks and full damage with occlusion
simplification disabled. Those are proof mechanisms, not the production design.
The desktop backend above implements the GPU copy and in-compositor rendering,
source padding, damage and occlusion handling, fractional scale, and GPU timing.
The original probe remains a smaller independent check of the required ordering.
A normal output screencopy includes the glass itself and is unsuitable as a
direct recurring backdrop source.

Primary implementation references, inspected against installed Hyprland 0.56.2:
[render stages](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/render/Renderer.cpp),
[pass execution](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/render/pass/Pass.cpp),
[libseat backend selection](https://github.com/kennylevinsen/seatd/blob/0.9.3/libseat/libseat.c),
and [Quickshell ScreencopyView](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ScreencopyView/).

Build products and a fixed set of evidence files are overwritten in
`$XDG_CACHE_HOME/dotfiles-liquid-glass-lab` (default
`~/.cache/dotfiles-liquid-glass-lab`). No generated files belong in Git. After
stopping the prototype, this dedicated cache directory can be removed.
