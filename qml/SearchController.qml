import QtQuick
import "Layout.js" as Layout

QtObject {
  id: root

  property var sections: []
  property var flatApps: []
  property int selectedIndex: 0
  property bool cursorActive: true

  readonly property int count: root.flatApps.length
  readonly property var selectedApp: {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.flatApps.length) return null
    return root.flatApps[root.selectedIndex]
  }

  function rebuild(apps, config, query, allAppsView, editMode) {
    var built = Layout.build(apps || [], config, query, allAppsView === true, editMode === true)
    root.sections = built.sections
    root.flatApps = built.flatApps
    if (built.flatApps.length === 0) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else {
      var next = built.selectedIndex
      if (next < 0) next = 0
      if (next >= built.flatApps.length) next = built.flatApps.length - 1
      root.selectedIndex = next
      root.cursorActive = true
    }
  }

  function select(delta) {
    if (root.flatApps.length === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? root.flatApps.length - 1 : 0
      return
    }
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next >= root.flatApps.length) next = root.flatApps.length - 1
    root.selectedIndex = next
  }

  function selectAbsolute(index) {
    if (root.flatApps.length === 0) return
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, root.flatApps.length - 1))
  }

  function indexOfApp(appId) {
    for (var i = 0; i < root.flatApps.length; i++) {
      if (root.flatApps[i] && root.flatApps[i].id === appId) return i
    }
    return -1
  }
}
