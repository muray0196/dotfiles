pragma ComponentBehavior: Bound
import QtQuick

// Retain the combined day composition for the historical preview directions.
Item {
  required property var scene
  implicitHeight: 388
  Clock { scene: parent.scene; width: parent.width }
  Calendar { scene: parent.scene; y: 146; width: parent.width }
}
