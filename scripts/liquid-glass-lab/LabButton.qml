import QtQuick

Rectangle {
  id: button
  required property string text
  property bool selected: false
  signal clicked()
  implicitWidth: label.implicitWidth + 24
  implicitHeight: 34
  radius: 17
  color: selected ? "#202735" : (pointer.containsMouse ? "#e2e7ed" : "#edf0f4")
  Accessible.role: Accessible.Button
  Accessible.name: text
  Accessible.onPressAction: button.clicked()

  Text {
    id: label
    anchors.centerIn: parent
    text: button.text
    color: button.selected ? "#ffffff" : "#424c5d"
    font.pixelSize: 12
    font.weight: Font.Medium
  }

  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
