-- /**
--  * @version   1.4
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
-- The on/off switch lives in ~/.config/omarchy/ocd/features.json and is
-- read fresh every time Hyprland (re)loads this file, so `ocd apply` never
-- needs to rewrite this file — it only needs to trigger a reload.

local FEATURES_FILE = os.getenv("HOME") .. "/.config/omarchy/ocd/features.json"

-- ocd_enabled(): reads the single on/off switch from features.json via jq.
-- Fails open (returns true) if the file or jq is missing, so a fresh
-- install behaves sanely before the first `ocd apply` has run.
--
-- Understands both schemas. A v1 file (four independent feature flags) is
-- read as "on unless the user had turned everything off", matching the
-- migration in lib/features.sh — Hyprland may well load this file before
-- `ocd apply` has had a chance to rewrite it.
local function ocd_enabled()
  local f = io.open(FEATURES_FILE, "r")
  if not f then
    return true
  end
  f:close()
  local expr = 'if has("enabled") then (.enabled != false) ' ..
    'else (((.features // {}) | length) == 0 ' ..
    'or (((.features // {}) | to_entries | map(.value) | any))) end'
  local cmd = string.format("jq -r %q %q 2>/dev/null", expr, FEATURES_FILE)
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

-- One switch for the whole mod. Everything below follows it together.
local enabled = ocd_enabled()

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
if enabled then
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
if enabled then
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
-- of ocd down with it, not just the titlebars. A failed or
-- not-yet-attempted hyprbars build (see lib/hyprbars.sh) must never do
-- that, so the entire block is guarded on the plugin actually being loaded
-- right now, not just on ocd being enabled.
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
        bar_height = 28,
        bar_color = "rgba(1e1e2eee)",
        bar_title_enabled = true,
        bar_text_size = 11,
        bar_text_font = "sans-serif",
        bar_buttons_alignment = "right",
        bar_padding = 10,
        bar_button_padding = 12,
        col = {
          text = "rgba(cdd6f4ff)",
        },
      },
    },
  })

  if enabled then
    -- Double-click the bar (anywhere that isn't a button) to toggle
    -- maximize, matching the middle button. `on_double_click` is a plain
    -- shell command, same form as a button's `action` — hyprbars runs it
    -- verbatim. Set in its own hl.config call rather than alongside the
    -- styling above so it only applies while ocd is enabled: hl.config
    -- assigns each leaf to one `section:key` variable, so a second call
    -- touching one key leaves the rest alone.
    hl.config({
      plugin = {
        hyprbars = {
          on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
          -- Buttons are bare colored circles at rest and reveal their
          -- glyphs on hover, so the controls stay minimal until you go
          -- looking for them.
          --
          -- hyprbars has no tooltips (its button struct is just
          -- cmd/colors/size/icon — there is no label field, and no
          -- plugin:hyprbars:* key for one), so this is the supported
          -- equivalent. Note the scope: hyprbars tracks hover as a bitmask
          -- over all buttons and renders every icon when *any* of them is
          -- hovered, so this reveals all three at once rather than
          -- labelling just the one under the pointer.
          icon_on_hover = true,
        },
      },
    })

    -- Red/yellow/green for close/maximize/minimize. Buttons are added
    -- right-to-left, so this renders as minimize, maximize, close.
    --
    -- Glyphs are checked against Liberation Sans, which is what "sans"
    -- resolves to here: hyprbars hardcodes that family for icons
    -- (renderText(..., "sans", ...) in barDeco.cpp) rather than using
    -- bar_text_font, so a glyph missing from it would depend on Pango
    -- fallback. U+2715 ✕ is absent from it; U+00D7 × is present and reads
    -- the same at this size.
    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(f38ba8ff)",
      fg_color = "rgba(1e1e2eff)",
      size = 16,
      icon = "×",
      action = "hyprctl dispatch 'hl.dsp.window.close()'",
    })
    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(f9e2afff)",
      fg_color = "rgba(1e1e2eff)",
      size = 16,
      icon = "□",
      action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    })
    -- Hyprland has no native "minimize": implemented as a silent move to a
    -- private special workspace, same dispatcher the SUPER+H keybind below
    -- uses, just invoked as a shell command instead of a Lua-config bind.
    hl.plugin.hyprbars.add_button({
      bg_color = "rgba(a6e3a1ff)",
      fg_color = "rgba(1e1e2eff)",
      size = 16,
      icon = "─",
      action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']],
    })
  end
end

-- Minimize keybind: parity with the titlebar button, but a pure Hyprland
-- dispatcher unrelated to hyprbars — it keeps working even if hyprbars
-- failed to build, same as every other ocd feature.
if enabled then
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
if enabled then
  o.bind(
    "SUPER + E",
    "Toggle Exposé (ocd)",
    "omarchy-shell shell toggle io.github.fevangelou.ocd.expose"
  )
end

-- Deliberately NOT gated on `enabled`: the settings panel is how ocd gets
-- turned back on. Taking its keybind away along with everything else would
-- leave hand-editing features.json as the only way back.
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
