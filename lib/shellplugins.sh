#!/usr/bin/env bash
# /**
#  * @version   1.2
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# Installing and toggling ocd's own Quickshell plugins.
#
# Confirmed from docs/omarchy-shell.md ("Installing a third-party plugin"
# and the IPC table): a plugin is a directory dropped into
# ~/.config/omarchy/plugins/<id>/, picked up by `rescanPlugins`, and
# enabled/disabled at runtime over IPC with `setPluginEnabled <id> <bool>` —
# no jq-patching of shell.json required for enablement. ocd still reads
# shell.json directly (read-only) for conflict scanning and status, but
# every *mutation* here goes through the documented IPC surface instead of
# us guessing its on-disk shape.

OCD_ID_DOCK="${OCD_PLUGIN_ID}.dock"
OCD_ID_EXPOSE="${OCD_PLUGIN_ID}.expose"
OCD_ID_SETTINGS="${OCD_PLUGIN_ID}.settings"

ocd_plugin_dir() {
    printf '%s/%s' "$OCD_PLUGINS_ROOT" "$1"
}

# ocd_plugin_install_dir <id> <src-dir>: copies src-dir's contents into
# ~/.config/omarchy/plugins/<id>/, replacing any previous ocd-owned copy.
# Idempotent and safe to re-run (e.g. on reinstall/update).
ocd_plugin_install_dir() {
    local id="$1" src="$2" dest
    dest="$(ocd_plugin_dir "$id")"
    [[ -d "$src" ]] || ocd_die "plugin source missing: $src"
    if ocd_dry_run; then
        printf '[dry-run] would install plugin %s: %s -> %s\n' "$id" "$src" "$dest" >&2
        ocd_log "DRY-RUN" "install plugin $id :: $src -> $dest"
        return 0
    fi
    mkdir -p "$dest"
    cp -rT "$src" "$dest"
    ocd_log "RUN" "installed plugin $id from $src to $dest"
}

ocd_plugin_remove_dir() {
    local id="$1" dest
    dest="$(ocd_plugin_dir "$id")"
    [[ -d "$dest" ]] || return 0
    ocd_run "remove plugin directory $id" -- rm -rf "$dest"
}

ocd_shell_rescan() {
    command -v omarchy-shell >/dev/null 2>&1 || return 0
    ocd_run "rescan plugins" -- omarchy-shell shell rescanPlugins
}

# ocd_shell_set_enabled <id> <true|false>
ocd_shell_set_enabled() {
    local id="$1" enabled="$2"
    command -v omarchy-shell >/dev/null 2>&1 || ocd_die "omarchy-shell not found on PATH"
    ocd_run "setPluginEnabled $id $enabled" -- omarchy-shell shell setPluginEnabled "$id" "$enabled"
}

# ocd_plugin_uninstall <id>: prefers the documented CLI (which also cleans
# up shell.json's own bookkeeping); falls back to a manual removal if the
# CLI is unavailable or refuses (e.g. plugin already gone).
ocd_plugin_uninstall() {
    local id="$1"
    if command -v omarchy >/dev/null 2>&1; then
        if ocd_run "omarchy plugin remove $id" -- omarchy plugin remove "$id" --yes; then
            return 0
        fi
        ocd_warn "'omarchy plugin remove $id' failed or the plugin was already gone; removing its directory directly"
    fi
    ocd_shell_set_enabled "$id" false || true
    ocd_plugin_remove_dir "$id"
}
