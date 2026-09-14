import QtQuick
import qs.Commons

Item {
  id: root

  property var apps: []
  property int selectedIndex: -1
  property bool editMode: false
  property string draggingAppId: ""
  property int columns: 6
  property int iconSize: Style.space(56)
  property var iconFor: function(icon) { return "" }
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  signal appActivated(var app)
  signal appContextRequested(var app, real x, real y)
  signal appHovered(var app)
  signal appDragStarted(var app)
  signal appDragMoved(var app, real sceneX, real sceneY)
  signal appDragEnded(var app)
  signal appDragCanceled(var app)

  readonly property int cellWidth: {
    if (root.columns <= 0) return Style.space(108)
    return Math.max(Style.space(92), Math.floor(width / root.columns))
  }
  readonly property int cellHeight: root.iconSize + Style.space(48)
  readonly property int rowCount: Math.max(1, Math.ceil(root.apps.length / Math.max(1, root.columns)))

  implicitHeight: root.apps.length === 0 ? 0 : root.rowCount * root.cellHeight

  function insertBeforeAppId(sceneX, sceneY) {
    if (!root.apps || root.apps.length === 0) return ""
    var p = root.mapFromItem(null, sceneX, sceneY)
    if (p.y < 0) return ""
    var cols = Math.max(1, root.columns)
    var col = Math.floor(p.x / Math.max(1, root.cellWidth))
    var row = Math.floor(p.y / Math.max(1, root.cellHeight))
    if (col < 0) col = 0
    if (col >= cols) col = cols - 1
    if (row < 0) row = 0
    var idx = row * cols + col
    var localX = p.x - col * root.cellWidth
    if (localX > root.cellWidth * 0.5) idx++
    if (idx < 0) idx = 0
    if (idx >= root.apps.length) return ""
    return (root.apps[idx] && root.apps[idx].id) || ""
  }

  function itemAt(index) {
    return cardRepeater.itemAt(index)
  }

  Grid {
    id: grid
    anchors.left: parent.left
    width: root.width
    columns: Math.max(1, root.columns)
    rowSpacing: 0
    columnSpacing: 0

    Repeater {
      id: cardRepeater
      model: root.apps

      AppCard {
        required property var modelData
        required property int index

        width: root.cellWidth
        iconSize: root.iconSize
        app: modelData
        selected: root.selectedIndex === (modelData && modelData.flatIndex)
        editMode: root.editMode
        dimmed: root.draggingAppId !== "" && modelData && modelData.id === root.draggingAppId
        iconSource: root.iconFor(modelData && modelData.icon)
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        onActivated: root.appActivated(modelData)
        onContextRequested: function(x, y) { root.appContextRequested(modelData, x, y) }
        onHovered: root.appHovered(modelData)
        onDragStarted: root.appDragStarted(modelData)
        onDragMoved: function(sceneX, sceneY) { root.appDragMoved(modelData, sceneX, sceneY) }
        onDragEnded: root.appDragEnded(modelData)
        onDragCanceled: root.appDragCanceled(modelData)
      }
    }
  }
}
