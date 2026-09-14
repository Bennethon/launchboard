import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Config.js" as Config

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (root.manifest && root.manifest.id) || "bennethon.launchboard"

  property bool opened: false
  property bool editMode: false
  property bool allAppsView: false
  property string filterText: ""
  property string dialog: ""
  property var dialogApp: null
  property string dialogSectionId: ""
  property string dialogInput: ""
  property var menuItems: []
  property bool ignoreActivate: false
  property string dragKind: ""
  property var dragApp: null
  property string dragSectionId: ""
  property string dragIcon: ""
  property string dragLabel: ""
  property real dragX: 0
  property real dragY: 0
  property bool dropValid: false
  property string dropSectionId: ""
  property string dropBeforeAppId: ""
  property string dropBeforeSectionId: ""
  property real dropLineY: 0
  property real dropLineX: 0
  property real dropLineExtent: 0
  property bool dropLineVertical: false
  property var hiddenSection: null
  property var gridSections: []
  readonly property bool dragging: root.dragKind !== ""
  readonly property string sectionLayout: Config.layoutOf(configStore.config)
  readonly property bool tiled: !root.allAppsView && root.sectionLayout === "tile"
  readonly property int sectionGap: Style.space(20)

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  // Menu scrim is 50% — fine behind a card, too thin under a fullscreen grid.
  property color scrim: Util.alpha(Color.background, 0.88)
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  readonly property int contentPadding: Math.max(Style.space(36), Style.gapsOut * 3)
  readonly property int iconSize: Math.max(Style.space(48), Math.min(Style.space(72), Math.round(panel.width / 28)))
  readonly property int contentWidth: Math.max(1, panel.width - contentPadding * 2)
  readonly property int sectionTileColumns: {
    if (!root.tiled) return 1
    var minTile = Math.max(Style.space(380), root.iconSize * 5 + Style.space(72))
    var cols = Math.floor((root.contentWidth + root.sectionGap) / (minTile + root.sectionGap))
    return Math.max(2, Math.min(3, cols))
  }
  readonly property int sectionTileWidth: {
    var cols = Math.max(1, root.sectionTileColumns)
    return Math.max(Style.space(200), Math.floor((root.contentWidth - root.sectionGap * (cols - 1)) / cols))
  }
  readonly property int columns: Math.max(root.tiled ? 2 : 4, Math.floor(root.sectionTileWidth / Math.max(Style.space(96), iconSize + Style.space(40))))

  onEditModeChanged: {
    if (!root.editMode) root.clearDrag()
    if (root.opened) root.rebuild()
  }
  onAllAppsViewChanged: root.clearDrag()
  onDialogChanged: if (root.dialog !== "") root.clearDrag()

  function open(payloadJson) {
    root.editMode = false
    root.allAppsView = false
    root.filterText = ""
    root.dialog = ""
    root.dialogApp = null
    root.dialogSectionId = ""
    root.dialogInput = ""
    root.menuItems = []
    root.clearDrag()
    search.cursorActive = true
    root.opened = true
    appSource.refresh()
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.clearDrag()
    root.dialog = ""
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function status(arg) {
    return JSON.stringify({
      opened: root.opened,
      backend: appSource.backend,
      appCount: appSource.apps.length,
      sectionCount: search.sections.length,
      flatCount: search.count,
      filter: root.filterText,
      editMode: root.editMode,
      allAppsView: root.allAppsView,
      layout: Config.layoutOf(configStore.config),
      hasShell: root.shell !== null && root.shell !== undefined,
      hasAppLibrary: !!(root.shell && root.shell.appLibrary)
    })
  }

  function toggleLayout() {
    configStore.mutate(function(cfg) {
      return Config.setLayout(cfg, Config.layoutOf(cfg) === "tile" ? "stack" : "tile")
    })
  }

  function createSection(name) {
    var title = String(name || "").trim()
    if (!title) return "empty"
    configStore.mutate(function(cfg) { return Config.addSection(cfg, title) })
    return "ok"
  }

  function rebuild() {
    search.rebuild(appSource.apps, configStore.config, root.filterText, root.allAppsView, root.editMode)
    var all = search.sections || []
    var hidden = null
    var grid = []
    for (var i = 0; i < all.length; i++) {
      if (all[i] && all[i].id === "hidden") hidden = all[i]
      else grid.push(all[i])
    }
    root.hiddenSection = hidden
    root.gridSections = root.allAppsView ? grid : all
  }

  function toggleAllApps() {
    root.allAppsView = !root.allAppsView
    root.rebuild()
    if (scroller) scroller.contentY = 0
  }

  function setFilter(next) {
    root.filterText = String(next || "")
    root.closeDialog()
    root.rebuild()
    Qt.callLater(root.ensureSelectedVisible)
  }

  function launchApp(app) {
    if (!app || !app.id) return
    appSource.launch(app.id, app.name)
    root.dismiss()
  }

  function selectApp(app) {
    if (!app) return
    var index = search.indexOfApp(app.id)
    if (index >= 0) search.selectAbsolute(index)
  }

  function closeDialog() {
    root.dialog = ""
    root.dialogApp = null
    root.dialogSectionId = ""
    root.dialogInput = ""
    root.menuItems = []
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function openMenu(app) {
    if (!app) return
    root.dialogApp = app
    var items = [
      { id: "open", label: "Open" },
      { id: "info", label: "App info" }
    ]
    if (root.editMode || true)
      items.push({ id: "move", label: "Move to section…" })
    items.push({
      id: app.hidden ? "unhide" : "hide",
      label: app.hidden ? "Show in launcher" : "Hide from launcher"
    })
    root.menuItems = items
    root.dialog = "menu"
  }

  function openInfo(app) {
    root.dialogApp = app || search.selectedApp
    if (!root.dialogApp) return
    root.dialog = "info"
  }

  function openMove(app) {
    root.dialogApp = app || search.selectedApp
    if (!root.dialogApp) return
    root.dialog = "move"
  }

  function openNewSection() {
    root.dialogSectionId = ""
    root.dialogInput = ""
    root.dialog = "section-name"
    Qt.callLater(function() { if (sectionField) sectionField.forceActiveFocus() })
  }

  function openRenameSection(sectionId) {
    var sections = configStore.config.sections || []
    for (var i = 0; i < sections.length; i++) {
      if (sections[i] && sections[i].id === sectionId) {
        root.dialogSectionId = sectionId
        root.dialogInput = sections[i].name
        root.dialog = "section-name"
        Qt.callLater(function() { if (sectionField) sectionField.forceActiveFocus() })
        return
      }
    }
  }

  function openDeleteSection(sectionId) {
    root.dialogSectionId = sectionId
    root.dialog = "confirm-delete"
  }

  function submitSectionName() {
    if (root.dialog !== "section-name") return
    var name = String(root.dialogInput || "").trim()
    if (!name) return
    if (root.dialogSectionId)
      configStore.mutate(function(cfg) { return Config.renameSection(cfg, root.dialogSectionId, name) })
    else
      configStore.mutate(function(cfg) { return Config.addSection(cfg, name) })
    // TextField.accepted and the launcher key handler both see Return.
    // Close first, then ignore the leftover activate so it cannot launch.
    root.ignoreActivate = true
    root.closeDialog()
    Qt.callLater(function() { root.ignoreActivate = false })
  }

  function applyMenu(id) {
    var app = root.dialogApp
    if (id === "open") {
      root.closeDialog()
      root.launchApp(app)
      return
    }
    if (id === "info") {
      root.dialog = "info"
      return
    }
    if (id === "move") {
      root.dialog = "move"
      return
    }
    if (id === "hide" && app) {
      configStore.mutate(function(cfg) { return Config.setHidden(cfg, app.id, true) })
      root.closeDialog()
      return
    }
    if (id === "unhide" && app) {
      configStore.mutate(function(cfg) { return Config.setHidden(cfg, app.id, false) })
      root.closeDialog()
    }
  }

  function moveSelectedTo(sectionId) {
    var app = root.dialogApp || search.selectedApp
    if (!app) return
    configStore.mutate(function(cfg) { return Config.moveAppToSection(cfg, app.id, sectionId) })
    root.closeDialog()
  }

  function userSectionItems() {
    var items = []
    if (!sectionRepeater) return items
    for (var i = 0; i < sectionRepeater.count; i++) {
      var item = sectionRepeater.itemAt(i)
      if (item && item.userSection) items.push(item)
    }
    return items
  }

  function sectionItemAtScene(sceneX, sceneY) {
    if (!sectionRepeater) return null
    for (var i = 0; i < sectionRepeater.count; i++) {
      var item = sectionRepeater.itemAt(i)
      if (item && typeof item.containsScenePoint === "function" && item.containsScenePoint(sceneX, sceneY))
        return item
    }
    return null
  }

  function sectionInsertBeforeId(sceneX, sceneY) {
    var users = root.userSectionItems()
    if (users.length === 0 || !sectionColumn) return ""
    var local = sectionColumn.mapFromItem(null, sceneX, sceneY)
    for (var i = 0; i < users.length; i++) {
      if (users[i].section && users[i].section.id === root.dragSectionId) continue
      if (root.tiled) {
        if (local.y < users[i].y) return String(users[i].section.id || "")
        if (local.y <= users[i].y + users[i].height && local.x < users[i].x + users[i].width / 2)
          return String(users[i].section.id || "")
      } else if (local.y < users[i].y + users[i].height / 2) {
        return String(users[i].section.id || "")
      }
    }
    return ""
  }

  function sectionMoveIsNoOp(sectionId, beforeId) {
    var sections = (configStore.config && configStore.config.sections) || []
    var from = -1
    var to = sections.length
    for (var i = 0; i < sections.length; i++) {
      if (!sections[i]) continue
      if (sections[i].id === sectionId) from = i
      if (beforeId && sections[i].id === beforeId) to = i
    }
    if (from < 0) return true
    if (!beforeId) return from === sections.length - 1
    return to === from || to === from + 1
  }

  function updateSectionDropMarker(beforeId) {
    var users = root.userSectionItems()
    root.dropLineVertical = root.tiled
    if (users.length === 0) {
      root.dropLineX = 0
      root.dropLineY = 0
      root.dropLineExtent = 0
      return
    }
    if (!root.tiled) {
      root.dropLineX = 0
      root.dropLineExtent = sectionColumn.width
      if (!beforeId) {
        var lastStack = users[users.length - 1]
        root.dropLineY = lastStack.y + lastStack.height + Style.space(10)
        return
      }
      for (var s = 0; s < users.length; s++) {
        if (users[s].section && users[s].section.id === beforeId) {
          root.dropLineY = Math.max(0, users[s].y - Style.space(10))
          return
        }
      }
      root.dropLineY = 0
      return
    }
    var halfGap = Math.floor(root.sectionGap / 2)
    if (!beforeId) {
      var last = users[users.length - 1]
      root.dropLineX = last.x + last.width + halfGap
      root.dropLineY = last.y
      root.dropLineExtent = last.height
      return
    }
    for (var i = 0; i < users.length; i++) {
      if (users[i].section && users[i].section.id === beforeId) {
        root.dropLineX = Math.max(0, users[i].x - halfGap)
        root.dropLineY = users[i].y
        root.dropLineExtent = users[i].height
        return
      }
    }
  }

  function beginAppDrag(app) {
    if (!root.editMode || root.allAppsView || root.dialog || !app || !app.id) return
    root.dragKind = "app"
    root.dragApp = app
    root.dragSectionId = ""
    root.dragIcon = root.iconFor(app.icon)
    root.dragLabel = String(app.name || "")
    root.dropValid = false
    root.dropSectionId = ""
    root.dropBeforeAppId = ""
  }

  function beginSectionDrag(sectionId, name) {
    if (!root.editMode || root.allAppsView || root.dialog) return
    if (!sectionId || sectionId === "uncategorized" || sectionId === "all") return
    root.dragKind = "section"
    root.dragApp = null
    root.dragSectionId = sectionId
    root.dragIcon = ""
    root.dragLabel = String(name || sectionId)
    root.dropValid = false
    root.dropBeforeSectionId = ""
  }

  function updateDrag(sceneX, sceneY) {
    root.dragX = sceneX
    root.dragY = sceneY
    if (root.dragKind === "app") {
      var item = root.sectionItemAtScene(sceneX, sceneY)
      if (!item || !item.section || item.section.kind === "all") {
        root.dropSectionId = ""
        root.dropBeforeAppId = ""
        root.dropValid = false
        return
      }
      root.dropSectionId = String(item.section.id || "")
      root.dropBeforeAppId = item.insertBeforeAppId(sceneX, sceneY)
      root.dropValid = root.dropSectionId !== ""
      return
    }
    if (root.dragKind === "section") {
      root.dropBeforeSectionId = root.sectionInsertBeforeId(sceneX, sceneY)
      root.updateSectionDropMarker(root.dropBeforeSectionId)
      root.dropValid = !root.sectionMoveIsNoOp(root.dragSectionId, root.dropBeforeSectionId)
    }
  }

  function finishDrag() {
    if (root.dragKind === "app" && root.dropValid && root.dragApp) {
      var appId = root.dragApp.id
      var dest = root.dropSectionId
      var before = root.dropBeforeAppId
      root.clearDrag()
      configStore.mutate(function(cfg) {
        if (dest === "hidden") return Config.setHidden(cfg, appId, true)
        var next = Config.setHidden(cfg, appId, false)
        return Config.moveAppToSection(next, appId, dest, before)
      })
      return
    }
    if (root.dragKind === "section" && root.dropValid && root.dragSectionId) {
      var sectionId = root.dragSectionId
      var beforeSection = root.dropBeforeSectionId
      root.clearDrag()
      configStore.mutate(function(cfg) { return Config.moveSectionBefore(cfg, sectionId, beforeSection) })
      return
    }
    root.clearDrag()
  }

  function clearDrag() {
    root.dragKind = ""
    root.dragApp = null
    root.dragSectionId = ""
    root.dragIcon = ""
    root.dragLabel = ""
    root.dropValid = false
    root.dropSectionId = ""
    root.dropBeforeAppId = ""
    root.dropBeforeSectionId = ""
    root.dropLineY = 0
    root.dropLineX = 0
    root.dropLineExtent = 0
    root.dropLineVertical = false
  }

  function autoScrollDrag() {
    if (!root.dragging || !scroller) return
    var p = scroller.mapFromItem(null, root.dragX, root.dragY)
    var edge = Style.space(56)
    var step = Style.space(16)
    var maxY = Math.max(0, scroller.contentHeight - scroller.height)
    if (p.y < edge)
      scroller.contentY = Math.max(0, scroller.contentY - step)
    else if (p.y > scroller.height - edge)
      scroller.contentY = Math.min(maxY, scroller.contentY + step)
  }

  function handleKey(event) {
    if (root.dragging) {
      if (event.key === Qt.Key_Escape) root.clearDrag()
      event.accepted = true
      return
    }

    if (root.ignoreActivate && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      event.accepted = true
      return
    }

    if (root.dialog === "confirm-delete") {
      if (deleteConfirm.handleKey(event)) event.accepted = true
      return
    }

    if (root.dialog === "section-name") {
      if (event.key === Qt.Key_Escape) {
        root.closeDialog()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.submitSectionName()
        event.accepted = true
      }
      return
    }

    if (root.dialog === "info" || root.dialog === "move" || root.dialog === "menu") {
      if (event.key === Qt.Key_Escape) {
        root.closeDialog()
        event.accepted = true
      } else if (root.dialog === "menu" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        if (root.menuItems.length > 0) root.applyMenu(root.menuItems[0].id)
        event.accepted = true
      }
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (root.filterText) root.setFilter("")
      else root.dismiss()
      event.accepted = true
    } else if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
      root.editMode = !root.editMode
      event.accepted = true
    } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
      root.toggleAllApps()
      event.accepted = true
    } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
      root.editMode = true
      root.openNewSection()
      event.accepted = true
    } else if (event.key === Qt.Key_I && (event.modifiers & Qt.ControlModifier)) {
      root.openInfo(search.selectedApp)
      event.accepted = true
    } else if (Util.editsFilter(event, root.filterText)) {
      root.setFilter(Util.editedFilter(event, root.filterText))
      event.accepted = true
    } else if (event.key === Qt.Key_Left) {
      root.moveSelection(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Right) {
      root.moveSelection(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.moveSelection(-root.columns)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.moveSelection(root.columns)
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      root.moveSelection(-root.columns * 3)
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      root.moveSelection(root.columns * 3)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      root.moveSelectionAbsolute(0)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      root.moveSelectionAbsolute(search.count - 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Tab) {
      root.jumpSection(event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (search.selectedApp) root.launchApp(search.selectedApp)
      event.accepted = true
    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
        root.setFilter(root.filterText + event.text)
        event.accepted = true
      }
    }
  }

  function jumpSection(delta) {
    if (!search.selectedApp || search.sections.length === 0) {
      root.moveSelection(delta)
      return
    }
    var currentId = search.selectedApp.sectionId
    var index = 0
    for (var i = 0; i < search.sections.length; i++) {
      if (search.sections[i].id === currentId) { index = i; break }
    }
    var next = (index + delta + search.sections.length) % search.sections.length
    var apps = search.sections[next].apps || []
    if (apps.length > 0) root.moveSelectionAbsolute(apps[0].flatIndex)
  }

  function selectedCardItem() {
    var app = search.selectedApp
    if (!app || !sectionRepeater) return null
    for (var i = 0; i < sectionRepeater.count; i++) {
      var section = sectionRepeater.itemAt(i)
      if (!section || typeof section.itemForAppId !== "function") continue
      var item = section.itemForAppId(app.id)
      if (item) return item
    }
    return null
  }

  function ensureSelectedVisible() {
    if (!search.selectedApp || !scroller) return
    var item = root.selectedCardItem()
    if (!item) return
    var pos = item.mapToItem(scroller.contentItem, 0, 0)
    var top = pos.y
    var bottom = pos.y + item.height
    if (top < scroller.contentY)
      scroller.contentY = Math.max(0, top - Style.space(24))
    else if (bottom > scroller.contentY + scroller.height)
      scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height), bottom - scroller.height + Style.space(24))
  }

  function moveSelection(delta) {
    search.select(delta)
    Qt.callLater(root.ensureSelectedVisible)
  }

  function moveSelectionAbsolute(index) {
    search.selectAbsolute(index)
    Qt.callLater(root.ensureSelectedVisible)
  }

  function iconFor(icon) {
    return appSource.iconSource(icon)
  }

  Timer {
    interval: 16
    repeat: true
    running: root.dragging
    onTriggered: {
      root.autoScrollDrag()
      root.updateDrag(root.dragX, root.dragY)
    }
  }

  ConfigStore { id: configStore }
  AppSource {
    id: appSource
    shell: root.shell
  }
  SearchController { id: search }

  Connections {
    target: configStore
    function onConfigChanged() { if (root.opened) root.rebuild() }
  }

  Connections {
    target: appSource
    function onAppsChanged() { if (root.opened) root.rebuild() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-launchboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        if (root.dragging) return
        if (root.dialog) root.closeDialog()
        else root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      Item {
        id: chrome
        anchors.fill: parent
        anchors.margins: root.contentPadding

        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (root.dragging) return
            if (root.dialog) root.closeDialog()
            else root.dismiss()
          }
        }

        Column {
          id: header
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Style.space(32)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.editMode ? "LaunchBoard · Editing" : "LaunchBoard"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              opacity: 0.72
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(18)

              Repeater {
                model: root.editMode
                  ? [
                      { id: "layout", label: root.sectionLayout === "tile" ? "Stack" : "Tile" },
                      { id: "new", label: "New section" },
                      { id: "all", label: root.allAppsView ? "Sections" : "All Apps" },
                      { id: "edit", label: "Done" }
                    ]
                  : [
                      { id: "all", label: root.allAppsView ? "Sections" : "All Apps" },
                      { id: "edit", label: "Edit" }
                    ]

                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: modelData.label
                  color: root.selectedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  opacity: 0.86

                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.opacity = 1
                    onExited: parent.opacity = 0.86
                    onClicked: {
                      if (modelData.id === "edit") root.editMode = !root.editMode
                      else if (modelData.id === "all") root.toggleAllApps()
                      else if (modelData.id === "new") root.openNewSection()
                      else if (modelData.id === "layout") root.toggleLayout()
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.filterText.length > 0
            width: parent.width
            textFormat: Text.PlainText
            text: "Search apps: " + root.filterText + "_"
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          Text {
            visible: root.filterText.length === 0 && !root.allAppsView && (configStore.config.sections || []).length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "Newly installed apps land in Uncategorized. Press Ctrl+E or click Edit to create sections."
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        Flickable {
          id: scroller
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: Style.space(18)
          anchors.bottom: parent.bottom
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          contentWidth: width
          contentHeight: Math.max(boardColumn.height, height)
          flickableDirection: Flickable.VerticalFlick

          Item {
            width: scroller.width
            height: Math.max(boardColumn.implicitHeight, scroller.height)

            TapHandler {
              onTapped: {
                if (root.dragging) return
                if (root.dialog) root.closeDialog()
                else root.dismiss()
              }
            }
          }

          Column {
            id: boardColumn
            width: scroller.width
            spacing: root.sectionGap

            Section {
              visible: root.allAppsView && root.hiddenSection !== null
              width: parent.width
              section: root.hiddenSection || ({})
              selectedIndex: search.selectedIndex
              editMode: root.editMode
              dropTarget: root.dragKind === "app" && root.dropValid && root.dropSectionId === "hidden"
              draggingAppId: root.dragKind === "app" && root.dragApp ? String(root.dragApp.id || "") : ""
              columns: root.columns
              iconSize: root.iconSize
              iconFor: root.iconFor
              background: root.background
              foreground: root.foreground
              border: root.border
              selectedBackground: root.selectedBackground
              selectedText: root.selectedText
              cornerRadius: root.cornerRadius
              fontFamily: root.fontFamily
              onAppActivated: function(app) {
                if (root.editMode) root.openMenu(app)
                else root.launchApp(app)
              }
              onAppContextRequested: function(app) { root.openMenu(app) }
              onAppHovered: function(app) { root.selectApp(app) }
            }

            Grid {
              id: sectionColumn
              width: parent.width
              columns: Math.max(1, root.sectionTileColumns)
              columnSpacing: root.sectionGap
              rowSpacing: root.sectionGap

              Repeater {
                id: sectionRepeater
                model: root.gridSections

              Section {
                required property var modelData
                width: root.sectionTileWidth
                section: modelData
                selectedIndex: search.selectedIndex
                editMode: root.editMode && !root.allAppsView
                dropTarget: root.dragKind === "app" && root.dropValid && root.dropSectionId === modelData.id
                draggingOut: root.dragKind === "section" && root.dragSectionId === modelData.id
                draggingAppId: root.dragKind === "app" && root.dragApp ? String(root.dragApp.id || "") : ""
                columns: root.columns
                iconSize: root.iconSize
                iconFor: root.iconFor
                background: root.background
                foreground: root.foreground
                border: root.border
                selectedBackground: root.selectedBackground
                selectedText: root.selectedText
                cornerRadius: root.cornerRadius
                fontFamily: root.fontFamily
                onAppActivated: function(app) {
                  if (root.editMode) root.openMenu(app)
                  else root.launchApp(app)
                }
                onAppContextRequested: function(app) { root.openMenu(app) }
                onAppHovered: function(app) { root.selectApp(app) }
                onAppDragStarted: function(app) { root.beginAppDrag(app) }
                onAppDragMoved: function(app, sceneX, sceneY) { root.updateDrag(sceneX, sceneY) }
                onAppDragEnded: function() { root.finishDrag() }
                onAppDragCanceled: function() { root.clearDrag() }
                onSectionDragStarted: root.beginSectionDrag(modelData.id, modelData.name)
                onSectionDragMoved: function(sceneX, sceneY) { root.updateDrag(sceneX, sceneY) }
                onSectionDragEnded: root.finishDrag()
                onSectionDragCanceled: root.clearDrag()
                onRenameRequested: root.openRenameSection(modelData.id)
                onDeleteRequested: root.openDeleteSection(modelData.id)
                onMoveRequested: function(delta) {
                  configStore.mutate(function(cfg) { return Config.moveSection(cfg, modelData.id, delta) })
                }
              }
              }
            }
          }

          Text {
            visible: search.count === 0
            width: scroller.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.filterText.length > 0 ? ("No matches for “" + root.filterText + "”") : "No applications found"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

        }
      }

      Rectangle {
        visible: root.dragKind === "section" && root.dropValid
        width: root.dropLineVertical ? Math.max(2, Style.space(3)) : sectionColumn.width
        height: root.dropLineVertical ? Math.max(Style.space(24), root.dropLineExtent) : Math.max(2, Style.space(3))
        radius: Math.min(width, height) / 2
        color: root.selectedText
        x: sectionColumn.mapToItem(keyCatcher, root.dropLineVertical ? root.dropLineX : 0, 0).x - (root.dropLineVertical ? width / 2 : 0)
        y: sectionColumn.mapToItem(keyCatcher, 0, root.dropLineY).y - (root.dropLineVertical ? 0 : height / 2)
        z: 80
      }

      Item {
        id: dragGhost
        visible: root.dragging
        width: root.dragKind === "section" ? Style.space(280) : Math.max(Style.space(92), root.iconSize + Style.space(36))
        height: root.dragKind === "section" ? Style.space(40) : root.iconSize + Style.space(44)
        x: keyCatcher.mapFromItem(null, root.dragX, root.dragY).x - width / 2
        y: keyCatcher.mapFromItem(null, root.dragX, root.dragY).y - height / 2
        z: 90
        opacity: 0.92

        BorderSurface {
          anchors.fill: parent
          color: Util.alpha(root.background, 1)
          radius: root.cornerRadius
          borderSpec: Border.surfaceSpec("menu", "border", root.selectedText, Math.max(1, Style.space(2)))
        }

        Row {
          visible: root.dragKind === "app"
          anchors.fill: parent
          anchors.margins: Style.space(8)
          spacing: Style.space(8)

          Image {
            width: root.iconSize * 0.7
            height: root.iconSize * 0.7
            anchors.verticalCenter: parent.verticalCenter
            source: root.dragIcon
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.iconSize * 0.7 - Style.space(8)
            textFormat: Text.PlainText
            text: root.dragLabel
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }

        Text {
          visible: root.dragKind === "section"
          anchors.fill: parent
          anchors.margins: Style.space(10)
          textFormat: Text.PlainText
          text: root.dragLabel
          color: root.selectedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }

      Rectangle {
        visible: root.dialog !== ""
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.55)

        MouseArea {
          anchors.fill: parent
          onClicked: root.closeDialog()
        }

        BorderSurface {
          visible: root.dialog === "menu" || root.dialog === "info" || root.dialog === "move" || root.dialog === "section-name"
          width: Math.min(parent.width - Style.space(48), Style.space(420))
          height: dialogBody.height + Style.space(36)
          anchors.centerIn: parent
          color: root.background
          borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))
          radius: root.cornerRadius

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: dialogBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(18)
            spacing: Style.space(10)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.dialog === "menu" ? String((root.dialogApp && root.dialogApp.name) || "")
                : root.dialog === "info" ? String((root.dialogApp && root.dialogApp.name) || "Application")
                : root.dialog === "move" ? "Move to section"
                : (root.dialogSectionId ? "Rename section" : "New section")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Column {
              visible: root.dialog === "info"
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                visible: !!(root.dialogApp && root.dialogApp.genericName)
                textFormat: Text.PlainText
                text: String((root.dialogApp && root.dialogApp.genericName) || "")
                color: root.foreground
                opacity: 0.8
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                visible: !!(root.dialogApp && root.dialogApp.comment)
                textFormat: Text.PlainText
                text: String((root.dialogApp && root.dialogApp.comment) || "")
                color: root.foreground
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Desktop entry:\n" + String((root.dialogApp && root.dialogApp.id) || "") + ".desktop"
                color: root.foreground
                opacity: 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WrapAnywhere
              }

              Text {
                width: parent.width
                visible: !!(root.dialogApp && root.dialogApp.categories && root.dialogApp.categories.length)
                textFormat: Text.PlainText
                text: "Categories: " + ((root.dialogApp && root.dialogApp.categories) ? root.dialogApp.categories.join(", ") : "")
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Column {
              visible: root.dialog === "menu"
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.menuItems
                Rectangle {
                  required property var modelData
                  width: parent.width
                  height: Style.space(32)
                  radius: root.cornerRadius
                  color: menuHover.containsMouse ? root.selectedBackground : "transparent"

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: menuHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.applyMenu(modelData.id)
                  }
                }
              }
            }

            Column {
              visible: root.dialog === "move"
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: [{ id: "uncategorized", name: "Uncategorized" }].concat(configStore.config.sections || [])
                Rectangle {
                  required property var modelData
                  width: parent.width
                  height: Style.space(32)
                  radius: root.cornerRadius
                  color: moveHover.containsMouse ? root.selectedBackground : "transparent"

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(8)
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: moveHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.moveSelectedTo(modelData.id)
                  }
                }
              }
            }

            TextField {
              id: sectionField
              visible: root.dialog === "section-name"
              width: parent.width
              foreground: root.foreground
              accent: root.selectedText
              text: root.dialogInput
              placeholderText: "Section name"
              onTextChanged: root.dialogInput = text
              onAccepted: root.submitSectionName()
            }
          }
        }

        ConfirmDialog {
          id: deleteConfirm
          anchors.fill: parent
          opened: root.dialog === "confirm-delete"
          message: "Delete this section? Apps return to Uncategorized."
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: "transparent"
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.closeDialog()
          onConfirmed: {
            configStore.mutate(function(cfg) { return Config.deleteSection(cfg, root.dialogSectionId) })
            root.closeDialog()
          }
        }
      }
    }
  }
}
