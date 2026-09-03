// /**
//  * @version   1.0
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
  // { "window-controls": true, "mouse-management": true, "dock": true, "expose": true }
  property var features: ({ "window-controls": true, "mouse-management": true, "dock": true, "expose": true })
  // Window-controls sub-option: "solid" (icon glyphs) or "text" (D/H/H — a
  // nod to DHH; see hypr/ocd.lua for the close/maximize/minimize mapping).
  property string controlStyle: "solid"
  // { name: <feature>, value: <bool> } while a destructive toggle awaits
  // confirmation; null otherwise.
  property var pendingConfirm: null

  readonly property bool canWindowControls: features["dock"] === true || features["expose"] === true

  function shQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function open(payloadJson) {
    // See lastGrabCloseAt above: swallow a reopen that's really just the
    // toggle IPC from the same click that closed us via the outside-click
    // focus grab, not a genuine new open request.
    if (Date.now() - root.lastGrabCloseAt < 300) return
    readFeaturesProc.running = true
    readControlStyleProc.running = true
    pendingConfirm = null
    opened = true
  }

  function close() {
    opened = false
    pendingConfirm = null
  }

  Process {
    id: readFeaturesProc
    command: ["jq", "-c", ".features", root.featuresPath]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          if (parsed && typeof parsed === "object") root.features = parsed
        } catch (e) { /* keep previous/defaults */ }
      }
    }
  }

  Process {
    id: readControlStyleProc
    command: ["jq", "-r", ".windowControlsStyle // \"solid\"", root.featuresPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = String(text || "").trim()
        root.controlStyle = (v === "text") ? "text" : "solid"
      }
    }
  }

  function setControlStyle(value) {
    if (value !== "solid" && value !== "text") return
    root.controlStyle = value
    var script =
      "set -e; f=" + shQuote(root.featuresPath) + "; " +
      "mkdir -p \"$(dirname \"$f\")\"; " +
      "[ -f \"$f\" ] || printf '%s' '{\"schemaVersion\":1,\"features\":{}}' > \"$f\"; " +
      "tmp=$(mktemp); jq --arg v " + shQuote(value) +
      " '.windowControlsStyle=$v' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""
    writeControlStyleProc.command = ["bash", "-c", script]
    writeControlStyleProc.running = true
  }

  Process {
    id: writeControlStyleProc
    onExited: function (exitCode) {
      if (exitCode === 0) root.applyDetached()
    }
  }

  // requestSetFeature: the UI-facing entry point. Enforces the dependency
  // graph (window-controls needs a restore surface) by warning-then-
  // confirming rather than silently refusing, since the user might
  // genuinely want both off at once.
  function requestSetFeature(name, value) {
    if (name === "window-controls" && value === true && !canWindowControls) return
    if ((name === "dock" || name === "expose") && value === false && features["window-controls"] === true) {
      var other = name === "dock" ? "expose" : "dock"
      if (features[other] !== true) {
        pendingConfirm = { name: name, value: value }
        return
      }
    }
    setFeature(name, value)
  }

  function confirmPending() {
    if (!pendingConfirm) return
    var p = pendingConfirm
    pendingConfirm = null
    setFeature(p.name, p.value)
  }

  function cancelPending() { pendingConfirm = null }

  function setFeature(name, value) {
    var next = {}
    for (var k in root.features) next[k] = root.features[k]
    next[name] = value
    root.features = next

    var script =
      "set -e; f=" + shQuote(root.featuresPath) + "; " +
      "mkdir -p \"$(dirname \"$f\")\"; " +
      "[ -f \"$f\" ] || printf '%s' '{\"schemaVersion\":1,\"features\":{}}' > \"$f\"; " +
      "tmp=$(mktemp); jq --arg k " + shQuote(name) + " --argjson v " + (value ? "true" : "false") +
      " '.features[$k]=$v' \"$f\" > \"$tmp\" && mv \"$tmp\" \"$f\""
    writeFeatureProc.command = ["bash", "-c", script]
    writeFeatureProc.running = true
  }

  Process {
    id: writeFeatureProc
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

  readonly property var featureOrder: ["window-controls", "mouse-management", "dock", "expose"]
  readonly property var featureLabels: ({
    "window-controls": "Window Controls",
    "mouse-management": "Mouse Management",
    "dock": "Dock",
    "expose": "Exposé"
  })
  readonly property var featureDescriptions: ({
    "window-controls": "Titlebars with minimize / maximize / close (hyprbars).",
    "mouse-management": "Drag-to-move and drag-to-resize, including border resize.",
    "dock": "Running windows and pinned apps in an auto-hiding dock.",
    "expose": "Fullscreen live-preview window switcher (SUPER+E)."
  })

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

          Repeater {
            model: root.featureOrder
            delegate: Column {
              required property string modelData
              width: content.width
              spacing: 2

              readonly property bool isWindowControls: modelData === "window-controls"
              readonly property bool rowEnabled: !isWindowControls || root.canWindowControls || root.features[modelData] === true

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: parent.width - toggle.width - Style.space(8)
                  text: root.featureLabels[modelData]
                  color: rowEnabled ? Color.foreground : Util.alpha(Color.foreground, 0.4)
                  font.family: Style.font.family
                  anchors.verticalCenter: parent.verticalCenter
                }

                Switch {
                  id: toggle
                  anchors.verticalCenter: parent.verticalCenter
                  enabled: rowEnabled
                  checked: root.features[modelData] === true
                  onToggled: root.requestSetFeature(modelData, checked)
                }
              }

              Text {
                width: parent.width
                text: root.featureDescriptions[modelData]
                color: Util.alpha(Color.foreground, 0.6)
                font.family: Style.font.family
                font.pixelSize: Math.max(9, Style.font.title - 4)
                wrapMode: Text.WordWrap
              }

              Text {
                visible: isWindowControls && !root.canWindowControls
                width: parent.width
                text: "Needs Dock or Exposé enabled as a restore surface for minimized windows."
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Math.max(9, Style.font.title - 4)
                wrapMode: Text.WordWrap
              }

              // Window-controls sub-option: titlebar button style. Only
              // shown/enabled while window-controls itself is on.
              //
              // Every item below has an EXPLICIT height rather than
              // relying on Row/Column implicit auto-sizing — confirmed
              // live (via temporary debug logging, since removed) that a
              // plain `Row`/`Column` nested this deep (Column > Repeater >
              // Column > Column) reported implicitHeight staying at 0
              // indefinitely, so the enclosing Column's own implicitHeight
              // never grew past its single Text label and the popup's
              // BorderSurface (sized from that implicitHeight) never
              // allocated space for these rows at all — not a rendering
              // bug, a layout-sizing one. Explicit heights sidestep it.
              //
              // The two options are laid out on ONE line inside a plain
              // Item (not a Row/Column positioner) with each child's `x`
              // explicitly chained off the previous sibling's own x+width.
              // This isn't just style: a `Row` positioner was confirmed
              // live to also fail to POSITION its children correctly at
              // this same nesting depth — giving the Row itself an
              // explicit width/height (as the previous version did) fixed
              // its own reported size but not the actual left-to-right
              // placement of the circle and label inside it, which is why
              // that version still rendered the two overlapping even after
              // the sizing fix. Plain property bindings (`x: sibling.x +
              // sibling.width + gap`) are evaluated by the ordinary QML
              // binding engine, not the positioner's internal layout pass,
              // and were confirmed reliable at this depth throughout this
              // file already (e.g. the explicit height bindings above).
              readonly property int controlTypeRowHeight: Style.space(18)

              Column {
                width: parent.width
                height: visible ? (Style.space(18) + Style.space(4) + parent.controlTypeRowHeight) : 0
                visible: isWindowControls
                spacing: Style.space(4)
                topPadding: Style.space(4)

                Text {
                  height: Style.space(18)
                  text: "Control Type"
                  color: root.features["window-controls"] === true ? Color.foreground : Util.alpha(Color.foreground, 0.4)
                  font.family: Style.font.family
                  font.pixelSize: Math.max(9, Style.font.title - 4)
                  font.bold: true
                }

                Item {
                  id: controlTypeOptions
                  width: parent.width
                  height: parent.parent.controlTypeRowHeight
                  readonly property bool rowActive: root.features["window-controls"] === true
                  readonly property int circleSize: Style.space(12)
                  readonly property int labelGap: Style.space(6)
                  readonly property int optionGap: Style.space(16)

                  Rectangle {
                    id: solidCircle
                    x: 0
                    y: (parent.height - height) / 2
                    width: parent.circleSize
                    height: parent.circleSize
                    radius: width / 2
                    color: root.controlStyle === "solid" ? Color.accent : "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: parent.rowActive ? Util.alpha(Color.foreground, 0.5) : Util.alpha(Color.foreground, 0.25)
                  }

                  Text {
                    id: solidLabel
                    x: solidCircle.x + solidCircle.width + parent.labelGap
                    y: 0
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "Solid Colors"
                    color: parent.rowActive ? Color.foreground : Util.alpha(Color.foreground, 0.4)
                    font.family: Style.font.family
                    font.pixelSize: Math.max(9, Style.font.title - 4)
                    font.bold: root.controlStyle === "solid"
                  }

                  MouseArea {
                    x: solidCircle.x
                    y: 0
                    width: solidLabel.x + solidLabel.contentWidth - solidCircle.x
                    height: parent.height
                    enabled: parent.rowActive
                    onClicked: root.setControlStyle("solid")
                  }

                  Rectangle {
                    id: textCircle
                    x: solidLabel.x + solidLabel.contentWidth + parent.optionGap
                    y: (parent.height - height) / 2
                    width: parent.circleSize
                    height: parent.circleSize
                    radius: width / 2
                    color: root.controlStyle === "text" ? Color.accent : "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: parent.rowActive ? Util.alpha(Color.foreground, 0.5) : Util.alpha(Color.foreground, 0.25)
                  }

                  Text {
                    id: textLabel
                    x: textCircle.x + textCircle.width + parent.labelGap
                    y: 0
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: "Text (Dock, Hoist, Halt)"
                    color: parent.rowActive ? Color.foreground : Util.alpha(Color.foreground, 0.4)
                    font.family: Style.font.family
                    font.pixelSize: Math.max(9, Style.font.title - 4)
                    font.bold: root.controlStyle === "text"
                  }

                  MouseArea {
                    x: textCircle.x
                    y: 0
                    width: textLabel.x + textLabel.contentWidth - textCircle.x
                    height: parent.height
                    enabled: parent.rowActive
                    onClicked: root.setControlStyle("text")
                  }
                }
              }
            }
          }

          Rectangle {
            visible: root.pendingConfirm !== null
            width: parent.width
            height: confirmCol.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Util.alpha(Color.accent, 0.12)

            Column {
              id: confirmCol
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(6)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Color.foreground
                font.family: Style.font.family
                text: "This turns off the last restore surface. Window controls (minimize) will also be turned off. Continue?"
              }

              Row {
                spacing: Style.space(8)
                Button { text: "Cancel"; onClicked: root.cancelPending() }
                Button {
                  text: "Turn off"
                  onClicked: {
                    if (root.pendingConfirm) {
                      root.confirmPending()
                      root.setFeature("window-controls", false)
                    }
                  }
                }
              }
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
