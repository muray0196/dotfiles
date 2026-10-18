import QtQuick

Rectangle {
  id: button
  required property var scene
  property string text: ""
  property string icon: ""
  property bool selected: false
  property bool overlay: false
  readonly property bool darkInk: scene.darkText
  signal clicked()
  implicitWidth: Math.max(overlay ? 40 : 44, caption.implicitWidth + (overlay ? 16 : 24))
  implicitHeight: overlay ? 28 : 32
  radius: overlay ? 8 : 16
  color: overlay ? (mouse.pressed ? (darkInk ? "#33172331" : "#4dffffff")
                    : mouse.containsMouse || activeFocus ? (darkInk ? "#24172331" : "#33ffffff")
                    : selected ? (darkInk ? "#1c172331" : "#26ffffff") : "transparent")
                 : (mouse.pressed ? "#edf4fa" : selected ? "#dce9f3" : mouse.containsMouse || activeFocus ? "#cce7ebee" : "#55e7ebee")
  Behavior on color { ColorAnimation { duration: 100 } }
  border.width: activeFocus ? 2 : overlay && selected ? 1 : 0
  border.color: overlay ? (activeFocus ? (darkInk ? "#245f9e" : "#a7dcff") : darkInk ? "#40172331" : "#66ffffff") : "#246891"
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.onPressAction: button.clicked()
  onActiveFocusChanged: {
    if (!icon) return;
    if (activeFocus) scene.showDetail(text, button);
    else if (!mouse.containsMouse) scene.hideDetail();
  }
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Label {
    id: caption
    scene: button.scene
    anchors.centerIn: parent
    text: button.icon || button.text
    ink: button.overlay ? (button.darkInk ? "#172331" : "#fafbff") : "#192939"
    shadowed: button.overlay
    family: button.icon ? "Material Symbols Rounded" : "Adwaita Sans"
    size: button.icon ? 20 : 12
    weight: button.icon ? Font.Normal : Font.DemiBold
    Accessible.ignored: true
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (button.icon) button.scene.showDetail(button.text, button)
    onExited: if (button.icon && !button.activeFocus) button.scene.hideDetail()
    onClicked: {
      if (button.icon) button.scene.hideDetail()
      button.clicked()
    }
  }
}
