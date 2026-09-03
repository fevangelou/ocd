// ocd Exposé — a fullscreen `overlay` plugin. Grid of every open window
// (including special:minimized ones, distinguished with a badge) with
// type-to-search and keyboard navigation. Summoned via IPC
// `omarchy-shell shell toggle io.github.fevangelou.ocd.expose` (bound to
// SUPER+E in hypr/ocd.lua) or by hovering the hot corner below.
//
// `keepLoaded: true` in manifest.json keeps this QML resident while
// closed — required for the hot corner (a tiny always-present PanelWindow,
// independent of `opened`) to be there to hover in the first place.
//
// No compositor plugin needed: window preview capture rides Hyprland's
// native hyprland-toplevel-export-v1 via Quickshell.Wayland.ScreencopyView
// (see WindowTile.qml). Every capture stream is torn down the instant the
// overlay closes because `gridView.model` is emptied on close, destroying
// every WindowTile (and therefore every ScreencopyView) it held.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "AppMatcher.js" as AppMatcher

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omarchy/ocd"

  property bool opened: false
  property string searchText: ""
  property var filteredWindows: []
  property int currentIndex: 0

  function open(payloadJson) {
    overridesReadProc.running = true
    searchText = ""
    recomputeFilteredWindows()
    opened = true
  }

  function close() {
    opened = false
    searchText = ""
    // Emptying the model (recomputeFilteredWindows is not called here on
    // purpose) destroys every WindowTile/ScreencopyView immediately.
    filteredWindows = []
  }

  // Quickshell's Hyprland.toplevels reports each window's address WITHOUT
  // the "0x" prefix that hyprctl's own JSON (and its window selectors,
  // "address:0x...") use — confirmed live: restore silently failed every
  // time until this was added, because the selector matched no window.
  function ocdNormalizeAddress(addr) {
    var s = String(addr || "")
    return s.indexOf("0x") === 0 ? s : "0x" + s
  }

  function recomputeFilteredWindows() {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    var all = []
    var raw = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
    for (var i = 0; i < raw.length; i++) {
      var t = raw[i]
      var appId = t.wayland ? t.wayland.appId : ""
      var resolved = AppMatcher.resolve(appId, t.title, typeof DesktopEntries !== "undefined" ? DesktopEntries : null)
      all.push({
        address: ocdNormalizeAddress(t.address),
        title: t.title || "",
        appName: resolved.name,
        icon: resolved.icon,
        minimized: !!(t.workspace && t.workspace.name === "special:minimized"),
        toplevel: t
      })
    }
    var needle = root.searchText.trim().toLowerCase()
    var filtered = needle.length === 0 ? all : all.filter(function (w) {
      return w.title.toLowerCase().indexOf(needle) !== -1 || w.appName.toLowerCase().indexOf(needle) !== -1
    })
    root.filteredWindows = filtered
    if (root.currentIndex >= filtered.length) root.currentIndex = Math.max(0, filtered.length - 1)
  }

  Process {
    id: overridesReadProc
    command: ["cat", root.configDir + "/appid-overrides.json"]
    stdout: StdioCollector {
      onStreamFinished: AppMatcher.loadOverrides(String(text || ""))
    }
  }

  Process {
    id: restoreProc
    stdout: SplitParser { onRead: line => console.log("[ocd-expose restore stdout] " + line) }
    stderr: SplitParser { onRead: line => console.log("[ocd-expose restore stderr] " + line) }
    onExited: (exitCode, exitStatus) => console.log("[ocd-expose restore] exited code=" + exitCode + " status=" + exitStatus)
  }
  function activate(win) {
    // Do not JSON.stringify(win) here: it contains a `toplevel` reference
    // (a Quickshell object) that is circular, and stringifying it throws —
    // confirmed live, that TypeError silently aborted this whole function
    // before any restore/focus logic ran, on every single click. This was
    // a bug in this debug logging itself, not in the restore mechanism.
    console.log("[ocd-expose] activate() called, address=" + (win && win.address) + " minimized=" + (win && win.minimized) + " title=" + (win && win.title))
    if (!win) { console.log("[ocd-expose] activate(): win is falsy, returning"); return }
    // Quattro's `hyprctl dispatch <name> <args>` CLI form no longer works
    // (parsed as Lua now, expects an hl.dsp.* dispatcher object — confirmed
    // live), so this goes through `hyprctl eval` calling
    // hl.dsp.window.move()/hl.dsp.focus() with a `window` selector
    // ("address:0x...") instead. See plugin/dock/Dock.qml's
    // restoreMinimized() for the identical minimize-restore mechanism.
    //
    // The non-minimized case used to call win.toplevel.wayland.activate()
    // (Quickshell's own protocol-level activate) instead of this same
    // hl.dsp.focus() call — confirmed live to be the wrong choice: if
    // another window was maximized/fullscreened, wayland.activate() left
    // it fullscreen and visually on top even after focus moved away,
    // while hl.dsp.focus() (used here now, and by the minimize-restore
    // path above) was confirmed to correctly clear the outgoing window's
    // fullscreen state as a side effect of a normal Hyprland-native focus
    // change. Using the same call for both cases now, not just for
    // consistency but because it's the one actually confirmed correct.
    var script = ""
    if (win.minimized) {
      script += "t=$(hyprctl activeworkspace -j | jq -r '.id // 1'); " +
        "hyprctl eval \"hl.dispatch(hl.dsp.window.move({workspace = '$t', window = 'address:" + win.address + "'}))\"; "
    }
    script += "hyprctl eval \"hl.dispatch(hl.dsp.focus({window = 'address:" + win.address + "'}))\""
    console.log("[ocd-expose] activating window, address=" + win.address + " minimized=" + win.minimized + " script=" + script)
    restoreProc.command = ["bash", "-c", script]
    restoreProc.running = true
    root.close()
  }

  IpcHandler {
    target: "ocd-expose"
    function open(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function ping(): string { return "ok" }
  }

  // Main fullscreen overlay, one per screen.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
      color: Util.alpha(Color.background, 0.85)

      WlrLayershell.namespace: "ocd-expose"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(32)
        spacing: Style.space(16)

        Rectangle {
          width: Math.min(parent.width, Style.space(420))
          height: searchInput.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.97)
          border.width: Math.max(1, Style.space(2))
          border.color: Color.popups.border
          anchors.horizontalCenter: parent.horizontalCenter

          TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.margins: Style.space(8)
            focus: root.opened
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            text: root.searchText
            onTextChanged: {
              root.searchText = text
              root.recomputeFilteredWindows()
            }

            Keys.onEscapePressed: root.close()
            Keys.onReturnPressed: root.activate(root.filteredWindows[root.currentIndex])
            Keys.onEnterPressed: root.activate(root.filteredWindows[root.currentIndex])
            Keys.onUpPressed: grid.moveCurrentIndexUp()
            Keys.onDownPressed: grid.moveCurrentIndexDown()
            Keys.onLeftPressed: grid.moveCurrentIndexLeft()
            Keys.onRightPressed: grid.moveCurrentIndexRight()
            // hjkl navigation only with Ctrl held, so plain h/j/k/l keep
            // working for type-to-search — the spec asks for both, and
            // they'd otherwise collide on every keystroke.
            Keys.onPressed: function (event) {
              if (!(event.modifiers & Qt.ControlModifier)) return
              if (event.key === Qt.Key_H) { grid.moveCurrentIndexLeft(); event.accepted = true }
              else if (event.key === Qt.Key_L) { grid.moveCurrentIndexRight(); event.accepted = true }
              else if (event.key === Qt.Key_K) { grid.moveCurrentIndexUp(); event.accepted = true }
              else if (event.key === Qt.Key_J) { grid.moveCurrentIndexDown(); event.accepted = true }
            }
          }
        }

        Text {
          visible: root.filteredWindows.length === 0
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.searchText.length > 0 ? "No windows match “" + root.searchText + "”" : "No open windows"
          color: Color.popups.text
          font.family: Style.font.family
        }

        GridView {
          id: grid
          width: parent.width
          height: parent.height - Style.space(80)
          cellWidth: Style.space(260)
          cellHeight: Style.space(200)
          model: root.filteredWindows
          currentIndex: root.currentIndex
          onCurrentIndexChanged: root.currentIndex = currentIndex
          clip: true

          delegate: Item {
            required property var modelData
            required property int index
            width: grid.cellWidth - Style.space(12)
            height: grid.cellHeight - Style.space(12)

            WindowTile {
              anchors.fill: parent
              toplevel: modelData.toplevel
              title: modelData.title
              appName: modelData.appName
              iconName: modelData.icon
              minimized: modelData.minimized
              isCurrent: index === grid.currentIndex
              onActivated: {
                grid.currentIndex = index
                root.activate(modelData)
              }
            }
          }
        }
      }

      MouseArea {
        // Click on the dimmed backdrop (outside any tile) closes, like a
        // typical modal overlay.
        anchors.fill: parent
        z: -1
        onClicked: { console.log("[ocd-expose] backdrop clicked, closing"); root.close() }
        onPressed: console.log("[ocd-expose] backdrop pressed")
      }
    }
  }

  // Hot corner: a tiny always-present strip (independent of `opened`) in
  // the top-right of each screen. Same trick as the dock's auto-hide hover
  // strip — a near-invisible input region that survives the overlay being
  // closed, because keepLoaded keeps this whole file resident.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: corner
      required property var modelData
      screen: modelData
      visible: !root.opened
      color: "transparent"

      WlrLayershell.namespace: "ocd-expose-hotcorner"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; right: true }
      implicitWidth: 2
      implicitHeight: 2

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.open("{}")
      }
    }
  }
}
