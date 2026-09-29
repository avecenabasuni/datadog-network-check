#!/usr/bin/env bash
set -uo pipefail

if ((BASH_VERSINFO[0]<4)); then printf 'Bash 4 or later is required.\n' >&2; exit 3; fi
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 3
# shellcheck source=lib/utils.sh
source "$ROOT/lib/utils.sh" || exit 3
# shellcheck source=lib/dns.sh
source "$ROOT/lib/dns.sh" || exit 3
# shellcheck source=lib/tcp.sh
source "$ROOT/lib/tcp.sh" || exit 3
# shellcheck source=lib/tls.sh
source "$ROOT/lib/tls.sh" || exit 3
# shellcheck source=lib/http.sh
source "$ROOT/lib/http.sh" || exit 3
# shellcheck source=lib/reporting.sh
source "$ROOT/lib/reporting.sh" || exit 3

# Internal limits, seconds. No background probing or package installation.
DNS_TIMEOUT=5 TCP_TIMEOUT=5 TLS_TIMEOUT=8 HTTP_TIMEOUT=12 MAX_IP_PROBES=4

main() {
    local choice i dep line host field state missing=0
    SITE=''
    while (($#)); do
        case $1 in
            --site) (($#>=2)) || { error '--site requires a value'; return 3; }; SITE=${2,,}; shift 2;;
            --help|-h) printf 'Usage: ./dd-network-check.sh [--site SITE]\nDefault: interactive site selection followed by a full scan.\n--quick and --category are reserved for a future release.\n'; return 0;;
            *) error "Unsupported argument: $1"; return 3;;
        esac
    done
    [[ $(uname -s) == Linux ]] || { error 'v0.1 supports Linux only'; return 3; }
    for dep in curl awk sed grep head tr date hostname mktemp mkdir mv rm rmdir; do
        have "$dep" || { error "Required utility unavailable: $dep"; missing=1; }
    done
    ((missing==0)) || return 3
    load_sites && validate_manifest || return 3
    printf '========================================\n Datadog Network Preflight Checker\n========================================\n'
    if [[ -z $SITE ]]; then
        printf '\nSelect Datadog Site:\n\n'; i=0
        for choice in "${SITE_CODES[@]}"; do ((i+=1)); printf '%s) %s\n' "$i" "${SITE_LABELS[$choice]}"; done
        while :; do
            printf '\nChoice: '
            IFS= read -r choice || { error 'Site selection ended; use --site for unattended runs'; return 3; }
            if [[ $choice =~ ^[1-9]$ ]]; then SITE=${SITE_CODES[choice-1]}; break; fi
            printf 'Choose a number from 1 to 9.\n'
        done
    fi
    [[ $SITE =~ ^[a-z0-9-]+$ && -n ${SITE_LABELS[$SITE]-} ]] || { error 'Unknown Datadog site'; return 3; }
    MACHINE=$(hostname | clean); TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    OS_NAME=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"' | clean)
    OS_NAME=${OS_NAME:-Linux}
    report_init || { error 'Cannot initialize private reports'; return 3; }
    trap 'error "Scan interrupted; incomplete files retained in reports, no final readiness report"; exit 3' INT TERM HUP
    emit '========================================'; emit ' DATADOG NETWORK PREFLIGHT'; emit '========================================'
    emit "Host       : $MACHINE"; emit "OS         : $OS_NAME"; emit "Site       : ${SITE_LABELS[$SITE]} (${SITE_DOMAINS[$SITE]})"
    emit "Timestamp  : $TIMESTAMP"; emit "Docs review: $VERIFIED"; emit ''
    emit 'Dependency availability'
    DEPENDENCY_JSON='{'
    for dep in bash curl getent dig nslookup openssl timeout nc; do
        state=unavailable; have "$dep" && state=available
        emit "$(printf '%-12s %s' "$dep" "$state")"
        [[ $DEPENDENCY_JSON == '{' ]] || DEPENDENCY_JSON+=','
        DEPENDENCY_JSON+="\"$dep\":\"$state\""
    done
    DEPENDENCY_JSON+='}'
    emit ''; emit 'Proxy Environment'; proxy_snapshot
    emit 'Direct DNS/TCP/OpenSSL probes bypass proxies; curl honors existing HTTPS/ALL_PROXY and NO_PROXY settings.'
    emit 'Proxy values are withheld to avoid disclosing credentials. curl ignores uppercase HTTP_PROXY.'
    detect_agent_version; emit "Installed stable Agent version: ${AGENT_VERSION:-not determined}"
    emit 'Sequential full scan; each endpoint may take up to about one minute when unreachable.'
    declare -gA E=() CATEGORY_STATUS=()
    declare -ga CATEGORY_ORDER=() BLOCKERS=() ALLOWLIST=() UNTESTED=()
    OVERALL=READY; LAST_CATEGORY=''
    for line in "${RECORDS[@]}"; do
        parse_record "$line"; reset_result
        host=${template//\{site\}/${SITE_DOMAINS[$SITE]}}; host=${host//\{rum\}/${SITE_RUM[$SITE]}}
        E[id]=$id; E[category]=$category; E[label]=$label; E[hostname]=$host; E[port]=$port
        E[protocol]=$protocol; E[applicable_os]=$os; E[test_type]=$test_type; E[requirement]=$requirement; E[source]=$source; E[notes]=$notes
        if [[ $os == windows || $os == desktop || $test_type == excluded || ( $sites != all && ,$sites, != *",$SITE,"* ) ]]; then
            E[classification]='NOT APPLICABLE'
            for field in dns cname tcp tls http; do E[$field]='NOT APPLICABLE'; E[${field}_detail]='Outside Linux/site/server scope'; done
            add_note 'NOT APPLICABLE TO SERVER-SIDE PREFLIGHT for this Linux/site selection'
        elif [[ $test_type == wildcard || $test_type == manual || ( $test_type == version && -z $AGENT_VERSION ) ]]; then
            E[classification]='NOT DIRECTLY TESTABLE'
            [[ $test_type != wildcard ]] || E[classification]='ALLOWLIST REQUIREMENT'
            for field in dns cname tcp tls http; do E[$field]='NOT DIRECTLY TESTABLE'; E[${field}_detail]='Manual review required; no network probe issued'; done
        else
            if [[ $test_type == version ]]; then host=${host//\{version\}/$AGENT_VERSION}; E[hostname]=$host; fi
            [[ $test_type != server_sanity_only ]] || E[classification]='SERVER-SIDE SANITY CHECK ONLY'
            dns_check "$host"; tcp_check; tls_check "$host"
            # curl may resolve through a proxy even after local DNS/TCP failure.
            if [[ ${E[dns]} != FAIL || -n ${E[ips]} ]] || ((PROXY_PRESENT)); then http_check "$host"
            else E[http_detail]='Local DNS hard failure and no HTTPS proxy configured'; fi
        fi
        classify_result; report_endpoint
    done
    report_finish || { error 'Failed to finalize reports'; return 3; }
    case $OVERALL in READY) return 0;; 'READY WITH WARNINGS') return 1;; BLOCKED) return 2;; *) return 3;; esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; exit $?; fi
