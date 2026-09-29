#!/usr/bin/env bash
# Never use --fail, --insecure, credentials, verbose traces, or a user's curlrc.
# Body/headers stay in bounded memory and are discarded after classification.
curl_probe() (
    # Prevent an inherited debug setting from writing TLS session secrets.
    unset SSLKEYLOGFILE
    local metadata rc reader reader_rc
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
        metadata=$(curl --disable --silent --show-error --include --location --max-redirs 3 \
            --proto '=https' --proto-redir '=https' --connect-timeout "$TCP_TIMEOUT" \
            --max-time "$HTTP_TIMEOUT" --max-filesize 65536 --range 0-32767 \
            --output /dev/fd/4 --user-agent 'dd-network-preflight/0.1' \
            --write-out $'\nDD_PREFLIGHT_META\n%{http_code}\n%{url_effective}\n%{remote_ip}\n%{num_redirects}\n%{ssl_verify_result}\n' "$1" 2>/dev/null)
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
http_check() {
    local host=$1 output meta rc='' status final_ip redirect verify body low vendor generic sampled=0 sample_bytes=''
    output=$({ curl_probe "https://$host:$port$path"; printf 'DD_PREFLIGHT_EXIT=%s\n' "$?"; } | tr -d '\000')
    if [[ $output == *DD_PREFLIGHT_META* ]]; then
        meta=${output##*DD_PREFLIGHT_META$'\n'}
        local -a fields
        mapfile -t fields <<< "$meta"
        status=${fields[0]-}; E[final_url]=$(safe_url "${fields[1]-}")
        final_ip=${fields[2]-}; is_ip "$final_ip" && E[remote_ip]=$final_ip
        redirect=${fields[3]-0}; [[ $redirect =~ ^[0-9]+$ ]] && E[redirect_count]=$redirect
        verify=${fields[4]-}
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
        28) E[http_detail]='Connection or request timeout';;
        35|51|58|60|77|83|90|91) E[http_detail]='TLS handshake or certificate verification failed'; E[curl_tls]=FAIL;;
        47) E[http_detail]='Redirect limit exceeded';;
    esac
    if [[ $output == *DD_PREFLIGHT_CAPTURE_ERROR* ]] || { ((rc==0)) && [[ -z ${E[http_status]} || -z $verify ]]; }; then
        E[http]=SKIPPED; E[http_detail]='HTTP diagnostic capture incomplete; response metadata unavailable'
        add_note 'Checker diagnostic incomplete; no network blocker inferred from missing metadata'
    fi
    if [[ $output != *DD_PREFLIGHT_CAPTURE_ERROR* && -n ${E[http_status]} && $verify == 0 ]] && ((rc==0 || rc==63 || (rc==23 && sampled))); then
        E[curl_tls]=PASS; E[http]=PASS
        E[http_detail]='Endpoint reachable; application-level response received; environment route'
        if ((rc==63 || sampled)); then E[http]=WARN; E[http_detail]='HTTPS response received; body exceeded diagnostic size limit'; fi
        if ((E[redirect_count]>0)); then E[http]=WARN; add_note 'Redirect observed; confirm final destination with the network team'; fi
        if ((10#${E[http_status]}>=500)) || [[ ${E[http_status]} == 407 ]]; then E[http]=WARN; add_note 'Service/proxy error response requires review'; fi
    fi
    # Only server/via headers; no cookies, authorization, locations, or raw body saved.
    body=${output%%DD_PREFLIGHT_META*}
    E[server]=$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{h=1;v=""} h && tolower($0) ~ /^server:/{v=substr($0,8)} /^\r?$/{h=0} END{print v}' <<< "$body" | clean)
    E[via]=$(awk 'BEGIN{IGNORECASE=1} /^HTTP\//{h=1;v=""} h && tolower($0) ~ /^via:/{v=substr($0,5)} /^\r?$/{h=0} END{print v}' <<< "$body" | clean)
    low=${body,,}; vendor=''; generic=0
    case $low in *fortigate*|*fortinet*) vendor=Fortinet;; *zscaler*) vendor=Zscaler;; *'palo alto'*) vendor='Palo Alto';; esac
    case $low in *blocked*|*'web filter'*|*'access denied'*|*'category blocked'*) generic=1;; esac
    if [[ -n $vendor ]] && ((generic)); then
        [[ ${E[http]} == FAIL ]] || E[http]=WARN
        add_note "POSSIBLE SECURITY FILTERING: $vendor and denial/filter signature detected; not definitive proof"
    elif ((generic)) && [[ ${E[http]} != FAIL ]]; then
        E[http]=WARN; add_note 'Denial/filter wording observed; may be an ordinary application response; filtering not established'
    fi
    if [[ ${E[tls]} == SKIPPED ]]; then add_note "Detailed TLS inspection SKIPPED; curl TLS fallback ${E[curl_tls]}"; fi
}
