import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Config.js" as Config
import "AppSearch.js" as AppSearch

// Application discovery + launch. Prefers the host AppLibrary facade when
// the plugin was loaded as a menu kind; otherwise uses DesktopEntries and
// the same uwsm-app/gtk-launch command Omarchy itself uses.
//
// On Omarchy 4.0.3 the scoped shell facade is injected but appLibrary is
// still null for this overlay, so the DesktopEntries path is the live one.
// That path applies launcher.hides and hidden-entries.sh itself so the
// grid matches the stock Apps menu.
Item {
  id: root

  property var shell: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var apps: []
  property string backend: "none"
  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})
  property bool configuredHidesReady: false
  property bool desktopHidesReady: false

  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null
  readonly property bool hidesReady: root.configuredHidesReady && root.desktopHidesReady

  function normalizeList(value) {
    if (!value) return []
    if (typeof value.join === "function") {
      var out = []
      for (var i = 0; i < value.length; i++) {
        var item = String(value[i] || "").trim()
        if (item) out.push(item)
      }
      return out
    }
    var single = String(value || "").trim()
    return single ? [single] : []
  }

  function parseHideIds(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = Config.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    return next
  }

  function isStockHidden(id) {
    var key = Config.normalizeDesktopId(id)
    if (!key) return false
    return root.configuredHiddenEntryIds[key] === true || root.desktopHiddenEntryIds[key] === true
  }

  function fromDesktopEntry(entry) {
    if (!entry) return null
    try {
      if (entry.noDisplay) return null
    } catch (e) {
    }
    try {
      if (entry.hidden) return null
    } catch (e2) {
    }

    var id = Config.normalizeDesktopId(entry.id)
    var name = AppSearch.entryName(entry)
    if (!id || !name) return null
    if (root.appLibrary === null && root.isStockHidden(id)) return null

    return {
      id: id,
      name: name,
      genericName: String(entry.genericName || ""),
      comment: String(entry.comment || ""),
      keywords: root.normalizeList(entry.keywords),
      categories: root.normalizeList(entry.categories),
      icon: String(entry.icon || "")
    }
  }

  function loadFromLibrary() {
    var rows = root.appLibrary.sortedEntries("") || []
    var apps = []
    var seen = {}
    for (var i = 0; i < rows.length; i++) {
      var app = root.fromDesktopEntry(rows[i] && rows[i].entry)
      if (!app || seen[app.id]) continue
      seen[app.id] = true
      apps.push(app)
    }
    root.backend = "omarchy-app-library"
    root.apps = apps
  }

  function loadFromDesktopEntries() {
    var values = []
    try {
      values = DesktopEntries.applications.values || []
    } catch (e) {
      console.warn("LaunchBoard: DesktopEntries unavailable:", e)
      root.backend = "none"
      root.apps = []
      return
    }

    var apps = []
    var seen = {}
    for (var i = 0; i < values.length; i++) {
      var app = root.fromDesktopEntry(values[i])
      if (!app || seen[app.id]) continue
      seen[app.id] = true
      apps.push(app)
    }
    apps.sort(function(a, b) {
      if (a.name.toLowerCase() < b.name.toLowerCase()) return -1
      if (a.name.toLowerCase() > b.name.toLowerCase()) return 1
      return 0
    })
    root.backend = "desktop-entries"
    root.apps = apps
  }

  function reload() {
    if (root.appLibrary && typeof root.appLibrary.sortedEntries === "function") {
      root.loadFromLibrary()
      return
    }
    if (!root.hidesReady) return
    root.loadFromDesktopEntries()
  }

  function refresh() {
    if (root.appLibrary && typeof root.appLibrary.refreshIcons === "function")
      root.appLibrary.refreshIcons()
    if (root.appLibrary === null)
      root.startHiddenEntryScan()
    root.reload()
  }

  function find(id) {
    var key = Config.normalizeDesktopId(id)
    var apps = root.apps
    for (var i = 0; i < apps.length; i++) {
      if (apps[i].id === key) return apps[i]
    }
    return null
  }

  function iconSource(icon) {
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function")
      return root.appLibrary.iconSource(icon)

    var value = String(icon || "")
    if (value.length === 0)
      return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.charAt(0) === "/")
      return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  function showLaunchOsd(label) {
    try {
      Quickshell.execDetached([
        "omarchy-shell", "osd", "show",
        JSON.stringify({
          icon: "󱓞",
          message: "Launching " + label + "…",
          duration: 2000
        })
      ])
    } catch (e) {
    }
  }

  function launch(id, name) {
    var key = Config.normalizeDesktopId(id)
    if (!key) return
    var label = String(name || (root.find(key) && root.find(key).name) || key)

    if (root.appLibrary && typeof root.appLibrary.launch === "function") {
      root.appLibrary.launch(key, label)
      return
    }

    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(key + ".desktop"))
    root.showLaunchOsd(label)
  }

  function hiddenEntryScanCommand() {
    var desktop = [
      Quickshell.env("XDG_CURRENT_DESKTOP"),
      Quickshell.env("XDG_SESSION_DESKTOP"),
      Quickshell.env("DESKTOP_SESSION")
    ].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  function startHiddenEntryScan() {
    if (!root.omarchyPath) {
      root.desktopHiddenEntryIds = ({})
      root.desktopHidesReady = true
      return
    }
    if (!hiddenEntryScan.running)
      hiddenEntryScan.running = true
  }

  function markConfiguredReady() {
    if (!root.configuredHidesReady)
      root.configuredHidesReady = true
    root.reload()
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  FileView {
    path: root.omarchyPath ? (root.omarchyPath + "/default/omarchy/launcher.hides") : ""
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.configuredHiddenEntryIds = root.parseHideIds(text())
      root.markConfiguredReady()
    }
    onFileChanged: {
      root.configuredHiddenEntryIds = root.parseHideIds(text())
      root.reload()
    }
    onLoadFailed: {
      root.configuredHiddenEntryIds = ({})
      root.markConfiguredReady()
    }
  }

  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser {
      onRead: function(line) { hiddenEntryOutput.text += line + "\n" }
    }
    onStarted: hiddenEntryOutput.text = ""
    onExited: {
      root.desktopHiddenEntryIds = root.parseHideIds(hiddenEntryOutput.text)
      root.desktopHidesReady = true
      root.reload()
    }
  }

  Connections {
    target: root.appLibrary
    enabled: root.appLibrary !== null
    function onAppsChanged() { root.reload() }
  }

  Connections {
    target: DesktopEntries.applications
    enabled: root.appLibrary === null
    ignoreUnknownSignals: true
    function onValuesChanged() {
      root.startHiddenEntryScan()
      root.reload()
    }
  }

  onAppLibraryChanged: root.reload()
  onShellChanged: Qt.callLater(root.reload)
  onOmarchyPathChanged: {
    if (!root.omarchyPath) {
      root.configuredHiddenEntryIds = ({})
      root.desktopHiddenEntryIds = ({})
      root.configuredHidesReady = true
      root.desktopHidesReady = true
      root.reload()
      return
    }
    root.desktopHidesReady = false
    root.startHiddenEntryScan()
  }

  Component.onCompleted: {
    if (!root.omarchyPath)
      root.configuredHidesReady = true
    root.startHiddenEntryScan()
    root.reload()
  }
}
