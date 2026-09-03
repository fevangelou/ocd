#!/usr/bin/env bash
# /**
#  * @version   1.0
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd shared paths, constants, and the dry-run-aware command runner.
# Sourced by every entry point; never executed directly.

OCD_PLUGIN_ID="io.github.fevangelou.ocd"
OCD_VERSION="0.1.0"

OCD_INSTALL_DIR="${OCD_INSTALL_DIR:-$HOME/.local/share/ocd}"

OCD_STATE_DIR="${OCD_STATE_DIR:-$HOME/.local/state/ocd}"
OCD_LOG_FILE="$OCD_STATE_DIR/install.log"
OCD_BACKUP_ROOT="$OCD_STATE_DIR/backups"

OCD_CONFIG_DIR="${OCD_CONFIG_DIR:-$HOME/.config/omarchy/ocd}"
OCD_FEATURES_FILE="$OCD_CONFIG_DIR/features.json"
OCD_APPID_OVERRIDES_FILE="$OCD_CONFIG_DIR/appid-overrides.json"

OMARCHY_CONFIG_DIR="${OMARCHY_CONFIG_DIR:-$HOME/.config/omarchy}"
OMARCHY_SHELL_JSON="$OMARCHY_CONFIG_DIR/shell.json"

HYPR_CONFIG_DIR="${HYPR_CONFIG_DIR:-$HOME/.config/hypr}"
HYPR_MAIN_LUA="$HYPR_CONFIG_DIR/hyprland.lua"
HYPR_OCD_LUA="$HYPR_CONFIG_DIR/ocd.lua"
HYPR_OCD_MARKER="ocd"

# Third-party plugin install root. Confirmed from docs/omarchy-shell.md
# ("Installing a third-party plugin"): a plugin is manually dropped into
# ~/.config/omarchy/plugins/<id>/, one directory per plugin id.
OCD_PLUGINS_ROOT="${OCD_PLUGINS_ROOT:-$HOME/.config/omarchy/plugins}"

DRY_RUN="${DRY_RUN:-0}"

ocd_dry_run() { [[ "$DRY_RUN" == "1" ]]; }

ocd_quote_cmd() {
    local out="" a
    for a in "$@"; do
        out+=" $(printf '%q' "$a")"
    done
    printf '%s' "${out# }"
}

# ocd_run <description> -- <command...>
# Executes and logs a mutating command; under --dry-run, only prints+logs it.
ocd_run() {
    local desc="$1"; shift
    [[ "${1:-}" == "--" ]] && shift
    if ocd_dry_run; then
        printf '[dry-run] %s\n         $ %s\n' "$desc" "$(ocd_quote_cmd "$@")" >&2
        ocd_log "DRY-RUN" "$desc :: $(ocd_quote_cmd "$@")"
        return 0
    fi
    ocd_log "RUN" "$desc :: $(ocd_quote_cmd "$@")"
    "$@"
}
