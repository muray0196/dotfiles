import QtQuick
import Quickshell

ShellRoot {
  FloatingWindow {
    title: "Liquid Glass — Playground"
    implicitWidth: 1120
    implicitHeight: 800
    minimumSize: Qt.size(1120, 800)
    maximumSize: Qt.size(1120, 800)
    color: "#fafbfc"
    visible: true
    Playground {
      anchors.fill: parent
      animated: Quickshell.env("LIQUID_GLASS_LAB_PAUSED") !== "1"
      onCloseRequested: Qt.quit()
    }
  }
}
