"""Regenerate offline terminal samples: python3 -B tests/capture_terminal.py."""
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
declare -A TERMINAL_SNAP=() TERMINAL_COUNTS=() TERMINAL_GROUP_COUNTS=() TERMINAL_GROUP_HOSTS=() TERMINAL_GROUP_HOST_SEEN=()
declare -a TERMINAL_ORDER=() TERMINAL_NOTE_KEY=() CATEGORY_ORDER=() BLOCKERS=() ALLOWLIST=() UNTESTED=() TERMINAL_OTHER_REQUIREMENTS=()
SITE=us1 MACHINE=eminerba-lab OS_NAME='Ubuntu 22.04.5 LTS'
AGENT_VERSION='7-84-1' AGENT_VERSION_DISPLAY='7.84.1' AGENT_VERSION_SOURCE=latest-release
PROXY_PRESENT=0 TERMINAL_TTY=$1 TERMINAL_WIDTH=$COLUMNS NTP_TARGET_SOURCE=documented-public-fallback
TERMINAL_PROGRESS_TOTAL=17 TERMINAL_PROGRESS_DONE=0 TERMINAL_PROGRESS_TICK=0
OVERALL='READY WITH WARNINGS' DIRECT_PASS=15 DIRECT_WARN=1 DIRECT_FAIL=0
REPORT_BASE='/home/ave/reports/dd-network-preflight-eminerba-lab-20260930-035702-VRGkFO'
terminal_banner
terminal_intro 'curl dig nslookup openssl nc' ''
terminal_table_header
add_row() {
    local category=$1 host=$2 impact=$3 classification=$4 http=$5 note=$6 redirect_host=${7-}
    terminal_category_start
    TERMINAL_PROGRESS_HOST=$host
    terminal_progress
    reset_result
    E[hostname]=$host E[impact]=$impact E[classification]=$classification E[test_type]=''
    E[dns]=PASS E[tcp]=PASS E[tls]=PASS E[http]=PASS E[http_status]=$http
    E[notes]=$note E[redirect_host]=$redirect_host
    E[redirect_http_detail]='No reachable redirect response'
    [[ $host != *'{version}'* ]] || E[test_type]=version
    if [[ $classification == 'NOT DIRECTLY TESTABLE' ]]; then
        E[dns]='NOT DIRECTLY TESTABLE' E[tcp]='NOT DIRECTLY TESTABLE'
        E[tls]='NOT DIRECTLY TESTABLE' E[http]='NOT DIRECTLY TESTABLE'
    elif [[ $note == expected ]]; then
        E[http_status]=302 E[redirect_http]=PASS E[redirect_http_status]=200
        E[redirect_http_detail]='Reached redirect'
    elif [[ $note == unexpected ]]; then
        E[http]=WARN E[http_status]=302 E[redirect_http]=PASS E[redirect_http_status]=200
        E[redirect_http_detail]='Reached redirect'
        E[notes]='Unexpected redirect target; possible proxy/captive portal block page.'
    elif [[ $note == denial ]]; then
        E[notes]='Generic denial wording observed; insufficient evidence of network filtering'
    elif [[ $note == ntp ]]; then
        E[test_type]=ntp E[protocol]=udp E[port]=123
        E[tcp]='NOT APPLICABLE' E[tls]='NOT APPLICABLE' E[http]='NOT APPLICABLE'
        E[ntp]=PASS E[ntp_detail]='Valid matched NTPv3 server reply; stratum 2; direct UDP/123'
    fi
    terminal_capture_endpoint
    terminal_progress_clear
    TERMINAL_CURRENT_INDEX=$((${#TERMINAL_ORDER[@]}-1))
    terminal_endpoint
    ((TERMINAL_PROGRESS_DONE+=1))
}
category=installation
add_row installation install.datadoghq.com PASS 'DIRECT TEST' 200 ''
add_row installation apt.datadoghq.com PASS 'DIRECT TEST' 206 ''
category=agent
add_row agent '7-84-1-app.agent.datadoghq.com' PASS 'DIRECT TEST' 403 ''
add_row agent '7-84-1-flare.agent.datadoghq.com' PASS 'DIRECT TEST' 403 ''
ALLOWLIST+=('*.agent.datadoghq.com')
category=rum
add_row rum browser-intake-datadoghq.com PASS 'SERVER-SIDE SANITY CHECK ONLY' 403 ''
add_row rum sdk-configuration.browser-intake-datadoghq.com PASS 'SERVER-SIDE SANITY CHECK ONLY' 403 denial
ALLOWLIST+=('*.browser-intake-datadoghq.com')
category=container_registries
add_row container_registries registry.datadoghq.com PASS 'DIRECT TEST' 302 expected docs.datadoghq.com
for host in gcr.io eu.gcr.io asia.gcr.io; do
    add_row container_registries "$host" PASS 'DIRECT TEST' 302 expected accounts.google.com
done
add_row container_registries us-docker.pkg.dev WARN 'DIRECT TEST' 302 unexpected proxy.example.test
add_row container_registries public.ecr.aws PASS 'DIRECT TEST' 401 ''
category=ntp
for pool in {0..3}; do
    add_row ntp "$pool.datadog.pool.ntp.org" PASS 'DIRECT TEST' '' ntp
done
category=other_requirements
add_row other_requirements destination-unspecified WARN 'NOT DIRECTLY TESTABLE' '' ''
TERMINAL_OTHER_REQUIREMENTS+=('UDP telemetry (UDP/8125)')
UNTESTED+=('UDP telemetry')
CATEGORY_ORDER=(installation agent rum container_registries ntp other_requirements)
terminal_group_notes "$LAST_TERMINAL_CATEGORY"
terminal_summary
'''
INTERRUPT_SCRIPT = r'''
source ./dd-network-check.sh
TERMINAL_TTY=1 TERMINAL_WIDTH=80 TERMINAL_PROGRESS_TICK=0
TERMINAL_PROGRESS_DONE=4 TERMINAL_PROGRESS_TOTAL=15
TERMINAL_PROGRESS_HOST='sdk-configuration.browser-intake-datadoghq.com'
trap terminal_interrupt INT
terminal_progress
kill -INT $$
'''


def render(tty, changes, script=SCRIPT, expected=0):
    env = os.environ.copy()
    env.update({'TERM': 'xterm', 'LC_ALL': 'C.UTF-8', 'COLUMNS': '80'})
    env.pop('NO_COLOR', None)
    env.pop('COLORTERM', None)
    env.update(changes)
    command = ['bash', '-c', script, '_', '1' if tty else '0']
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
            assert process.returncode == expected, (process.returncode, stderr)
            output = b''.join(chunks).replace(b'\r\n', b'\n')
            return output + stderr if expected else output
        finally:
            if slave >= 0:
                os.close(slave)
            os.close(master)
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    assert result.returncode == expected, (result.returncode, result.stderr)
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
        visible = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', output)
        assert b';' not in visible, name
        lines = visible.decode('utf-8').replace('\r', '\n').splitlines()
        body_lines = [line for line in lines if not line.startswith(('  Reports:', '  TXT ', '  JSON '))]
        assert max(map(len, body_lines)) <= (50 if name == 'narrow-50.txt' else 80), name
        if name == 'color-tty.ansi':
            assert b'\x1b[38;2;99;44;166m' in output
            assert b'\x1b[33m' in output
            assert b'Checking ' in output
        else:
            assert b'\x1b' not in output, name
        if name == 'ascii-locale.txt':
            assert output.isascii()
        if name == 'piped.txt':
            assert output.startswith(b'DATADOG NETWORK PREFLIGHT  v0.1.8\n')
        (OUT / name).write_bytes(output)
        print(f'{name}: {len(output)} bytes')
    interrupted = render(True, {}, INTERRUPT_SCRIPT, expected=3)
    assert b'Checking 4/15' in interrupted
    assert b'\x1b[2K' in interrupted and b'\x1b[?25h' in interrupted
    assert b'Scan interrupted' in interrupted
    (OUT / 'ctrl-c-mid-scan.ansi').write_bytes(interrupted)
    print(f'ctrl-c-mid-scan.ansi: {len(interrupted)} bytes')


if __name__ == '__main__':
    main()
