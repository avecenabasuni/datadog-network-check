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
    elif ((generic)) && [[ ${E[http]} != FAIL ]]; then
        E[http]=WARN; add_note 'Denial/filter wording observed; may be an ordinary application response; filtering not established'
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
