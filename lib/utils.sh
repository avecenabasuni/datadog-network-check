#!/usr/bin/env bash
# Libraries return results in the caller-owned associative array E.
# Site and Agent globals are read by the entry point after this module is sourced.
# shellcheck disable=SC2154,SC2034
have() { command -v "$1" >/dev/null 2>&1; }
error() { printf 'ERROR: %s\n' "$*" >&2; }
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }
json_string() {
    local s=${1-} i c
    s=${s//\\/\\\\}; s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    for ((i=1;i<32;i++)); do
        printf -v c '\\%03o' "$i"
        printf -v c '%b' "$c"
        s=${s//"$c"/}
    done
    printf '"%s"' "$s"
}
json_lines() {
    local value first=1
    printf '['
    while IFS= read -r value; do
        [[ -n $value ]] || continue
        ((first)) || printf ','; first=0; json_string "$value"
    done <<< "${1-}"
    printf ']'
}
valid_host() {
    local h=$1 label
    [[ ${#h} -le 253 && $h == *.* && $h != *..* && $h != *. ]] || return 1
    local -a labels
    IFS=. read -r -a labels <<< "$h"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && $label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 1
    done
}
is_ip() {
    local part n
    if [[ $1 == *:* ]]; then [[ $1 =~ ^[0-9a-fA-F:]+(%[a-zA-Z0-9._-]+)?$ ]]; return; fi
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    local -a parts
    IFS=. read -r -a parts <<< "$1"
    for part in "${parts[@]}"; do n=$((10#$part)); ((n<=255)) || return 1; done
}
add_note() { E[notes]+="${E[notes]:+; }$*"; }
reset_result() {
    E=([dns]=SKIPPED [dns_detail]='Not attempted' [cname]=SKIPPED [cname_detail]='Not attempted'
       [ips]='' [cnames]='' [tcp]=SKIPPED [tcp_detail]='DNS dependency unavailable'
       [tcp_attempts]='' [tcp_ip]='' [tls]=SKIPPED [tls_detail]='TCP dependency unavailable'
       [tls_attempts]='' [tls_ip]='' [tls_exit]=''
       [subject]='' [issuer]='' [expiry]='' [verification]='' [http]=SKIPPED
       [http_detail]='Not attempted' [http_status]='' [final_url]='' [remote_ip]=''
       [redirect_count]=0 [server]='' [via]='' [curl_exit]='' [curl_tls]=SKIPPED
       [http_attempts]='' [time_namelookup]='' [time_connect]='' [time_appconnect]='' [time_starttransfer]='' [time_total]=''
       [redirect_http]=SKIPPED [redirect_http_detail]='No reachable redirect response'
       [redirect_http_status]='' [redirect_final_url]='' [redirect_host]='' [redirect_remote_ip]=''
       [redirect_curl_exit]='' [redirect_curl_tls]=SKIPPED [redirect_redirect_count]=0 [redirect_time_total]=''
       [ntp]='NOT APPLICABLE' [ntp_detail]='Not an NTP endpoint' [ntp_attempts]='' [ntp_ip]=''
       [ntp_version]='' [ntp_stratum]='' [ntp_leap]='' [ntp_kiss_code]='' [ntp_target_source]=''
       [notes]='' [status]=PASS [impact]=PASS [classification]='DIRECT TEST')
}
proxy_snapshot() {
    local key state
    PROXY_PRESENT=0; PROXY_JSON='{'
    for key in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy ALL_PROXY all_proxy; do
        state='not configured'
        if [[ -n ${!key-} ]]; then
            state='configured (value withheld)'
            case $key in HTTPS_PROXY|https_proxy|ALL_PROXY|all_proxy) PROXY_PRESENT=1;; esac
        fi
        emit "$(printf '%-13s %s' "$key:" "$state")"
        [[ $PROXY_JSON == '{' ]] || PROXY_JSON+=','
        PROXY_JSON+="\"$key\":$(json_string "$state")"
    done
    PROXY_JSON+='}'
}
load_sites() {
    local line code label site rum extra n=0
    SITE_CODES=(); declare -gA SITE_LABELS=() SITE_DOMAINS=() SITE_RUM=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line || $line == \#* ]] && continue
        [[ ${line//[^|]/} == '|||' ]] || { error 'Malformed sites manifest'; return 1; }
        IFS='|' read -r code label site rum extra <<< "$line"
        # shellcheck disable=SC2015
        [[ $code =~ ^[a-z0-9-]+$ && $label =~ ^[A-Z0-9-]+$ && -z ${SITE_LABELS[$code]-} ]] && valid_host "$site" && valid_host "$rum" || { error 'Invalid site record'; return 1; }
        SITE_CODES+=("$code"); SITE_LABELS[$code]=$label; SITE_DOMAINS[$code]=$site; SITE_RUM[$code]=$rum; ((n+=1))
    done < "$ROOT/config/sites.conf"
    ((n==9)) || { error 'Expected nine site definitions'; return 1; }
}
parse_record() {
    IFS='|' read -r id category label template port protocol os test_type requirement sites path notes source <<< "$1"
}
validate_manifest() {
    local line line_no=0 host site_key count=0
    local -A ids=()
    RECORDS=(); VERIFIED=''
    while IFS= read -r line || [[ -n $line ]]; do
        ((line_no+=1))
        if [[ $line == '# last_verified_against_datadog_docs='* ]]; then VERIFIED=${line#*=}; fi
        [[ -z $line || $line == \#* ]] && continue
        if [[ ${line//[^|]/} != '||||||||||||' || $line =~ [[:cntrl:]] ]]; then error "Malformed endpoint record at line $line_no"; return 1; fi
        parse_record "$line"
        if [[ ! $id =~ ^[a-z0-9_-]+$ || ! $category =~ ^[a-z0-9_-]+$ || -n ${ids[$id]-} || -z $label || ! $port =~ ^[1-9][0-9]{0,4}$ ]] || ((10#$port>65535)); then
            error "Invalid endpoint identity/port at line $line_no"; return 1
        fi
        ids[$id]=1
        case $protocol in https|tcp|udp) ;; *) error "Invalid protocol at line $line_no"; return 1;; esac
        case $os in all|linux|windows|desktop) ;; *) error "Invalid OS at line $line_no"; return 1;; esac
        case $test_type in full|server_sanity_only|wildcard|version|ntp|manual|excluded) ;; *) error "Invalid test type at line $line_no"; return 1;; esac
        case $requirement in required|informational) ;; *) error "Invalid requirement at line $line_no"; return 1;; esac
        [[ $path =~ ^/[a-zA-Z0-9/_.-]*$ && $source == https://* && $source != *' '* && -n $sites && -n $template ]] || { error "Invalid path/source/scope at line $line_no"; return 1; }
        [[ $sites != ,* && $sites != *, && $sites != *,,* ]] || { error "Invalid site list at line $line_no"; return 1; }
        if [[ $sites != all ]]; then
            local -a allowed
            IFS=, read -r -a allowed <<< "$sites"
            for site_key in "${allowed[@]}"; do [[ -n ${SITE_LABELS[$site_key]-} ]] || { error "Invalid site scope at line $line_no"; return 1; }; done
        fi
        host=${template//\{site\}/example.com}; host=${host//\{rum\}/example.com}; host=${host//\{version\}/7-0-0}
        [[ $test_type != wildcard ]] || host=${host#\*.}
        if [[ $test_type != manual && $test_type != excluded ]]; then
            valid_host "$host" || { error "Invalid hostname/template at line $line_no"; return 1; }
            if [[ $test_type == ntp ]]; then
                [[ $protocol == udp && $port == 123 ]] || { error "NTP requires UDP/123 at line $line_no"; return 1; }
            else
                [[ $protocol == https ]] || { error "Unsupported active protocol at line $line_no"; return 1; }
            fi
        fi
        [[ $test_type != wildcard || $template == \*.* ]] || return 1
        [[ $test_type != version || $template == *'{version}'* ]] || return 1
        [[ $template != *'{version}'* || $test_type == version ]] || { error "Version token in non-version record at line $line_no"; return 1; }
        [[ $test_type != server_sanity_only || $requirement == informational ]] || { error "Browser sanity must be informational at line $line_no"; return 1; }
        RECORDS+=("$line"); ((count+=1))
    done < "$ROOT/config/endpoints.conf"
    [[ $VERIFIED =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && $count -gt 0 ]] || { error 'Missing manifest verification date or empty manifest'; return 1; }
}
set_agent_version() {
    [[ $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    AGENT_VERSION="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    AGENT_VERSION_DISPLAY="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
}
detect_agent_version() {
    local release_url rc
    AGENT_VERSION=''; AGENT_VERSION_DISPLAY=''; AGENT_VERSION_SOURCE='none'; AGENT_VERSION_DETAIL=''
    if [[ -n ${CLI_AGENT_VERSION-} ]]; then
        set_agent_version "$CLI_AGENT_VERSION" || { error 'Invalid --agent-version; use X.Y.Z'; return 1; }
        AGENT_VERSION_SOURCE=flag; return 0
    fi
    if [[ -n ${DD_PREFLIGHT_AGENT_VERSION-} ]]; then
        set_agent_version "$DD_PREFLIGHT_AGENT_VERSION" || { error 'Invalid DD_PREFLIGHT_AGENT_VERSION; use X.Y.Z'; return 1; }
        AGENT_VERSION_SOURCE=environment; return 0
    fi
    # GitHub's latest-release redirect selects a stable release without parsing
    # a changelog or requiring jq/Python. Only accept an exact official tag URL.
    release_url=$(SSLKEYLOGFILE= curl --disable --silent --show-error --fail --head --location \
        --proto '=https' --proto-redir '=https' --max-redirs 3 \
        --connect-timeout 5 --max-time 12 --output /dev/null --write-out '%{url_effective}' \
        'https://github.com/DataDog/datadog-agent/releases/latest' 2>/dev/null)
    rc=$?
    if ((rc!=0)); then
        AGENT_VERSION_DETAIL="Latest release lookup failed (curl exit $rc); use --agent-version X.Y.Z."
    elif [[ $release_url =~ ^https://github\.com/DataDog/datadog-agent/releases/tag/([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        set_agent_version "${BASH_REMATCH[1]}" || return 1
        AGENT_VERSION_SOURCE=latest-release
    else
        AGENT_VERSION_DETAIL='Latest release lookup returned no stable X.Y.Z tag; use --agent-version X.Y.Z.'
    fi
    return 0
}
classify_result() {
    local field fields='dns cname tcp tls http'
    if [[ ${E[classification]} == 'NOT APPLICABLE' ]]; then E[status]='NOT APPLICABLE'; E[impact]=PASS; return; fi
    E[status]=PASS
    [[ ${E[test_type]-} != ntp ]] || fields='dns ntp'
    for field in $fields; do
        case ${E[$field]} in
            FAIL) E[status]=FAIL;;
            WARN|SKIPPED|'NOT DIRECTLY TESTABLE') [[ ${E[status]} == FAIL ]] || E[status]=WARN;;
        esac
    done
    E[impact]=${E[status]}
    if [[ $requirement == informational && ${E[impact]} == FAIL ]]; then E[impact]=WARN; fi
    if [[ ${E[test_type]-} != ntp ]] && ((PROXY_PRESENT)) && [[ ${E[http]} == PASS || ${E[http]} == WARN ]] && [[ ${E[curl_tls]} == PASS && ${E[impact]} == FAIL ]]; then
        E[impact]=WARN; add_note 'Environment-route HTTPS succeeded despite direct-path failures; proxy/NO_PROXY routing and Agent proxy configuration require review'
    fi
}
