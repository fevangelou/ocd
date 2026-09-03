#!/usr/bin/env bash
# /**
#  * @version   1.2
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd uninstaller. Runs from either the original repo checkout or the
# permanent copy at ~/.local/share/ocd (it's copied there at install time).
# Designed to fully revert even if the install partially failed.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="$SELF_DIR/lib"

# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=lib/log.sh
source "$LIB_DIR/log.sh"
# shellcheck source=lib/jsonpatch.sh
source "$LIB_DIR/jsonpatch.sh"
# shellcheck source=lib/markers.sh
source "$LIB_DIR/markers.sh"
# shellcheck source=lib/minimize.sh
source "$LIB_DIR/minimize.sh"
# shellcheck source=lib/shellplugins.sh
source "$LIB_DIR/shellplugins.sh"
# shellcheck source=lib/hyprbars.sh
source "$LIB_DIR/hyprbars.sh"

ASSUME_YES=0

ocd_uninstall_usage() {
    cat <<'EOF'
Usage: uninstall.sh [--dry-run] [--yes] [--help]

  --dry-run                  Print every mutation, change nothing.
  --yes                      Don't prompt before deleting features.json and
                              the app-ID override map (your data).
  --help                     Show this message.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --help|-h) ocd_uninstall_usage; exit 0 ;;
            *) ocd_die "unknown flag: $1 (see --help)" ;;
        esac
    done
}

maybe_remove_user_data() {
    [[ -d "$OCD_CONFIG_DIR" ]] || return 0
    if [[ "$ASSUME_YES" == "1" ]]; then
        ocd_run "remove $OCD_CONFIG_DIR (--yes given)" -- rm -rf "$OCD_CONFIG_DIR"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        ocd_warn "Not running interactively — leaving $OCD_CONFIG_DIR (features.json, app-ID overrides) in place. Remove it yourself, or re-run with --yes."
        return 0
    fi
    local reply
    read -r -p "Remove $OCD_CONFIG_DIR (your feature toggles and app-ID overrides)? [y/N] " reply || reply="n"
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        ocd_run "remove $OCD_CONFIG_DIR" -- rm -rf "$OCD_CONFIG_DIR"
    else
        ocd_info "Leaving $OCD_CONFIG_DIR in place"
    fi
}

main() {
    parse_args "$@"
    ocd_log_init
    ocd_info "ocd uninstaller starting (log: $OCD_LOG_FILE)"
    ocd_dry_run && ocd_info "--dry-run: no changes will be made"

    # Always first, unconditionally, even on a partially-failed install:
    # never leave a window stranded with no way back.
    ocd_sweep_minimized

    ocd_marker_remove "$HYPR_MAIN_LUA" "$HYPR_OCD_MARKER"
    if [[ -f "$HYPR_OCD_LUA" ]]; then
        ocd_run "remove ocd.lua" -- rm -f "$HYPR_OCD_LUA"
    fi

    if [[ -f "$OCD_HYPRBARS_OWNED_MARKER" ]]; then
        ocd_hyprbars_disable
        ocd_run "clear hyprbars-owned marker" -- rm -f "$OCD_HYPRBARS_OWNED_MARKER"
    elif ocd_hyprbars_is_enabled; then
        ocd_info "hyprbars is enabled but ocd didn't turn it on (it was already there) — leaving it as-is"
    fi
    if [[ -f "$OCD_HYPRPM_REPO_OWNED_MARKER" ]]; then
        ocd_info "ocd added the hyprland-plugins hyprpm repo. Leaving it in place (other plugins may use it); run 'hyprpm remove hyprland-plugins' yourself if you want it fully gone."
        ocd_run "clear hyprpm-repo-owned marker" -- rm -f "$OCD_HYPRPM_REPO_OWNED_MARKER"
    fi

    ocd_info "Removing ocd's Quickshell plugins..."
    ocd_plugin_uninstall "$OCD_ID_DOCK"
    ocd_plugin_uninstall "$OCD_ID_EXPOSE"
    ocd_plugin_uninstall "$OCD_ID_SETTINGS"
    ocd_shell_rescan

    if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
        if command -v Hyprland >/dev/null 2>&1; then
            ocd_run "verify config" -- Hyprland --verify-config || ocd_warn "Hyprland config failed --verify-config after removing ocd — check your hypr/*.lua files by hand"
        fi
        ocd_run "reload Hyprland config" -- hyprctl reload || true
    fi

    maybe_remove_user_data

    ocd_run "remove ~/.local/bin/ocd symlink" -- rm -f "$HOME/.local/bin/ocd"
    if [[ -d "$OCD_INSTALL_DIR" ]]; then
        ocd_run "remove $OCD_INSTALL_DIR" -- rm -rf "$OCD_INSTALL_DIR"
    fi

    ocd_info "Uninstall complete."
}

main "$@"
