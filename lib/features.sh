#!/usr/bin/env bash
# /**
#  * @version   1.3
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# features.json: the single source of truth for whether ocd is wanted.
# `ocd apply` reconciles actual system state to it. This file only
# reads/writes it — it never mutates the system.
#
# Schema v2 replaced v1's four independent feature flags (plus a
# windowControlsStyle sub-option) with one `enabled` boolean. ocd is a
# single mod, not a suite: the per-feature matrix mostly produced
# combinations nobody asked for, and it actively caused harm — a transient
# hyprbars build failure used to write window-controls=false, silently
# demoting what the user had actually asked for with nothing to ever
# restore it.

OCD_SCHEMA_VERSION=2

ocd_features_init() {
    if [[ ! -f "$OCD_FEATURES_FILE" ]]; then
        ocd_info "Creating default $OCD_FEATURES_FILE"
        if ocd_dry_run; then
            printf '[dry-run] would create default features.json at %s\n' "$OCD_FEATURES_FILE" >&2
            return 0
        fi
        mkdir -p "$OCD_CONFIG_DIR"
        cat >"$OCD_FEATURES_FILE" <<EOF
{
  "schemaVersion": $OCD_SCHEMA_VERSION,
  "enabled": true
}
EOF
        ocd_log "RUN" "wrote default features.json"
        return 0
    fi
    ocd_features_migrate
}

# jq expression collapsing a v1 file to a single boolean. `enabled` goes
# false only if the user had genuinely turned every feature off; any
# feature still on — or a file with no features block at all — means the
# mod was wanted.
OCD_ENABLED_EXPR='if has("enabled") then (.enabled != false)
                  else (((.features // {}) | length) == 0
                        or (((.features // {}) | to_entries | map(.value) | any))) end'

ocd_features_migrate() {
    local ver
    ver="$(ocd_json_get "$OCD_FEATURES_FILE" '.schemaVersion // 1' 2>/dev/null)" || return 0
    [[ "$ver" =~ ^[0-9]+$ ]] || ver=1
    (( ver >= OCD_SCHEMA_VERSION )) && return 0
    ocd_info "Migrating features.json to schema v$OCD_SCHEMA_VERSION (one on/off switch instead of per-feature flags)."
    ocd_json_patch "$OCD_FEATURES_FILE" \
        "{ schemaVersion: \$sv, enabled: ($OCD_ENABLED_EXPR) }" \
        --argjson sv "$OCD_SCHEMA_VERSION"
}

# ocd_enabled_get -> prints "true" or "false".
# Reads a v1 file correctly too, so a --dry-run (which writes nothing, and
# so never migrates) still reports the right answer.
ocd_enabled_get() {
    [[ -f "$OCD_FEATURES_FILE" ]] || { printf 'true'; return 0; }
    local val
    val="$(ocd_json_get "$OCD_FEATURES_FILE" "$OCD_ENABLED_EXPR")" || val="true"
    [[ "$val" == "false" ]] && printf 'false' || printf 'true'
}

# ocd_enabled_set <true|false>
ocd_enabled_set() {
    local value="$1"
    [[ "$value" == "true" || "$value" == "false" ]] || ocd_die "enabled must be true or false, got '$value'"
    ocd_features_init
    # Turning ocd off takes away both restore surfaces at once, so anything
    # parked in special:minimized would have no way back. Sweep first.
    [[ "$value" == "false" ]] && ocd_sweep_minimized
    ocd_json_patch "$OCD_FEATURES_FILE" \
        '.schemaVersion = $sv | .enabled = $v' \
        --argjson sv "$OCD_SCHEMA_VERSION" --argjson v "$value"
}
