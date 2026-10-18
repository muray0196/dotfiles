-- Disposable nested session only. No autostart, includes, services, or bindings.
hl.monitor({output = "", mode = "preferred", position = "auto", scale = 1})
hl.config({
  general = {gaps_in = 0, gaps_out = 40, border_size = 0},
  animations = {enabled = false},
  decoration = {rounding = 0, blur = {enabled = false}, shadow = {enabled = false}},
  misc = {disable_hyprland_logo = true, disable_splash_rendering = true},
  debug = {damage_tracking = 0},
  xwayland = {enabled = false},
})
