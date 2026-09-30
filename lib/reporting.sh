#!/usr/bin/env bash
emit() {
    printf '%s\n' "${1-}" >> "$TXT_REPORT" || { error 'Cannot write TXT report'; exit 3; }
}
terminal_utf8() {
    [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]]
}
terminal_color_enabled() {
    [[ -t 1 && -z ${NO_COLOR-} && ${TERM-} != dumb ]]
}
terminal_symbol() {
    if terminal_utf8; then
        case $1 in
            PASS|READY) printf '✔';;
            WARN|'READY WITH WARNINGS') printf '⚠';;
            REVIEW) printf '◌';;
            FAIL|BLOCKED) printf '✖';;
            *) printf -- '-';;
        esac
    else
        case $1 in
            PASS|READY) printf '[OK]';;
            WARN|'READY WITH WARNINGS') printf '[!!]';;
            REVIEW) printf '[??]';;
            FAIL|BLOCKED) printf '[XX]';;
            *) printf '[--]';;
        esac
    fi
}
terminal_status() {
    local status=$1 label=$2 color='' symbol
    symbol=$(terminal_symbol "$status")
    if terminal_color_enabled; then
        case $status in
            PASS|READY) color=$'\033[32m';;
            WARN|'READY WITH WARNINGS') color=$'\033[33m';;
            REVIEW) color=$'\033[36m';;
            FAIL|BLOCKED) color=$'\033[31m';;
            'N/A') color=$'\033[90m';;
        esac
    fi
    if [[ -n $color ]]; then
        printf '  %s%-6s\033[0m %s %s\n' "$color" "$status" "$label" "$symbol"
    else
        printf '  %-6s %s %s\n' "$status" "$label" "$symbol"
    fi
}
terminal_narrow() {
    (($(terminal_width)<80))
}
terminal_width() {
    if [[ -n ${TERMINAL_WIDTH-} ]]; then printf '%s' "$TERMINAL_WIDTH"; return; fi
    local width=80 measured
    if [[ ${COLUMNS-} =~ ^[0-9]+$ ]]; then
        measured=$((10#$COLUMNS))
        ((measured>=30 && measured<width)) && width=$measured
    fi
    if [[ ${TERMINAL_TTY-0} == 1 ]] && command -v tput >/dev/null 2>&1; then
        measured=$(tput cols 2>/dev/null) || measured=''
        if [[ $measured =~ ^[0-9]+$ ]] && ((measured>=30 && measured<width)); then width=$measured; fi
    fi
    printf '%s' "$width"
}
terminal_truncate() {
    local value=$1 limit=$2 marker='...'
    terminal_utf8 && marker='…'
    if ((${#value}<=limit)); then printf '%s' "$value"
    elif ((limit>${#marker})); then printf '%s%s' "${value:0:limit-${#marker}}" "$marker"
    else printf '%s' "${value:0:limit}"; fi
}
terminal_banner() {
    local width context mark divider spaces gap version="v$TOOL_VERSION"
    [[ ${TERMINAL_NO_BANNER-0} != 1 ]] || return 0
    if [[ ${TERMINAL_TTY-0} != 1 ]]; then
        printf 'DATADOG NETWORK PREFLIGHT  %s\n' "$version"
        return
    fi
    width=$(terminal_width)
    if terminal_utf8; then
        context="$MACHINE · $OS_NAME · ${SITE_LABELS[$SITE]} (${SITE_DOMAINS[$SITE]})"
    else
        context="$MACHINE | $OS_NAME | ${SITE_LABELS[$SITE]} (${SITE_DOMAINS[$SITE]})"
    fi
    if ((width<64)) || [[ ${TERMINAL_QUIET-0} == 1 ]]; then
        mark='|'; divider='-'
        if terminal_utf8; then mark='▌'; divider='─'; fi
        gap=$((width-4-25-${#version}))
        ((gap>=1)) || gap=1
        if terminal_color_enabled; then terminal_purple; fi
        printf ' %s DATADOG NETWORK PREFLIGHT%*s%s\n' "$mark" "$gap" '' "$version"
        if terminal_color_enabled; then printf '\033[0m'; fi
        printf -v spaces '%*s' "$((width-2))" ''
        printf ' %s\n' "${spaces// /$divider}"
        printf ' %s\n' "$(terminal_truncate "$context" "$((width-2))")"
        return
    fi
    if terminal_color_enabled; then terminal_purple; fi
    if terminal_utf8; then
        printf '%s\n' \
            '██████╗  █████╗ ████████╗ █████╗ ██████╗  ██████╗  ██████╗' \
            '██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗██╔════╝' \
            '██║  ██║███████║   ██║   ███████║██║  ██║██║   ██║██║  ███╗' \
            '██║  ██║██╔══██║   ██║   ██╔══██║██║  ██║██║   ██║██║   ██║' \
            '██████╔╝██║  ██║   ██║   ██║  ██║██████╔╝╚██████╔╝╚██████╔╝' \
            '╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚═════╝'
        printf '  N E T W O R K   P R E F L I G H T          %s\n' "$version"
        printf '%s\n' '  ────────────────────────────────────────────────────────────'
    else
        printf '%s\n' \
            ' ____    _  _____  _    ____   ___   ____' \
            '|  _ \  / \|_   _|/ \  |  _ \ / _ \ / ___|' \
            '| | | |/ _ \ | | / _ \ | | | | | | | |  _' \
            '| |_| / ___ \| |/ ___ \| |_| | |_| | |_| |' \
            '|____/_/   \_\_/_/   \_\____/ \___/ \____|'
        printf '  N E T W O R K   P R E F L I G H T    %s\n' "$version"
        printf '%s\n' '  ------------------------------------------'
    fi
    if terminal_color_enabled; then printf '\033[0m'; fi
    printf '  %s\n' "$(terminal_truncate "$context" "$((width-2))")"
}
terminal_purple() {
    local color_term=${COLORTERM-}
    color_term=${color_term,,}
    [[ $color_term != truecolor && $color_term != 24bit ]] || { printf '\033[38;2;99;44;166m'; return; }
    printf '\033[38;5;98m'
}
terminal_wrap() {
    local rest=$1 prefix=$2 continuation=$3 width limit chunk suffix
    width=$(terminal_width)
    ((width>=30)) || width=30
    while ((${#prefix}+${#rest} > width)); do
        limit=$((width-${#prefix}))
        chunk=${rest:0:limit}
        if [[ $chunk == *'; '* ]]; then
            suffix=${chunk##*; }
            if ((${#suffix}<25)); then chunk="${chunk%; *};"
            else chunk=${chunk% *}; fi
        elif [[ $chunk == *' '* ]]; then
            chunk=${chunk% *}
        fi
        [[ -n $chunk ]] || chunk=${rest:0:limit}
        printf '%s%s\n' "$prefix" "$chunk"
        rest=${rest:${#chunk}}
        rest=${rest# }
        prefix=$continuation
    done
    printf '%s%s\n' "$prefix" "$rest"
}
terminal_note() {
    local content=${1//$'\n'/ } marker='->' line width
    local -a lines=()
    terminal_utf8 && marker='↳'
    while IFS= read -r line; do lines+=("$line"); done < <(terminal_wrap "$content" "       $marker " '         ')
    if ((${#lines[@]}>2)); then
        width=$(terminal_width)
        lines[1]="${lines[1]:0:width-21} ... see TXT report"
    fi
    for line in "${lines[@]:0:2}"; do
        if terminal_color_enabled; then printf '\033[2m%s\033[0m\n' "$line"
        else printf '%s\n' "$line"; fi
    done
}
terminal_progress() {
    [[ ${TERMINAL_TTY-0} == 1 && ${TERM-} != dumb ]] || return 0
    local width
    width=$(terminal_width)
    printf '\r%-*.*s\r' "$((width-1))" "$((width-1))" "Checking destinations: $TERMINAL_PROGRESS_DONE/$TERMINAL_PROGRESS_TOTAL"
}
terminal_progress_clear() {
    [[ ${TERMINAL_TTY-0} == 1 && ${TERM-} != dumb ]] || return 0
    local width
    width=$(terminal_width)
    printf '\r%*s\r' "$((width-1))" ''
}
terminal_section() {
    local title=${1//_/ } status count counts='' divider padding fill width
    if [[ $title == SUMMARY ]] && ! terminal_narrow; then
        printf '\n%s\n' '+------------------------------------------------------------------------------+'
        printf '| %-76s |\n' SUMMARY
        printf '%s\n' '+------------------------------------------------------------------------------+'
        return
    fi
    [[ $title != SUMMARY ]] || { printf '\n[ SUMMARY ]\n'; return; }
    title=${title^^}
    [[ $1 != rum ]] || title+=' (VM-side only)'
    if declare -p TERMINAL_COUNTS >/dev/null 2>&1; then
        for status in PASS WARN FAIL REVIEW; do
            count=${TERMINAL_COUNTS["$1:$status"]-0}
            ((count)) && counts+="  $count $(terminal_symbol "$status")"
        done
    fi
    width=$(terminal_width)
    divider='-'; terminal_utf8 && divider='─'
    fill=$((width-3-${#title}-${#counts}))
    if ((fill<3)); then
        printf '\n %s\n  %s\n' "$title" "${counts#  }"
        return
    fi
    printf -v padding '%*s' "$fill" ''
    padding=${padding// /$divider}
    if terminal_color_enabled; then
        printf '\n \033[1m%s\033[0m \033[2m%s\033[0m%s\n' "$title" "$padding" "$counts"
    else
        printf '\n %s %s%s\n' "$title" "$padding" "$counts"
    fi
}
terminal_intro() {
    local available=$1 unavailable=$2
    local proxy='none' separator=' | '
    terminal_utf8 && separator=' · '
    ((PROXY_PRESENT)) && proxy='configured (values withheld)'
    printf '\n'
    terminal_wrap "Proxy: $proxy${separator}Tools: ${available:-none}${separator}Scope: all destinations" '  ' '  '
    [[ -z $unavailable ]] || terminal_wrap "Unavailable tools: $unavailable" '  ' '  '
    printf '  Agent: %s\n' "${AGENT_VERSION:-not determined}"
}
terminal_stage() {
    case $1 in PASS) printf ok;; WARN) printf warn;; FAIL) printf fail;; *) printf -- '--';; esac
}
terminal_row() {
    local state=$1 host=$2 dns=$3 tcp=$4 tls=$5 http=$6 width host_width symbol color='' stages status_field
    width=$(terminal_width)
    symbol=$(terminal_symbol "$state")
    if ((width<64)); then
        host=$(terminal_truncate "$host" "$((width-14))")
        terminal_status "$state" "$host"
        terminal_wrap "DNS $dns  TCP $tcp  TLS $tls  HTTP $http" '        ' '        '
        return
    fi
    host_width=$((width-38))
    host=$(terminal_truncate "$host" "$host_width")
    printf -v status_field '%-6s' "$state"
    printf -v stages '%4s %4s %4s %-8s' "$dns" "$tcp" "$tls" "$http"
    if terminal_color_enabled; then
        case $state in
            PASS) color=$'\033[32m';;
            WARN) color=$'\033[33m';;
            REVIEW) color=$'\033[36m';;
            FAIL) color=$'\033[31m';;
        esac
        printf '  %s%s\033[0m %-*s \033[2m%s\033[0m %s\n' "$color" "$status_field" "$host_width" "$host" "$stages" "$symbol"
    else
        printf '  %s %-*s %s %s\n' "$status_field" "$host_width" "$host" "$stages" "$symbol"
    fi
}
terminal_table_header() {
    local width host_width
    width=$(terminal_width)
    if ((width<64)); then
        printf '\n  STATUS DESTINATION\n        DNS  TCP  TLS  HTTP\n'
    else
        host_width=$((width-38))
        printf '\n  %-6s %-*s %4s %4s %4s %-8s\n' STATUS "$host_width" DESTINATION DNS TCP TLS HTTP
    fi
}
terminal_endpoint() {
    local state hint field detail http_display dns_display tcp_display tls_display reasons=''
    [[ ${E[classification]} != 'NOT APPLICABLE' ]] || return 0
    if [[ $LAST_TERMINAL_CATEGORY != "$category" ]]; then
        terminal_section "$category"
        LAST_TERMINAL_CATEGORY=$category
    fi
    if [[ ${E[classification]} == 'ALLOWLIST REQUIREMENT' || ${E[classification]} == 'NOT DIRECTLY TESTABLE' ]]; then
        if [[ ${E[classification]} == 'ALLOWLIST REQUIREMENT' ]]; then hint='wildcard allowlist'
        elif [[ ${E[test_type]} == version ]]; then hint='Agent version not determined'
        else hint='manual target'; fi
        terminal_row REVIEW "${E[hostname]}" '--' '--' '--' '--'
        terminal_note "$hint (not tested)"
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
    terminal_row "$state" "${E[hostname]}" "$dns_display" "$tcp_display" "$tls_display" "$http_display"
    [[ $state != PASS ]] || return 0
    if [[ -n ${TERMINAL_CURRENT_INDEX-} ]]; then
        if [[ ${TERMINAL_NOTE_KEY[$TERMINAL_CURRENT_INDEX]-} == redirect_allowlist && ${TERMINAL_GROUP_COUNTS["$category:redirect_allowlist"]-0} -ge 2 ]]; then return 0; fi
    fi
    for field in dns cname tcp tls http; do
        [[ ${E[$field]} == PASS ]] && continue
        [[ $field != cname || ${E[cname]} != SKIPPED ]] || continue
        detail=${E[${field}_detail]}
        if [[ $field == http && ${E[redirect_http_detail]} != 'No reachable redirect response' ]]; then
            if [[ ${E[redirect_http]} == PASS ]]; then
                detail="redirected to ${E[redirect_final_url]}; review destination allowlist"
            else
                detail="redirect follow-up ${E[redirect_http]}: ${E[redirect_http_detail]} (${E[redirect_final_url]})"
            fi
        fi
        reasons+="${reasons:+; }${field^^}: $detail"
    done
    if [[ ${E[notes]} == *'POSSIBLE SECURITY FILTERING'* ]]; then
        reasons+="${reasons:+; }Possible security filtering; review the TXT report."
    elif [[ ${E[notes]} == *'Denial/filter wording observed'* ]]; then
        reasons+="${reasons:+; }Response contains denial/filter wording; review the TXT report."
    fi
    [[ -z $reasons ]] || terminal_note "$reasons"
}
terminal_capture_endpoint() {
    local index field state key
    [[ ${E[classification]} != 'NOT APPLICABLE' ]] || return 0
    index=${#TERMINAL_ORDER[@]}
    TERMINAL_ORDER+=("$category")
    for field in classification test_type impact hostname dns cname tcp tls http http_status redirect_http_detail redirect_http_status redirect_http redirect_final_url dns_detail cname_detail tcp_detail tls_detail http_detail notes; do
        TERMINAL_SNAP["$index:$field"]=${E[$field]-}
    done
    state=${E[impact]}
    [[ ${E[classification]} != 'ALLOWLIST REQUIREMENT' && ${E[classification]} != 'NOT DIRECTLY TESTABLE' ]] || state=REVIEW
    key="$category:$state"
    TERMINAL_COUNTS[$key]=$(( ${TERMINAL_COUNTS[$key]-0}+1 ))
    TERMINAL_NOTE_KEY[index]=''
    if [[ $state == WARN && ${E[http]} == WARN && ${E[redirect_http_detail]} != 'No reachable redirect response' && ${E[redirect_http]} == PASS && ${E[dns]} == PASS && ${E[tcp]} == PASS && ${E[tls]} == PASS && ${E[notes]} != *'Denial/filter wording observed'* ]]; then
        TERMINAL_NOTE_KEY[index]=redirect_allowlist
        key="$category:redirect_allowlist"
        TERMINAL_GROUP_COUNTS[$key]=$(( ${TERMINAL_GROUP_COUNTS[$key]-0}+1 ))
    fi
}
terminal_group_notes() {
    local count=${TERMINAL_GROUP_COUNTS["$1:redirect_allowlist"]-0}
    if ((count>=2)); then
        terminal_note "$count endpoints redirect to another HTTPS destination. Confirm the redirect targets are allowed by your proxy/firewall."
    fi
}
terminal_render_report() {
    local i field category previous=''
    ((${#TERMINAL_ORDER[@]})) || return 0
    terminal_table_header
    LAST_TERMINAL_CATEGORY=''
    for ((i=0;i<${#TERMINAL_ORDER[@]};i++)); do
        category=${TERMINAL_ORDER[i]}
        [[ -z $previous || $previous == "$category" ]] || terminal_group_notes "$previous"
        for field in classification test_type impact hostname dns cname tcp tls http http_status redirect_http_detail redirect_http_status redirect_http redirect_final_url dns_detail cname_detail tcp_detail tls_detail http_detail notes; do
            E[$field]=${TERMINAL_SNAP["$i:$field"]-}
        done
        TERMINAL_CURRENT_INDEX=$i
        terminal_endpoint
        previous=$category
    done
    terminal_group_notes "$previous"
    TERMINAL_CURRENT_INDEX=''
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
    terminal_capture_endpoint
    ((TERMINAL_PROGRESS_DONE+=1))
    terminal_progress
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
    terminal_progress_clear
    terminal_render_report
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
        for line in "${BLOCKERS[@]}"; do terminal_wrap "$line" '  - ' '    '; done
    fi
    if ((${#ALLOWLIST[@]} || ${#UNTESTED[@]})); then
        printf '\nManual review: %s wildcard allowlist, %s other untested requirement(s).\n' "${#ALLOWLIST[@]}" "${#UNTESTED[@]}"
    fi
    printf 'RUM: VM-side sanity only; end-user browser connectivity is untested.\n'
    printf '\nReports: %s\n' "${REPORT_BASE%/*}"
    printf '  TXT  %s.txt\n  JSON %s.json\n' "${REPORT_BASE##*/}" "${REPORT_BASE##*/}"
}
