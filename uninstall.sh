#!/bin/bash

# Ambxst for Omarchy — uninstaller.
#
# Restores what install.sh changed, from its record in
# ~/.local/state/ambxst/omarchy-install.json: the bar that was in use, the
# Omarchy services Ambxst took over, the keybinds block in bindings.lua,
# the `ambxst` command and the plugin folder. Ambxst's settings
# (~/.config/ambxst) are kept unless --purge is given.
#
#   ./uninstall.sh [--purge] [--dry-run]

set -euo pipefail

PLUGIN_ID="ambxst.bar"
DEST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ambxst"
STATE_FILE="$STATE_DIR/omarchy-install.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
BINDINGS="$HOME/.config/hypr/bindings.lua"
BIN="$HOME/.local/bin/ambxst"
MARK_BEGIN="-- >>> ambxst.bar keybinds (managed by Ambxst's installer)"
MARK_END="-- <<< ambxst.bar keybinds"

PURGE=false
DRY=false
for arg in "$@"; do
  case $arg in
    --purge) PURGE=true ;;
    --dry-run) DRY=true ;;
    -h | --help)
      sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "uninstall.sh: unknown option $arg" >&2
      exit 2
      ;;
  esac
done

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
run() {
  if [[ $DRY == "true" ]]; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}
shell_running() {
  omarchy-shell shell ping >/dev/null 2>&1
}

prior_bar="omarchy.bar"
disabled=()
if [[ -f $STATE_FILE ]]; then
  prior_bar=$(jq -r '.priorBar // "omarchy.bar"' "$STATE_FILE")
  mapfile -t disabled < <(jq -r '.disabledByAmbxst[]?' "$STATE_FILE")
else
  warn "No install record at $STATE_FILE; restoring Omarchy's defaults."
fi

say "Restoring the bar ($prior_bar)"
if [[ $prior_bar == "omarchy.bar" || $prior_bar == "$PLUGIN_ID" ]]; then
  run omarchy bar reset >/dev/null || warn "could not reset the bar; run: omarchy bar reset"
else
  run omarchy bar use "$prior_bar" >/dev/null || run omarchy bar reset >/dev/null || true
fi

for id in "${disabled[@]}"; do
  say "Turning Omarchy's $id back on"
  if shell_running; then
    run omarchy plugin enable "$id" >/dev/null || warn "could not enable $id"
  elif [[ $DRY == "false" && -f $SHELL_JSON ]]; then
    tmp=$(mktemp)
    jq --arg id "$id" '.disabledPlugins = ((.disabledPlugins // []) - [$id])' "$SHELL_JSON" >"$tmp" && mv "$tmp" "$SHELL_JSON"
  fi
done

if [[ -f $BINDINGS ]] && grep -qF -- "$MARK_BEGIN" "$BINDINGS"; then
  say "Removing Ambxst's keybinds from $BINDINGS"
  if [[ $DRY == "false" ]]; then
    tmp=$(mktemp)
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      !skip' "$BINDINGS" >"$tmp" && cat "$tmp" >"$BINDINGS" && rm -f "$tmp"
    sed -i -e ':a' -e '/^\n*$/{$d;N;ba' -e '}' "$BINDINGS"
    command -v hyprctl >/dev/null && hyprctl reload >/dev/null 2>&1 || true
  fi
fi

if [[ -f $BIN ]] && grep -q "Ambxst for Omarchy" "$BIN"; then
  run rm -f "$BIN"
fi

say "Removing the plugin"
if [[ -L $DEST ]]; then
  run rm -f "$DEST"
elif [[ -d $DEST ]]; then
  run rm -rf "$DEST"
fi
if shell_running; then
  run omarchy-shell -q shell rescanPlugins || true
fi

run rm -f "$STATE_FILE"

if [[ $PURGE == "true" ]]; then
  say "Removing Ambxst's settings and caches"
  run rm -rf "$HOME/.config/ambxst" "$HOME/.cache/ambxst" "$STATE_DIR" "${XDG_DATA_HOME:-$HOME/.local/share}/ambxst"
fi

say "Ambxst is uninstalled."
