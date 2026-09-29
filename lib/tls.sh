#!/usr/bin/env bash
tls_check() {
    local host=$1 target output rc cert meta
    if ! have openssl || ! have timeout; then
        E[tls_detail]='Detailed TLS inspection SKIPPED: openssl or timeout unavailable; see curl_tls for fallback'; return
    fi
    [[ -n ${E[tcp_ip]} ]] || return
    if ! openssl s_client -help 2>&1 | grep -q -- '-verify_hostname'; then
        E[tls_detail]='OpenSSL lacks hostname verification; see curl_tls'; return
    fi
    target=${E[tcp_ip]}; [[ $target != *:* ]] || target="[$target]"
    output=$(timeout -k 1 "$TLS_TIMEOUT" openssl s_client -connect "$target:$port" -servername "$host" -verify_hostname "$host" -verify_return_error -showcerts </dev/null 2>&1); rc=$?
    E[verification]=$(printf '%s\n' "$output" | awk '/Verify return code:|Verification error:/ {print}')
    E[tls]=FAIL; E[tls_detail]="Direct SNI/chain/hostname verification failed (exit $rc)"
    if ((rc==0)) && [[ $output == *'Verify return code: 0 (ok)'* ]]; then E[tls]=PASS; E[tls_detail]='Direct SNI, hostname and certificate chain verified'; fi
    [[ $rc != 124 && $rc != 137 ]] || E[tls_detail]='TLS handshake timeout'
    cert=$(printf '%s\n' "$output" | awk '/-----BEGIN CERTIFICATE-----/{p=1} p{print} /-----END CERTIFICATE-----/{exit}')
    if [[ -n $cert ]]; then
        meta=$(printf '%s\n' "$cert" | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
        E[subject]=$(sed -n 's/^subject=//p' <<< "$meta" | clean)
        E[issuer]=$(sed -n 's/^issuer=//p' <<< "$meta" | clean)
        E[expiry]=$(sed -n 's/^notAfter=//p' <<< "$meta" | clean)
    fi
}
