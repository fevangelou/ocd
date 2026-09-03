#!/usr/bin/env bash
# Sweeping windows out of the special:minimized workspace. Shared by
# lib/features.sh (before disabling the last restore surface) and
# uninstall.sh (must run before any teardown, unconditionally).

OCD_MINIMIZED_WORKSPACE="special:minimized"

# ocd_sweep_minimized: moves every window parked in special:minimized back to
# the currently active real workspace. Safe to call when there's nothing to
# sweep or when Hyprland isn't running.
ocd_sweep_minimized() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl version >/dev/null 2>&1 || return 0
    ocd_require_jq

    local target
    target="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')"
    [[ -n "$target" && "$target" != "null" ]] || target=1

    local addrs
    addrs="$(hyprctl clients -j 2>/dev/null | jq -r --arg ws "$OCD_MINIMIZED_WORKSPACE" '.[] | select(.workspace.name == $ws) | .address')"
    if [[ -z "$addrs" ]]; then
        ocd_info "No minimized windows to sweep"
        return 0
    fi

    # Quattro's `hyprctl dispatch <name> <args>` CLI form is gone — it's now
    # parsed as Lua (`hl.dispatch(...)`) and expects an actual dispatcher
    # object from hl.dsp.*, not a raw comma-joined string. Confirmed live:
    # hl.dsp.window.move() takes a `window` selector ("address:0x...") to
    # target an arbitrary window, not just the focused one — its `address`
    # field is silently ignored, so this must be `window`, not `address`.
    local addr
    while IFS= read -r addr; do
        [[ -z "$addr" ]] && continue
        ocd_run "restore minimized window $addr to workspace $target" -- \
            hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace = '${target}', window = 'address:${addr}'}))"
    done <<<"$addrs"
}
