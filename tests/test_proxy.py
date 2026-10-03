"""Process-local proxy routing, privacy, and real local CONNECT/TLS probes."""
import base64
import json
import os
from pathlib import Path
import pty
import select
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import unittest

import test_checker


class ProxyUnitTests(unittest.TestCase):
    run_code = test_checker.UnitTests.run_code

    def test_proxy_url_validation(self):
        for url in ['http://proxy:3128', 'https://proxy.internal:443', 'http://127.0.0.1:80', 'http://[::1]:3128']:
            self.assertEqual(self.run_code(f'proxy_url_valid "{url}"; echo $?'), '0')
        for url in ['http://user:pass@proxy:80', 'socks5://proxy:80', 'http://proxy', 'http://proxy:0',
                    'http://proxy:65536', 'http://proxy:80/path', 'http://proxy:80?q=x', 'http://proxy:80#x',
                    'http://[1::2::3]:80', 'http://bad host:80', 'http://-proxy:80']:
            self.assertEqual(self.run_code(f'proxy_url_valid "{url}"; echo $?'), '1', url)

    def test_route_config_and_credentials_stay_off_curl_argv(self):
        output = self.run_code(r'''
ROUTE_MODE=explicit PROXY_URL=http://private-proxy:3128
PROXY_AUTH_PRESENT=1 PROXY_USER=privateuser PROXY_PASSWORD='p"ass\word'
export PROXY_URL PROXY_USER PROXY_PASSWORD
HTTPS_PROXY=http://wrong:80 NO_PROXY='*'
curl() { printf 'argv=%s\n' "$*"; [[ ! -v HTTPS_PROXY && ! -v NO_PROXY ]] || exit 9; [[ $(export -p) != *PROXY_PASSWORD* ]] || exit 9; cat; }
curl_route --silent https://example.com
''')
        argv, config = output.split('\n', 1)
        self.assertNotIn('private', argv)
        self.assertIn('--config -', argv)
        self.assertIn('noproxy = ""', config)
        self.assertIn('proxy-basic', config)
        self.assertIn(r'proxy-user = "privateuser:p\"ass\\word"', config)

    def test_direct_bypasses_environment_without_mutating_parent(self):
        output = self.run_code(r'''
ROUTE_MODE=direct HTTPS_PROXY=http://keep-parent:3128
curl() { [[ ! -v HTTPS_PROXY ]] || exit 9; cat; }
curl_route https://example.com
printf 'parent=%s\n' "$HTTPS_PROXY"
''')
        self.assertIn('proxy = ""', output)
        self.assertIn('noproxy = "*"', output)
        self.assertIn('parent=http://keep-parent:3128', output)

    def test_proxy_classification_uses_selected_route_only(self):
        output = self.run_code('ROUTE_MODE=explicit; E[dns]=FAIL; E[tcp]=FAIL; E[tls]=FAIL; '
            'E[http]=PASS; classify_result; echo "${E[status]} ${E[impact]}"; '
            'E[http]=FAIL; classify_result; echo "${E[status]} ${E[impact]}"; '
            'E[test_type]=ntp; E[ntp]=FAIL; E[http]=PASS; classify_result; echo "${E[status]} ${E[impact]}"')
        self.assertEqual(output, 'PASS PASS\nFAIL FAIL\nFAIL FAIL')

    def test_ntp_stays_direct_with_explicit_proxy(self):
        output = self.run_code('ROUTE_MODE=explicit; E[test_type]=ntp; '
            'curl_route() { echo SHOULD_NOT_RUN; }; ntp_resolve 127.0.0.1; '
            'ntp_probe() { return 124; }; ntp_check; classify_result; '
            'echo "${E[selected_route]} ${E[ntp]} ${E[status]}"')
        self.assertIn('direct FAIL FAIL', output)
        self.assertNotIn('SHOULD_NOT_RUN', output)

    def test_stdin_password_without_final_newline(self):
        code = test_checker.SOURCE + '''
ROUTE_MODE=explicit PROXY_URL=http://proxy:80 PROXY_USER=user
PROXY_PASSWORD_STDIN=1 PROXY_AUTH_PRESENT=0
proxy_configure || exit 3
printf '%s' "$PROXY_AUTH_PRESENT"
'''
        result = test_checker.bash(code, stdin='no-newline-password')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '1')

    def test_proxy_terminal_wide_and_narrow(self):
        for width in [80, 50]:
            output = self.run_code(f'ROUTE_MODE=explicit; COLUMNS={width}; category=agent; '
                'E[hostname]=example.com; E[impact]=PASS; E[dns]=FAIL; E[tcp]=FAIL; E[tls]=FAIL; '
                'E[http]=PASS; E[curl_tls]=PASS; E[http_status]=403; E[proxy_connect_status]=200; '
                'terminal_table_header; terminal_endpoint')
            self.assertIn('PROXY', output)
            self.assertNotIn('DNS', output)
            self.assertNotIn('fail', output)
            self.assertIn('PASS', output)
            self.assertLessEqual(max(map(len, output.splitlines())), width)

    def test_interactive_proxy_password_is_not_echoed(self):
        master, slave = pty.openpty()
        code = test_checker.SOURCE + '''
ROUTE_MODE=environment PROXY_URL='' PROXY_USER='' PROXY_PASSWORD=''
PROXY_PASSWORD_STDIN=0 PROXY_AUTH_PRESENT=0
proxy_configure || exit 3
printf '\\nRESULT route=%s auth=%s\\n' "$ROUTE_MODE" "$PROXY_AUTH_PRESENT"
'''
        process = subprocess.Popen(['bash', '-c', code], cwd=test_checker.ROOT,
            stdin=slave, stdout=slave, stderr=slave)
        os.close(slave)
        output = b''
        def until(marker):
            nonlocal output
            deadline = time.monotonic() + 5
            while marker not in output:
                self.assertLess(time.monotonic(), deadline, output)
                if select.select([master], [], [], .1)[0]:
                    output += os.read(master, 4096)
        try:
            for marker, answer in [(b'Choice [1]:', b'2\n'), (b'Proxy URL', b'http://proxy:3128\n'),
                                   (b'Basic authentication?', b'y\n'), (b'Proxy username:', b'user\n'),
                                   (b'Proxy password:', b'never-echo-this\n')]:
                until(marker)
                time.sleep(.05)
                os.write(master, answer)
            until(b'RESULT route=explicit auth=1')
            self.assertEqual(process.wait(timeout=3), 0)
            self.assertNotIn(b'never-echo-this', output)
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
            os.close(master)


class ProxyIntegrationTests(unittest.TestCase):
    setUp = test_checker.IntegrationTests.setUp
    write_command = test_checker.IntegrationTests.write_command
    manifest = test_checker.IntegrationTests.manifest

    def fixture(self, connect='200', rc=0):
        self.manifest('agent|agent|Agent|intake.example.com|443|https|all|full|required|all|/|-|https://example.com/docs\n')
        self.write_command('getent', 'exit 2')
        self.write_command('curl', f'''if [[ $* == *'--config -'* ]]; then cat >/dev/null; fi
printf '%s\\n' "$*" >> "$MOCK_LOG"
if [[ $* == *releases/latest* ]]; then echo 'https://github.com/DataDog/datadog-agent/releases/tag/7.84.1'; exit 0; fi
printf 'HTTP/1.1 403 Forbidden\\r\\nServer: private-proxy secret-pass\\r\\nVia: private-user\\r\\n\\r\\n'
printf '\\nDD_PREFLIGHT_META\\n403\\nhttps://intake.example.com/\\n192.0.2.3\\n0\\n0\\n0.01\\n0.02\\n0.03\\n0.04\\n0.05\\n{connect}\\n'
exit {rc}
''')

    def scan_proxy(self, expected=0):
        self.env.update({'HTTPS_PROXY': 'http://wrong.invalid:99', 'NO_PROXY': '*'})
        result = test_checker.bash('./dd-network-check.sh --site us1 --proxy http://private-proxy:3128 '
            '--proxy-user private-user --proxy-password-stdin', self.env, self.root, 'secret-pass\n')
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        report = json.loads(next((self.root / 'reports').glob('*.json')).read_text())
        return result, report

    def test_proxy_success_ignores_direct_failures_and_redacts_secrets(self):
        self.fixture()
        result, report = self.scan_proxy()
        endpoint = report['endpoints'][1]
        self.assertEqual(endpoint['status'], 'PASS')
        self.assertEqual(endpoint['dns_results']['status'], 'FAIL')
        self.assertEqual(endpoint['selected_route'], 'explicit')
        self.assertEqual(endpoint['http_result']['proxy_connect_status'], '200')
        self.assertEqual(endpoint['http_result']['remote_ip'], '')
        self.assertEqual(report['metadata']['route_mode'], 'explicit')
        self.assertEqual(report['metadata']['agent_version_source'], 'latest-release')
        self.assertEqual(report['overall_status'], 'READY')
        txt = next((self.root / 'reports').glob('*.txt')).read_text()
        for secret in ['private-proxy', 'private-user', 'secret-pass']:
            for text in [result.stdout, result.stderr, json.dumps(report), txt, (self.root / 'calls').read_text()]:
                self.assertNotIn(secret, text)
        self.assertNotIn(';', result.stdout)

    def test_connect_407_blocks_without_retry_or_fallback(self):
        self.fixture('407', 56)
        result, report = self.scan_proxy(2)
        self.assertEqual(report['endpoints'][1]['http_result']['status'], 'FAIL')
        self.assertIn('authentication rejected', result.stdout)
        self.assertEqual(len(report['endpoints'][1]['http_result']['attempts']), 1)
        self.assertTrue(all('DNS:' not in x for x in report['blockers']))

    def test_proxy_timeout_blocks_and_retries_are_recorded(self):
        self.fixture('000', 28)
        result, report = self.scan_proxy(2)
        http = report['endpoints'][1]['http_result']
        self.assertEqual(http['status'], 'FAIL')
        self.assertEqual(len(http['attempts']), 2)
        self.assertIn('Timeout', result.stdout)

    def test_proxy_retry_recovery_remains_warning(self):
        self.fixture()
        command = self.bin / 'curl'
        body = command.read_text()
        body = body.replace("printf 'HTTP/1.1", '''if [[ $* == *intake.example.com:443* && ! -e "$MOCK_LOG-retry" ]]; then
 touch "$MOCK_LOG-retry"
 printf '\\nDD_PREFLIGHT_META\\n000\\nhttps://intake.example.com/\\n\\n0\\n0\\n0\\n0\\n0\\n0\\n0\\n000\\n'
 exit 28
fi
printf 'HTTP/1.1''')
        command.write_text(body)
        result, report = self.scan_proxy(1)
        http = report['endpoints'][1]['http_result']
        self.assertEqual(http['status'], 'WARN')
        self.assertEqual(len(http['attempts']), 2)
        self.assertEqual(http['proxy_connect_status'], '200')
        self.assertIn('origin reached after a failed attempt', result.stdout)

    def test_bad_cli_is_rejected_without_reports(self):
        for args in ['--proxy http://user:pass@proxy:80', '--proxy http://proxy:80 --direct',
                     '--proxy-user user --direct', '--proxy-password-stdin', '--proxy socks5://proxy:80']:
            result = test_checker.bash('./dd-network-check.sh --site us1 ' + args, self.env, self.root, 'password\n')
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(list((self.root / 'reports').iterdir()), [])


class LocalServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class LocalProxyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(dir=test_checker.ROOT / 'reports')
        self.addCleanup(directory.cleanup)
        self.cert = str(Path(directory.name) / 'cert.pem')
        key = str(Path(directory.name) / 'key.pem')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
            '-keyout', key, '-out', self.cert, '-subj', '/CN=intake.example.test',
            '-addext', 'subjectAltName=DNS:intake.example.test,DNS:localhost'],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, key)
        class Origin(socketserver.BaseRequestHandler):
            def handle(self):
                try:
                    with context.wrap_socket(self.request, server_side=True) as connection:
                        request = connection.recv(8192)
                        if b' /redirect ' in request:
                            connection.sendall(b'HTTP/1.1 302 Found\r\nLocation: https://intake.example.test/final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
                        else:
                            connection.sendall(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
                except (ssl.SSLError, OSError):
                    pass
        self.origin = LocalServer(('127.0.0.1', 0), Origin)
        self.start(self.origin)
        self.connects = []
        self.auth = None
        self.rejection = None
        outer = self
        class Proxy(socketserver.BaseRequestHandler):
            def handle(self):
                client = self.request
                data = b''
                while b'\r\n\r\n' not in data:
                    chunk = client.recv(8192)
                    if not chunk: return
                    data += chunk
                outer.connects.append(data)
                rejection = outer.rejection
                if outer.auth and b'Proxy-Authorization: Basic ' + outer.auth not in data:
                    rejection = '407 Proxy Authentication Required'
                if rejection:
                    client.sendall(('HTTP/1.1 ' + rejection + '\r\nContent-Length: 0\r\nConnection: close\r\n\r\n').encode())
                    return
                with socket.create_connection(outer.origin.server_address, timeout=3) as upstream:
                    client.sendall(b'HTTP/1.1 200 Connection established\r\n\r\n')
                    # TLS control records can make select readable without any
                    # application bytes. A bounded read must not stall traffic
                    # flowing in the other direction through the tunnel.
                    client.settimeout(.1)
                    while True:
                        if isinstance(client, ssl.SSLSocket) and client.pending():
                            ready = [client]
                        else:
                            ready, _, _ = select.select([client, upstream], [], [], 3)
                        if not ready: return
                        for current in ready:
                            try:
                                chunk = current.recv(8192)
                            except socket.timeout:
                                continue
                            if not chunk: return
                            (upstream if current is client else client).sendall(chunk)
        self.proxy = LocalServer(('127.0.0.1', 0), Proxy)
        self.context = context

    def start(self, server):
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)

    def probe(self, path='/', authenticated=False, trusted=True, https_proxy=False):
        if https_proxy:
            self.proxy.socket = self.context.wrap_socket(self.proxy.socket, server_side=True)
        self.start(self.proxy)
        self.auth = base64.b64encode(b'user:p"ass\\word') if authenticated else None
        code = test_checker.SOURCE + f'ROUTE_MODE=explicit; PROXY_URL={"https" if https_proxy else "http"}://localhost:{self.proxy.server_address[1]}; '
        code += r'''PROXY_USER=user; PROXY_PASSWORD='p"ass\word'; '''
        code += f'PROXY_AUTH_PRESENT={int(authenticated)}; path={path}; TCP_TIMEOUT=2; HTTP_TIMEOUT=3; '
        if trusted:
            code += 'curl() { command curl --cacert "$FIXTURE_CA" --proxy-cacert "$FIXTURE_CA" "$@"; }; '
        code += 'http_check intake.example.test; classify_result; endpoint_json'
        env = {k: v for k, v in os.environ.items() if not k.lower().endswith('_proxy') and k not in ['CURL_CA_BUNDLE', 'SSL_CERT_FILE', 'SSL_CERT_DIR']}
        env.update({'FIXTURE_CA': self.cert, 'HTTPS_PROXY': 'http://wrong:1', 'NO_PROXY': '*'})
        result = test_checker.bash(code, env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_real_connect_and_basic_auth_with_special_password(self):
        result = self.probe(authenticated=True)
        self.assertEqual(result['status'], 'PASS', result['http_result'])
        self.assertEqual(result['http_result']['proxy_connect_status'], '200')
        self.assertIn(b'CONNECT intake.example.test:443', self.connects[0])

    def test_real_https_proxy_verifies_both_tls_connections(self):
        result = self.probe(https_proxy=True)
        self.assertEqual(result['status'], 'PASS', result['http_result'])

    def test_real_untrusted_destination_certificate_fails(self):
        result = self.probe(trusted=False)
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(result['http_result']['curl_exit'], '60')

    def test_real_untrusted_https_proxy_certificate_fails(self):
        result = self.probe(trusted=False, https_proxy=True)
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(result['http_result']['curl_exit'], '60')
        self.assertEqual(result['http_result']['proxy_connect_status'], '000')

    def test_real_missing_proxy_auth_is_rejected(self):
        # probe() configures the expected credentials only when authenticated.
        self.rejection = '407 Proxy Authentication Required'
        result = self.probe()
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(result['http_result']['proxy_connect_status'], '407')
        self.assertEqual(len(self.connects), 1)

    def test_real_rejected_connect_cannot_pass(self):
        self.rejection = '403 Forbidden'
        result = self.probe()
        self.assertEqual(result['status'], 'FAIL')
        self.assertEqual(result['http_result']['proxy_connect_status'], '403')

    def test_real_redirect_stays_on_proxy(self):
        result = self.probe(path='/redirect')
        self.assertEqual(result['status'], 'PASS', result['http_result'])
        self.assertEqual(result['http_result']['redirect_result']['proxy_connect_status'], '200')
        self.assertGreaterEqual(len(self.connects), 3)
