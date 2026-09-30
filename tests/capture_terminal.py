"""Regenerate deterministic, offline terminal presentation samples.

Run from the repository root: python3 -B tests/capture_terminal.py
"""
import os
from pathlib import Path
import pty
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs' / 'terminal-captures'
SCRIPT = r'''
source ./dd-network-check.sh
declare -A E=() SITE_LABELS=([us1]=US1) SITE_DOMAINS=([us1]=datadoghq.com)
declare -A TERMINAL_SNAP=() TERMINAL_COUNTS=() TERMINAL_GROUP_COUNTS=()
declare -a TERMINAL_ORDER=() TERMINAL_NOTE_KEY=() CATEGORY_ORDER=() BLOCKERS=() ALLOWLIST=() UNTESTED=()
SITE=us1 MACHINE=eminerba-lab OS_NAME='Ubuntu 22.04.5 LTS'
AGENT_VERSION='' PROXY_PRESENT=0 TERMINAL_TTY=$1
OVERALL='READY WITH WARNINGS' DIRECT_PASS=4 DIRECT_WARN=5 DIRECT_FAIL=0
REPORT_BASE='/home/ave/reports/dd-network-preflight-eminerba-lab-20260930-035702-VRGkFOu3'
terminal_banner
terminal_intro 'curl dig nslookup openssl nc' ''
add_row() {
    local category=$1 host=$2 impact=$3 classification=$4 http=$5 note=$6
    reset_result
    E[hostname]=$host E[impact]=$impact E[classification]=$classification
    E[dns]=PASS E[tcp]=PASS E[tls]=PASS E[http]=PASS E[http_status]=$http
    E[notes]=$note E[redirect_http_detail]='No reachable redirect response'
    if [[ $impact == WARN ]]; then
        E[http]=WARN
        if [[ $note == redirect ]]; then
            E[http_status]=302 E[redirect_http]=PASS E[redirect_http_status]=200
            E[redirect_http_detail]='Reached redirect'
            E[redirect_final_url]='https://accounts.google.com/[path omitted]'
        else
            E[notes]='Denial/filter wording observed'
            E[http_detail]='Response contains denial/filter wording'
        fi
    fi
    terminal_capture_endpoint
}
category=installation
add_row installation install.datadoghq.com PASS 'DIRECT TEST' 200 ''
add_row installation apt.datadoghq.com PASS 'DIRECT TEST' 206 ''
category=agent
add_row agent '*.agent.datadoghq.com' PASS 'ALLOWLIST REQUIREMENT' '' ''
ALLOWLIST+=('*.agent.datadoghq.com')
category=rum
add_row rum browser-intake-datadoghq.com PASS 'SERVER-SIDE SANITY CHECK ONLY' 403 ''
add_row rum sdk-configuration.browser-intake-datadoghq.com WARN 'SERVER-SIDE SANITY CHECK ONLY' 403 denial
add_row rum '*.browser-intake-datadoghq.com' PASS 'ALLOWLIST REQUIREMENT' '' ''
ALLOWLIST+=('*.browser-intake-datadoghq.com')
category=container_registries
for host in registry.datadoghq.com gcr.io eu.gcr.io asia.gcr.io; do
    add_row container_registries "$host" WARN 'DIRECT TEST' 302 redirect
done
add_row container_registries public.ecr.aws PASS 'DIRECT TEST' 401 ''
CATEGORY_ORDER=(installation agent rum container_registries)
terminal_render_report
terminal_summary
'''


def render(tty, changes):
    env = os.environ.copy()
    env.update({'TERM': 'xterm', 'LC_ALL': 'C.UTF-8', 'COLUMNS': '80'})
    env.pop('NO_COLOR', None)
    env.pop('COLORTERM', None)
    env.update(changes)
    command = ['bash', '-c', SCRIPT, '_', '1' if tty else '0']
    if tty:
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=slave,
                                       stderr=subprocess.PIPE)
            os.close(slave)
            slave = -1
            chunks = []
            while True:
                try:
                    chunk = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno != 5:
                        raise
                    break
                if not chunk:
                    break
                chunks.append(chunk)
            stderr = process.communicate()[1]
            if process.returncode:
                raise RuntimeError(stderr.decode())
            return b''.join(chunks).replace(b'\r\n', b'\n')
        finally:
            if slave >= 0:
                os.close(slave)
            os.close(master)
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, check=True)
    return result.stdout


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    variants = {
        'color-tty.ansi': (True, {'COLORTERM': 'truecolor'}),
        'no-color.txt': (True, {'NO_COLOR': '1'}),
        'ascii-locale.txt': (True, {'LC_ALL': 'C', 'NO_COLOR': '1'}),
        'narrow-50.txt': (True, {'COLUMNS': '50', 'NO_COLOR': '1'}),
        'piped.txt': (False, {}),
    }
    for name, (tty, env) in variants.items():
        output = render(tty, env)
        visible = re.sub(rb'\x1b\[[0-9;]*m', b'', output)
        lines = visible.decode('utf-8').splitlines()
        assert max(map(len, lines)) <= (50 if name == 'narrow-50.txt' else 80), name
        if name == 'color-tty.ansi':
            assert b'\x1b[38;2;99;44;166m' in output
            assert b'\x1b[33m' in output
        else:
            assert b'\x1b' not in output, name
        if name == 'ascii-locale.txt':
            assert output.isascii()
        if name == 'piped.txt':
            assert output.startswith(b'DATADOG NETWORK PREFLIGHT  v0.1.3\n')
        (OUT / name).write_bytes(output)
        print(f'{name}: {len(output)} bytes')


if __name__ == '__main__':
    main()
