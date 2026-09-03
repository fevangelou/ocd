# AGENTS.md — working notes for continuing ocd development

This file is for an AI agent (or future you) picking this project back up in
a fresh session, possibly on a different machine. `README.md` is the
user-facing doc; this one is the internal one — architecture, the live-test
loop, and every non-obvious gotcha hit during development so they don't get
rediscovered the hard way. The project's original pre-implementation
research pass (`RESEARCH.md`, now folded into this file and removed) checked
every upstream claim below against a fetched source rather than relying on
model memory, since Omarchy Quattro shipped after the model's training
cutoff — the confirmed facts worth keeping are under "Confirmed upstream
facts" below.

## What this project is

ocd ("Omarch Classic Desktop") is a curl-installable mod for Omarchy 4.x
("Quattro") — see `README.md` for the pitch and feature list. One thing
worth internalizing beyond the README: the target user for this project is
explicitly someone *migrating from Windows/macOS/Ubuntu/Fedora*, not an
existing Hyprland power user. Every UX decision should be judged against
"does this feel familiar to someone who's never touched a tiling WM," not
"is this the most idiomatic Hyprland way to do it."

## Repo layout

- `bin/ocd`, `lib/*.sh` — the CLI and all system-mutation logic (Bash).
  `features.json` is the single source of truth for what's *wanted*;
  `ocd apply` reconciles actual system state to it.
- `hypr/ocd.lua` — installed as `~/.config/hypr/ocd.lua`, hooked into
  `hyprland.lua` via one `require("ocd")` in a marker block. Reads
  `features.json` fresh on every Hyprland (re)load.
- `plugin/dock/`, `plugin/expose/`, `plugin/settings/` — three independent
  Quickshell plugins (QML), each installed to
  `~/.config/omarchy/plugins/io.github.fevangelou.ocd.<name>/`.
- `boot.sh` — the `curl | bash` entry point; shallow-clones the repo and
  hands off to `install.sh`. Both take zero interactive input (everything
  flag-driven), since a pipe has no TTY to read from.

## Development is done live, on a real machine

There is no emulator/CI for this — every change in this project's history
was hand-verified on the user's actual machine (`fe-thinkpad-x280`, user
`fevangelou`, Omarchy 4.0.2). Treat that as the only real verification
available. The deployed copies live at:

- `~/.config/omarchy/plugins/io.github.fevangelou.ocd.{dock,expose,settings}/`
- `~/.config/hypr/ocd.lua`
- `~/.local/share/ocd/` (installed `bin/`, `lib/`, `README.md`,
  `uninstall.sh` — mirrors the repo root)

**The deployed files and this repo must be kept identical.** After editing
a source file here, deploy it with a direct `cp` to the matching path above
(not a full reinstall) and verify:

```sh
cp <repo-file> <deployed-path>
omarchy restart shell
sleep 3
omarchy-shell shell ping                      # expect "ok"
journalctl --user --since "-10 sec" --no-pager \
  | grep -iE "fevangelou|ERROR|WARN scene" | grep -v "sudo\["
hyprctl plugin list | head -2                  # confirms hyprbars survived the restart
```

Known benign log noise (not a regression, seen on every restart):
`WARN qt.qpa.services: Failed to register with host portal QDBusError(...)`
— a portal-registration warning unrelated to ocd. Anything else in that
grep is real and worth chasing down.

Since QML/Lua can't be rendered or clicked from here, the loop is always:
edit → deploy → verify logs are clean → **ask the user to confirm the
actual visual/behavioral result**, since "no errors in the log" only proves
it didn't crash, not that it looks or behaves right.

Before touching a file, it's worth double-checking the deployed copy still
matches the repo (`diff -rq`) — drift can happen if a change was tested live
and not yet committed back, or vice versa.

## QML/Quickshell gotchas (all confirmed live on this Omarchy build)

- **`Row`/`Column` positioners fail silently at deep nesting** (4+ levels,
  e.g. `Column > Repeater > Column > Column > Row`): not just wrong
  implicit size, but wrong child *positioning* (x-offsets), even after
  giving the positioner explicit width/height. The fix that actually works
  at any nesting depth: abandon the positioner for that element and use a
  plain `Item` with explicit, sibling-chained `x`/`y` bindings (e.g.
  `x: solidCircle.x + solidCircle.width + parent.labelGap`). Plain property
  binding evaluation is reliable here; positioner internal layout logic is
  not, past a certain depth. See `plugin/settings/Settings.qml`'s Control
  Type row for a worked example.
- **Nested `QtObject` sub-properties on a `qs.Commons` singleton don't
  resolve for a plugin loaded from `~/.config/omarchy/plugins/<id>/`** —
  e.g. `Color.popups.text` and `Style.bar.sizeHorizontal` both silently
  evaluate to `undefined`, even though both are real, verified properties
  when read from the singleton's own source. Top-level properties and
  function calls on the same singleton work fine (`Color.foreground`,
  `Style.space(n)`). If a color/size looks wrong or missing only on a
  manually-installed plugin, suspect this before anything else. Not fully
  root-caused — two independent instances hit (Exposé's `Color.popups.text`,
  the settings panel's `Style.bar.sizeHorizontal`), both worked around by
  switching to a top-level property/function instead of chasing the root
  cause further.
- **`Style.space(px)`** — the shell's spacing-scale helper
  (`/usr/share/omarchy/shell/Commons/Style.qml`):
  `Math.max(1, Math.round(px * effectiveSpacingScale))`, ≈1:1 px at default
  scale. Use it instead of a bare pixel literal for anything that should
  respect the user's UI scale.
- **Outside-click / focus-loss dismissal**: use `Quickshell.Hyprland`'s
  `HyprlandFocusGrab` (`import Quickshell.Hyprland`), the same mechanism
  first-party `/usr/share/omarchy/shell/Ui/PopupCard.qml` uses — set
  `active` to the popup's open state, `windows` to the list of windows that
  count as "inside," and close on `onCleared`. `PanelWindow`/
  `ProxyWindowBase` has **no** simple keyboard-focus boolean to poll
  instead — confirmed absent from the qmltypes. Gotcha: if the thing that
  *opens* the popup (e.g. a bar icon) lives in a separate plugin
  window with no live QML reference to the popup, it can't be added to
  `windows` the way `PopupCard.qml` adds its own anchor bar — a click on
  that icon while open will clear the grab (closing the popup) and then
  still land on the icon's own click handler, which can immediately reopen
  it. `plugin/settings/Settings.qml` guards this with a short
  timestamp-based debounce (`lastGrabCloseAt`, ~300ms) on the open path —
  copy that pattern for any similar cross-window popup.

## hyprpm / hyprbars gotchas (all confirmed live)

- `hyprctl dispatch <name> <comma,args>` (the classic CLI form) is **no
  longer accepted** on this Hyprland build (0.56.2) — it's parsed as Lua
  now, and a raw string like `movetoworkspace 1,address:0x...` is a syntax
  error. Use `hyprctl eval "hl.dispatch(hl.dsp.window.move({...}))"`
  instead. The targeting field for a specific window is `window`, not
  `address` — `address` is silently accepted and silently ignored,
  targeting whatever's currently focused instead. This bit every restore
  path (`lib/minimize.sh`, `Dock.qml`, `Expose.qml`) before being caught;
  the correct field name was found by triggering Hyprland's own
  argument-validation error (calling with the wrong field name lists the
  real accepted ones). Root-caused via `hyprctl repl`, which prints full
  return values/errors — `hyprctl eval` only prints `ok`/`error`, so use
  `repl` for interactive debugging and `eval` once the call is known-good.
- Related: `Quickshell.Hyprland`'s toplevel `.address` is formatted
  **without** the `0x` prefix that `hyprctl`'s own JSON and window
  selectors (`"address:0x..."`) use — a real window's address was
  `0x55706a59d720` per `hyprctl clients -j`, but the toplevel model reported
  it as `55706a59d720`. Normalize with a `0x` prefix wherever a toplevel
  address feeds a `hyprctl`/`hl.dsp.*` selector (already done in
  `Dock.qml`/`Expose.qml` at the point each reads `t.address`).
- `hyprpm` shells out to `sudo`/`doas`/`run0` **itself**, internally, for
  the state-store bootstrap and for installing headers after a fresh
  Hyprland checkout — it refuses to be run as root itself. Non-interactive
  contexts (curl|bash install, an agent-driven shell, the settings panel's
  detached `ocd apply`) have no TTY for that prompt and will fail with
  "Failed to run a superuser cmd" or "Headers missing." ocd handles this by
  leaving `window-controls` disabled and `features.json` honest — it does
  not try to work around the sudo requirement. If hit, the fix is running
  `hyprpm list` / `hyprpm update` by hand in a real terminal once, then
  re-running `ocd apply`.
- A full `hyprctl reload` unloads hyprpm-managed plugins (hyprbars
  included) even though hyprpm's own state still says "enabled" — always
  follow a reload with `hyprpm reload -n` to re-attach.
- A `state.toml` under `/var/cache/hyprpm/<user>/` left `root`-owned from
  an earlier privileged bootstrap causes "Failed to write plugin state" on
  later unprivileged `enable`/`update` calls. Fix:
  `sudo chown -R "$(whoami):$(whoami)" /var/cache/hyprpm/"$(whoami)"`.
- hyprbars config (`plugin.hyprbars.*` keys, `hl.plugin.hyprbars`) must be
  gated on the plugin actually being loaded right now
  (`if hl.plugin and hl.plugin.hyprbars then ...`), not just on the
  `window-controls` feature flag — an unloaded/failed hyprbars build
  referencing those keys crashes *all* of Hyprland's Lua config load, not
  just window-controls.

## Confirmed upstream facts (from the original research pass)

Omarchy Quattro shipped after the model's training cutoff, so these were
checked against a fetched source rather than recalled, before any
implementation code was written. Still true as of this build; re-verify
against the shell/plugin docs directly if something here stops matching
observed behavior.

- **Third-party plugin install location**: `~/.config/omarchy/plugins/<id>/`
  — a directory per plugin id, picked up by IPC `rescanPlugins`. Confirmed
  live: `omarchy plugin list --json` and `omarchy-shell shell listPlugins`
  return identical JSON (`id`, `name`, `kinds`, `enabled`, `active`,
  `canDisable`, `firstParty`, `clonedFrom`). `shell.json`'s `plugins: []`
  only records *deviations* from default state — several first-party
  widgets showed `enabled: false` there despite `plugins[]` being empty —
  so ocd never hand-patches `shell.json` for enablement; every enable/
  disable goes through IPC (`setPluginEnabled`) or the `omarchy plugin` CLI.
- **`omarchy plugin validate <folder>`** exists and is worth running against
  any manifest before deploying it — confirmed it actually catches a
  deliberately-broken manifest (not a no-op check).
- **A `service`-kind plugin owning its own layer-shell `PanelWindow` is a
  supported, first-party-used pattern**, not just a `bar-widget` — Omarchy's
  own `omarchy.background` plugin does exactly this
  (`shell/plugins/background/Background.qml`). This is why the dock is a
  `service` plugin here rather than a bar-widget: a bar-widget rides
  wherever the user has dragged the bar and can't independently auto-hide
  at a screen edge.
- **Chromium web-app WM_CLASS/appId format**: `chrome-<host>_<path>-<Profile>`
  (`/` → `_`), fixed at window creation — confirmed from an upstream Omarchy
  GitHub discussion on web-app windows. E.g. a Gmail tab at
  `mail.google.com/mail/u/0` reports
  `chrome-mail.google.com_mail_u_0-Default`. This is what
  `plugin/{dock,expose}/AppMatcher.js`'s seed map and
  `appid-overrides.json` schema are built against.
- **hyprbars/hyprpm commit pinning**: `hyprland-plugins` ships its own
  Hyprland-commit → plugin-commit pin table that `hyprpm` resolves
  automatically against whatever Hyprland is installed — ocd deliberately
  does not hand-pin a commit itself (that would fight hyprpm's own
  resolution and go stale immediately). The one failure mode worth handling
  is documented in the hyprpm gotchas above ("Headers outdated").
- **`shell.json` schema**: `version: 1`, `bar.id` selects the active bar,
  one entry per plugin instance (bar widgets under `bar.layout.<section>`,
  everything else under top-level `plugins[]`), settings live **inline on
  the entry** — no `config:` sub-object, no deep-merge with defaults once
  hand-edited. This is why `ocd`'s own settings live in their own files
  (`features.json`, `dock-pins.json`, `appid-overrides.json`) rather than
  inline on a `shell.json` entry, and why `lib/jsonpatch.sh` patches with
  `jq` rather than ever overwriting the file wholesale.
- No community Exposé-style window switcher (live previews + type-to-search)
  existed at research time — `gardnmi/omarchy-minimize` (MIT) is the closest
  prior art (hover-triggered live preview via Quickshell's toplevel-export
  integration, same shape ocd's Exposé independently follows: still-frame
  by default, promote to live only while hovered/focused, tear the stream
  down on close) and `rosakodu/omarchy-dock` (MIT) is a bar-widget dock with
  its own separate pin-list file (ocd's dock instead follows the documented
  inline-`shell.json` convention, and reading `rosakodu`'s pin file is a
  plausible conflict signature to scan for at install time). See the
  README's Acknowledgements section — both are credited there, not
  vendored.

## File header / license convention

Every source file (Bash, Lua, QML, JS) carries this header, comment-syntax
adapted per language (`#`, `--`, or `//` respectively), placed after the
shebang for Bash and at the very top otherwise:

```
/**
 * @version    1.0
 * @package    Omarchy Classic Desktop (OCD)
 * @author     Fotis Evangelou
 * @url        https://github.com/fevangelou/ocd
 * @copyright  Copyright (c) 2026 Fotis Evangelou. All rights reserved.
 * @license    GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
 */
```

Project license is **GPLv3** (`LICENSE`, verbatim from gnu.org — do not
hand-edit it, GPL text is meant to be distributed unmodified). Every
`plugin/*/manifest.json` `"license"` field must say `"GPL-3.0"` to match.
JSON files don't get the comment header (no comment syntax in JSON).

## Repo / remote

GitHub: `fevangelou/ocd` (`https://github.com/fevangelou/ocd`), branch
`main`. No tagged releases yet — `boot.sh` defaults `OCD_REF` to `main`;
override with `OCD_REF=some-branch` for testing an unmerged branch.
