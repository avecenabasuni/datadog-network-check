#!/usr/bin/env bash
# A separate wrapper makes TCP execution replaceable in offline tests.
tcp_connect() { timeout -k 1 "$TCP_TIMEOUT" bash -c 'exec 3<>/dev/tcp/"$1"/"$2"' bash "$1" "$2" 2>&1; }
tcp_check() {
    local ip output rc good=0 bad=0 count=0 reason
    if ! have timeout; then E[tcp_detail]='timeout unavailable; bounded raw TCP diagnostic skipped'; return; fi
    [[ -n ${E[ips]} ]] || return
    while IFS= read -r ip; do
        ((count+=1)); if ((count>MAX_IP_PROBES)); then add_note "TCP sampled first $MAX_IP_PROBES addresses; remaining addresses untested"; break; fi
        output=$(tcp_connect "$ip" "$port"); rc=$?
        if ((rc==0)); then
            ((good+=1)); [[ -n ${E[tcp_ip]} ]] || E[tcp_ip]=$ip
            E[tcp_attempts]+="$ip PASS"$'\n'
        else
            ((bad+=1)); reason="connect error $rc"
            case $output in *refused*) reason='connection refused';; *unreachable*) reason='network unreachable';; esac
            [[ $rc != 124 && $rc != 137 ]] || reason=timeout
            E[tcp_attempts]+="$ip FAIL - $reason"$'\n'
        fi
    done <<< "${E[ips]}"
    E[tcp]=FAIL
    ((good==0)) || E[tcp]=PASS
    if ((good>0 && (bad>0 || count>MAX_IP_PROBES))); then E[tcp]=WARN; fi
    E[tcp_detail]="$good successful, $bad failed address probes; direct path"
}
