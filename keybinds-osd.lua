-- Atoll for Omarchy — brightness keys through Atoll.
--
-- Loaded (by the installer) only when Atoll draws the OSD, i.e. Omarchy's
-- own omarchy.osd is switched off. Volume needs nothing here: Atoll sees
-- every PipeWire change. Brightness changes made outside Atoll have no
-- event to follow, so these keys go through Atoll, which sets the level
-- (brightnessctl / ddcutil) and shows its OSD.

o.rebind("XF86MonBrightnessUp", "Brightness up", "omarchy-shell atoll run brightness-up", { locked = true, repeating = true })
o.rebind("XF86MonBrightnessDown", "Brightness down", "omarchy-shell atoll run brightness-down", { locked = true, repeating = true })
