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
  property bool dirReady: false
  property string lastError: ""
  property string pendingWrite: ""

  function applyRaw(raw) {
    var parsed = Config.parse(raw)
    if (parsed.error && root.ready) {
      root.lastError = parsed.error
      return
    }
    root.lastError = parsed.error || ""
    root.ready = true
    root.config = parsed.config
    if (parsed.repaired && !parsed.error)
      root.persist()
  }

  function flushPending() {
    if (!root.dirReady || !root.pendingWrite) return
    var text = root.pendingWrite
    root.pendingWrite = ""
    configFile.setText(text)
  }

  function persist() {
    root.pendingWrite = Config.serialize(root.config)
    if (root.dirReady) {
      root.flushPending()
      return
    }
    if (!ensureDir.running)
      ensureDir.running = true
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
    onExited: {
      root.dirReady = exitCode === 0
      if (!root.dirReady)
        root.lastError = "could not create " + root.configDir
      else
        root.flushPending()
    }
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

  Component.onCompleted: {
    if (!ensureDir.running)
      ensureDir.running = true
  }
}
