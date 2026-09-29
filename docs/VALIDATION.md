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

## v0.1.1 transport attribution and bounded retries

All **64 offline regression tests passed**. This includes 16 new cases covering origin-versus-redirect attribution, TLS process timeouts after verified negotiation, incomplete handshakes, certificate-error preservation, bounded recovery attempts and timeout-phase diagnostics. Bundle freshness and Bash syntax checks passed. ShellCheck remained unavailable and was not installed.

Live smoke checks on the development machine passed: example.com returned HTTP 206; the Datadog API origin returned HTTP 307 with verified TLS, and its separate redirect diagnostic received HTTP 200 (WARN for the response size cap). The reserved nonexistent DNS name and held non-listening loopback port failed as expected. The smoke output is in `reports/live-smoke.json`, ignored by Git. These observations are not evidence about the customer VM.

A full US1 scan using the rebuilt standalone artifact completed with **exit 1 / READY WITH WARNINGS**, covering all **59 manifest entries** and **23 categories**, with **zero blockers**. TXT and JSON reports were generated and validated, including schema 1.1, tool version 0.1.1 and absence of ANSI escapes. Report base: `reports/dd-network-preflight-MSI-20260929-125955-O4h7j6LL`. API evidence from that scan:

```text
api.datadoghq.com
DNS              PASS
TCP              WARN - three IPv4 successes, one IPv6 network-unreachable result
TLS              PASS
HTTP origin      307 - verified TLS, endpoint reachable
Origin timing    TCP=0.266403s, TLS=0.518607s, total=0.766905s (cumulative)
Redirect follow  WARN - HTTP 200, response exceeded diagnostic size limit
Endpoint impact  WARN
```

The JSON report now uses schema 1.1: original HTTP response fields describe the manifest endpoint, while `http_result.redirect_result` describes the follow-up. TLS/HTTP attempt histories and cumulative request timing make transient recovery and persistent failures distinguishable. A reachable original endpoint followed by a failed redirect is explicitly WARN; that redirect destination still requires review. A separately listed required destination can still block the scan through its own result.

Context7 was consulted for official [curl timing variables](https://github.com/curl/curl/blob/master/docs/cmdline-opts/write-out.md), [redirect behavior](https://github.com/curl/curl/blob/master/docs/cmdline-opts/location.md), and OpenSSL verification behavior. The [OpenSSL s_client documentation](https://docs.openssl.org/3.0/man1/openssl-s_client/) was also reviewed for non-interactive use and EOF handling. Verification code zero alone is not treated as evidence of a completed handshake after a timeout; the warning exception also requires negotiated TLS cipher evidence and no verification error.

## v0.1.2 warning semantics

The customer US1 report from 2026-09-29T13:06:08Z showed 46 DNS and 46 TLS passes, with 32 HTTP passes and 14 HTTP warnings; no directly tested endpoint had a hard failure. Most category warnings came from the checker's four-address sampling limit and IPv6 `network unreachable` alongside successful IPv4. The checker was overstating network risk. A response-body cap after verified HTTPS and a successful same-host redirect also generated warnings despite proving the original endpoint reachable.

The revised rules keep sampling and an unavailable IPv6 route in report notes without warning when the tested IPv4 path works. Verified HTTP responses remain PASS when only the checker-controlled body sample stops. One verified redirect to the original HTTPS hostname can PASS; cross-host or multi-hop redirects remain WARN. Actual sampled address timeouts/refusals, failed TLS verification, incomplete HTTPS responses, and unverified wildcard/manual requirements retain their distinct statuses. The summary now includes direct endpoint PASS/WARN/FAIL counts, separate from manual coverage requirements. JSON schema is 1.2 and tool version is 0.1.2.

All **70 offline tests passed**; the new cases cover four successful sampled addresses plus untested answers, IPv4 success with IPv6 unreachability, IPv4 timeout, IPv6-only failure, single same-host redirect success, and multi-hop redirect warning. Bundle freshness and Bash syntax checks passed. ShellCheck was unavailable and was not installed. An opt-in live smoke check returned DNS/TCP/TLS/HTTP PASS for the Datadog API origin, while reserved DNS and closed-port negatives failed as expected. These live observations were made from the development machine, not the customer VM.

Context7 confirmed the official curl [`--max-filesize` behavior](https://github.com/curl/curl/blob/master/docs/cmdline-opts/max-filesize.md): exit 63 can reflect the deliberate transfer cap rather than a failed HTTPS connection. The checker still requires a real HTTP status and verified TLS before accepting that outcome; unrelated curl errors retain their failure status.

A full US1 scan with the 0.1.2 standalone program covered all **59 manifest entries** and **23 categories**, writing schema 1.2 TXT and JSON reports without ANSI escapes. Its direct checks were **39 PASS, 7 WARN, 0 FAIL** and its overall result was **READY WITH WARNINGS**, with zero blockers. Installation, API, APM, logs, DBM and other required directly testable server categories passed. The remaining direct warnings were one informational RUM Remote Configuration sanity check with ambiguous denial wording and six conditional registry alternatives involving cross-host redirects. The agent, RUM and miscellaneous requirement categories also retain unverified wildcard/manual coverage warnings. Report base: `reports/dd-network-preflight-MSI-20260929-131802-5VwN2FFU`. This scan ran from the development machine, not the customer VM.

The API result in that report is an example of the corrected classification:

```text
api.datadoghq.com
DNS              PASS
TCP              PASS - 3 reachable IPv4 addresses; IPv6 network unreachable is recorded
TLS              PASS
HTTP             PASS - origin HTTP 307
Redirect follow  PASS - same hostname, HTTP 200; response sampling capped
Endpoint impact  PASS
```

## v0.1.3 terminal presentation

The terminal now renders one status line per applicable endpoint, with compact DNS/TCP/TLS/HTTP evidence and short reasons below WARN or FAIL results. Wildcard/manual requirements appear as REVIEW, and RUM sanity checks carry a `[VM only]` label. Category readiness, direct PASS/WARN/FAIL counts, blockers, remaining manual requirements and report paths remain visible at the end. The detailed TXT and JSON contents and readiness rules are unchanged.

A full US1 scan with the v0.1.3 standalone artifact completed with **39 direct PASS, 7 direct WARN, 0 direct FAIL** and **READY WITH WARNINGS** from the development VM. Its compact console output was checked against the 59-entry schema 1.2 JSON report and full TXT report. The terminal had no ANSI codes when redirected; TXT and JSON were also ANSI-free. Report base: `reports/dd-network-preflight-MSI-20260929-132831-9O47t3Hh`. Later display-only adjustments shortened status spacing, clarified redirect destinations and explicitly labeled VM-side RUM checks; focused tests cover those final renderings. This scan is not evidence about the customer VM.

All **73 regression tests passed**. The suite includes checks for interactive compact rows, detailed TXT retention, a visible HTTP timeout reason, unavailable OpenSSL diagnostics, RUM's VM-only limit, terminal-only ANSI color, `NO_COLOR` suppression and the standalone one-command scan. ShellCheck was unavailable and was not installed. Context7's official [Bash conditional expressions](https://www.gnu.org/software/bash/manual/html_node/Bash-Conditional-Expressions.html) and [`printf` builtin](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html) documentation were consulted for terminal detection and formatted output.
