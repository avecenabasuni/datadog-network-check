# Testing

Terminal regressions reproduce a TCP-warning `eu.gcr.io` scan with a verified redirect, check warning/count consistency across terminal/TXT/JSON, and assert no visible semicolons. PTY tests hold one foreground probe while multiple spinner frames appear, retain parent result state, restart for another endpoint, and check helper reaping and cursor restoration on explicit stop, EXIT and TERM. Terminal capture generation strips ANSI controls before checking punctuation. Context7's GNU Bash execution-environment, wait and signal references and curl redirect documentation were reviewed for these changes.

The checker runtime needs no Python. The regression suite uses Python 3's standard-library `unittest` to invoke Bash and inspect JSON. It writes isolated fixtures only below `reports/`, removes its own fixtures, and makes no external network calls. NTP tests exchange real UDP datagrams on IPv4/IPv6 loopback only.

NTP regressions cover valid NTPv3/v4 replies, malformed/truncated/untrusted bytes, origin mismatch, wrong mode/version/stratum, zero transmit timestamp, unsynchronized servers, Kiss-o'-Death, response deadlines, address sampling/recovery, missing tools, public versus explicit target impact, override validation, and terminal/TXT/JSON readiness consistency. Context7's Datadog NTP overview and Agent troubleshooting references were checked on 2026-10-03, with the official Agent implementation and RFC 5905 for packet behavior.

The suite also checks that the generated standalone bundle matches its source files, then tests the exact README one-command invocation with a mock downloader. It covers rejected partial/empty downloads, preserved input and exit codes, argument forwarding, and a complete interactive scan from a directory without a checkout. See [distribution design](DISTRIBUTION.md).

HTTP capture regression cases simulate older curl receiving an unknown-size response larger than the sample limit. They verify metadata/exit-code preservation, PASS when a verified HTTP response is intentionally capped, and continued FAIL for real write errors or timeouts. Small responses and diagnostic-reader failures are covered separately.

Transport-attribution regressions cover a verified TLS session followed by a process timeout, an incomplete handshake with verification code zero, certificate failures that must never be downgraded, and a timeout retry on another TCP-reachable address. HTTP cases cover recovery versus persistent failure, cumulative timing-based timeout details, no retries for certificate errors, and preservation of original HTTP 307 independently of successful, timed-out or certificate-rejected redirect follow-ups. Integration tests assert TXT/JSON histories, redacted redirect URLs, actionable blocker reasons and the resulting readiness status.

Readiness semantics tests distinguish four sampled TCP successes from untested additional DNS answers, working IPv4 plus IPv6 `network unreachable`, a real IPv4 timeout, and IPv6-only failure. Redirect tests distinguish a verified single-hop same-host redirect, an expected registry redirect, an unexpected redirect host, and multi-hop redirects. Agent tests cover latest stable release discovery, bounded lookup and invalid-response handling, override precedence, concrete app/flare probes, and REVIEW when the version is unknown. Wildcard tests require no network calls, endpoint rows, category warnings, REVIEW counts, or exit-code changes from documentation guidance; patterns remain in TXT/JSON notes. The report assertions cover direct endpoint PASS/WARN/FAIL counts separately from manual requirements.

```bash
bash tests/run.sh
```

Coverage includes all site/template combinations; malformed and executable-looking manifest data; duplicate DNS answers; IPv4/IPv6; NSS errors; missing dig, OpenSSL and timeout; CNAME chain/response errors; refused and timed-out TCP; mixed-family TCP results; SNI/hostname verification; non-2xx HTTP; TLS/timeout errors despite earlier HTTP headers; redirects; block-page heuristics; secret withholding; JSON escaping; wildcard non-probing; interactive selection; report persistence; and all four exit codes.

Denial-response regressions distinguish generic 200/401/403/404 wording (report note only) from Fortinet/Zscaler/Palo Alto denial signatures (WARN). An S3 XML `AccessDenied` fixture for RUM Remote Configuration must retain PASS in the terminal, TXT/JSON endpoint, counts, and readiness without storing raw response contents. Generic denial wording must not clear HTTP 407/5xx warnings or timeout/TLS failures. These rules were checked against CloudFront and curl documentation using Context7 on 2026-10-03.

Shell functions (`have`, `tcp_connect`, `tls_probe`, `curl_probe`) provide narrow test seams. Integration fixtures replace executables through PATH, so production code has no undocumented test-mode environment variable or alternate manifest bypass. Regression reports are parsed with Python JSON and checked for ANSI escape codes. A streaming test delays a later endpoint and checks that the earlier row has already appeared. The total-count test compares the number with the applicable manifest records. `tests/capture_terminal.py` writes six offline captures, including color TTY, `NO_COLOR`, ASCII locale, 50 columns, pipe, and Ctrl-C footer cleanup. Python is invoked with `-B` to avoid writes outside the report directory.

Terminal presentation tests check that an interactive run shows one compact endpoint row while the TXT report retains the detailed probe records. They also check actionable failure text, plain output when redirected, ANSI colors when stdout is a TTY, and `NO_COLOR` suppression. The summary's readiness counts are still validated against JSON.

Passing NTP rows omit the reply commentary at both 80 and 50 columns. WARN/FAIL NTP notes remain visible, while TXT/JSON retain the full response details and stratum.

Recovered NTP warnings must explain the prior address failure in terminal, TXT and JSON while preserving the failed and successful attempts. Spinner tests repeatedly stop the helper near a frame boundary, require empty stderr, and check that each helper has exited. A timeout kills the test process group to avoid leaving a stuck helper.

`tests/run.sh` runs ShellCheck when available and clearly reports when it is absent. It never installs packages. Bash syntax can also be checked with:

```bash
bash -n dd-network-check.sh
for module in lib/*.sh; do bash -n "$module" || exit 1; done
```

For real DNS/TCP/HTTPS smoke checks, explicitly run:

```bash
python3 -B tests/live_smoke.py --live
```

This probes a public HTTPS host, the documented Datadog API origin without credentials, a reserved nonexistent `.invalid` domain, and a bound but non-listening loopback port. It writes `reports/live-smoke.json`. Public-route failures are reported honestly and cause the smoke command to fail; they are not automatically evidence of a code defect. Proxy/trust-store/IPv6 constraints depend on the test machine. A non-2xx response is expected but not guaranteed at a public API root; the offline fixtures deterministically test 400/401/403/404/405.

For a real full report, run `./dd-network-check.sh --site us1` or select the appropriate site interactively. An exit code of 1 or 2 is an expected diagnostic outcome, not a test harness crash. Review a customer VM independently; development-machine results are not customer readiness evidence.
