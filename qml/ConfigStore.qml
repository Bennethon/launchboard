import QtQuick
import Quickshell
import Quickshell.Io
import "Config.js" as Config

Item {
  id: root

  readonly property string configHome: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    if (xdg && xdg.length > 0) return xdg
    return Quickshell.env("HOME") + "/.config"
  }
  readonly property string configDir: configHome + "/launchboard"
  readonly property string configPath: configDir + "/config.json"

  property var config: Config.emptyConfig()
  property bool ready: false
  property string lastError: ""

  function applyRaw(raw) {
    var parsed = Config.parse(raw)
    root.lastError = parsed.error || ""
    root.ready = true
    root.config = parsed.config
  }

  function persist() {
    if (!ensureDir.running)
      ensureDir.running = true
    configFile.setText(Config.serialize(root.config))
  }

  function replace(next) {
    root.lastError = ""
    root.config = Config.parse(JSON.stringify(next || Config.emptyConfig())).config
    root.persist()
  }

  function mutate(fn) {
    if (typeof fn !== "function") return
    root.replace(fn(root.config))
  }

  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.configDir]
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyRaw(text())
    onLoadFailed: root.applyRaw("")
    onFileChanged: reload()
  }
}
