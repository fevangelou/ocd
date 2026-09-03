#!/usr/bin/env bash
# /**
#  * @version   1.1
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# Preflight checks: Omarchy major version, live Hyprland session, shell IPC,
# and detection of conflicting community dock/Exposé plugins.

OCD_REQUIRED_OMARCHY_MAJOR=4

ocd_omarchy_pkg_version() {
    pacman -Qi omarchy 2>/dev/null | awk -F': ' '/^Version/ {print $2; exit}'
}

# Prints the detected version on success; dies with a clear message otherwise.
ocd_check_omarchy_version() {
    local ver major
    ver="$(ocd_omarchy_pkg_version)"
    [[ -n "$ver" ]] || ocd_die "omarchy package not found (pacman -Qi omarchy). Is this an Omarchy system?"
    major="${ver%%.*}"
    major="${major%%-*}"
    if [[ ! "$major" =~ ^[0-9]+$ ]] || (( major != OCD_REQUIRED_OMARCHY_MAJOR )); then
        ocd_die "ocd targets Omarchy ${OCD_REQUIRED_OMARCHY_MAJOR}.x (\"Quattro\"); detected version $ver. Refusing to install on an unsupported major version (a half-applied install on the wrong major is worse than none)."
    fi
    ocd_info "Detected Omarchy $ver"
    printf '%s' "$ver"
}

ocd_check_hyprland_session() {
    command -v hyprctl >/dev/null 2>&1 || ocd_die "hyprctl not found; ocd requires a running Hyprland session"
    local out
    if ! out="$(hyprctl version 2>&1)"; then
        ocd_die "'hyprctl version' failed; is Hyprland running under this user session?"
    fi
    ocd_info "Hyprland session detected"
    printf '%s\n' "$out"
}

ocd_hyprland_version() {
    hyprctl version 2>/dev/null | awk '/^Hyprland/ {print $2; exit}'
}

ocd_check_shell_ipc() {
    command -v omarchy-shell >/dev/null 2>&1 || ocd_die "omarchy-shell not found on PATH"
    if ! omarchy-shell shell ping >/dev/null 2>&1; then
        ocd_die "omarchy-shell did not answer 'ping' over IPC. Is the shell running? Try: omarchy-shell restart"
    fi
    ocd_info "omarchy-shell IPC responded to ping"
}

# ocd_scan_conflicts: prints one human-readable conflict line per finding.
# Empty output means clean. Never fails the script itself; callers decide
# what to do with the output.
ocd_scan_conflicts() {
    ocd_require_jq
    if [[ -f "$OMARCHY_SHELL_JSON" ]]; then
        local ids id
        ids="$(jq -r '
            [(.plugins // [])[].id?, ((.bar.layout // {}) | .. | objects | .id?)]
            | flatten | map(select(. != null)) | unique | .[]
        ' "$OMARCHY_SHELL_JSON" 2>/dev/null)" || ids=""
        while IFS= read -r id; do
            [[ -z "$id" ]] && continue
            [[ "$id" == "$OCD_PLUGIN_ID"* ]] && continue
            [[ "$id" == omarchy.* ]] && continue
            if [[ "$id" =~ [Dd]ock ]] || [[ "$id" =~ [Ee]xpos ]] || [[ "$id" =~ [Ss]witcher ]]; then
                printf 'shell.json plugin id: %s\n' "$id"
            fi
        done <<<"$ids"
    fi
    if [[ -f "$HOME/.config/omarchy/dock-pinned.json" ]]; then
        printf 'file present: ~/.config/omarchy/dock-pinned.json (matches rosakodu/omarchy-dock pin-list convention)\n'
    fi
}
