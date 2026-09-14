import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var section: ({})
  property int selectedIndex: -1
  property bool editMode: false
  property bool dropTarget: false
  property bool draggingOut: false
  property string draggingAppId: ""
  property int columns: 6
  property int iconSize: Style.space(56)
  property var iconFor: function(icon) { return "" }
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  signal appActivated(var app)
  signal appContextRequested(var app, real x, real y)
  signal appHovered(var app)
  signal appDragStarted(var app)
  signal appDragMoved(var app, real sceneX, real sceneY)
  signal appDragEnded(var app)
  signal appDragCanceled(var app)
  signal sectionDragStarted()
  signal sectionDragMoved(real sceneX, real sceneY)
  signal sectionDragEnded()
  signal sectionDragCanceled()
  signal renameRequested()
  signal deleteRequested()
  signal moveRequested(int delta)

  readonly property bool userSection: root.section && root.section.kind === "user"
  readonly property var sectionApps: (root.section && root.section.apps) || []
  readonly property int panelPadding: Style.space(16)

  implicitHeight: panel.height
  height: implicitHeight
  opacity: root.draggingOut ? 0.38 : 1

  function containsScenePoint(sceneX, sceneY) {
    var p = root.mapFromItem(null, sceneX, sceneY)
    return p.x >= 0 && p.y >= 0 && p.x < root.width && p.y < root.height
  }

  function insertBeforeAppId(sceneX, sceneY) {
    return appGrid.insertBeforeAppId(sceneX, sceneY)
  }

  function itemForAppId(appId) {
    var id = String(appId || "")
    if (!id) return null
    for (var i = 0; i < root.sectionApps.length; i++) {
      if (root.sectionApps[i] && String(root.sectionApps[i].id || "") === id)
        return appGrid.itemAt(i)
    }
    return null
  }

  BorderSurface {
    id: panel
    width: parent.width
    height: body.height + root.panelPadding * 2
    color: Util.alpha(root.background, 1)
    radius: root.cornerRadius
    borderSpec: Border.surfaceSpec("menu", "border", root.dropTarget ? root.selectedText : root.border, Math.max(1, Style.space(2)))
    padding: root.panelPadding

    MouseArea {
      id: sectionPointer
      property bool dragging: false
      property bool suppressClick: false
      property real pressX: 0
      property real pressY: 0
      readonly property real dragThreshold: Style.space(8)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      preventStealing: root.editMode && root.userSection
      cursorShape: sectionPointer.dragging ? Qt.ClosedHandCursor : (root.editMode && root.userSection ? Qt.OpenHandCursor : Qt.ArrowCursor)
      onPressed: function(mouse) {
        sectionPointer.dragging = false
        sectionPointer.suppressClick = false
        sectionPointer.pressX = mouse.x
        sectionPointer.pressY = mouse.y
      }
      onPositionChanged: function(mouse) {
        if (!root.editMode || !root.userSection) return
        if (!(mouse.buttons & Qt.LeftButton)) return
        if (!sectionPointer.dragging) {
          var distance = Math.abs(mouse.x - sectionPointer.pressX) + Math.abs(mouse.y - sectionPointer.pressY)
          if (distance < sectionPointer.dragThreshold) return
          sectionPointer.dragging = true
          root.sectionDragStarted()
        }
        var scene = sectionPointer.mapToItem(null, mouse.x, mouse.y)
        root.sectionDragMoved(scene.x, scene.y)
      }
      onReleased: {
        if (!sectionPointer.dragging) return
        sectionPointer.suppressClick = true
        sectionPointer.dragging = false
        root.sectionDragEnded()
      }
      onCanceled: {
        if (sectionPointer.dragging) root.sectionDragCanceled()
        sectionPointer.dragging = false
        sectionPointer.suppressClick = false
      }
      onClicked: {
        sectionPointer.suppressClick = false
      }
    }

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: root.panelPadding
      spacing: Style.space(10)

      Item {
        width: parent.width
        height: Style.space(28)

        Text {
          anchors.left: parent.left
          anchors.right: headerActions.visible ? headerActions.left : parent.right
          anchors.rightMargin: headerActions.visible ? Style.space(12) : 0
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String((root.section && root.section.name) || "")
          color: root.selectedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Row {
          id: headerActions
          visible: root.editMode && root.userSection
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          Repeater {
            model: [
              { label: "Up", action: "up" },
              { label: "Down", action: "down" },
              { label: "Rename", action: "rename" },
              { label: "Delete", action: "delete" }
            ]

            Text {
              required property var modelData
              textFormat: Text.PlainText
              text: modelData.label
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onEntered: parent.opacity = 1
                onExited: parent.opacity = 0.7
                onClicked: {
                  if (modelData.action === "up") root.moveRequested(-1)
                  else if (modelData.action === "down") root.moveRequested(1)
                  else if (modelData.action === "rename") root.renameRequested()
                  else if (modelData.action === "delete") root.deleteRequested()
                }
              }
            }
          }
        }
      }

      AppGrid {
        id: appGrid
        width: parent.width
        apps: root.sectionApps
        selectedIndex: root.selectedIndex
        editMode: root.editMode
        draggingAppId: root.draggingAppId
        columns: root.columns
        iconSize: root.iconSize
        iconFor: root.iconFor
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        fontFamily: root.fontFamily
        onAppActivated: function(app) { root.appActivated(app) }
        onAppContextRequested: function(app, x, y) { root.appContextRequested(app, x, y) }
        onAppHovered: function(app) { root.appHovered(app) }
        onAppDragStarted: function(app) { root.appDragStarted(app) }
        onAppDragMoved: function(app, sceneX, sceneY) { root.appDragMoved(app, sceneX, sceneY) }
        onAppDragEnded: function(app) { root.appDragEnded(app) }
        onAppDragCanceled: function(app) { root.appDragCanceled(app) }
      }
    }
  }
}
