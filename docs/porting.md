# Porting notes

How this tree differs from upstream [Ambxst](https://github.com/Axenide/Ambxst), and how to bring in a new upstream release.

## Layout

The plugin root is the repository root: `manifest.json` and its entry point `Bar.qml` must stay there. `Bar.qml` is upstream's `shell.qml` turned into an Omarchy bar plugin (an `Item` the host injects `shell`, `manifest`, `barConfig`, … into, exposing `position`, `vertical`, `barSize`, `barHidden` and `summonBarWidget` / `hideBarWidget` / `isBarWidgetOpen` / `panelWidgetIdAt`).

`modules/`, `config/`, `assets/`, `translations/` are upstream's, with the changes below. Not shipped: `backend/` (Go daemon), `nix/`, `shell.qml`, upstream's installer, screenshots and example wallpapers.

## Mechanical changes

- **Imports.** Inside omarchy-shell, `qs.` resolves to Omarchy's shell directory, so every `import qs.modules.x` / `import qs.config` is rewritten to a relative directory import, and each QML directory gets a `qmldir` (singletons marked). `tools/port_imports.py <repo>` does both and is idempotent. `qs.Commons` (Omarchy's) is left alone.
- **Paths.** `Quickshell.cachePath/dataPath/statePath/cacheDir/shellDir` point at Omarchy's dirs in its shell, so they are pinned to Ambxst's own (`~/.cache/ambxst`, `~/.local/share/ambxst`, `~/.local/state/ambxst`) or made relative.
- **IPC functions** need typed returns (`: void`), or Quickshell drops the whole target.
- **Native dialogs** (`ColorDialog`, `FileDialog`) use `DontUseNativeDialog`: Omarchy runs Qt with the GTK3 platform theme, and a native dialog would load GTK inside the shell process.

## Omarchy layer

| File | Role |
|---|---|
| `modules/services/BackendService.qml` | Upstream's JSON-RPC client API (`call`, `notify`, `addSubscription`, …), answered in process by Omarchy commands, Quickshell services and `scripts/*` |
| `modules/services/AxctlService.qml` | Compositor model from Hyprland (events + `hyprctl -j`); dispatches as `hl.dsp.*` Lua |
| `modules/services/OmarchyBridge.qml` | Paths, `~/.config/ambxst/omarchy.json`, which Omarchy services are switched off |
| `modules/theme/OmarchyTheme.qml`, `OmarchyPalette.js` | Omarchy theme → `~/.cache/ambxst/colors.json` |
| `scripts/net.sh`, `sysmon.sh`, `weather.sh`, `thumbs.sh` | What the Go daemon did, where Omarchy has no command |
| `bin/ambxst` | The `ambxst` CLI, forwarding to `omarchy-shell ambxst …` |

Hand edits to upstream files are marked with an `Ambxst on Omarchy:` comment; `grep -rn "Ambxst on Omarchy" modules config` lists them.

## Syncing upstream

```bash
git clone --depth 1 https://github.com/Axenide/Ambxst /tmp/ambxst-upstream
# copy modules/ config/ assets/ translations/ version over this tree (keep the files in the table above),
# re-apply the marked hand edits, then:
tools/port_imports.py .
grep -rnE '"axctl"|"ambxst"|BackendService\.call\("[a-z]+\.' modules config   # new backend calls to answer?
omarchy plugin validate .
```

A new `BackendService.call("x.y")` upstream needs a handler in `BackendService.qml`'s `handlers` table; without one it gets the "not available on Omarchy" error, which consumers already handle.

## Checking a change

```bash
./install.sh --dev --yes           # link this checkout as the plugin
omarchy-restart-shell
journalctl --user -t omarchy-shell -n 200 | grep -iE "ambxst|error|warn"
omarchy-shell ambxst run dashboard
```
