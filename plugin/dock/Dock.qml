// ocd Dock — a `service`-kind plugin owning its own layer-shell surface
// (confirmed pattern: shell/plugins/background/Background.qml does the
// same thing). A service is loaded at startup regardless of the "dock"
// feature flag; ocd apply toggles it in shell.json via setPluginEnabled,
// but this file also re-checks features.json itself on load/refresh so it
// never shows stale UI between a features.json edit and the next apply.
//
// Persistent taskbar, not a floating auto-hide dock: a full-width bar at
// the bottom, always visible, reserving screen space (exclusionMode.Auto —
// same convention Omarchy's own bar uses at the top, confirmed by reading
// shell/plugins/bar/Bar.qml). Each open window gets its own text "tab"
// (no icons, by request) spanning the bar; pinned apps with no running
// instance get a tab too, dimmer, that launches on click. Minimized
// windows keep their tab, visually dimmed with a "(min)" suffix — this is
// the dock's restore surface.
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
  readonly property string overridesPath: configDir + "/appid-overrides.json"
  // dock-pins.json: a plain JSON array of pinned-app entries, each
  // { "desktopId": "<desktop entry id, without .desktop>", "exec": "<Exec= line, used verbatim if desktopId can't be resolved>" }.
  // ocd's own file (not inline on a shell.json entry): the inline-settings
  // convention documented for shell.json is specific to bar-widget kind
  // entries, and the dock is a service kind here, with no confirmed
  // equivalent — see RESEARCH.md.
  readonly property string pinsPath: configDir + "/dock-pins.json"
  readonly property string ocdBin: home + "/.local/share/ocd/bin/ocd"

  property bool dockFeatureEnabled: true
  property var pins: []
  // Unified, ordered list of tabs: pinned-but-not-running apps first, then
  // every window Hyprland knows about (including special:minimized ones).
  // Recomputed explicitly (see recomputeTabs) rather than left as a live
  // binding, since it merges two independently-refreshed data sources.
  property var tabs: []
  // Address (normalized, "0x...") of the currently-focused window, so its
  // tab can be visually distinguished from other running-but-unfocused
  // ones. Kept as plain hyprctl JSON rather than a Quickshell/Hyprland
  // "active toplevel" property, since none was confirmed to exist.
  property string activeAddress: ""

  // Same value shell/Commons/Style.qml documents as its own default
  // (`sizeHorizontal`, 26) — not read from Style.bar.sizeHorizontal itself,
  // which was confirmed live to not resolve for a plugin loaded from
  // ~/.config/omarchy/plugins/<id>/ (see README "Known limitations").
  readonly property int barHeight: Style.space(26)
  readonly property int minTabWidth: Style.space(90)
  readonly property int maxTabWidth: Style.space(220)

  function refreshFeatureFlag() { featureReadProc.running = true }
  function refreshOverrides() { overridesReadProc.running = true }
  function refreshPins() { pinsReadProc.running = true }
  function refreshWindows() {
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    recomputeTabs()
    activeWindowProc.running = true
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "").trim())
          root.activeAddress = (parsed && parsed.address) ? root.ocdNormalizeAddress(parsed.address) : ""
        } catch (e) { root.activeAddress = "" }
      }
    }
  }

  // Quickshell's Hyprland.toplevels reports each window's address WITHOUT
  // the "0x" prefix that hyprctl's own JSON (and its window selectors,
  // "address:0x...") use — confirmed live: restore silently failed every
  // time until this was added, because the selector matched no window.
  function ocdNormalizeAddress(addr) {
    var s = String(addr || "")
    return s.indexOf("0x") === 0 ? s : "0x" + s
  }

  // recomputeTabs: pinned apps (no running instance) + every toplevel,
  // including special:minimized ones. One tab per window, not per app —
  // multiple windows of the same app get their own separate tabs, same as
  // a classic taskbar.
  function recomputeTabs() {
    var list = []
    for (var i = 0; i < root.pins.length; i++) {
      var p = root.pins[i]
      if (dockHasRunningInstance(p.desktopId)) continue
      var resolvedPin = AppMatcher.resolve(p.desktopId, "", typeof DesktopEntries !== "undefined" ? DesktopEntries : null)
      list.push({ kind: "pinned", label: resolvedPin.name, exec: p.exec, desktopId: p.desktopId })
    }
    var raw = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
    for (var j = 0; j < raw.length; j++) {
      var t = raw[j]
      var minimized = !!(t.workspace && t.workspace.name === "special:minimized")
      var appId = t.wayland ? t.wayland.appId : ""
      var resolvedWin = AppMatcher.resolve(appId, t.title, typeof DesktopEntries !== "undefined" ? DesktopEntries : null)
      list.push({ kind: "window", label: resolvedWin.name, address: ocdNormalizeAddress(t.address), minimized: minimized, toplevel: t })
    }
    root.tabs = list
  }

  Process {
    id: featureReadProc
    command: ["jq", "-r", ".features.dock // true", root.configDir + "/features.json"]
    stdout: StdioCollector {
      onStreamFinished: root.dockFeatureEnabled = (String(text || "").trim() !== "false")
    }
  }

  Process {
    id: overridesReadProc
    command: ["cat", root.overridesPath]
    stdout: StdioCollector {
      onStreamFinished: { AppMatcher.loadOverrides(String(text || "")); root.recomputeTabs() }
    }
  }

  Process {
    id: pinsReadProc
    command: ["jq", "-c", ".", root.pinsPath]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text || "").trim()
        try { root.pins = t.length > 0 ? JSON.parse(t) : [] }
        catch (e) { root.pins = [] }
        root.recomputeTabs()
      }
    }
  }

  Process { id: writePinsProc }
  function persistPins() {
    var json = JSON.stringify(root.pins)
    var script = "mkdir -p " + AppMatcher.shQuote(root.configDir) +
      " && printf '%s' " + AppMatcher.shQuote(json) + " > " + AppMatcher.shQuote(root.pinsPath)
    writePinsProc.command = ["bash", "-c", script]
    writePinsProc.running = true
  }

  function addPin(desktopId, exec) {
    for (var i = 0; i < pins.length; i++) if (pins[i].desktopId === desktopId) return
    var next = pins.slice()
    next.push({ desktopId: desktopId, exec: exec || "" })
    pins = next
    persistPins()
    recomputeTabs()
  }

  function removePin(desktopId) {
    pins = pins.filter(function (p) { return p.desktopId !== desktopId })
    persistPins()
    recomputeTabs()
  }

  function isPinned(desktopId) {
    for (var i = 0; i < pins.length; i++) if (pins[i].desktopId === desktopId) return true
    return false
  }

  Process { id: launchProc }
  function launchExec(execString) {
    if (!execString) return
    // Strip desktop-entry field codes (%f %u %U etc.) — we're launching
    // with no file/URL argument context.
    var cleaned = String(execString).replace(/%[fFuUdDnNickvm]/g, "").trim()
    launchProc.command = ["bash", "-c", cleaned + " >/dev/null 2>&1 & disown"]
    launchProc.running = true
  }

  Process { id: focusProc }
  function focusWindow(address) {
    // Was toplevel.wayland.activate() (Quickshell's own protocol-level
    // activate) — confirmed live to be the wrong choice, same bug as
    // Exposé's identically-named issue: if another window was
    // maximized/fullscreened, activate() left it fullscreen and visually
    // on top even after focus moved to the clicked tab. hl.dsp.focus()
    // via hyprctl eval (same mechanism restoreMinimized() below uses) was
    // confirmed to correctly clear the outgoing window's fullscreen state
    // as a side effect of a normal Hyprland-native focus change.
    focusProc.command = ["bash", "-c", "hyprctl eval \"hl.dispatch(hl.dsp.focus({window = 'address:" + address + "'}))\""]
    focusProc.running = true
  }

  Process {
    id: restoreProc
    stdout: SplitParser { onRead: line => console.log("[ocd-dock restore stdout] " + line) }
    stderr: SplitParser { onRead: line => console.log("[ocd-dock restore stderr] " + line) }
    onExited: (exitCode, exitStatus) => console.log("[ocd-dock restore] exited code=" + exitCode + " status=" + exitStatus)
  }
  function restoreMinimized(address) {
    console.log("[ocd-dock] restoreMinimized() called, address=" + address)
    // Same mechanism as lib/minimize.sh's ocd_sweep_minimized: move out of
    // special:minimized to the active workspace, then focus. Quattro's
    // `hyprctl dispatch <name> <args>` CLI form no longer works (it's
    // parsed as Lua and expects an hl.dsp.* dispatcher object, not a raw
    // comma-joined string — confirmed live), so this goes through
    // `hyprctl eval` calling hl.dsp.window.move()/hl.dsp.focus() with a
    // `window` selector ("address:0x...") instead. Shelled out rather than
    // using Hyprland.dispatch() directly since that Quickshell API's exact
    // argument form isn't confirmed, while this hyprctl eval form is.
    var script = "t=$(hyprctl activeworkspace -j | jq -r '.id // 1'); " +
      "hyprctl eval \"hl.dispatch(hl.dsp.window.move({workspace = '$t', window = 'address:" + address + "'}))\"; " +
      "hyprctl eval \"hl.dispatch(hl.dsp.focus({window = 'address:" + address + "'}))\""
    console.log("[ocd-dock] restore script=" + script)
    restoreProc.command = ["bash", "-c", script]
    restoreProc.running = true
  }

  Component.onCompleted: {
    refreshFeatureFlag()
    refreshOverrides()
    refreshPins()
    refreshWindows()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.refreshWindows() }
  }

  // Polling fallback: the Quickshell docs note many Hyprland actions don't
  // send change events, so a modest poll keeps the dock honest even if a
  // specific event class isn't covered by onRawEvent above.
  Timer {
    interval: 4000
    running: true
    repeat: true
    onTriggered: root.refreshWindows()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.dockFeatureEnabled
      color: Util.alpha(Color.background, 0.97)

      WlrLayershell.namespace: "ocd-dock"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Persistent, reserved-space bar — same convention Omarchy's own
      // bar uses (confirmed: shell/plugins/bar/Bar.qml sets
      // ExclusionMode.Auto for its normal, non-hidden state). This is a
      // deliberate change from an earlier auto-hide design: a always-on
      // taskbar is the explicit request, so it costs the same tiling-area
      // shrink the top bar already costs.
      exclusionMode: ExclusionMode.Auto

      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.barHeight

      Rectangle {
        // Thin top separator, matching a taskbar's usual visual break
        // from the desktop above it. Color.popups.border (a nested
        // singleton property) was avoided here on purpose — see the
        // README's "Known limitations" entry on Color.popups.text /
        // Style.bar.sizeHorizontal not resolving reliably for a plugin
        // loaded this way; Color.foreground is a flat property and has
        // been reliable everywhere it's used.
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.max(1, Style.space(1))
        color: Util.alpha(Color.foreground, 0.18)
      }

      Row {
        id: tabsRow
        anchors.fill: parent
        spacing: 1

        readonly property real tabWidth: root.tabs.length > 0
          ? Math.max(root.minTabWidth, Math.min(root.maxTabWidth, width / root.tabs.length))
          : 0

        Repeater {
          model: root.tabs
          delegate: DockItem {
            required property var modelData
            width: tabsRow.tabWidth
            height: tabsRow.height
            label: modelData.label
            pinned: modelData.kind === "pinned"
            running: modelData.kind === "window"
            isMinimized: modelData.kind === "window" && modelData.minimized
            isActive: modelData.kind === "window" && !modelData.minimized && modelData.address === root.activeAddress
            onActivated: {
              if (modelData.kind === "pinned") root.launchExec(modelData.exec)
              else if (modelData.minimized) root.restoreMinimized(modelData.address)
              else root.focusWindow(modelData.address)
            }
          }
        }
      }
    }
  }

  // dockHasRunningInstance: best-effort match between a pinned desktop id
  // and a live window's appId. Desktop ids and appIds don't always agree
  // (Chromium web apps especially), so this is intentionally loose —
  // false negatives just mean a pin and its running window both show up,
  // which is harmless; it never hides a window.
  function dockHasRunningInstance(desktopId) {
    if (!desktopId) return false
    var needle = String(desktopId).toLowerCase().replace(/\.desktop$/, "")
    var raw = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
    for (var i = 0; i < raw.length; i++) {
      var t = raw[i]
      var appId = t.wayland ? String(t.wayland.appId || "").toLowerCase() : ""
      if (appId.indexOf(needle) !== -1 || needle.indexOf(appId) !== -1) return true
    }
    return false
  }
}
