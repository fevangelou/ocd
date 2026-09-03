// /**
//  * @version   1.0
//  * @package   Omarchy Classic Desktop (OCD)
//  * @author    Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// A single grid tile in Exposé: live/still preview, app name + title,
// minimized badge. Degrades to an icon + title card if screencopy is
// unavailable or the window refuses capture — never a black rectangle.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Ui

Item {
  id: root

  property var toplevel
  property string title: ""
  property string appName: ""
  property string iconName: ""
  property bool minimized: false
  property bool isCurrent: false

  signal activated()

  readonly property bool hovered: mouse.containsMouse || isCurrent

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(Color.background, 0.9)
    border.width: root.hovered ? Math.max(1, Style.space(2)) : 0
    border.color: Color.accent
  }

  Item {
    id: previewArea
    anchors.fill: parent
    anchors.margins: Style.space(8)
    anchors.bottomMargin: Style.space(32)

    property bool captureFailed: false

    ScreencopyView {
      id: capture
      anchors.fill: parent
      visible: hasContent && !previewArea.captureFailed
      // Still-frame by default (ScreencopyView's own `live` default is
      // false); only the hovered/current tile is promoted to a live
      // stream, to bound GPU cost across a grid of N windows. Whichever
      // component owns Expose.qml's `opened -> false` transition is
      // responsible for this Item (and therefore this ScreencopyView)
      // being destroyed via the grid model going empty, which tears down
      // every capture stream the instant the overlay closes rather than
      // merely hiding them.
      live: root.hovered
      paintCursor: false
      captureSource: root.toplevel && root.toplevel.wayland ? root.toplevel.wayland : null
    }

    // If capture never produces content shortly after becoming visible
    // (screencopy unavailable, or this window refuses capture), fall back
    // to an icon card instead of leaving a black rectangle on screen.
    Timer {
      interval: 900
      running: root.visible && !capture.hasContent
      onTriggered: previewArea.captureFailed = true
    }

    IconImage {
      anchors.centerIn: parent
      width: Style.space(64)
      height: Style.space(64)
      visible: !capture.visible
      source: root.iconName.length > 0
        ? Quickshell.iconPath(root.iconName, "application-x-executable")
        : Quickshell.iconPath("application-x-executable")
    }
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(6)
    spacing: 2

    Text {
      width: parent.width
      text: root.appName
      color: Color.popups.text
      font.family: Style.font.family
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.title !== root.appName && root.title.length > 0
      text: root.title
      color: Util.alpha(Color.popups.text, 0.7)
      font.family: Style.font.family
      elide: Text.ElideRight
    }
  }

  Rectangle {
    visible: root.minimized
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(6)
    radius: Style.cornerRadius
    color: Color.accent
    width: badgeText.implicitWidth + Style.space(8)
    height: badgeText.implicitHeight + Style.space(4)
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: "minimized"
      color: Color.background
      font.pixelSize: 10
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { console.log("[ocd-expose] WindowTile clicked, title=" + root.title); root.activated() }
    onPressed: console.log("[ocd-expose] WindowTile pressed, title=" + root.title)
    onContainsMouseChanged: console.log("[ocd-expose] WindowTile containsMouse=" + containsMouse + " title=" + root.title)
  }
}
