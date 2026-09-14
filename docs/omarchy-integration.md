# Omarchy integration notes

Investigated against **Omarchy 4.0.3-1** on this machine (`/usr/share/omarchy`,
`~/.config/omarchy`, `~/.config/hypr`). LaunchBoard is a third-party
`omarchy-shell` plugin. It must not edit `/usr/share/omarchy/`.

## How plugins are structured

`omarchy-shell` is one long-running Quickshell process. The bar, overlays,
menus, and panels all load as plugins inside that process.

| Kind | Role | Load behavior |
|---|---|---|
| `overlay` | Fullscreen layer-shell surface | Loaded when summoned |
| `menu` | Summoned menu surface | Loaded when summoned |
| `panel` | Floating window (e.g. Omasweeper) | Loaded when summoned |
| `bar-widget` | Item in the bar | Mounted with the bar |
| `service` | Headless singleton | Mounted at startup (1p) |
| `bar` | Full bar replacement | One active at a time |

A plugin is a directory with `manifest.json` plus the QML files named in
`entryPoints`. Official install path:

```
~/.config/omarchy/plugins/<plugin-id>/manifest.json
```

`omarchy plugin add <git-url>` clones a repo whose **root** contains
`manifest.json`. Development installs can symlink a working tree to that
path; the shell will load a symlink even though `omarchy plugin validate`
rejects validating through one.

Required manifest fields: `schemaVersion` (must be `1`), `id`, `name`,
`version`, `kinds`, `entryPoints`. Set `keepLoaded: true` when the overlay
should stay mounted between summons (clipboard, emojis, image-picker,
Omarchy menu all do this).

## How overlays are implemented

First-party overlays (`omarchy.clipboard`, `omarchy.emojis`,
`omarchy.image-picker`) are an `Item` root that:

1. Exposes `opened`, plus `open(payloadJson)`, `close()`, and usually `toggle()`.
2. Creates a `PanelWindow` anchored to all edges with
   `WlrLayershell.layer: WlrLayer.Overlay`,
   `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`,
   `exclusionMode: ExclusionMode.Ignore`.
3. Uses `Color.menu.*` (or a dedicated surface such as `Color.imagePicker`)
   and `Style.*` from `qs.Commons`.
4. Forces focus onto a key catcher with `Keys.priority: Keys.BeforeItem` so
   typing works immediately.

The host Loader injects `omarchyPath`, `shell`, `manifest`, and (when
declared) `pluginRegistry` / `barWidgetRegistry` after load.

Stock Hyprland layer rules disable compositor fades for
`omarchy-menu|omarchy-image-selector|omarchy-emojis|omarchy-clipboard|omarchy-keyboard-panel`.
LaunchBoard uses namespace `omarchy-launchboard`. A matching user-level
layer rule ships in `hypr/bindings.lua` and is applied only if the user
opts into `scripts/install-binding.sh`.

## How plugins are registered and loaded

1. Drop or symlink the plugin under `~/.config/omarchy/plugins/<id>/`.
2. `omarchy-shell shell rescanPlugins` (saving any file under the plugins
   directory also hot-reloads).
3. Enable it so it appears in `~/.config/omarchy/shell.json`:

```bash
omarchy plugin enable bennethon.launchboard
```

Third-party non-bar plugins are enabled **iff** their id is listed in
`shell.json` `plugins[]`. First-party non-bar plugins are enabled unless
listed in `disabledPlugins[]`.

Summon / hide / toggle:

```bash
omarchy-shell shell summon bennethon.launchboard '{}'
omarchy-shell shell hide bennethon.launchboard
omarchy-shell shell toggle bennethon.launchboard
```

`toggle` reads the plugin's `opened` property. Closing the overlay must set
`opened` to `false` or the next toggle will call `hide` instead of `open`.

## Application list, icons, and launch

The host keeps a shared `AppLibrary` (`shell/services/AppLibrary.qml`) built
on Quickshell `DesktopEntries`. It:

- Filters `NoDisplay` entries and Omarchy's `launcher.hides` list
- Resolves icons (`iconIndex` + `Quickshell.iconPath`)
- Launches with `uwsm-app -- gtk-launch '<id>.desktop'`
- Shows a short “Launching …” OSD if the window is slow to appear
- Exposes `entryName`, `entrySubtext`, `sortedEntries(query)`, `iconSource`,
  `refreshIcons`, `launch`, `remove`

Desktop entry fields used by the stock Apps menu:

| Field | Use |
|---|---|
| `id` | Stable desktop-file id **without** `.desktop` |
| `name` | Display name |
| `genericName` | Secondary label / search |
| `comment` | Description / search |
| `keywords` | Search |
| `icon` | Icon name or path |
| `noDisplay` | Hidden from launchers |

`AppLibrary.launch()` always appends `.desktop` before calling `gtk-launch`.
Ids such as `org.telegram.desktop` therefore stay suffix-free in config.

### Public vs internal

| Surface | Stability | LaunchBoard use |
|---|---|---|
| `manifest.json` kinds / entryPoints / `keepLoaded` | Documented plugin contract | Required |
| `omarchy-shell shell summon/hide/toggle/rescanPlugins` | Documented IPC | Required |
| `shell.open` / `close` / `opened` lifecycle | Documented in shell README | Required |
| Injected `shell`, `manifest`, `omarchyPath` | Documented host injection | Required |
| `shell.appLibrary` facade | Documented **only for `menu` plugins** | Preferred path |
| `qs.Commons` Color / Style / Util | Shared theme kit; used by 3p plugins | Theming |
| `qs.Ui` ConfirmDialog / TextField | Shared widgets; used by 1p overlays | Dialogs |
| `AppLibrary.qml` / `AppSearch.js` internals | **Not** a public import | Do not import |
| `DesktopEntries` (Quickshell) | Quickshell API, not Omarchy | Fallback source |
| `uwsm-app -- gtk-launch` | What Omarchy itself runs | Fallback launch |

The host injects `shell.appLibrary` only when the manifest includes
`kind: "menu"` (`shell.qml` `pluginShellFor`). LaunchBoard therefore
declares `["overlay", "menu"]`:

- `overlay` selects the fullscreen Loader path
- `menu` requests the application-library facade

Both entry points resolve to the same QML file.

**Runtime note (Omarchy 4.0.3):** after a successful load, the injected
`shell` facade is present (`hasShell: true`) but `shell.appLibrary` is
still `null`. `AppSource` therefore uses Quickshell `DesktopEntries` and
launches with `uwsm-app -- gtk-launch '<id>.desktop'` — the same command
`AppLibrary.launch()` runs. On this machine that path discovered 80
visible applications. If a later Omarchy build starts attaching the
facade to dual-kind plugins, `AppSource` will pick it up automatically.

Do **not** parse and execute `.desktop` `Exec=` lines.

## How the stock Apps menu works

`SUPER + ALT + SPACE` is bound in `/usr/share/omarchy/default/hypr/bindings/utilities.lua` to:

```lua
o.bind("SUPER + ALT + SPACE", "Apps menu", "omarchy-menu toggle apps")
```

`omarchy-menu` is a wrapper that summons `omarchy.menu`. The Apps submenu
is a QML provider: it calls `appLibrary.sortedEntries("")`, shows
`entry.name` / `entry.icon`, and launches with `appLibrary.launch(id, name)`.

That menu is a searchable list. It is not a visual library. LaunchBoard
does not replace `omarchy.menu`; it is a second overlay the user can bind
to the same chord.

## Plugin configuration persistence

Omarchy's own plugin settings live inline on the `shell.json` entry
(`{"id":"…", "someKey": …}`). That model fits a handful of scalars, not a
user-built section layout.

LaunchBoard stores organization in:

```
${XDG_CONFIG_HOME:-~/.config}/launchboard/config.json
```

Clipboard history is the closest first-party precedent for a plugin-owned
file (`~/.local/state/omarchy/clipboard-history.json` via `FileView`).
XDG config is the better home for a user-edited layout.

`shell.json` only needs:

```json
{ "id": "bennethon.launchboard" }
```

inside `plugins[]`.

## Keyboard bindings

User overrides belong in `~/.config/hypr/bindings.lua`. That file is loaded
after Omarchy defaults. Replacing an existing chord requires `hl.unbind`
first.

Default for the target chord:

| Keys | Action | Command |
|---|---|---|
| `SUPER + ALT + SPACE` | Apps menu | `omarchy-menu toggle apps` |

Safe shadow (shipped as `hypr/bindings.lua`). Standard installation does
**not** source it. Users opt in with `scripts/install-binding.sh`, or by
adding Omarchy's supported override to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "LaunchBoard", "omarchy-shell shell toggle bennethon.launchboard")
```

This does not delete the packaged bind. Hyprland reloads defaults first,
then user config. Removing the override (or the plugin file a `pcall`
points at) and reloading is enough for `omarchy-menu toggle apps` to be
the only handler again. `install-binding.sh --remove` and `uninstall.sh`
do that for the helper's marker block and never write a copy of the
Apps-menu bind into user config.

Do not edit `/usr/share/omarchy/default/hypr/`.

## Theme tokens LaunchBoard uses

From `qs.Commons` (live theme, not a fork):

- `Color.menu.background`, `.text`, `.border`, `.scrim`
- `Color.menu.selectedBackground`, `.selectedText`
- `Color.accent`, `Color.foreground`, `Color.background`
- `Style.cornerRadius`, `Style.gapsOut`, `Style.font.*`, `Style.spacing.*`
- `Style.font.menuFamily` (honors `OMARCHY_MENU_FONT`)

## What LaunchBoard isolates behind abstractions

| Need | Abstraction | Primary | Fallback |
|---|---|---|---|
| Installed apps + metadata | `AppSource` | `shell.appLibrary` | `DesktopEntries` |
| Icons | `AppSource.iconSource` | `appLibrary.iconSource` | `Quickshell.iconPath` |
| Launch | `AppSource.launch` | `appLibrary.launch` | `uwsm-app -- gtk-launch` |
| Hidden stock entries | `AppSource` | AppLibrary filters | `noDisplay` / `hidden` |
| User layout | `ConfigStore` | `~/.config/launchboard/config.json` | empty in-memory config |

If Omarchy later publishes a first-class application API for overlay
plugins, only `AppSource.qml` should need to change.
