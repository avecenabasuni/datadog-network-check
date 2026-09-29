#!/usr/bin/env bash
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P) || exit 1
cd "$ROOT" || exit 1
python3 -B -m unittest discover -s tests -p 'test_*.py' -v || exit 1
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x dd-network-check.sh lib/*.sh tests/*.sh || exit 1
else
    printf '\nShellCheck: unavailable (not installed automatically).\n'
fi
