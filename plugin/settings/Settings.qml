// /**
//  * @version   1.4
//  * @package   Omarchy Classic Desktop (OCD)
//  * @author    Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// ocd Settings — a `panel`-kind plugin (same "owns its own PanelWindow"
// pattern as the first-party OSD panel: shell/plugins/osd/Osd.qml). Writes
// ONLY features.json; it performs no other system mutation itself. Every
// change spawns `ocd apply --notify` detached and asynchronous — a
// hyprbars rebuild can take minutes, and this panel must never block the
// shell process while that happens. `ocd apply --notify` sends its own
// desktop notification on completion; this panel just shows a lightweight
// "Applying…" state in the meantime and clears it once no `ocd apply`
// process is left running (polled via pgrep) or after a timeout.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string featuresPath: home + "/.config/omarchy/ocd/features.json"
  readonly property string ocdBin: home + "/.local/share/ocd/bin/ocd"

  property bool opened: false
  property bool applying: false
  // Set by the HyprlandFocusGrab below right before it calls close(). The
  // bar's "ocd" launcher icon lives in a completely separate PanelWindow
  // (a different plugin/kind — no live QML reference between the two), so
  // it can't be added to the grab's own `windows` list the way the
  // first-party PopupCard.qml adds its anchor bar. Without this guard,
  // clicking that icon while the panel is open would clear the grab (close
  // us) and then still deliver the click to the icon's own MouseArea,
  // whose toggle IPC would immediately reopen us — net effect: the icon
  // stops being able to close the panel at all. open() below ignores a
  // reopen that lands within this window of a grab-triggered close, since
  // it's almost certainly that same click's toggle IPC arriving a beat
  // later, not a deliberate fresh open.
  property real lastGrabCloseAt: 0
  // The single on/off switch for the whole mod (features.json schema v2).
  property bool enabled: true

  function shQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function open(payloadJson) {
    // See lastGrabCloseAt above: swallow a reopen that's really just the
    // toggle IPC from the same click that closed us via the outside-click
    // focus grab, not a genuine new open request.
    if (Date.now() - root.lastGrabCloseAt < 300) return
    readEnabledProc.running = true
    opened = true
  }

  function close() {
    opened = false
  }

  // Reads either schema: a v1 file (four per-feature flags) counts as on
  // unless every feature was off, matching ocd_features_migrate in
  // lib/features.sh. The panel can be opened before `ocd apply` has had a
  // chance to migrate the file.
  Process {
    id: readEnabledProc
    command: ["jq", "-r",
      'if has("enabled") then (.enabled != false) ' +
      'else (((.features // {}) | length) == 0 ' +
      'or (((.features // {}) | to_entries | map(.value) | any))) end',
      root.featuresPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = String(text || "").trim()
        if (v === "true" || v === "false") root.enabled = (v === "true")
      }
    }
  }

  function setEnabled(value) {
    root.enabled = value
    var script =
      "set -e; f=" + shQuote(root.featuresPath) + "; " +
      "mkdir -p \"$(dirname \"$f\")\"; " +
      "[ -f \"$f\" ] || printf '%s' '{\"schemaVersion\":2}' > \"$f\"; " +
      "tmp=$(mktemp); jq --argjson v " + (value ? "true" : "false") +
      " '{schemaVersion: 2, enabled: $v}' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""
    writeEnabledProc.command = ["bash", "-c", script]
    writeEnabledProc.running = true
  }

  Process {
    id: writeEnabledProc
    onExited: function (exitCode) {
      if (exitCode === 0) root.applyDetached()
    }
  }

  Process { id: applyDetachedProc }
  function applyDetached() {
    root.applying = true
    // Absolute path, not PATH-relative: a Quickshell-spawned process
    // doesn't inherit an interactive shell's PATH.
    applyDetachedProc.command = ["bash", "-c", shQuote(root.ocdBin) + " apply --notify >/dev/null 2>&1 &"]
    applyDetachedProc.running = true
    applyPollTimer.elapsed = 0
    applyPollTimer.running = true
  }

  Timer {
    id: applyPollTimer
    interval: 1500
    repeat: true
    running: false
    property int elapsed: 0
    onTriggered: {
      elapsed += interval
      pgrepProc.running = true
      if (elapsed > 180000) { running = false; root.applying = false }
    }
  }

  Process {
    id: pgrepProc
    command: ["pgrep", "-f", "bin/ocd apply"]
    onExited: function (exitCode) {
      // pgrep exits 1 when nothing matches — no ocd apply left running.
      if (exitCode !== 0) { applyPollTimer.running = false; root.applying = false }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"

      WlrLayershell.namespace: "ocd-settings"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; right: true }
      // An 8px-only top margin put this popup's own surface directly over
      // the bar itself, which (being on the Overlay layer, above the bar's
      // Top layer) ate clicks meant for the bar's own "ocd" launcher icon
      // underneath it — confirmed live via a screenshot.
      //
      // Style.bar.sizeHorizontal (the bar's real configured thickness,
      // shell/Commons/Style.qml, default 26px matching this machine) was
      // tried first but resolved to `undefined` here specifically — same
      // symptom as the Color.popups.text issue documented in the README's
      // "Known limitations": nested qs.Commons singleton properties don't
      // seem to reliably resolve for a plugin loaded from
      // ~/.config/omarchy/plugins/<id>/ the way they do for a first-party
      // one under shell/plugins/. Using a fixed value instead rather than
      // chasing that further right now. Assumes a top-positioned bar,
      // matching this project's own bar-widget launcher placement;
      // re-anchor to bottom if you ever move the bar there.
      margins { top: Style.space(32); right: Style.space(8) }
      implicitWidth: card.width
      implicitHeight: card.height

      // Outside-click dismissal, same mechanism the first-party PopupCard.qml
      // uses (Ui/PopupCard.qml): while active, Hyprland routes input only to
      // `windows`; clicking anywhere outside that set clears the grab. Only
      // this panel is listed (not the bar's "ocd" icon too, unlike
      // PopupCard's own anchorWindow — that's a different plugin/window with
      // no live QML reference available here), so a click on the icon itself
      // also clears the grab; the lastGrabCloseAt guard on open() above stops
      // that from immediately reopening via the icon's own toggle IPC.
      HyprlandFocusGrab {
        active: root.opened
        windows: [panel]
        onCleared: {
          root.lastGrabCloseAt = Date.now()
          root.close()
        }
      }

      BorderSurface {
        id: card
        width: Style.space(320)
        height: content.implicitHeight + Style.space(24)
        color: Util.alpha(Color.background, 0.98)
        // Color.popups.border swapped for Color.accent: same nested-
        // singleton-property risk as Color.popups.text (see above and the
        // README's "Known limitations") — not confirmed broken here
        // specifically, but not worth the same gamble twice in one file.
        borderSpec: Border.surfaceSpec("popups", "border", Color.accent, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius

        Keys.onEscapePressed: root.close()

        Column {
          id: content
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)

          Text {
            text: "Omarchy Classic Desktop (OCD)"
            color: Color.foreground
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.title
          }

          // One switch for the whole mod. The per-feature toggles this
          // replaced produced combinations nobody wanted, and a failed
          // hyprbars build used to silently flip window-controls off and
          // leave it that way — see lib/features.sh for the schema change.
          //
          // Explicit heights throughout rather than relying on implicit
          // auto-sizing: a positioner nested this deep (Column > Column)
          // was confirmed live to report implicitHeight 0 indefinitely, so
          // the popup's BorderSurface never allocated space for its rows.
          Column {
            width: content.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              height: Style.space(24)
              spacing: Style.space(8)

              Text {
                width: parent.width - masterToggle.width - Style.space(8)
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: "Enabled"
                color: Color.foreground
                font.family: Style.font.family
              }

              Switch {
                id: masterToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: root.enabled
                onToggled: root.setEnabled(checked)
              }
            }

            Text {
              width: parent.width
              text: "Window controls, mouse management, the dock and Exposé. Turning this off leaves this settings panel in place."
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Math.max(9, Style.font.title - 4)
              wrapMode: Text.WordWrap
            }
          }

          Text {
            visible: root.applying
            width: parent.width
            text: "Applying…"
            color: Color.accent
            font.family: Style.font.family
            font.italic: true
          }
        }
      }
    }
  }
}
