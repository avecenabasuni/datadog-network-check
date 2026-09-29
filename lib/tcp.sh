#!/usr/bin/env bash
# A separate wrapper makes TCP execution replaceable in offline tests.
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
