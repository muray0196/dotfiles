import QtQuick
import "material" as Material

Material.Glass {
  required property var scene
  backdrop: scene.pool.sharp
  softenedBackdrop: scene.pool.soft
  backdropSize: Qt.size(scene.width, scene.height)
  backdropPosition: Qt.point(x, y)
  // All optical lengths, lighting, softness and shape defaults belong to Glass.
}
