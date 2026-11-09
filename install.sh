#!/bin/bash

# Ambxst for Omarchy — installer.
#
# Puts the `ambxst.bar` plugin into Omarchy's plugins folder, installs what
# Ambxst needs that Omarchy doesn't ship (with Omarchy's own package
# helpers), and makes it Omarchy's bar. Everything it changes is recorded in
# ~/.local/state/ambxst/omarchy-install.json so ./uninstall.sh puts it back.
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
#   --[no-]notifications  Ambxst is the notification daemon (default: yes)
#   --[no-]osd            Ambxst draws the volume/brightness OSD (default: yes)
#   --[no-]dock           Ambxst's dock replaces Omarchy's (default: yes)

set -euo pipefail

PLUGIN_ID="ambxst.bar"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
DEST="$PLUGINS_DIR/$PLUGIN_ID"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ambxst"
STATE_FILE="$STATE_DIR/omarchy-install.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"
BIN_DIR="$HOME/.local/bin"
MARK_BEGIN="-- >>> ambxst.bar keybinds (managed by Ambxst's installer)"
MARK_END="-- <<< ambxst.bar keybinds"

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

shell_running() {
  omarchy-shell shell ping >/dev/null 2>&1
}

# ------------------------------------------------------------------ checks

command -v omarchy-shell >/dev/null || die "Omarchy's shell (omarchy-shell) was not found. Ambxst for Omarchy runs inside it."
command -v jq >/dev/null || die "jq is required."
[[ -f $SRC_DIR/manifest.json ]] || die "Run this from the Ambxst checkout (manifest.json not found)."

say "Ambxst for Omarchy $(jq -r .version "$SRC_DIR/manifest.json")"

# ---------------------------------------------------------------- packages
#
# Omarchy's base install already has grim, slurp, imagemagick, ffmpeg,
# tesseract (English), zbar, wl-clipboard, wtype, jq, curl, brightnessctl,
# ddcutil, hyprsunset, gpu-screen-recorder, power-profiles-daemon, tmux.
# Ambxst's own fonts ship inside the plugin (assets/fonts).

OFFICIAL=(
  qt6-multimedia               # QtMultimedia: video wallpapers, sounds, media
  qt6-multimedia-gstreamer
  gst-plugins-bad
  qt6-imageformats             # webp/avif thumbnails
  qt6-svg
  ttf-nerd-fonts-symbols-mono  # "Symbols Nerd Font Mono" glyphs
  tesseract-data-spa           # Ambxst's default OCR languages: eng + spa
  libnotify
)
OPTIONAL=(
  matugen                      # Ambxst's own colour mode (colours from the wallpaper)
)

if [[ $PACKAGES == "true" ]]; then
  say "Installing packages Ambxst needs (omarchy-pkg-add)"
  pkgs=()
  for entry in "${OFFICIAL[@]}"; do
    pkgs+=("${entry%% *}")
  done
  run omarchy-pkg-add "${pkgs[@]}" || warn "Some packages failed to install; Ambxst may miss features."

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
    # Keep nothing but the plugin itself: settings live in ~/.config/ambxst.
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

# The `ambxst` command (forwards to the shell; see bin/ambxst).
if [[ -e $BIN_DIR/ambxst ]] && ! grep -q "Ambxst for Omarchy" "$BIN_DIR/ambxst" 2>/dev/null; then
  warn "$BIN_DIR/ambxst exists and is not ours; leaving it alone."
else
  run install -m 755 "$SRC_DIR/bin/ambxst" "$BIN_DIR/ambxst"
fi

# ---------------------------------------------------------------- state

prior_bar="omarchy.bar"
prior_disabled="[]"
if [[ -f $SHELL_JSON ]]; then
  prior_bar=$(jq -r '.bar.id // "omarchy.bar"' "$SHELL_JSON" 2>/dev/null || echo omarchy.bar)
  prior_disabled=$(jq -c '.disabledPlugins // []' "$SHELL_JSON" 2>/dev/null || echo "[]")
fi
# A reinstall keeps the state of the first install: the bar from before,
# and which Omarchy services were Ambxst's doing (they look "already off"
# now, but they are still Ambxst's to turn back on).
previously_ours="[]"
if [[ -f $STATE_FILE ]]; then
  prior_bar=$(jq -r '.priorBar // "omarchy.bar"' "$STATE_FILE")
  previously_ours=$(jq -c '.disabledByAmbxst // []' "$STATE_FILE")
fi
[[ $prior_bar == "$PLUGIN_ID" ]] && prior_bar="omarchy.bar"

disabled_by_us=()

is_in() {
  jq -e --arg id "$1" 'index($id) != null' <<<"$2" >/dev/null
}

disable_plugin() {
  local id=$1
  if is_in "$id" "$prior_disabled" && ! is_in "$id" "$previously_ours"; then
    return # already off before Ambxst; not ours to turn back on
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

say "Choosing what Ambxst takes over from Omarchy"

if [[ -z $NOTIFICATIONS ]]; then
  ask "Use Ambxst's notifications (notch, history, popups) instead of Omarchy's?" true
  NOTIFICATIONS=$REPLY_BOOL
fi
[[ $NOTIFICATIONS == "true" ]] && disable_plugin omarchy.notifications

if [[ -z $OSD ]]; then
  ask "Use Ambxst's volume/brightness OSD instead of Omarchy's?" true
  OSD=$REPLY_BOOL
fi
[[ $OSD == "true" ]] && disable_plugin omarchy.osd

if [[ -z $DOCK ]]; then
  ask "Use Ambxst's dock instead of Omarchy's floating-workspace dock?" true
  DOCK=$REPLY_BOOL
fi
[[ $DOCK == "true" ]] && disable_plugin omarchy.dock

# A reinstall that no longer hands a service to Ambxst gives it back.
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
  ask "Add Ambxst's keybindings (SUPER+R launcher, SUPER+D dashboard, ...) to $BINDINGS?" true
  if [[ $REPLY_BOOL == "true" ]]; then
    if [[ $DRY == "true" ]]; then
      echo "   would append the Ambxst keybinds block to $BINDINGS"
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
        echo 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/ambxst.bar/keybinds.lua")'
        if [[ $OSD == "true" ]]; then
          echo 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/ambxst.bar/keybinds-osd.lua")'
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
    --args '{priorBar: $bar, disabledByAmbxst: $ARGS.positional, keybinds: $keybinds, dev: $dev,
      installedAt: (now | todate)}' "${disabled_by_us[@]}" >"$STATE_FILE"
fi

# ------------------------------------------------------------- activate

say "Making Ambxst Omarchy's bar"
if shell_running; then
  run omarchy-shell -q shell rescanPlugins || true
fi
run omarchy bar use "$PLUGIN_ID" >/dev/null || warn "Could not select the bar; run: omarchy bar use $PLUGIN_ID"
if [[ $keybinds_added == "true" ]] && command -v hyprctl >/dev/null; then
  run hyprctl reload >/dev/null 2>&1 || true
fi

cat <<EOF

  Ambxst is installed.

    ambxst run launcher       open the launcher (SUPER+R)
    ambxst run dashboard      open the dashboard (SUPER+D)
    ambxst disable            go back to Omarchy's bar
    ./uninstall.sh            remove Ambxst and restore what it changed

  Settings: Ambxst's own (SUPER+ALT+C) in ~/.config/ambxst/config,
  plus Omarchy-specific choices in ~/.config/ambxst/omarchy.json.
  If the bar doesn't appear: omarchy-restart-shell, then check the log with
    journalctl --user -t omarchy-shell -n 100 | grep -iE "ambxst|error"

EOF
