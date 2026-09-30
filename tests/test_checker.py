"""Offline behavior tests. Python is a development dependency only.

All test artifacts live beneath reports/. No customer endpoints are contacted.
"""
import json
import os
from pathlib import Path
import pty
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
            '[[ ${#SITE_CODES[@]} == 9 && ${#RECORDS[@]} == 59 ]] || exit 1; '
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
        self.assertEqual(piped.stdout, 'DATADOG NETWORK PREFLIGHT  v0.1.3\n')
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
        self.assertIn('HTTP: redirected to https://example.com/[path omitted]', output)

    def test_terminal_long_and_narrow_rows_keep_full_hostname(self):
        hostname = 'instrumentation-telemetry-intake.datadoghq.com'
        code = ("category=instrumentation; LAST_TERMINAL_CATEGORY=''; "
                f"E[hostname]={hostname}; E[dns]=PASS; E[tcp]=PASS; "
                "E[tls]=SKIPPED; E[http]=PASS; E[http_status]=403; terminal_endpoint")
        wide = self.run_code(code)
        self.assertIn('instrumentation-telemetry-intake.datadogh', wide)
        self.assertNotIn(hostname, wide)
        self.assertIn('ok   ok   -- 403', wide)
        narrow = self.run_code('COLUMNS=60; ' + code)
        self.assertIn(hostname, narrow)
        self.assertNotIn('STATUS DESTINATION', narrow)
        self.assertIn('DNS ok  TCP ok  TLS --  HTTP 403', narrow)

    def test_terminal_review_is_explicitly_untested(self):
        output = self.run_code("category=agent; LAST_TERMINAL_CATEGORY=''; "
            "E[hostname]='*.agent.datadoghq.com'; E[classification]='ALLOWLIST REQUIREMENT'; "
            "terminal_endpoint")
        self.assertIn('REVIEW', output)
        self.assertIn('wildcard allowlist (not tested)', output)
        self.assertNotIn('DNS ok', output)
        self.assertLessEqual(max(map(len, output.splitlines())), 80)

    def test_terminal_category_header_uses_endpoint_counts(self):
        output = self.run_code("declare -A TERMINAL_COUNTS=([agent:PASS]=2 [agent:REVIEW]=3); "
            "terminal_section agent")
        self.assertIn('AGENT', output)
        self.assertRegex(output, r'2\s+[^\s]+\s+3\s+[^\s]+')
        self.assertLessEqual(max(map(len, output.splitlines())), 80)

    def test_terminal_wraps_long_diagnostic_at_80_columns(self):
        output = self.run_code("terminal_wrap 'HTTP: redirected to "
            "https://accounts.google.com/[path omitted]; review destination allowlist' "
            "'       ' '             '")
        self.assertLessEqual(max(map(len, output.splitlines())), 80)
        self.assertIn('https://accounts.google.com/[path omitted];', output)
        self.assertIn('review destination allowlist', output)

    def test_terminal_groups_matching_redirect_warnings(self):
        output = self.run_code(r'''
declare -A TERMINAL_SNAP=() TERMINAL_COUNTS=() TERMINAL_GROUP_COUNTS=()
declare -a TERMINAL_ORDER=() TERMINAL_NOTE_KEY=()
category=container_registries
for host in gcr.io eu.gcr.io; do
    reset_result
    E[hostname]=$host; E[impact]=WARN
    E[dns]=PASS; E[tcp]=PASS; E[tls]=PASS; E[http]=WARN; E[http_status]=302
    E[redirect_http]=PASS; E[redirect_http_detail]='Reached redirect'
    E[redirect_http_status]=200
    E[redirect_final_url]='https://accounts.google.com/[path omitted]'
    terminal_capture_endpoint
done
terminal_render_report
''')
        self.assertIn('gcr.io', output)
        self.assertIn('eu.gcr.io', output)
        self.assertEqual(output.count('2 redirects; check HTTPS targets'), 1)
        self.assertNotIn('redirected to https://accounts.google.com', output)

    def test_terminal_progress_is_silent_when_piped(self):
        output = self.run_code('TERMINAL_TTY=0; TERMINAL_PROGRESS_DONE=1; '
            'TERMINAL_PROGRESS_TOTAL=3; terminal_progress; terminal_progress_clear')
        self.assertEqual(output, '')

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

    def test_agent_version_derivation(self):
        for version, expected in [('7.75.0', '7-75-0'), ('7.75.0-rc.1', '')]:
            output = self.run_code('have() { return 0; }; timeout() { echo "Agent ' + version +
                ' - Commit: example"; }; detect_agent_version; echo "$AGENT_VERSION"')
            self.assertEqual(output, expected)

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
        output = self.http(status='200', body='HTTP/1.1 200 OK\r\n\r\nFortiGate: category blocked')
        self.assertIn('POSSIBLE SECURITY FILTERING', output)
        self.assertTrue(output.startswith('WARN\nPASS'))

    def test_weak_denial_not_definitive(self):
        output = self.http(body='HTTP/1.1 403 Forbidden\r\n\r\nAccess denied')
        self.assertIn('filtering not established', output)
        self.assertNotIn('POSSIBLE SECURITY FILTERING', output)

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
        self.assertEqual(len(report['endpoints']), 1 if 'wildcard' not in txt else 2)
        self.assertEqual(report['metadata']['hostname'], os.uname().nodename)
        return result, report

    def test_interactive_report_ready(self):
        self.manifest()
        result, report = self.scan(0, interactive=True)
        self.assertIn('9) US2-FED', result.stdout)
        self.assertIn('DATADOG NETWORK PREFLIGHT  v0.1.3', result.stdout)
        self.assertEqual(result.stdout.count('DATADOG NETWORK PREFLIGHT  v0.1.3'), 1)
        self.assertIn('[ SELECT DATADOG SITE ]', result.stdout)
        self.assertRegex(result.stdout, r'1 pass.*0 warn.*0 fail.*0 review')
        self.assertRegex(result.stdout, r'PASS\s+example\.com\s+ok\s+ok\s+ok\s+403')
        self.assertNotIn('TLS probe', result.stdout)
        self.assertNotIn('CNAME chain', result.stdout)
        self.assertNotIn('\x1b', result.stdout)
        self.assertIn('TXT  ' + str(self.root / 'reports'), result.stdout)
        self.assertIn('JSON ' + str(self.root / 'reports'), result.stdout)
        detailed = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('TLS probe', detailed)
        self.assertIn('DNS               PASS', detailed)
        self.assertEqual(report['overall_status'], 'READY')
        self.assertEqual(report['endpoints'][0]['http_result']['http_status'], '403')
        calls = (self.root / 'calls').read_text()
        self.assertIn('--disable --silent', calls)
        self.assertIn('--proto =https --proto-redir =https', calls)
        self.assertNotIn('--insecure', calls)

    def test_wildcard_never_probed(self):
        self.manifest('wildcard|agent|Agent wildcard|*.agent.{site}|443|https|all|wildcard|required|all|/|ALLOWLIST REQUIREMENT|https://example.com/docs\n')
        _, report = self.scan(1)
        self.assertEqual(report['overall_status'], 'READY WITH WARNINGS')
        self.assertNotIn('*.agent', (self.root / 'calls').read_text())
        self.assertEqual(report['allowlist_requirements'], ['*.agent.datadoghq.com'])

    def test_summary_lists_only_categories_needing_attention(self):
        self.manifest('wildcard|rum|Browser wildcard|*.browser-intake-datadoghq.com|443|https|all|wildcard|informational|all|/|ALLOWLIST REQUIREMENT|https://example.com/docs\n')
        result, report = self.scan(1)
        summary = result.stdout.split('SUMMARY', 1)[1]
        self.assertIn('READY WITH WARNINGS', summary)
        self.assertRegex(summary, r'1 pass.*0 warn.*0 fail.*1 review')
        self.assertIn('rum: 1 untested requirement', summary)
        self.assertNotIn('agent:', summary)
        self.assertIn('Manual review: 1 wildcard allowlist', summary)
        self.assertEqual(report['categories'], {'agent': 'PASS', 'rum': 'WARN'})

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
