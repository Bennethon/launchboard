#!/usr/bin/env bash
# Remove LaunchBoard from Omarchy. User config is kept unless --purge.
set -euo pipefail

PROJECT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PLUGIN_ID="bennethon.launchboard"
LEGACY_PLUGIN_ID="ben.launchboard"
PLUGIN_DST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
LEGACY_DST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${LEGACY_PLUGIN_ID}"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/launchboard"
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
KEEP_BIND=0
PURGE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--keep-bind] [--purge]

  Removes the LaunchBoard plugin from Omarchy.

  If you opted into the Super+Alt+Space shadow, it is removed
  automatically. Hyprland then reloads Omarchy's packaged Apps-menu
  bind — nothing is rewritten into /usr/share/omarchy.

  --keep-bind   Leave the Hyprland pcall hook in bindings.lua
  --purge       Also delete ~/.config/launchboard/
  --unbind      Deprecated alias; the shadow is already removed by default
EOF
}

say() { printf '%s\n' "$*"; }

remove_bind_hook() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if ! grep -q "BEGIN launchboard" "$file"; then
    return 0
  fi
  cp -a "$file" "$file.bak.$(date +%s)"
  local tmp
  tmp="$(mktemp)"
  awk '
    /BEGIN launchboard/ {skip=1; next}
    /END launchboard/ {skip=0; next}
    !skip {print}
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  say "==> Removed LaunchBoard Hyprland shadow from $file"
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
    if hyprctl configerrors 2>/dev/null | grep -vq '^$'; then
      say "==> hyprctl configerrors:"
      hyprctl configerrors || true
    fi
  fi
}

for arg in "$@"; do
  case "$arg" in
    --keep-bind) KEEP_BIND=1 ;;
    --purge) PURGE=1 ;;
    --unbind) ;; # default behavior
    -h|--help) usage; exit 0 ;;
    *) printf 'uninstall.sh: unknown option: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  omarchy plugin disable "$LEGACY_PLUGIN_ID" >/dev/null 2>&1 || true
fi

for dst in "$PLUGIN_DST" "$LEGACY_DST"; do
  if [[ -L "$dst" || -d "$dst" ]]; then
    rm -rf "$dst"
    say "==> Removed $dst"
  fi
done

rm -f "$APPS_DIR/launchboard.desktop" "$ICONS_DIR/launchboard.svg"
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

if [[ "$KEEP_BIND" -eq 0 ]]; then
  if [[ -f "$BINDINGS" ]] && grep -q "BEGIN launchboard" "$BINDINGS"; then
    remove_bind_hook "$BINDINGS"
    say "==> SUPER+ALT+SPACE is the packaged Apps menu again after Hyprland reload"
  fi
fi

if [[ "$PURGE" -eq 1 && -d "$CONFIG_DST" ]]; then
  rm -rf "$CONFIG_DST"
  say "==> Deleted $CONFIG_DST"
else
  say "==> Kept $CONFIG_DST"
fi

say "LaunchBoard removed."
