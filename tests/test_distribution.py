"""Exercise the published command and standalone bundle without network calls."""
import json
import re
import subprocess
import unittest

import test_checker

ROOT = test_checker.ROOT
COMMAND = next(line for line in (ROOT / 'README.md').read_text().splitlines()
               if line.startswith("bash -c 's=$(SSLKEYLOGFILE= curl "))
DOWNLOAD_URL = re.search(r'https://raw\.githubusercontent\.com/[^\s)\"]+', COMMAND).group(0)


class DistributionTests(unittest.TestCase):
    setUp = test_checker.IntegrationTests.setUp
    write_command = test_checker.IntegrationTests.write_command

    def command(self, suffix='', stdin=None):
        self.invocation = self.root / 'empty invocation directory'
        self.invocation.mkdir(exist_ok=True)
        return test_checker.bash(COMMAND + suffix, self.env, self.invocation, stdin)

    def test_bundle_is_fresh_and_syntax_valid(self):
        result = subprocess.run(['python3', '-B', 'scripts/build_standalone.py', '--check'],
                                cwd=ROOT, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess((ROOT / 'dist/dd-network-check.sh').stat().st_size, 100000)
        result = subprocess.run(['bash', '-n', 'dist/dd-network-check.sh'], cwd=ROOT,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_download_error_never_executes_partial_payload(self):
        self.write_command('curl', "printf 'echo PAYLOAD_EXECUTED; mkdir unwanted\\n'; exit 18")
        result = self.command()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertNotIn('PAYLOAD_EXECUTED', result.stdout)
        self.assertEqual(list(self.invocation.iterdir()), [])

    def test_empty_download_exits_three(self):
        self.write_command('curl', 'exit 0')
        result = self.command()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(list(self.invocation.iterdir()), [])

    def test_exit_codes_preserved(self):
        for code in [0, 1, 2, 3]:
            with self.subTest(code=code):
                self.write_command('curl', f"printf 'exit {code}\\n'")
                result = self.command()
                self.assertEqual(result.returncode, code, result.stderr)

    def test_downloader_flags_and_input_and_argument_forwarding(self):
        self.env['SSLKEYLOGFILE'] = str(self.root / 'must-not-exist')
        self.write_command('curl', r'''
[[ -z ${SSLKEYLOGFILE-} && $1 == -qfsSm60 ]] || exit 99
printf '%s\n' "$*" > "$MOCK_LOG"
cat <<'PAYLOAD'
IFS= read -r choice
printf 'selection=%s arguments=%s,%s\n' "$choice" "$1" "$2"
exit 1
PAYLOAD
''')
        result = self.command(' -- --site us5', '5\n')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout.strip(), 'selection=5 arguments=--site,us5')
        args = (self.root / 'calls').read_text()
        for expected in ['-qfsSm60', DOWNLOAD_URL]:
            self.assertIn(expected, args)
        self.assertNotIn('-L', args)
        self.assertNotIn('--location', args)
        self.assertFalse((self.root / 'must-not-exist').exists())

    def test_full_interactive_bundle_without_checkout(self):
        self.env['BUNDLE_PATH'] = str(ROOT / 'dist/dd-network-check.sh')
        self.write_command('curl', fr'''
if [[ ${{*: -1}} == "{DOWNLOAD_URL}" ]]; then
    cat "$BUNDLE_PATH"
else
    printf '%s\n' "$*" >> "$MOCK_LOG"
    printf 'HTTP/1.1 403 Forbidden\r\nServer: intake\r\n\r\n'
    printf '\nDD_PREFLIGHT_META\n403\nhttps://example.com/\n192.0.2.1\n0\n0\n'
fi
''')
        result = self.command(stdin='1\n')
        self.assertEqual(result.returncode, 1, result.stderr + result.stdout[-3000:])
        self.assertIn('9) US2-FED', result.stdout)
        self.assertIn('Choice:', result.stdout)
        self.assertEqual([p.name for p in self.invocation.iterdir()], ['reports'])
        reports = list((self.invocation / 'reports').glob('*.json'))
        self.assertEqual(len(reports), 1)
        report = json.loads(reports[0].read_text())
        expected_ids = [line.split('|')[0] for line in (ROOT / 'config/endpoints.conf').read_text().splitlines()
                        if line and not line.startswith('#') and line.split('|')[7] != 'wildcard']
        self.assertEqual([e['id'] for e in report['endpoints']], expected_ids)
        self.assertEqual(report['site']['code'], 'us1')
        self.assertEqual(report['overall_status'], 'READY WITH WARNINGS')
        self.assertEqual(report['metadata']['scan_scope'], 'full')
        self.assertEqual(len(list((self.invocation / 'reports').iterdir())), 2)
        self.assertTrue(reports[0].with_suffix('.txt').exists())
        self.assertNotIn('*.agent', (self.root / 'calls').read_text())
        self.assertNotIn('*.agent', result.stdout)
        self.assertNotIn('*.browser-intake', result.stdout)
        self.assertEqual(report['allowlist_requirements'], ['*.agent.datadoghq.com', '*.browser-intake-datadoghq.com'])
        self.assertTrue(all(endpoint['test_type'] != 'wildcard' for endpoint in report['endpoints']))

    def test_standalone_help_and_invalid_site_need_no_files(self):
        self.env['BUNDLE_PATH'] = str(ROOT / 'dist/dd-network-check.sh')
        self.write_command('curl', 'cat "$BUNDLE_PATH"')
        result = self.command(' -- --help')
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.command(' -- --site invalid-site')
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(list(self.invocation.iterdir()), [])
