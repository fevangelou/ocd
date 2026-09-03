// Small bar icon that toggles the ocd settings panel via IPC. Kept
// intentionally minimal — all real UI lives in Settings.qml.
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  implicitWidth: icon.width + Style.space(16)
  implicitHeight: Style.space(24)

  Process {
    id: toggleProc
    command: ["omarchy-shell", "shell", "toggle", "io.github.fevangelou.ocd.settings"]
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouse.containsMouse ? Util.alpha(Color.accent, 0.15) : "transparent"
  }

  // Two overlapping window rectangles — stands in for "ocd" (window
  // management). The front rectangle is filled with the bar's own
  // background so the back rectangle's edge doesn't show through the
  // overlap, giving a clean layered look instead of a lattice of lines.
  Item {
    id: icon
    anchors.centerIn: parent
    // Explicit rect size + diagonal gap (rather than percentages of the
    // container) so the offset between the two windows is a fixed, tunable
    // pixel amount instead of shrinking/growing with rounding.
    readonly property real rectW: Style.space(10)
    readonly property real rectH: Style.space(7)
    readonly property real gapX: Style.space(5)
    readonly property real gapY: Style.space(3)
    width: rectW + gapX
    height: rectH + gapY

    Rectangle {
      id: backWindow
      x: 0
      y: 0
      width: parent.rectW
      height: parent.rectH
      radius: Style.space(1.5)
      color: "transparent"
      border.width: Style.space(1)
      border.color: mouse.containsMouse ? Color.accent : Color.foreground
    }

    Rectangle {
      id: frontWindow
      x: parent.gapX
      y: parent.gapY
      width: parent.rectW
      height: parent.rectH
      radius: Style.space(1.5)
      color: Color.background
      border.width: Style.space(1)
      border.color: mouse.containsMouse ? Color.accent : Color.foreground
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: toggleProc.running = true
  }
}
