import QtQuick
import Quickshell
import qs.Commons
import "Config.js" as Config
import "AppSearch.js" as AppSearch

// Application discovery + launch. Prefers the host AppLibrary facade when
// the plugin was loaded as a menu kind; otherwise uses DesktopEntries and
// the same uwsm-app/gtk-launch command Omarchy itself uses.
//
// On Omarchy 4.0.3 the scoped shell facade is injected but appLibrary is
// still null for this overlay, so the DesktopEntries path is the live one.
Item {
  id: root

  property var shell: null
  property var apps: []
  property string backend: "none"

  readonly property var appLibrary: root.shell && root.shell.appLibrary ? root.shell.appLibrary : null

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
    if (root.appLibrary && typeof root.appLibrary.sortedEntries === "function")
      root.loadFromLibrary()
    else
      root.loadFromDesktopEntries()
  }

  function refresh() {
    if (root.appLibrary && typeof root.appLibrary.refreshIcons === "function")
      root.appLibrary.refreshIcons()
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

  function launch(id, name) {
    var key = Config.normalizeDesktopId(id)
    if (!key) return
    var label = String(name || (root.find(key) && root.find(key).name) || key)

    if (root.appLibrary && typeof root.appLibrary.launch === "function") {
      root.appLibrary.launch(key, label)
      return
    }

    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(key + ".desktop"))
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
    function onValuesChanged() { root.reload() }
  }

  onAppLibraryChanged: root.reload()
  onShellChanged: Qt.callLater(root.reload)
  Component.onCompleted: root.reload()
}
