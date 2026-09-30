#!/usr/bin/env bash
emit() {
    printf '%s\n' "${1-}" >> "$TXT_REPORT" || { error 'Cannot write TXT report'; exit 3; }
}
terminal_status() {
    local status=$1 label=$2 color=''
    if [[ -t 1 && -z ${NO_COLOR-} && ${TERM-} != dumb ]]; then
        case $status in
            PASS|READY) color=$'\033[32m';;
            WARN|REVIEW|'READY WITH WARNINGS') color=$'\033[33m';;
            FAIL|BLOCKED) color=$'\033[31m';;
            'N/A') color=$'\033[90m';;
        esac
    fi
    if [[ -n $color ]]; then
        printf '  %s%-6s\033[0m %s\n' "$color" "$status" "$label"
    else
        printf '  %-6s %s\n' "$status" "$label"
    fi
}
terminal_narrow() {
    [[ ${COLUMNS-} =~ ^[0-9]+$ ]] && ((10#$COLUMNS < 80))
}
terminal_section() {
    local title=${1//_/ }
    printf '\n%s\n' "${title^^}"
    if [[ $title != SUMMARY && ${TERMINAL_HEADER_SHOWN-} != 1 ]] && ! terminal_narrow; then
        printf '  %-6s %-45s %4s %4s %4s %s\n' STATUS DESTINATION DNS TCP TLS HTTP
        TERMINAL_HEADER_SHOWN=1
    fi
}
terminal_intro() {
    local available=$1 unavailable=$2
    printf '\n%-7s %s\n' Host "$MACHINE"
    printf '%-7s %s\n' OS "$OS_NAME"
    printf '%-7s %s (%s)\n' Site "${SITE_LABELS[$SITE]}" "${SITE_DOMAINS[$SITE]}"
    printf '%-7s %s\n' Agent "${AGENT_VERSION:-not determined}"
    printf '%-7s %s\n' Tools "${available:-none}"
    [[ -z $unavailable ]] || printf '%-7s %s\n' Missing "$unavailable"
    if ((PROXY_PRESENT)); then printf '%-7s %s\n' Proxy 'configured (values withheld)'
    else printf '%-7s %s\n' Proxy 'not configured'; fi
    printf '%-7s %s\n' Scan 'all documented destinations; detailed TXT/JSON reports follow'
}
terminal_stage() {
    case $1 in PASS) printf ok;; WARN) printf warn;; FAIL) printf fail;; *) printf -- '--';; esac
}
terminal_endpoint() {
    local state hint field detail http_display dns_display tcp_display tls_display row vm_note=''
    [[ ${E[classification]} != 'NOT APPLICABLE' ]] || return 0
    if [[ $LAST_TERMINAL_CATEGORY != "$category" ]]; then
        terminal_section "$category"
        LAST_TERMINAL_CATEGORY=$category
    fi
    if [[ ${E[classification]} == 'ALLOWLIST REQUIREMENT' || ${E[classification]} == 'NOT DIRECTLY TESTABLE' ]]; then
        if [[ ${E[classification]} == 'ALLOWLIST REQUIREMENT' ]]; then hint='wildcard allowlist'
        elif [[ ${E[test_type]} == version ]]; then hint='Agent version not determined'
        else hint='manual target'; fi
        if terminal_narrow || ((${#E[hostname]} + ${#hint} > 56)); then
            terminal_status REVIEW "${E[hostname]}"
            printf '         %s (not tested)\n' "$hint"
        else
            terminal_status REVIEW "${E[hostname]}  $hint (not tested)"
        fi
        return 0
    fi
    state=${E[impact]}
    http_display=${E[http_status]:-${E[http]}}
    if [[ ${E[redirect_http_detail]} != 'No reachable redirect response' ]]; then
        http_display+=">${E[redirect_http_status]:-${E[redirect_http]}}"
    fi
    dns_display=$(terminal_stage "${E[dns]}")
    tcp_display=$(terminal_stage "${E[tcp]}")
    tls_display=$(terminal_stage "${E[tls]}")
    [[ ${E[classification]} != 'SERVER-SIDE SANITY CHECK ONLY' ]] || vm_note='  [VM only]'
    if terminal_narrow || ((${#E[hostname]} > 45)) || [[ -n $vm_note ]]; then
        terminal_status "$state" "${E[hostname]}"
        printf '         DNS %s  TCP %s  TLS %s  HTTP %s%s\n' "$dns_display" "$tcp_display" "$tls_display" "$http_display" "$vm_note"
    else
        printf -v row '%-45s %4s %4s %4s %s%s' "${E[hostname]}" "$dns_display" "$tcp_display" "$tls_display" "$http_display" "$vm_note"
        terminal_status "$state" "$row"
    fi
    [[ $state != PASS ]] || return 0
    for field in dns cname tcp tls http; do
        [[ ${E[$field]} == PASS ]] && continue
        detail=${E[${field}_detail]}
        if [[ $field == http && ${E[redirect_http_detail]} != 'No reachable redirect response' ]]; then
            if [[ ${E[redirect_http]} == PASS ]]; then
                detail="redirected to ${E[redirect_final_url]}; review destination allowlist"
            else
                detail="redirect follow-up ${E[redirect_http]}: ${E[redirect_http_detail]} (${E[redirect_final_url]})"
            fi
        fi
        printf '       %s: %s\n' "${field^^}" "$detail"
    done
    if [[ ${E[notes]} == *'POSSIBLE SECURITY FILTERING'* ]]; then
        printf '       Possible security filtering; review the TXT report.\n'
    elif [[ ${E[notes]} == *'Denial/filter wording observed'* ]]; then
        printf '       Response contains denial/filter wording; review the TXT report.\n'
    fi
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
    printf ',"curl_tls_fallback":'; json_string "${E[curl_tls]}"
    printf ',"remote_ip":'; json_string "${E[tls_ip]}"
    printf ',"openssl_exit":'; json_string "${E[tls_exit]}"
    printf ',"attempts":'; json_lines "${E[tls_attempts]}"; printf '}'
    printf ',"certificate_metadata":{'
    first=1
    for field in subject issuer expiry verification; do
        ((first)) || printf ','; first=0; json_string "$field"; printf ':'; json_string "${E[$field]}"
    done
    printf '},"http_result":{"status":'; json_string "${E[http]}"
    printf ',"detail":'; json_string "${E[http_detail]}"
    for field in http_status final_url remote_ip redirect_count server via curl_exit time_namelookup time_connect time_appconnect time_starttransfer time_total; do
        printf ','; json_string "$field"; printf ':'; json_string "${E[$field]}"
    done
    printf ',"attempts":'; json_lines "${E[http_attempts]}"
    printf ',"redirect_result":{"status":'; json_string "${E[redirect_http]}"
    printf ',"detail":'; json_string "${E[redirect_http_detail]}"
    for field in http_status final_url remote_ip curl_exit curl_tls redirect_count time_total; do
        printf ','; json_string "$field"; printf ':'; json_string "${E[redirect_$field]}"
    done
    printf '}}}\n'
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
    while IFS= read -r value; do [[ -z $value ]] || emit "TLS probe         $value"; done <<< "${E[tls_attempts]}"
    while IFS= read -r value; do [[ -z $value ]] || emit "HTTP probe        $value"; done <<< "${E[http_attempts]}"
    for field in subject issuer expiry verification http_status final_url remote_ip redirect_count server via curl_tls; do
        value=${E[$field]}; [[ -z $value ]] || emit "$(printf '%-17s %s' "$field" "$value")"
    done
    if [[ ${E[redirect_http_detail]} != 'No reachable redirect response' ]]; then
        emit "Redirect follow   ${E[redirect_http]} - ${E[redirect_http_detail]}"
        emit "Redirect result   HTTP=${E[redirect_http_status]:-none}, curl=${E[redirect_curl_exit]:-unknown}, IP=${E[redirect_remote_ip]:-unknown}, hops=${E[redirect_redirect_count]}, total=${E[redirect_time_total]:-unknown}s"
        emit "Redirect URL      ${E[redirect_final_url]}"
    fi
    emit "Endpoint result  ${E[status]} (readiness impact: ${E[impact]})"
    emit "Note             ${E[notes]}"
    terminal_endpoint
    endpoint_json >> "$ENDPOINT_JSON" || { error 'Cannot write endpoint JSON'; exit 3; }
    if [[ ${E[classification]} == 'DIRECT TEST' || ${E[classification]} == 'SERVER-SIDE SANITY CHECK ONLY' ]]; then
        case ${E[status]} in
            PASS) ((DIRECT_PASS+=1));;
            WARN) ((DIRECT_WARN+=1));;
            FAIL) ((DIRECT_FAIL+=1));;
        esac
    fi
    if [[ -z ${CATEGORY_STATUS[$category]-} ]]; then CATEGORY_ORDER+=("$category"); CATEGORY_STATUS[$category]=PASS; fi
    case ${E[impact]} in
        FAIL) CATEGORY_STATUS[$category]=FAIL; OVERALL=BLOCKED
              value="${E[hostname]}:"
              for field in dns tcp tls http; do
                  [[ ${E[$field]} != FAIL ]] || value+=" ${field^^}: ${E[${field}_detail]};"
              done
              BLOCKERS+=("$value");;
        WARN) [[ ${CATEGORY_STATUS[$category]} == FAIL ]] || CATEGORY_STATUS[$category]=WARN
              [[ $OVERALL == BLOCKED ]] || OVERALL='READY WITH WARNINGS';;
    esac
    [[ ${E[classification]} != 'ALLOWLIST REQUIREMENT' ]] || ALLOWLIST+=("${E[hostname]}")
    [[ ${E[classification]} != 'NOT DIRECTLY TESTABLE' ]] || UNTESTED+=("${E[hostname]}: ${E[notes]}")
}
report_finish() {
    local category line first=1 index=0 attention=0
    emit ''; emit '----------------------------------------'; emit 'SUMMARY'; emit '----------------------------------------'
    for category in "${CATEGORY_ORDER[@]}"; do emit "$(printf '%-26s %s' "$category" "${CATEGORY_STATUS[$category]}")"; done
    emit ''; emit "Direct endpoint checks: $DIRECT_PASS PASS, $DIRECT_WARN WARN, $DIRECT_FAIL FAIL"
    emit 'Wildcard and manual requirements are listed below; they are not counted as passed checks.'
    emit "Overall: $OVERALL"
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
        printf '{"schema_version":"1.2","metadata":{"tool_version":'; json_string "$TOOL_VERSION"
        printf ',"timestamp":'; json_string "$TIMESTAMP"
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
        printf '},"direct_endpoint_counts":{"pass":%s,"warn":%s,"fail":%s},"endpoints":[' "$DIRECT_PASS" "$DIRECT_WARN" "$DIRECT_FAIL"; first=1
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
    terminal_section SUMMARY
    terminal_status "$OVERALL" 'Network prerequisites'
    printf '  Direct endpoint checks: %s PASS, %s WARN, %s FAIL\n' "$DIRECT_PASS" "$DIRECT_WARN" "$DIRECT_FAIL"
    for category in "${CATEGORY_ORDER[@]}"; do
        [[ ${CATEGORY_STATUS[$category]} != PASS ]] || continue
        if ((attention==0)); then printf '\nAttention by category:\n'; attention=1; fi
        terminal_status "${CATEGORY_STATUS[$category]}" "${category//_/ }"
    done
    if ((${#BLOCKERS[@]})); then
        printf '\nBlockers:\n'
        for line in "${BLOCKERS[@]}"; do printf '  - %s\n' "$line"; done
    fi
    if ((${#ALLOWLIST[@]} || ${#UNTESTED[@]})); then
        printf '\nManual review: %s wildcard allowlist, %s other untested requirement(s).\n' "${#ALLOWLIST[@]}" "${#UNTESTED[@]}"
    fi
    printf 'RUM: VM-side sanity only; end-user browser connectivity is untested.\n'
    printf 'Reports:\n  TXT  %s.txt\n  JSON %s.json\n' "$REPORT_BASE" "$REPORT_BASE"
}
