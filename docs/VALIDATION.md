# Validation record

Date: **2026-09-29**. Environment: Linux under Ubuntu/WSL on the development machine. These results are not customer-VM readiness evidence.

- **34 offline regression tests passed**, including interactive execution, all exit codes, manifest validation, stage failure handling, absent optional diagnostics, proxy secrecy, binary HTTP responses, and TXT/JSON reporting.
- Bash syntax checks passed for the entry point, libraries and test runner.
- ShellCheck was unavailable in both the Windows host and Linux environment. It was not installed. `tests/run.sh` will run it when present.
- Opt-in live smoke checks passed: example.com returned verified HTTPS with status 206; Datadog API root returned HTTPS 200 after a redirect; the reserved `.invalid` hostname failed DNS; a held, non-listening loopback port failed TCP.
- A real full **US1 scan completed with exit 1 / READY WITH WARNINGS**. It recorded all **59 manifest entries** and **23 categories**, with no required endpoint blockers. Of 46 directly probed entries, 32 HTTP stages passed and 14 warned. Six entries were not applicable; seven requirements could not be directly tested. The machine had no determinable installed stable Agent version.
- Report JSON parsed successfully, all 59 IDs were unique, and neither JSON nor TXT contained ANSI escape sequences.

Warnings included IPv6 network unreachability alongside working IPv4, sampling of larger DNS answer sets, redirects, and unverified wildcard/manual requirements. All observed endpoint HTTPS responses were evidence of reachability only.

Actual generated artifacts (ignored by Git):

- `reports/dd-network-preflight-MSI-20260929-035726-ohtgQ5G9.txt`
- `reports/dd-network-preflight-MSI-20260929-035726-ohtgQ5G9.json`
- `reports/live-smoke.json`

Excerpt from the real US1 scan:

```text
trace.agent.datadoghq.com - APM traces
DNS              PASS
CNAME            PASS
TCP/443          WARN - 3 successful IPv4 probes; 1 IPv6 network-unreachable result
TLS              PASS - SNI, hostname and chain verified
HTTP             PASS
HTTP Status      403

Overall: READY WITH WARNINGS
```

The full scan exposed binary NUL bytes in one registry response. The final implementation filters NULs from bounded in-memory capture, and the final regression suite includes that case. No raw response bodies are persisted.

## One-command distribution follow-up

The expanded suite passed **41 tests**, including a complete 59-record interactive standalone scan from a directory without `config/` or `lib/`. Only the report directory was created there. Tests also verified that failed/partial/empty downloads do not execute, terminal input and arguments are preserved, checker exit codes propagate, and the generated bundle matches its source modules and manifests. The standalone bundle passed Bash syntax validation. ShellCheck remained unavailable.
