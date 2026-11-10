-- ╭─────────────────────────────────────────────────────────────────────────╮
-- │  Atoll for Omarchy — keybindings                                       │
-- │                                                                         │
-- │  Loaded from ~/.config/hypr/bindings.lua (the installer can add this):  │
-- │    pcall(dofile, os.getenv("HOME")                                      │
-- │      .. "/.config/omarchy/plugins/atoll.bar/keybinds.lua")             │
-- │                                                                         │
-- │  Every action is an IPC call into Omarchy's running shell:              │
-- │    omarchy-shell atoll run <action>   (or the `atoll run` wrapper)    │
-- │  The keys below are free in a stock Omarchy. Check yours with:          │
-- │    omarchy menu keybindings --print                                     │
-- ╰─────────────────────────────────────────────────────────────────────────╯

local function atoll(action)
  return "omarchy-shell atoll run " .. action
end

-- ── Notch ───────────────────────────────────────────────────────────────────

o.bind("SUPER + R", "Atoll launcher", atoll("launcher"))
o.bind("SUPER + D", "Atoll dashboard", atoll("dashboard"))
o.bind("SUPER + COMMA", "Atoll wallpapers", atoll("wallpapers"))
o.bind("SUPER + SHIFT + V", "Atoll clipboard", atoll("clipboard"))
o.bind("SUPER + ALT + PERIOD", "Atoll emoji", atoll("emoji"))
o.bind("SUPER + ALT + N", "Atoll notes", atoll("notes"))
o.bind("SUPER + ALT + T", "Atoll tmux sessions", atoll("tmux"))
o.bind("SUPER + ALT + A", "Atoll assistant", atoll("assistant"))
o.bind("SUPER + ALT + O", "Atoll overview", atoll("overview"))
o.bind("SUPER + SHIFT + ESCAPE", "Atoll power menu", atoll("powermenu"))

-- ── Tools ───────────────────────────────────────────────────────────────────

o.bind("SUPER + ALT + X", "Atoll tools", atoll("tools"))
o.bind("SUPER + ALT + Z", "Atoll screenshot", atoll("screenshot"))
o.bind("SUPER + ALT + R", "Atoll screen recorder", atoll("screenrecord"))
o.bind("SUPER + ALT + E", "Atoll lens (search the screen)", atoll("lens"))
o.bind("SUPER + ALT + C", "Atoll settings", atoll("config"))

-- ── Optional: Atoll's own key layout ───────────────────────────────────────
-- These are upstream Ambxst's defaults. They replace Omarchy bindings, so they
-- are commented out; remove the leading "--" to use them.
-- o.rebind("SUPER + SPACE", "Atoll launcher", atoll("launcher"))          -- was: Omarchy launcher
-- o.rebind("SUPER + V", "Atoll clipboard", atoll("clipboard"))             -- was: Omarchy clipboard
-- o.rebind("SUPER + PERIOD", "Atoll emoji", atoll("emoji"))                -- was: Omarchy emojis
-- o.rebind("SUPER + TAB", "Atoll overview", atoll("overview"))             -- was: next workspace
-- o.rebind("SUPER + ESCAPE", "Atoll power menu", atoll("powermenu"))       -- was: Omarchy system menu
-- o.rebind("SUPER + SHIFT + S", "Atoll screenshot", atoll("screenshot"))   -- was: Omarchy screenshot
