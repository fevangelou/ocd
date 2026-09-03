#!/usr/bin/env bash
# /**
#  * @version   1.1
#  * @package   Omarchy Classic Desktop (OCD)
#  * @author    Fotis Evangelou
#  * @url       https://github.com/fevangelou/ocd
#  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
#  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
#  */

# ocd logging helpers. Requires lib/common.sh to be sourced first.

ocd_log_init() {
    mkdir -p "$(dirname "$OCD_LOG_FILE")"
    : >>"$OCD_LOG_FILE"
}

ocd_log() {
    local level="$1"; shift
    printf '%s [%s] %s\n' "$(date -Iseconds)" "$level" "$*" >>"$OCD_LOG_FILE"
}

ocd_info()  { ocd_log "INFO" "$*"; printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
ocd_warn()  { ocd_log "WARN" "$*"; printf '\033[1;33m==> warning:\033[0m %s\n' "$*" >&2; }
ocd_error() { ocd_log "ERROR" "$*"; printf '\033[1;31m==> error:\033[0m %s\n' "$*" >&2; }
ocd_die()   { ocd_error "$*"; exit 1; }
