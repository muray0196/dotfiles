import QtQuick
import Quickshell

ShellRoot {
  FloatingWindow {
    id: window
    title: "Liquid Glass — independent optical study"
    implicitWidth: 1120
    implicitHeight: 760
    minimumSize: Qt.size(1120, 760)
    maximumSize: Qt.size(1120, 760)
    color: "#fafbfc"
    visible: true
    Scene {
      anchors.fill: parent
      animated: Quickshell.env("LIQUID_GLASS_LAB_PAUSED") !== "1"
      pattern: Number(Quickshell.env("LIQUID_GLASS_LAB_SCENE") || "4")
    }
  }
}
