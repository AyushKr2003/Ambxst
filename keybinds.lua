-- ╭─────────────────────────────────────────────────────────────────────────╮
-- │  Ambxst for Omarchy — keybindings                                       │
-- │                                                                         │
-- │  Loaded from ~/.config/hypr/bindings.lua (the installer can add this):  │
-- │    pcall(dofile, os.getenv("HOME")                                      │
-- │      .. "/.config/omarchy/plugins/ambxst.bar/keybinds.lua")             │
-- │                                                                         │
-- │  Every action is an IPC call into Omarchy's running shell:              │
-- │    omarchy-shell ambxst run <action>   (or the `ambxst run` wrapper)    │
-- │  The keys below are free in a stock Omarchy. Check yours with:          │
-- │    omarchy menu keybindings --print                                     │
-- ╰─────────────────────────────────────────────────────────────────────────╯

local function ambxst(action)
  return "omarchy-shell ambxst run " .. action
end

-- ── Notch ───────────────────────────────────────────────────────────────────

o.bind("SUPER + R", "Ambxst launcher", ambxst("launcher"))
o.bind("SUPER + D", "Ambxst dashboard", ambxst("dashboard"))
o.bind("SUPER + COMMA", "Ambxst wallpapers", ambxst("wallpapers"))
o.bind("SUPER + SHIFT + V", "Ambxst clipboard", ambxst("clipboard"))
o.bind("SUPER + ALT + PERIOD", "Ambxst emoji", ambxst("emoji"))
o.bind("SUPER + ALT + N", "Ambxst notes", ambxst("notes"))
o.bind("SUPER + ALT + T", "Ambxst tmux sessions", ambxst("tmux"))
o.bind("SUPER + ALT + A", "Ambxst assistant", ambxst("assistant"))
o.bind("SUPER + ALT + O", "Ambxst overview", ambxst("overview"))
o.bind("SUPER + SHIFT + ESCAPE", "Ambxst power menu", ambxst("powermenu"))

-- ── Tools ───────────────────────────────────────────────────────────────────

o.bind("SUPER + ALT + X", "Ambxst tools", ambxst("tools"))
o.bind("SUPER + ALT + Z", "Ambxst screenshot", ambxst("screenshot"))
o.bind("SUPER + ALT + R", "Ambxst screen recorder", ambxst("screenrecord"))
o.bind("SUPER + ALT + E", "Ambxst lens (search the screen)", ambxst("lens"))
o.bind("SUPER + ALT + C", "Ambxst settings", ambxst("config"))

-- ── Optional: Ambxst's own key layout ───────────────────────────────────────
-- These are upstream Ambxst's defaults. They replace Omarchy bindings, so they
-- are commented out; remove the leading "--" to use them.
-- o.rebind("SUPER + SPACE", "Ambxst launcher", ambxst("launcher"))          -- was: Omarchy launcher
-- o.rebind("SUPER + V", "Ambxst clipboard", ambxst("clipboard"))             -- was: Omarchy clipboard
-- o.rebind("SUPER + PERIOD", "Ambxst emoji", ambxst("emoji"))                -- was: Omarchy emojis
-- o.rebind("SUPER + TAB", "Ambxst overview", ambxst("overview"))             -- was: next workspace
-- o.rebind("SUPER + ESCAPE", "Ambxst power menu", ambxst("powermenu"))       -- was: Omarchy system menu
-- o.rebind("SUPER + SHIFT + S", "Ambxst screenshot", ambxst("screenshot"))   -- was: Omarchy screenshot
