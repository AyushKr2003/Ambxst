-- Ambxst for Omarchy — brightness keys through Ambxst.
--
-- Loaded (by the installer) only when Ambxst draws the OSD, i.e. Omarchy's
-- own omarchy.osd is switched off. Volume needs nothing here: Ambxst sees
-- every PipeWire change. Brightness changes made outside Ambxst have no
-- event to follow, so these keys go through Ambxst, which sets the level
-- (brightnessctl / ddcutil) and shows its OSD.

o.rebind("XF86MonBrightnessUp", "Brightness up", "omarchy-shell ambxst run brightness-up", { locked = true, repeating = true })
o.rebind("XF86MonBrightnessDown", "Brightness down", "omarchy-shell ambxst run brightness-down", { locked = true, repeating = true })
