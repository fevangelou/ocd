// /**
//  * @version   1.2
//  * @package   Omarchy Classic Desktop (OCD)
//  * @author    Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// A single taskbar tab: a pinned app (not running, launches on click) or
// a window (running or minimized, focuses/restores on click). Text only —
// no icons, by request. Sized entirely by the parent Row (tabsRow.tabWidth
// in Dock.qml), not self-sizing.
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string label: ""
  property bool pinned: false
  property bool running: false
  property bool isMinimized: false
  // The currently-focused window's tab — visually the most "selected"
  // state, distinct from merely "running" (every open window) or
  // "hovered" (transient, mouse-only).
  property bool isActive: false

  signal activated()

  Rectangle {
    anchors.fill: parent
    color: root.isActive
      ? Util.alpha(Color.accent, 0.22)
      : (mouse.containsMouse
        ? Util.alpha(Color.foreground, 0.14)
        : (root.isMinimized ? Util.alpha(Color.foreground, 0.05) : "transparent"))
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  // Running-window indicator: a thin underline along the top edge of the
  // tab — brighter/thicker for the active tab, dim for minimized, plain
  // accent for running-but-unfocused. Same spot a browser tab's active
  // indicator would sit, just inverted to the top since this bar is
  // anchored to the bottom of the screen.
  Rectangle {
    visible: root.running
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: root.isActive ? Math.max(2, Style.space(3)) : Math.max(1, Style.space(2))
    color: root.isMinimized ? Util.alpha(Color.accent, 0.35) : Color.accent
  }

  // Divider between adjacent tabs — without this, same-app tabs (two
  // terminal windows, say) visually merge into one block with no way to
  // tell where one ends and the next begins.
  Rectangle {
    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    width: Math.max(1, Style.space(1))
    color: Util.alpha(Color.foreground, 0.14)
  }

  Text {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: root.label + (root.isMinimized ? " (min)" : "")
    font.pixelSize: Math.max(10, Style.font.title - 3)
    font.bold: root.isActive
    color: root.pinned && !root.running
      ? Util.alpha(Color.foreground, 0.55)
      : (root.isMinimized ? Util.alpha(Color.foreground, 0.6) : Color.foreground)
    font.family: Style.font.family
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.activated()
    // No ToolTip here on purpose: it rendered its popup directly over the
    // tab's own label — confirmed live to visually sit on top of and
    // intercept clicks meant for this MouseArea, so clicking the text
    // itself did nothing while the surrounding tab area still worked. The
    // label is already fully visible on the tab, so a same-text tooltip
    // added little anyway.
  }
}
