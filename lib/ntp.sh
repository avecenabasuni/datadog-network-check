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
    E[selected_route]=direct
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
