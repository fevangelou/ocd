#!/usr/bin/env bash
# Idempotent marker-block management for text files ocd does not own outright
# (currently just ~/.config/hypr/hyprland.lua). Grep-before-append, never
# duplicate; symmetric removal for uninstall.

ocd_marker_present() {
    local file="$1" tag="$2"
    [[ -f "$file" ]] && grep -qF ">>> ${tag} >>>" "$file"
}

# ocd_marker_append <file> <tag> <body> [comment-prefix=--]
ocd_marker_append() {
    local file="$1" tag="$2" body="$3" prefix="${4:---}"
    if ocd_marker_present "$file" "$tag"; then
        ocd_log "INFO" "marker '$tag' already present in $file, skipping"
        return 0
    fi
    if ocd_dry_run; then
        printf '[dry-run] would append marker block "%s" to %s\n' "$tag" "$file" >&2
        ocd_log "DRY-RUN" "append marker '$tag' to $file"
        return 0
    fi
    [[ -f "$file" ]] || : >"$file"
    {
        printf '\n%s >>> %s >>>\n' "$prefix" "$tag"
        printf '%s\n' "$body"
        printf '%s <<< %s <<<\n' "$prefix" "$tag"
    } >>"$file"
    ocd_log "RUN" "appended marker '$tag' to $file"
}

# ocd_marker_remove <file> <tag>
ocd_marker_remove() {
    local file="$1" tag="$2"
    [[ -f "$file" ]] || return 0
    ocd_marker_present "$file" "$tag" || return 0
    if ocd_dry_run; then
        printf '[dry-run] would remove marker block "%s" from %s\n' "$tag" "$file" >&2
        ocd_log "DRY-RUN" "remove marker '$tag' from $file"
        return 0
    fi
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    # Also drops the single blank separator line ocd_marker_append put
    # immediately before its own fence, so repeated append/remove cycles
    # don't accumulate blank lines at end of file.
    awk -v start=">>> ${tag} >>>" -v end="<<< ${tag} <<<" '
        index($0, start) { skip=1; if (buffered_blank) { buffered_blank=0 }; next }
        index($0, end) { skip=0; next }
        skip { next }
        /^$/ { buffered_blank=1; next }
        buffered_blank { print ""; buffered_blank=0 }
        { print }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
    ocd_log "RUN" "removed marker '$tag' from $file"
}
