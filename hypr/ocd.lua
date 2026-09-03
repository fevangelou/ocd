-- /**
--  * @version   1.1
--  * @package   Omarchy Classic Desktop (OCD)
--  * @author    Fotis Evangelou
--  * @url       https://github.com/fevangelou/ocd
--  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
--  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
--  */

-- ocd (Omarch Classic Desktop) — Hyprland-side configuration.
--
-- Installed to ~/.config/hypr/ocd.lua and loaded via a single
-- `require("ocd")` appended to the bottom of ~/.config/hypr/hyprland.lua,
-- inside an ocd marker block. This file is self-contained: it never edits
-- any file Omarchy owns, and everything it does is easy to grep back out.
--
-- Feature flags live in ~/.config/omarchy/ocd/features.json and are read
-- fresh every time Hyprland (re)loads this file, so `ocd apply` never needs
-- to rewrite this file — it only needs to trigger a reload.

local FEATURES_FILE = os.getenv("HOME") .. "/.config/omarchy/ocd/features.json"

-- ocd_feature(name): reads features.json via jq. Fails open (returns true)
-- if the file or jq is missing, so a fresh install behaves sanely before the
-- first `ocd apply` has run.
local function ocd_feature(name)
  local f = io.open(FEATURES_FILE, "r")
  if not f then
    return true
  end
  f:close()
  local cmd = string.format("jq -r '.features[%q] // empty' %q 2>/dev/null", name, FEATURES_FILE)
  local handle = io.popen(cmd)
  if not handle then
    return true
  end
  local result = handle:read("*a")
  handle:close()
  result = result:gsub("%s+", "")
  if result == "false" then
    return false
  end
  return true
end

-- ocd_string_setting(jqPath, default): same fail-open shape as ocd_feature,
-- for a top-level (non-boolean, non-"features"-nested) string setting.
local function ocd_string_setting(jqPath, default)
  local f = io.open(FEATURES_FILE, "r")
  if not f then
    return default
  end
  f:close()
  local cmd = string.format("jq -r '%s // empty' %q 2>/dev/null", jqPath, FEATURES_FILE)
  local handle = io.popen(cmd)
  if not handle then
    return default
  end
  local result = handle:read("*a")
  handle:close()
  result = result:gsub("%s+", "")
  if result == "" then
    return default
  end
  return result
end

local mouse_management = ocd_feature("mouse-management")
local window_controls = ocd_feature("window-controls")
local dock_enabled = ocd_feature("dock")
local expose_enabled = ocd_feature("expose")
-- "solid" (default, icon glyphs on colored backgrounds) or "text" — a nod
-- to DHH: close/maximize/minimize become the initials "Halt"/"Hoist"/"Dock"
-- on the same green/yellow/red backgrounds, spelling D-H-H top to bottom.
local control_style = ocd_string_setting(".windowControlsStyle", "solid")

--------------------------------------------------------------------------
-- Component 2: mouse window management
--------------------------------------------------------------------------
-- Omarchy already binds SUPER + mouse:272/273 to hl.dsp.window.drag() /
-- hl.dsp.window.resize() (see default/hypr/bindings/tiling.lua) — that part
-- of "drag to move / drag to resize" ships out of the box and ocd does not
-- rebind it. What's missing for a "classic" feel is resizing from a
-- window's own border with no modifier held, which Omarchy ships disabled
-- (general.resize_on_border = false in the default looknfeel). ocd turns
-- it on. hl.config() sets Hyprland variables individually (each leaf maps
-- to one `section:key` variable, same as the .conf era) so this only
-- touches resize_on_border — it does not reset gaps, borders, or anything
-- else general.* already has set.
if mouse_management then
  hl.config({
    general = {
      resize_on_border = true,
    },
  })
end

-- Deliberately NOT forcing floating on drag. Hyprland's tiling layouts
-- (dwindle/master) interpret a drag on a tiled window as a swap, not a free
-- move — that's a real limitation, not a bug, and is documented in the
-- README. Auto-floating on every drag would be a bigger surprise than the
-- swap itself: there is no clean way to detect "the user started a drag"
-- distinct from "the user clicked" from Lua config, so we'd have to force
-- windows floating unconditionally (breaking tiling workflows) rather than
-- only during a drag. Users who want freeform drag on a given window can
-- float it first with Omarchy's existing SUPER+T toggle.

-- Cursor-warp-on-focus is Hyprland's default (cursor:no_warps = false):
-- whenever focus changes programmatically (not by the cursor moving over
-- the window itself), Hyprland warps the cursor to the newly-focused
-- window's center — normally there to keep focus-follows-mouse from
-- immediately fighting a keyboard-driven focus change. It's exactly what
-- made clicking a dock tab or an Exposé tile feel broken: the cursor would
-- jump away from wherever you'd just clicked. Confirmed live (toggled,
-- asked the user to click again, they confirmed it fixed it) before
-- landing here. Scoped to dock/expose rather than applied unconditionally,
-- since those are the two surfaces whose whole point is "click a tab/tile
-- to focus a window you weren't already pointing at" — the only place this
-- warp is actually disruptive.
if dock_enabled or expose_enabled then
  hl.config({
    cursor = {
      no_warps = true,
    },
  })
end

--------------------------------------------------------------------------
-- Component 3: window controls (hyprbars) + minimize
--------------------------------------------------------------------------
-- hyprbars itself is enabled/disabled by `ocd apply` via hyprpm (a
-- compositor plugin load, not something Lua config can do). This section
-- only configures its look and buttons.
--
-- hyprbars config keys and hl.plugin.hyprbars only exist once the plugin is
-- actually loaded. This isn't a no-op when it's absent: Hyprland's config
-- parser rejects unknown plugin:hyprbars:* keys, and calling into a nil
-- hl.plugin.hyprbars crashes Lua config loading outright — taking every
-- other ocd feature down with it, not just window-controls. A failed or
-- not-yet-attempted hyprbars build (see lib/hyprbars.sh) must never do
-- that, so the entire block is guarded on the plugin actually being loaded
-- right now, not just on the window-controls feature flag.
--
-- Colors are intentionally plain and centralized here rather than pulled
-- from Omarchy's live theme: hyprbars renders its titlebar at Hyprland
-- config-load time, and Omarchy's theme switcher does not currently expose
-- a stable Lua-readable "current theme colors" source ocd could hook into.
-- Retinting therefore requires a config reload (`ocd apply`, or Omarchy's
-- own theme switch if it triggers one) rather than happening live — see
-- README "Known limitations".
-- Config keys and the button `action` string form are per the *current*
-- hyprwm/hyprland-plugins README (fetched live, not memorized — an earlier
-- version of this file had both wrong): the text-color key is the nested
-- `col.text`, written in Lua as `col = { text = ... }`, not a flat
-- `col_text` (Hyprland rejected that as an unknown config key). And a
-- button's `action` is a full shell command to run on click — the
-- confirmed-correct form is `hyprctl dispatch '<hl.dsp.… call>'`, not a
-- bare classic dispatcher-name fragment like `"killactive"` (which is not
-- how hyprbars 's button actions work at all, confirmed against the
-- README's own Lua example — this was silently inert before, which is
-- almost certainly why the titlebar buttons did nothing even once loaded).
if hl.plugin and hl.plugin.hyprbars then
  hl.config({
    plugin = {
      hyprbars = {
        bar_height = 30,
        bar_color = "rgba(1e1e2eee)",
        bar_title_enabled = true,
        bar_text_size = 11,
        bar_text_font = "sans-serif",
        bar_buttons_alignment = "right",
        bar_padding = 10,
        bar_button_padding = 6,
        col = {
          text = "rgba(cdd6f4ff)",
        },
      },
    },
  })

  if window_controls then
    -- "text" style: close/maximize/minimize become "H"/"H"/"D" — Halt,
    -- Hoist, Dock — on the same colors as "solid", spelling D-H-H bottom to
    -- top (green->yellow->red) as a nod to DHH. hyprbars' own README
    -- confirms `icon` accepts plain text directly, not just icon-font
    -- glyphs — its own Lua example uses icon = "X" and icon = "_".
    local close_icon, maximize_icon, minimize_icon = "", "", ""
    if control_style == "text" then
      close_icon, maximize_icon, minimize_icon = "H", "H", "D"
    end

    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(f38ba8ff)",
      fg_color = "rgba(1e1e2eff)",
      size = 12,
      icon = close_icon,
      action = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(f9e2afff)",
      fg_color = "rgba(1e1e2eff)",
      size = 12,
      icon = maximize_icon,
      action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
    -- Hyprland has no native "minimize": implemented as a silent move to a
    -- private special workspace, same dispatcher the SUPER+H keybind below
    -- uses, just invoked as a shell command instead of a Lua-config bind.
    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(a6e3a1ff)",
      fg_color = "rgba(1e1e2eff)",
      size = 12,
      icon = minimize_icon,
      action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
    })
  end
end

-- Minimize keybind: parity with the titlebar button, but a pure Hyprland
-- dispatcher unrelated to hyprbars — it keeps working even if hyprbars
-- failed to build, same as every other ocd feature.
if window_controls then
  o.bind(
    "SUPER + H",
    "Minimize window",
    hl.dsp.window.move({ workspace = "special:minimized", follow = false })
  )
end

--------------------------------------------------------------------------
-- Component 6: Exposé + Component 7: settings panel — hotkeys
--------------------------------------------------------------------------
-- Both are Quickshell plugins summoned over the shell's own IPC. o.bind
-- routes a plain string dispatcher through hl.dsp.exec_cmd(), so this is a
-- normal shell command, same pattern Omarchy itself uses for its own
-- omarchy-hyprland-* helper scripts.
o.bind(
  "SUPER + E",
  "Toggle Exposé (ocd)",
  "omarchy-shell shell toggle io.github.fevangelou.ocd.expose"
)

o.bind(
  "SUPER + COMMA",
  "Toggle ocd settings",
  "omarchy-shell shell toggle io.github.fevangelou.ocd.settings"
)

-- No floating window rules are added here on purpose: ocd doesn't force
-- any window class into floating mode (see the drag-to-move note above),
-- so there's nothing that needs an accompanying hyprbars:no_bar exemption
-- yet. If you hit a window where the titlebar looks wrong, add a rule to
-- your own hypr/looknfeel.lua with `hyprbars = { no_bar = true }` — see
-- README "Per-window hyprbars exceptions".
