<p align="center">
<img src="./assets/ambxst/ambxst-logo-color.svg" alt="Ambxst Logo" width="50%" />
</p>

<p align="center"><b>Ambxst for Omarchy</b> — <a href="https://github.com/Axenide/Ambxst">Ambxst</a>, the <i>Axtremely</i> customizable shell, as an <a href="https://omarchy.org">Omarchy</a> shell plugin.</p>

---

Ambxst's bar, notch (dynamic island), dock, dashboard, launcher, overview, notifications, OSD, tools and settings, running **inside Omarchy's own shell** as one bar plugin (`ambxst.bar`). Ambxst is the look; Omarchy is the engine.

- No second Quickshell, no Go daemon: it runs in the `omarchy-shell` process Omarchy already starts.
- Omarchy first: data and actions come from Omarchy's commands and state (theme, background, clipboard history, night light, stay-awake, screen recording, lock, power menu, workspace layouts). Base Omarchy packages fill the rest (NetworkManager, grim, ImageMagick, tesseract, zbar, wl-clipboard).
- Colours follow your Omarchy theme live (`omarchy theme set`), or Ambxst's own matugen/preset colours if you choose.

## Install

Requires Omarchy with its shell running.

```bash
git clone https://github.com/AyushKr2003/Ambxst.git
cd Ambxst
./install.sh
```

The installer:

1. installs what Ambxst needs that Omarchy doesn't ship, with `omarchy-pkg-add` (`qt6-multimedia`, gstreamer plugins, Nerd Font symbols, Spanish OCR data; `matugen` optional). Ambxst's fonts (Phosphor icons, Roboto Condensed, League Gothic) are bundled in `assets/fonts`;
2. copies the plugin to `~/.config/omarchy/plugins/ambxst.bar` (validated with `omarchy plugin validate`) and puts an `ambxst` command in `~/.local/bin`;
3. asks which Omarchy services Ambxst should take over — notifications, OSD, dock — and switches those off with `omarchy plugin disable`;
4. optionally loads `keybinds.lua` from `~/.config/hypr/bindings.lua`;
5. selects Ambxst as the bar: `omarchy bar use ambxst.bar`.

Everything it changes is recorded in `~/.local/state/ambxst/omarchy-install.json`.

| Command | Purpose |
|---|---|
| `./install.sh --yes` | Install with every default |
| `./install.sh --dev` | Link the plugin to this checkout (edits reload live) |
| `./install.sh --dry-run` | Show what would happen |
| `./install.sh --no-notifications --no-osd --no-dock` | Keep Omarchy's own services |
| `./uninstall.sh` | Restore the previous bar, services and keybinds |
| `./uninstall.sh --purge` | …and delete Ambxst's settings and caches |
| `ambxst disable` / `ambxst enable` | Switch between Omarchy's bar and Ambxst |
| `ambxst status` | Show whether it is installed and active |

Update: `git pull && ./install.sh` (settings are kept).

## Keybindings

`keybinds.lua` (added by the installer) uses keys that are free in a stock Omarchy:

| Keys | Action |
|---|---|
| `SUPER + R` | Launcher |
| `SUPER + D` | Dashboard |
| `SUPER + COMMA` | Wallpapers |
| `SUPER + SHIFT + V` | Clipboard |
| `SUPER + ALT + PERIOD` | Emoji |
| `SUPER + ALT + N` / `T` / `A` | Notes / tmux / AI assistant |
| `SUPER + ALT + O` | Overview |
| `SUPER + SHIFT + ESCAPE` | Power menu |
| `SUPER + ALT + X` / `Z` / `R` / `E` | Tools / screenshot / screen recorder / lens |
| `SUPER + ALT + C` | Ambxst settings |

Upstream Ambxst's own layout (`SUPER + SPACE` launcher, `SUPER + V` clipboard, `SUPER + TAB` overview, …) is in the same file, commented out, because it replaces Omarchy bindings.

Omarchy's panel hotkeys open the matching Ambxst surface: `SUPER + CTRL + W` Wi-Fi, `+ B` Bluetooth, `+ A` audio mixer (Ambxst settings), `+ P` power menu. `SUPER + SHIFT + SPACE` (`omarchy toggle bar`) unpins Ambxst's bar.

Every action is also an IPC call, for scripts and your own binds:

```bash
omarchy-shell ambxst run launcher     # or: ambxst run launcher
```

## How Omarchy powers it

Ambxst's QML is kept as upstream wrote it; the port changes the layer underneath. Upstream talks JSON-RPC to its Go daemon, so `modules/services/BackendService.qml` answers the same calls in process:

| Ambxst feature | On Omarchy |
|---|---|
| Windows, workspaces, monitors (`AxctlService`) | Hyprland's event socket (Quickshell.Hyprland) + `hyprctl -j`; actions as Hyprland Lua dispatchers (`hl.dsp.*`) |
| Workspace layouts | `omarchy-hyprland-workspace-layout-current` / `-toggle` (dwindle, scrolling, floating) |
| Colours | `OmarchyTheme`: the current theme's `colors.toml` → Ambxst's palette, re-generated when Omarchy pushes a new theme |
| Wallpapers tab | lists the Omarchy theme's backgrounds; picking one runs `omarchy-theme-bg-set` |
| Clipboard | Omarchy's clipboard history (`~/.local/state/omarchy/clipboard-history.json`); copy via `omarchy-clipboard-paste-*`; pins, aliases and order kept by Ambxst |
| Caffeine | `omarchy-toggle-idle stay-awake/allow-idle` |
| Night light | `omarchy-toggle-nightlight`, `hyprctl hyprsunset` |
| Power profiles | power-profiles-daemon (Quickshell UPower) |
| Screen recording | `omarchy-capture-screenrecording` (its marker file is the recording state) |
| Screenshots, OCR, QR, lens | grim + ImageMagick on the frozen frame, tesseract, zbar |
| Network | NetworkManager (`scripts/net.sh`, `nmcli monitor` for changes) |
| System metrics | `scripts/sysmon.sh`, only while the Metrics tab is open |
| Weather | open-meteo (`scripts/weather.sh`) |
| Lock | Omarchy's lock screen (`omarchy-system-lock`) |
| Power menu | Omarchy's system actions (`omarchy-system logout/reboot/shutdown`) |
| Notifications | Ambxst's daemon when `omarchy.notifications` is off; it answers the same `notifications` IPC so `omarchy toggle notification silencing` and `omarchy-notification-*` keep working |
| OSD | Ambxst's when `omarchy.osd` is off (brightness keys routed through Ambxst) |

## Configuration

Ambxst's own settings window (`SUPER + ALT + C`) works as upstream; its files live in `~/.config/ambxst/config/`.

Choices that only exist on Omarchy are in `~/.config/ambxst/omarchy.json` (applied live):

```json
{
  "colorSource": "omarchy",
  "ambxstWallpaper": false,
  "manageHyprland": false
}
```

- `colorSource`: `"omarchy"` follows the Omarchy theme; `"ambxst"` uses Ambxst's matugen/preset colours (and its GTK/terminal theme generators). Picking a colour preset or matugen scheme in Ambxst switches to `"ambxst"`.
- `ambxstWallpaper`: let Ambxst draw the wallpaper itself (video wallpapers, tint) instead of Omarchy's background.
- `manageHyprland`: let Ambxst apply its compositor settings (gaps, borders, rounding, blur, animations) live with `hyprctl eval`. Off by default: Omarchy's `looknfeel.lua` stays in charge.

## Not available on Omarchy (yet)

- **Ambxst lock screen** — Omarchy's lock is used; Ambxst's view is not wired into it yet.
- **Mods marketplace** — needs Ambxst's Go daemon; the Mods page reports it as unavailable.
- **Keybind editor** (Settings › Binds) — Omarchy owns Hyprland's bindings; use `keybinds.lua` / `~/.config/hypr/bindings.lua`.
- **Idle timeouts** (Settings › System › Idle) — Omarchy's idle service handles screensaver, lock and suspend.
- **Native compositor overview** (niri/mango) — Hyprland uses Ambxst's own overview.

## Troubleshooting

```bash
omarchy-restart-shell
journalctl --user -t omarchy-shell -n 200 | grep -iE "ambxst|error|warn"
```

A QML error makes Omarchy fall back to its own bar ("bar option ambxst.bar failed to load"); the log names the file. `ambxst disable` always gets you back to Omarchy's bar.

## Credits and license

[Ambxst](https://github.com/Axenide/Ambxst) is by [Axenide](https://github.com/Axenide) and contributors; this port keeps its UI and is released under the same **AGPL-3.0** ([LICENSE](LICENSE)). [Omarchy](https://github.com/omacom/omarchy) is by DHH and contributors (MIT). Bundled fonts: Phosphor Icons (MIT), Roboto Condensed and League Gothic (SIL OFL 1.1), licences in `assets/fonts/`.
