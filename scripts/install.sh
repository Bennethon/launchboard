#!/usr/bin/env bash
# Install LaunchBoard into the current Omarchy session.
set -euo pipefail

PROJECT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PLUGIN_ID="bennethon.launchboard"
LEGACY_PLUGIN_ID="ben.launchboard"
PLUGIN_DST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
LEGACY_DST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${LEGACY_PLUGIN_ID}"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/launchboard"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"

usage() {
  cat <<EOF
Usage: $(basename "$0")

  Development / local install. Symlinks this checkout into
  ~/.config/omarchy/plugins/${PLUGIN_ID} and enables the plugin.

  Does not change Hyprland keybindings. To opt in to Super+Alt+Space:
    $(dirname "$(readlink -f "$0")")/install-binding.sh
EOF
}

say() { printf '%s\n' "$*"; }
fail() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $arg" ;;
  esac
done

command -v omarchy >/dev/null 2>&1 || fail "omarchy CLI is not on PATH"
[[ -f "$PROJECT/manifest.json" ]] || fail "manifest.json missing"
[[ -f "$PROJECT/qml/Launcher.qml" ]] || fail "qml/Launcher.qml missing"

mkdir -p "$(dirname "$PLUGIN_DST")" "$CONFIG_DST" "$APPS_DIR" "$ICONS_DIR"

if [[ -e "$LEGACY_DST" ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "$LEGACY_PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$LEGACY_DST"
  say "==> Removed legacy $LEGACY_DST"
fi

if [[ -e "$PLUGIN_DST" && ! -L "$PLUGIN_DST" && -d "$PLUGIN_DST/.git" ]]; then
  fail "$PLUGIN_DST is a git checkout; refuse to replace it. Remove it first."
fi

rm -rf "$PLUGIN_DST"
ln -sfn "$PROJECT" "$PLUGIN_DST"
say "==> Symlinked $PLUGIN_DST -> $PROJECT"

if [[ ! -f "$CONFIG_DST/config.json" ]]; then
  printf '%s\n' '{
  "version": 1,
  "layout": "stack",
  "sections": [],
  "hiddenApps": []
}' > "$CONFIG_DST/config.json"
  say "==> Wrote first-run $CONFIG_DST/config.json"
fi

install -m 644 "$PROJECT/share/icons/launchboard.svg" "$ICONS_DIR/launchboard.svg"
sed "s|^Icon=.*|Icon=$ICONS_DIR/launchboard.svg|" \
  "$PROJECT/share/applications/launchboard.desktop" > "$APPS_DIR/launchboard.desktop"
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
say "==> Installed launcher entry (NoDisplay=true)"

if omarchy plugin validate "$PROJECT" >/dev/null 2>&1; then
  say "==> Plugin manifest validated"
else
  omarchy plugin validate "$PROJECT" || true
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

enabled=0
for _ in $(seq 1 30); do
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" >/dev/null && enabled=1 && break
  fi
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  sleep 0.15
done

if [[ "$enabled" -eq 1 ]]; then
  say "==> Enabled $PLUGIN_ID"
else
  say "==> Plugin discovered but not yet enabled. Run: omarchy plugin enable $PLUGIN_ID"
fi

say ""
say "LaunchBoard is installed."
say "  Plugin:  $PLUGIN_DST"
say "  Source:  $PROJECT"
say "  Config:  $CONFIG_DST/config.json"
say ""
say "Open it with:"
say "  omarchy-shell shell toggle $PLUGIN_ID"
say ""
say "Keybindings are unchanged. To optionally shadow SUPER+ALT+SPACE:"
say "  $PROJECT/scripts/install-binding.sh"
