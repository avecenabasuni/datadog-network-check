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
