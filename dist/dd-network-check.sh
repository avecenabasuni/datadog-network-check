#!/usr/bin/env bash
# GENERATED FILE: edit source modules/manifests, then run scripts/build_standalone.py.
# Includes all runtime modules and both reviewed manifests. No runtime extraction.
# source_sha256=8c437ac7709f242d50454424b23615b1bf40296aa9888429424b71def97e51a9
set -uo pipefail

if ((BASH_VERSINFO[0]<4)); then printf 'Bash 4 or later is required.\n' >&2; exit 3; fi
# Standalone mode writes reports beneath the invocation directory.
ROOT=$(pwd -P) || exit 3
# BEGIN GENERATED MODULE: lib/utils.sh
#!/usr/bin/env bash
# Libraries return results in the caller-owned associative array E.
# Site and Agent globals are read by the entry point after this module is sourced.
# shellcheck disable=SC2154,SC2034
have() { command -v "$1" >/dev/null 2>&1; }
error() { local message=$*; printf 'ERROR: %s\n' "${message//;/.}" >&2; }
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
    done <<'DD_PREFLIGHT_SITES_MANIFEST_EOF'
# last_verified_against_datadog_docs=2026-09-29
# source=https://docs.datadoghq.com/getting_started/site/
# rum_source=https://docs.datadoghq.com/real_user_monitoring/
# code|label|site_parameter|rum_domain
us1|US1|datadoghq.com|browser-intake-datadoghq.com
us3|US3|us3.datadoghq.com|browser-intake-us3-datadoghq.com
us5|US5|us5.datadoghq.com|browser-intake-us5-datadoghq.com
eu1|EU1|datadoghq.eu|browser-intake-datadoghq.eu
ap1|AP1|ap1.datadoghq.com|browser-intake-ap1-datadoghq.com
ap2|AP2|ap2.datadoghq.com|browser-intake-ap2-datadoghq.com
uk1|UK1|uk1.datadoghq.com|browser-intake-uk1-datadoghq.com
us1-fed|US1-FED|ddog-gov.com|browser-intake-ddog-gov.com
us2-fed|US2-FED|us2.ddog-gov.com|browser-intake-us2-ddog-gov.com
DD_PREFLIGHT_SITES_MANIFEST_EOF
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
    done <<'DD_PREFLIGHT_ENDPOINTS_MANIFEST_EOF'
# last_verified_against_datadog_docs=2026-09-29
# id|category|label|hostname_template|port|protocol|applicable_os|test_type|requirement|sites|path|notes|source
install|installation|install distribution|install.datadoghq.com|443|https|linux|full|required|all|/|Domain reachability only; no packages or scripts downloaded|https://docs.datadoghq.com/agent/configuration/network/
apt|installation|apt distribution|apt.datadoghq.com|443|https|linux|full|required|all|/|Domain reachability only; no packages or scripts downloaded|https://docs.datadoghq.com/agent/configuration/network/
yum|installation|yum distribution|yum.datadoghq.com|443|https|linux|full|required|all|/|Domain reachability only; no packages or scripts downloaded|https://docs.datadoghq.com/agent/configuration/network/
keys|installation|keys distribution|keys.datadoghq.com|443|https|linux|full|required|all|/|Domain reachability only; no packages or scripts downloaded|https://docs.datadoghq.com/agent/configuration/network/
windows-agent|installation|windows-agent distribution|windows-agent.datadoghq.com|443|https|windows|full|required|all|/|Domain reachability only; no packages or scripts downloaded|https://docs.datadoghq.com/agent/configuration/network/
agent-wildcard|agent|Agent metrics and flare allowlist|*.agent.{site}|443|https|all|wildcard|required|all|/|Documented firewall inclusion pattern; configuration guidance only; not an endpoint test|https://docs.datadoghq.com/agent/configuration/network/
agent-metrics|agent|Version-specific metrics intake|{version}-app.agent.{site}|443|https|all|version|required|all|/|Official Agent version naming convention; latest stable release by default or explicit version override|https://docs.datadoghq.com/agent/configuration/network/
agent-flare|agent|Version-specific flare destination|{version}-flare.agent.{site}|443|https|all|version|informational|all|/|Destination connectivity only; no flare created or uploaded|https://docs.datadoghq.com/agent/configuration/network/
api|api|Agent API|api.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
legacy-api|api|Legacy Agent API|app.{site}|443|https|all|full|informational|all|/|Only Agent older than 6.18/7.18; documented legacy hostname|https://docs.datadoghq.com/agent/configuration/network/
trace|apm|APM traces|trace.agent.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
telemetry|instrumentation|Instrumentation telemetry|instrumentation-telemetry-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
llmobs|llm|LLM Observability|llmobs-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
process|process_usm|Live Processes / Live Containers / Cloud Network Monitoring / USM|process.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
images|containers|Container images|contimage-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
orchestrator|containers|Orchestrator|orchestrator.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
lifecycle|containers|Container lifecycle|contlcycle-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
profile|profiling|Continuous Profiling|intake.profile.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
sbom|security|Cloud Security Vulnerabilities SBOM|sbom-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
config|remote_configuration|Agent Remote Configuration|config.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
ndm|network_devices|Network Device Monitoring|ndm-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
snmp|network_devices|SNMP traps intake|snmp-traps-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
ndmflow|network_devices|Network device flows|ndmflow-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
netpath|network_path|Network Path intake|netpath-intake.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
logs-agent|logs|Agent logs HTTPS|agent-http-intake.logs.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
logs-custom|logs|Custom forwarder logs HTTPS|http-intake.logs.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/logs/log_collection/#logging-endpoints
ip-ranges|ip_ranges|Datadog IP ranges|ip-ranges.{site}|443|https|all|full|required|all|/|-|https://docs.datadoghq.com/agent/configuration/network/
dbm-metrics-intake|dbm|Database Monitoring dbm-metrics-intake|dbm-metrics-intake.{site}|443|https|all|full|required|us1,us3,us5,eu1,ap1,ap2,uk1|/|Network Traffic page lists DBM for commercial sites only; government coverage is unverified|https://docs.datadoghq.com/agent/configuration/network/
dbquery-intake|dbm|Database Monitoring dbquery-intake|dbquery-intake.{site}|443|https|all|full|required|us1,us3,us5,eu1,ap1,ap2,uk1|/|Network Traffic page lists DBM for commercial sites only; government coverage is unverified|https://docs.datadoghq.com/agent/configuration/network/
softinv-intake|software_inventory|End User Device Monitoring softinv-intake|softinv-intake.{site}|443|https|all|full|informational|us1,us3,us5,eu1,ap1,ap2,uk1|/|Conditional software inventory / End User Device Monitoring destination; feature and platform applicability require review|https://docs.datadoghq.com/agent/configuration/network/
eudm-intake|software_inventory|End User Device Monitoring eudm-intake|eudm-intake.{site}|443|https|all|full|informational|us1,us3,us5,eu1,ap1,ap2,uk1|/|Conditional software inventory / End User Device Monitoring destination; feature and platform applicability require review|https://docs.datadoghq.com/agent/configuration/network/
intake-synthetics|synthetics|Private Synthetic worker intake.synthetics|intake.synthetics.{site}|443|https|all|full|informational|all|/|Conditional: only when this VM hosts a private worker; intake-v2 is a legacy worker destination|https://docs.datadoghq.com/agent/configuration/network/
intake-v2-synthetics|synthetics|Private Synthetic worker intake-v2.synthetics|intake-v2.synthetics.{site}|443|https|all|full|informational|all|/|Conditional: only when this VM hosts a private worker; intake-v2 is a legacy worker destination|https://docs.datadoghq.com/agent/configuration/network/
rum|rum|Browser RUM intake|{rum}|443|https|all|server_sanity_only|informational|all|/|SERVER-SIDE SANITY CHECK ONLY; does not validate end-user browser connectivity|https://docs.datadoghq.com/real_user_monitoring/
rum-rc|rum|RUM Remote Configuration|sdk-configuration.{rum}|443|https|all|server_sanity_only|informational|us1,us3,us5,eu1,ap1,ap2,uk1|/|Documented sdk-configuration subdomain; unsupported on government sites; server sanity only|https://docs.datadoghq.com/real_user_monitoring/remote_configuration/
rum-wildcard|rum|RUM SDK subdomain allowlist|*.{rum}|443|https|all|wildcard|informational|us1,us3,us5,eu1,ap1,ap2,uk1|/|Documented firewall inclusion pattern; configuration guidance only; normalized using explicit RUM mapping; apex intake must also be allowed|https://docs.datadoghq.com/real_user_monitoring/remote_configuration/
rum-quota|rum|Browser Profiling quota|quota.{rum}|443|https|all|server_sanity_only|informational|all|/|SERVER-SIDE SANITY CHECK ONLY; conditional on Browser Profiling|https://docs.datadoghq.com/real_user_monitoring/
browser-logs|rum|Browser SDK logs|logs.{rum}|443|https|all|server_sanity_only|informational|all|/|SERVER-SIDE SANITY CHECK ONLY|https://docs.datadoghq.com/logs/log_collection/#logging-endpoints
public-ip-38|network_path_optional|Optional source public IP discovery|icanhazip.com|443|https|all|full|informational|all|/|Third-party endpoint documented for Network Path Agent 7.75+; optional feature|https://docs.datadoghq.com/agent/configuration/network/
public-ip-39|network_path_optional|Optional source public IP discovery|ipinfo.io|443|https|all|full|informational|all|/|Third-party endpoint documented for Network Path Agent 7.75+; optional feature|https://docs.datadoghq.com/agent/configuration/network/
public-ip-40|network_path_optional|Optional source public IP discovery|checkip.amazonaws.com|443|https|all|full|informational|all|/|Third-party endpoint documented for Network Path Agent 7.75+; optional feature|https://docs.datadoghq.com/agent/configuration/network/
public-ip-41|network_path_optional|Optional source public IP discovery|api.ipify.org|443|https|all|full|informational|all|/|Third-party endpoint documented for Network Path Agent 7.75+; optional feature|https://docs.datadoghq.com/agent/configuration/network/
public-ip-42|network_path_optional|Optional source public IP discovery|whatismyip.akamai.com|443|https|all|full|informational|all|/|Third-party endpoint documented for Network Path Agent 7.75+; optional feature|https://docs.datadoghq.com/agent/configuration/network/
registry-43|container_registries|Container image registry|registry.datadoghq.com|443|https|all|full|informational|all|/|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-44|container_registries|Container image registry|us-docker.pkg.dev|443|https|all|full|informational|all|/datadog-prod/public-images|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-45|container_registries|Container image registry|gcr.io|443|https|all|full|informational|all|/datadoghq|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-46|container_registries|Container image registry|eu.gcr.io|443|https|all|full|informational|all|/datadoghq|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-47|container_registries|Container image registry|asia.gcr.io|443|https|all|full|informational|all|/datadoghq|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-48|container_registries|Container image registry|datadoghq.azurecr.io|443|https|all|full|informational|all|/|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-49|container_registries|Container image registry|public.ecr.aws|443|https|all|full|informational|all|/datadog|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
registry-50|container_registries|Container image registry|docker.io|443|https|all|full|informational|all|/datadog|Conditional on chosen registry; GET reachability does not validate registry authentication or image pulls|https://docs.datadoghq.com/agent/configuration/network/
ntp0|ntp|Datadog NTP public fallback 0|0.datadog.pool.ntp.org|123|udp|all|ntp|informational|all|/|Documented public fallback; Agent may use private cloud or configured servers; use --ntp-host for customer targets|https://docs.datadoghq.com/integrations/ntp/
ntp1|ntp|Datadog NTP public fallback 1|1.datadog.pool.ntp.org|123|udp|all|ntp|informational|all|/|Documented public fallback; Agent may use private cloud or configured servers; use --ntp-host for customer targets|https://docs.datadoghq.com/integrations/ntp/
ntp2|ntp|Datadog NTP public fallback 2|2.datadog.pool.ntp.org|123|udp|all|ntp|informational|all|/|Documented public fallback; Agent may use private cloud or configured servers; use --ntp-host for customer targets|https://docs.datadoghq.com/integrations/ntp/
ntp3|ntp|Datadog NTP public fallback 3|3.datadog.pool.ntp.org|123|udp|all|ntp|informational|all|/|Documented public fallback; Agent may use private cloud or configured servers; use --ntp-host for customer targets|https://docs.datadoghq.com/integrations/ntp/
autoscaling|other_requirements|Custom Agent Autoscaling|destination-unspecified|8443|tcp|all|manual|informational|us1,eu1|/|Network page names port 8443 without destination; do not invent a hostname|https://docs.datadoghq.com/agent/configuration/network/
rc-probe|other_requirements|Remote Configuration protocol-development test|destination-unspecified|8042|tcp|all|manual|informational|us1,eu1|/|Network page names port 8042 without destination; do not invent a hostname|https://docs.datadoghq.com/agent/configuration/network/
inbound-agent|excluded|inbound-agent|not-applicable|443|https|all|excluded|informational|all|/|Local Agent receiver/debug/IPC ports are inbound; NOT APPLICABLE TO SERVER-SIDE PREFLIGHT|https://docs.datadoghq.com/agent/configuration/network/
webhooks-source|excluded|webhooks-source|not-applicable|443|https|all|excluded|informational|all|/|Datadog webhook source ranges contact third parties; NOT APPLICABLE TO SERVER-SIDE PREFLIGHT|https://docs.datadoghq.com/agent/configuration/network/
synthetics-source|excluded|synthetics-source|not-applicable|443|https|all|excluded|informational|all|/|Public Synthetic worker source ranges are not VM destinations; NOT APPLICABLE TO SERVER-SIDE PREFLIGHT|https://docs.datadoghq.com/agent/configuration/network/
legacy-tcp-logs|excluded|legacy-tcp-logs|not-applicable|443|https|all|excluded|informational|all|/|Deprecated TCP and legacy HIPAA log destinations are unsupported; use documented HTTPS intakes|https://docs.datadoghq.com/agent/configuration/network/
lambda-logs|excluded|lambda-logs|not-applicable|443|https|all|excluded|informational|all|/|Lambda-only log destinations do not originate from a Linux application VM|https://docs.datadoghq.com/agent/configuration/network/
DD_PREFLIGHT_ENDPOINTS_MANIFEST_EOF
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
# END GENERATED MODULE: lib/utils.sh
# BEGIN GENERATED MODULE: lib/dns.sh
#!/usr/bin/env bash
# E is a caller-owned associative array; ShellCheck reads its keys as variables.
# shellcheck disable=SC2154
dns_check() {
    local host=$1 output='' ip rc=0 current=$1 next depth answer seen=" $1 "
    if have getent && have timeout; then
        output=$(timeout -k 1 "$DNS_TIMEOUT" getent ahosts "$host" 2>/dev/null); rc=$?
        # NSS may suppress IPv6 on IPv4-only hosts; DNS detail below supplements it.
        while read -r ip _; do is_ip "$ip" && E[ips]+="$ip"$'\n'; done <<< "$output"
        E[dns_detail]="getent/NSS exit $rc"
        [[ -n ${E[ips]} ]] && E[dns]=PASS || E[dns]=FAIL
    else
        E[dns_detail]='getent or timeout unavailable; using DNS-tool/curl evidence where available'
    fi
    if have dig; then
        for family in A AAAA; do
            output=$(dig +time=2 +tries=1 +noall +answer "$host." "$family" 2>/dev/null)
            while read -r _ _ _ type ip _; do
                [[ $type == A || $type == AAAA ]] && is_ip "$ip" && E[ips]+="$ip"$'\n'
            done <<< "$output"
        done
        E[cname]=PASS; E[cname_detail]='No CNAME present'
        for ((depth=0;depth<8;depth++)); do
            answer=$(dig +time=2 +tries=1 +noall +comments +answer "$current." CNAME 2>/dev/null); rc=$?
            if ((rc!=0)) || [[ $answer != *'status: NOERROR'* ]]; then
                E[cname]=WARN; E[cname_detail]='CNAME query failed or returned non-NOERROR; filtering is not proven'; break
            fi
            next=$(awk '$4=="CNAME" {print $5;exit}' <<< "$answer"); next=${next%.}
            [[ -n $next ]] || break
            if ! valid_host "$next" || [[ $seen == *" $next "* ]]; then
                E[cname]=WARN; E[cname_detail]='Invalid or cyclic CNAME answer'; break
            fi
            E[cnames]+="$next"$'\n'; seen+="$next "; current=$next
            E[cname_detail]='CNAME chain observed; each hop queried'
        done
        if ((depth==8)); then E[cname]=WARN; E[cname_detail]='CNAME inspection depth limit reached'; fi
    elif have nslookup && have timeout; then
        output=$(timeout -k 1 "$DNS_TIMEOUT" nslookup "$host" 2>/dev/null); rc=$?
        while IFS= read -r ip; do is_ip "$ip" && E[ips]+="$ip"$'\n'; done < <(
            awk '/^Name:/{answer=1} answer && /^Address[ :]/ {sub(/^Address[^:]*: */, ""); print}' <<< "$output")
        answer=$(timeout -k 1 "$DNS_TIMEOUT" nslookup -type=CNAME "$host" 2>/dev/null)
        E[cnames]=$(awk '/canonical name =/ {sub(/.*canonical name = */, "");sub(/\.$/, "");print}' <<< "$answer")
        E[cname]=WARN; E[cname_detail]="nslookup partial chain inspection (lookup exit $rc)"
    else
        E[cname_detail]='dig unavailable and bounded nslookup unavailable'
    fi
    E[ips]=$(printf '%s' "${E[ips]}" | awk 'NF && !seen[$0]++')
    if [[ ${E[dns]} == SKIPPED && -n ${E[ips]} ]]; then
        E[dns]=PASS; E[dns_detail]='Resolved with DNS utility; NSS path not inspected'
    elif [[ ${E[dns]} == SKIPPED ]] && { have dig || { have nslookup && have timeout; }; }; then
        E[dns]=FAIL; E[dns_detail]='No address returned by available resolver'
    elif [[ ${E[dns]} == FAIL && -n ${E[ips]} ]]; then
        add_note 'DNS utility returned addresses but NSS resolution failed; resolver paths disagree'
    fi
}
# END GENERATED MODULE: lib/dns.sh
# BEGIN GENERATED MODULE: lib/tcp.sh
#!/usr/bin/env bash
# E and port are supplied by the caller.
# shellcheck disable=SC2154
# A separate wrapper makes TCP execution replaceable in offline tests.
# The child Bash expands its positional parameters.
# shellcheck disable=SC2016
tcp_connect() { timeout -k 1 "$TCP_TIMEOUT" bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' bash "$1" "$2" 2>&1; }
tcp_check() {
    local ip output rc good=0 bad=0 unavailable_v6=0 count=0 reason
    if ! have timeout; then E[tcp_detail]='timeout unavailable; bounded raw TCP diagnostic skipped'; return; fi
    [[ -n ${E[ips]} ]] || return
    while IFS= read -r ip; do
        ((count+=1)); if ((count>MAX_IP_PROBES)); then add_note "TCP sampled first $MAX_IP_PROBES addresses; remaining addresses untested"; break; fi
        output=$(tcp_connect "$ip" "$port"); rc=$?
        if ((rc==0)); then
            ((good+=1)); [[ -n ${E[tcp_ip]} ]] || E[tcp_ip]=$ip
            E[tcp_attempts]+="$ip PASS"$'\n'
        else
            reason="connect error $rc"
            case $output in *refused*) reason='connection refused';; *unreachable*) reason='network unreachable';; esac
            [[ $rc != 124 && $rc != 137 ]] || reason=timeout
            if [[ $ip == *:* && $reason == 'network unreachable' ]]; then
                ((unavailable_v6+=1))
            else
                ((bad+=1))
            fi
            E[tcp_attempts]+="$ip FAIL - $reason"$'\n'
        fi
    done <<< "${E[ips]}"
    E[tcp]=FAIL
    ((good==0)) || E[tcp]=PASS
    if ((good>0 && bad>0)); then E[tcp]=WARN; fi
    if ((good>0 && unavailable_v6>0)); then
        add_note "$unavailable_v6 IPv6 address probe(s) reported network unreachable; reachable addresses remain verified"
    fi
    E[tcp_detail]="$good successful, $bad other failures, $unavailable_v6 IPv6 network-unreachable probes; direct path"
}
# END GENERATED MODULE: lib/tcp.sh
# BEGIN GENERATED MODULE: lib/ntp.sh
#!/usr/bin/env bash
# NTP is direct UDP, never an HTTP/proxy or TCP-port test. Binary data stays in
# printf/socket/dd/od; Bash variables hold only octal escapes or decimal bytes.
# shellcheck disable=SC2154,SC2034
valid_ntp_host() {
    local address=$1 part count=0
    local -a parts=()
    valid_host "$address" && return 0
    [[ $address =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && return 0
    is_ip "$address" || return 1
    [[ $address == *:* ]] || return 0
    address=${address%%%*}
    [[ $address != *:::* ]] || return 1
    IFS=: read -r -a parts <<< "$address"
    for part in "${parts[@]}"; do
        [[ -n $part ]] || continue
        [[ $part =~ ^[0-9a-fA-F]{1,4}$ ]] || return 1
        ((count+=1))
    done
    if [[ $address == *::* ]]; then
        [[ ${address#*::} != *::* ]] && ((count<8))
    else
        [[ $address != :* && $address != *: ]] && ((count==8))
    fi
}
add_ntp_host() {
    local host=$1 existing
    if ! valid_ntp_host "$host"; then
        error 'Invalid --ntp-host; use a hostname or unbracketed IP without a port'; return 1
    fi
    for existing in "${NTP_HOSTS[@]}"; do [[ $existing != "$host" ]] || return 0; done
    ((${#NTP_HOSTS[@]}<8)) || { error 'At most 8 distinct --ntp-host targets are supported'; return 1; }
    NTP_HOSTS+=("$host")
}
select_ntp_targets() {
    local line host index=0
    local -a selected=()
    NTP_TARGET_SOURCE=documented-public-fallback
    ((${#NTP_HOSTS[@]})) || return 0
    NTP_TARGET_SOURCE=explicit-customer-targets
    for line in "${RECORDS[@]}"; do
        parse_record "$line"
        if [[ $test_type == ntp ]]; then
            # Insert overrides at the first NTP record, preserving category order.
            if ((index==0)); then
                for host in "${NTP_HOSTS[@]}"; do
                    ((index+=1))
                    selected+=("ntp-custom-$index|ntp|Customer NTP target|$host|123|udp|all|ntp|required|all|/|Explicit customer target; no public fallback; connectivity only, clock synchronization not assessed|https://docs.datadoghq.com/integrations/ntp/")
                done
            fi
        else selected+=("$line"); fi
    done
    RECORDS=("${selected[@]}")
}
ntp_resolve() {
    local host=$1 field
    E[ntp]=SKIPPED; E[ntp_detail]='Not attempted'
    for field in tcp tls http; do
        E[$field]='NOT APPLICABLE'; E[${field}_detail]='NTP uses UDP; this HTTPS stage does not apply'
    done
    E[curl_tls]='NOT APPLICABLE'
    if is_ip "$host"; then
        E[ips]=$host; E[dns]=PASS; E[dns_detail]='Explicit IP target; DNS lookup not required'
        E[cname]='NOT APPLICABLE'; E[cname_detail]='Explicit IP target'
    else dns_check "$host"; fi
}
ntp_prepare_request() {
    local seconds fraction i value escaped
    seconds=$(date +%s) || return 1
    [[ $seconds =~ ^[0-9]+$ ]] || return 1
    seconds=$(((seconds+2208988800)&0xffffffff))
    fraction=$(((RANDOM<<17) ^ (RANDOM<<2) ^ (RANDOM&3)))
    NTP_PACKET='\033' # Version 3, client mode; matches the Agent default.
    for ((i=1;i<40;i++)); do NTP_PACKET+='\000'; done
    NTP_NONCE=()
    for value in "$seconds" "$fraction"; do
        for ((i=24;i>=0;i-=8)); do
            NTP_NONCE+=("$(((value>>i)&255))")
            printf -v escaped '\\%03o' "$(((value>>i)&255))"
            NTP_PACKET+=$escaped
        done
    done
}
ntp_probe() {
    # Connected UDP socket constrains the response peer. Read one datagram only;
    # the outer deadline covers opening, sending, receiving and byte conversion.
    LC_ALL=C timeout -k 1 "$NTP_TIMEOUT" bash -c '
        set -o pipefail
        exec 3<>"/dev/udp/$1/$2" || exit 10
        printf "%b" "$3" >&3 || exit 11
        dd bs=512 count=1 status=none <&3 | od -An -v -tu1
    ' bash "$1" "$port" "$NTP_PACKET" 2>&1
}
ntp_validate_response() {
    local token i mode version leap stratum nonzero=0 code=''
    local -a bytes=() tokens=()
    NTP_REPLY_STATUS=FAIL; NTP_REPLY_DETAIL='Malformed or truncated NTP response'
    # Validate before any arithmetic/index use; socket content is untrusted.
    read -r -a tokens <<< "${1//$'\n'/ }"
    for token in "${tokens[@]}"; do
        [[ $token =~ ^[0-9]{1,3}$ ]] || return 0
        ((10#$token<=255)) || return 0
        bytes+=("$((10#$token))")
    done
    ((${#bytes[@]}>=48 && ${#bytes[@]}<=512)) || return 0
    mode=$((bytes[0]&7)); version=$(((bytes[0]>>3)&7)); leap=$((bytes[0]>>6)); stratum=${bytes[1]}
    if ((mode!=4 || (version!=3 && version!=4))); then NTP_REPLY_DETAIL='Unexpected NTP mode or version'; return 0; fi
    for ((i=0;i<8;i++)); do
        if ((bytes[i+24]!=NTP_NONCE[i])); then NTP_REPLY_DETAIL='NTP originate timestamp does not match request'; return 0; fi
    done
    E[ntp_version]=$version; E[ntp_leap]=$leap; E[ntp_stratum]=$stratum
    if ((stratum==0)); then
        for ((i=12;i<16;i++)); do
            if ((bytes[i]>=32 && bytes[i]<=126)); then printf -v token '\\%03o' "${bytes[i]}"; printf -v token '%b' "$token"; code+=$token
            else code+='?'; fi
        done
        E[ntp_kiss_code]=$code
        NTP_REPLY_STATUS=WARN; NTP_REPLY_DETAIL="NTP server replied with Kiss-o'-Death ($code); no usable time response"
        return 0
    fi
    if ((stratum>16)); then NTP_REPLY_DETAIL='Invalid NTP stratum'; return 0; fi
    if ((stratum==16 || leap==3)); then
        NTP_REPLY_STATUS=WARN; NTP_REPLY_DETAIL='NTP server replied but reports an unsynchronized clock'; return 0
    fi
    for ((i=40;i<48;i++)); do ((nonzero |= bytes[i])); done
    if ((nonzero==0)); then NTP_REPLY_DETAIL='NTP transmit timestamp is zero'; return 0; fi
    NTP_REPLY_STATUS=PASS; NTP_REPLY_DETAIL="Valid matched NTPv$version server reply; stratum $stratum; direct UDP/$port"
}
ntp_check() {
    local ip output rc count=0 failed=0 unreachable=0 dep result detail
    for dep in timeout dd od; do
        if ! have "$dep"; then E[ntp_detail]="$dep unavailable; no NTP probe issued"; return 0; fi
    done
    if [[ -z ${E[ips]} ]]; then
        E[ntp_detail]='No resolved NTP address; no UDP request issued'
        [[ ${E[dns]} != FAIL ]] || E[ntp]=FAIL
        return 0
    fi
    add_note 'NTP checks unauthenticated protocol reachability, not host clock offset or synchronization; HTTP proxies do not apply'
    while IFS= read -r ip; do
        is_ip "$ip" || continue
        ((count+=1)); ((count<=NTP_MAX_IP_PROBES)) || break
        if ! ntp_prepare_request; then E[ntp_detail]='Unable to construct NTP request; no probe issued'; return 0; fi
        E[ntp_version]=''; E[ntp_stratum]=''; E[ntp_leap]=''; E[ntp_kiss_code]=''
        output=$(ntp_probe "$ip"); rc=$?
        result=FAIL; detail='UDP transport failed; filtering is not established'
        case $rc in
            0) ntp_validate_response "$output"; result=$NTP_REPLY_STATUS; detail=$NTP_REPLY_DETAIL;;
            124|137) detail="No NTP response within ${NTP_TIMEOUT}s; filtering is not established";;
            *) if [[ $ip == *:* && $output == *'Network is unreachable'* ]]; then
                   detail='IPv6 network unreachable'; ((unreachable+=1))
               elif ((rc==10)); then detail='UDP socket could not open; route or Bash UDP support unavailable'; fi;;
        esac
        E[ntp_attempts]+="$ip $result - $detail"$'\n'
        E[ntp]=$result; E[ntp_detail]=$detail
        if [[ $result == PASS ]]; then
            E[ntp_ip]=$ip
            if ((failed>unreachable)); then
                E[ntp]=WARN; E[ntp_detail]='Reply received after an earlier address failed.'
            fi
            break
        fi
        # KoD/unsynchronized servers replied: do not retry a rate-limited server.
        if [[ $result == WARN ]]; then E[ntp_ip]=$ip; break; fi
        ((failed+=1))
    done <<< "${E[ips]}"
    if ((count==0)); then E[ntp]=SKIPPED; E[ntp_detail]='No usable resolved address'; fi
    add_note "NTP probes at most $NTP_MAX_IP_PROBES resolved addresses and stops on a matched server response; remaining addresses untested"
}
# END GENERATED MODULE: lib/ntp.sh
# BEGIN GENERATED MODULE: lib/tls.sh
#!/usr/bin/env bash
# E and port are supplied by the caller.
# shellcheck disable=SC2154
tls_probe() (
    unset SSLKEYLOGFILE
    local target=$2
    [[ $target != *:* ]] || target="[$target]"
    timeout -k 1 "$TLS_TIMEOUT" openssl s_client -connect "$target:$port" \
        -servername "$1" -verify_hostname "$1" -verify_return_error -showcerts \
        -no_ign_eof </dev/null 2>&1
)
tls_check() {
    local host=$1 target output rc cert meta attempt candidate verification_error
    if ! have openssl || ! have timeout; then
        E[tls_detail]='Detailed TLS inspection SKIPPED: openssl or timeout unavailable; see curl_tls for fallback'; return
    fi
    [[ -n ${E[tcp_ip]} ]] || return
    if ! openssl s_client -help 2>&1 | grep -q -- '-verify_hostname'; then
        E[tls_detail]='OpenSSL lacks hostname verification; see curl_tls'; return
    fi
    target=${E[tcp_ip]}
    for ((attempt=1; attempt<=TLS_MAX_ATTEMPTS; attempt++)); do
        output=$(tls_probe "$host" "$target"); rc=$?
        E[tls_ip]=$target; E[tls_exit]=$rc
        E[verification]=$(printf '%s\n' "$output" | awk '/Verify return code:|Verification error:/ {print}')
        verification_error=0
        if [[ $output == *'verify error:'* || $output == *'Verification error:'* || $output == *'certificate verify failed'* ]] ||
            printf '%s\n' "${E[verification]}" | grep -Eq 'Verify return code: [1-9]'; then verification_error=1; fi
        E[tls]=FAIL; E[tls_detail]="Direct SNI/chain/hostname verification failed (exit $rc)"
        if ((rc==0 && !verification_error)) && [[ $output == *'Verify return code: 0 (ok)'* ]]; then
            E[tls]=PASS; E[tls_detail]='Direct SNI, hostname and certificate chain verified'
        elif ((rc==124 || rc==137)); then
            E[tls_detail]='OpenSSL probe timed out; completed verified handshake not established'
            # Verification alone is insufficient: require a negotiated TLS cipher too.
            # A post-handshake process timeout is not proof of a handshake failure.
            if ((!verification_error)) && [[ $output == *'Verify return code: 0 (ok)'* ]] &&
                printf '%s\n' "$output" | grep -Eq '^(New|Reused), TLSv[0-9.]+, Cipher is (TLS_|ECDHE-|DHE-|AES|CHACHA)[A-Za-z0-9_-]+'; then
                E[tls]=WARN; E[tls_detail]='Verified TLS session negotiated; OpenSSL process exceeded deadline afterward'
            fi
        fi
        if ((verification_error)); then E[tls_detail]='OpenSSL reported certificate verification failure; see verification result'; fi
        E[tls_attempts]+="attempt $attempt: IP=$target, ${E[tls]}, exit=$rc; ${E[tls_detail]}"$'\n'
        [[ ${E[tls]} == FAIL && $verification_error == 0 && ( $rc == 124 || $rc == 137 ) ]] || break
        # One bounded retry; prefer another address already proven reachable by TCP.
        while IFS= read -r candidate; do
            [[ $candidate == *' PASS' ]] || continue
            candidate=${candidate% PASS}
            if [[ $candidate != "$target" ]]; then target=$candidate; break; fi
        done <<< "${E[tcp_attempts]}"
    done
    if ((attempt>1)) && [[ ${E[tls]} == PASS || ${E[tls]} == WARN ]]; then
        E[tls]=WARN; add_note 'TLS recovered on bounded retry; initial timeout retained in TLS attempts'
    fi
    cert=$(printf '%s\n' "$output" | awk '/-----BEGIN CERTIFICATE-----/{p=1} p{print} /-----END CERTIFICATE-----/{exit}')
    if [[ -n $cert ]]; then
        meta=$(printf '%s\n' "$cert" | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
        E[subject]=$(sed -n 's/^subject=//p' <<< "$meta" | clean)
        E[issuer]=$(sed -n 's/^issuer=//p' <<< "$meta" | clean)
        E[expiry]=$(sed -n 's/^notAfter=//p' <<< "$meta" | clean)
    fi
}
# END GENERATED MODULE: lib/tls.sh
# BEGIN GENERATED MODULE: lib/http.sh
#!/usr/bin/env bash
# E is a caller-owned associative array; its keys and indexes are not arithmetic variables.
# shellcheck disable=SC2154,SC2004
# Never use --fail, --insecure, credentials, verbose traces, or a user's curlrc.
# Body/headers stay in bounded memory and are discarded after classification.
curl_probe() (
    # Prevent an inherited debug setting from writing TLS session secrets.
    unset SSLKEYLOGFILE
    local metadata rc reader reader_rc
    local -a redirect_options=()
    [[ ${2:-origin} != follow ]] || redirect_options=(--location --max-redirs 3)
    # Keep the bounded response sample on a separate pipe from curl metadata.
    # Older curl releases do not enforce --max-filesize for unknown-size bodies.
    # Descriptor 4 is a pipe, not a file; raw responses never touch the filesystem.
    {
        exec 4> >(
            # Count sampled bytes independently of curl's write-error counters.
            # tee copies into the capture pipe, not a filesystem file.
            bytes=$(head -c 65536 | tee /dev/fd/3 | wc -c) || exit 1
            printf '\nDD_PREFLIGHT_SAMPLE_BYTES=%s\n' "$bytes" >&3
        )
        reader=$!
        metadata=$(curl --disable --silent --show-error --include "${redirect_options[@]}" \
            --proto '=https' --proto-redir '=https' --connect-timeout "$TCP_TIMEOUT" \
            --max-time "$HTTP_TIMEOUT" --max-filesize 65536 --range 0-32767 \
            --output /dev/fd/4 --user-agent "dd-network-preflight/$TOOL_VERSION" \
            --write-out $'\nDD_PREFLIGHT_META\n%{http_code}\n%{url_effective}\n%{remote_ip}\n%{num_redirects}\n%{ssl_verify_result}\n%{time_namelookup}\n%{time_connect}\n%{time_appconnect}\n%{time_starttransfer}\n%{time_total}\n' "$1" 2>/dev/null)
        rc=$?
        exec 4>&-
        # Finish the sample before emitting metadata, including on small bodies.
        wait "$reader"; reader_rc=$?
        printf '\n%s\n' "$metadata"
        ((reader_rc==0)) || printf '\nDD_PREFLIGHT_CAPTURE_ERROR\n'
        return "$rc"
    } 3>&1
)
safe_url() {
    local url=${1%%\?*} scheme authority
    url=${url%%\#*}; scheme=${url%%://*}; authority=${url#*://}; authority=${authority%%/*}; authority=${authority##*@}
    [[ $scheme == https && $authority =~ ^[a-zA-Z0-9.:-]+$ ]] || { printf '[URL withheld]'; return; }
    printf '%s://%s/[path omitted]' "$scheme" "$authority"
}
redirect_host_from_url() {
    local authority=${1#https://}
    [[ $1 == https://* ]] || return 0
    authority=${authority%%/*}
    authority=${authority%:443}
    authority=${authority%.}
    printf '%s' "${authority,,}"
}
expected_redirect_host() {
    case $1 in
        registry.datadoghq.com) printf 'docs.datadoghq.com';;
        gcr.io|eu.gcr.io|asia.gcr.io|us-docker.pkg.dev) printf 'accounts.google.com';;
        docker.io) printf 'www.docker.com';;
    esac
}
http_attempt() {
    local host=$1 output meta rc='' status final_ip redirect verify body low vendor generic sampled=0 sample_bytes='' field i
    for field in http_status final_url remote_ip server via curl_exit time_namelookup time_connect time_appconnect time_starttransfer time_total; do E[$field]=''; done
    E[curl_tls]=SKIPPED; E[redirect_count]=0
    output=$({ curl_probe "https://$host:$port$path" "${2:-origin}"; printf 'DD_PREFLIGHT_EXIT=%s\n' "$?"; } | tr -d '\000')
    if [[ $output == *DD_PREFLIGHT_META* ]]; then
        meta=${output##*DD_PREFLIGHT_META$'\n'}
        local -a fields
        mapfile -t fields <<< "$meta"
        status=${fields[0]-}; E[final_url]=$(safe_url "${fields[1]-}")
        final_ip=${fields[2]-}; is_ip "$final_ip" && E[remote_ip]=$final_ip
        redirect=${fields[3]-0}; [[ $redirect =~ ^[0-9]+$ ]] && E[redirect_count]=$redirect
        verify=${fields[4]-}
        i=5
        for field in time_namelookup time_connect time_appconnect time_starttransfer time_total; do
            [[ ! ${fields[i]-} =~ ^[0-9]+\.[0-9]+$ ]] || E[$field]=${fields[i]}
            ((i+=1))
        done
    else status=''; verify=''; fi
    [[ $output != *DD_PREFLIGHT_EXIT=* ]] || rc=${output##*DD_PREFLIGHT_EXIT=}
    if [[ ! $rc =~ ^[0-9]+$ ]]; then
        E[http]=SKIPPED; E[http_detail]='HTTP diagnostic capture incomplete; curl exit code unavailable'
        add_note 'Checker diagnostic incomplete; no network blocker inferred from missing metadata'; return
    fi
    E[curl_exit]=$rc
    # A closed sample pipe is intentional only when our independent byte count proves
    # the sample limit was reached. Other write errors remain failures.
    body=${output%DD_PREFLIGHT_META*}
    if [[ $body == *DD_PREFLIGHT_SAMPLE_BYTES=* ]]; then
        sample_bytes=${body##*DD_PREFLIGHT_SAMPLE_BYTES=}; sample_bytes=${sample_bytes%%$'\n'*}
        sample_bytes=${sample_bytes//[[:space:]]/}
        [[ $sample_bytes != 65536 ]] || sampled=1
    fi
    [[ ! $status =~ ^[1-5][0-9][0-9]$ ]] || E[http_status]=$status
    E[http]=FAIL; E[http_detail]="No complete HTTPS response (curl exit $rc)"
    case $rc in
        5) E[http_detail]='Proxy DNS resolution failed';;
        6) E[http_detail]='Destination DNS resolution failed';;
        7) E[http_detail]='TCP connection failed on environment route';;
        28)
            E[http_detail]='Connection or request timeout; phase unavailable'
            if nonzero_time "${E[time_starttransfer]}"; then E[http_detail]='Timeout after response started'
            elif nonzero_time "${E[time_appconnect]}"; then E[http_detail]='Timeout waiting for HTTP response after TLS completed'
            elif nonzero_time "${E[time_connect]}"; then E[http_detail]='Timeout after TCP connected, before TLS completed (may include proxy negotiation)'
            elif [[ -n ${E[time_connect]} ]]; then E[http_detail]='Timeout before TCP connection completed (DNS/proxy/connect phase)'; fi;;
        35|51|58|60|77|83|90|91) E[http_detail]='TLS handshake or certificate verification failed'; E[curl_tls]=FAIL;;
        47) E[http_detail]='Redirect limit exceeded';;
    esac
    # A verified completed TLS connection is useful evidence even if HTTP stalls.
    # Verification code zero on its own also occurs before a handshake: require
    # curl's completed application-connect timestamp and no explicit TLS error.
    if [[ ${E[curl_tls]} != FAIL && $verify == 0 ]] && nonzero_time "${E[time_appconnect]}"; then E[curl_tls]=PASS; fi
    if [[ $output == *DD_PREFLIGHT_CAPTURE_ERROR* ]] || { ((rc==0)) && [[ -z ${E[http_status]} || -z $verify ]]; }; then
        E[http]=SKIPPED; E[http_detail]='HTTP diagnostic capture incomplete; response metadata unavailable'
        add_note 'Checker diagnostic incomplete; no network blocker inferred from missing metadata'
    fi
    if [[ $output != *DD_PREFLIGHT_CAPTURE_ERROR* && -n ${E[http_status]} && $verify == 0 ]] && ((rc==0 || rc==63 || (rc==23 && sampled))); then
        E[curl_tls]=PASS; E[http]=PASS
        E[http_detail]='Endpoint reachable; application-level response received; environment route'
        if ((rc==63 || sampled)); then
            E[http_detail]='Verified HTTPS response received; diagnostic body sample intentionally capped'
            add_note 'Response body exceeded checker sample limit; HTTP reachability was already verified'
        fi
        if ((E[redirect_count]>0)) && [[ ${2:-origin} != follow ]]; then
            E[http]=WARN; add_note 'Redirect observed; confirm final destination with the network team'
        fi
        if ((10#${E[http_status]}>=500)) || [[ ${E[http_status]} == 407 ]]; then E[http]=WARN; add_note 'Service/proxy error response requires review'; fi
    fi
    # Only server/via headers; no cookies, authorization, locations, or raw body saved.
    body=${output%%DD_PREFLIGHT_META*}
    E[server]=$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{h=1;v=""} h && tolower($0) ~ /^server:/{v=substr($0,8)} /^\r?$/{h=0} END{print v}' <<< "$body" | clean)
    E[via]=$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{h=1;v=""} h && tolower($0) ~ /^via:/{v=substr($0,5)} /^\r?$/{h=0} END{print v}' <<< "$body" | clean)
    low=${body,,}; vendor=''; generic=0
    case $low in *fortigate*|*fortinet*) vendor=Fortinet;; *zscaler*) vendor=Zscaler;; *'palo alto'*) vendor='Palo Alto';; esac
    case $low in *blocked*|*'web filter'*|*'access denied'*) generic=1;; esac
    if [[ -n $vendor ]] && ((generic)); then
        [[ ${E[http]} == FAIL ]] || E[http]=WARN
        add_note "POSSIBLE SECURITY FILTERING: $vendor and denial/filter signature detected; not definitive proof"
    elif ((generic)) && [[ ${E[http]} == PASS || ${E[http]} == WARN ]]; then
        # S3/CloudFront and application endpoints also return Access Denied.
        # Generic wording alone cannot identify a firewall/proxy block page.
        # Keep transport, service/proxy errors, and retry warnings independent.
        add_note 'Generic denial wording observed; insufficient evidence of network filtering'
    fi
    if [[ ${E[tls]} == SKIPPED ]]; then add_note "Detailed TLS inspection SKIPPED; curl TLS fallback ${E[curl_tls]}"; fi
}

nonzero_time() { [[ $1 =~ ^[0-9]+\.[0-9]+$ && $1 == *[1-9]* ]]; }

http_check() {
    local host=$1 attempt key summary origin_http final_authority expected_host
    E[http_attempts]=''
    for ((attempt=1; attempt<=HTTP_MAX_ATTEMPTS; attempt++)); do
        http_attempt "$host" origin
        summary="origin attempt $attempt: ${E[http]}, curl=${E[curl_exit]:-unknown}, HTTP=${E[http_status]:-none}, IP=${E[remote_ip]:-unknown}, TCP=${E[time_connect]:-unknown}s, TLS=${E[time_appconnect]:-unknown}s, first_byte=${E[time_starttransfer]:-unknown}s, total=${E[time_total]:-unknown}s; ${E[http_detail]}"
        E[http_attempts]+="$summary"$'\n'
        [[ ${E[http]} == FAIL ]] || break
        # No automatic retries for certificate failures or application responses.
        case ${E[curl_exit]} in 7|28|52|55|56) ;; *) break;; esac
    done
    if ((attempt>1)) && [[ ${E[http]} == PASS || ${E[http]} == WARN ]]; then
        E[http]=WARN
        add_note 'Origin HTTPS recovered on retry; initial failure retained in HTTP attempts; reachability may be intermittent'
    fi
    if [[ ${E[curl_tls]} == PASS && ${E[http_status]} =~ ^3[0-9][0-9]$ && ( ${E[http]} == PASS || ${E[http]} == WARN ) ]]; then
        # Keep original endpoint evidence separate from the redirect diagnostic.
        # Re-request the original URL with curl-managed HTTPS-only redirect handling;
        # never parse/replay an untrusted Location header ourselves.
        origin_http=${E[http]}
        E[http]=WARN
        add_note 'Origin returned a redirect; follow-up is a separate diagnostic, not an origin reachability failure'
        local -A origin=()
        for key in "${!E[@]}"; do origin[$key]=${E[$key]}; done
        http_attempt "$host" follow
        for key in http http_detail http_status final_url remote_ip curl_exit curl_tls redirect_count time_total; do origin[redirect_$key]=${E[$key]}; done
        origin[redirect_host]=$(redirect_host_from_url "${E[final_url]}")
        origin[notes]=${E[notes]}
        if [[ ${E[http]} == FAIL || ${E[http]} == SKIPPED ]]; then
            origin[notes]+="; Redirect follow-up ${E[http]}: ${E[http_detail]}; review redirect destination separately"
        elif [[ $origin_http == PASS && ${E[http]} == PASS && ${E[curl_tls]} == PASS && ${E[redirect_count]} == 1 ]]; then
            final_authority=${E[final_url]#https://}
            final_authority=${final_authority%%/*}
            final_authority=${final_authority%:443}
            if [[ $final_authority == "$host" ]]; then
                origin[http]=PASS
                origin[notes]+='; Single same-host HTTPS redirect verified; no additional destination identified'
            fi
        fi
        expected_host=$(expected_redirect_host "$host")
        if [[ -n $expected_host && ${origin[redirect_host]} == "$expected_host" ]]; then
            if [[ $origin_http == PASS && ${E[http]} == PASS && ${E[curl_tls]} == PASS ]]; then
                origin[http]=PASS
                origin[notes]+="; Expected registry redirect to $expected_host confirmed"
            fi
        elif [[ -n $expected_host && ${E[http]} == PASS ]]; then
            origin[notes]+='; Unexpected redirect target; possible proxy/captive portal block page.'
        fi
        E=()
        for key in "${!origin[@]}"; do E[$key]=${origin[$key]}; done
    fi
}
# END GENERATED MODULE: lib/http.sh
# BEGIN GENERATED MODULE: lib/reporting.sh
#!/usr/bin/env bash
# E and manifest fields are supplied by the caller; associative indexes are strings.
# shellcheck disable=SC2154,SC2004
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
    local status=$1 label=${2//;/.} color='' symbol
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
    local value=${1//;/.} limit=$2 marker='...'
    terminal_utf8 && marker='…'
    if ((${#value}<=limit)); then printf '%s' "$value"
    elif ((limit>${#marker})); then printf '%s%s' "${value:0:limit-${#marker}}" "$marker"
    else printf '%s' "${value:0:limit}"; fi
}
terminal_middle_host() {
    local value=${1//;/.} limit=$2 marker='...' room suffix prefix
    terminal_utf8 && marker='…'
    if ((${#value}<=limit)); then printf '%s' "$value"; return; fi
    room=$((limit-${#marker}))
    if ((room<2)); then printf '%s' "$marker"; return; fi
    suffix=$((room*2/3))
    prefix=$((room-suffix))
    printf '%s%s%s' "${value:0:prefix}" "$marker" "${value: -suffix}"
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
    local rest=${1//;/.} prefix=$2 continuation=$3 width limit chunk
    width=$(terminal_width)
    ((width>=30)) || width=30
    while ((${#prefix}+${#rest} > width)); do
        limit=$((width-${#prefix}))
        chunk=${rest:0:limit}
        if [[ $chunk == *' '* ]]; then
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
    local content=${1//$'\n'/ } marker='->' line
    local -a lines=()
    terminal_utf8 && marker='↳'
    while IFS= read -r line; do lines+=("$line"); done < <(terminal_wrap "$content" "       $marker " '         ')
    if ((${#lines[@]}>2)); then
        lines=()
        while IFS= read -r line; do lines+=("$line"); done < <(terminal_wrap 'See TXT report for diagnostic details.' "       $marker " '         ')
    fi
    for line in "${lines[@]:0:2}"; do
        if terminal_color_enabled; then printf '\033[2m%s\033[0m\n' "$line"
        else printf '%s\n' "$line"; fi
    done
}
terminal_full_host_note() {
    local marker='->' line prefix continuation='         ' width
    terminal_utf8 && marker='↳'
    prefix="       $marker "
    width=$(terminal_width)
    if ((${#prefix}+${#1}>width && ${#1}+${#marker}+2<=width)); then
        prefix=" $marker "
    elif ((${#prefix}+${#1}>width && ${#1}+${#marker}<=width)); then
        prefix=$marker
    fi
    while IFS= read -r line; do
        if terminal_color_enabled; then printf '\033[2m%s\033[0m\n' "$line"
        else printf '%s\n' "$line"; fi
    done < <(terminal_wrap "$1" "$prefix" "$continuation")
}
terminal_progress() {
    [[ ${TERMINAL_TTY-0} == 1 ]] && terminal_color_enabled || return 0
    terminal_progress_clear
    local width frame
    local -a frames=()
    width=$(terminal_width)
    for frame in '|' '/' '-' $'\\'; do
        frames+=("$(terminal_truncate "$frame Checking $TERMINAL_PROGRESS_DONE/$TERMINAL_PROGRESS_TOTAL ${TERMINAL_PROGRESS_HOST-}" "$width")")
    done
    TERMINAL_PROGRESS_ACTIVE=1
    printf '\033[?25l'
    printf '\r\033[2K\033[2m%s\033[0m' "${frames[0]}"
    have sleep || return 0
    (
        trap - EXIT INT TERM HUP
        tick=1
        while sleep 0.12; do
            printf '\r\033[2K\033[2m%s\033[0m' "${frames[tick%4]}"
            ((tick+=1))
        done
    ) &
    TERMINAL_PROGRESS_PID=$!
}
terminal_progress_clear() {
    if [[ -n ${TERMINAL_PROGRESS_PID-} ]]; then
        kill "$TERMINAL_PROGRESS_PID" 2>/dev/null || :
        wait "$TERMINAL_PROGRESS_PID" 2>/dev/null || :
        unset TERMINAL_PROGRESS_PID
    fi
    [[ ${TERMINAL_PROGRESS_ACTIVE-0} == 1 ]] || return 0
    TERMINAL_PROGRESS_ACTIVE=0
    [[ ${TERMINAL_TTY-0} == 1 ]] && terminal_color_enabled || return 0
    printf '\r\033[2K\033[?25h'
}
terminal_interrupt() {
    terminal_progress_clear
    if [[ ${TERMINAL_TTY-0} == 1 ]] && terminal_color_enabled; then printf '\033[0m\033[?25h'; fi
    error 'Scan interrupted. Incomplete files retained in reports, no final readiness report'
    exit 3
}
terminal_destination_count() {
    local line total=0
    for line in "${RECORDS[@]}"; do
        parse_record "$line"
        if [[ $os == windows || $os == desktop || $test_type == excluded || $test_type == wildcard || ( $sites != all && ,$sites, != *",$SITE,"* ) ]]; then
            continue
        fi
        ((total+=1))
    done
    printf '%s' "$total"
}
terminal_section() {
    local title=${1//_/ } divider padding fill width
    if [[ $title == SUMMARY ]] && ! terminal_narrow; then
        printf '\n%s\n' '+------------------------------------------------------------------------------+'
        printf '| %-76s |\n' SUMMARY
        printf '%s\n' '+------------------------------------------------------------------------------+'
        return
    fi
    [[ $title != SUMMARY ]] || { printf '\n[ SUMMARY ]\n'; return; }
    title=${title^^}
    [[ $1 != rum ]] || title+=' (VM-side only)'
    width=$(terminal_width)
    divider='-'; terminal_utf8 && divider='─'
    fill=$((width-3-${#title}))
    if ((fill<3)); then
        printf '\n %s\n' "$title"
        return
    fi
    printf -v padding '%*s' "$fill" ''
    padding=${padding// /$divider}
    if terminal_color_enabled; then
        printf '\n \033[1m%s\033[0m \033[2m%s\033[0m\n' "$title" "$padding"
    else
        printf '\n %s %s\n' "$title" "$padding"
    fi
}
terminal_category_start() {
    [[ ${LAST_TERMINAL_CATEGORY-} != "$category" ]] || return 0
    terminal_progress_clear
    [[ -z ${LAST_TERMINAL_CATEGORY-} ]] || terminal_group_notes "$LAST_TERMINAL_CATEGORY"
    terminal_section "$category"
    LAST_TERMINAL_CATEGORY=$category
}
terminal_intro() {
    local available=$1 unavailable=$2
    local proxy='none'
    ((PROXY_PRESENT)) && proxy='configured (values withheld)'
    printf '\n'
    terminal_wrap "Proxy: $proxy" '  ' '  '
    terminal_wrap "Tools: ${available:-none}" '  ' '         '
    [[ -z $unavailable ]] || terminal_wrap "Unavailable tools: $unavailable" '  ' '  '
    printf '  Scope: all destinations\n'
    terminal_wrap "Agent: ${AGENT_VERSION_DISPLAY:-not determined} (${AGENT_VERSION_SOURCE:-none})" '  ' '         '
    [[ -z ${AGENT_VERSION_DETAIL-} ]] || terminal_wrap "$AGENT_VERSION_DETAIL" '  ' '  '
    if [[ -n ${NTP_TARGET_SOURCE-} ]]; then
        terminal_wrap "NTP: ${NTP_TARGET_SOURCE//-/ } (UDP/123)" '  ' '       '
    fi
}
terminal_stage() {
    case $1 in PASS) printf ok;; WARN) printf warn;; FAIL) printf fail;; *) printf -- '--';; esac
}
terminal_row() {
    local state=$1 host=$2 dns=$3 tcp=$4 tls=$5 http=$6 width host_width shown color='' stages status_field
    width=$(terminal_width)
    if ((width<64)); then
        shown=$(terminal_middle_host "$host" "$((width-9))")
        if terminal_color_enabled; then
            case $state in PASS) color=$'\033[32m';; WARN) color=$'\033[33m';; REVIEW) color=$'\033[36m';; FAIL) color=$'\033[31m';; esac
        fi
        if [[ -n $color ]]; then printf '  %s%-6s\033[0m %s\n' "$color" "$state" "$shown"
        else printf '  %-6s %s\n' "$state" "$shown"; fi
        terminal_wrap "DNS $dns  TCP $tcp  TLS $tls  HTTP $http" '        ' '        '
        [[ $shown == "$host" ]] || terminal_full_host_note "$host"
        return
    fi
    host_width=$((width-33))
    shown=$(terminal_middle_host "$host" "$host_width")
    printf -v status_field '%-6s' "$state"
    printf -v stages '%4s %4s %4s %s' "$dns" "$tcp" "$tls" "$http"
    if terminal_color_enabled; then
        case $state in
            PASS) color=$'\033[32m';;
            WARN) color=$'\033[33m';;
            REVIEW) color=$'\033[36m';;
            FAIL) color=$'\033[31m';;
        esac
        printf '  %s%s\033[0m %-*s \033[2m%s\033[0m\n' "$color" "$status_field" "$host_width" "$shown" "$stages"
    else
        printf '  %s %-*s %s\n' "$status_field" "$host_width" "$shown" "$stages"
    fi
    [[ $shown == "$host" ]] || terminal_full_host_note "$host"
}
terminal_table_header() {
    local width host_width
    width=$(terminal_width)
    if ((width<64)); then
        printf '\n  STATUS DESTINATION\n        DNS  TCP  TLS  HTTP\n'
    else
        host_width=$((width-33))
        printf '\n  %-6s %-*s %4s %4s %4s %s\n' STATUS "$host_width" DESTINATION DNS TCP TLS HTTP
    fi
}
terminal_endpoint() {
    local state hint field detail attempt http_display dns_display tcp_display tls_display
    [[ ${E[classification]} != 'NOT APPLICABLE' ]] || return 0
    terminal_category_start
    if [[ ${E[classification]} == 'NOT DIRECTLY TESTABLE' ]]; then
        if [[ ${E[test_type]} == version ]]; then hint='Agent version not determined. Not tested.'
        else hint='Manual target; not tested.'; fi
        terminal_row REVIEW "${E[hostname]}" '--' '--' '--' '--'
        terminal_note "$hint"
        return 0
    fi
    state=${E[impact]}
    if [[ ${E[test_type]-} == ntp ]]; then
        terminal_row "$state" "${E[hostname]}" "$(terminal_stage "${E[dns]}")" '--' '--' '--'
        [[ $state != PASS ]] || return 0
        terminal_note "NTP UDP/${E[port]}: ${E[ntp]} - ${E[ntp_detail]}"
        [[ $NTP_TARGET_SOURCE != documented-public-fallback || $state == PASS ]] || terminal_note 'Public fallback only; use --ntp-host for private/cloud NTP.'
        return 0
    fi
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
        if [[ ${TERMINAL_NOTE_KEY[$TERMINAL_CURRENT_INDEX]-} == redirect_allowlist ]]; then return 0; fi
    fi
    if [[ ${E[notes]} == *'POSSIBLE SECURITY FILTERING'* ]]; then
        terminal_note 'Possible security filtering. See TXT report.'
        return 0
    fi
    if [[ ${E[notes]} == *'Origin HTTPS recovered on retry'* ]]; then
        terminal_note 'HTTP: origin reached after a failed attempt. See TXT report.'
        return 0
    fi
    if [[ ${E[http]} != PASS && ${E[redirect_http_detail]} != 'No reachable redirect response' ]]; then
        if [[ ${E[notes]} == *'Unexpected redirect target; possible proxy/captive portal block page.'* ]]; then
            terminal_note 'Unexpected redirect target. Possible proxy/captive portal block page.'
            return 0
        fi
        if [[ ${E[redirect_http]} == FAIL ]]; then
            terminal_note 'Redirect follow-up failed. See TXT report.'
        else
            terminal_note 'Redirect follow-up needs review. See TXT report.'
        fi
        return 0
    fi
    for field in dns cname tcp tls http; do
        [[ ${E[$field]} == PASS ]] && continue
        [[ $field != cname || ${E[cname]} != SKIPPED ]] || continue
        if [[ $field == tcp && ( ${E[tcp]} == WARN || ${E[tcp]} == FAIL ) ]]; then
            while IFS= read -r attempt; do
                [[ $attempt == *' FAIL - '* ]] || continue
                [[ ${E[tcp]} != WARN || $attempt != *'network unreachable'* ]] || continue
                terminal_note "TCP: $attempt."
                return 0
            done <<< "${E[tcp_attempts]}"
        fi
        detail=${E[${field}_detail]}
        if ((${#detail}>64)); then
            terminal_note "${field^^} check needs review; see TXT report."
        else
            terminal_note "${field^^}: ${detail%.}."
        fi
        return 0
    done
    terminal_note 'Review this endpoint in the TXT report.'
}
terminal_capture_endpoint() {
    local index field state key
    [[ ${E[classification]} != 'NOT APPLICABLE' ]] || return 0
    index=${#TERMINAL_ORDER[@]}
    TERMINAL_ORDER+=("$category")
    for field in classification test_type impact hostname dns cname tcp tls http ntp http_status redirect_http_detail redirect_http_status redirect_http redirect_final_url dns_detail cname_detail tcp_detail tls_detail http_detail ntp_detail notes; do
        TERMINAL_SNAP["$index:$field"]=${E[$field]-}
    done
    state=${E[impact]}
    [[ ${E[classification]} != 'NOT DIRECTLY TESTABLE' ]] || state=REVIEW
    key="$category:$state"
    # Associative keys need variable expansion here.
    # shellcheck disable=SC2004
    TERMINAL_COUNTS[$key]=$(( ${TERMINAL_COUNTS[$key]-0}+1 ))
    TERMINAL_NOTE_KEY[index]=''
    if [[ $state == PASS && $category == container_registries && -n ${E[redirect_host]} && ${E[redirect_http]} == PASS ]]; then
        key="$category:expected_redirect"
        TERMINAL_GROUP_COUNTS[$key]=$(( ${TERMINAL_GROUP_COUNTS[$key]-0}+1 ))
        key="$category:${E[redirect_host]}"
        if [[ -z ${TERMINAL_GROUP_HOST_SEEN[$key]-} ]]; then
            TERMINAL_GROUP_HOST_SEEN[$key]=1
            TERMINAL_GROUP_HOSTS[$category]+="${TERMINAL_GROUP_HOSTS[$category]:+, }${E[redirect_host]}"
        fi
    fi
}
terminal_group_notes() {
    local count=${TERMINAL_GROUP_COUNTS["$1:expected_redirect"]-0}
    if ((count)); then
        terminal_note "Allow ${TERMINAL_GROUP_HOSTS[$1]}."
    fi
}
terminal_box_border() {
    local position=$1 width fill left right divider title=''
    width=$(terminal_width)
    divider='-'; left='+'; right='+'
    if terminal_utf8; then
        divider='─'
        if [[ $position == top ]]; then left='╭'; right='╮'; else left='╰'; right='╯'; fi
    fi
    [[ $position != top ]] || title="${divider} SUMMARY "
    printf -v fill '%*s' "$((width-2-${#title}))" ''
    printf '%s%s%s%s\n' "$left" "$title" "${fill// /$divider}" "$right"
}
terminal_box_line() {
    local content=${1//;/.} state=${2-} width padding color=''
    width=$(terminal_width)
    printf -v padding '%*s' "$((width-4-${#content}))" ''
    if terminal_color_enabled; then
        case $state in
            PASS|READY) color=$'\033[32m';;
            WARN|'READY WITH WARNINGS') color=$'\033[33m';;
            REVIEW) color=$'\033[36m';;
            FAIL|BLOCKED) color=$'\033[31m';;
        esac
    fi
    if terminal_utf8; then printf '│  '; else printf '|  '; fi
    if [[ -n $color ]]; then printf '%s%s\033[0m' "$color" "$content"
    else printf '%s' "$content"; fi
    if terminal_utf8; then printf '%s│\n' "$padding"; else printf '%s|\n' "$padding"; fi
}
terminal_box_wrap() {
    local rest=${1//;/.} state=${2-} continuation=${3-} width limit chunk
    width=$(terminal_width)
    limit=$((width-4))
    while ((${#rest}>limit)); do
        chunk=${rest:0:limit}
        [[ $chunk != *' '* ]] || chunk=${chunk% *}
        [[ -n $chunk ]] || chunk=${rest:0:limit}
        terminal_box_line "$chunk" "$state"
        rest=${rest:${#chunk}}
        rest="$continuation${rest# }"
    done
    terminal_box_line "$rest" "$state"
}
terminal_summary_reason() {
    local category=$1 failed=$2 warned=$3 index field
    if ((failed)); then
        if ((warned)); then printf '%s blocked, %s warning(s); see TXT report' "$failed" "$warned"
        else printf '%s blocked endpoint(s); see TXT report' "$failed"; fi
        return
    fi
    for ((index=0;index<${#TERMINAL_ORDER[@]};index++)); do
        [[ ${TERMINAL_ORDER[index]} == "$category" && ${TERMINAL_SNAP["$index:impact"]-} == WARN ]] || continue
        if [[ ${TERMINAL_SNAP["$index:notes"]-} == *'POSSIBLE SECURITY FILTERING'* ]]; then
            printf '%s possible security-filter response(s); see TXT report' "$warned"
            return
        fi
        if [[ ${TERMINAL_SNAP["$index:notes"]-} == *'Unexpected redirect target'* ]]; then
            printf '%s unexpected redirect(s); inspect proxy' "$warned"
            return
        fi
        for field in dns tcp tls http ntp; do
            if [[ ${TERMINAL_SNAP["$index:$field"]-} == WARN ]]; then
                printf '%s %s warning(s); see TXT report' "$warned" "${field^^}"
                return
            fi
        done
    done
    printf '%s endpoint warning(s); see TXT report' "$warned"
}
terminal_summary() {
    local category count review_count=0 attention=0 line passed warned failed reviewed state
    local verdict=$OVERALL width
    width=$(terminal_width)
    [[ $verdict != BLOCKED ]] || verdict='NOT READY'
    review_count=${#UNTESTED[@]}
    printf '\n'
    terminal_box_border top
    terminal_box_wrap "$(terminal_symbol "$OVERALL")  $verdict" "$OVERALL"
    terminal_box_line ''
    if ((width<64)); then
        terminal_box_wrap "$(terminal_symbol PASS) $DIRECT_PASS pass   $(terminal_symbol WARN) $DIRECT_WARN warn"
        terminal_box_wrap "$(terminal_symbol FAIL) $DIRECT_FAIL fail   $(terminal_symbol REVIEW) $review_count review"
    else
        terminal_box_wrap "$(terminal_symbol PASS) $DIRECT_PASS pass    $(terminal_symbol WARN) $DIRECT_WARN warn    $(terminal_symbol FAIL) $DIRECT_FAIL fail    $(terminal_symbol REVIEW) $review_count review"
    fi
    terminal_box_line ''
    terminal_box_line 'By category'
    for category in "${CATEGORY_ORDER[@]}"; do
        passed=${TERMINAL_COUNTS["$category:PASS"]-0}
        warned=${TERMINAL_COUNTS["$category:WARN"]-0}
        failed=${TERMINAL_COUNTS["$category:FAIL"]-0}
        reviewed=${TERMINAL_COUNTS["$category:REVIEW"]-0}
        ((passed+warned+failed+reviewed)) || continue
        terminal_box_wrap "  ${category//_/ }: $passed pass, $warned warn, $failed fail, $reviewed review" '' '    '
    done
    terminal_box_line ''
    terminal_box_line 'Needs attention'
    for category in "${CATEGORY_ORDER[@]}"; do
        failed=${TERMINAL_COUNTS["$category:FAIL"]-0}
        warned=${TERMINAL_COUNTS["$category:WARN"]-0}
        ((failed+warned)) || continue
        attention=1; state=WARN
        ((failed==0)) || state=FAIL
        line="  $(terminal_symbol "$state") ${category//_/ }: $(terminal_summary_reason "$category" "$failed" "$warned")"
        terminal_box_wrap "$line" "$state" '    '
    done
    ((attention)) || terminal_box_line '  None'
    if ((${#BLOCKERS[@]})); then
        terminal_box_line ''
        terminal_box_line 'Blockers'
        for line in "${BLOCKERS[@]}"; do terminal_box_wrap "  - $line" FAIL '    '; done
    fi
    if ((${#UNTESTED[@]})); then
        terminal_box_line ''
        terminal_box_wrap "Manual review: ${#UNTESTED[@]} other requirement(s)" '' '  '
    fi
    for line in "${TERMINAL_OTHER_REQUIREMENTS[@]}"; do
        terminal_box_wrap "  - $line" '' '    '
    done
    if ((${TERMINAL_UNSPECIFIED_COUNT-0})); then
        terminal_box_wrap "  - $TERMINAL_UNSPECIFIED_COUNT destination-unspecified requirement(s)" '' '    '
    fi
    terminal_box_wrap 'RUM: VM-side sanity only; end-user browser connectivity untested' '' '  '
    terminal_box_border bottom
    printf '\n'
    printf '  Reports: %s\n' "$(terminal_path "${REPORT_BASE%/*}")"
    printf '  TXT  %s.txt\n' "$(terminal_path "${REPORT_BASE##*/}")"
    printf '  JSON %s.json\n' "$(terminal_path "${REPORT_BASE##*/}")"
}
terminal_path() {
    local text=$1
    if [[ $text == *';'* ]]; then
        text=${text//\\/\\\\}; text=${text//\'/\\\'}
        printf "\$'%s'" "${text//;/\\073}"
    else printf '%s' "$text"; fi
}
report_init() {
    local safe_host stamp
    # Refuse symlinks and foreign-owned directories for report safety.
    [[ ! -L $ROOT/reports ]] || { error 'reports must not be a symlink'; return 1; }
    umask 077
    mkdir -p -- "$ROOT/reports" || return 1
    if [[ ! -O $ROOT/reports ]]; then error 'Report directory must be owned by the current user'; return 1; fi
    safe_host=${MACHINE//[^a-zA-Z0-9._-]/_}; stamp=$(date -u +%Y%m%d-%H%M%S)
    RUN_DIR=$(mktemp -d "$ROOT/reports/.run-XXXXXX") || return 1
    REPORT_BASE="$ROOT/reports/dd-network-preflight-$safe_host-$stamp-${RUN_DIR##*.run-}"
    TXT_REPORT="$RUN_DIR/report.txt"; JSON_REPORT="$RUN_DIR/report.json"; ENDPOINT_JSON="$RUN_DIR/endpoints.jsonl"
    : > "$TXT_REPORT" && : > "$ENDPOINT_JSON"
}
endpoint_json() {
    local field first=1
    printf '{'
    for field in id category label hostname redirect_host port protocol applicable_os test_type requirement source status impact classification notes; do
        ((first)) || printf ','; first=0
        json_string "$field"; printf ':'; json_string "${E[$field]-}"
    done
    printf ',"dns_results":{"status":'; json_string "${E[dns]}"
    printf ',"detail":'; json_string "${E[dns_detail]}"; printf '}'
    printf ',"cname_result":{"status":'; json_string "${E[cname]}"
    printf ',"detail":'; json_string "${E[cname_detail]}"; printf '}'
    printf ',"cnames":'; json_lines "${E[cnames]}"
    printf ',"resolved_ips":'; json_lines "${E[ips]}"
    printf ',"ntp_result":{"status":'; json_string "${E[ntp]}"
    printf ',"detail":'; json_string "${E[ntp_detail]}"
    for field in ntp_ip ntp_version ntp_stratum ntp_leap ntp_kiss_code ntp_target_source; do
        printf ','; json_string "${field#ntp_}"; printf ':'; json_string "${E[$field]}"
    done
    printf ',"attempts":'; json_lines "${E[ntp_attempts]}"; printf '}'
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
    emit "Redirect host    ${E[redirect_host]:-none}"
    for field in dns cname tcp tls http; do
        emit "$(printf '%-17s %s - %s' "${field^^}" "${E[$field]}" "${E[${field}_detail]}")"
    done
    if [[ ${E[test_type]} == ntp ]]; then
        emit "NTP UDP/$port     ${E[ntp]} - ${E[ntp_detail]}"
        emit "NTP target source ${E[ntp_target_source]}"
        emit "NTP reply         version=${E[ntp_version]:-unknown}, stratum=${E[ntp_stratum]:-unknown}, leap=${E[ntp_leap]:-unknown}, kiss_code=${E[ntp_kiss_code]:-none}"
        while IFS= read -r value; do [[ -z $value ]] || emit "NTP probe         $value"; done <<< "${E[ntp_attempts]}"
    fi
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
    if [[ ${E[classification]} != 'NOT APPLICABLE' ]]; then
        terminal_progress_clear
        TERMINAL_CURRENT_INDEX=$((${#TERMINAL_ORDER[@]}-1))
        terminal_endpoint
        ((TERMINAL_PROGRESS_DONE+=1))
    fi
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
              for field in dns tcp tls http ntp; do
                  [[ ${E[$field]} != FAIL ]] || value+=" ${field^^}: ${E[${field}_detail]};"
              done
              BLOCKERS+=("$value");;
        WARN) [[ ${CATEGORY_STATUS[$category]} == FAIL ]] || CATEGORY_STATUS[$category]=WARN
              [[ $OVERALL == BLOCKED ]] || OVERALL='READY WITH WARNINGS';;
    esac
    [[ ${E[classification]} != 'NOT DIRECTLY TESTABLE' ]] || UNTESTED+=("${E[hostname]}: ${E[notes]}")
    if [[ ${E[classification]} == 'NOT DIRECTLY TESTABLE' && $category == other_requirements ]]; then
        if [[ -n ${E[label]} && ${E[label]} != '-' ]]; then
            TERMINAL_OTHER_REQUIREMENTS+=("${E[label]} (${E[protocol]^^}/$port)")
        elif [[ ${E[hostname]} == destination-unspecified ]]; then
            ((TERMINAL_UNSPECIFIED_COUNT+=1))
        fi
    fi
}
report_finish() {
    local category line first=1 index=0
    emit ''; emit '----------------------------------------'; emit 'SUMMARY'; emit '----------------------------------------'
    for category in "${CATEGORY_ORDER[@]}"; do emit "$(printf '%-26s %s' "$category" "${CATEGORY_STATUS[$category]}")"; done
    emit ''; emit "Direct endpoint checks: $DIRECT_PASS PASS, $DIRECT_WARN WARN, $DIRECT_FAIL FAIL"
    emit 'Manual requirements are listed below; they are not counted as passed checks.'
    emit "Overall: $OVERALL"
    if ((${#BLOCKERS[@]})); then
        emit 'Detected blockers:'
        for line in "${BLOCKERS[@]}"; do ((index+=1)); emit "$index. $line"; done
        emit 'Suggested owner: Customer Network / DNS / Security Team'
    fi
    emit 'Documented firewall allowlist patterns (configuration guidance; excluded from test results and readiness):'
    for line in "${ALLOWLIST[@]}"; do emit "  $line"; done
    emit 'Other untested requirements:'
    for line in "${UNTESTED[@]}"; do emit "  $line"; done
    emit 'RUM: SERVER-SIDE SANITY CHECK ONLY. Browser corporate DNS/firewalls remain unvalidated.'
    emit 'This checks network prerequisites, not Agent configuration, API keys, instrumentation, permissions, or telemetry ingestion.'
    emit "TXT report: $REPORT_BASE.txt"; emit "JSON report: $REPORT_BASE.json"
    {
        printf '{"schema_version":"1.4","metadata":{"tool_version":'; json_string "$TOOL_VERSION"
        printf ',"timestamp":'; json_string "$TIMESTAMP"
        printf ',"hostname":'; json_string "$MACHINE"
        printf ',"os":'; json_string "$OS_NAME"
        printf ',"last_verified_against_datadog_docs":'; json_string "$VERIFIED"
        printf ',"agent_version":'; json_string "$AGENT_VERSION"
        printf ',"agent_version_source":'; json_string "$AGENT_VERSION_SOURCE"
        printf ',"agent_version_detail":'; json_string "$AGENT_VERSION_DETAIL"
        printf ',"ntp_target_source":'; json_string "$NTP_TARGET_SOURCE"
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
    [[ -z $LAST_TERMINAL_CATEGORY ]] || terminal_group_notes "$LAST_TERMINAL_CATEGORY"
    terminal_summary
}
# END GENERATED MODULE: lib/reporting.sh

# Internal limits, seconds. No background probing or package installation.
# MAX_IP_PROBES is consumed by sourced DNS/TCP modules.
# shellcheck disable=SC2034
TOOL_VERSION=0.1.8
DNS_TIMEOUT=5 TCP_TIMEOUT=5 TLS_TIMEOUT=8 HTTP_TIMEOUT=12 MAX_IP_PROBES=4
NTP_TIMEOUT=5 NTP_MAX_IP_PROBES=2
HTTP_MAX_ATTEMPTS=2 TLS_MAX_ATTEMPTS=2

main() {
    local choice i dep line host field state missing=0 available_tools='' unavailable_tools=''
    SITE=''; CLI_AGENT_VERSION=''; TERMINAL_NO_BANNER=0; TERMINAL_QUIET=0
    declare -ga NTP_HOSTS=()
    while (($#)); do
        case $1 in
            --site) (($#>=2)) || { error '--site requires a value'; return 3; }; SITE=${2,,}; shift 2;;
            --agent-version) (($#>=2)) || { error '--agent-version requires X.Y.Z'; return 3; }; CLI_AGENT_VERSION=$2; shift 2;;
            --ntp-host) (($#>=2)) || { error '--ntp-host requires a hostname or IP'; return 3; }; add_ntp_host "$2" || return 3; shift 2;;
            --quiet) TERMINAL_QUIET=1; shift;;
            --no-banner) TERMINAL_NO_BANNER=1; shift;;
            --help|-h) printf 'Usage: ./dd-network-check.sh [--site SITE] [--agent-version X.Y.Z] [--ntp-host HOST] [--quiet] [--no-banner]\nDefault: full scan using the latest stable Agent release and documented public NTP fallback pools.\n--agent-version overrides DD_PREFLIGHT_AGENT_VERSION and the GitHub latest-release lookup.\n--ntp-host replaces public NTP pools with an explicit customer target (repeat for up to 8 targets). UDP/123.\n--quiet uses a compact terminal header. --no-banner hides the header.\n--quick and --category are reserved for a future release.\n'; return 0;;
            *) error "Unsupported argument: $1"; return 3;;
        esac
    done
    [[ $(uname -s) == Linux ]] || { error 'v0.1 supports Linux only'; return 3; }
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
    emit 'Direct DNS/TCP/OpenSSL probes bypass proxies; curl honors existing HTTPS/ALL_PROXY and NO_PROXY settings.'
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

main "$@"
exit $?
