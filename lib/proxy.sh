#!/usr/bin/env bash
# Route settings are process-local. Never persist or print their values.
# shellcheck disable=SC2154
proxy_url_valid() {
    local authority host number
    [[ $1 =~ ^https?://([^/[:space:]@?#]+)$ ]] || return 1
    authority=${BASH_REMATCH[1]}
    if [[ $authority =~ ^\[([0-9a-fA-F:]+)\]:([0-9]+)$ ]]; then
        host=${BASH_REMATCH[1]}; number=${BASH_REMATCH[2]}
        valid_ntp_host "$host" || return 1
    elif [[ $authority =~ ^([a-zA-Z0-9._-]+):([0-9]+)$ ]]; then
        host=${BASH_REMATCH[1]}; number=${BASH_REMATCH[2]}
        valid_ntp_host "$host" || return 1
    else return 1; fi
    [[ ${#number} -le 5 ]] && ((10#$number>0 && 10#$number<=65535))
}
proxy_redact() {
    local text=$1 secret
    if [[ ${ROUTE_MODE:-environment} == explicit ]]; then
        for secret in "${PROXY_PASSWORD-}" "${PROXY_USER-}" "${PROXY_URL-}" "${PROXY_HOST-}"; do
            [[ -z $secret ]] || text=${text//"$secret"/[withheld]}
        done
    fi
    printf '%s' "$text"
}
proxy_read_password() {
    if ((PROXY_PASSWORD_STDIN)); then
        IFS= read -r PROXY_PASSWORD || [[ -n $PROXY_PASSWORD ]] || { error 'Cannot read proxy password from stdin'; return 1; }
    elif [[ -t 0 ]]; then
        printf 'Proxy password: '
        IFS= read -rs PROXY_PASSWORD || { printf '\n'; return 1; }
        printf '\n'
    else error 'Use --proxy-password-stdin for unattended authentication'; return 1; fi
}
proxy_configure() {
    local choice auth
    [[ $ROUTE_MODE != explicit || -n $PROXY_URL ]] || { error '--proxy requires a URL'; return 1; }
    if [[ $ROUTE_MODE == environment && -t 0 && -t 1 ]]; then
        printf '\n[ HTTPS ROUTE ]\n  1) Current environment (default)\n  2) Custom proxy\n  3) Direct\nChoice [1]: '
        IFS= read -r choice || return 1
        case ${choice:-1} in
            1) :;;
            2) ROUTE_MODE=explicit; printf 'Proxy URL (http[s]://host:port): '; IFS= read -r PROXY_URL || return 1
               printf 'Basic authentication? [y/N]: '; IFS= read -r auth || return 1
               case ${auth,,} in y|yes) printf 'Proxy username: '; IFS= read -r PROXY_USER && [[ -n $PROXY_USER ]] || { error 'Proxy username is required'; return 1; };; ''|n|no) :;; *) error 'Invalid authentication choice'; return 1;; esac;;
            3) ROUTE_MODE=direct;;
            *) error 'Invalid HTTPS route choice'; return 1;;
        esac
    fi
    if [[ $ROUTE_MODE == explicit ]]; then
        proxy_url_valid "$PROXY_URL" || { error 'Invalid proxy URL. Use http[s]://host:port without credentials or a path'; return 1; }
        PROXY_HOST=${PROXY_URL#*://}; PROXY_HOST=${PROXY_HOST%:*}; PROXY_HOST=${PROXY_HOST#[}; PROXY_HOST=${PROXY_HOST%]}
    fi
    if [[ -n $PROXY_USER ]] || ((PROXY_PASSWORD_STDIN)); then
        [[ $ROUTE_MODE == explicit && -n $PROXY_USER && $PROXY_USER != *:* && ! $PROXY_USER =~ [[:cntrl:]] ]] || { error 'Proxy authentication requires --proxy and a valid username'; return 1; }
        proxy_read_password || return 1
        [[ ! $PROXY_PASSWORD =~ [[:cntrl:]] ]] || { error 'Invalid proxy password'; return 1; }
        PROXY_AUTH_PRESENT=1
    fi
}
curl_config_string() {
    local value=${2//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s = "%s"\n' "$1" "$value"
}
curl_route() (
    unset SSLKEYLOGFILE
    export -n PROXY_URL PROXY_USER PROXY_PASSWORD PROXY_HOST
    if [[ ${ROUTE_MODE:-environment} == environment ]]; then curl --disable "$@"; exit $?; fi
    unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy
    {
        if [[ $ROUTE_MODE == explicit ]]; then
            curl_config_string proxy "$PROXY_URL"
            curl_config_string noproxy ''
            if ((PROXY_AUTH_PRESENT)); then
                printf 'proxy-basic\n'
                curl_config_string proxy-user "$PROXY_USER:$PROXY_PASSWORD"
            fi
        else curl_config_string proxy ''; curl_config_string noproxy '*'; fi
    } | curl --disable --config - "$@"
    exit "${PIPESTATUS[1]}"
)
