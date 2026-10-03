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
# shellcheck source=lib/ntp.sh
source "$ROOT/lib/ntp.sh" || exit 3
# shellcheck source=lib/tls.sh
source "$ROOT/lib/tls.sh" || exit 3
# shellcheck source=lib/http.sh
source "$ROOT/lib/http.sh" || exit 3
# shellcheck source=lib/proxy.sh
source "$ROOT/lib/proxy.sh" || exit 3
# shellcheck source=lib/reporting.sh
source "$ROOT/lib/reporting.sh" || exit 3

# Internal limits, seconds. No background probing or package installation.
# MAX_IP_PROBES is consumed by sourced DNS/TCP modules.
# shellcheck disable=SC2034
TOOL_VERSION=0.2.0
DNS_TIMEOUT=5 TCP_TIMEOUT=5 TLS_TIMEOUT=8 HTTP_TIMEOUT=12 MAX_IP_PROBES=4
NTP_TIMEOUT=5 NTP_MAX_IP_PROBES=2
HTTP_MAX_ATTEMPTS=2 TLS_MAX_ATTEMPTS=2

main() {
    local choice i dep line host field state missing=0 available_tools='' unavailable_tools=''
    SITE=''; CLI_AGENT_VERSION=''; TERMINAL_NO_BANNER=0; TERMINAL_QUIET=0
    ROUTE_MODE=environment; PROXY_URL=''; PROXY_USER=''; PROXY_PASSWORD=''; PROXY_PASSWORD_STDIN=0; PROXY_AUTH_PRESENT=0
    export -n PROXY_URL PROXY_USER PROXY_PASSWORD PROXY_HOST
    declare -ga NTP_HOSTS=()
    while (($#)); do
        case $1 in
            --site) (($#>=2)) || { error '--site requires a value'; return 3; }; SITE=${2,,}; shift 2;;
            --agent-version) (($#>=2)) || { error '--agent-version requires X.Y.Z'; return 3; }; CLI_AGENT_VERSION=$2; shift 2;;
            --ntp-host) (($#>=2)) || { error '--ntp-host requires a hostname or IP'; return 3; }; add_ntp_host "$2" || return 3; shift 2;;
            --proxy) (($#>=2)) && [[ $ROUTE_MODE == environment ]] || { error 'Use one --proxy URL or --direct'; return 3; }; ROUTE_MODE=explicit; PROXY_URL=$2; shift 2;;
            --direct) [[ $ROUTE_MODE == environment ]] || { error 'Use one --proxy URL or --direct'; return 3; }; ROUTE_MODE=direct; shift;;
            --proxy-user) (($#>=2)) && [[ -n $2 ]] || { error '--proxy-user requires a username'; return 3; }; PROXY_USER=$2; shift 2;;
            --proxy-password-stdin) PROXY_PASSWORD_STDIN=1; shift;;
            --quiet) TERMINAL_QUIET=1; shift;;
            --no-banner) TERMINAL_NO_BANNER=1; shift;;
            --help|-h) printf 'Usage: ./dd-network-check.sh [--site SITE] [--agent-version X.Y.Z] [--ntp-host HOST] [--proxy URL | --direct] [--proxy-user USER] [--proxy-password-stdin] [--quiet] [--no-banner]\nDefault: full scan using the latest stable Agent release and documented public NTP fallback pools.\n--agent-version overrides DD_PREFLIGHT_AGENT_VERSION and the GitHub latest-release lookup.\n--ntp-host replaces public NTP pools with an explicit customer target (repeat for up to 8 targets). UDP/123.\n--proxy selects an HTTP/HTTPS forward proxy for all HTTPS tests. --direct bypasses environment proxies.\n--proxy-user enables Basic authentication. Password is read silently or with --proxy-password-stdin and --site.\n--quiet uses a compact terminal header. --no-banner hides the header.\n--quick and --category are reserved for a future release.\n'; return 0;;
            *) error "Unsupported argument: $1"; return 3;;
        esac
    done
    ((PROXY_PASSWORD_STDIN==0)) || [[ -n $SITE ]] || { error '--proxy-password-stdin requires --site'; return 3; }
    [[ $(uname -s) == Linux ]] || { error 'Linux only'; return 3; }
    for dep in curl awk sed grep head tee wc tr date hostname mktemp mkdir mv rm rmdir; do
        have "$dep" || { error "Required utility unavailable: $dep"; missing=1; }
    done
    ((missing==0)) || return 3
    load_sites && validate_manifest || return 3
    select_ntp_targets
    TERMINAL_TTY=0; [[ -t 1 ]] && TERMINAL_TTY=1
    TERMINAL_WIDTH=$(terminal_width)
    if [[ -z $SITE ]]; then
        printf '\n[ SELECT DATADOG SITE ]\n'; i=0
        for choice in "${SITE_CODES[@]}"; do
            ((i+=1))
            printf '  %-14s' "$i) ${SITE_LABELS[$choice]}"
            ((i%3)) || printf '\n'
        done
        while :; do
            printf '\nChoice: '
            IFS= read -r choice || { error 'Site selection ended; use --site for unattended runs'; return 3; }
            if [[ $choice =~ ^[1-9]$ ]]; then SITE=${SITE_CODES[choice-1]}; break; fi
            printf 'Choose a number from 1 to 9.\n'
        done
        printf '\n'
    fi
    [[ $SITE =~ ^[a-z0-9-]+$ && -n ${SITE_LABELS[$SITE]-} ]] || { error 'Unknown Datadog site'; return 3; }
    proxy_configure || return 3
    MACHINE=$(hostname | clean); TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    OS_NAME=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '"' | clean)
    OS_NAME=${OS_NAME:-Linux}
    terminal_banner
    report_init || { error 'Cannot initialize private reports'; return 3; }
    trap terminal_interrupt INT TERM HUP
    trap terminal_progress_clear EXIT
    emit '========================================'; emit ' DATADOG NETWORK PREFLIGHT'; emit '========================================'
    emit "Host       : $MACHINE"; emit "OS         : $OS_NAME"; emit "Site       : ${SITE_LABELS[$SITE]} (${SITE_DOMAINS[$SITE]})"
    emit "Timestamp  : $TIMESTAMP"; emit "Docs review: $VERIFIED"; emit ''
    emit "Version    : $TOOL_VERSION"
    emit 'Dependency availability'
    DEPENDENCY_JSON='{'
    for dep in bash curl getent dig nslookup openssl timeout nc dd od sleep; do
        state=unavailable; have "$dep" && state=available
        emit "$(printf '%-12s %s' "$dep" "$state")"
        if [[ $state == available ]]; then available_tools+=" $dep"
        else unavailable_tools+=" $dep"; fi
        [[ $DEPENDENCY_JSON == '{' ]] || DEPENDENCY_JSON+=','
        DEPENDENCY_JSON+="\"$dep\":\"$state\""
    done
    DEPENDENCY_JSON+='}'
    emit ''; emit 'Proxy Environment'; proxy_snapshot
    emit "Selected HTTPS route: $ROUTE_MODE. Proxy authentication present: $PROXY_AUTH_PRESENT"
    emit 'DNS/TCP/OpenSSL are direct diagnostics. Explicit proxy determines HTTPS readiness and overrides environment exclusions.'
    emit 'Proxy values are withheld to avoid disclosing credentials. curl ignores uppercase HTTP_PROXY.'
    emit "NTP targets: $NTP_TARGET_SOURCE; direct UDP/123; HTTP proxy settings do not apply."
    [[ $NTP_TARGET_SOURCE != documented-public-fallback ]] || emit 'Agent may select private cloud or configured NTP servers; use --ntp-host to test those instead.'
    detect_agent_version || return 3
    emit "Agent version used: ${AGENT_VERSION_DISPLAY:-not determined} (${AGENT_VERSION_SOURCE})"
    [[ -z $AGENT_VERSION_DETAIL ]] || emit "$AGENT_VERSION_DETAIL"
    emit 'Sequential full scan; bounded retries on transient failures. Slow endpoints may take over one minute.'
    terminal_intro "${available_tools# }" "${unavailable_tools# }"
    declare -gA E=() CATEGORY_STATUS=()
    declare -gA TERMINAL_SNAP=() TERMINAL_COUNTS=() TERMINAL_GROUP_COUNTS=() TERMINAL_GROUP_HOSTS=() TERMINAL_GROUP_HOST_SEEN=()
    declare -ga CATEGORY_ORDER=() BLOCKERS=() ALLOWLIST=() UNTESTED=() TERMINAL_ORDER=() TERMINAL_NOTE_KEY=() TERMINAL_OTHER_REQUIREMENTS=()
    OVERALL=READY; LAST_CATEGORY=''; LAST_TERMINAL_CATEGORY=''; DIRECT_PASS=0; DIRECT_WARN=0; DIRECT_FAIL=0
    TERMINAL_UNSPECIFIED_COUNT=0; TERMINAL_PROGRESS_DONE=0; TERMINAL_PROGRESS_TICK=0
    TERMINAL_PROGRESS_TOTAL=$(terminal_destination_count)
    terminal_table_header
    for line in "${RECORDS[@]}"; do
        parse_record "$line"; reset_result
        host=${template//\{site\}/${SITE_DOMAINS[$SITE]}}; host=${host//\{rum\}/${SITE_RUM[$SITE]}}
        if [[ $test_type == wildcard ]]; then
            # Docs list these as firewall configuration patterns, not network
            # destinations. Keep their guidance outside endpoint test results.
            if [[ $os != windows && $os != desktop && ( $sites == all || ,$sites, == *",$SITE,"* ) ]]; then
                ALLOWLIST+=("$host")
            fi
            continue
        fi
        E[id]=$id; E[category]=$category; E[label]=$label; E[hostname]=$host; E[port]=$port
        E[protocol]=$protocol; E[applicable_os]=$os; E[test_type]=$test_type; E[requirement]=$requirement; E[source]=$source; E[notes]=$notes
        [[ $test_type != ntp ]] || E[ntp_target_source]=$NTP_TARGET_SOURCE
        if [[ $os == windows || $os == desktop || $test_type == excluded || ( $sites != all && ,$sites, != *",$SITE,"* ) ]]; then
            E[classification]='NOT APPLICABLE'
            for field in dns cname tcp tls http; do E[$field]='NOT APPLICABLE'; E[${field}_detail]='Outside Linux/site/server scope'; done
            add_note 'NOT APPLICABLE TO SERVER-SIDE PREFLIGHT for this Linux/site selection'
        elif [[ $test_type == manual || ( $test_type == version && -z $AGENT_VERSION ) ]]; then
            terminal_category_start
            TERMINAL_PROGRESS_HOST=$host; terminal_progress
            E[classification]='NOT DIRECTLY TESTABLE'
            for field in dns cname tcp tls http; do E[$field]='NOT DIRECTLY TESTABLE'; E[${field}_detail]='Manual review required; no network probe issued'; done
            if [[ $test_type == version ]]; then
                add_note "$AGENT_VERSION_DETAIL"
            fi
        elif [[ $test_type == ntp ]]; then
            terminal_category_start
            TERMINAL_PROGRESS_HOST=$host; terminal_progress
            ntp_resolve "$host"; ntp_check
        else
            if [[ $test_type == version ]]; then host=${host//\{version\}/$AGENT_VERSION}; E[hostname]=$host; fi
            terminal_category_start
            TERMINAL_PROGRESS_HOST=$host; terminal_progress
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
