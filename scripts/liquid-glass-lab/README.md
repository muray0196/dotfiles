# Liquid Glass playground

A Quickshell playground for the current desktop glass, with independently
selectable shapes, backgrounds, and appearances. It uses the existing
`Glass.qml`, `BackdropSource.qml`, and the same `glass.frag` compiled by the
desktop backend. Sample labels reuse the current widget's `Label.qml` through
the `widget` source-directory link. The runner copies only that label component
into the bounded lab cache.

The optical lab samples its own animated scene. The separate **desktop backend**
renders the same material directly from Hyprland's current GPU framebuffer,
under a Quickshell clock. The desktop commands below are explicit experimental
operations; they do not install a service or modify persistent compositor
configuration. Device-matched native Apple captures are still required before
claiming a match to a particular Apple material. The WWDC demonstration is a
qualitative visual reference.

## Run

From the repository root, in the graphical session:

```bash
python3 scripts/liquid-glass-lab/lab.py run
python3 scripts/liquid-glass-lab/lab.py run --paused
python3 scripts/liquid-glass-lab/lab.py stop
```

Requirements: Python 3, Quickshell, Qt 6 Quick, and Qt Shader Tools (`qsb`).
The runner finds `qsb` on `PATH` or at Arch's `/usr/lib/qt6/bin/qsb`.
It installs nothing. The playground opens a 1120 × 800 floating window.

The playground opens with a collection of three shapes on Flower. Choose Circle,
Pill, Card, Wide panel, Tall panel, or Collection, and independently switch
between Flower, Desert, Color, Grid, Type, Split, White, and Dark backgrounds.
Drag each surface, toggle sample content or text appearance, pause Motion,
and use Compare to inspect the unobstructed source. Recenter resets placement
and the background's motion phase. Close or Escape exits this window only.
Keys 1–6 select shapes, B cycles backgrounds, Space pauses, G compares, and R
recenters. Sample content is illustrative, not live telemetry.

Clarity and Tint map to the current desktop renderer's settings. Soft with
tint Off is the default; preview controls are grouped separately. Geometry is the only
per-shape input: dimensions and a circle/pill outline or the normal rounded
rectangle. Edge width, surface height, thickness, body curvature, refraction,
lighting, and shadows follow `Glass.qml` without overrides. Background selection
never changes any material input. The shared analysis filter matches the
desktop's half-resolution sigma of 2.8. There are no per-background or per-shape
material presets. This is an in-scene Qt preview of the shared material, not a
capture of the compositor's desktop framebuffer.

### Clarity and tint

Clarity controls background detail. Tint adds an optional color independently.
The playground, desktop backend, and appearance picker share these definitions:

| Attribute | Choice | Rendering and purpose |
| --- | --- | --- |
| Clarity | **Clear** | Refraction and highlights with no added smoothing. Retains full background detail. |
| Clarity | **Soft** (default) | Restrained local transmission filtering (`transmissionRoughness = 0.008`), preserving a transparent appearance while calming fine texture. |
| Clarity | **Diffused** | Mixes 85% of the broadly filtered source into the interior. The narrow filter is off. |
| Tint | **Off** (default) | Preserves transmitted colors without a colored backing. |
| Tint | **Black** | Mixes in black at approximately 64% opacity to support light foreground text. |
| Tint | **White, Blue, Teal, Green, Amber, Rose** | Mixes in the selected color at approximately 32% opacity, keeping the transmitted image visible. |

Clarity is one choice, not two stackable filters. Selecting a clarity preserves
the current tint, and selecting a tint preserves clarity. Neither changes the
surface geometry, refraction field, highlight settings, or foreground typography.
Both the broad filter and tint ease in over the outer 12 logical pixels.
Compare removes all optical treatment, including tint, to reproduce the source.
`tints.json` is the shared palette: the build generates the QML palette and native
header from its ARGB values, and both paths use the same shader calculation.
The labels describe this project's rendering, not recovered Apple material modes.

Clear was previously named Sharp, and Soft was previously named Clear. This
rename preserves their rendering and the gently smoothed default. CLI values
follow the new names: use `clear` for no added smoothing and `soft` for the narrow
filter. The former independent Softness switch and combined `soft-tinted` preset
have been removed. Use the current commands instead:

```sh
hyprctl liquidglass clarity clear
hyprctl liquidglass clarity soft
hyprctl liquidglass clarity diffused
hyprctl liquidglass tint off
hyprctl liquidglass tint black
hyprctl liquidglass tint blue
hyprctl liquidglass
```

Status reports `clarity` and `tint`. The widget controller exposes the same two
attributes through `desktop.py clarity` and `desktop.py tint`, with an optional
value; omit it to read the current selection. The backend starts in Soft with tint Off.
Tint replaces the former Natural/Dark tone setting; use `off` or `black` respectively.
These are runtime settings; no preference file or login configuration is written.

Soft's local filter uses a kernel scaled by optical depth, with interior spread
capped at 1.6 logical pixels. It averages displayed RGB values in the interior to
avoid lifting the mean brightness of contrasting detail; the bevel retains the
existing linear-light filter. Each tap covers its sampling footprint through the
existing mip chain. This is the previously selected Softness filter, not a new
blur strength or retuned edge. `filterInterior: false` remains a low-level optical
fixture option, not a user-facing control.
The flat interior skips the linear-light color conversions whose results it
discards. Its 25 samples, weights, and encoded-color average are unchanged;
the curved edge retains the original linear-light calculation.

Clear still uses the refracted pixel footprint to prevent sampling aliasing;
no extra transmission blur or neutral veil is added. Diffused uses the existing
broad source buffer and never adds Soft's narrow filter on top. There is no new
capture or redraw timer for any clarity or tint.

The desktop's Clear mode now uses **4× hardware anisotropic filtering** on the
full-resolution source, retaining bilinear magnification, trilinear mipmaps,
zero LOD bias, and clamp-to-edge. It preserves more detail where the refracted
footprint is compressed unevenly. The requested 4× level is capped at the GPU's
supported maximum; unsupported GPUs retain isotropic filtering. Soft,
Diffused, the broad analysis texture, and the Qt playground retain their
existing isotropic sampling. `hyprctl liquidglass` reports `source_anisotropy`
and `max_anisotropy` (the minimum across initialized output renderers).

For Clear and Soft, the broad lighting blur runs only over the glass footprints, with
extra rows for the vertical kernel and texels for bilinear filtering. Overlapping
footprints are merged. Both modes use this buffer only for lighting. The lookup
is unrefracted and magnifies the half-resolution buffer, so both also skip its
unused mipmap generation. Their full-resolution source filtering is unchanged. The
blur kernel, highlight appearance, output resolution, and frame scheduling are
unchanged; this optimization does not reduce refresh rate.

Diffused displays the broad blur and retains its full-region calculation and
mipmaps. Where half-float rendering is supported, the desktop stores the horizontal
result in linear RGBA16F. This avoids rounding that intermediate to 8-bit encoded
RGB and decoding each vertical tap again. At native scale, hardware bilinear
filtering combines adjacent vertical taps: 11 fetches retain all 21 Gaussian
weights. Other scales retain 21 fetches because their taps are not adjacent
texels. Blur strength, radius, half-resolution dimensions, and final RGBA8 output
remain unchanged. At fractional scales, the vertical pass also interpolates in
linear light. Small pixel differences from the former 8-bit intermediate are
expected; this path improves intermediate precision rather than promising byte
identity. It uses about 2 MiB more intermediate storage for a 1920 × 1080 capture.
GPUs without half-float render-target support retain the original blur. The Qt
playground retains its existing intermediate format; the five-widget desktop
test uses the actual desktop backend.

Large default surfaces also have a shallow, continuous body lens. A quartic
height field adds gentle curvature across the broad interior and joins the
rounded perimeter through the existing cap profile. Its analytic surface normal
and height drive the same refraction calculation; it adds no color fill or blur.
The maximum additional height is 5.5% of the short side, eased down for small
controls. Uniform backgrounds remain uniform under refraction, and the exact
optical center stays aligned. This is an independent single-interface optical
approximation, not a two-surface ray trace or a physical fluid simulation.

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
- **3:10–3:38:** movement and appearance belong to one material. This playground
  keeps geometry fixed while dragging so it can isolate spatial sampling.

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
color wrapping and textured detail. The older tuned reference scenes have been
removed; these observations remain research context, not playground presets.

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
a straight edge.

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

The earlier per-scene Flower and Desert optical profiles have been removed.
Both images now exercise the same current material and geometry rules in the
playground. Backgrounds do not select bevel lengths, depth, or lighting.

`assets/flower.png` is the unchanged 1985 × 792 image supplied by the user on
2026-10-17, not a frame extracted from Apple's video. Different subject framing
prevents direct pixel-error comparisons against that video. Its SHA-256 is
`ba21aafca6eeb8241f1ef4852b0926de962e653cee4490042c7ba56a01b91697`.
`assets/desert.png` is the unchanged unobstructed 1920 × 1080 frame at **2:59.8**
from the Apple video linked above, retained as a playground
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
  A small numerical bound keeps the outermost normal finite. The shader retains
  an optional center magnification term, disabled in the playground.
- The shader's edge and interior scattering controls remain available to optical
  fixtures. Both are disabled in default Soft.
- Soft uses `transmissionRoughness = 0.008`, a small angular spread in
  radians. Projecting a ray cone onto the background gives a footprint growing
  with optical travel and obliquity, elongated along the refracted ray. A smooth
  screen-basis projection avoids a direction seam at the optical center. A
  normalized 5-by-5 binomial kernel keeps linear-light averaging at the bevel.
  With `filterInterior`, it eases into displayed-RGB averaging and a 1.2-times
  wider spread beyond the bevel, retaining the 1.6-logical-pixel kernel bound.
  The sampling footprint also covers gaps between the wider interior taps.
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
  method. It is disabled in default Soft: averaging unrelated surroundings
  into the rim washed out its transmitted colors. Directional highlights remain.
- Default material dimensions use a smooth size response based on the shorter
  side, from 96 to 420 logical pixels. Bevel/radius increases from 0.38 to 0.82,
  backing distance/radius from 0.6 to 2.0, and surface height/radius from 0.5 to
  0.68. Narrow transmission softness grows with the resulting optical travel;
  the broad diffuse-image blend stays disabled at every size.
  Callers own that buffer's resolution and padding.
- `AdaptiveInk.qml` is retained only as an optical test fixture for a simple
  light/dark threshold. The playground uses the current widget labels instead.
- Dragging updates the surface's source position without changing its geometry.

The model is not extracted Apple shader code. Circular corners, analytic lighting,
the chosen bevel, and label adaptation remain calibration candidates. The
material currently expects an opaque source scene and axis-aligned geometry in
one coordinate system. Arbitrary shape merging is not implemented. The optical
lab's buffers follow Qt's graphics backend. Desktop composition has its own
buffer ownership and restrictions, described below.

## Verify

### Clear quality and performance experiments

```sh
python3 scripts/liquid-glass-lab/lab.py benchmark --device /dev/dri/renderD128 --motion --power-seconds 6
```

Select the intended GPU render node explicitly. The offscreen EGL harness uses
the actual desktop renderer; it never loads a plugin into the running desktop.
It requires C++23, Qt 6.9+ GUI, EGL/GLES development tools, GPU timer
support, and anisotropic filtering up to 16. Motion export also needs ffmpeg.
It writes a bounded, replaceable `clear-benchmark/` directory in the lab cache:
`index.html` offers A/B switching, matching pixel crops and motion clips;
`results.json` retains timings, source hashes and pixel comparisons.

Clear is compared at 1× and 2× display scale with normal trilinear filtering,
4×/8×/16× anisotropy, an experimental −0.5 LOD bias, and bilinear-only sampling.
The desktop now selects AF4 for Clear; the harness explicitly overrides its
level so AF1/4/8/16 remain comparable. Full resolution, mipmaps and zero LOD
bias are retained. Negative LOD and bilinear-only sampling remain experiments. The no-mipmap
experiment still generates mipmaps: it isolates sampling quality, not the
potential cost of deleting their generation. The 4×-per-axis reference uses
the same optical model and is a diagnostic, not external ground truth.
Anisotropic sampling is driver-dependent; see the
[Khronos extension specification](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_texture_filter_anisotropic.txt).

The desktop's Gaussian sigma remains 2.8, now a shader constant so its weights
can be computed at compilation. The dynamic-sigma experiment reproduces the
previous uniform-based calculation for pixel and timing comparisons. The
playground retains an adjustable sigma. Clear still needs the broad analysis
buffer because highlight brightness samples it; removing it changes appearance.
The `full-analysis / AF4` control restores the original whole-region lighting
blur and analysis mipmaps, isolating the cost of the Clear optimization while
keeping its refraction and filtering identical. `vs_af4` in the results records
pixel differences against the optimized AF4 render; the check fails if the
full-analysis control differs by even one channel value.

Each shuffled trial warms up 48 frames. Timers cover the GPU copy, mipmaps,
analysis blur and three material draws, excluding fixture reset and readback.
`--frames` and `--repeats` control measurement length. These numbers do not
measure whole-desktop pacing. Optional `--power-seconds 4..60` runs three
interleaved trials of full-analysis AF4 and optimized AF4 at 60 fps, with a moving
source and no per-frame readback or file writes. Its whole-board sensor also includes
other desktop workloads, so small differences do not establish energy savings.
Motion moves the source by 0.25 physical pixels per frame. Four exact PNG phases
are retained; the H.264 clips are lossy viewing aids.

### Functional checks

```bash
python3 scripts/liquid-glass-lab/lab.py build
python3 scripts/liquid-glass-lab/lab.py check
/usr/lib/qt6/bin/qmllint -I /usr/lib/qt6/qml ~/.cache/dotfiles-liquid-glass-lab/*.qml
./tests/smoke.sh
```

`check` additionally requires a C++20 compiler, pkg-config, Qt Quick development
files, Qt Test, and a graphical display. It opens temporary Qt windows, renders
the actual shaders through OpenGL, and repeats at scale factors 1 and 2. It does
not use screenshots of the desktop as the rendering source.

Playground checks exercise all shape and background buttons, compare each
shape's optical properties against a fresh instance of the current `Glass.qml`,
and verify the shared shader path. They also cover background independence,
Compare, all 24 clarity/tint combinations and their round trips, actual pointer
dragging, Recenter, and the Close signal. Captures include `playground.png` and
one image per shape and clarity/tint combination at each display scale. Uniform-white
probes check each tint's actual RGB mixing against the shared palette.

The optical fixtures cover identity sampling, refraction direction, an
undistorted center, shape bounds, fractional movement, resizing, background
updates, feedback, blur, foreground integrity, and adaptive ink. Lighting probes
cover rotating illumination, falloff inside the curved region, and highlights
moving along straight edges without disturbing the flat center. The
surrounding-color fixture holds the interior gray while changing the outside
from red to blue, checking a stable center and the reflection toggle.
The playground checks Clear for source detail without added blur or a color
veil when refraction and lighting are isolated. It verifies that clarity selects
one smoothing approach, tint preserves clarity, and both preserve optical geometry.
Narrow-transmission checks cover fine-detail contrast, dark and saturated regions
next to bright content, the bounded reach at long optical paths, unchanged
foreground pixels, and unchanged background outside the glass.
Interior-filter checks additionally compare edge and corner pixels against the
checkpoint kernel and require preserved mean brightness on fine contrast detail.
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
lifecycle case. The soft-glass addition also compared the original unfiltered binary
against its replacement in one disposable compositor: flower, bright, and dark
backgrounds were pixel-identical. After rendering and integration checks passed,
the tested replacement was applied in the normal session while retaining the
original immutable binary and the existing widget process and geometry.

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
