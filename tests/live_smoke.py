"""Explicit opt-in real network smoke checks; no third-party Python packages."""
import json
from pathlib import Path
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def probe(host, port=443, tcp_only=False):
    code = '''source ./dd-network-check.sh
declare -A E=(); reset_result
port=$2; path=/; requirement=required; PROXY_PRESENT=0
E[hostname]=$1
if [[ $3 == tcp ]]; then
 E[ips]=$1; tcp_check
else
 dns_check "$1"; tcp_check; tls_check "$1"; http_check "$1"
fi
endpoint_json
'''
    result = subprocess.run(['bash', '-c', code, 'smoke', host, str(port), 'tcp' if tcp_only else 'full'],
                            cwd=ROOT, text=True, capture_output=True, timeout=100)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)


def main():
    if sys.argv[1:] != ['--live']:
        print('Usage: python3 -B tests/live_smoke.py --live')
        return 3
    results = [probe('example.com'), probe('api.datadoghq.com'), probe('dd-preflight-does-not-exist.invalid')]
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))  # Held open without listen: deterministic refused port.
        results.append(probe('127.0.0.1', sock.getsockname()[1], tcp_only=True))
    target = ROOT / 'reports/live-smoke.json'
    target.write_text(json.dumps(results, indent=2) + '\n')
    for result in results:
        print(result['hostname'], 'DNS=' + result['dns_results']['status'],
              'TCP=' + result['tcp_result']['status'], 'TLS=' + result['tls_result']['status'],
              'HTTP=' + result['http_result']['status'], 'status=' + result['http_result']['http_status'])
    print('Report:', target)
    return 0 if (all(r['http_result']['status'] in ('PASS', 'WARN') for r in results[:2])
                 and results[2]['dns_results']['status'] == 'FAIL'
                 and results[3]['tcp_result']['status'] == 'FAIL') else 1


if __name__ == '__main__':
    raise SystemExit(main())
