#!/usr/bin/env bash
# /**
#  * @version   1.0
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# Backup/restore of files ocd is about to mutate: Hyprland Lua config and
# shell.json. Never touches files ocd owns outright (those are just deleted
# on uninstall, no backup needed).

# ocd_backup_create: creates a timestamped snapshot, prints the timestamp
# (not the full path) so callers/uninstall can address it as
# `--restore-backup <timestamp>`.
ocd_backup_create() {
    local stamp dest
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    dest="$OCD_BACKUP_ROOT/$stamp"
    if ocd_dry_run; then
        printf '[dry-run] would back up %s/**/*.lua and %s to %s\n' "$HYPR_CONFIG_DIR" "$OMARCHY_SHELL_JSON" "$dest" >&2
        ocd_log "DRY-RUN" "backup :: $dest"
        printf '%s' "$stamp"
        return 0
    fi
    mkdir -p "$dest/hypr"
    if [[ -d "$HYPR_CONFIG_DIR" ]]; then
        local f rel
        while IFS= read -r -d '' f; do
            rel="${f#"$HYPR_CONFIG_DIR"/}"
            mkdir -p "$dest/hypr/$(dirname "$rel")"
            cp -p "$f" "$dest/hypr/$rel"
        done < <(find "$HYPR_CONFIG_DIR" -maxdepth 3 -name '*.lua' -print0)
    fi
    if [[ -f "$OMARCHY_SHELL_JSON" ]]; then
        mkdir -p "$dest/omarchy"
        cp -p "$OMARCHY_SHELL_JSON" "$dest/omarchy/shell.json"
    fi
    ocd_log "RUN" "created backup at $dest"
    printf '%s' "$stamp"
}

ocd_backup_restore_cmd_hint() {
    printf 'uninstall.sh --restore-backup %s' "$1"
}

# ocd_backup_restore <timestamp>
ocd_backup_restore() {
    local stamp="$1" src
    src="$OCD_BACKUP_ROOT/$stamp"
    [[ -d "$src" ]] || ocd_die "no backup found at $src"
    ocd_info "Restoring from backup $stamp"
    if [[ -d "$src/hypr" ]]; then
        local f rel dest_path
        while IFS= read -r -d '' f; do
            rel="${f#"$src/hypr/"}"
            dest_path="$HYPR_CONFIG_DIR/$rel"
            mkdir -p "$(dirname "$dest_path")"
            ocd_run "restore $rel" -- cp -p "$f" "$dest_path"
        done < <(find "$src/hypr" -type f -name '*.lua' -print0)
    fi
    if [[ -f "$src/omarchy/shell.json" ]]; then
        ocd_run "restore shell.json" -- cp -p "$src/omarchy/shell.json" "$OMARCHY_SHELL_JSON"
    fi
    ocd_info "Restore complete."
}
