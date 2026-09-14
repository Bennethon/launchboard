#!/usr/bin/env bash
# Remove LaunchBoard from Omarchy. User config is kept unless --purge.
set -euo pipefail

PROJECT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PLUGIN_ID="bennethon.launchboard"
PLUGIN_DST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${PLUGIN_ID}"
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

strip_launchboard_block() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  if ! awk -f "$PROJECT/scripts/strip-launchboard-block.awk" "$file" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$file"
}

remove_bind_hook() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if ! grep -q "BEGIN launchboard" "$file"; then
    return 0
  fi
  if ! grep -q "END launchboard" "$file"; then
    printf 'uninstall.sh: unbalanced LaunchBoard markers in %s; refusing to edit\n' "$file" >&2
    return 1
  fi
  cp -a "$file" "$file.bak.$(date +%s)"
  if ! strip_launchboard_block "$file"; then
    printf 'uninstall.sh: failed to strip LaunchBoard block from %s; original left in place\n' "$file" >&2
    return 1
  fi
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
fi

if [[ -L "$PLUGIN_DST" || -d "$PLUGIN_DST" ]]; then
  rm -rf "$PLUGIN_DST"
  say "==> Removed $PLUGIN_DST"
fi

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
