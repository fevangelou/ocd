# ocd — Omarchy Classic Desktop

**A curl-installable plugin/mod for [Omarchy](https://omarchy.org) 4.x ("Quattro")
that brings back familiar, conventional desktop-UI affordances on top of its
Hyprland + Quickshell stack.**

<img width="1920" height="1080" alt="screenshot-2026-09-03_04-21-44" src="https://github.com/user-attachments/assets/10a4450e-687c-4415-a8a3-b6f6335e382d" />

## What is OCD?

Omarchy is a great on-ramp from Windows, macOS and "traditional" Linux desktops like Gnome or KDE into the
Arch/Hyprland world — except that its keyboard-driven, tiling-first design
asks a lot of anyone whose muscle memory is a taskbar, a dock, and a mouse.
OCD exists to close that gap: it layers the classic desktop conventions most
people already know — window titlebars with minimize/maximize/close, a dock,
drag-to-move/resize, an Exposé-style window switcher — on top of stock
Omarchy, so it *feels* familiar from day one. No keybindings to memorize, no
mental gymnastics — just click what you'd normally click, and grow into
Omarchy's keyboard-driven workflows at your own pace, if at all.

Embrace Minimize, Maximize or Close in Omarchy - or as I'd like to call it: Dock, Hoist, Halt ;)

**Features:**

- **Window controls** — real titlebars with minimize / maximize / close
  buttons (via [hyprbars](https://github.com/hyprwm/hyprland-plugins/tree/main/hyprbars))
- **Mouse window management** — resize from a window's own border with no
  modifier key held (Omarchy already ships SUPER+drag to move/resize)
- **Dock** — running windows plus your pinned apps, auto-hiding at the
  bottom edge
- **Exposé** — every open window as a live preview, type-to-search, SUPER+E
- **Settings panel** — a bar icon and popup to toggle every feature above
  independently, live, no config file editing required

Every feature can be turned on or off independently, at any time, from the
settings panel or the `ocd` CLI. Nothing here is vendored from another
plugin, and installing refuses to proceed (without `--force`) if it detects
a conflicting community dock/Exposé plugin already set up.

Here's a short video demo as well:

https://github.com/user-attachments/assets/a3131b9f-ffcc-44e9-bb4f-3404a54251d9

## Changelog

- **v1.0** — Initial upload. Window controls, mouse management, dock,
  Exposé, and the settings panel, targeting Omarchy 4.x ("Quattro").
  
## To Do
For the Dock:
- Resolve auto-hiding not working when all windows are closed
- Add 2 icons to reveal the Omarchy menu and the desktop
- Use a colored dot instead of (min) for minimized apps
- Explore a second more compact dock design option (e.g. with icons) as in Ubuntu Desktop, Gnome, macOS etc. The minimal Omarchy-like option will remain default.
- Explore if it's possible to enable drag and drop for app tabs

For the Popup:
- Switch to the font used in other navbar popups (so things look more "native")

For the Exposé:
- Provide text assistance like 'Close with "Esc" key or hover your mouse on the top/right corner'
- Add option to choose the corner that triggers Exposé on your desktop

For the Window Controls:
- Consider +, - & inside each respective control (or as an option to toggle in the settings popup)
- Tooltip when hovering on each control
- Consider "double-click on window title" action to maximize/restore window size

## Installation

Recommended — preview first, no changes made:

```sh
curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash -s -- --dry-run
```

Happy with the plan? Drop the flag to actually install:

```sh
curl -fsSL https://raw.githubusercontent.com/fevangelou/ocd/main/boot.sh | bash
```

Or, from a git clone:

```sh
git clone https://github.com/fevangelou/ocd.git
cd ocd
./install.sh --dry-run   # preview
./install.sh              # install
```

Both entry points take the same flags:

| Flag | Effect |
|---|---|
| `--dry-run` | Print every mutation, change nothing. |
| `--force` | Proceed even if a conflicting community dock/Exposé plugin is detected. |
| `--features=list` | Comma-separated subset to enable initially (default: all). Names: `window-controls`, `mouse-management`, `dock`, `expose`. |

`--features` only sets the *initial* state — every component still gets
installed either way, and you can flip anything later from the settings
panel (bar icon, or SUPER+,) or with `ocd enable/disable <feature>` +
`ocd apply`.

Requires a live Omarchy 4.x session — the installer checks this itself and
refuses to run on anything else.

## Uninstallation

```sh
~/.local/share/ocd/uninstall.sh
# or, from a checkout:
./uninstall.sh
```

Fully reverts every change ocd made — strips the Hyprland config hook,
disables hyprbars if ocd was the one that enabled it, removes all three
Quickshell plugins, and cleans up `~/.local/share/ocd`. Safe to run even
after a partially-failed install. Flags: `--dry-run`, `--yes` (skip the
prompt before deleting your `features.json`/pins/overrides), and
`--restore-backup TIMESTAMP` (roll your Hyprland config back to the exact
state a backup captured before install — see
`~/.local/state/ocd/backups/`).

## How it's built

- **Bash** — `bin/ocd` (the CLI) and `lib/*.sh` own every system mutation:
  installing, uninstalling, and reconciling actual system state to
  `~/.config/omarchy/ocd/features.json`, the single source of truth for
  what's wanted.
- **Lua** — `~/.config/hypr/ocd.lua` configures Hyprland itself (resize
  behavior, the minimize keybind, hyprbars styling/buttons, hotkeys) and is
  hooked into `hyprland.lua` with a single `require("ocd")` inside a marker
  block, so it's trivially removable.
- **QML (Quickshell)** — the dock, Exposé, and settings panel are three
  independent Quickshell plugins under `plugin/`, dropped into
  `~/.config/omarchy/plugins/io.github.fevangelou.ocd.*/` and toggled
  entirely over Omarchy's own shell IPC — no hand-patched `shell.json`.
- **hyprbars** — a compiled Hyprland plugin (titlebars), built and loaded
  via `hyprpm`; ocd configures it but doesn't vendor or fork it.

Nothing here is hidden behind a build step — every file is plain,
inspectable source, and `features.json`/`appid-overrides.json`/
`dock-pins.json` are hand-editable JSON.

Did we mention it was live-built on Omarchy?

## Acknowledgements

Thank you to [DHH](https://github.com/dhh) and the whole Omarchy community —
without Omarchy itself, and the welcoming, keyboard-driven desktop it
introduced to so many newcomers, this mod wouldn't have a home to exist in.

No code from any other plugin is vendored here, but two projects were read
as prior art during research and are worth crediting directly:

- [`gardnmi/omarchy-minimize`](https://github.com/gardnmi/omarchy-minimize) —
  its hover-triggered live preview (still-frame by default, promoted to a
  live capture stream only while hovered/focused, torn down on close)
  independently informed the same approach in Exposé.
- [`rosakodu/omarchy-dock`](https://github.com/rosakodu/omarchy-dock) — an
  earlier bar-widget dock for Omarchy; its existence helped confirm that
  Chromium PWA icon matching is a real, shared pain point worth solving
  properly here.

## License

GNU General Public License v3.0 (GPLv3) — see [`LICENSE`](LICENSE).

## Copyrights

Copyright (c) 2026 Fotis Evangelou. All rights reserved.
