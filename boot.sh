#!/usr/bin/env bash
# /**
#  * @version   1.0
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd bootstrap — the `curl ... | bash` entry point. Bootstrap ONLY: it
# checks for git, shallow-clones the repo into a temp dir, and hands off to
# the real installer. All actual work lives in install.sh.
#
# curl | bash executes as it downloads, so a truncated transfer can run a
# partial script. Everything below lives inside main(), called only on the
# final line, so bash must finish parsing this entire file before any of it
# executes. stdin is the pipe here, not a terminal — this script (and
# install.sh after it) takes zero interactive input; everything is
# flag-driven via "$@", forwarded through untouched.
set -euo pipefail

OCD_REPO_URL="${OCD_REPO_URL:-https://github.com/fevangelou/ocd.git}"
# No tagged release exists yet; this should become a pinned stable tag once
# ocd starts cutting releases. Override for testing with `OCD_REF=some-branch`.
OCD_REF="${OCD_REF:-main}"

ocd_boot_log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
ocd_boot_die() { printf '\033[1;31m==> error:\033[0m %s\n' "$*" >&2; exit 1; }

main() {
    local clone_dir=""
    cleanup() {
        [[ -n "$clone_dir" && -d "$clone_dir" ]] && rm -rf "$clone_dir"
    }
    # Covers failure paths that happen *before* the exec handoff below
    # (a failed clone, a missing install.sh). On success, exec replaces
    # this process — bash does not run EXIT traps across exec — so
    # cleanup of the success path is handed to install.sh itself via
    # OCD_EPHEMERAL_CLONE, which it honors by registering its own trap.
    trap cleanup EXIT
    trap 'ocd_boot_die "bootstrap failed"' ERR

    command -v git >/dev/null 2>&1 || ocd_boot_die "git is required (sudo pacman -S --needed git)"

    clone_dir="$(mktemp -d "${TMPDIR:-/tmp}/ocd-install.XXXXXX")"

    ocd_boot_log "Cloning ocd ($OCD_REF) into $clone_dir..."
    git clone --quiet --depth 1 --branch "$OCD_REF" "$OCD_REPO_URL" "$clone_dir"

    [[ -f "$clone_dir/install.sh" ]] || ocd_boot_die "install.sh missing from cloned repo"
    chmod +x "$clone_dir/install.sh"

    ocd_boot_log "Handing off to install.sh..."
    OCD_EPHEMERAL_CLONE=1 exec "$clone_dir/install.sh" "$@"
}

main "$@"
