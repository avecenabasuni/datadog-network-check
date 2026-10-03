"""Warning attribution, visible punctuation and timed TTY progress regressions."""
import os
import pty
import re
import signal
import subprocess
import tempfile
from pathlib import Path
import unittest

import test_checker
import test_diagnostics

ANSI = re.compile(rb'\x1b\[[0-9;?]*[A-Za-z]')


class TerminalFixTests(unittest.TestCase):
    run_code = test_checker.UnitTests.run_code

    def test_terminal_text_removes_semicolons_before_wrapping(self):
        for width in [80, 50]:
            output = self.run_code(f'COLUMNS={width}; '
                "terminal_wrap 'First clause; second clause; third clause with additional words' '  ' '  '; "
                "terminal_note 'Warning; inspect proxy; see TXT report.'; "
                "terminal_box_wrap 'RUM: VM-side sanity only; browser connectivity untested'; "
                "terminal_status WARN 'example; label'; "
                "terminal_truncate 'name; value' 40; terminal_middle_host 'a;host.example.com' 40")
            self.assertNotIn(';', output)
            self.assertIn('First clause. second clause.', output.replace('\n  ', ' '))
            self.assertLessEqual(max(map(len, output.splitlines())), width)
        encoded = self.run_code(r'''terminal_path "/tmp/it's;folder\\name"''')
        self.assertNotIn(';', encoded)
        decoded = test_checker.bash("printf '%s' " + encoded)
        self.assertEqual(decoded.returncode, 0, decoded.stderr)
        self.assertEqual(decoded.stdout, "/tmp/it's;folder\\name")

    def test_help_and_errors_have_no_semicolons(self):
        result = test_checker.bash('./dd-network-check.sh --help')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(';', result.stdout)
        result = test_checker.bash("./dd-network-check.sh 'bad;argument'")
        self.assertEqual(result.returncode, 3)
        self.assertNotIn(';', result.stderr)

    def test_retry_reason_does_not_hide_endpoint_row(self):
        output = self.run_code("category=api; E[hostname]=example.com; E[impact]=WARN; "
            "E[dns]=PASS; E[tcp]=PASS; E[tls]=PASS; E[http]=WARN; E[http_status]=302; "
            "E[notes]='Origin HTTPS recovered on retry; initial failure retained'; "
            "E[redirect_http]=PASS; E[redirect_http_status]=200; E[redirect_http_detail]='Reached redirect'; "
            'terminal_endpoint')
        self.assertRegex(output, r'WARN\s+example\.com\s+ok\s+ok\s+ok\s+302>200')
        self.assertIn('origin reached after a failed attempt.', output)
        self.assertNotIn('Redirect follow-up needs review', output)

    def tty(self, code, expected=0):
        master, slave = pty.openpty()
        env = os.environ.copy()
        env.update({'TERM': 'xterm', 'LC_ALL': 'C.UTF-8', 'COLUMNS': '80'})
        env.pop('NO_COLOR', None)
        try:
            result = subprocess.run(['bash', '-c', test_checker.SOURCE + code],
                cwd=test_checker.ROOT, env=env, stdout=slave, stderr=subprocess.PIPE, timeout=6)
            os.close(slave)
            slave = -1
            output = b''
            while True:
                try:
                    chunk = os.read(master, 16384)
                    if not chunk:
                        break
                    output += chunk
                except OSError as exc:
                    if exc.errno != 5:
                        raise
                    break
            self.assertEqual(result.returncode, expected, result.stderr.decode())
            return output, result.stderr
        finally:
            if slave >= 0:
                os.close(slave)
            os.close(master)

    def test_spinner_moves_during_one_blocking_probe_and_keeps_parent_state(self):
        output, _ = self.tty(r'''
trap terminal_progress_clear EXIT
TERMINAL_TTY=1 TERMINAL_WIDTH=80 TERMINAL_PROGRESS_TICK=0
TERMINAL_PROGRESS_DONE=4 TERMINAL_PROGRESS_TOTAL=54
TERMINAL_PROGRESS_HOST=7-84-1-app.agent.datadoghq.com
terminal_progress
worker=$TERMINAL_PROGRESS_PID
# Simulate a foreground network call. E must remain in the parent shell.
sleep 0.65
E[dns]=PASS
terminal_progress_clear
kill -0 "$worker" 2>/dev/null && exit 9
printf '\nFINAL_ROW dns=%s\n' "${E[dns]}"
sleep 0.2
''')
        frames = re.findall(rb'([|/\-\\]) Checking 4/54 7-84-1-app.agent.datadoghq.com', output)
        self.assertGreaterEqual(len(set(frames)), 3, output)
        self.assertIn(b'FINAL_ROW dns=PASS', output)
        self.assertNotIn(b'Checking', output.split(b'FINAL_ROW', 1)[1])
        self.assertIn(b'\x1b[?25l', output)
        self.assertIn(b'\x1b[?25h', output)

    def test_spinner_repeated_stop_during_frame_does_not_break_trap_parser(self):
        code = test_checker.SOURCE + r'''
terminal_color_enabled() { return 0; }
trap terminal_progress_clear EXIT
TERMINAL_TTY=1 TERMINAL_WIDTH=80
TERMINAL_PROGRESS_DONE=37 TERMINAL_PROGRESS_TOTAL=54
TERMINAL_PROGRESS_HOST=checkip.amazonaws.com
for ((i=0;i<80;i++)); do
    terminal_progress
    worker=$TERMINAL_PROGRESS_PID
    sleep 0.121
    terminal_progress_clear
    kill -0 "$worker" 2>/dev/null && exit 9
done
exit 0
'''
        process = subprocess.Popen(['bash', '-c', code], cwd=test_checker.ROOT,
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, start_new_session=True)
        try:
            _, stderr = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            _, stderr = process.communicate()
            self.fail('Spinner shutdown stalled: ' + stderr.decode())
        self.assertEqual(process.returncode, 0, stderr.decode())
        self.assertEqual(stderr, b'')

    def test_spinner_stops_before_new_endpoint_and_on_exit(self):
        with tempfile.TemporaryDirectory(dir=test_checker.ROOT / 'reports') as directory:
            pid_file = os.path.join(directory, 'worker')
            output, _ = self.tty(r'''
trap terminal_progress_clear EXIT
TERMINAL_TTY=1 TERMINAL_WIDTH=80 TERMINAL_PROGRESS_TICK=0
TERMINAL_PROGRESS_DONE=0 TERMINAL_PROGRESS_TOTAL=2
TERMINAL_PROGRESS_HOST=first.example.com
terminal_progress
first=$TERMINAL_PROGRESS_PID
sleep 0.3
terminal_progress_clear
printf '\nFIRST_FINISHED\n'
TERMINAL_PROGRESS_HOST=second.example.com
terminal_progress
printf '%s' "$TERMINAL_PROGRESS_PID" > ''' + repr(pid_file) + r'''
sleep 0.3
kill -0 "$first" 2>/dev/null && exit 9
exit 3
''', expected=3)
            worker = int(Path(pid_file).read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(worker, 0)
            self.assertNotIn(b'Checking 0/2 first.example.com', output.split(b'FIRST_FINISHED')[1])
            self.assertTrue(output.endswith(b'\x1b[?25h'), output)

    def test_interrupt_reaps_spinner_and_restores_cursor(self):
        output, stderr = self.tty(r'''
trap terminal_interrupt INT TERM HUP
trap terminal_progress_clear EXIT
TERMINAL_TTY=1 TERMINAL_WIDTH=80 TERMINAL_PROGRESS_TICK=0
TERMINAL_PROGRESS_DONE=0 TERMINAL_PROGRESS_TOTAL=2
TERMINAL_PROGRESS_HOST=example.com
terminal_progress
sleep 0.2
kill -TERM $$
''', expected=3)
        self.assertIn(b'\x1b[?25h', output)
        self.assertIn(b'Scan interrupted.', stderr)
        self.assertNotIn(b';', stderr)


class RegistryWarningTests(unittest.TestCase):
    setUp = test_checker.IntegrationTests.setUp
    write_command = test_checker.IntegrationTests.write_command
    manifest = test_checker.IntegrationTests.manifest
    scan = test_checker.IntegrationTests.scan
    redirect_fixture = test_diagnostics.DiagnosticReportTests.redirect_fixture
    registry_manifest = test_diagnostics.DiagnosticReportTests.registry_manifest

    def test_eu_registry_tcp_warning_does_not_blame_verified_redirect(self):
        self.redirect_fixture(r'''
printf '\nDD_PREFLIGHT_META\n200\nhttps://accounts.google.com/\n192.0.2.3\n1\n0\n'
''')
        self.registry_manifest('eu.gcr.io')
        self.write_command('getent', "printf '192.0.2.1 STREAM example.com\\n192.0.2.2 STREAM example.com\\n'")
        self.write_command('timeout', r'''
shift 2; shift
case $1 in
 getent) shift; getent "$@";;
 bash) [[ ${*: -2:1} != 192.0.2.2 ]] || exit 124;;
 openssl) echo 'Verify return code: 0 (ok)';;
 *) exit 1;;
esac
''')
        result, report = self.scan(1)
        endpoint = report['endpoints'][0]
        self.assertEqual(endpoint['tcp_result']['status'], 'WARN')
        self.assertEqual(endpoint['http_result']['status'], 'PASS')
        self.assertEqual(endpoint['http_result']['redirect_result']['status'], 'PASS')
        self.assertEqual(endpoint['impact'], 'WARN')
        self.assertIn('TCP: 192.0.2.2 FAIL - timeout.', result.stdout)
        self.assertNotIn('Redirect follow-up needs review', result.stdout)
        self.assertNotIn(';', result.stdout)
        txt = next((self.root / 'reports').glob('*.txt')).read_text()
        self.assertIn('192.0.2.2 FAIL - timeout', txt)
        self.assertIn('; direct path', txt)
        self.assertEqual(report['direct_endpoint_counts'], {'pass': 0, 'warn': 1, 'fail': 0})
