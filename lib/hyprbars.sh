#!/usr/bin/env bash
# hyprbars lifecycle via hyprpm. Per RESEARCH.md §3: hyprland-plugins ships
# its own Hyprland-commit -> plugin-commit pin table that hyprpm resolves
# automatically, so ocd does not hand-pin a commit — it calls plain
# hyprpm add/enable and handles the documented "Headers outdated" failure
# mode (stale headers after a Hyprland upgrade) with one retry via
# `hyprpm update`.

OCD_HYPRLAND_PLUGINS_REPO="https://github.com/hyprwm/hyprland-plugins"

# Ownership markers: uninstall.sh only disables hyprbars / mentions removing
# the hyprpm repo if ocd is the one that turned them on in the first place —
# never touch a setup the user already had.
OCD_HYPRBARS_OWNED_MARKER="$OCD_STATE_DIR/hyprbars-plugin-owned"
OCD_HYPRPM_REPO_OWNED_MARKER="$OCD_STATE_DIR/hyprpm-repo-owned"

ocd_hyprbars_is_enabled() {
    hyprctl plugin list 2>/dev/null | grep -qi hyprbars
}

ocd_hyprpm_repo_present() {
    hyprpm list 2>/dev/null | grep -qi "hyprland-plugins"
}

# hyprpm's per-user state dir (/var/cache/hyprpm/<user>/, holding
# state.toml and the built plugin repos). Confirmed live, twice: hyprpm's
# internal privilege escalation re-creates files here as root on *every*
# build it does that needs its own header/state work, not just the very
# first time ever — so a one-time `chown` is not a durable fix. This is
# re-checked and re-applied on every enable attempt instead.
OCD_HYPRPM_STATE_DIR="/var/cache/hyprpm/$(id -un)"

ocd_hyprpm_fix_ownership() {
    [[ -d "$OCD_HYPRPM_STATE_DIR" ]] || return 0
    find "$OCD_HYPRPM_STATE_DIR" -not -writable -print -quit 2>/dev/null | grep -q . || return 0
    ocd_warn "hyprpm's per-user state directory ($OCD_HYPRPM_STATE_DIR) has root-owned files again — hyprpm recreates them as root on every privileged build, not just the first ever time. Reclaiming ownership; this needs an interactive sudo prompt (same constraint as the state-store bootstrap above)."
    if ocd_dry_run; then
        printf '[dry-run] would run: sudo chown -R "%s:%s" %s\n' "$(id -un)" "$(id -gn)" "$OCD_HYPRPM_STATE_DIR" >&2
        return 0
    fi
    ocd_run "reclaim hyprpm state dir ownership" -- sudo chown -R "$(id -un):$(id -gn)" "$OCD_HYPRPM_STATE_DIR"
}

# hyprpm's very first invocation ever on a machine needs to create a
# root-owned "state store". It does this itself, internally, by shelling
# out to sudo/doas/run0 — hyprpm explicitly *refuses* to be run as root
# itself ("Don't run hyprpm as a superuser"), so ocd must never wrap it in
# sudo. That internal sudo call needs a real interactive TTY to read a
# password from; it fails ("Failed to run a superuser cmd") when hyprpm is
# invoked from a non-interactive context (a curl|bash pipe, an installer
# run from an agent, a detached `ocd apply`), which has nothing to do with
# ocd or this machine specifically — it's how hyprpm's own privilege
# escalation is designed. There is no reliable non-interactive workaround:
# if it fails this way, the fix is for the user to run `hyprpm list` (or
# `hyprpm add`/`enable`) themselves once, interactively, in a real
# terminal, then re-run `ocd apply`.
ocd_hyprpm_needs_interactive_bootstrap() {
    local out
    out="$(hyprpm list 2>&1)" && return 1
    grep -qi "superuser cmd\|state store" <<<"$out"
}

# ocd_hyprbars_enable: idempotent. Streams hyprpm's build output directly
# (not captured) since the build is slow and is the likeliest failure point.
# Leaves everything else intact on failure.
ocd_hyprbars_enable() {
    if ocd_hyprbars_is_enabled; then
        ocd_info "hyprbars already enabled"
        return 0
    fi
    command -v hyprpm >/dev/null 2>&1 || ocd_die "hyprpm not found; it ships with the hyprland package"

    ocd_hyprpm_fix_ownership

    if ocd_hyprpm_needs_interactive_bootstrap; then
        ocd_warn "hyprpm needs a one-time interactive sudo prompt to set up its plugin state store — this can only happen in a real terminal, not from this installer/apply run. Leaving window-controls disabled; every other ocd feature is unaffected. Fix: open a terminal and run 'hyprpm list' once (approve the password prompt it shows you), then re-run 'ocd apply'."
        return 1
    fi

    local repo_was_present=1
    ocd_hyprpm_repo_present || repo_was_present=0

    ocd_info "Adding hyprland-plugins via hyprpm (repo add is a no-op if already present)..."
    ocd_run "hyprpm add hyprland-plugins" -- hyprpm add "$OCD_HYPRLAND_PLUGINS_REPO" || true
    if [[ "$repo_was_present" == "0" ]] && ! ocd_dry_run; then
        mkdir -p "$OCD_STATE_DIR"
        : >"$OCD_HYPRPM_REPO_OWNED_MARKER"
    fi

    ocd_info "Building and enabling hyprbars — this can take a few minutes..."
    local ok=0
    if ocd_run "hyprpm enable hyprbars" -- hyprpm enable hyprbars; then
        ok=1
    else
        ocd_warn "hyprbars build failed. This is commonly stale plugin headers after a Hyprland upgrade — retrying once via 'hyprpm update'."
        ocd_hyprpm_fix_ownership
        ocd_run "hyprpm update" -- hyprpm update || true
        ocd_hyprpm_fix_ownership
        ocd_run "hyprpm enable hyprbars (retry)" -- hyprpm enable hyprbars && ok=1
    fi

    if [[ "$ok" == "1" ]]; then
        ocd_run "hyprpm reload" -- hyprpm reload -n
        if ! ocd_dry_run; then
            mkdir -p "$OCD_STATE_DIR"
            : >"$OCD_HYPRBARS_OWNED_MARKER"
        fi
        return 0
    fi

    ocd_warn "hyprbars still failed to build after 'hyprpm update'. Leaving window-controls disabled; every other ocd feature (mouse management, dock, Exposé) is unaffected and unchanged."
    return 1
}

ocd_hyprbars_disable() {
    if ! ocd_hyprbars_is_enabled; then
        ocd_info "hyprbars already disabled"
        return 0
    fi
    # Same root-owned-state-dir failure mode as enable (see
    # ocd_hyprpm_fix_ownership above) can hit `hyprpm disable` too — it
    # also writes state.toml. Must not be fatal to the whole `ocd apply`
    # run: confirmed live, an unguarded failure here previously aborted
    # apply outright, before shell.json/feature reconciliation even ran.
    ocd_hyprpm_fix_ownership
    if ! ocd_run "hyprpm disable hyprbars" -- hyprpm disable hyprbars; then
        ocd_warn "hyprpm disable hyprbars failed. hyprbars may still be loaded; re-run 'ocd apply' to retry. Every other ocd feature is unaffected."
        return 1
    fi
    ocd_run "hyprpm reload" -- hyprpm reload -n || true
}
