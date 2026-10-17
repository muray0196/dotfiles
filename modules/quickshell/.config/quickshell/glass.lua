-- Opt-in live trial. Loading this file does not load or install HyprGlass.
-- The ordinary desktop and application windows keep their existing rendering.
if hl.plugin.hyprglass then
  local hg = hl.plugin.hyprglass
  local style = "off"
  local runtime = os.getenv("XDG_RUNTIME_DIR")
  local selection = runtime and io.open(runtime .. "/quickshell-glass-style", "r")
  if selection then
    local saved = selection:read("*l")
    selection:close()
    if saved == "smoky" or saved == "clear" or saved == "blurred" or saved == "legacy-clear"
      or saved == "frosted" or saved == "liquid"
      or saved == "rounded" or saved == "soft" or saved == "sculpted" then
      style = saved
    end
  end
  hg.config({
    enabled = false,
    layers = {
      enabled = style ~= "off",
      namespaces = "quickshell-clock,quickshell-performance",
      preset = "widgets-" .. (style == "off" and "clear" or style),
      live_resample = true,
      live_resample_fps = 60,
    },
  })

  hg.preset("widgets-smoky", {
    blur_strength = 1.4,
    blur_iterations = 2,
    refraction_strength = 0.14,
    refraction_spread = 0.08,
    chromatic_aberration = 0.02,
    fresnel_strength = 0.18,
    specular_strength = 0.16,
    edge_thickness = 0.035,
    lens_distortion = 0.0,
    glass_opacity = 1.0,
    tint_color = 0x18203028,
    dark = {
      brightness = 0.72,
      contrast = 0.88,
      saturation = 0.78,
      vibrancy = 0.1,
      adaptive_dim = 0.38,
    },
  })

  hg.preset("widgets-legacy-clear", {
    inherits = "widgets-smoky",
    blur_strength = 0.65,
    refraction_strength = 0.34,
    fresnel_strength = 0.28,
    specular_strength = 0.3,
    bevel_strength = 0.16,
    bevel_size = 1.5,
    bevel_tint = 0.35,
    bevel_shadow = 0.08,
    tint_color = 0x18203018,
    dark = { brightness = 0.82, adaptive_dim = 0.36 },
  })

  hg.preset("widgets-frosted", {
    inherits = "widgets-smoky",
    blur_strength = 2.2,
    refraction_strength = 0.08,
    fresnel_strength = 0.12,
    specular_strength = 0.1,
    tint_color = 0x18203030,
    dark = { brightness = 0.74, saturation = 0.68 },
  })

  -- Requires the optional edge-clarity patch. The rim samples the unblurred
  -- desktop at full resolution; the interior scatters light for legibility.
  hg.preset("widgets-liquid", {
    inherits = "widgets-legacy-clear",
    edge_clarity = 0.8,
    blur_strength = 0.7,
    blur_iterations = 2,
    refraction_strength = 1.25,
    refraction_flow = 1.0,
    refraction_spread = 0.0,
    edge_thickness = 0.075,
    fresnel_strength = 0.24,
    specular_strength = 0.3,
    bevel_strength = 0.35,
    bevel_size = 2.0,
    bevel_tint = 0.0,
    bevel_angle = 315.0,
    bevel_shadow = 0.15,
    chromatic_aberration = 0.0,
    tint_color = 0x16202c12,
    dark = { brightness = 0.78, contrast = 0.95, saturation = 0.95, adaptive_dim = 0.45 },
  })

  -- Optics23: one continuous curved lens. Radius must match Theme.qml;
  -- the background itself folds through the rounded shoulder.
  hg.preset("widgets-clear", {
    inherits = "widgets-liquid",
    layer_radius = 44.0,
    rim_width = 30.0,
    surface_curve = 2.2,
    integrated_lens = 1.0,
    -- Clearer transmission: keep the optical shape, reduce the frosted backing.
    blur_strength = 0.32,
    blur_iterations = 1,
    adaptive_scatter = 0.18,
    tint_color = 0x00000000,
    dark = { brightness = 0.98, contrast = 1.0, saturation = 1.0, vibrancy = 0.0, adaptive_dim = 0.10 },
    -- Clear empty areas, with feathered contrast immediately around foreground.
    local_dimming = 0.28,
    material_motion = 1.0,
    shadow_strength = 0.06,
    shadow_size = 8.0,
    edge_clarity = 0.88,
    -- Sets the curved cap and virtual image-plane depth.
    refraction_strength = 1.85,
    -- Keep the narrow edge reflection, without a broad glossy surface highlight.
    fresnel_strength = 0.42,
    specular_strength = 0.0,
    bevel_strength = 0.68,
    bevel_size = 2.0,
    bevel_shadow = 0.0,
    -- Restrained inner contrast; the narrow reflection should define the rim.
    adaptive_rim = 0.18,
    -- Background-coloured reflection and fixed, localized light on the curve.
    shaped_reflection = 1.0,
  })

  -- The explicitly launched reference scene uses the same Clear material.
  -- Its separate test build permits radii beyond the normal 48 px limit;
  -- the renderer clamps each circle to half its own surface size.
  hg.preset("reference-clear", { inherits = "widgets-clear", layer_radius = 1024.0 })
  hg.layer("quickshell-glass-reference", { preset = "reference-clear" })

  -- Only the transmitted background softens. Geometry, colour, local contrast,
  -- clear refracting rim, and fixed highlights are inherited unchanged.
  hg.preset("widgets-blurred", {
    inherits = "widgets-clear",
    blur_strength = 1.15,
    blur_iterations = 2,
  })

  -- Compatibility for an existing runtime choice during config reloads.
  hg.preset("widgets-rounded", { inherits = "widgets-clear" })

  hg.preset("widgets-soft", {
    inherits = "widgets-rounded",
    integrated_lens = 0.0,
    adaptive_rim = 0.0,
    shaped_reflection = 0.0,
    local_dimming = 0.0,
    layer_radius = 22.0,
    rim_width = 30.0,
    surface_curve = 1.65,
    adaptive_scatter = 0.85,
    shadow_strength = 0.13,
    shadow_size = 10.0,
    edge_clarity = 0.6,
    blur_strength = 1.15,
    refraction_strength = 1.6,
    specular_strength = 0.32,
    bevel_strength = 0.2,
    bevel_shadow = 0.04,
    dark = { brightness = 0.8, adaptive_dim = 0.46 },
  })

  hg.preset("widgets-sculpted", {
    inherits = "widgets-rounded",
    integrated_lens = 0.0,
    adaptive_rim = 0.0,
    shaped_reflection = 0.0,
    local_dimming = 0.0,
    layer_radius = 22.0,
    rim_width = 34.0,
    surface_curve = 2.7,
    adaptive_scatter = 0.55,
    shadow_strength = 0.18,
    shadow_size = 10.0,
    edge_clarity = 0.92,
    blur_strength = 0.65,
    refraction_strength = 2.25,
    fresnel_strength = 0.32,
    specular_strength = 0.55,
    bevel_strength = 0.32,
    bevel_shadow = 0.04,
    dark = { brightness = 0.8, adaptive_dim = 0.43 },
  })
end
