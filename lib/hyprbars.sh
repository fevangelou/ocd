#!/usr/bin/env bash
# /**
#  * @version   1.2
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# hyprbars lifecycle via hyprpm. hyprland-plugins ships
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

# Whether the *running compositor* has hyprbars attached. This is the only
# thing that actually matters to the user — and it is emphatically not the
# same as "hyprpm exited 0". Confirmed live: hyprpm can print
# "✔ built hyprbars into hyprbars/hyprbars.so" and "[ERR] Failed to write
# plugin state" in the same run, exit successfully, and leave nothing
# loaded.
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

# hyprpm mutates its state store through its OWN internal privilege
# escalation, not as the invoking user. Confirmed live by intercepting the
# call — every enable/disable/add ends in:
#
#   sudo install -m644 -o 0 -g 0 /run/user/<uid>/hyprpm/.temp-state \
#        /var/cache/hyprpm/<user>/<repo>/state.toml
#
# Note `-o 0 -g 0`: the store is *meant* to be root-owned, so chowning it
# to the user (which ocd used to do) fixes nothing and merely fights
# upstream — hyprpm re-roots it on the very next write.
#
# What actually matters is whether that internal sudo can obtain
# credentials at all. sudo reads its password from /dev/tty, so a process
# with no controlling terminal — `ocd apply` spawned by the Quickshell
# settings panel, a curl|bash pipe, an agent run — can never satisfy it.
# hyprpm then prints "[ERR] Failed to write plugin state" and, crucially,
# still exits 0.
ocd_hyprpm_can_escalate() {
    sudo -n true 2>/dev/null && return 0      # NOPASSWD, or a cached timestamp
    (exec 3<>/dev/tty) 2>/dev/null            # a terminal sudo could prompt on
}

ocd_hyprpm_escalation_hint() {
    ocd_warn "hyprpm needs root to write its plugin state (it runs 'sudo install ... /var/cache/hyprpm/...' internally), and there's no terminal here for sudo to ask for a password on."
    ocd_warn "Run 'ocd apply' yourself in a terminal to finish this step. Everything else ocd does has already been applied."
}

# Every hyprpm invocation goes through here, purely so the call is logged
# and dry-run-aware in one place.
ocd_hyprpm() {
    local desc="$1"; shift
    ocd_run "$desc" -- hyprpm "$@"
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

    # Bail out before touching hyprpm at all if its internal sudo can't
    # possibly succeed — otherwise it "succeeds" (exit 0) having written
    # nothing, and the only symptom is that no titlebars appear.
    if ! ocd_dry_run && ! ocd_hyprpm_can_escalate; then
        ocd_hyprpm_escalation_hint
        return 1
    fi

    if ocd_hyprpm_needs_interactive_bootstrap; then
        ocd_warn "hyprpm needs a one-time interactive sudo prompt to set up its plugin state store — this can only happen in a real terminal, not from this installer/apply run. Window controls are unavailable until then; everything else ocd does is unaffected. Fix: open a terminal and run 'hyprpm list' once (approve the password prompt it shows you), then re-run 'ocd apply'."
        return 1
    fi

    local repo_was_present=1
    ocd_hyprpm_repo_present || repo_was_present=0

    ocd_info "Adding hyprland-plugins via hyprpm (repo add is a no-op if already present)..."
    ocd_hyprpm "hyprpm add hyprland-plugins" add "$OCD_HYPRLAND_PLUGINS_REPO" || true

    # `hyprpm add` failing is not cosmetic: without the repo cloned,
    # `hyprpm enable hyprbars` can only ever answer "Couldn't enable plugin
    # (missing?)". The usual cause is stale headers ("Headers outdated,
    # please run hyprpm update") on a state dir that was just created — so
    # do what hyprpm's own message asks, then add again, before going near
    # enable.
    if ! ocd_dry_run && ! ocd_hyprpm_repo_present; then
        ocd_warn "hyprpm has no hyprland-plugins repo after 'add' — usually outdated plugin headers. Running 'hyprpm update' to rebuild them, then retrying the add."
        ocd_hyprpm "hyprpm update" update || true
        ocd_hyprpm "hyprpm add hyprland-plugins (retry)" add "$OCD_HYPRLAND_PLUGINS_REPO" || true
    fi

    if [[ "$repo_was_present" == "0" ]] && ! ocd_dry_run; then
        mkdir -p "$OCD_STATE_DIR"
        : >"$OCD_HYPRPM_REPO_OWNED_MARKER"
    fi

    ocd_info "Building and enabling hyprbars — this can take a few minutes..."
    ocd_hyprpm "hyprpm enable hyprbars" enable hyprbars || true
    ocd_hyprpm "hyprpm reload" reload -n || true

    # Deliberately not trusting hyprpm's exit code — see
    # ocd_hyprbars_is_enabled. Ask the compositor what it actually loaded.
    if ocd_dry_run || ocd_hyprbars_is_enabled; then
        if ! ocd_dry_run; then
            mkdir -p "$OCD_STATE_DIR"
            : >"$OCD_HYPRBARS_OWNED_MARKER"
        fi
        return 0
    fi

    ocd_warn "hyprbars did not load. Retrying once via 'hyprpm update' — the common cause is plugin headers left stale by a Hyprland upgrade."
    ocd_hyprpm "hyprpm update" update || true
    ocd_hyprpm "hyprpm enable hyprbars (retry)" enable hyprbars || true
    ocd_hyprpm "hyprpm reload (retry)" reload -n || true

    if ocd_hyprbars_is_enabled; then
        mkdir -p "$OCD_STATE_DIR"
        : >"$OCD_HYPRBARS_OWNED_MARKER"
        return 0
    fi

    ocd_warn "hyprbars still would not load after 'hyprpm update'. Check 'hyprpm list' and 'hyprctl plugin list' — if hyprpm reports the plugin as enabled but the compositor shows none loaded, 'hyprpm reload' in a terminal is worth one try."
    ocd_warn "Window controls are unavailable this run; mouse management, the dock and Exposé are unaffected, and your ocd setting is unchanged."
    return 1
}

# hyprpm keeps its own per-repo record of which plugins are enabled,
# separate from what the compositor has loaded. The two drift apart exactly
# when an enable half-succeeds (built fine, state write or load failed), and
# a disable that only consults `hyprctl plugin list` would then skip the
# work and leave hyprpm permanently convinced hyprbars is on.
ocd_hyprbars_state_enabled() {
    local f
    for f in "$OCD_HYPRPM_STATE_DIR"/*/state.toml; do
        [[ -r "$f" ]] || continue
        awk '
            /^[[:space:]]*\[/ { in_hb = ($0 ~ /hyprbars/); next }
            in_hb && /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true/ { found = 1 }
            END { exit !found }
        ' "$f" && return 0
    done
    return 1
}

ocd_hyprbars_disable() {
    if ! ocd_hyprbars_is_enabled && ! ocd_hyprbars_state_enabled; then
        ocd_info "hyprbars already disabled"
        return 0
    fi
    # `hyprpm disable` writes state.toml too, so it needs the same
    # privilege escalation as enable and fails the same silent way without
    # it. Must not be fatal to the whole `ocd apply` run: confirmed live,
    # an unguarded failure here previously aborted apply outright, before
    # shell.json reconciliation even ran.
    if ! ocd_dry_run && ! ocd_hyprpm_can_escalate; then
        ocd_hyprpm_escalation_hint
        ocd_warn "Titlebars are still showing until then."
        return 1
    fi
    ocd_hyprpm "hyprpm disable hyprbars" disable hyprbars || true
    ocd_hyprpm "hyprpm reload" reload -n || true

    # Same reason as enable: hyprpm exits 0 on a failed state write, so the
    # compositor is the only trustworthy source.
    if ! ocd_dry_run && ocd_hyprbars_is_enabled; then
        ocd_warn "hyprbars is still loaded after 'hyprpm disable'. Re-run 'ocd apply' in a terminal to retry; everything else ocd does is unaffected."
        return 1
    fi
}
