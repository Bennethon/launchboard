# Changelog

## 0.1.1 — 2026-09-13

- Match the stock Apps menu hide list on the DesktopEntries fallback
  (`launcher.hides` plus `hidden-entries.sh`).
- Create `~/.config/launchboard/` before the first config write, and keep
  the last good layout if `config.json` fails to parse.
- Reject reserved section ids (`hidden`, `all`, `uncategorized`, `menu`).
- Use layer namespace `bennethon-launchboard` instead of `omarchy-*`.
- Fail closed when stripping the Hyprland bind hook if markers are unbalanced.
- Show a short “Launching …” OSD on the fallback launch path.
- Document the inspect-then-enable install path; plugins are unsandboxed.
- Remove leftover `ben.launchboard` install/uninstall handling.
- Add Node tests for config, search, layout, and the bind-hook awk.

## 0.1.0 — 2026-09-13

- Initial public release.
