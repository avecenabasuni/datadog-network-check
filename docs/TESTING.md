# Testing

The checker runtime needs no Python. The regression suite uses Python 3's standard-library `unittest` to invoke Bash and inspect JSON. It writes isolated fixtures only below `reports/`, removes its own fixtures, and makes no network calls.

The suite also checks that the generated standalone bundle matches its source files, then tests the exact README one-command invocation with a mock downloader. It covers rejected partial/empty downloads, preserved input and exit codes, argument forwarding, and a complete interactive scan from a directory without a checkout. See [distribution design](DISTRIBUTION.md).

HTTP capture regression cases simulate older curl receiving an unknown-size response larger than the sample limit. They verify metadata/exit-code preservation, WARN instead of a false blocker for an intentionally closed sample pipe, and continued FAIL for real write errors or timeouts. Small responses and diagnostic-reader failures are covered separately.

Transport-attribution regressions cover a verified TLS session followed by a process timeout, an incomplete handshake with verification code zero, certificate failures that must never be downgraded, and a timeout retry on another TCP-reachable address. HTTP cases cover recovery versus persistent failure, cumulative timing-based timeout details, no retries for certificate errors, and preservation of original HTTP 307 independently of successful, timed-out or certificate-rejected redirect follow-ups. Integration tests assert TXT/JSON histories, redacted redirect URLs, actionable blocker reasons and the resulting readiness status.

```bash
bash tests/run.sh
```

Coverage includes all site/template combinations; malformed and executable-looking manifest data; duplicate DNS answers; IPv4/IPv6; NSS errors; missing dig, OpenSSL and timeout; CNAME chain/response errors; refused and timed-out TCP; mixed-family TCP results; SNI/hostname verification; non-2xx HTTP; TLS/timeout errors despite earlier HTTP headers; redirects; block-page heuristics; secret withholding; JSON escaping; wildcard non-probing; interactive selection; report persistence; and all four exit codes.

Shell functions (`have`, `tcp_connect`, `tls_probe`, `curl_probe`) provide narrow test seams. Integration fixtures replace executables through PATH, so production code has no undocumented test-mode environment variable or alternate manifest bypass. Regression reports are parsed with Python JSON and checked for ANSI escape codes. Python is invoked with `-B` to avoid writes outside the report directory.

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
