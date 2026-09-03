#!/usr/bin/env bash
# /**
#  * @version   1.0
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd installer. Run from a checked-out copy of the repo (boot.sh clones one
# and execs this, and so does `ocd update` from a newer release). Safe to
# re-run: every step is idempotent, and an existing features.json is left
# untouched unless --features is given explicitly.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB_DIR="$REPO_DIR/lib"

# boot.sh clones into a mktemp dir and execs us with this set; it can't
# clean up after itself post-exec (bash doesn't run EXIT traps across exec),
# so we own deleting the ephemeral clone once we're done with it.
if [[ "${OCD_EPHEMERAL_CLONE:-0}" == "1" ]]; then
    trap 'rm -rf "$REPO_DIR"' EXIT
fi

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
# shellcheck source=lib/features.sh
source "$LIB_DIR/features.sh"
# shellcheck source=lib/preflight.sh
source "$LIB_DIR/preflight.sh"
# shellcheck source=lib/backup.sh
source "$LIB_DIR/backup.sh"
# shellcheck source=lib/shellplugins.sh
source "$LIB_DIR/shellplugins.sh"
# shellcheck source=lib/hyprbars.sh
source "$LIB_DIR/hyprbars.sh"
# shellcheck source=lib/update.sh
source "$LIB_DIR/update.sh"

FORCE=0
FEATURES_ARG=""

ocd_install_usage() {
    cat <<'EOF'
Usage: install.sh [--dry-run] [--force] [--features=list] [--help]

  --dry-run          Print every mutation this installer would make, change nothing.
                      Recommended as your first run.
  --force             Proceed even if a conflicting community dock/Exposé plugin
                      is detected in shell.json.
  --features=list     Comma-separated subset to enable initially (default: all).
                      Names: window-controls (alias titlebars), mouse-management
                      (alias mouse), dock, expose. Example:
                      --features=titlebars,expose
  --help              Show this message.

Everything gets installed regardless of --features; the flag only sets the
initial ~/.config/omarchy/ocd/features.json state. Change it later with
`ocd enable/disable <feature>` + `ocd apply`, or the settings panel.
EOF
}

ocd_normalize_feature() {
    case "$1" in
        window-controls|titlebars) printf 'window-controls' ;;
        mouse-management|mouse) printf 'mouse-management' ;;
        dock) printf 'dock' ;;
        expose|exposé|exposeacute) printf 'expose' ;;
        *) ocd_die "unknown feature name in --features: '$1' (known: window-controls/titlebars, mouse-management/mouse, dock, expose)" ;;
    esac
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --force) FORCE=1; shift ;;
            --features=*) FEATURES_ARG="${1#--features=}"; shift ;;
            --help|-h) ocd_install_usage; exit 0 ;;
            *) ocd_die "unknown flag: $1 (see --help)" ;;
        esac
    done
}

check_sudo_for_missing_packages() {
    local missing=()
    command -v jq >/dev/null 2>&1 || missing+=(jq)
    # hyprpm's own declared build dependencies for compiling hyprbars
    # (confirmed live: a bare Omarchy install can be missing cmake even
    # though the rest of a build toolchain is present). Arch package names:
    # pkg-config -> pkgconf, g++/gcc -> gcc (provides both).
    command -v cmake >/dev/null 2>&1 || missing+=(cmake)
    command -v cpio >/dev/null 2>&1 || missing+=(cpio)
    command -v pkg-config >/dev/null 2>&1 || missing+=(pkgconf)
    command -v gcc >/dev/null 2>&1 || missing+=(gcc)
    # hyprpm also builds Hyprland itself locally to generate ABI-matching
    # headers for the plugin — meson/ninja are Hyprland's own build system
    # and aren't in hyprpm's printed dependency list, but a build fails
    # ("Headers missing") without them (confirmed live).
    command -v meson >/dev/null 2>&1 || missing+=(meson)
    command -v ninja >/dev/null 2>&1 || missing+=(ninja)
    [[ ${#missing[@]} -eq 0 ]] && return 0

    ocd_info "Missing required package(s): ${missing[*]}. ocd needs sudo once, up front, to install them via pacman — nothing else in this installer runs as root."
    if ocd_dry_run; then
        printf '[dry-run] would run: sudo pacman -S --needed %s\n' "${missing[*]}" >&2
        return 0
    fi
    sudo pacman -S --needed "${missing[@]}"
}

run_preflight() {
    ocd_info "Running preflight checks..."
    ocd_check_omarchy_version >/dev/null
    ocd_check_hyprland_session >/dev/null
    ocd_check_shell_ipc

    local hv
    hv="$(ocd_hyprland_version)"
    [[ -n "$hv" ]] || ocd_warn "Could not detect Hyprland version string from 'hyprctl version'"
    ocd_info "Detected Hyprland $hv"

    check_sudo_for_missing_packages

    local conflicts
    conflicts="$(ocd_scan_conflicts)"
    if [[ -n "$conflicts" ]]; then
        ocd_warn "Found what looks like an existing community dock/Exposé plugin:"
        while IFS= read -r line; do printf '    - %s\n' "$line" >&2; done <<<"$conflicts"
        if [[ "$FORCE" != "1" ]]; then
            ocd_die "Refusing to install alongside a possible conflicting dock/Exposé plugin. Remove it first, or re-run with --force if you've confirmed it's not a conflict (two docks stacked on one bar is a bad time)."
        fi
        ocd_warn "--force given, proceeding anyway."
    fi
}

compute_initial_features() {
    # Prints 4 lines: window-controls mouse-management dock expose (each true/false)
    local wc=true mm=true dock=true expose=true
    if [[ -n "$FEATURES_ARG" ]]; then
        wc=false; mm=false; dock=false; expose=false
        local IFS=','
        local part
        for part in $FEATURES_ARG; do
            case "$(ocd_normalize_feature "$part")" in
                window-controls) wc=true ;;
                mouse-management) mm=true ;;
                dock) dock=true ;;
                expose) expose=true ;;
            esac
        done
    fi
    if [[ "$wc" == "true" && "$dock" == "false" && "$expose" == "false" ]]; then
        ocd_die "--features=$FEATURES_ARG requests window-controls (minimize) with no restore surface. Include dock and/or expose."
    fi
    printf '%s\n%s\n%s\n%s\n' "$wc" "$mm" "$dock" "$expose"
}

write_initial_features_file() {
    local wc="$1" mm="$2" dock="$3" expose="$4"
    # install.sh is safe/expected to re-run — a fresh install, a re-run
    # after a partial failure, or `ocd update` re-invoking it from a newer
    # release. An existing features.json means this isn't a first install,
    # so leave the user's feature toggles alone unless they explicitly
    # asked to reset them via --features.
    if [[ -f "$OCD_FEATURES_FILE" && -z "$FEATURES_ARG" ]]; then
        ocd_info "Existing features.json found — leaving your feature toggles as-is (pass --features=... to reset them)."
        return 0
    fi
    ocd_info "Writing initial features.json (window-controls=$wc mouse-management=$mm dock=$dock expose=$expose)"
    if ocd_dry_run; then
        printf '[dry-run] would write %s\n' "$OCD_FEATURES_FILE" >&2
        return 0
    fi
    mkdir -p "$OCD_CONFIG_DIR"
    cat >"$OCD_FEATURES_FILE" <<EOF
{
  "schemaVersion": 1,
  "features": {
    "window-controls": $wc,
    "mouse-management": $mm,
    "dock": $dock,
    "expose": $expose
  }
}
EOF
    ocd_log "RUN" "wrote initial features.json"
}

install_files() {
    ocd_info "Installing ocd to $OCD_INSTALL_DIR..."
    # shellcheck disable=SC2016
    ocd_run "sync lib/ and bin/" -- bash -c '
        set -euo pipefail
        mkdir -p "$1"
        rm -rf "$1/lib" "$1/bin"
        cp -r "$2/lib" "$1/lib"
        cp -r "$2/bin" "$1/bin"
        cp "$2/uninstall.sh" "$1/uninstall.sh"
        [ -f "$2/README.md" ] && cp "$2/README.md" "$1/README.md"
        chmod +x "$1/bin/ocd" "$1/uninstall.sh"
    ' _ "$OCD_INSTALL_DIR" "$REPO_DIR"

    if ocd_dry_run; then
        printf '[dry-run] would symlink %s/.local/bin/ocd -> %s/bin/ocd\n' "$HOME" "$OCD_INSTALL_DIR" >&2
    else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$OCD_INSTALL_DIR/bin/ocd" "$HOME/.local/bin/ocd"
        ocd_log "RUN" "symlinked ~/.local/bin/ocd -> $OCD_INSTALL_DIR/bin/ocd"
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) ocd_warn "$HOME/.local/bin is not on your PATH — run ocd as $HOME/.local/bin/ocd, or add it to PATH" ;;
        esac
    fi

    [[ -d "$HYPR_CONFIG_DIR" ]] || ocd_dry_run || mkdir -p "$HYPR_CONFIG_DIR"
    ocd_run "install ocd.lua" -- cp "$REPO_DIR/hypr/ocd.lua" "$HYPR_OCD_LUA"
    ocd_marker_append "$HYPR_MAIN_LUA" "$HYPR_OCD_MARKER" 'require("ocd")'

    ocd_plugin_install_dir "$OCD_ID_DOCK" "$REPO_DIR/plugin/dock"
    ocd_plugin_install_dir "$OCD_ID_EXPOSE" "$REPO_DIR/plugin/expose"
    ocd_plugin_install_dir "$OCD_ID_SETTINGS" "$REPO_DIR/plugin/settings"
    ocd_shell_rescan
}

main() {
    parse_args "$@"
    ocd_log_init
    ocd_info "ocd installer starting (log: $OCD_LOG_FILE)"
    ocd_dry_run && ocd_info "--dry-run: no changes will be made"

    run_preflight

    local stamp
    stamp="$(ocd_backup_create)"
    ocd_info "Backup created: $stamp"
    ocd_info "Restore command: $(ocd_backup_restore_cmd_hint "$stamp")"

    local wc mm dock expose
    { read -r wc; read -r mm; read -r dock; read -r expose; } < <(compute_initial_features)

    install_files
    ocd_record_installed_ref "$REPO_DIR"
    write_initial_features_file "$wc" "$mm" "$dock" "$expose"

    ocd_info "Reconciling system state via 'ocd apply'..."
    local apply_args=() ocd_bin="$OCD_INSTALL_DIR/bin/ocd"
    if ocd_dry_run; then
        apply_args+=(--dry-run)
        ocd_bin="$REPO_DIR/bin/ocd"   # nothing was actually copied to OCD_INSTALL_DIR
    fi
    "$ocd_bin" apply "${apply_args[@]}"

    ocd_info "Install complete."
    ocd_info "Run 'ocd status' any time to see the reconciled state."
    ocd_info "To undo everything: $REPO_DIR/uninstall.sh"
}

main "$@"
