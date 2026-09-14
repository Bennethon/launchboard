import QtQuick
import qs.Commons

Item {
  id: root

  property var app: ({})
  property bool selected: false
  property bool editMode: false
  property bool dimmed: false
  property int iconSize: Style.space(56)
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property string iconSource: ""

  signal activated()
  signal contextRequested(real x, real y)
  signal hovered()
  signal dragStarted()
  signal dragMoved(real sceneX, real sceneY)
  signal dragEnded()
  signal dragCanceled()

  readonly property string displayName: String((root.app && root.app.name) || "")
  readonly property string detailText: {
    if (!root.app) return ""
    if (root.app.genericName && root.app.genericName !== root.displayName)
      return String(root.app.genericName)
    return String(root.app.comment || "")
  }
  readonly property bool showDetail: root.selected && root.detailText.length > 0

  width: Math.max(Style.space(92), root.iconSize + Style.space(36))
  height: root.iconSize + Style.space(44)
  opacity: root.dimmed ? 0.28 : 1

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Style.cornerRadius
    color: root.selected ? root.selectedBackground : "transparent"
    border.width: root.selected ? Style.space(1) : 0
    border.color: Util.alpha(root.selectedText, 0.35)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      Item {
        width: parent.width
        height: root.iconSize

        Image {
          anchors.centerIn: parent
          width: root.iconSize
          height: root.iconSize
          source: root.iconSource
          fillMode: Image.PreserveAspectFit
          smooth: true
          asynchronous: true
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
        }

        Rectangle {
          visible: root.app && root.app.hidden === true
          anchors.right: parent.right
          anchors.top: parent.top
          width: Style.space(10)
          height: Style.space(10)
          radius: width / 2
          color: Util.alpha(root.selectedText, 0.85)
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.displayName
        color: root.selected ? root.selectedText : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: root.showDetail ? 1 : 2
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.showDetail
        textFormat: Text.PlainText
        text: root.detailText
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }

  MouseArea {
    id: pointer
    property bool dragging: false
    property bool suppressClick: false
    property real pressX: 0
    property real pressY: 0
    readonly property real dragThreshold: Style.space(8)

    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: root.editMode
    cursorShape: pointer.dragging ? Qt.ClosedHandCursor : (root.editMode ? Qt.OpenHandCursor : Qt.PointingHandCursor)
    onEntered: root.hovered()
    onPressed: function(mouse) {
      pointer.dragging = false
      pointer.suppressClick = false
      pointer.pressX = mouse.x
      pointer.pressY = mouse.y
    }
    onPositionChanged: function(mouse) {
      if (!root.editMode || mouse.button === Qt.RightButton) return
      if (!(mouse.buttons & Qt.LeftButton)) return
      if (!pointer.dragging) {
        var distance = Math.abs(mouse.x - pointer.pressX) + Math.abs(mouse.y - pointer.pressY)
        if (distance < pointer.dragThreshold) return
        pointer.dragging = true
        root.dragStarted()
      }
      var scene = pointer.mapToItem(null, mouse.x, mouse.y)
      root.dragMoved(scene.x, scene.y)
    }
    onReleased: function(mouse) {
      if (!pointer.dragging) return
      pointer.suppressClick = true
      pointer.dragging = false
      root.dragEnded()
    }
    onCanceled: {
      if (pointer.dragging) root.dragCanceled()
      pointer.dragging = false
      pointer.suppressClick = false
    }
    onClicked: function(mouse) {
      if (pointer.suppressClick) {
        pointer.suppressClick = false
        return
      }
      root.hovered()
      if (mouse.button === Qt.RightButton)
        root.contextRequested(mouse.x, mouse.y)
      else
        root.activated()
    }
  }
}
