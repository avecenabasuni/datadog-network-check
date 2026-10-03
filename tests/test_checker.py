"""Offline behavior tests. Python is a development dependency only.

All test artifacts live beneath reports/. No customer endpoints are contacted.
"""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'source ./dd-network-check.sh\ndeclare -A E=()\nreset_result\nport=443; path=/; requirement=required; PROXY_PRESENT=0\n'


def bash(code, env=None, cwd=ROOT, stdin=None):
    return subprocess.run(['bash', '-c', code], cwd=cwd, env=env, input=stdin,
                          text=True, capture_output=True, timeout=45)


class UnitTests(unittest.TestCase):
    def run_code(self, code):
        result = bash(SOURCE + code)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result.stdout.strip()

    def test_manifests_all_sites(self):
        self.assertEqual(self.run_code('load_sites && validate_manifest || exit 1; '
            '[[ ${#SITE_CODES[@]} == 9 && ${#RECORDS[@]} == 62 ]] || exit 1; '
            'for SITE in "${SITE_CODES[@]}"; do for line in "${RECORDS[@]}"; do '
            'parse_record "$line"; [[ $test_type == manual || $test_type == excluded ]] && continue; '
            'h=${template//\\{site\\}/${SITE_DOMAINS[$SITE]}}; '
            'h=${h//\\{rum\\}/${SITE_RUM[$SITE]}}; h=${h//\\{version\\}/7-75-0}; '
            'valid_host "${h#\\*.}" || exit 1; done; done; echo OK'), 'OK')

    def test_json_escaping(self):
        output = self.run_code("json_string $'quotes \" backslash \\\\ tab\\t newline\\n escape\\033'")
        self.assertEqual(json.loads(output), 'quotes " backslash \\ tab\t newline\n escape')

    def test_terminal_colors_only_when_tty_and_enabled(self):
        def capture(no_color, status='PASS'):
            master, slave = pty.openpty()
            env = os.environ.copy()
            env['TERM'] = 'xterm'
            env.pop('NO_COLOR', None)
            if no_color:
                env['NO_COLOR'] = '1'
            try:
                result = subprocess.run(['bash', '-c', SOURCE + f'terminal_status {status} example.com'],
                    cwd=ROOT, env=env, stdout=slave, stderr=subprocess.PIPE, timeout=10)
                os.close(slave)
                slave = -1
                rendered = os.read(master, 4096)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                return rendered
            finally:
                if slave >= 0:
                    os.close(slave)
                os.close(master)

        self.assertIn(b'\x1b[32m', capture(False))
        self.assertIn(b'\x1b[36m', capture(False, 'REVIEW'))
        self.assertNotIn(b'\x1b[', capture(True))

    def test_terminal_symbols_fall_back_to_ascii(self):
        env = os.environ.copy()
        env['LC_ALL'] = 'C'
        result = bash(SOURCE + 'terminal_status PASS example.com; terminal_status WARN example.com; '
                      'terminal_status REVIEW example.com; terminal_status FAIL example.com', env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('\x1b', result.stdout)
        for symbol in ('[OK]', '[!!]', '[??]', '[XX]'):
            self.assertIn(symbol, result.stdout)

    def test_banner_variants_and_piped_title(self):
        setup = (SOURCE + "declare -A SITE_LABELS=([us1]=US1) SITE_DOMAINS=([us1]=datadoghq.com); "
                 "SITE=us1; MACHINE=eminerba-lab; OS_NAME='Ubuntu 22.04.5 LTS'; "
                 "TERMINAL_TTY=1; ")

        def tty_banner(locale, width, extra='', colorterm=None):
            master, slave = pty.openpty()
            env = os.environ.copy()
            env.update({'LC_ALL': locale, 'TERM': 'xterm'})
            env.pop('NO_COLOR', None)
            env.pop('COLORTERM', None)
            if colorterm:
                env['COLORTERM'] = colorterm
            try:
                code = setup + f'TERMINAL_WIDTH={width}; {extra} terminal_banner'
                result = subprocess.run(['bash', '-c', code], cwd=ROOT, env=env,
                    stdout=slave, stderr=subprocess.PIPE, timeout=10)
                os.close(slave)
                slave = -1
                try:
                    output = os.read(master, 10000).decode('utf-8')
                except OSError as exc:
                    if exc.errno != 5:
                        raise
                    output = ''
                self.assertEqual(result.returncode, 0, result.stderr.decode())
                return output
            finally:
                if slave >= 0:
                    os.close(slave)
                os.close(master)

        full = tty_banner('C.UTF-8', 80)
        self.assertIn('██████╗  █████╗', full)
        self.assertIn('\x1b[38;5;98m', full)
        self.assertIn('\x1b[38;2;99;44;166m', tty_banner('C.UTF-8', 80, colorterm='truecolor'))
        self.assertIn('eminerba-lab · Ubuntu 22.04.5 LTS · US1', full)
        ascii_banner = tty_banner('C', 80)
        self.assertIn(' ____    _  _____', ascii_banner)
        self.assertNotIn('█', ascii_banner)
        self.assertIn('eminerba-lab | Ubuntu 22.04.5 LTS | US1', ascii_banner)
        compact = tty_banner('C.UTF-8', 50)
        self.assertIn('▌ DATADOG NETWORK PREFLIGHT', compact)
        self.assertNotIn('██████╗', compact)
        self.assertNotIn('██████╗', tty_banner('C.UTF-8', 80, 'TERMINAL_QUIET=1;'))
        self.assertEqual(tty_banner('C.UTF-8', 80, 'TERMINAL_NO_BANNER=1;'), '')
        piped = bash(setup + 'TERMINAL_TTY=0; terminal_banner')
        self.assertEqual(piped.returncode, 0, piped.stderr)
        self.assertEqual(piped.stdout, 'DATADOG NETWORK PREFLIGHT  v0.1.7\n')
        self.assertNotIn('\x1b', piped.stdout)

    def test_compact_warning_explains_skipped_optional_tls_probe(self):
        output = self.run_code("LAST_TERMINAL_CATEGORY=agent; category=agent; E[hostname]=example.com; "
            "E[classification]='DIRECT TEST'; E[impact]=WARN; E[dns]=PASS; E[tcp]=PASS; "
            "E[tls]=SKIPPED; E[tls_detail]='OpenSSL unavailable'; "
            "E[http]=PASS; E[http_status]=403; terminal_endpoint")
        self.assertIn('TLS: OpenSSL unavailable', output)

    def test_terminal_rows_keep_redirect_and_align_stages(self):
        output = self.run_code("category=api; LAST_TERMINAL_CATEGORY=''; E[hostname]=api.datadoghq.com; "
            "E[dns]=PASS; E[tcp]=PASS; E[tls]=PASS; E[http]=WARN; E[impact]=WARN; "
            "E[http_status]=307; E[redirect_http_status]=200; E[redirect_http]=PASS; "
            "E[redirect_http_detail]='Reached redirect'; E[redirect_final_url]='https://example.com/[path omitted]'; "
            "E[http_detail]='Redirect'; terminal_table_header; terminal_endpoint")
        self.assertIn('STATUS DESTINATION', output)
        self.assertRegex(output, r'WARN\s+api\.datadoghq\.com\s+ok\s+ok\s+ok\s+307>200')
        self.assertIn('Redirect follow-up needs review. See TXT report.', output)

    def test_terminal_long_and_narrow_rows_keep_full_hostname(self):
        hostname = 'instrumentation-telemetry-intake.datadoghq.com'
        code = ("category=instrumentation; LAST_TERMINAL_CATEGORY=''; "
                f"E[hostname]={hostname}; E[dns]=PASS; E[tcp]=PASS; "
                "E[tls]=SKIPPED; E[http]=PASS; E[http_status]=403; terminal_endpoint")
        wide = self.run_code(code)
        self.assertIn(hostname, wide)
        self.assertIn('ok   ok   -- 403', wide)
        self.assertLessEqual(max(map(len, wide.splitlines())), 80)
        narrow = self.run_code('COLUMNS=60; ' + code)
        self.assertIn(hostname, narrow)
        self.assertNotIn('STATUS DESTINATION', narrow)
        self.assertIn('DNS ok  TCP ok  TLS --  HTTP 403', narrow)
        very_narrow = self.run_code('COLUMNS=50; ' + code)
        self.assertIn('\u2026', very_narrow)
        self.assertIn('intake.datadoghq.com', very_narrow)
        self.assertIn(hostname, very_narrow)
        self.assertLessEqual(max(map(len, very_narrow.splitlines())), 50)

    def test_notes_end_in_a_complete_sentence(self):
        output = self.run_code("COLUMNS=50; terminal_note 'This diagnostic has many clauses and "
            "details that would otherwise be cut off in the middle of a sentence, "
            "so the concise fallback should be shown instead.'")
        self.assertIn('See TXT report for diagnostic details.', output)
        self.assertNotIn('...', output)
        self.assertLessEqual(len(output.splitlines()), 2)

    def test_terminal_review_is_explicitly_untested(self):
        output = self.run_code("category=agent; LAST_TERMINAL_CATEGORY=''; "
            "E[hostname]='{version}-app.agent.datadoghq.com'; E[test_type]=version; E[classification]='NOT DIRECTLY TESTABLE'; "
            "terminal_endpoint")
        self.assertIn('REVIEW', output)
        self.assertIn('Agent version not determined. Not tested.', output)
        self.assertNotIn('DNS ok', output)
        self.assertLessEqual(max(map(len, output.splitlines())), 80)

    def test_terminal_category_header_streams_without_future_counts(self):
        output = self.run_code("declare -A TERMINAL_COUNTS=([agent:PASS]=2 [agent:REVIEW]=3); "
            "terminal_section agent")
        self.assertIn('AGENT', output)
        self.assertNotIn('2 ', output)
        self.assertNotIn('3 ', output)
        self.assertLessEqual(max(map(len, output.splitlines())), 80)

    def test_terminal_wraps_long_diagnostic_at_80_columns(self):
        output = self.run_code("terminal_wrap 'HTTP: redirected to "
            "https://accounts.google.com/[path omitted]; review destination allowlist' "
            "'       ' '             '")
        self.assertLessEqual(max(map(len, output.splitlines())), 80)
        self.assertIn('https://accounts.google.com/[path omitted].', output)
        self.assertIn('review destination allowlist', ' '.join(output.split()))

    def test_terminal_groups_expected_redirect_hosts_once(self):
        output = self.run_code(r'''
declare -A TERMINAL_SNAP=() TERMINAL_COUNTS=() TERMINAL_GROUP_COUNTS=() TERMINAL_GROUP_HOSTS=() TERMINAL_GROUP_HOST_SEEN=()
declare -a TERMINAL_ORDER=() TERMINAL_NOTE_KEY=()
category=container_registries
for host in gcr.io eu.gcr.io; do
    reset_result
    E[hostname]=$host; E[impact]=PASS
    E[dns]=PASS; E[tcp]=PASS; E[tls]=PASS; E[http]=PASS; E[http_status]=302
    E[redirect_http]=PASS; E[redirect_http_detail]='Reached redirect'
    E[redirect_http_status]=200
    E[redirect_host]=accounts.google.com
    E[redirect_final_url]='https://accounts.google.com/[path omitted]'
    terminal_capture_endpoint
    TERMINAL_CURRENT_INDEX=$((${#TERMINAL_ORDER[@]}-1))
    terminal_endpoint
done
terminal_group_notes "$category"
''')
        self.assertIn('gcr.io', output)
        self.assertIn('eu.gcr.io', output)
        self.assertEqual(output.count('Allow accounts.google.com.'), 1)
        self.assertNotIn('redirected to https://accounts.google.com', output)

    def test_redirect_group_note_lists_unique_hosts_at_50_columns(self):
        output = self.run_code("COLUMNS=50; declare -A "
            "TERMINAL_GROUP_COUNTS=([container_registries:expected_redirect]=3) "
            "TERMINAL_GROUP_HOSTS=([container_registries]='docs.datadoghq.com, "
            "accounts.google.com, www.docker.com'); terminal_group_notes container_registries")
        for host in ('docs.datadoghq.com', 'accounts.google.com', 'www.docker.com'):
            self.assertIn(host, output)
        self.assertLessEqual(len(output.splitlines()), 2)
        self.assertLessEqual(max(map(len, output.splitlines())), 50)

    def test_terminal_progress_is_silent_when_piped(self):
        output = self.run_code('TERMINAL_TTY=0; TERMINAL_PROGRESS_DONE=1; '
            'TERMINAL_PROGRESS_TOTAL=3; terminal_progress; terminal_progress_clear')
        self.assertEqual(output, '')

    def test_progress_total_uses_applicable_manifest_records(self):
        output = self.run_code('load_sites && validate_manifest; SITE=us1; '
            'full=$(terminal_destination_count); '
            'RECORDS=("${RECORDS[0]}" "${RECORDS[4]}"); '
            'printf "%s %s" "$full" "$(terminal_destination_count)"')
        self.assertEqual(output, '54 1')

    def test_safe_url_redaction(self):
        output = self.run_code("safe_url 'https://name:secret@example.com/token-path?api_key=secret#secret'")
        self.assertEqual(output, 'https://example.com/[path omitted]')

    def test_dns_failure(self):
        output = self.run_code('have() { [[ $1 == getent || $1 == timeout ]]; }; '
            'timeout() { return 2; }; dns_check missing.invalid; '
            'echo "${E[dns]} ${E[cname]} ${E[ips]}"')
        self.assertEqual(output, 'FAIL SKIPPED')

    def test_dns_missing_dig(self):
        output = self.run_code('have() { [[ $1 == getent || $1 == timeout ]]; }; '
            'timeout() { printf "192.0.2.1 STREAM test\\n192.0.2.1 DGRAM test\\n2001:db8::1 STREAM test\\n"; }; '
            'dns_check example.com; echo "${E[dns]} ${E[cname]}"; echo "${E[ips]}"')
        self.assertEqual(output, 'PASS SKIPPED\n192.0.2.1\n2001:db8::1')

    def test_cname_chain_and_aaaa(self):
        code = r'''
have() { [[ $1 == dig ]]; }
dig() {
    case "${*: -1}" in
      A) echo 'example.com. 60 IN A 192.0.2.1';;
      AAAA) echo 'example.com. 60 IN AAAA 2001:db8::1';;
      CNAME) echo ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1'
        [[ " $* " != *' example.com. '* ]] || echo 'example.com. 60 IN CNAME edge.example.com.';;
    esac
    return 0
}
dns_check example.com; echo "${E[dns]} ${E[cname]}"; echo "${E[cnames]}"; echo "${E[ips]}"
'''
        output = self.run_code(code)
        self.assertIn('PASS PASS\nedge.example.com', output)
        self.assertIn('2001:db8::1', output)

    def test_cname_servfail(self):
        output = self.run_code('have() { [[ $1 == dig ]]; }; dig() { echo "status: SERVFAIL"; }; '
                               'dns_check example.com; echo "${E[dns]} ${E[cname]}"')
        self.assertEqual(output, 'FAIL WARN')

    def test_tcp_refused_and_timeout(self):
        for response in ['echo "connection refused"; return 1', 'return 124']:
            output = self.run_code('E[ips]=192.0.2.1; tcp_connect() { ' + response + '; }; '
                                  'tcp_check; echo "${E[tcp]} ${E[tcp_attempts]}"')
            self.assertTrue(output.startswith('FAIL 192.0.2.1 FAIL'), output)

    def test_tcp_mixed_ipv4_ipv6(self):
        output = self.run_code("E[ips]=$'192.0.2.1\\n2001:db8::1'; "
            'tcp_connect() { [[ $1 == 192.0.2.1 ]]; }; tcp_check; echo "${E[tcp]} ${E[tcp_ip]}"')
        self.assertEqual(output, 'WARN 192.0.2.1')

    def test_tcp_sampling_does_not_warn_when_all_sampled_ips_pass(self):
        output = self.run_code("E[ips]=$'192.0.2.1\\n192.0.2.2\\n192.0.2.3\\n192.0.2.4\\n192.0.2.5'; "
            'tcp_connect() { return 0; }; tcp_check; echo "${E[tcp]} ${E[tcp_detail]}"; echo "${E[notes]}"')
        self.assertTrue(output.startswith('PASS 4 successful, 0 other failures'), output)
        self.assertIn('remaining addresses untested', output)

    def test_tcp_ipv6_unreachable_with_working_ipv4_is_pass_with_detail(self):
        output = self.run_code("E[ips]=$'192.0.2.1\\n2001:db8::1'; "
            'tcp_connect() { [[ $1 == 192.0.2.1 ]] && return 0; echo "Network is unreachable"; return 1; }; '
            'tcp_check; echo "${E[tcp]} ${E[tcp_detail]}"; echo "${E[tcp_attempts]}"; echo "${E[notes]}"')
        self.assertTrue(output.startswith('PASS 1 successful, 0 other failures, 1 IPv6 network-unreachable'), output)
        self.assertIn('2001:db8::1 FAIL - network unreachable', output)
        self.assertIn('IPv6 address probe(s) reported network unreachable', output)

    def test_tcp_ipv4_timeout_with_working_ipv4_remains_warn(self):
        output = self.run_code("E[ips]=$'192.0.2.1\\n192.0.2.2'; "
            'tcp_connect() { [[ $1 == 192.0.2.1 ]] && return 0; return 124; }; '
            'tcp_check; echo "${E[tcp]} ${E[tcp_detail]}"')
        self.assertTrue(output.startswith('WARN 1 successful, 1 other failures'), output)

    def test_tcp_ipv6_only_unreachable_remains_fail(self):
        output = self.run_code('E[ips]=2001:db8::1; '
            'tcp_connect() { echo "Network is unreachable"; return 1; }; '
            'tcp_check; echo "${E[tcp]} ${E[tcp_detail]}"')
        self.assertTrue(output.startswith('FAIL 0 successful, 0 other failures, 1 IPv6'), output)

    def test_missing_timeout(self):
        output = self.run_code('have() { return 1; }; E[ips]=192.0.2.1; tcp_check; echo "${E[tcp]}"')
        self.assertEqual(output, 'SKIPPED')

    def test_missing_openssl(self):
        output = self.run_code('have() { [[ $1 != openssl ]]; }; tls_check example.com; echo "${E[tls]} ${E[tls_detail]}"')
        self.assertIn('SKIPPED', output)

    def test_missing_all_dns_tools(self):
        output = self.run_code('have() { return 1; }; dns_check example.com; '
                               'echo "${E[dns]} ${E[cname]}"')
        self.assertEqual(output, 'SKIPPED SKIPPED')

    def test_nss_dns_disagreement(self):
        output = self.run_code('have() { [[ $1 != nslookup ]]; }; timeout() { return 2; }; '
            'dig() { echo "status: NOERROR"; echo "example.com. 60 IN A 192.0.2.1"; }; '
            'dns_check example.com; echo "${E[dns]} ${E[ips]} ${E[notes]}"')
        self.assertIn('FAIL 192.0.2.1', output)
        self.assertIn('resolver paths disagree', output)

    def test_latest_stable_agent_lookup_is_bounded_and_does_not_use_installed_agent(self):
        output = self.run_code(r'''
SSLKEYLOGFILE=/must-not-write; export SSLKEYLOGFILE
datadog-agent() { echo 'Agent 7.75.0'; }
curl() {
    [[ -z ${SSLKEYLOGFILE-} && ${*: -1} == https://github.com/DataDog/datadog-agent/releases/latest ]] || return 99
    [[ " $* " == *' --head '* && " $* " == *' --max-time 12 '* && " $* " == *' --max-redirs 3 '* ]] || return 99
    [[ " $* " == *' --proto =https --proto-redir =https '* && " $* " != *' --insecure '* ]] || return 99
    echo 'https://github.com/DataDog/datadog-agent/releases/tag/7.84.1'
}
detect_agent_version
printf '%s %s %s' "$AGENT_VERSION_SOURCE" "$AGENT_VERSION" "$AGENT_VERSION_DISPLAY"
''')
        self.assertEqual(output, 'latest-release 7-84-1 7.84.1')

    def test_latest_agent_lookup_rejects_untrusted_or_prerelease_url(self):
        for url in ['https://github.com/DataDog/datadog-agent/releases/tag/7.84.1-rc.1',
                    'https://other.example/releases/tag/7.84.1',
                    'https://github.com/DataDog/datadog-agent/releases/latest']:
            output = self.run_code(f"curl() {{ echo '{url}'; }}; detect_agent_version; "
                'printf "%s|%s|%s" "$AGENT_VERSION" "$AGENT_VERSION_SOURCE" "$AGENT_VERSION_DETAIL"')
            self.assertTrue(output.startswith('|none|Latest release lookup returned no stable'), output)

    def test_latest_agent_lookup_error_does_not_accept_partial_output(self):
        output = self.run_code("curl() { echo 'https://github.com/DataDog/datadog-agent/releases/tag/7.84.1'; return 28; }; "
            'detect_agent_version; printf "%s|%s" "$AGENT_VERSION" "$AGENT_VERSION_DETAIL"')
        self.assertTrue(output.startswith('|Latest release lookup failed (curl exit 28)'), output)

    def test_agent_version_overrides_skip_latest_lookup(self):
        output = self.run_code("CLI_AGENT_VERSION=7.77.0; DD_PREFLIGHT_AGENT_VERSION=7.75.0; "
            "curl() { echo UNEXPECTED_LOOKUP; return 99; }; detect_agent_version; "
            'printf "%s %s" "$AGENT_VERSION_SOURCE" "$AGENT_VERSION"')
        self.assertEqual(output, 'flag 7-77-0')
        output = self.run_code("DD_PREFLIGHT_AGENT_VERSION=7.75.0; "
            "curl() { echo UNEXPECTED_LOOKUP; return 99; }; detect_agent_version; "
            'printf "%s %s" "$AGENT_VERSION_SOURCE" "$AGENT_VERSION"')
        self.assertEqual(output, 'environment 7-75-0')

    def test_header_fields_have_separate_lines_at_wide_and_narrow_widths(self):
        for width in [80, 50]:
            output = self.run_code(f'TERMINAL_WIDTH={width}; '
                "AGENT_VERSION_DISPLAY=7.84.1; AGENT_VERSION_SOURCE=latest-release; "
                "terminal_intro 'bash curl getent dig nslookup openssl timeout nc' ''")
            lines = output.splitlines()
            self.assertEqual(lines[0], 'Proxy: none')
            self.assertTrue(lines[1].startswith('  Tools: bash curl'))
            self.assertIn('  Scope: all destinations', lines)
            self.assertIn('  Agent: 7.84.1 (latest-release)', lines)
            self.assertLessEqual(max(map(len, lines)), width)
            self.assertFalse(any('Proxy:' in line and 'Tools:' in line for line in lines))

    def test_tls_sni_verification(self):
        code = r'''
E[tcp_ip]=2001:db8::1
openssl() { echo '-verify_hostname'; }
timeout() {
 [[ " $* " == *' -servername example.com '* && " $* " == *' -verify_hostname example.com '* && " $* " == *' -verify_return_error '* && " $* " == *' [2001:db8::1]:443 '* ]] || return 1
 echo 'Verify return code: 0 (ok)'
}
tls_check example.com; echo "${E[tls]}"
'''
        self.assertEqual(self.run_code(code), 'PASS')

    def http(self, status='403', rc=0, body='HTTP/1.1 403 Forbidden\r\nServer: intake\r\n\r\n', redirects=0):
        payload = body + '\nDD_PREFLIGHT_META\n' + status + '\nhttps://example.com/\n192.0.2.1\n' + str(redirects) + '\n0\n'
        # Pass fixture via a shell-quoted heredoc, never execute response content.
        code = 'curl_probe() { cat <<\'FIXTURE\'\n' + payload + '\nFIXTURE\nreturn ' + str(rc) + '; }; '
        code += 'http_check example.com; printf "%s\\n" "${E[http]}" "${E[curl_tls]}" "${E[notes]}"'
        return self.run_code(code)

    def test_http_non_2xx_reachable(self):
        for status in ['200', '400', '401', '403', '404', '405']:
            self.assertTrue(self.http(status).startswith('PASS\nPASS'), status)

    def test_http_timeout_not_overridden_by_status(self):
        self.assertTrue(self.http(rc=28).startswith('FAIL\n'))

    def test_http_tls_failure(self):
        self.assertTrue(self.http(rc=60).startswith('FAIL\nFAIL'))

    def test_http_redirect_warning(self):
        self.assertTrue(self.http(redirects=1).startswith('WARN\nPASS'))

    def test_http_capture_limit(self):
        self.assertTrue(self.http(status='200', rc=63).startswith('PASS\nPASS'))

    def test_http_binary_response(self):
        result = bash(SOURCE + r'''
curl_probe() { printf 'HTTP/1.1 200 OK\r\n\r\n\000binary\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n'; }
http_check example.com; echo "${E[http]}"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertEqual(result.stdout.strip(), 'PASS')

    def test_large_stream_keeps_metadata_after_sample_pipe_closes(self):
        # Emulate pre-8.4 curl: unknown-size body ignores --max-filesize and
        # returns CURLE_WRITE_ERROR when our bounded response pipe closes.
        result = bash(SOURCE + r'''
curl() {
    { printf 'HTTP/1.1 200 OK\r\nServer: fixture\r\n\r\n'; head -c 180000 /dev/zero | tr '\000' x; } >&4 2>/dev/null
    printf '\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n'
    return 23
}
http_check example.com
printf '%s\n' "${E[http]}" "${E[curl_exit]}" "${E[http_status]}" "${E[curl_tls]}" "${E[server]}" "${E[http_detail]}"
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        lines = result.stdout.splitlines()
        self.assertEqual(lines[:4], ['PASS', '23', '200', 'PASS'])
        self.assertEqual(lines[4].strip(), 'fixture')
        self.assertIn('diagnostic body sample intentionally capped', lines[5])

    def test_real_write_error_not_treated_as_sample_limit(self):
        output = self.run_code(r'''
curl_probe() { printf '\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n100\n40\n'; return 23; }
http_check example.com; echo "${E[http]} ${E[curl_exit]}"
''')
        self.assertEqual(output, 'FAIL 23')

    def test_large_response_timeout_stays_failure(self):
        output = self.run_code(r'''
curl_probe() { printf '\nDD_PREFLIGHT_SAMPLE_BYTES=65536\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n'; return 28; }
http_check example.com; echo "${E[http]} ${E[curl_exit]}"
''')
        self.assertEqual(output, 'FAIL 28')

    def test_missing_metadata_is_diagnostic_gap_not_network_blocker(self):
        output = self.run_code('curl_probe() { printf "HTTP/1.1 200 OK\\r\\n\\r\\n"; }; '
                               'http_check example.com; classify_result; '
                               'echo "${E[http]} ${E[curl_exit]} ${E[impact]}"')
        self.assertEqual(output, 'SKIPPED 0 WARN')

    def test_sample_reader_failure_is_not_reported_as_pass(self):
        output = self.run_code(r'''
curl_probe() { printf '\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n20\n40\nDD_PREFLIGHT_CAPTURE_ERROR\n'; }
http_check example.com; echo "${E[http]} ${E[curl_exit]}"
''')
        self.assertEqual(output, 'SKIPPED 0')

    def test_actual_probe_retains_small_body_and_metadata(self):
        output = self.run_code(r'''
curl() {
    printf 'HTTP/1.1 403 Forbidden\r\nServer: fixture\r\n\r\nrejected' >&4
    printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.1\n0\n0\n8\n44\n'
}
http_check example.com; echo "${E[http]} ${E[curl_exit]} ${E[http_status]} ${E[server]}"
''')
        self.assertEqual(output, 'PASS 0 403  fixture')

    def test_curl_does_not_enable_secret_logging(self):
        output = self.run_code('SSLKEYLOGFILE=/do-not-write; export SSLKEYLOGFILE; '
            'curl() { [[ -z ${SSLKEYLOGFILE-} ]] || return 1; echo OK; }; curl_probe https://example.com; '
            '[[ $SSLKEYLOGFILE == /do-not-write ]] || exit 1')
        self.assertTrue(output.endswith('OK'), output)

    def test_block_page(self):
        for vendor in ['FortiGate', 'Zscaler', 'Palo Alto']:
            for status in ['200', '403']:
                output = self.http(status=status, body=f'HTTP/1.1 {status} Response\r\n\r\n{vendor}: category blocked')
                self.assertIn('POSSIBLE SECURITY FILTERING', output)
                self.assertTrue(output.startswith('WARN\nPASS'), output)

    def test_generic_denial_wording_does_not_warn_on_verified_http(self):
        for status in ['200', '401', '403', '404']:
            for wording in ['Access denied', 'blocked', 'web filter']:
                output = self.http(status=status, body=f'HTTP/1.1 {status} Response\r\n\r\n{wording}')
                self.assertTrue(output.startswith('PASS\nPASS'), output)
                self.assertIn('insufficient evidence of network filtering', output)
                self.assertNotIn('POSSIBLE SECURITY FILTERING', output)

    def test_denial_wording_never_clears_service_or_transport_errors(self):
        for status in ['407', '500', '503']:
            output = self.http(status=status, body=f'HTTP/1.1 {status} Error\r\n\r\nAccess denied')
            self.assertTrue(output.startswith('WARN\nPASS'), output)
            self.assertIn('Service/proxy error response requires review', output)
        for rc in [28, 60]:
            output = self.http(rc=rc, body='HTTP/1.1 403 Forbidden\r\n\r\nAccess denied')
            self.assertTrue(output.startswith('FAIL\n'), output)

    def test_classification(self):
        base = 'for k in dns cname tcp tls http; do E[$k]=PASS; done; '
        self.assertEqual(self.run_code(base + 'classify_result; echo "${E[impact]}"'), 'PASS')
        self.assertEqual(self.run_code(base + 'E[dns]=FAIL; classify_result; echo "${E[impact]}"'), 'FAIL')
        self.assertEqual(self.run_code(base + 'E[http]=FAIL; requirement=informational; classify_result; echo "${E[status]} ${E[impact]}"'), 'FAIL WARN')
        self.assertEqual(self.run_code(base + 'E[tcp]=FAIL; E[curl_tls]=PASS; PROXY_PRESENT=1; classify_result; echo "${E[status]} ${E[impact]}"'), 'FAIL WARN')

    def test_proxy_secrets_withheld(self):
        output = self.run_code("emit() { echo \"$*\"; }; HTTPS_PROXY='http://user:supersecret@proxy:3128'; "
                               "NO_PROXY='sensitive.example.com'; proxy_snapshot; echo \"$PROXY_JSON\"")
        self.assertNotIn('supersecret', output)
        self.assertNotIn('sensitive', output)
        self.assertIn('configured (value withheld)', output)


class IntegrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='.test-', dir=ROOT / 'reports')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for name in ['lib', 'config']:
            shutil.copytree(ROOT / name, self.root / name)
        shutil.copy2(ROOT / 'dd-network-check.sh', self.root)
        (self.root / 'reports').mkdir()
        self.bin = self.root / 'mock-bin'
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.lower().endswith('_proxy')}
        self.env['PATH'] = str(self.bin) + ':' + os.environ['PATH']
        self.env['MOCK_LOG'] = str(self.root / 'calls')
        self.write_command('getent', 'echo "192.0.2.1 STREAM example.com"')
        self.write_command('dig', "echo ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1'")
        self.write_command('timeout', r'''
shift 2; shift
case $1 in
  getent) shift; getent "$@";;
  bash) exit 0;;
  openssl) echo 'Verify return code: 0 (ok)';;
  datadog-agent) exit 1;;
  *) exit 1;;
esac
''')
        self.write_command('openssl', "echo '-verify_hostname'")
        self.write_command('curl', r'''
printf '%s\n' "$*" >> "$MOCK_LOG"
printf 'HTTP/1.1 403 Forbidden\r\nServer: intake\r\n\r\n'
printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.1\n0\n0\n'
''')

    def write_command(self, name, body):
        target = self.bin / name
        # Keep unrelated network-probe fixtures offline and independent of
        # release discovery. Tests for lookup failure provide their own branch.
        if name == 'curl' and 'releases/latest' not in body:
            body = r'''
if [[ ${*: -1} == https://github.com/DataDog/datadog-agent/releases/latest ]]; then
    printf 'https://github.com/DataDog/datadog-agent/releases/tag/7.84.1'
    exit 0
fi
''' + body
        target.write_text('#!/usr/bin/env bash\n' + body + '\n')
        target.chmod(0o700)

    def manifest(self, extra='', required=True):
        req = 'required' if required else 'informational'
        text = '# last_verified_against_datadog_docs=2026-09-29\n'
        text += f'public|agent|Public HTTPS|example.com|443|https|all|full|{req}|all|/|-|https://example.com/docs\n'
        (self.root / 'config/endpoints.conf').write_text(text + extra)

    def scan(self, expected, interactive=False):
        result = bash('./dd-network-check.sh' + ('' if interactive else ' --site us1'), self.env, self.root, '1\n' if interactive else None)
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        reports = list((self.root / 'reports').glob('*.json'))
        if expected == 3:
            self.assertEqual(reports, [])
            return result, None
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        txt = reports[0].with_suffix('.txt').read_text()
        self.assertNotIn('\x1b', txt)
        manifest_rows = [line.split('|') for line in (self.root / 'config/endpoints.conf').read_text().splitlines()
                         if line and not line.startswith('#')]
        expected_endpoints = sum(row[6] not in ('windows', 'desktop') and row[7] not in ('excluded', 'wildcard')
                                 and (row[9] == 'all' or 'us1' in row[9].split(','))
                                 for row in manifest_rows)
        self.assertEqual(len(report['endpoints']), expected_endpoints)
        self.assertEqual(report['metadata']['hostname'], os.uname().nodename)
        return result, report

    def test_interactive_report_ready(self):
        self.manifest()
        result, report = self.scan(0, interactive=True)
        self.assertIn('9) US2-FED', result.stdout)
        self.assertIn('DATADOG NETWORK PREFLIGHT  v0.1.7', result.stdout)
        self.assertEqual(result.stdout.count('DATADOG NETWORK PREFLIGHT  v0.1.7'), 1)
        self.assertIn('[ SELECT DATADOG SITE ]', result.stdout)
        self.assertIn('Choice: \nDATADOG NETWORK PREFLIGHT', result.stdout)
        self.assertRegex(result.stdout, r'1 pass.*0 warn.*0 fail.*0 review')
        self.assertRegex(result.stdout, r'PASS\s+example\.com\s+ok\s+ok\s+ok\s+403')
        self.assertNotIn('TLS probe', result.stdout)
        self.assertNotIn('CNAME chain', result.stdout)
        self.assertNotIn('\x1b', result.stdout)
        self.assertIn('Reports: ' + str(self.root / 'reports'), result.stdout)
        self.assertRegex(result.stdout, r'(?m)^  TXT  dd-network-preflight-.*\.txt$')
        self.assertRegex(result.stdout, r'(?m)^  JSON dd-network-preflight-.*\.json$')
        detailed = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('TLS probe', detailed)
        self.assertIn('DNS               PASS', detailed)
        self.assertEqual(report['overall_status'], 'READY')
        self.assertEqual(report['endpoints'][0]['http_result']['http_status'], '403')
        calls = (self.root / 'calls').read_text()
        self.assertIn('--disable --silent', calls)
        self.assertIn('--proto =https --proto-redir =https', calls)
        self.assertNotIn('--insecure', calls)

    def test_rows_stream_before_later_endpoint_finishes(self):
        self.manifest('second|api|Second destination|second.example.com|443|https|all|full|required|all|/|-|https://example.com/docs\n')
        self.write_command('curl', r'''
[[ $* != *second.example.com* ]] || sleep 3
printf 'HTTP/1.1 403 Forbidden\r\n\r\n'
printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.1\n0\n0\n'
''')
        process = subprocess.Popen(['bash', './dd-network-check.sh', '--site', 'us1'],
                                   cwd=self.root, env=self.env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        seen = b''
        try:
            while b' API ' not in seen:
                ready, _, _ = select.select([process.stdout], [], [], 2)
                self.assertTrue(ready, seen.decode(errors='replace'))
                seen += os.read(process.stdout.fileno(), 4096)
            self.assertRegex(seen.decode(), r'PASS\s+example\.com')
            self.assertIsNone(process.poll(), 'Rows were held until the scan completed')
            _, stderr = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, stderr.decode())
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_wildcard_never_probed(self):
        self.manifest('wildcard|agent|Agent wildcard|*.agent.{site}|443|https|all|wildcard|required|all|/|ALLOWLIST REQUIREMENT|https://example.com/docs\n')
        result, report = self.scan(0)
        self.assertEqual(report['overall_status'], 'READY')
        self.assertNotIn('*.agent', (self.root / 'calls').read_text())
        self.assertEqual(report['allowlist_requirements'], ['*.agent.datadoghq.com'])
        self.assertNotIn('*.agent', result.stdout)
        self.assertNotIn('Manual review', result.stdout)
        self.assertEqual(report['categories'], {'agent': 'PASS'})
        self.assertEqual(report['untested_requirements'], [])
        detailed = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('configuration guidance; excluded from test results and readiness', detailed)
        self.assertIn('*.agent.datadoghq.com', detailed)

    def test_wildcard_only_category_does_not_create_endpoint_or_warning(self):
        self.manifest('wildcard|rum|Browser wildcard|*.{rum}|443|https|all|wildcard|informational|all|/|-|https://example.com/docs\n')
        result, report = self.scan(0)
        self.assertEqual(report['categories'], {'agent': 'PASS'})
        self.assertEqual(report['direct_endpoint_counts'], {'pass': 1, 'warn': 0, 'fail': 0})
        self.assertEqual(report['allowlist_requirements'], ['*.browser-intake-datadoghq.com'])
        self.assertNotIn('*.browser-intake', result.stdout)
        self.assertNotIn('REVIEW ', result.stdout)

    def test_wildcard_docs_notes_follow_scope_for_all_nine_sites(self):
        self.manifest(
            'agent-pattern|agent|Agent pattern|*.agent.{site}|443|https|all|wildcard|required|all|/|-|https://example.com/docs\n'
            'rum-pattern|rum|Browser pattern|*.{rum}|443|https|all|wildcard|informational|us1,us3,us5,eu1,ap1,ap2,uk1|/|-|https://example.com/docs\n')
        records = [line.split('|') for line in (self.root / 'config/sites.conf').read_text().splitlines()
                   if line and not line.startswith('#')]
        for code, _, site_domain, rum_domain in records:
            with self.subTest(site=code):
                previous = set((self.root / 'reports').glob('*.json'))
                result = bash(f'./dd-network-check.sh --site {code}', self.env, self.root)
                self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
                report_path, = set((self.root / 'reports').glob('*.json')) - previous
                report = json.loads(report_path.read_text())
                patterns = [f'*.agent.{site_domain}']
                if code not in ('us1-fed', 'us2-fed'):
                    patterns.append(f'*.{rum_domain}')
                self.assertEqual(report['allowlist_requirements'], patterns)
                self.assertEqual([endpoint['id'] for endpoint in report['endpoints']], ['public'])
                self.assertEqual(report['categories'], {'agent': 'PASS'})
                self.assertEqual(report['untested_requirements'], [])
                self.assertNotIn('REVIEW ', result.stdout)

    def test_version_override_probes_versioned_agent_hostname(self):
        (self.root / 'config/endpoints.conf').write_text(
            '# last_verified_against_datadog_docs=2026-09-29\n'
            'metrics|agent|Metrics|{version}-app.agent.{site}|443|https|all|version|required|all|/|-|https://example.com/docs\n'
            'flare|agent|Flare|{version}-flare.agent.{site}|443|https|all|version|informational|all|/|-|https://example.com/docs\n')
        self.env['DD_PREFLIGHT_AGENT_VERSION'] = '7.74.0'
        result = bash('./dd-network-check.sh --site us1 --agent-version 7.75.0', self.env, self.root)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        report = json.loads(next((self.root / 'reports').glob('*.json')).read_text())
        self.assertEqual([endpoint['hostname'] for endpoint in report['endpoints']], [
            '7-75-0-app.agent.datadoghq.com', '7-75-0-flare.agent.datadoghq.com'])
        self.assertEqual([endpoint['classification'] for endpoint in report['endpoints']],
                         ['DIRECT TEST', 'DIRECT TEST'])
        self.assertIn('Agent: 7.75.0', result.stdout)
        self.assertNotIn('7-74-0-app', result.stdout)

    def test_missing_agent_version_keeps_versioned_host_review(self):
        (self.root / 'config/endpoints.conf').write_text(
            '# last_verified_against_datadog_docs=2026-09-29\n'
            'metrics|agent|Metrics|{version}-app.agent.{site}|443|https|all|version|required|all|/|-|https://example.com/docs\n')
        self.write_command('curl', r'''
[[ ${*: -1} != https://github.com/DataDog/datadog-agent/releases/latest ]] || exit 28
exit 99
''')
        result, report = self.scan(1)
        self.assertEqual(report['endpoints'][0]['classification'], 'NOT DIRECTLY TESTABLE')
        self.assertIn('Agent: not determined', result.stdout)
        self.assertIn('Latest release lookup failed (curl exit 28)', result.stdout)
        self.assertEqual(report['metadata']['agent_version_source'], 'none')
        self.assertIn('curl exit 28', report['metadata']['agent_version_detail'])
        self.assertIn('curl exit 28', report['endpoints'][0]['notes'])
        self.assertNotIn('7-75-0-app', (self.root / 'calls').read_text() if (self.root / 'calls').exists() else '')

    def test_latest_release_probes_both_agent_hosts_and_keeps_wildcard_as_docs_note(self):
        (self.root / 'config/endpoints.conf').write_text(
            '# last_verified_against_datadog_docs=2026-09-29\n'
            'wildcard|agent|Allowlist|*.agent.{site}|443|https|all|wildcard|required|all|/|-|https://example.com/docs\n'
            'metrics|agent|Metrics|{version}-app.agent.{site}|443|https|all|version|required|all|/|-|https://example.com/docs\n'
            'flare|agent|Flare|{version}-flare.agent.{site}|443|https|all|version|informational|all|/|-|https://example.com/docs\n')
        result, report = self.scan(0)
        self.assertEqual(report['metadata']['agent_version'], '7-84-1')
        self.assertEqual(report['metadata']['agent_version_source'], 'latest-release')
        self.assertEqual([endpoint['hostname'] for endpoint in report['endpoints']], [
            '7-84-1-app.agent.datadoghq.com', '7-84-1-flare.agent.datadoghq.com'])
        self.assertEqual([endpoint['classification'] for endpoint in report['endpoints']],
                         ['DIRECT TEST', 'DIRECT TEST'])
        self.assertEqual(report['allowlist_requirements'], ['*.agent.datadoghq.com'])
        self.assertNotIn('*.agent', result.stdout)
        self.assertEqual(report['direct_endpoint_counts'], {'pass': 2, 'warn': 0, 'fail': 0})
        self.assertNotIn('*.agent', (self.root / 'calls').read_text())

    def test_summary_lists_only_categories_needing_attention(self):
        self.manifest('manual|other_requirements|Configured target|configuration-dependent|123|udp|all|manual|informational|all|/|-|https://example.com/docs\n')
        result, report = self.scan(1)
        summary = result.stdout.split('SUMMARY', 1)[1]
        self.assertIn('READY WITH WARNINGS', summary)
        self.assertRegex(summary, r'1 pass.*0 warn.*0 fail.*1 review')
        self.assertIn('By category', summary)
        self.assertIn('other requirements: 0 pass, 0 warn, 0 fail, 1 review', summary)
        attention = summary.split('Needs attention', 1)[1].split('Manual review', 1)[0]
        self.assertIn('None', attention)
        self.assertNotIn('other requirements:', attention)
        self.assertIn('Manual review: 1 other requirement(s)', summary)
        self.assertEqual(report['categories'], {'agent': 'PASS', 'other_requirements': 'WARN'})

    def test_other_requirement_description_stays_under_manual_review(self):
        self.manifest('ntp|other_requirements|NTP targets from Agent configuration|configuration-dependent|123|udp|all|manual|informational|all|/|Review configured servers|https://example.com/docs\n')
        result, _ = self.scan(1)
        summary = result.stdout.split('SUMMARY', 1)[1]
        attention = summary.split('Needs attention', 1)[1].split('Manual review', 1)[0]
        self.assertNotIn('other requirements:', attention)
        self.assertIn('NTP targets from Agent configuration (UDP/123)', summary)

    def test_rum_warning_is_independent_of_wildcard_docs_note(self):
        self.manifest(
            'rum-direct|rum|Browser intake|browser-intake-datadoghq.com|443|https|all|server_sanity_only|informational|all|/|-|https://example.com/docs\n'
            'rum-wildcard|rum|Browser wildcard|*.browser-intake-datadoghq.com|443|https|all|wildcard|informational|all|/|ALLOWLIST REQUIREMENT|https://example.com/docs\n')
        self.write_command('curl', r'''
printf 'HTTP/1.1 403 Forbidden\r\n\r\nFortiGate: access denied'
printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.1\n0\n0\n'
''')
        result, _ = self.scan(1)
        summary = result.stdout.split('SUMMARY', 1)[1]
        attention = summary.split('Needs attention', 1)[1].split('Manual review', 1)[0]
        self.assertEqual(attention.count('rum:'), 1)
        self.assertIn('rum: 0 pass, 1 warn, 0 fail, 0 review', summary)
        self.assertIn('possible security-filter response(s)', attention)
        self.assertNotIn('Manual review', summary)

    def test_rum_remote_configuration_s3_denial_is_connectivity_pass(self):
        (self.root / 'config/endpoints.conf').write_text(
            '# last_verified_against_datadog_docs=2026-09-29\n'
            'rum-rc|rum|RUM Remote Configuration|sdk-configuration.{rum}|443|https|all|server_sanity_only|informational|all|/|-|https://example.com/docs\n')
        self.write_command('curl', r'''
printf 'HTTP/1.1 403 Forbidden\r\nServer: AmazonS3\r\nVia: 1.1 edge.cloudfront.net (CloudFront)\r\n\r\n'
printf '<Error><Code>AccessDenied</Code><Message>Access Denied</Message><RequestId>private-request-id</RequestId></Error>'
printf '\nDD_PREFLIGHT_META\n403\nhttps://sdk-configuration.browser-intake-datadoghq.com/\n192.0.2.1\n0\n0\n'
''')
        result, report = self.scan(0)
        endpoint = report['endpoints'][0]
        self.assertEqual(endpoint['http_result']['http_status'], '403')
        self.assertEqual(endpoint['http_result']['status'], 'PASS')
        self.assertEqual(endpoint['status'], 'PASS')
        self.assertEqual(endpoint['impact'], 'PASS')
        self.assertEqual(report['direct_endpoint_counts'], {'pass': 1, 'warn': 0, 'fail': 0})
        self.assertEqual(report['overall_status'], 'READY')
        self.assertIn('Generic denial wording observed', endpoint['notes'])
        self.assertNotIn('POSSIBLE SECURITY FILTERING', endpoint['notes'])
        self.assertRegex(result.stdout, r'PASS\s+sdk-configuration\.browser-intake-datadoghq\.com\s+ok\s+ok\s+ok\s+403')
        detailed = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('insufficient evidence of network filtering', detailed)
        self.assertNotIn('private-request-id', detailed + json.dumps(report) + result.stdout)

    def test_rum_terminal_explicitly_limits_browser_claim(self):
        self.manifest()
        (self.root / 'config/endpoints.conf').write_text(
            '# last_verified_against_datadog_docs=2026-09-29\n'
            'browser|rum|RUM intake|browser-intake-datadoghq.com|443|https|all|server_sanity_only|informational|all|/|Browser path differs|https://example.com/docs\n')
        result, report = self.scan(0)
        self.assertIn('RUM (VM-side only)', result.stdout)
        self.assertIn('end-user browser connectivity untested', result.stdout)
        self.assertEqual(report['endpoints'][0]['classification'], 'SERVER-SIDE SANITY CHECK ONLY')

    def test_malformed_no_network(self):
        self.manifest('broken|record\n')
        self.scan(3)
        self.assertFalse((self.root / 'calls').exists())

    def test_manifest_command_injection_rejected(self):
        self.manifest('evil|agent|Bad|$(touch hacked).example.com|443|https|all|full|required|all|/|-|https://example.com/docs\n')
        self.scan(3)
        self.assertFalse((self.root / 'hacked').exists())

    def test_invalid_port_scope_and_duplicate(self):
        for record in [
            'other|agent|Bad|example.com|65536|https|all|full|required|all|/|-|https://example.com/docs',
            'other|agent|Bad|example.com|443|https|all|full|required||/|-|https://example.com/docs',
            'other|agent|Bad|example.com|443|https|all|full|required|us1,|/|-|https://example.com/docs',
            'public|agent|Duplicate|example.com|443|https|all|full|required|all|/|-|https://example.com/docs',
            'other|agent|Bad|example.com|443|https|all|unknown|required|all|/|-|https://example.com/docs',
            'other|agent|Bad|{version}.example.com|443|https|all|full|required|all|/|-|https://example.com/docs',
        ]:
            with self.subTest(record=record):
                self.manifest(record + '\n')
                self.scan(3)
                self.assertFalse((self.root / 'calls').exists())

    def test_proxy_values_absent_from_reports(self):
        self.manifest()
        self.env['HTTPS_PROXY'] = 'http://private-user:secret-value@proxy.example:3128'
        self.env['NO_PROXY'] = 'private-internal.example'
        _, report = self.scan(0)
        content = json.dumps(report)
        for secret in ['private-user', 'secret-value', 'proxy.example', 'private-internal.example']:
            self.assertNotIn(secret, content)

    def test_blocked_http_transport(self):
        self.manifest()
        self.write_command('curl', 'exit 28')
        result, report = self.scan(2)
        self.assertEqual(report['overall_status'], 'BLOCKED')
        self.assertIn('HTTP: Connection or request timeout', result.stdout)
        self.assertIn('NOT READY', result.stdout)
        self.assertNotIn('\x1b', result.stdout)

    def test_oversize_http_sample_does_not_block_required_endpoint(self):
        self.manifest()
        self.write_command('curl', r'''
{ printf 'HTTP/1.1 200 OK\r\nServer: fixture\r\n\r\n'; head -c 180000 /dev/zero | tr '\000' x; } >&4 2>/dev/null
printf '\nDD_PREFLIGHT_META\n200\nhttps://example.com/\n192.0.2.1\n0\n0\n180000\n40\n'
exit 23
''')
        _, report = self.scan(0)
        self.assertEqual(report['overall_status'], 'READY')
        self.assertEqual(report['blockers'], [])
        http = report['endpoints'][0]['http_result']
        self.assertEqual(http['status'], 'PASS')
        self.assertEqual(http['curl_exit'], '23')
        self.assertEqual(http['http_status'], '200')

    def test_informational_failure_warning(self):
        self.manifest(required=False)
        self.write_command('curl', 'exit 60')
        _, report = self.scan(1)
        self.assertEqual(report['endpoints'][0]['status'], 'FAIL')
        self.assertEqual(report['endpoints'][0]['impact'], 'WARN')


if __name__ == '__main__':
    unittest.main()
