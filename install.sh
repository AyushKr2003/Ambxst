#!/bin/bash

# Atoll for Omarchy — installer.
#
# Puts the `atoll.bar` plugin into Omarchy's plugins folder, installs what
# Atoll needs that Omarchy doesn't ship (with Omarchy's own package
# helpers), and makes it Omarchy's bar. Everything it changes is recorded in
# ~/.local/state/atoll/omarchy-install.json so ./uninstall.sh puts it back.
#
#   ./install.sh [--yes] [--dev] [--dry-run]
#                [--no-packages] [--no-keybinds]
#                [--notifications|--no-notifications] [--osd|--no-osd] [--dock|--no-dock]
#
#   --yes             accept every default without asking
#   --dev             link the plugin to this checkout instead of copying it
#   --dry-run         print what would happen, change nothing
#   --no-packages     skip package installation
#   --no-keybinds     don't load keybinds.lua from ~/.config/hypr/bindings.lua
#   --[no-]notifications  Atoll is the notification daemon (default: yes)
#   --[no-]osd            Atoll draws the volume/brightness OSD (default: yes)
#   --[no-]dock           Atoll's dock replaces Omarchy's (default: yes)

set -euo pipefail

PLUGIN_ID="atoll.bar"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
DEST="$PLUGINS_DIR/$PLUGIN_ID"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/atoll"
STATE_FILE="$STATE_DIR/omarchy-install.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"
BIN_DIR="$HOME/.local/bin"
MARK_BEGIN="-- >>> atoll.bar keybinds (managed by Atoll's installer)"
MARK_END="-- <<< atoll.bar keybinds"

YES=false
DEV=false
DRY=false
PACKAGES=true
KEYBINDS=true
NOTIFICATIONS=""
OSD=""
DOCK=""

for arg in "$@"; do
  case $arg in
    --yes | -y) YES=true ;;
    --dev) DEV=true ;;
    --dry-run) DRY=true ;;
    --no-packages) PACKAGES=false ;;
    --no-keybinds) KEYBINDS=false ;;
    --notifications) NOTIFICATIONS=true ;;
    --no-notifications) NOTIFICATIONS=false ;;
    --osd) OSD=true ;;
    --no-osd) OSD=false ;;
    --dock) DOCK=true ;;
    --no-dock) DOCK=false ;;
    -h | --help)
      sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: unknown option $arg" >&2
      exit 2
      ;;
  esac
done

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31mxx\033[0m %s\n' "$*" >&2
  exit 1
}
run() {
  if [[ $DRY == "true" ]]; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}

# ask "Question" default(true|false) -> sets REPLY_BOOL
ask() {
  local question=$1 default=$2 hint answer
  if [[ $YES == "true" || ! -t 0 ]]; then
    REPLY_BOOL=$default
    return
  fi
  [[ $default == "true" ]] && hint="Y/n" || hint="y/N"
  read -r -p "   $question [$hint] " answer
  case ${answer,,} in
    y | yes) REPLY_BOOL=true ;;
    n | no) REPLY_BOOL=false ;;
    *) REPLY_BOOL=$default ;;
  esac
}

is_in() {
  jq -e --arg id "$1" 'index($id) != null' <<<"$2" >/dev/null
}

shell_running() {
  omarchy-shell shell ping >/dev/null 2>&1
}

# ------------------------------------------------------------------ checks

command -v omarchy-shell >/dev/null || die "Omarchy's shell (omarchy-shell) was not found. Atoll for Omarchy runs inside it."
command -v jq >/dev/null || die "jq is required."
[[ -f $SRC_DIR/manifest.json ]] || die "Run this from the Atoll checkout (manifest.json not found)."

say "Atoll for Omarchy $(jq -r .version "$SRC_DIR/manifest.json")"

# ---------------------------------------------------------------- packages
#
# Omarchy's base install already has grim, slurp, imagemagick, ffmpeg,
# tesseract (English), zbar, wl-clipboard, wtype, jq, curl, brightnessctl,
# ddcutil, hyprsunset, gpu-screen-recorder, power-profiles-daemon, tmux.
# Atoll's own fonts ship inside the plugin (assets/fonts).

OFFICIAL=(
  qt6-multimedia               # QtMultimedia: video wallpapers, sounds, media
  qt6-multimedia-gstreamer
  gst-plugins-bad
  qt6-imageformats             # webp/avif thumbnails
  qt6-svg
  ttf-nerd-fonts-symbols-mono  # "Symbols Nerd Font Mono" glyphs
  tesseract-data-spa           # Atoll's default OCR languages: eng + spa
  libnotify
)
OPTIONAL=(
  matugen                      # Atoll's own colour mode (colours from the wallpaper)
)

if [[ $PACKAGES == "true" ]]; then
  say "Installing packages Atoll needs (omarchy-pkg-add)"
  pkgs=()
  for entry in "${OFFICIAL[@]}"; do
    pkgs+=("${entry%% *}")
  done
  run omarchy-pkg-add "${pkgs[@]}" || warn "Some packages failed to install; Atoll may miss features."

  for pkg in "${OPTIONAL[@]}"; do
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      ask "Install $pkg (optional: colours from the wallpaper instead of the Omarchy theme)?" true
      if [[ $REPLY_BOOL == "true" ]]; then
        run omarchy-pkg-add "$pkg" 2>/dev/null || run omarchy-pkg-aur-add "$pkg" || warn "Could not install $pkg"
      fi
    fi
  done
fi

# ---------------------------------------------------------------- plugin

say "Installing the plugin into $DEST"
run mkdir -p "$PLUGINS_DIR" "$STATE_DIR" "$BIN_DIR"

if [[ -e $DEST || -L $DEST ]]; then
  if [[ -L $DEST ]]; then
    run rm -f "$DEST"
  else
    # Keep nothing but the plugin itself: settings live in ~/.config/atoll.
    run rm -rf "$DEST"
  fi
fi

if [[ $DEV == "true" ]]; then
  run ln -s "$SRC_DIR" "$DEST"
else
  run mkdir -p "$DEST"
  if [[ $DRY == "false" ]]; then
    tar -C "$SRC_DIR" --exclude=.git --exclude=.github -cf - . | tar -C "$DEST" -xf -
  fi
fi

if [[ $DRY == "false" ]] && command -v omarchy-plugin-validate >/dev/null; then
  omarchy-plugin-validate "$DEST" >/dev/null || die "Omarchy rejected the plugin (omarchy plugin validate $DEST)."
fi

# The `atoll` command (forwards to the shell; see bin/atoll).
if [[ -e $BIN_DIR/atoll ]] && ! grep -q "Atoll for Omarchy" "$BIN_DIR/atoll" 2>/dev/null; then
  warn "$BIN_DIR/atoll exists and is not ours; leaving it alone."
else
  run install -m 755 "$SRC_DIR/bin/atoll" "$BIN_DIR/atoll"
fi

# ---------------------------------------------------------------- state

prior_bar="omarchy.bar"
prior_disabled="[]"
if [[ -f $SHELL_JSON ]]; then
  prior_bar=$(jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON" 2>/dev/null || echo omarchy.bar)
  prior_disabled=$(jq -c '.disabledPlugins // []' "$SHELL_JSON" 2>/dev/null || echo "[]")
fi
# A reinstall keeps the state of the first install: the bar from before,
# and which Omarchy services were Atoll's doing (they look "already off"
# now, but they are still Atoll's to turn back on).
previously_ours="[]"
if [[ -f $STATE_FILE ]]; then
  prior_bar=$(jq -r '.priorBar // "omarchy.bar"' "$STATE_FILE")
  previously_ours=$(jq -c '.disabledByAtoll // []' "$STATE_FILE")
  # An update (`atoll update`, or a rerun without flags) keeps the earlier answers.
  [[ -z $NOTIFICATIONS ]] && NOTIFICATIONS=$(jq -r '.choices.notifications | values' "$STATE_FILE")
  [[ -z $OSD ]] && OSD=$(jq -r '.choices.osd | values' "$STATE_FILE")
  [[ -z $DOCK ]] && DOCK=$(jq -r '.choices.dock | values' "$STATE_FILE")
  [[ $(jq -r '.keybinds' "$STATE_FILE") == "false" ]] && KEYBINDS=false
fi
[[ $prior_bar == "$PLUGIN_ID" ]] && prior_bar="omarchy.bar"

disabled_by_us=()

disable_plugin() {
  local id=$1
  if is_in "$id" "$prior_disabled" && ! is_in "$id" "$previously_ours"; then
    return # already off before Atoll; not ours to turn back on
  fi
  disabled_by_us+=("$id")
  if shell_running; then
    run omarchy plugin disable "$id" >/dev/null || warn "could not disable $id"
  elif [[ $DRY == "false" ]]; then
    mkdir -p "$(dirname "$SHELL_JSON")"
    [[ -f $SHELL_JSON ]] || echo '{"version": 1}' >"$SHELL_JSON"
    tmp=$(mktemp)
    jq --arg id "$id" '.disabledPlugins = ((.disabledPlugins // []) + [$id] | unique)' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
  fi
}

# ------------------------------------------------------- handovers

say "Choosing what Atoll takes over from Omarchy"

if [[ -z $NOTIFICATIONS ]]; then
  ask "Use Atoll's notifications (notch, history, popups) instead of Omarchy's?" true
  NOTIFICATIONS=$REPLY_BOOL
fi
[[ $NOTIFICATIONS == "true" ]] && disable_plugin omarchy.notifications

if [[ -z $OSD ]]; then
  ask "Use Atoll's volume/brightness OSD instead of Omarchy's?" true
  OSD=$REPLY_BOOL
fi
[[ $OSD == "true" ]] && disable_plugin omarchy.osd

if [[ -z $DOCK ]]; then
  ask "Use Atoll's dock instead of Omarchy's floating-workspace dock?" true
  DOCK=$REPLY_BOOL
fi
[[ $DOCK == "true" ]] && disable_plugin omarchy.dock

# A reinstall that no longer hands a service to Atoll gives it back.
for id in $(jq -r '.[]' <<<"$previously_ours"); do
  is_in "$id" "$(printf '%s\n' "${disabled_by_us[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" && continue
  if shell_running; then
    run omarchy plugin enable "$id" >/dev/null || warn "could not enable $id"
  elif [[ $DRY == "false" && -f $SHELL_JSON ]]; then
    tmp=$(mktemp)
    jq --arg id "$id" '.disabledPlugins = ((.disabledPlugins // []) - [$id])' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
  fi
done

# ------------------------------------------------------------- keybinds

keybinds_added=false
if [[ $KEYBINDS == "true" ]]; then
  ask "Add Atoll's keybindings (SUPER+R launcher, SUPER+D dashboard, ...) to $BINDINGS?" true
  if [[ $REPLY_BOOL == "true" ]]; then
    if [[ $DRY == "true" ]]; then
      echo "   would append the Atoll keybinds block to $BINDINGS"
      keybinds_added=true
    else
      mkdir -p "$(dirname "$BINDINGS")"
      # Replace an earlier block, so its contents follow this run's choices.
      if [[ -f $BINDINGS ]] && grep -qF -- "$MARK_BEGIN" "$BINDINGS"; then
        tmp=$(mktemp)
        awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
          $0 == b { skip = 1; next }
          $0 == e { skip = 0; next }
          !skip' "$BINDINGS" >"$tmp" && cat "$tmp" >"$BINDINGS" && rm -f "$tmp"
        # Drop the blank line the earlier block was appended after.
        sed -i -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' "$BINDINGS"
      fi
      {
        echo ""
        echo "$MARK_BEGIN"
        echo 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/atoll.bar/keybinds.lua")'
        if [[ $OSD == "true" ]]; then
          echo 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/atoll.bar/keybinds-osd.lua")'
        fi
        echo "$MARK_END"
      } >>"$BINDINGS"
      keybinds_added=true
    fi
  fi
fi

# --------------------------------------------------------------- record

if [[ $DRY == "false" ]]; then
  jq -n --arg bar "$prior_bar" --argjson keybinds "$keybinds_added" --argjson dev "$DEV" \
    --argjson n "$NOTIFICATIONS" --argjson o "$OSD" --argjson d "$DOCK" \
    --args '{priorBar: $bar, disabledByAtoll: $ARGS.positional, keybinds: $keybinds, dev: $dev,
      choices: {notifications: $n, osd: $o, dock: $d},
      installedAt: (now | todate)}' "${disabled_by_us[@]}" >"$STATE_FILE"
fi

# ------------------------------------------------------------- activate

say "Making Atoll Omarchy's bar"
if shell_running; then
  run omarchy-shell -q shell rescanPlugins || true
fi
run omarchy bar use "$PLUGIN_ID" >/dev/null || warn "Could not select the bar; run: omarchy bar use $PLUGIN_ID"
if [[ $keybinds_added == "true" ]] && command -v hyprctl >/dev/null; then
  run hyprctl reload >/dev/null 2>&1 || true
fi

cat <<EOF

  Atoll is installed.

    atoll run launcher       open the launcher (SUPER+R)
    atoll run dashboard      open the dashboard (SUPER+D)
    atoll disable            go back to Omarchy's bar
    ./uninstall.sh            remove Atoll and restore what it changed

  Settings: Atoll's own (SUPER+ALT+C) in ~/.config/atoll/config,
  plus Omarchy-specific choices in ~/.config/atoll/omarchy.json.
  If the bar doesn't appear: omarchy-restart-shell, then check the log with
    journalctl --user -t omarchy-shell -n 100 | grep -iE "atoll|error"

EOF
