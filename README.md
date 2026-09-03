# ocd — Omarch Classic Desktop

A curl-installable mod for **Omarchy 4.x ("Quattro")** that adds conventional
desktop-UI affordances on top of its Hyprland + Quickshell stack:

- **Window controls** — titlebars with minimize / maximize / close (via [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars))
- **Mouse window management** — border drag-to-resize with no modifier held (Omarchy already binds SUPER+drag move/resize)
- **Dock** — running windows plus your pinned apps, auto-hiding at the bottom edge
- **Exposé** — every window as a live preview, with type-to-search (SUPER+E)
- **Settings panel** — toggle each of the above independently, live

Plugin IDs live under `io.github.fevangelou.ocd.*` — nothing here uses the
`omarchy.*` namespace, which is reserved for first-party plugins.

Everything ships from this one repo. Nothing here depends on a community
dock or Exposé plugin, and none is vendored — install refuses to proceed
(without `--force`) if it detects one already configured, since two docks on
one bar is a bad first impression.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash -s -- --dry-run
```

Run with `--dry-run` first — it prints every mutation the installer would
make and changes nothing. When you're happy with the plan, drop the flag:

```sh
curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash
```

`boot.sh` only checks for `git`, shallow-clones this repo into a temp dir,
and hands off to `install.sh`. All real work — and every flag below — lives
there. Because it's read via a pipe, `boot.sh`/`install.sh` take **zero
interactive input**; everything is flag-driven.

### Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print every mutation, change nothing. Recommended first run. |
| `--force` | Proceed even if a conflicting community dock/Exposé plugin is detected. |
| `--features=list` | Comma-separated subset to enable initially (default: all four). Names: `window-controls`/`titlebars`, `mouse-management`/`mouse`, `dock`, `expose`. Example: `--features=titlebars,expose` |

`--features` only sets the *initial* state of
`~/.config/omarchy/ocd/features.json` — every component still gets
installed. Change it later with `ocd enable/disable <feature>` + `ocd apply`,
or the settings panel (SUPER+, or the "ocd" bar icon).

To install from a branch instead of `main` (for testing):

```sh
OCD_REF=some-branch curl -fsSL .../boot.sh | bash
```

## What it changes

- **Preflight-only** (nothing written): confirms `pacman -Qi omarchy` is
  major version 4, a live Hyprland session, and that `omarchy-shell`
  answers `ping` over IPC. Refuses on anything else.
- **Backup, before any mutation**: every `*.lua` under `~/.config/hypr/`
  plus `~/.config/omarchy/shell.json` are copied to
  `~/.local/state/ocd/backups/<ISO8601>/`. The installer prints the exact
  one-line restore command (`uninstall.sh --restore-backup <timestamp>`).
- **`~/.config/hypr/hyprland.lua`**: touched in exactly one way — a single
  `require("ocd")` appended inside a marker block:
  ```lua
  -- >>> ocd >>>
  require("ocd")
  -- <<< ocd <<<
  ```
  Re-running the installer is idempotent (it greps for the marker first),
  not additive.
- **`~/.config/hypr/ocd.lua`** (new file, entirely ocd's): mouse/resize
  config, the minimize keybind and dispatcher, hyprbars styling/buttons,
  and the Exposé/settings hotkeys. Reads
  `~/.config/omarchy/ocd/features.json` itself on every Hyprland
  (re)load, so toggling a feature never requires rewriting this file —
  just a reload.
- **hyprbars**, via `hyprpm add`/`enable` — see "hyprbars & the Hyprland
  ABI" below.
- **Three Quickshell plugins**, dropped into
  `~/.config/omarchy/plugins/io.github.fevangelou.ocd.{dock,expose,settings}/`
  (Omarchy's documented manual-install location) and enabled over IPC
  (`setPluginEnabled`) — no hand-patching of `shell.json`.
- **`~/.config/omarchy/ocd/`**: `features.json` (the single source of
  truth for what's enabled), `appid-overrides.json` and `dock-pins.json`
  (your data — see below).
- **Never touched**: any file Omarchy owns (`default/hypr/*`,
  `shell/plugins/*`, packaged `config/hypr/*` templates, the other four
  `~/.config/hypr/*.lua` files). `shell.json` is only ever read directly by
  ocd, never hand-patched — all enable/disable goes through the shell's own
  IPC (`setPluginEnabled`), which is also what `omarchy plugin enable/disable`
  uses under the hood.

## Why Omarchy 4.x only

Quattro moved Hyprland config from `.conf` to Lua and changed the plugin
manifest/IPC surface from earlier releases. A half-applied install on 3.x
(or an unknown version) is worse than none, so `install.sh` refuses outright
rather than guessing.

## `ocd apply` — the reconcile loop

`~/.config/omarchy/ocd/features.json` is the **single source of truth** for
what's wanted. The settings panel writes only that file; it performs no
system mutation itself. `ocd apply` (run by the installer, the panel
detached/async, or you by hand) reconciles actual system state to it:

```sh
ocd status                 # print reconciled state
ocd enable dock             # ocd disable dock also works
ocd apply                   # actually make it so
ocd apply --dry-run         # preview the reconciliation
```

`features.json` is safe to hand-edit — follow with `ocd apply`.

**Dependency rule, enforced in both the CLI and the panel:** `window-controls`
(minimize) needs at least one restore surface. You can't enable it with both
`dock` and `expose` off, and turning off the last of the two while
`window-controls` is on prompts for confirmation (panel) or is refused
outright by `ocd enable`/`ocd disable` (CLI) — either way, before a restore
surface actually goes away, every window parked in `special:minimized` is
swept back to a real workspace first. No window is ever strandable.

The settings panel invokes `ocd apply --notify` **detached** — a hyprbars
rebuild after enabling window-controls can take minutes, and the panel must
never block the shell process while that happens. It shows a lightweight
"Applying…" indicator and reports completion via a desktop notification, not
by blocking.

## hyprbars & the Hyprland ABI

hyprbars is a compiled Hyprland plugin, loaded via `hyprpm`. `hyprland-plugins`
ships its own Hyprland-commit → plugin-commit pin table that `hyprpm`
resolves automatically against whatever Hyprland you have installed — ocd
does **not** hand-pin a commit itself (an earlier draft of this tool
intended to; it turned out to fight hyprpm's own mechanism and go stale
immediately, per `RESEARCH.md`). `ocd apply` calls plain `hyprpm add`/`enable`
and, on the documented "headers outdated" failure (stale headers after a
Hyprland upgrade), retries once via `hyprpm update`.

**This build step is the most likely thing to fail**, and it's designed to
fail safely: output streams live rather than being captured, and a failed
hyprbars build leaves window-controls disabled while every other feature —
mouse management, dock, Exposé — is unaffected.

**hyprpm's own interactive-sudo requirement, confirmed on a real machine
during development:** `hyprpm` shells out to `sudo`/`doas`/`run0` *itself*,
internally, for more than one privileged step — the state-store bootstrap
on first-ever use, and (every time it has to build against a fresh Hyprland
checkout) installing the headers it just compiled via `sudo make ...
installheaders`. `hyprpm` explicitly refuses to be run as root itself
(`sudo hyprpm ...` fails with "Don't run hyprpm as a superuser"), so `ocd`
never wraps it in `sudo` — and each of those internal prompts needs a real
interactive terminal to read a password from. Run non-interactively (a
`curl|bash` install, `ocd apply` from the settings panel, or an agent
driving a shell with no attached TTY), any of these steps can fail — you'll
see "Failed to run a superuser cmd" or "Headers missing" in the streamed
`hyprpm` output. `ocd` handles this exactly like any other hyprbars build
failure: window-controls stays disabled, `features.json` reflects that
honestly, and every other feature is unaffected. If you hit this: open a
real terminal yourself and run

```sh
hyprpm list        # one-time state-store bootstrap, if needed
hyprpm update       # builds/installs headers, if needed — approve any sudo prompt
```

then re-run `ocd apply`. None of this is ocd-specific — any tool driving
`hyprpm` non-interactively hits the same thing, and it's why `install.sh`
cannot fully guarantee a working titlebar on the very first run on every
machine; everything else it does (mouse management, dock, Exposé, the
settings panel) does not depend on this at all.

One more `hyprpm` rough edge hit during development, past the two above: on
this Hyprland (0.56.2), after headers built successfully it still failed
with **"Failed to write plugin state"** — its own per-user state directory
(`/var/cache/hyprpm/<user>/`, holding `state.toml`) had ended up entirely
`root`-owned from the earlier privileged bootstrap, and ordinary
`enable`/`update` calls write `state.toml` unprivileged (no further sudo
prompt). Fix, one-time:

```sh
sudo chown -R "$(whoami):$(whoami)" /var/cache/hyprpm/"$(whoami)"
```

then re-run `ocd apply`. **This was confirmed to fully resolve it** — after
the chown, `hyprbars` built, loaded, and `ocd apply` reported all four
features (`window-controls`, `mouse-management`, `dock`, `expose`) `true`,
verified via both `hyprctl plugin list` and `ocd status` on a real machine.

**After every Omarchy update:**

```sh
hyprpm update
ocd apply
```

If Omarchy's own `omarchy-refresh-hyprland` / config-reset flow is ever run
by hand, it rewrites all five of your `~/.config/hypr/*.lua` files
(including `hyprland.lua`) from the packaged templates — your `require("ocd")`
hook line goes with it, same as any other personal customization in those
files. Re-running the installer (or a future `ocd apply` once it detects the
hook is missing) restores it; this is a known, narrow gap in Omarchy's
current update model, not an ocd bug — see `RESEARCH.md` §1 for the exact
mechanism and what was checked.

hyprbars retinting on an Omarchy theme switch: colors are set once, in
`ocd.lua`, from a small fixed palette — Omarchy's theme switcher doesn't
currently expose a stable Lua-readable "current theme" source ocd could hook
into live. A `hyprctl reload` (which `ocd apply` triggers) re-applies them;
they don't follow a theme switch automatically. Edit the `hl.config({ plugin
= { hyprbars = { ... } } })` block in `~/.config/hypr/ocd.lua` directly if
you want different colors.

## Mouse window management: the tiling caveat

Dragging a **tiled** window moves it to swap position with whatever's under
the cursor, not a free move — that's how Hyprland's dwindle/master layouts
interpret a drag, and ocd doesn't change it. ocd deliberately does **not**
force windows into floating mode to work around this: there's no reliable
way to detect "the user started a drag" versus "the user clicked" from Lua
config, so the only way to guarantee free dragging would be forcing every
window floating unconditionally, breaking tiling workflows outright. Float a
window first (Omarchy's existing SUPER+T) if you want to drag it freely.

What ocd *does* add: `general:resize_on_border = true`, so you can resize
from a window's own edge with no modifier held — Omarchy ships this off by
default. SUPER+drag move/resize was already an Omarchy default before ocd
existed; ocd doesn't rebind it.

## Dock and Exposé architecture

Both are separate plugin manifests (not kinds bundled into one), specifically
so they can be enabled/disabled independently — Omarchy's plugin-enable
mechanism (`setPluginEnabled`) operates per plugin id, and dock/expose are
two of ocd's four independently-toggleable features. The settings panel is
its own third manifest (bundling `panel` + `bar-widget` kinds is fine there,
since it isn't independently toggled).

- **Dock** is a `service`-kind plugin owning its own layer-shell surface
  (the same pattern Omarchy's own background plugin uses), not a
  `bar-widget`. A bar-widget would ride wherever the user has dragged the
  bar and couldn't independently auto-hide at a screen edge; a service can.
  Auto-hides by default — zero exclusive zone plus a ~2px always-present
  input strip at the bottom edge, so the tiling area is never permanently
  shrunk. Reserve-space is not currently exposed as a toggle; it's a small
  change to `plugin/dock/Dock.qml`'s `exclusionMode` if you want it.
- **Exposé** is an `overlay`-kind plugin. Capture rides Hyprland's native
  `hyprland-toplevel-export-v1` via Quickshell's `ScreencopyView` — **no
  compositor plugin required**. Previews are still-frame by default; only
  the hovered/keyboard-focused tile is promoted to a live stream, to bound
  GPU cost across a grid of N windows. Every capture stream is torn down
  the instant the overlay closes (the grid's model is emptied, which
  destroys every tile and the `ScreencopyView` each one owned) — this
  wasn't independently benchmarked against a live session, so if you notice
  GPU usage lingering after closing Exposé, that's the first place to look.
- Both surface windows parked in `special:minimized` (the restore path for
  minimize), visually distinguished — dimmed icon in the dock, a
  "minimized" badge in Exposé.
- Screencopy unavailable, or a specific window refuses capture: Exposé
  falls back to an icon + title card, never a black rectangle.

### App-ID matching (Chromium web apps)

Omarchy's Chromium-based web apps report a WM_CLASS/appId like
`chrome-<host>_<path>-<Profile>` (e.g.
`chrome-mail.google.com_mail_u_0-Default`), which won't resolve through a
normal desktop-entry-by-class lookup. ocd carries a small built-in seed map
for Omarchy's stock web apps and merges a user-editable override on top:

**`~/.config/omarchy/ocd/appid-overrides.json`** — flat object keyed by the
exact appId:

```json
{
  "chrome-mail.google.com_mail_u_0-Default": { "name": "Gmail", "icon": "gmail" },
  "some-other-appid": { "desktopId": "org.some.App" }
}
```

Either `desktopId` (resolved through Quickshell's desktop-entry index —
preferred, since it also picks up the entry's real icon) or an explicit
`name`/`icon` pair works; `desktopId` wins if both are present. An
unmatched appId never disappears — it degrades to the window's own title,
then the raw appId, then a generic icon.

**`~/.config/omarchy/ocd/dock-pins.json`** — a JSON array of pinned apps:

```json
[{ "desktopId": "org.mozilla.firefox", "exec": "firefox" }]
```

`exec` is used verbatim (with desktop-entry field codes like `%u` stripped)
if `desktopId` doesn't resolve to a real launch command.

Both files are yours — `uninstall.sh` prompts before deleting them.

## Uninstall

```sh
~/.local/share/ocd/uninstall.sh          # if you no longer have the original checkout
# or, from a checkout:
./uninstall.sh
```

Fully reverts, and is safe to run even after a partially-failed install:

1. Sweeps every window out of `special:minimized` **first**, unconditionally.
2. Strips the marker block from `hyprland.lua`; deletes `ocd.lua`.
3. Disables hyprbars **only if ocd is the one that enabled it** — if it was
   already on before you installed ocd, uninstall leaves it alone (tracked
   via a marker file, not guessed). Same for the `hyprland-plugins` hyprpm
   repo: if ocd added it, the repo itself is left in place (other plugins
   might use it) but you're told how to remove it (`hyprpm remove
   hyprland-plugins`) if you want it gone too.
4. Removes all three Quickshell plugins (`omarchy plugin remove <id> --yes`,
   falling back to manual `setPluginEnabled false` + directory removal if
   the CLI is unavailable).
5. Prompts before deleting `~/.config/omarchy/ocd/` (`features.json`,
   `appid-overrides.json`, `dock-pins.json` — your data). `--yes` skips the
   prompt; a non-interactive shell defaults to leaving it in place rather
   than guessing.
6. Removes `~/.local/share/ocd` and the `~/.local/bin/ocd` symlink.

Flags: `--dry-run`, `--yes`, `--restore-backup TIMESTAMP` (also restores
`~/.config/hypr/*.lua` and `shell.json` wholesale from a named backup,
instead of just stripping ocd's own marker — see `~/.local/state/ocd/backups/`).

## Logs

Every mutation ocd makes is logged to `~/.local/state/ocd/install.log`,
across install, apply, and uninstall.

## Known limitations / not independently verified

Quattro shipped after this tool's own research pass; `RESEARCH.md` records
exactly what was confirmed against live upstream sources versus what's a
reasoned best guess flagged in code comments where it appears. Beyond that,
`install.sh` (not just `--dry-run`) was actually run end-to-end on a real
Omarchy 4.0.2 machine during development — several real bugs were found and
fixed this way that a dry-run or a code read alone would have missed:
hyprbars config crashing Hyprland's *entire* config when the plugin failed
to load (not just window-controls — fixed by gating that whole block on the
plugin actually being loaded, not just the feature flag), the settings
plugin never getting enabled (nothing called `setPluginEnabled` for it
specifically), and a wrong color token (`Color.text` doesn't exist; fixed to
`Color.popups.text` / `Color.foreground` depending on surface — see
`plugin/*/`).

**The most significant bug found this way**: restoring a minimized window
didn't work at all — SUPER+H would minimize a window fine, but nothing
could bring it back (not the dock, not Exposé, not `ocd apply`'s own
sweep). Root cause: this Hyprland (0.56.2) no longer accepts the classic
`hyprctl dispatch <name> <comma,args>` CLI form at all — it's now parsed as
Lua and a raw string like `movetoworkspace 1,address:0x...` is a syntax
error. Every restore path shelled out to exactly that broken form. Fixed by
switching to `hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace =
'<id>', window = 'address:<addr>'}))"` (and `hl.dsp.focus({window =
'address:<addr>'})` to refocus) — confirmed correct live, including the
non-obvious part that the targeting field is named `window`, not `address`
(which is silently accepted and silently ignored, targeting the currently
focused window instead of the one you asked for). See `RESEARCH.md`'s
addendum for the full diagnostic trail. This affected `lib/minimize.sh`,
`plugin/dock/Dock.qml`, and `plugin/expose/Expose.qml`, all now fixed and
confirmed against real minimized windows on the test machine. hyprbars's
own titlebar-button actions (`hypr/ocd.lua`'s `hl.plugin.hyprbars.add_button`
calls) go through a separate code path inside the hyprbars plugin binary,
not this CLI layer, and were not confirmed to be affected.

**Update: hyprbars was confirmed fully working end-to-end** on the test
machine — after the `hyprpm` state-store ownership fix above, `ocd apply`
reported `window-controls=true, mouse-management=true, dock=true,
expose=true`, and `hyprctl plugin list` independently confirmed hyprbars
loaded ("A plugin to add title bars to windows"). Every failure mode hit
along the way (missing `cmake`, missing `meson`/`ninja`, the state-store
bootstrap, the interactive header-install step, the state-directory
ownership bug) was handled by ocd exactly as designed while working through
it — clear warning, `features.json` stayed honest, config kept verifying,
nothing else broke. `hyprctl layers` also independently confirmed the
dock's and Exposé hot-corner's layer-shell surfaces exist and are
positioned exactly where the QML declares (dock: full-width strip at the
bottom edge; hot corner: 2×2px at the top-right) — both plugins are
genuinely running, not just "enabled" in name.

Still open, in descending order of how much you'd notice:

- **A cosmetic QML warning remains in Exposé**: `Color.popups.text` (used
  for the search box, empty-state text, and window-tile title) logs `Unable
  to assign [undefined] to QColor` at runtime, even though
  `shell/Commons/Color.qml` defines `popups.text` as a real
  always-populated `color` property with a fallback that should never be
  `undefined` — confirmed by reading that file directly, and confirmed the
  deployed plugin file already uses the correct token name, so this isn't a
  typo. It doesn't block anything — dock and Exposé both loaded and
  registered correctly (`omarchy plugin validate` passes, `omarchy-shell
  shell listPlugins` shows both `enabled: true`, and the layer-shell
  surfaces are confirmed live) — but the affected text's rendered color may
  not match the theme. If you hit this, it's worth checking whether `Color`
  (a `pragma Singleton`) gets a fresh, differently-initialized instance for
  a plugin loaded from `~/.config/omarchy/plugins/<id>/` versus one loaded
  from `shell/plugins/` — that's the most likely explanation given the
  token name itself is verified correct.
  **A second, independent instance of the same pattern was found and
  worked around**: `plugin/settings/Settings.qml`'s popup tried
  `Style.bar.sizeHorizontal` (the bar's real configured thickness, also a
  real, verified property on a `qs.Commons` singleton) to size its top
  margin below the bar — confirmed live, via the actual rendered layer
  geometry (`hyprctl layers`), that it evaluated to the same as leaving it
  out entirely (i.e. `undefined`/0), while `Style.space(n)` — a plain
  function call on the same singleton, not a nested object property —
  works everywhere it's used across every ocd plugin. That's a second data
  point narrowing the shape of the bug: it looks specifically like nested
  `QtObject` sub-properties (`Color.popups`, `Style.bar`, ...) of a
  `qs.Commons` singleton don't resolve correctly for a plugin loaded from
  `~/.config/omarchy/plugins/<id>/`, while top-level properties and
  function calls on the same singleton do. Worked around in `Settings.qml`
  with a fixed `Style.space(40)` top margin instead.
- `Hyprland.toplevels.values`, `WlrKeyboardFocus` enum members beyond
  `.None`, and `Quickshell.iconPath`'s exact signature are used based on
  standard Quickshell/wlr-layer-shell idioms, not a line-by-line source
  read of this Quickshell version's QML types.
- The dock's hover-to-reveal interaction (mouse actually entering the 2px
  strip and the `Behavior on anchors.bottomMargin` animation sliding it
  into view), Exposé's live-preview grid contents, and the settings panel's
  toggle UI were not interactively clicked through by a human during
  development — the surfaces are confirmed to exist and be positioned
  correctly (see above), and the underlying restore-from-minimized mechanism
  is now confirmed correct against real minimized windows (see the dispatch
  bug above), but "hover it and watch it animate in" / "click a tile and
  watch it actually restore" wasn't eyeballed end-to-end through the UI
  itself.
- hyprbars titlebar buttons (close/maximize/minimize) were not confirmed
  clickable through the actual GUI — hyprbars loading and rendering was
  confirmed (`hyprctl plugin list`), but mouse-click delivery to the
  buttons themselves wasn't independently tested.
- hyprbars live retint and Exposé's capture-teardown GPU cost (see above)
  are documented as design intent, not measured.

`features.json`, `appid-overrides.json`, and `dock-pins.json` are all
plain, hand-editable JSON, and `ocd.lua` / the `plugin/*/` QML are ordinary
files — nothing here is hidden behind a build step, so any of the above is
straightforward to inspect or patch further.

## Prior art / credits

No code from any community plugin is vendored — Component brief required
this to be self-contained. Two repos were read as prior art during
`RESEARCH.md`'s research pass:

- [`gardnmi/omarchy-minimize`](https://github.com/gardnmi/omarchy-minimize)
  (MIT) — minimize-to-special-workspace plus a hover-triggered live preview.
  Exposé's "still-frame by default, promote to a live capture stream only
  while hovered/focused, tear the stream down on close" approach is
  independently implemented here but follows the same shape as this
  project's technique; credited accordingly.
- [`rosakodu/omarchy-dock`](https://github.com/rosakodu/omarchy-dock) (MIT)
  — a bar-widget dock with its own separate pin-list file. ocd's dock is
  architecturally different (a `service` plugin, inline-`shell.json`-free
  pin storage for the same underlying reason this repo's dock isn't a
  bar-widget), but its existence confirmed Chromium PWA icon matching is a
  problem worth a dedicated override map.

## License

MIT — see `LICENSE`.
