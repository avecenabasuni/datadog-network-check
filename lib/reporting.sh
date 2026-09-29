#!/usr/bin/env bash
emit() {
    local line=${1-} color=''
    printf '%s\n' "$line" >> "$TXT_REPORT" || { error 'Cannot write TXT report'; exit 3; }
    if [[ -t 1 && -z ${NO_COLOR-} ]]; then
        case $line in *FAIL*|*BLOCKED*) color=$'\033[31m';; *WARN*|*SKIPPED*|*'NOT DIRECTLY TESTABLE'*) color=$'\033[33m';; *PASS*|READY) color=$'\033[32m';; esac
        printf '%s%s\033[0m\n' "$color" "$line"
    else printf '%s\n' "$line"; fi
}
report_init() {
    local safe_host stamp
    # Refuse symlinks and foreign-owned directories for report safety.
    [[ ! -L $ROOT/reports ]] || { error 'reports must not be a symlink'; return 1; }
    umask 077
    mkdir -p -- "$ROOT/reports" || return 1
    if [[ ! -O $ROOT/reports ]]; then error 'Report directory must be owned by the current user'; return 1; fi
    safe_host=${MACHINE//[^a-zA-Z0-9._-]/_}; stamp=$(date -u +%Y%m%d-%H%M%S)
    RUN_DIR=$(mktemp -d "$ROOT/reports/.run-XXXXXXXX") || return 1
    REPORT_BASE="$ROOT/reports/dd-network-preflight-$safe_host-$stamp-${RUN_DIR##*.run-}"
    TXT_REPORT="$RUN_DIR/report.txt"; JSON_REPORT="$RUN_DIR/report.json"; ENDPOINT_JSON="$RUN_DIR/endpoints.jsonl"
    : > "$TXT_REPORT" && : > "$ENDPOINT_JSON"
}
endpoint_json() {
    local field first=1
    printf '{'
    for field in id category label hostname port protocol applicable_os test_type requirement source status impact classification notes; do
        ((first)) || printf ','; first=0
        json_string "$field"; printf ':'; json_string "${E[$field]-}"
    done
    printf ',"dns_results":{"status":'; json_string "${E[dns]}"
    printf ',"detail":'; json_string "${E[dns_detail]}"; printf '}'
    printf ',"cname_result":{"status":'; json_string "${E[cname]}"
    printf ',"detail":'; json_string "${E[cname_detail]}"; printf '}'
    printf ',"cnames":'; json_lines "${E[cnames]}"
    printf ',"resolved_ips":'; json_lines "${E[ips]}"
    printf ',"tcp_result":{"status":'; json_string "${E[tcp]}"
    printf ',"detail":'; json_string "${E[tcp_detail]}"
    printf ',"attempts":'; json_lines "${E[tcp_attempts]}"; printf '}'
    printf ',"tls_result":{"status":'; json_string "${E[tls]}"
    printf ',"detail":'; json_string "${E[tls_detail]}"
    printf ',"curl_tls_fallback":'; json_string "${E[curl_tls]}"; printf '}'
    printf ',"certificate_metadata":{'
    first=1
    for field in subject issuer expiry verification; do
        ((first)) || printf ','; first=0; json_string "$field"; printf ':'; json_string "${E[$field]}"
    done
    printf '},"http_result":{"status":'; json_string "${E[http]}"
    printf ',"detail":'; json_string "${E[http_detail]}"
    for field in http_status final_url remote_ip redirect_count server via curl_exit; do
        printf ','; json_string "$field"; printf ':'; json_string "${E[$field]}"
    done
    printf '}}\n'
}
report_endpoint() {
    local field value
    if [[ $LAST_CATEGORY != "$category" ]]; then
        emit ''; emit '----------------------------------------'; emit "${category^^}"; emit '----------------------------------------'
        LAST_CATEGORY=$category
    fi
    emit ''; emit "${E[hostname]} - $label"
    emit "Classification   ${E[classification]}"
    for field in dns cname tcp tls http; do
        emit "$(printf '%-17s %s - %s' "${field^^}" "${E[$field]}" "${E[${field}_detail]}")"
    done
    [[ -z ${E[ips]} ]] || emit "Resolved IPs     ${E[ips]//$'\n'/, }"
    value=${E[cnames]%$'\n'}; [[ -z $value ]] || emit "CNAME chain      ${value//$'\n'/ -> }"
    value=${E[tcp_attempts]%$'\n'}; [[ -z $value ]] || emit "TCP/$port probes   ${value//$'\n'/; }"
    for field in subject issuer expiry verification http_status final_url remote_ip redirect_count server via curl_tls; do
        value=${E[$field]}; [[ -z $value ]] || emit "$(printf '%-17s %s' "$field" "$value")"
    done
    emit "Endpoint result  ${E[status]} (readiness impact: ${E[impact]})"
    emit "Note             ${E[notes]}"
    endpoint_json >> "$ENDPOINT_JSON" || { error 'Cannot write endpoint JSON'; exit 3; }
    if [[ -z ${CATEGORY_STATUS[$category]-} ]]; then CATEGORY_ORDER+=("$category"); CATEGORY_STATUS[$category]=PASS; fi
    case ${E[impact]} in
        FAIL) CATEGORY_STATUS[$category]=FAIL; OVERALL=BLOCKED; BLOCKERS+=("${E[hostname]}: DNS=${E[dns]}, TCP=${E[tcp]}, TLS=${E[tls]}, HTTP=${E[http]}");;
        WARN) [[ ${CATEGORY_STATUS[$category]} == FAIL ]] || CATEGORY_STATUS[$category]=WARN
              [[ $OVERALL == BLOCKED ]] || OVERALL='READY WITH WARNINGS';;
    esac
    [[ ${E[classification]} != 'ALLOWLIST REQUIREMENT' ]] || ALLOWLIST+=("${E[hostname]}")
    [[ ${E[classification]} != 'NOT DIRECTLY TESTABLE' ]] || UNTESTED+=("${E[hostname]}: ${E[notes]}")
}
report_finish() {
    local category line first=1 index=0
    emit ''; emit '----------------------------------------'; emit 'SUMMARY'; emit '----------------------------------------'
    for category in "${CATEGORY_ORDER[@]}"; do emit "$(printf '%-26s %s' "$category" "${CATEGORY_STATUS[$category]}")"; done
    emit ''; emit "Overall: $OVERALL"
    if ((${#BLOCKERS[@]})); then
        emit 'Detected blockers:'
        for line in "${BLOCKERS[@]}"; do ((index+=1)); emit "$index. $line"; done
        emit 'Suggested owner: Customer Network / DNS / Security Team'
    fi
    emit 'Wildcard allowlist requirements (NOT DIRECTLY TESTABLE):'
    for line in "${ALLOWLIST[@]}"; do emit "  $line"; done
    emit 'Other untested requirements:'
    for line in "${UNTESTED[@]}"; do emit "  $line"; done
    emit 'RUM: SERVER-SIDE SANITY CHECK ONLY. Browser corporate DNS/firewalls remain unvalidated.'
    emit 'This checks network prerequisites, not Agent configuration, API keys, instrumentation, permissions, or telemetry ingestion.'
    emit "TXT report: $REPORT_BASE.txt"; emit "JSON report: $REPORT_BASE.json"
    {
        printf '{"schema_version":"1.0","metadata":{"tool_version":"0.1.0","timestamp":'; json_string "$TIMESTAMP"
        printf ',"hostname":'; json_string "$MACHINE"
        printf ',"os":'; json_string "$OS_NAME"
        printf ',"last_verified_against_datadog_docs":'; json_string "$VERIFIED"
        printf ',"agent_version":'; json_string "$AGENT_VERSION"
        printf ',"scan_scope":"full","proxy_detection":%s,"dependencies":%s},' "$PROXY_JSON" "$DEPENDENCY_JSON"
        printf '"site":{"code":'; json_string "$SITE"
        printf ',"parameter":'; json_string "${SITE_DOMAINS[$SITE]}"; printf '},"categories":{'
        for category in "${CATEGORY_ORDER[@]}"; do
            ((first)) || printf ','; first=0; json_string "$category"; printf ':'; json_string "${CATEGORY_STATUS[$category]}"
        done
        printf '},"endpoints":['; first=1
        while IFS= read -r line; do ((first)) || printf ','; first=0; printf '%s' "$line"; done < "$ENDPOINT_JSON"
        printf '],"allowlist_requirements":'; json_lines "$(printf '%s\n' "${ALLOWLIST[@]}")"
        printf ',"untested_requirements":'; json_lines "$(printf '%s\n' "${UNTESTED[@]}")"
        printf ',"blockers":'; json_lines "$(printf '%s\n' "${BLOCKERS[@]}")"
        printf ',"overall_status":'; json_string "$OVERALL"; printf '}\n'
    } > "$JSON_REPORT" || return 1
    # Private unique run directory prevents collisions; do not overwrite reports.
    [[ ! -e $REPORT_BASE.txt && ! -e $REPORT_BASE.json ]] || return 1
    mv -- "$TXT_REPORT" "$REPORT_BASE.txt" && mv -- "$JSON_REPORT" "$REPORT_BASE.json" || return 1
    rm -f -- "$ENDPOINT_JSON"; rmdir -- "$RUN_DIR"
}
