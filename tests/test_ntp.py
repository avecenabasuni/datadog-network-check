"""NTP packet validation and loopback UDP tests; no public servers contacted."""
import json
import socket
import threading
import unittest

import test_checker

REPLY = r'''
fake_reply() {
    local i
    local -a bytes=()
    for ((i=0;i<48;i++)); do bytes+=(0); done
    bytes[0]=28; bytes[1]=2
    for ((i=0;i<8;i++)); do bytes[i+24]=${NTP_NONCE[i]}; done
    bytes[32]=1; bytes[40]=1
    MODIFY
    printf '%s ' "${bytes[@]}"
}
'''


class NTPTests(unittest.TestCase):
    run_code = test_checker.UnitTests.run_code

    def validate(self, modify='', raw=None):
        code = 'NTP_NONCE=(1 2 3 4 5 6 7 8); '
        code += REPLY.replace('MODIFY', modify)
        code += f'ntp_validate_response {raw}; ' if raw else 'ntp_validate_response "$(fake_reply)"; '
        code += 'printf "%s\\n%s\\n%s" "$NTP_REPLY_STATUS" "$NTP_REPLY_DETAIL" "${E[ntp_kiss_code]}"'
        return self.run_code(code)

    def test_valid_ntpv3_and_ntpv4_replies(self):
        for header in [28, 36]:
            output = self.validate(f'bytes[0]={header}')
            self.assertTrue(output.startswith('PASS\nValid matched NTPv'), output)

    def test_bad_header_origin_stratum_and_timestamp_fail(self):
        for modify in ['bytes[0]=27', 'bytes[0]=20', 'bytes[24]=99', 'bytes[1]=17', 'bytes[40]=0']:
            with self.subTest(modify=modify):
                self.assertTrue(self.validate(modify).startswith('FAIL\n'))

    def test_malformed_truncated_and_untrusted_input_fail(self):
        for raw in ["''", "'28 2 0'", "'999'", "'x[$(touch should-not-exist)]'", "'01 08 xyz'"]:
            self.assertTrue(self.validate(raw=raw).startswith('FAIL\n'))

    def test_unsynchronized_reply_warns(self):
        for modify in ['bytes[0]=220', 'bytes[1]=16', 'bytes[0]=220; bytes[1]=16; bytes[40]=0']:
            self.assertIn('WARN\nNTP server replied but reports an unsynchronized clock', self.validate(modify))

    def test_kiss_of_death_warns_and_reports_code(self):
        output = self.validate('bytes[1]=0; bytes[12]=82; bytes[13]=65; bytes[14]=84; bytes[15]=69')
        self.assertIn("WARN\nNTP server replied with Kiss-o'-Death (RATE)", output)
        self.assertTrue(output.endswith('RATE'), output)

    def test_request_is_48_bytes_with_ntpv3_client_header(self):
        output = self.run_code('ntp_prepare_request; printf "%b" "$NTP_PACKET" | od -An -v -tu1')
        data = [int(x) for x in output.split()]
        self.assertEqual(len(data), 48)
        self.assertEqual(data[0], 27)
        self.assertEqual(data[1:40], [0] * 39)
        self.assertTrue(any(data[40:]))

    def probe(self, body, ips='192.0.2.1'):
        code = REPLY.replace('MODIFY', '')
        code += 'E[test_type]=ntp; port=123; ntp_resolve 192.0.2.1; '
        code += f"E[ips]=$'{ips}'; "
        code += 'ntp_probe() { ' + body + '; }; ntp_check; classify_result; '
        code += 'printf "%s\\n%s\\n%s\\n%s" "${E[ntp]}" "${E[impact]}" "${E[ntp_attempts]}" "${E[notes]}"'
        return self.run_code(code)

    def test_socket_success_without_reply_never_passes(self):
        self.assertTrue(self.probe('return 0').startswith('FAIL\nFAIL\n'))

    def test_timeout_and_dns_failure_keep_distinct_reasons(self):
        output = self.probe('return 124')
        self.assertTrue(output.startswith('FAIL\nFAIL\n'))
        self.assertIn('No NTP response within 5s; filtering is not established', output)
        output = self.run_code('E[test_type]=ntp; E[ntp]=SKIPPED; E[dns]=FAIL; '
                               'ntp_probe() { echo SHOULD_NOT_RUN; }; ntp_check; classify_result; '
                               'echo "${E[ntp]} ${E[impact]} ${E[ntp_detail]}"')
        self.assertIn('FAIL FAIL No resolved NTP address', output)
        self.assertNotIn('SHOULD_NOT_RUN', output)

    def test_missing_dependency_is_skipped_warning(self):
        for dep in ['timeout', 'dd', 'od']:
            output = self.run_code(f'have() {{ [[ $1 != {dep} ]]; }}; E[test_type]=ntp; '
                                   'ntp_resolve 192.0.2.1; ntp_check; classify_result; '
                                   'echo "${E[ntp]} ${E[impact]} ${E[ntp_detail]}"')
            self.assertEqual(output, f'SKIPPED WARN {dep} unavailable; no NTP probe issued')

    def test_success_stops_and_failed_address_recovery_warns(self):
        output = self.probe('fake_reply', '192.0.2.1\\n192.0.2.2')
        self.assertTrue(output.startswith('PASS\nPASS\n'))
        self.assertNotIn('192.0.2.2 PASS', output)
        output = self.probe('[[ $1 != 192.0.2.1 ]] || return 124; fake_reply', '192.0.2.1\\n192.0.2.2')
        self.assertTrue(output.startswith('WARN\nWARN\n'))
        self.assertIn('earlier failed address', output)

    def test_ipv6_unreachable_with_working_ipv4_passes(self):
        output = self.probe('if [[ $1 == *:* ]]; then echo "Network is unreachable"; return 10; fi; fake_reply',
                            '2001:db8::1\\n192.0.2.1')
        self.assertTrue(output.startswith('PASS\nPASS\n'), output)
        self.assertIn('IPv6 network unreachable', output)

    def test_address_limit_and_no_retry_after_kiss_of_death(self):
        output = self.probe('return 124', '192.0.2.1\\n192.0.2.2\\n192.0.2.3')
        self.assertNotIn('192.0.2.3 FAIL', output)
        code = REPLY.replace('MODIFY', 'bytes[1]=0; bytes[12]=82; bytes[13]=65; bytes[14]=84; bytes[15]=69')
        code += "E[test_type]=ntp; port=123; ntp_resolve 192.0.2.1; E[ips]=$'192.0.2.1\\n192.0.2.2'; "
        code += 'ntp_probe() { fake_reply; }; ntp_check; echo "${E[ntp]} ${E[ntp_attempts]}"'
        output = self.run_code(code)
        self.assertTrue(output.startswith('WARN '))
        self.assertNotIn('192.0.2.2 WARN', output)

    def test_public_failure_does_not_block_but_explicit_failure_does(self):
        output = self.run_code('E[test_type]=ntp; E[dns]=PASS; E[ntp]=FAIL; '
            'requirement=informational; classify_result; echo "${E[status]} ${E[impact]}"; '
            'requirement=required; PROXY_PRESENT=1; E[http]=PASS; E[curl_tls]=PASS; '
            'classify_result; echo "${E[status]} ${E[impact]}"')
        self.assertEqual(output, 'FAIL WARN\nFAIL FAIL')

    def test_customer_targets_replace_public_pools_and_deduplicate(self):
        output = self.run_code('load_sites; validate_manifest; NTP_HOSTS=(); '
            'add_ntp_host ntp.internal; add_ntp_host 192.0.2.9; add_ntp_host 2001:db8::9; '
            'add_ntp_host ntp.internal; select_ntp_targets; '
            'echo "$NTP_TARGET_SOURCE"; for line in "${RECORDS[@]}"; do '
            'parse_record "$line"; [[ $test_type != ntp ]] || echo "$template $requirement"; done')
        self.assertEqual(output.splitlines(), ['explicit-customer-targets',
            'ntp.internal required', '192.0.2.9 required', '2001:db8::9 required'])

    def test_ntp_terminal_rows_fit_wide_and_narrow_widths(self):
        for width in [80, 50]:
            output = self.run_code(f'COLUMNS={width}; category=ntp; NTP_TARGET_SOURCE=documented-public-fallback; '
                'E[test_type]=ntp; E[port]=123; E[hostname]=0.datadog.pool.ntp.org; E[dns]=PASS; '
                'E[ntp]=PASS; E[impact]=PASS; '
                "E[ntp_detail]='Valid matched NTPv3 server reply; stratum 2; direct UDP/123'; terminal_endpoint")
            self.assertRegex(output, r'PASS\s+0\.datadog\.pool\.ntp\.org')
            self.assertNotIn('NTP UDP/123:', output)
            self.assertNotIn('Valid matched', output)
            self.assertLessEqual(max(map(len, output.splitlines())), width)

    def test_invalid_customer_targets_and_limit_are_rejected(self):
        output = self.run_code('NTP_HOSTS=(); for host in "bad;host" "https://ntp.example.com" '
            '"ntp.example.com:123" "[::1]" "-host" ":::" "1:2:3" "1::2::3" "12345::1"; do add_ntp_host "$host" >/dev/null 2>&1 && exit 1; done; '
            'for i in {1..8}; do add_ntp_host "ntp$i.internal" || exit 1; done; '
            'add_ntp_host ninth.internal >/dev/null 2>&1 && exit 1; echo OK')
        self.assertEqual(output, 'OK')

    def test_real_loopback_datagram_and_response_validation(self):
        for family, host in [(socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')]:
            with self.subTest(host=host), socket.socket(family, socket.SOCK_DGRAM) as server:
                server.bind((host, 0))
                server.settimeout(3)
                received = []
                errors = []

                def respond():
                    try:
                        packet, peer = server.recvfrom(512)
                        received.append(packet)
                        reply = bytearray(48)
                        reply[0:2] = bytes([28, 2])
                        reply[24:32] = packet[40:48]
                        reply[32] = reply[40] = 1
                        server.sendto(reply, peer)
                    except Exception as exc:
                        errors.append(exc)

                thread = threading.Thread(target=respond)
                thread.start()
                result = test_checker.bash(test_checker.SOURCE +
                    f'port={server.getsockname()[1]}; E[test_type]=ntp; E[protocol]=udp; '
                    f'ntp_resolve {host}; ntp_check; classify_result; endpoint_json')
                thread.join(4)
                self.assertFalse(errors, errors)
                self.assertFalse(thread.is_alive())
                self.assertEqual(result.returncode, 0, result.stderr)
                report = json.loads(result.stdout)
                self.assertEqual(report['ntp_result']['status'], 'PASS')
                self.assertEqual(report['ntp_result']['ip'], host)
                self.assertEqual(report['ntp_result']['stratum'], '2')
                self.assertEqual(report['status'], 'PASS')
                self.assertEqual(report['tcp_result']['status'], 'NOT APPLICABLE')
                self.assertEqual(report['tls_result']['status'], 'NOT APPLICABLE')
                self.assertEqual(report['http_result']['status'], 'NOT APPLICABLE')
                self.assertEqual(len(received[0]), 48)
                self.assertEqual(received[0][0], 27)

    def test_real_loopback_silent_server_times_out(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as server:
            server.bind(('127.0.0.1', 0))
            result = test_checker.bash(test_checker.SOURCE +
                f'port={server.getsockname()[1]}; NTP_TIMEOUT=1; E[test_type]=ntp; '
                'ntp_resolve 127.0.0.1; ntp_check; classify_result; '
                'echo "${E[ntp]} ${E[impact]} ${E[ntp_detail]}"')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('FAIL FAIL No NTP response within 1s', result.stdout)


class NTPIntegrationTests(unittest.TestCase):
    setUp = test_checker.IntegrationTests.setUp
    write_command = test_checker.IntegrationTests.write_command
    manifest = test_checker.IntegrationTests.manifest
    scan = test_checker.IntegrationTests.scan

    def ntp_manifest(self, requirement='informational'):
        self.manifest(f'ntp0|ntp|NTP public fallback|0.datadog.pool.ntp.org|123|udp|all|ntp|{requirement}|all|/|-|https://docs.datadoghq.com/integrations/ntp/\n')

    def test_default_ntp_timeout_is_reported_without_http_probe(self):
        self.ntp_manifest()
        result, report = self.scan(1)
        endpoint = report['endpoints'][1]
        self.assertEqual(endpoint['ntp_result']['status'], 'FAIL')
        self.assertEqual(endpoint['impact'], 'WARN')
        self.assertEqual(endpoint['ntp_result']['target_source'], 'documented-public-fallback')
        self.assertEqual(endpoint['tcp_result']['status'], 'NOT APPLICABLE')
        self.assertEqual(report['untested_requirements'], [])
        self.assertEqual(report['metadata']['ntp_target_source'], 'documented-public-fallback')
        self.assertIn('NTP UDP/123: FAIL', result.stdout)
        self.assertIn('use --ntp-host', result.stdout)
        self.assertNotIn('0.datadog.pool.ntp.org', (self.root / 'calls').read_text())
        txt = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('NTP UDP/123     FAIL', txt)
        self.assertIn('NTP probe', txt)

    def test_custom_ip_target_replaces_public_and_blocks_on_failure(self):
        self.ntp_manifest()
        result = test_checker.bash('./dd-network-check.sh --site us1 --ntp-host 192.0.2.99', self.env, self.root)
        self.assertEqual(result.returncode, 2, result.stderr)
        report = json.loads(next((self.root / 'reports').glob('*.json')).read_text())
        self.assertEqual(report['metadata']['ntp_target_source'], 'explicit-customer-targets')
        self.assertEqual(report['endpoints'][1]['hostname'], '192.0.2.99')
        self.assertEqual(report['endpoints'][1]['requirement'], 'required')
        self.assertEqual(report['endpoints'][1]['ntp_result']['status'], 'FAIL')
        self.assertTrue(any('NTP:' in blocker for blocker in report['blockers']))
        self.assertNotIn('datadog.pool.ntp.org', result.stdout)

    def test_valid_ntp_passes_terminal_txt_json_and_readiness(self):
        self.ntp_manifest()
        self.write_command('timeout', r'''
shift 2; shift
case $1 in
 getent) shift; getent "$@";;
 openssl) echo 'Verify return code: 0 (ok)';;
 bash)
   if [[ ${*: -2:1} == 123 ]]; then
     read -r -a request <<< "$(printf '%b' "${!#}" | od -An -v -tu1 | tr '\n' ' ')"
     reply=(); for i in {0..47}; do reply+=(0); done
     reply[0]=28; reply[1]=2; reply[32]=1; reply[40]=1
     for i in {0..7}; do reply[i+24]=${request[i+40]}; done
     printf '%s ' "${reply[@]}"
   fi;;
 *) exit 1;;
esac
''')
        result, report = self.scan(0)
        self.assertEqual(report['overall_status'], 'READY')
        self.assertEqual(report['direct_endpoint_counts'], {'pass': 2, 'warn': 0, 'fail': 0})
        self.assertEqual(report['endpoints'][1]['ntp_result']['status'], 'PASS')
        self.assertEqual(report['endpoints'][1]['ntp_result']['stratum'], '2')
        self.assertEqual(report['endpoints'][1]['http_result']['status'], 'NOT APPLICABLE')
        self.assertEqual(report['schema_version'], '1.4')
        self.assertRegex(result.stdout, r'PASS\s+0\.datadog\.pool\.ntp\.org')
        self.assertNotIn('NTP UDP/123: PASS', result.stdout)
        txt = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('NTP UDP/123     PASS', txt)
        self.assertIn('stratum=2', txt)

    def test_active_udp_requires_ntp_type_and_port_123(self):
        for kind, port in [('full', 123), ('ntp', 443)]:
            self.manifest(f'ntp|ntp|Bad NTP|ntp.example.com|{port}|udp|all|{kind}|required|all|/|-|https://example.com/docs\n')
            self.scan(3)

    def test_ntp_cli_rejects_invalid_target_before_network(self):
        result = test_checker.bash("./dd-network-check.sh --site us1 --ntp-host 'bad;host'", self.env, self.root)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(list((self.root / 'reports').iterdir()), [])
        self.assertFalse((self.root / 'calls').exists())
