# RESEARCH.md — Phase 0 findings for `ocd`

Research performed 2026-09-02 against live upstream sources. Omarchy Quattro (v4.0.0)
shipped 2026-08-14 — after the model's training cutoff — so every claim below was
checked against a fetched source, not recalled. No implementation code has been
written.

**Repo location correction:** the task brief's `github.com/basecamp/omarchy` now
301-redirects to **`github.com/omacom/omarchy`** (repo transferred to a new org; the
project itself is unchanged — same DHH-authored release, PR #6231 "Omarchy Quattro").
Both URLs resolve, but all sources below are cited against `omacom/omarchy` as
canonical. Default branch is now `quattro` (it's the mainline, not a feature branch).

---

## 1. `omacom/omarchy` (branch `quattro`) — shell/manifest/config internals

**Manifest schema** (`docs/omarchy-shell.md`, `shell/services/PluginRegistry.qml`,
commit `d3d23fd`) — matches the prompt closely:

- Required: `schemaVersion` (=1), `id`, `name`, `version`, `kinds` (non-empty array),
  `entryPoints` (map of kind → relative QML path).
- `kinds`: `bar`, `bar-widget`, `panel`, `overlay`, `menu`, `service`. Optional
  `keepLoaded: true` persists the plugin between summons/hot-reloads.
- **Confirmed: one manifest can declare multiple kinds.** Real example,
  `shell/plugins/menu/manifest.json`:
  ```json
  "kinds": ["menu", "bar-widget"],
  "entryPoints": { "menu": "Menu.qml", "barWidget": "BarWidget.qml" }
  ```
  So `ocd` should ship **one plugin manifest** with `kinds: ["overlay", "panel",
  "service"]` (Exposé, settings panel, dock-as-service) or split dock into its own
  `bar-widget` manifest if we go that route (see §5 below) — one `entryPoints` key
  per declared kind, each its own QML file.
- **Confirmed: a `service`-kind plugin can own its own layer-shell window.** The
  first-party `omarchy.background` plugin (`shell/plugins/background/manifest.json`)
  is `kinds: ["service"]`, and `Background.qml` directly instantiates a `PanelWindow`
  per screen via `Quickshell.Wayland`:
  ```qml
  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "omarchy-background"
    WlrLayershell.layer: WlrLayer.Background
    exclusionMode: ExclusionMode.Ignore
  }
  ```
  This resolves the prompt's open question in Component 5: a `service` dock plugin
  creating its own `PanelWindow` **is** a supported pattern, not just a bar-widget.
- `barWidget.defaultSection`: `left`/`center`/`right`. `barWidget.allowMultiple`.
  Real-world example with a full settings `schema`/`defaults` block (worth modeling
  our dock's settings on), `shell/plugins/agents/manifest.json`:
  ```json
  "barWidget": {
    "defaults": { "refreshIntervalSec": 900, "syncMode": "Off" },
    "schema": [
      { "key": "refreshIntervalSec", "type": "integer", "min": 30, "max": 3600, ... }
    ]
  }
  ```
  This is the pattern for storing the dock's pin list / overrides inline — confirms
  the prompt's "settings are inline on the widget's shell.json entry" claim.

**IPC methods** (confirmed from `docs/omarchy-shell.md`):
`ping`, `summon <id> <payloadJson>`, `hide <id>`, `toggle <id> <payloadJson>`,
`togglePanelAt <section> <index>`, `call <id> <method> <arg>`, `rescanPlugins`,
`reloadConfig`, `applyTheme`, `toggleBarTransparency`, `setPluginEnabled <id> <bool>`,
`enablePlugin <id> <placementJson>`, `putBarWidget`, `moveBarWidget`, `setBarWidget`,
`listPlugins`, `listShellConfig`, `debugBarGeometry`. `omarchy-shell shell toggle <id>`
(prompt's assumed panel-summon command) is real — confirmed via `toggle`.

**`shell.json` rules** — confirmed exactly as the prompt assumed:
- `version: 1` required, `bar.id` selects the active bar.
- One entry per plugin instance: bar widgets under `bar.layout.<section>`, everything
  else under top-level `plugins[]`. Real example: `{ "id": "community.weather-extra" }`.
- **"Settings are inline on the entry. No `config:` sub-object, no merge layers."**
  Confirmed verbatim in the doc — matches Component 5/8 assumptions exactly.
- Built-ins are disabled via `disabledPlugins: [...]`, not removed from `plugins[]`.
- Once hand-edited, `shell.json` is canonical — no deep-merge with defaults on update.
  Confirms Component 8's "patch with jq, never overwrite" requirement is correct and
  necessary, not overcautious.
- `omarchy plugin remove <id>` exists as a first-party CLI counterpart; not required
  for us but confirms `plugins[]` entries are meant to be programmatically removable.

**Lua config layering** (`config/hypr/hyprland.lua`, `default/hypr/helpers.lua`,
commit `d3d23fd`) — **partial divergence from the prompt:**

- There is **no generic autoload directory or arbitrary-require hook**. The shipped
  `hyprland.lua` requires exactly five fixed user files, in this order, after
  Omarchy's own defaults:
  `hypr.monitors`, `hypr.input`, `hypr.bindings`, `hypr.looknfeel`, `hypr.autostart`.
  A trailing comment invites free-form config at the bottom of the file: *"Add any
  other personal Hyprland configuration below."*
- This means the prompt's plan — append a single marker-wrapped
  `require("ocd")` to the bottom of `hyprland.lua` — is still the right mechanism
  (it's exactly the documented free-form extension point), **but it is not immune
  to being clobbered**: see the `omarchy-refresh-hyprland` finding immediately below.
  No change to Component 4's design is needed; the self-healing/idempotent-reapply
  behavior it already specifies is not a nicety here, it's load-bearing.
- `default/hypr/helpers.lua` exposes a global `o` table: `o.bind`, `o.bind_toggle`,
  `o.exec_on_start`, `o.launch_on_start`, `o.launch`, `o.launch_webapp`,
  `o.launch_webapp_sole`, `o.launch_sole`, `o.window(match, rules)` (wraps
  `hl.window_rule`), `o.notify`, `o.cmd_present`/`o.cmd_missing`,
  `o.preinstalled_bindings_enabled()`. `hl.*` is Hyprland's own Lua API surface,
  assumed globally available. `ocd.lua` should use `o.bind` for keybinds and
  `o.window` for the float-on-drag window rule rather than hand-rolling `hl.*` calls,
  to stay stylistically consistent and survive Omarchy's own Lua API changes better.

**`bin/omarchy-refresh-hyprland` / migrations** — **material finding, changes how we
talk about risk, not the design:**
- `omarchy-refresh-hyprland` unconditionally overwrites *all six* user Hyprland Lua
  files (`hyprland.lua`, `monitors.lua`, `input.lua`, `bindings.lua`, `looknfeel.lua`,
  `autostart.lua`) via `omarchy-refresh-config`, which backs up the previous file
  (`<file>.bak.<epoch>`) and diffs it for the user before replacing it wholesale.
  This is a **user-invoked escape hatch** (also reachable indirectly through a
  reset/repair flow), not something `pacman -Syu` runs automatically.
- Checked all 103 files under `migrations/` for calls to `omarchy-refresh-hyprland`
  or `omarchy-refresh-config hypr/hyprland.lua`: **zero hits.** No migration
  currently rewrites `hyprland.lua` during a version upgrade.
- Net effect: our marker-block hook survives ordinary `pacman -Syu` / Omarchy
  updates, but is wiped if the user manually runs the refresh/reset command. `ocd`
  already plans to grep-and-append idempotently; the README should say explicitly:
  *"If you ever run `omarchy-refresh-hyprland` or reset your Hyprland configs, our
  hook line is removed along with your other customizations — run `ocd apply` (or
  re-run the installer) to restore it."* This is a one-line consequence, not a
  redesign.

---

## 2. Community prior art (Dock / Exposé-adjacent)

`omarchyplugins.com` **redirects to `plugins.omarchy.org`**, which currently lists
**0 community plugins** — the marketplace is new/empty. Real prior art was found via
GitHub search and `aorumbayev/awesome-omarchy` instead:

- **`gardnmi/omarchy-minimize`** (MIT). Directly the closest prior art to two of our
  components at once:
  - Minimize parks windows on a **private special workspace**,
    `special:omarchy-minimized` — same technique the prompt specifies
    (`special:minimized`), just a different name. Restores by Hyprland window
    address.
  - Live preview: *"While a chip is hovered, Quickshell requests a local live
    compositor export of that exact window to render its preview"* — i.e. Quickshell's
    built-in Hyprland toplevel-export integration, generated on demand and discarded
    when the preview closes. This validates the prompt's "tear down every capture
    stream the moment [it] closes" requirement — it's already the pattern this
    plugin uses for a single chip; Exposé just needs it fanned out to N previews and
    torn down together on close.
  - App matching: resolves desktop-entry metadata/icons "from the local application
    database and icon theme" keyed on the app ID Hyprland's toplevel model reports —
    no custom Chromium web-app logic described, i.e. it does *not* solve the
    `chrome-app` ID problem; ours still has to.
  - License is MIT — safe to read for technique, cite in README if we lift any
    approach (we are not vendoring code per the brief, but the "hover → live export,
    discard on close" pattern is worth crediting as inspiration).

- **`rosakodu/omarchy-dock`** (MIT © 2026 rosakodu). Bar-widget dock, not a standalone
  service. Tracks windows via direct Hyprland IPC (not the Quickshell foreign-toplevel
  abstraction). Notable divergence from our plan: it stores its pin list in a
  **separate file**, `~/.config/omarchy/dock-pinned.json`, rather than inline on the
  `shell.json` widget entry. Since `docs/omarchy-shell.md` explicitly documents inline
  settings as the supported pattern (§1 above) and our conflict-detection logic needs
  to read pin state directly out of `shell.json` for the reconcile loop, `ocd` should
  still follow the prompt's inline-on-`shell.json` design rather than copy this — but
  it means a `dock-pinned.json`-style file is a plausible **conflict signature** to
  scan for at install time (evidence a community dock is/was configured), alongside
  scanning `shell.json`'s `plugins[]`/`bar.layout` for foreign dock/expose plugin IDs.
  It confirms Chromium PWA icon matching is a known pain point other authors have
  independently built solutions for ("Full Web Apps (PWA) Support" via "automatic
  domain matching").

- **`sanjyay/Mirador`** — a workspace-level overview ("visual overview of workspaces
  and their windows"), not a per-window Exposé/switcher. Same category problem the
  prompt already warned about with `hyprexpo`: useful to know it exists (so our
  conflict scan should probably not flag it as an Exposé conflict — it doesn't do
  type-to-search window activation), but not prior art for what we're building.

No dedicated community "Exposé"/window-switcher plugin with live previews + type-to-
search was found to exist yet. `ocd`'s Exposé appears to be new ground, not a reinvention.

---

## 3. `hyprwm/hyprland-plugins`, hyprbars

- Config form confirmed: `plugin { hyprbars { bar_height, bar_color,
  bar_title_enabled, bar_text_size/font/weight, bar_buttons_alignment, bar_padding,
  bar_button_padding, on_double_click, ... } }`, plus
  `hyprbars-button = bgcolor, size, icon, on-click, fgcolor` lines. Lua form:
  `hl.plugin.hyprbars.add_button({ bg_color, fg_color, size, icon, action })`.
  Per-window rules: `hyprbars:no_bar`, `hyprbars:bar_color`, `hyprbars:title_color`.
- **Divergence from the prompt's Component 3 instruction** ("pin to a commit known to
  build against the detected Hyprland, not HEAD"): `hyprland-plugins` already ships
  its own **commit-pin table** (Hyprland-commit → plugin-commit pairs) that `hyprpm`
  consults automatically on `hyprpm add`/`hyprpm update` — it resets the plugin to
  whatever commit matches the caller's installed Hyprland build. We do not need to
  (and should not) hardcode our own commit pin; that would fight hyprpm's own
  resolution and go stale immediately. What we *do* need to handle is hyprpm's
  documented failure mode: after a Hyprland upgrade the installed plugin headers go
  stale and `hyprpm add`/`enable` fails with **"Headers outdated"** until `hyprpm
  update` re-fetches/rebuilds. `install.sh` should catch that specific failure,
  attempt `hyprpm update` once, and only then give up with the stream of build output
  intact — this satisfies "leave everything else intact and reversible" more
  precisely than a hand-pinned commit would.
- ABI is verified at load time via both sides exporting
  `__hyprland_api_get_hash()` — a hard mismatch is refused by Hyprland itself, so a
  botched pin can't silently load; it'll fail loud, which is the safe direction.

---

## 4. Quickshell APIs (Hyprland integration, capture, desktop entries)

Confirmed via `quickshell.org/docs` (v0.3.0 series; Arch ships `quickshell 0.3.1-1`):

- `Quickshell.Hyprland`: `HyprlandToplevel`, `HyprlandWorkspace`, and a global
  `Hyprland` singleton with explicit refresh methods — the docs flag that "many
  actions... don't send events," i.e. some state needs an explicit refresh call
  rather than assuming reactive updates, relevant to keeping the dock's window list
  in sync.
- `Quickshell.Wayland`: **`ScreencopyView`** is the concrete type for live window
  capture. It requires compositor support for `hyprland-toplevel-export-v1` (Hyprland
  has this natively — confirms "no compositor plugin required" for Exposé).
  `live` video mode defaults to **false** (still-frame capture) and must be
  explicitly enabled for a continuously-updating preview — worth using still-frame
  by default in the Exposé grid and only promoting the focused/hovered tile to live,
  mirroring `omarchy-minimize`'s hover-triggered pattern, to bound GPU cost.
- Foreign toplevel management goes through `zwlr-foreign-toplevel-management-v1`,
  which Quickshell also uses for its own session-lock window enumeration — same
  protocol the prompt assumed for the dock's window list.
- Desktop-entry index / icon provider APIs exist under Quickshell's standard library
  (`DesktopEntries`, icon theme lookup) — did not find anything Omarchy-specific
  layered on top; `ocd`'s app-ID override map is genuinely new work, not something
  Quickshell or Omarchy already solves for Chromium web apps.

---

## 5. Chromium web-app ID format — confirmed, and the prompt's example is wrong

From an `omacom/omarchy` GitHub discussion on web-app windows (#8657):

> WM_CLASS is `chrome-<host>_<path>-<Profile>` with `/` → `_`, fixed at window creation.

So a Slack web app opened at the root would report something like
`chrome-app.slack.com_-Default`, and a Gmail tab at `mail.google.com/mail/u/0` would
report `chrome-mail.google.com_mail_u_0-Default` — **not**
`chrome-app.slack.com__-Default` as the task prompt guessed (the prompt's example has
an extra underscore and the general shape is right but not exact). This matters
because our override map's *defaults* need to match real IDs, not guessed ones. I did
not enumerate Omarchy's actual stock web-app list (bin/omarchy-webapp-install or
similar) — that's implementation-phase work, not research-phase, but the format
string above is confirmed and should replace the prompt's example when we seed
default map entries.

---

## 6. Version detection

`omacom/omarchy` tag `v4.0.0`, released 2026-08-14, is the "Quattro" release (PR
#6231, "Omarchy Quattro" by dhh). This confirms the major-version-4 gate is correct
in principle. I did not have a live Quattro install to check the literal
`pacman -Qi omarchy` `Version` field string — that should be a quick manual check at
implementation time (expect something like `4.0.0-1`; parse the leading integer
before the first `.`).

---

## Divergences from spec requiring a decision

1. **App-ID override map defaults** should use the confirmed format
   `chrome-<host>_<path>-<Profile>` (§5), not the prompt's example string. Low-risk,
   proceeding without asking — this only affects seed data, not architecture.

2. **hyprbars commit pinning** (§3): the prompt says to pin to a specific known-good
   commit ourselves. Real upstream mechanism is hyprpm's own commit-pin table, which
   already does this per the caller's installed Hyprland. Recommend: **do not
   hand-pin a commit** — call plain `hyprpm add <repo>` / `hyprpm enable hyprbars`
   and handle the "Headers outdated" failure explicitly (retry once via `hyprpm
   update`, otherwise fail loud and leave the rest of the install intact). This is a
   deviation from an explicit prompt instruction, so flagging it rather than just
   doing it silently.

3. **Dock as `service` vs `bar-widget`** (§1): the prompt asks us to default to
   `bar-widget` "if uncertain." We're no longer uncertain — `service`-owned
   `PanelWindow`s are a confirmed, first-party-used pattern (`omarchy.background`).
   Recommend building the dock as a **`service`** plugin with its own layer-shell
   surface (needed anyway for auto-hide + hover strip behavior at the screen edge,
   which a bar-widget riding inside the existing bar can't do independently of where
   the user has dragged the bar). Flagging because it overrides the prompt's stated
   default.

4. **Single vs. multiple manifests**: confirmed one manifest can carry multiple
   `kinds`. Proposal: one `ocd` manifest with `kinds: ["overlay", "panel", "service"]`
   covering Exposé + settings panel + dock-as-service-with-window, each with its own
   `entryPoints` value. This matches the prompt's stated preference
   ("prefer one plugin with multiple entry points... if the schema allows it") — not
   a divergence, just confirming the plan is unblocked.

5. **`hyprland.lua` hook fragility** (§1): not a design change, but the README must
   document that `omarchy-refresh-hyprland` (a user-invoked command) wipes our hook
   line along with the user's other Hyprland customizations, and that `ocd apply`
   restores it. Worth the user's explicit sign-off since it's a real (if narrow)
   failure mode of the chosen approach, and the alternative — hooking a different one
   of the five fixed files — has the identical exposure, so there's no strictly safer
   choice within Omarchy's current design.

## Addendum (implementation phase)

Four things discovered while implementing, after this research pass closed,
recorded here for traceability:

- **`Quickshell.Hyprland`'s toplevel `.address` is formatted without the
  `0x` prefix that `hyprctl`'s own JSON (`.address` field) and its window
  selectors (`"address:0x..."`) both use.** Confirmed live via debug
  logging: a real window's address was `0x55706a59d720` per `hyprctl
  clients -j`, but `Hyprland.toplevels.values[i].address` fed a restore
  command that built the selector `address:55706a59d720` (no `0x`) — which
  matched no window, so `hl.dsp.window.move()`/`hl.dsp.focus()` silently
  no-op'd (move) or warned `window not found` (focus) on every attempt, no
  matter how many times the user clicked. This is a Quickshell-vs-hyprctl
  formatting mismatch, not a Hyprland dispatch issue — fixed by normalizing
  with a `0x` prefix at the point `t.address` is read into `plugin/dock/
  Dock.qml`'s and `plugin/expose/Expose.qml`'s data models.

- **`hyprctl dispatch <name> <args>` (the classic comma-joined-string CLI
  form) no longer works on this Hyprland (0.56.2)** — it's now parsed as
  Lua source (`hl.dispatch(<name> <args>)`, literal token concatenation,
  not a real function call), so a raw string like `movetoworkspace
  1,address:0x...` fails with a Lua syntax error. This broke every restore-
  from-`special:minimized` path (`lib/minimize.sh`'s sweep, and the dock's
  and Exposé's click-to-restore), while `hypr/ocd.lua`'s config-time
  `o.bind(..., hl.dsp.window.move({...}))` binding for the minimize
  keybind itself was unaffected (it never goes through this CLI layer) —
  which is exactly why SUPER+H minimize worked but nothing could restore a
  minimized window. Found live, root-caused via `hyprctl repl` (which
  actually prints return values and error messages in full, unlike
  `hyprctl eval` which just prints `ok`/`error` — use `repl` for
  interactive debugging, `eval` for scripting once the call is known-good).
  Confirmed working replacement, live: `hyprctl eval "hl.dispatch(hl.dsp.
  window.move({workspace = '<id>', window = 'address:<addr>'}))"` then
  `hl.dsp.focus({window = 'address:<addr>'})` for focus — the key finding
  being that `hl.dsp.window.move()`'s targeting field for an arbitrary
  (non-focused) window is named **`window`** (a selector string, e.g.
  `"address:0x...")`, not `address` (which is accepted with no error but
  silently ignored, targeting the currently-focused window instead — a
  dangerous silent-no-op failure mode, not a loud one). Discovered the
  correct field name by triggering Hyprland's own argument-validation error
  message via `hl.dsp.focus({address = ...})`, which listed the actual
  accepted field names. hyprbars's own titlebar-button `action` strings
  (`"killactive"`, `"fullscreen,1"`, etc. in `hypr/ocd.lua`) are a separate,
  third code path — evaluated inside the hyprbars plugin binary itself, not
  through this CLI/Lua-eval layer — and were not confirmed to be affected
  or unaffected by this change.

- **Third-party plugin install location**, not covered above: confirmed
  from `docs/omarchy-shell.md` ("Installing a third-party plugin") to be
  `~/.config/omarchy/plugins/<id>/` — a directory per plugin id, picked up
  by IPC `rescanPlugins`. This is what `install.sh`/`uninstall.sh` use.
  `omarchy plugin list --json` and `omarchy-shell shell listPlugins` return
  identical JSON (`id`, `name`, `kinds`, `enabled`, `active`, `canDisable`,
  `firstParty`, `clonedFrom`) — confirmed live against a real Omarchy 4.0.2
  install, where `shell.json`'s `plugins: []` was empty despite several
  first-party widgets showing `enabled: false`, confirming `shell.json`
  really does only record *deviations* from default state, never a full
  mirror of it. `ocd` therefore never hand-patches `shell.json` for
  enablement — every plugin enable/disable goes through IPC
  (`setPluginEnabled`) or the `omarchy plugin` CLI, both exercised live.
- **`omarchy plugin validate <folder>`** exists and was run against all
  three of ocd's manifests (`plugin/dock`, `plugin/expose`,
  `plugin/settings`) on that same live machine — all three pass; a
  deliberately-broken manifest was confirmed to fail it, so the pass isn't
  a false negative from the tool being a no-op.
- `install.sh --dry-run` and `uninstall.sh --dry-run` were both run
  end-to-end on that live Omarchy 4.0.2 machine (preflight, conflict scan,
  backup planning, hyprbars/shell-plugin reconciliation, `Hyprland
  --verify-config`) and confirmed to make zero filesystem changes outside
  the log file. `lib/features.sh`'s dependency-graph guard and
  `lib/markers.sh`'s append/remove idempotency were also exercised directly
  against real `jq`/`hyprctl` output in an isolated `$HOME`.

## Sources

- https://github.com/omacom/omarchy (formerly basecamp/omarchy, 301-redirects), branch `quattro`, commit `d3d23fd` (HEAD at research time)
  - `docs/omarchy-shell.md`
  - `shell/services/PluginRegistry.qml`
  - `shell/plugins/{bar,background,osd,reminders,menu,notifications,polkit,lock,clipboard,emojis,image-picker,dev-gallery,agents,panels/audio}/manifest.json`
  - `shell/plugins/background/Background.qml`
  - `default/hypr/helpers.lua`
  - `config/hypr/hyprland.lua`
  - `bin/omarchy-refresh-hyprland`, `bin/omarchy-refresh-config`
  - `migrations/*.sh` (all 103 files, grepped for refresh-hyprland calls)
  - `manual/32-shell-plugins.md`
  - https://github.com/omacom/omarchy/releases/tag/v4.0.0
  - https://github.com/omacom/omarchy/pull/6231
  - https://github.com/omacom/omarchy/discussions/8657 (WM_CLASS format for web apps)
- https://raw.githubusercontent.com/hyprwm/hyprland-plugins/main/hyprbars/README.md
- https://github.com/hyprwm/Hyprland/issues/9005 ("Headers outdated" failure mode)
- https://wiki.hypr.land/Plugins/Development/Plugin-Guidelines/ (commit-pin mechanism)
- https://quickshell.org/docs/v0.3.0/types/Quickshell.Hyprland/Hyprland/
- https://quickshell.org/docs/v0.2.1/types/Quickshell.Hyprland/HyprlandToplevel/
- https://quickshell.org/docs/v0.2.1/types/Quickshell.Wayland/ScreencopyView/
- https://archlinux.org/packages/extra/x86_64/quickshell/files/ (quickshell 0.3.1-1)
- https://omarchyplugins.com/ → https://plugins.omarchy.org/ (0 listed plugins at research time)
- https://github.com/aorumbayev/awesome-omarchy
- https://github.com/gardnmi/omarchy-minimize (MIT)
- https://github.com/rosakodu/omarchy-dock (MIT © 2026 rosakodu)
- https://github.com/sanjyay/Mirador
