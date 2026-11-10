<h1 align="center">Atoll</h1>

<p align="center">A desktop shell for <a href="https://omarchy.org">Omarchy</a>: one bar, a notch that grows into everything, and a dock, drawn as a single shape around your windows.<br>Based on <a href="https://github.com/Axenide/Ambxst">Ambxst</a> by Axenide.</p>

---

An atoll is a ring of land around a calm lagoon. Atoll frames your workspace the same way: the bar, the notch (a dynamic island) and the dock are one panel, and the notch grows in place into the launcher, dashboard, notifications and power menu. It runs **inside Omarchy's own shell** as one bar plugin (`atoll.bar`), with Omarchy as the engine.

- No second Quickshell, no Go daemon: it runs in the `omarchy-shell` process Omarchy already starts.
- Omarchy first: data and actions come from Omarchy's commands and state (theme, background, clipboard history, night light, stay-awake, screen recording, lock, power menu, workspace layouts). Base Omarchy packages fill the rest (NetworkManager, grim, ImageMagick, tesseract, zbar, wl-clipboard).
- Colours follow your Omarchy theme live (`omarchy theme set`), or Atoll's own matugen/preset colours if you choose.

## Install

Requires Omarchy with its shell running.

```bash
git clone https://github.com/AyushKr2003/Ambxst.git atoll
cd atoll
./install.sh
```

The installer:

1. installs what Atoll needs that Omarchy doesn't ship, with `omarchy-pkg-add` (`qt6-multimedia`, gstreamer plugins, Nerd Font symbols, Spanish OCR data; `matugen` optional). Atoll's fonts (Phosphor icons, Roboto Condensed, League Gothic) are bundled in `assets/fonts`;
2. copies the plugin to `~/.config/omarchy/plugins/atoll.bar` (validated with `omarchy plugin validate`) and puts an `atoll` command in `~/.local/bin`;
3. asks which Omarchy services Atoll should take over — notifications, OSD, dock — and switches those off with `omarchy plugin disable`;
4. optionally loads `keybinds.lua` from `~/.config/hypr/bindings.lua`;
5. selects Atoll as the bar: `omarchy bar use atoll.bar`.

Everything it changes is recorded in `~/.local/state/atoll/omarchy-install.json`.

| Command | Purpose |
|---|---|
| `./install.sh --yes` | Install with every default |
| `./install.sh --dev` | Link the plugin to this checkout (edits reload live) |
| `./install.sh --dry-run` | Show what would happen |
| `./install.sh --no-notifications --no-osd --no-dock` | Keep Omarchy's own services |
| `./uninstall.sh` | Restore the previous bar, services and keybinds |
| `./uninstall.sh --purge` | …and delete Atoll's settings and caches |
| `atoll disable` / `atoll enable` | Switch between Omarchy's bar and Atoll |
| `atoll status` | Show whether it is installed and active |

Update: `atoll update`, or `git pull && ./install.sh` in your checkout. Settings and your earlier choices are kept.

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
| `SUPER + ALT + C` | Atoll settings |

Upstream Ambxst's own layout (`SUPER + SPACE` launcher, `SUPER + V` clipboard, `SUPER + TAB` overview, …) is in the same file, commented out, because it replaces Omarchy bindings.

Omarchy's panel hotkeys open the matching Atoll surface: `SUPER + CTRL + W` Wi-Fi, `+ B` Bluetooth, `+ A` audio mixer (Atoll settings), `+ P` power menu. `SUPER + SHIFT + SPACE` (`omarchy toggle bar`) unpins Atoll's bar.

Every action is also an IPC call, for scripts and your own binds:

```bash
omarchy-shell atoll run launcher     # or: atoll run launcher
```

## How Omarchy powers it

Atoll's QML is kept as upstream wrote it; the port changes the layer underneath. Upstream talks JSON-RPC to its Go daemon, so `modules/services/BackendService.qml` answers the same calls in process:

| Atoll feature | On Omarchy |
|---|---|
| Windows, workspaces, monitors (`AxctlService`) | Hyprland's event socket (Quickshell.Hyprland) + `hyprctl -j`; actions as Hyprland Lua dispatchers (`hl.dsp.*`) |
| Workspace layouts | `omarchy-hyprland-workspace-layout-current` / `-toggle` (dwindle, scrolling, floating) |
| Colours | `OmarchyTheme`: the current theme's `colors.toml` → Atoll's palette, re-generated when Omarchy pushes a new theme |
| Wallpapers tab | lists the Omarchy theme's backgrounds; picking one runs `omarchy-theme-bg-set` |
| Clipboard | Omarchy's clipboard history (`~/.local/state/omarchy/clipboard-history.json`); copy via `omarchy-clipboard-paste-*`; pins, aliases and order kept by Atoll |
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
| Notifications | Atoll's daemon when `omarchy.notifications` is off; it answers the same `notifications` IPC so `omarchy toggle notification silencing` and `omarchy-notification-*` keep working |
| OSD | Atoll's when `omarchy.osd` is off (brightness keys routed through Atoll) |

## Configuration

Atoll's own settings window (`SUPER + ALT + C`) works as upstream; its files live in `~/.config/atoll/config/`.

Choices that only exist on Omarchy are in `~/.config/atoll/omarchy.json` (applied live):

```json
{
  "colorSource": "omarchy",
  "ownWallpaper": false,
  "manageHyprland": false
}
```

- `colorSource`: `"omarchy"` follows the Omarchy theme; `"atoll"` uses Atoll's own matugen/preset colours (and its GTK/terminal theme generators), as upstream Ambxst does. Picking a colour preset or matugen scheme in Atoll switches to `"atoll"`.
- `ownWallpaper`: let Atoll draw the wallpaper itself (video wallpapers, tint) instead of Omarchy's background.
- `manageHyprland`: let Atoll apply its compositor settings (gaps, borders, rounding, blur, animations) live with `hyprctl eval`. Off by default: Omarchy's `looknfeel.lua` stays in charge.

## Not available on Omarchy (yet)

- **Atoll lock screen** — Omarchy's lock is used; Atoll's view is not wired into it yet.
- **Mods marketplace** — needs Ambxst's Go daemon; the Mods page reports it as unavailable.
- **Keybind editor** (Settings › Binds) — Omarchy owns Hyprland's bindings; use `keybinds.lua` / `~/.config/hypr/bindings.lua`.
- **Idle timeouts** (Settings › System › Idle) — Omarchy's idle service handles screensaver, lock and suspend.
- **Native compositor overview** (niri/mango) — Hyprland uses Atoll's own overview.

## Troubleshooting

```bash
omarchy-restart-shell
journalctl --user -t omarchy-shell -n 200 | grep -iE "atoll|error|warn"
```

A QML error makes Omarchy fall back to its own bar ("bar option atoll.bar failed to load"); the log names the file. `atoll disable` always gets you back to Omarchy's bar.

## Credits and license

Atoll is a fork of Ambxst adapted to Omarchy.

[Ambxst](https://github.com/Axenide/Ambxst) is by [Axenide](https://github.com/Axenide) and contributors; Atoll keeps its UI and is released under the same **AGPL-3.0** ([LICENSE](LICENSE)). [Omarchy](https://github.com/omacom/omarchy) is by DHH and contributors (MIT). Bundled fonts: Phosphor Icons (MIT), Roboto Condensed and League Gothic (SIL OFL 1.1), licences in `assets/fonts/`.
