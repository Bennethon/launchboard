#!/usr/bin/env bash
# Opt-in Super+Alt+Space shadow for LaunchBoard.
# Standard `omarchy plugin add` / install.sh does not run this.
set -euo pipefail

PROJECT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PLUGIN_ID="bennethon.launchboard"
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
REMOVE=0

HOOK_BEGIN="-- BEGIN launchboard"
HOOK_BLOCK="$(cat <<'EOF'
-- BEGIN launchboard
-- Shadow SUPER+ALT+SPACE while LaunchBoard is installed. The packaged
-- Omarchy Apps-menu bind is unchanged; pcall no-ops if this file is gone.
pcall(dofile, (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/omarchy/plugins/bennethon.launchboard/hypr/bindings.lua")
-- END launchboard
EOF
)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--remove]

  Explicitly opt in to shadowing SUPER+ALT+SPACE with LaunchBoard.
  This writes one reversible block to ~/.config/hypr/bindings.lua.
  Plugin installation does not do this on its own.

  --remove   Delete the LaunchBoard block and reload Hyprland
EOF
}

say() { printf '%s\n' "$*"; }
fail() { printf 'install-binding.sh: %s\n' "$*" >&2; exit 1; }

reload_hypr() {
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
    if hyprctl configerrors 2>/dev/null | grep -vq '^$'; then
      say "==> hyprctl configerrors:"
      hyprctl configerrors || true
    fi
  fi
}

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
    say "==> No LaunchBoard block in $file"
    return 0
  fi
  if ! grep -q "END launchboard" "$file"; then
    fail "unbalanced LaunchBoard markers in $file; refusing to edit"
  fi
  cp -a "$file" "$file.bak.$(date +%s)"
  if ! strip_launchboard_block "$file"; then
    fail "failed to strip LaunchBoard block from $file; original left in place"
  fi
  say "==> Removed LaunchBoard Hyprland shadow from $file"
  reload_hypr
}

for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $arg" ;;
  esac
done

if [[ "$REMOVE" -eq 1 ]]; then
  remove_bind_hook "$BINDINGS"
  say "==> SUPER+ALT+SPACE is the packaged Apps menu again after Hyprland reload"
  exit 0
fi

[[ -f "$PROJECT/hypr/bindings.lua" ]] || fail "hypr/bindings.lua missing"

mkdir -p "$(dirname "$BINDINGS")"
[[ -f "$BINDINGS" ]] || printf '%s\n' "-- Keep only your personal keybinding overrides here." > "$BINDINGS"

need_bind=0
if ! grep -q -- "$HOOK_BEGIN" "$BINDINGS"; then
  need_bind=1
elif ! grep -q -- "plugins/${PLUGIN_ID}/" "$BINDINGS"; then
  need_bind=1
  if ! grep -q "END launchboard" "$BINDINGS"; then
    fail "unbalanced LaunchBoard markers in $BINDINGS; refusing to edit"
  fi
  cp -a "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  if ! strip_launchboard_block "$BINDINGS"; then
    fail "failed to strip LaunchBoard block from $BINDINGS; original left in place"
  fi
fi

if [[ "$need_bind" -eq 1 ]]; then
  cp -a "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  printf '\n%s\n' "$HOOK_BLOCK" >> "$BINDINGS"
  say "==> Shadowed SUPER+ALT+SPACE with LaunchBoard (Omarchy Apps menu bind is still packaged)"
  reload_hypr
else
  say "==> Keybinding shadow already present in $BINDINGS"
fi

say ""
say "LaunchBoard now opens on Super+Alt+Space."
say "Undo with: $PROJECT/scripts/install-binding.sh --remove"
