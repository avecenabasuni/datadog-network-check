"""Regressions for intermittent transport and origin/redirect attribution."""
import unittest

import test_checker


class DiagnosticTests(unittest.TestCase):
    run_code = test_checker.UnitTests.run_code

    def test_tls_timeout_after_negotiation_is_warning(self):
        output = self.run_code(r'''
E[tcp_ip]=192.0.2.1
openssl() { echo '-verify_hostname'; }
tls_probe() {
 echo 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384'
 echo 'Verify return code: 0 (ok)'
 return 124
}
tls_check example.com
echo "${E[tls]} ${E[tls_exit]} ${E[tls_detail]}"
echo "${E[tls_attempts]}"
''')
        self.assertTrue(output.startswith('WARN 124 Verified TLS session negotiated'), output)
        self.assertNotIn('attempt 2', output)

    def test_verification_alone_does_not_prove_completed_handshake(self):
        for cipher in ['', 'New, TLSv1.3, Cipher is (NONE)', 'New, TLSv1.3, Cipher is 0000']:
            output = self.run_code(r'''
E[tcp_ip]=192.0.2.1
openssl() { echo '-verify_hostname'; }
tls_probe() { echo 'Verify return code: 0 (ok)'; echo 'CIPHER'; return 124; }
tls_check example.com; echo "${E[tls]}"; echo "${E[tls_attempts]}"
'''.replace('CIPHER', cipher))
            self.assertTrue(output.startswith('FAIL\n'), output)
            self.assertIn('attempt 2', output)
            self.assertNotIn('attempt 3', output)

    def test_tls_certificate_error_not_downgraded_or_retried(self):
        output = self.run_code(r'''
E[tcp_ip]=192.0.2.1
openssl() { echo '-verify_hostname'; }
tls_probe() {
 echo 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384'
 echo 'Verify return code: 0 (ok)'
 echo 'verify error:num=62:hostname mismatch'
 return 124
}
tls_check example.com; echo "${E[tls]}"; echo "${E[tls_attempts]}"
''')
        self.assertTrue(output.startswith('FAIL\n'), output)
        self.assertNotIn('attempt 2', output)

    def test_tls_retry_uses_other_tcp_success_and_preserves_failure(self):
        output = self.run_code(r'''
E[tcp_ip]=192.0.2.1; E[tcp_attempts]=$'192.0.2.1 PASS\n192.0.2.2 FAIL - timeout\n192.0.2.3 PASS\n'
openssl() { echo '-verify_hostname'; }
tls_probe() { [[ $2 != 192.0.2.1 ]] || return 124; echo 'Verify return code: 0 (ok)'; }
tls_check example.com; echo "${E[tls]} ${E[tls_ip]} ${E[tls_exit]}"; echo "${E[tls_attempts]}"
''')
        self.assertTrue(output.startswith('WARN 192.0.2.3 0'), output)
        self.assertIn('attempt 1: IP=192.0.2.1, FAIL', output)
        self.assertIn('attempt 2: IP=192.0.2.3, PASS', output)
        self.assertNotIn('IP=192.0.2.2', output)

    def test_tls_probe_no_key_logging_and_explicit_eof(self):
        output = self.run_code(r'''
SSLKEYLOGFILE=/must-not-write; export SSLKEYLOGFILE
timeout() { [[ -z ${SSLKEYLOGFILE-} && " $* " == *' -no_ign_eof '* ]] || return 1; echo SAFE; }
tls_probe example.com 192.0.2.1
[[ $SSLKEYLOGFILE == /must-not-write ]] || exit 1
''')
        self.assertEqual(output, 'SAFE')

    def test_http_recovers_once_without_hiding_first_failure(self):
        output = self.run_code(r'''
curl_probe() {
 if ((attempt==1)); then
  printf '\nDD_PREFLIGHT_META\n000\nhttps://example.com/\n192.0.2.1\n0\n0\n0.010000\n0.200000\n0.000000\n0.000000\n5.000000\n'
  return 28
 fi
 printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.2\n0\n0\n0.010000\n0.200000\n0.500000\n0.700000\n0.800000\n'
}
http_check example.com; echo "${E[http]} ${E[curl_tls]} ${E[remote_ip]}"
echo "${E[http_attempts]}"; echo "${E[notes]}"
''')
        self.assertTrue(output.startswith('WARN PASS 192.0.2.2'), output)
        self.assertIn('origin attempt 1: FAIL', output)
        self.assertIn('origin attempt 2: PASS', output)
        self.assertIn('before TLS completed', output)
        self.assertIn('recovered on retry', output)

    def test_http_persistent_timeout_remains_failure_with_two_attempts(self):
        output = self.run_code('curl_probe() { return 28; }; http_check example.com; '
                               'classify_result; echo "${E[http]} ${E[impact]}"; echo "${E[http_attempts]}"')
        self.assertTrue(output.startswith('FAIL FAIL'), output)
        self.assertEqual(output.count('origin attempt '), 2)

    def test_http_certificate_error_never_retried(self):
        output = self.run_code('curl_probe() { return 60; }; http_check example.com; '
                               'echo "${E[http]} ${E[curl_tls]}"; echo "${E[http_attempts]}"')
        self.assertTrue(output.startswith('FAIL FAIL'), output)
        self.assertEqual(output.count('origin attempt '), 1)

    def test_http_timeout_phase_diagnostics(self):
        for timings, expected in [
            ('0.000000\\n0.000000\\n0.000000', 'before TCP connection'),
            ('0.200000\\n0.000000\\n0.000000', 'before TLS completed'),
            ('0.200000\\n0.500000\\n0.000000', 'waiting for HTTP response'),
            ('0.200000\\n0.500000\\n0.700000', 'after response started'),
        ]:
            output = self.run_code(r'''
curl_probe() { printf '\nDD_PREFLIGHT_META\n000\nhttps://example.com/\n192.0.2.1\n0\n0\n0.010000\nTIMINGS\n12.000000\n'; return 28; }
http_check example.com; echo "${E[http]} ${E[http_detail]}"
'''.replace('TIMINGS', timings))
            self.assertTrue(output.startswith('FAIL '), output)
            self.assertIn(expected, output)

    def test_http_stall_preserves_proven_tls_without_clearing_http_failure(self):
        output = self.run_code(r'''
curl_probe() { printf '\nDD_PREFLIGHT_META\n000\nhttps://example.com/\n192.0.2.1\n0\n0\n0.010000\n0.200000\n0.500000\n0.000000\n12.000000\n'; return 28; }
http_check example.com; echo "${E[http]} ${E[curl_tls]}"
''')
        self.assertEqual(output, 'FAIL PASS')

    def test_probe_follows_only_in_separate_diagnostic(self):
        output = self.run_code(r'''
curl() { printf '%s\n' "$*"; }
curl_probe https://example.com origin
curl_probe https://example.com follow
''')
        calls = [line for line in output.splitlines() if line.startswith('--disable ')]
        self.assertEqual(len(calls), 2)
        self.assertNotIn('--location', calls[0])
        self.assertIn('--location --max-redirs 3', calls[1])
        self.assertIn('--proto =https --proto-redir =https', calls[1])


class DiagnosticReportTests(unittest.TestCase):
    setUp = test_checker.IntegrationTests.setUp
    write_command = test_checker.IntegrationTests.write_command
    manifest = test_checker.IntegrationTests.manifest
    scan = test_checker.IntegrationTests.scan

    def redirect_fixture(self, follow):
        self.manifest()
        self.write_command('curl', r'''
printf '%s\n' "$*" >> "$MOCK_LOG"
if [[ " $* " == *' --location '* ]]; then
''' + follow + r'''
else
 printf '\nDD_PREFLIGHT_META\n307\nhttps://example.com/\n192.0.2.1\n0\n0\n0.010000\n0.240000\n0.540000\n0.700000\n0.710000\n'
fi
''')

    def test_reachable_307_and_failed_redirect_do_not_block_origin(self):
        self.redirect_fixture(r'''
printf '\nDD_PREFLIGHT_META\n000\nhttps://other.example/private?secret=withheld\n192.0.2.2\n1\n0\n0.010000\n0.000000\n0.000000\n0.000000\n5.000000\n'
exit 28
''')
        result, report = self.scan(1)
        http = report['endpoints'][0]['http_result']
        self.assertEqual(report['blockers'], [])
        self.assertEqual(http['http_status'], '307')
        self.assertEqual(http['remote_ip'], '192.0.2.1')
        self.assertEqual(http['time_appconnect'], '0.540000')
        self.assertEqual(http['redirect_result']['status'], 'FAIL')
        self.assertEqual(http['redirect_result']['remote_ip'], '192.0.2.2')
        self.assertEqual(http['redirect_result']['curl_exit'], '28')
        self.assertNotIn('secret=withheld', result.stdout)
        self.assertIn('Redirect follow   FAIL', result.stdout)
        self.assertEqual((self.root / 'calls').read_text().count('--disable --silent'), 2)

    def test_redirect_certificate_failure_remains_visible(self):
        self.redirect_fixture('exit 60')
        _, report = self.scan(1)
        redirect = report['endpoints'][0]['http_result']['redirect_result']
        self.assertEqual(redirect['status'], 'FAIL')
        self.assertEqual(redirect['curl_tls'], 'FAIL')

    def test_successful_redirect_preserves_both_responses(self):
        self.redirect_fixture(r'''
printf '\nDD_PREFLIGHT_META\n200\nhttps://other.example/\n192.0.2.2\n1\n0\n0.010000\n0.240000\n0.540000\n0.700000\n0.710000\n'
''')
        _, report = self.scan(1)
        http = report['endpoints'][0]['http_result']
        self.assertEqual(http['http_status'], '307')
        self.assertEqual(http['redirect_result']['http_status'], '200')
        self.assertEqual(http['redirect_result']['redirect_count'], '1')

    def test_post_negotiation_tls_timeout_and_307_are_warning_in_report(self):
        self.redirect_fixture('exit 28')
        self.write_command('timeout', r'''
shift 2; shift
case $1 in
 getent) shift; getent "$@";;
 bash) exit 0;;
 openssl) printf 'New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384\nVerify return code: 0 (ok)\n'; exit 124;;
 *) exit 1;;
esac
''')
        _, report = self.scan(1)
        tls = report['endpoints'][0]['tls_result']
        self.assertEqual(tls['status'], 'WARN')
        self.assertEqual(tls['openssl_exit'], '124')
        self.assertEqual(len(tls['attempts']), 1)
        self.assertEqual(report['overall_status'], 'READY WITH WARNINGS')

    def test_persistent_failure_summary_includes_reason(self):
        self.manifest()
        self.write_command('curl', 'exit 28')
        _, report = self.scan(2)
        self.assertIn('Connection or request timeout', report['blockers'][0])
        self.assertEqual(len(report['endpoints'][0]['http_result']['attempts']), 2)


if __name__ == '__main__':
    unittest.main()
