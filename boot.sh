#!/usr/bin/env bash
# /**
#  * @version   1.4
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd bootstrap — the `curl ... | bash` entry point. Bootstrap ONLY: it
# checks for git, fetches one exact commit of this repository into a temp
# dir, and hands off to the real installer. All actual work lives in
# install.sh.
#
# curl | bash executes as it downloads, so a truncated transfer can run a
# partial script. Everything below lives inside main(), called only on the
# final line, so bash must finish parsing this entire file before any of it
# executes. stdin is the pipe here, not a terminal — this script (and
# install.sh after it) takes zero interactive input; everything is
# flag-driven via "$@", forwarded through untouched.
#
# The repository URL and commit below are written out literally, on purpose,
# and are NOT overridable from the environment. An installer that can be
# pointed at another repository or a moving branch by setting a variable is
# exactly the "source that was not part of the reviewed snapshot" problem —
# and it cannot be verified by reading this file alone. To install something
# other than the released commit, clone the repository and run ./install.sh
# directly; to track main during development, use `ocd update --main`.
#
# Both lines carry the same commit, tagged v1.4. Update both together when
# cutting a release.
set -euo pipefail

ocd_boot_log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
ocd_boot_die() { printf '\033[1;31m==> error:\033[0m %s\n' "$*" >&2; exit 1; }

main() {
    local clone_dir=""
    cleanup() {
        [[ -n "$clone_dir" && -d "$clone_dir" ]] && rm -rf "$clone_dir"
    }
    # Covers failure paths that happen *before* the exec handoff below
    # (a failed fetch, a missing install.sh). On success, exec replaces
    # this process — bash does not run EXIT traps across exec — so
    # cleanup of the success path is handed to install.sh itself via
    # OCD_EPHEMERAL_CLONE, which it honors by registering its own trap.
    trap cleanup EXIT
    trap 'ocd_boot_die "bootstrap failed"' ERR

    command -v git >/dev/null 2>&1 || ocd_boot_die "git is required (sudo pacman -S --needed git)"

    clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/ocd-install.XXXXXX")"

    # A plain `git clone --branch` only accepts branch/tag names, not a
    # commit SHA, so pinning needs an explicit fetch-by-SHA plus a detached
    # checkout of that same SHA. GitHub serves any commit reachable from a
    # ref, which a released, tagged commit always is.
    #
    # This is one fail-closed && chain from fetch through to exec: no step
    # can fail and let a later one run against a half-populated checkout.
    ocd_boot_log "Fetching ocd v1.4 into $clone_dir..."
    git init --quiet "$clone_dir" &&
        git -C "$clone_dir" fetch --quiet --depth 1 https://github.com/fevangelou/ocd.git 3df5af9decac24f21cfdd59db562d0c70680a11e &&
        git -C "$clone_dir" checkout --detach 3df5af9decac24f21cfdd59db562d0c70680a11e &&
        [[ -f "$clone_dir/install.sh" ]] &&
        chmod +x "$clone_dir/install.sh" &&
        ocd_boot_log "Handing off to install.sh..." &&
        OCD_EPHEMERAL_CLONE=1 exec "$clone_dir/install.sh" "$@"
}

main "$@"
