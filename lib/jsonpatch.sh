#!/usr/bin/env bash
# /**
#  * @version   1.1
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# Safe jq read/patch/write: read -> transform -> validate -> atomic move.
# Used for both shell.json (a file ocd does not own) and ocd's own
# features.json / appid-overrides.json.

ocd_require_jq() {
    command -v jq >/dev/null 2>&1 || ocd_die "jq is required but not installed (pacman -S jq)"
}

# ocd_json_patch <file> <jq-filter> [extra jq args...]
# Reads file (treats missing file as '{}'), applies filter, validates the
# result parses, writes atomically. Leaves unrelated keys byte-identical
# aside from jq's own formatting. Under --dry-run, prints a diff and writes
# nothing.
ocd_json_patch() {
    local file="$1" filter="$2"; shift 2
    ocd_require_jq
    local input="{}"
    [[ -f "$file" ]] && input="$(cat "$file")"
    local output
    if ! output="$(printf '%s' "$input" | jq "$@" "$filter")"; then
        ocd_die "jq filter failed for $file: $filter"
    fi
    printf '%s' "$output" | jq -e . >/dev/null 2>&1 || ocd_die "jq produced invalid JSON for $file, aborting without writing"
    if ocd_dry_run; then
        printf '[dry-run] would patch %s with filter: %s\n' "$file" "$filter" >&2
        if command -v diff >/dev/null 2>&1; then
            diff -u <(printf '%s' "$input" | jq -S . 2>/dev/null) <(printf '%s' "$output" | jq -S .) || true
        fi
        ocd_log "DRY-RUN" "patch $file :: $filter"
        return 0
    fi
    mkdir -p "$(dirname "$file")"
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    printf '%s\n' "$output" >"$tmp"
    mv "$tmp" "$file"
    ocd_log "RUN" "patched $file :: $filter"
}

# ocd_json_get <file> <jq-filter>
# Prints the raw jq output, or nothing (exit 1) if the file doesn't exist.
ocd_json_get() {
    local file="$1" filter="$2"
    ocd_require_jq
    [[ -f "$file" ]] || return 1
    jq -r "$filter" "$file"
}
