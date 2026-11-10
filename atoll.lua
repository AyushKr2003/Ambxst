-- ╭─────────────────────────────────────────────────────────────────────────╮
-- │  Atoll look'n'feel -- Ambxst's Hyprland styling for Omarchy             │
-- │  Load it from ~/.config/hypr/looknfeel.lua (before your own tweaks):    │
-- │                                                                         │
-- │    pcall(dofile, os.getenv("HOME")                                      │
-- │      .. "/.config/omarchy/plugins/atoll.bar/atoll.lua")                 │
-- │                                                                         │
-- │  pcall keeps Hyprland starting if Atoll is uninstalled; dofile (not     │
-- │  require) re-reads it on every `hyprctl reload`. Anything set after     │
-- │  the dofile in looknfeel.lua wins.                                      │
-- ╰─────────────────────────────────────────────────────────────────────────╯
--
-- Upstream Ambxst doesn't ship a Hyprland file: its compositor page
-- (CompositorConfig.qml) and axctl generate one. This is that output, taken
-- from axctl's Lua generator (pkg/ipc/hyprland/generator_lua.go) and
-- Ambxst's layer rules (backend/pkg/svc/compositor/toml.go), with Atoll's
-- default compositor values (~/.config/atoll/config/compositor.json):
-- 2/4 gaps, a 2px border, 16px corners (the shell's own roundness), a soft
-- shadow, light blur, and one ease curve for windows, borders, fades and the
-- workspace slide. Atoll's own `manageHyprland` stays off, so this file --
-- not the shell -- is what styles Hyprland while Atoll is the bar.

local home = os.getenv("HOME")

-- ── Values (Atoll's compositor.json defaults) ───────────────────────────────

local vars = {
  gapsIn = 2,
  gapsOut = 4,
  borderSize = 2,
  -- compositor.syncRoundness: windows take the shell's roundness (theme.json).
  rounding = 16,

  shadowRange = 8,
  shadowRenderPower = 3,
  -- Atoll's "shadow" colour (black) at its shadowOpacity 0.5.
  shadowColor = "rgba(00000080)",

  blurSize = 4,
  blurPasses = 2,
  -- Atoll's surfaces are full-screen and mostly transparent: only blur where
  -- they actually draw (compositor.json blurIgnoreAlphaValue).
  layerIgnoreAlpha = 0.2,

  -- axctl's curve and speed for every Ambxst animation.
  speed = 2.5,
}

-- ── Live values from the shell and the theme ────────────────────────────────

local function read(path)
  local f = io.open(path)
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- Atoll's roundness, when the shell has written its theme.json.
local theme_json = read(home .. "/.config/atoll/config/theme.json")
local roundness = theme_json and tonumber(theme_json:match('"roundness"%s*:%s*(%d+)'))
if roundness and roundness >= 0 and roundness <= 64 then vars.rounding = roundness end

-- Workspaces slide along the bar's axis, as Ambxst does
-- (CompositorTomlWriter.qml): slidefade for a top/bottom bar,
-- slidefadevert for a left/right one.
local bar_json = read(home .. "/.config/atoll/config/bar.json")
local bar_position = bar_json and bar_json:match('"position"%s*:%s*"(%a+)"') or "top"
local workspace_style = (bar_position == "left" or bar_position == "right") and "slidefadevert 20%" or "slidefade 20%"

-- Borders in Atoll's palette: `primary` (the active border) is the Omarchy
-- theme's accent, `surface` (the inactive one) its background
-- (modules/theme/OmarchyPalette.js). Read from the current theme so a theme
-- switch (which reloads Hyprland) keeps them in step; without the file the
-- theme's own hyprland.lua colours stay.
local colors = read(home .. "/.local/state/omarchy/current/theme/colors.toml") or ""
local function color(key)
  local hex = colors:match("\n" .. key .. '%s*=%s*"#(%x%x%x%x%x%x)"')
  return hex and ("rgb(" .. hex .. ")") or nil
end
local active_border, inactive_border = color("accent"), color("background")

-- ── General / decoration ────────────────────────────────────────────────────

local general = {
  gaps_in = vars.gapsIn,
  gaps_out = vars.gapsOut,
  border_size = vars.borderSize,
}
if active_border and inactive_border then
  general.col = { active_border = active_border, inactive_border = inactive_border }
end

hl.config({
  general = general,

  decoration = {
    rounding = vars.rounding,
    shadow = {
      enabled = true,
      range = vars.shadowRange,
      render_power = vars.shadowRenderPower,
      sharp = false,
      color = vars.shadowColor,
      color_inactive = vars.shadowColor,
      offset = "0 0",
      scale = 1.0,
    },
    blur = {
      enabled = true,
      size = vars.blurSize,
      passes = vars.blurPasses,
      ignore_opacity = true,
      new_optimizations = true,
      xray = false,
      special = true,
      popups = false,
    },
  },
})

-- ── Animations (axctl's generator) ──────────────────────────────────────────
-- One ease (Material's standard curve) at speed 2.5: windows pop in from 80%,
-- borders and fades follow it, workspaces slide-fade 20%. Omarchy's defaults
-- also set the In/Out sub-leaves, which would win over the parents, so they
-- get the same curve.

hl.curve("atoll", { type = "bezier", points = { { 0.4, 0.0 }, { 0.2, 1.0 } } })

hl.config({ animations = { enabled = true } })

for _, leaf in ipairs({ "windows", "windowsIn", "windowsOut", "windowsMove" }) do
  local a = { leaf = leaf, enabled = true, speed = vars.speed, bezier = "atoll" }
  if leaf ~= "windowsMove" then a.style = "popin 80%" end
  hl.animation(a)
end
hl.animation({ leaf = "border", enabled = true, speed = vars.speed, bezier = "atoll" })
for _, leaf in ipairs({ "fade", "fadeIn", "fadeOut" }) do
  hl.animation({ leaf = leaf, enabled = true, speed = vars.speed, bezier = "atoll" })
end
hl.animation({ leaf = "workspaces", enabled = true, speed = vars.speed, bezier = "atoll", style = workspace_style })

-- ── Layers (Ambxst's layer rules) ───────────────────────────────────────────
-- Atoll's notch, bar, dock and popups animate themselves; a compositor fade
-- on top doubles the motion, so they skip Hyprland's layer animation. They
-- get blur behind what they draw (ignore_alpha keeps the transparent rest
-- of the full-screen surface unblurred).
hl.layer_rule({
  match = { namespace = "^atoll$" },
  blur = true,
  blur_popups = true,
  no_anim = true,
  ignore_alpha = vars.layerIgnoreAlpha,
})
hl.layer_rule({
  match = { namespace = "^(atoll:.*|quickshell:notificationPopup)$" },
  no_anim = true,
})
