-- Optional LaunchBoard shadow for SUPER + ALT + SPACE.
--
-- Not loaded by `omarchy plugin add` or scripts/install.sh. Source this
-- from ~/.config/hypr/bindings.lua only after an explicit opt-in
-- (scripts/install-binding.sh, or a manual pcall/dofile).
--
-- Omarchy still ships the Apps-menu bind in
-- $OMARCHY_PATH/default/hypr/bindings/utilities.lua. This file is loaded
-- afterward, so the unbind only lasts as long as this file is sourced.
-- Delete the plugin (or the pcall line) and reload Hyprland: the packaged
-- bind is the only SUPER + ALT + SPACE handler again. Nothing in
-- /usr/share/omarchy is edited.

hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "LaunchBoard", "omarchy-shell shell toggle bennethon.launchboard")

-- Keep the overlay instant, matching other Omarchy fullscreen surfaces.
hl.layer_rule({
  match = { namespace = "^bennethon-launchboard$" },
  no_anim = true,
  animation = "none"
})
