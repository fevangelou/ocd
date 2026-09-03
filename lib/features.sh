#!/usr/bin/env bash
# features.json: the single source of truth for which ocd features are
# wanted. Written by the settings panel or by hand; `ocd apply` reconciles
# actual system state to it. This file only reads/writes it and enforces the
# dependency graph — it never mutates the system.

OCD_FEATURE_NAMES=(window-controls mouse-management dock expose)

ocd_features_init() {
    [[ -f "$OCD_FEATURES_FILE" ]] && return 0
    ocd_info "Creating default $OCD_FEATURES_FILE"
    if ocd_dry_run; then
        printf '[dry-run] would create default features.json at %s\n' "$OCD_FEATURES_FILE" >&2
        return 0
    fi
    mkdir -p "$OCD_CONFIG_DIR"
    cat >"$OCD_FEATURES_FILE" <<'EOF'
{
  "schemaVersion": 1,
  "features": {
    "window-controls": true,
    "mouse-management": true,
    "dock": true,
    "expose": true
  },
  "windowControlsStyle": "solid"
}
EOF
    ocd_log "RUN" "wrote default features.json"
}

OCD_CONTROL_STYLES=(solid text)

# ocd_control_style_get -> prints "solid" or "text" (default: solid)
ocd_control_style_get() {
    [[ -f "$OCD_FEATURES_FILE" ]] || { printf 'solid'; return 0; }
    local val
    val="$(ocd_json_get "$OCD_FEATURES_FILE" '.windowControlsStyle // "solid"')" || val="solid"
    [[ "$val" == "text" ]] && printf 'text' || printf 'solid'
}

# ocd_control_style_set <solid|text>
ocd_control_style_set() {
    local value="$1" s valid=0
    for s in "${OCD_CONTROL_STYLES[@]}"; do [[ "$s" == "$value" ]] && valid=1; done
    [[ "$valid" == "1" ]] || ocd_die "windowControlsStyle must be one of: ${OCD_CONTROL_STYLES[*]} (got '$value')"
    ocd_features_init
    ocd_json_patch "$OCD_FEATURES_FILE" '.windowControlsStyle = $v' --arg v "$value"
}

ocd_feature_is_valid_name() {
    local name="$1" n
    for n in "${OCD_FEATURE_NAMES[@]}"; do
        [[ "$n" == "$name" ]] && return 0
    done
    return 1
}

# ocd_feature_get <name> -> prints "true" or "false"
ocd_feature_get() {
    local name="$1"
    ocd_feature_is_valid_name "$name" || ocd_die "unknown feature '$name' (known: ${OCD_FEATURE_NAMES[*]})"
    [[ -f "$OCD_FEATURES_FILE" ]] || { printf 'true'; return 0; }
    local val
    val="$(ocd_json_get "$OCD_FEATURES_FILE" ".features[\"$name\"]")" || val="true"
    [[ "$val" == "false" ]] && printf 'false' || printf 'true'
}

# ocd_feature_set <name> <true|false>
# Only writes features.json. Does not touch the system. Validates the
# dependency graph *after* the hypothetical change and refuses if it would
# strand minimized windows or enable window-controls with no restore surface.
ocd_feature_set() {
    local name="$1" value="$2"
    ocd_feature_is_valid_name "$name" || ocd_die "unknown feature '$name' (known: ${OCD_FEATURE_NAMES[*]})"
    [[ "$value" == "true" || "$value" == "false" ]] || ocd_die "feature value must be true or false, got '$value'"
    ocd_features_init

    local dock expose window_controls
    dock="$(ocd_feature_get dock)"
    expose="$(ocd_feature_get expose)"
    window_controls="$(ocd_feature_get window-controls)"
    case "$name" in
        dock) dock="$value" ;;
        expose) expose="$value" ;;
        window-controls) window_controls="$value" ;;
    esac

    if [[ "$window_controls" == "true" && "$dock" == "false" && "$expose" == "false" ]]; then
        ocd_die "refusing: window-controls (minimize) needs at least one restore surface. Enable dock or expose first, or disable window-controls instead."
    fi

    # Disabling the last restore surface must sweep special:minimized first,
    # so no window is ever stranded there with no way back.
    if [[ "$name" == "dock" && "$value" == "false" && "$expose" == "false" ]] ||
       [[ "$name" == "expose" && "$value" == "false" && "$dock" == "false" ]]; then
        ocd_info "Disabling the last restore surface — sweeping minimized windows back to a real workspace first"
        ocd_sweep_minimized
    fi

    ocd_json_patch "$OCD_FEATURES_FILE" ".features[\"$name\"] = \$v" --argjson v "$value"
}

ocd_features_print_status() {
    ocd_features_init
    local name val
    for name in "${OCD_FEATURE_NAMES[@]}"; do
        val="$(ocd_feature_get "$name")"
        printf '  %-18s %s\n' "$name" "$val"
    done
}
