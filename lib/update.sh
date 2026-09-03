#!/usr/bin/env bash
# /**
#  * @version   1.2
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# `ocd update` support: finds the latest published release tag and fetches
# it with the same pinned-SHA-then-verify mechanism boot.sh uses for a fresh
# install, so an update is never less trustworthy than the original install.
# Never follows `main` — only tags shaped like a release (vN, vN.N, vN.N.N).

OCD_REPO_URL="${OCD_REPO_URL:-https://github.com/fevangelou/ocd.git}"
OCD_INSTALLED_REF_FILE="$OCD_INSTALL_DIR/.installed-ref"

# ocd_tag_for_sha <sha>: prints the release tag whose commit is exactly
# <sha>, or nothing. Looked up against the remote directly rather than via
# local tag refs — boot.sh/ocd_fetch_pinned's shallow fetch-by-SHA never
# fetches tags, so a checkout that IS exactly a tagged release still has no
# local tag ref for `git describe` to find.
ocd_tag_for_sha() {
    local sha="$1"
    git ls-remote --tags "$OCD_REPO_URL" 2>/dev/null | awk -v sha="$sha" '
        $1 == sha { ref = $2; sub(/\^\{\}$/, "", ref); sub(/^refs\/tags\//, "", ref); print ref }
    ' | tail -1
}

# ocd_record_installed_ref <repo_dir>: called by install.sh right after a
# successful install, so `ocd update`/`ocd status` know exactly which
# commit (and tag, if any) is actually on disk. Reads git metadata from the
# checkout install.sh just ran from — works whether that came from boot.sh's
# ephemeral clone, `ocd update`'s own fetch, or a manual `git clone`.
ocd_record_installed_ref() {
    local repo_dir="$1" sha tag
    command -v git >/dev/null 2>&1 || return 0
    sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$sha" ]] || return 0
    tag="$(ocd_tag_for_sha "$sha")"
    if ocd_dry_run; then
        printf '[dry-run] would record installed ref (sha=%s tag=%s) at %s\n' "$sha" "${tag:-none}" "$OCD_INSTALLED_REF_FILE" >&2
        return 0
    fi
    mkdir -p "$OCD_INSTALL_DIR"
    printf 'sha=%s\ntag=%s\n' "$sha" "$tag" >"$OCD_INSTALLED_REF_FILE"
}

ocd_installed_sha() {
    [[ -f "$OCD_INSTALLED_REF_FILE" ]] || return 0
    grep '^sha=' "$OCD_INSTALLED_REF_FILE" | head -1 | cut -d= -f2
}

ocd_installed_tag() {
    [[ -f "$OCD_INSTALLED_REF_FILE" ]] || return 0
    grep '^tag=' "$OCD_INSTALLED_REF_FILE" | head -1 | cut -d= -f2
}

# ocd_latest_release_tag: the highest vX(.Y(.Z)) tag published on the repo,
# found via `git ls-remote` — no GitHub API call, so no token/rate-limit
# concerns, and it works against any git host, not just GitHub.
ocd_latest_release_tag() {
    git ls-remote --tags --refs "$OCD_REPO_URL" 2>/dev/null |
        awk '{print $2}' | sed 's#^refs/tags/##' |
        grep -E '^v[0-9]+(\.[0-9]+){0,2}$' |
        sort -V | tail -1
}

# ocd_tag_sha <tag>: resolves a tag name to its underlying *commit* SHA via
# ls-remote. An annotated tag (`git tag -a`, what release tags use) points
# at its own tag object, not the commit — ls-remote exposes the commit via
# a second "refs/tags/<tag>^{}" peeled entry, which takes priority here. A
# lightweight tag has no peeled entry, so the plain ref is already the
# commit and is used as a fallback.
ocd_tag_sha() {
    local tag="$1"
    git ls-remote --tags "$OCD_REPO_URL" "refs/tags/$tag" "refs/tags/$tag^{}" 2>/dev/null |
        awk -v peeled="refs/tags/$tag^{}" '
            $2 == peeled { print $1; found=1 }
            END { if (!found) print prev }
            { prev = $1 }
        '
}

# ocd_branch_sha <branch>: resolves a branch name to its current tip commit
# SHA via ls-remote. Used only by `ocd update --main` (dev/testing) — the
# resolved SHA still goes through ocd_fetch_pinned's fetch-by-SHA-then-verify
# below, so even a branch update never silently runs whatever `main` drifts
# to mid-fetch, just whatever it was at the moment it was resolved.
ocd_branch_sha() {
    local branch="$1"
    git ls-remote --heads "$OCD_REPO_URL" "$branch" 2>/dev/null | awk '{print $1}'
}

# ocd_fetch_pinned <sha> <dest_dir>: fetch + detached-checkout exactly <sha>,
# then verify the checkout really is that commit. Identical mechanism to
# boot.sh's install-time pin (see boot.sh for why `git clone --branch` can't
# be used for a raw SHA) — kept in sync so `ocd update` carries the same
# guarantee as the original install: you only ever run a specific, named,
# reviewed commit, never whatever a branch happens to point to right now.
ocd_fetch_pinned() {
    local sha="$1" dest="$2"
    git init --quiet "$dest"
    git -C "$dest" remote add origin "$OCD_REPO_URL"
    git -C "$dest" fetch --quiet --depth 1 origin "$sha"
    git -C "$dest" checkout --quiet FETCH_HEAD
    local resolved
    resolved="$(git -C "$dest" rev-parse HEAD)"
    [[ "$resolved" == "$sha" ]] ||
        ocd_die "checked-out commit ($resolved) does not match pinned ref ($sha) — refusing to run untrusted code"
}
