#!/usr/bin/env bash
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
