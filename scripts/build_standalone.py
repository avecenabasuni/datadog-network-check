#!/usr/bin/env python3
"""Build the single-file Bash distribution; Python is for maintainers only."""
import argparse
import hashlib
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'dist/dd-network-check.sh'
MAX_BYTES = 120000  # Stay below Linux's per-argument limit for bash -c.


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f'Expected exactly one distribution anchor: {old!r}')
    return text.replace(old, new, 1)


def build():
    sources = {}

    def read(name):
        text = (ROOT / name).read_text(encoding='utf-8')
        sources[name] = text
        return text

    entry = read('dd-network-check.sh')
    entry = replace_once(entry,
        'ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || exit 3',
        '# Standalone mode writes reports beneath the invocation directory.\n'
        'ROOT=$(pwd -P) || exit 3')
    pattern = r'# shellcheck source=(lib/[a-z]+\.sh)\nsource "\$ROOT/\1" \|\| exit 3'
    modules = re.findall(pattern, entry)
    if modules != ['lib/utils.sh', 'lib/dns.sh', 'lib/tcp.sh', 'lib/ntp.sh', 'lib/tls.sh', 'lib/http.sh', 'lib/proxy.sh', 'lib/reporting.sh']:
        raise ValueError('Entry-point module list changed; review the distribution builder')

    def inline(match):
        name = match.group(1)
        module = read(name)
        if name == 'lib/utils.sh':
            for manifest in ['sites', 'endpoints']:
                data = read(f'config/{manifest}.conf')
                delimiter = f'DD_PREFLIGHT_{manifest.upper()}_MANIFEST_EOF'
                if delimiter in data:
                    raise ValueError('Manifest conflicts with the quoted here-document delimiter')
                module = replace_once(module, f'done < "$ROOT/config/{manifest}.conf"',
                    f"done <<'{delimiter}'\n{data.rstrip(chr(10))}\n{delimiter}")
        return f'# BEGIN GENERATED MODULE: {name}\n{module.rstrip()}\n# END GENERATED MODULE: {name}'

    entry = re.sub(pattern, inline, entry)
    entry = replace_once(entry,
        'if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; exit $?; fi',
        'main "$@"\nexit $?')
    digest = hashlib.sha256()
    for name, content in sorted(sources.items()):
        digest.update(name.encode() + b'\0' + content.encode() + b'\0')
    banner = ('# GENERATED FILE: edit source modules/manifests, then run scripts/build_standalone.py.\n'
              '# Includes all runtime modules and both reviewed manifests. No runtime extraction.\n'
              f'# source_sha256={digest.hexdigest()}\n')
    if not entry.startswith('#!/usr/bin/env bash\n'):
        raise ValueError('Unexpected entry-point interpreter')
    entry = entry.replace('#!/usr/bin/env bash\n', '#!/usr/bin/env bash\n' + banner, 1)
    if len(entry.encode()) > MAX_BYTES:
        raise ValueError('Bundle exceeds the one-command argument-size budget; review distribution strategy')
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Fail if the committed bundle is stale')
    args = parser.parse_args()
    try:
        content = build()
        if args.check:
            if not TARGET.exists() or TARGET.read_bytes() != content.encode():
                print('Standalone bundle is stale; run python3 -B scripts/build_standalone.py', file=sys.stderr)
                return 1
            print('Standalone bundle matches all source modules and manifests.')
        else:
            TARGET.parent.mkdir(exist_ok=True)
            TARGET.write_text(content, encoding='utf-8', newline='\n')
            print(f'Built {TARGET.relative_to(ROOT)} ({len(content.encode())} bytes)')
    except (OSError, ValueError) as exc:
        print(f'Build failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
