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

## Oversized HTTP response correction

A reported false BLOCKED result was reproduced: the old combined response/metadata stream was truncated before curl's trailing metadata and exit code, causing the checker to display its internal fallback value as `curl exit 99`. This could happen on older curl versions when an unknown-size response exceeded the capture limit. It was not proof of network blocking.

The corrected probe sends its bounded body/header sample and curl metadata through separate channels, counts the sampled bytes independently, and preserves the actual curl result. An intentional sample cutoff becomes WARN only with verified HTTPS and an HTTP response; unrelated write errors, TLS errors and timeouts remain FAIL. Missing diagnostic metadata is explicitly SKIPPED.

Live checks of `install.datadoghq.com` from the development environment received HTTP 200 with verified TLS. Both curl's own file-size cutoff (exit 63) and an emulated older-curl streaming path using the real curl executable (exit 23) correctly resulted in WARN. These development-machine observations do not replace a fresh customer-VM scan.

All **48 regression tests passed** after this fix, including the standalone full-scan test and negative cases that keep actual network errors as FAIL. The bundle freshness and Bash syntax checks passed. ShellCheck was still unavailable and was not installed.

The compatibility behavior was checked through Context7 against curl's official [maximum file size documentation](https://github.com/curl/curl/blob/master/docs/cmdline-opts/max-filesize.md): before 8.4.0, unknown-size transfers were not constrained by this option during transfer.
