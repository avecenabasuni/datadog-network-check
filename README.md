# Datadog Network Preflight Checker

A read-only Bash tool for checking network prerequisites from a Linux application VM before a Datadog POC. Run it, select a Datadog site, and it scans the full documented destination inventory. No product selection or API key is required.

**A successful scan does not mean “Datadog is working.”** It does not validate Agent configuration, API keys, instrumentation, DBM permissions, or telemetry ingestion.

```text
Server-side connectivity:             Browser RUM connectivity:

Application VM                       End-user browser
      |                                    |
      |                         Corporate Network / DNS / Firewall
      |                                    |
      v                                    v
Datadog endpoints                     Datadog RUM intake

Passing the first DOES NOT prove the second.
```

## Run with one command (recommended)

From a writable directory on the Linux VM, paste this single command:

```bash
bash -c 's=$(SSLKEYLOGFILE= curl -qfsSm60 "https://raw.githubusercontent.com/avecenabasuni/datadog-network-check/main/dist/dd-network-check.sh?v=0.1.8") || exit 3; exec bash -c "${s:-exit 3}" -- "$@"'
```

Select a Datadog site when prompted; the **entire scan** runs automatically. The generated single-file distribution includes every runtime module and both manifests. No clone, unpacking, package installation, API key, or product selection is needed. Runtime requirements remain Bash 4+, curl and the standard Linux utilities listed below; Python and Git are not required on the customer VM.

The download completes successfully before execution begins. The compact `-qfsSm60` options disable curlrc, reject HTTP download errors, show errors without a progress meter, and cap the entire transfer at 60 seconds. The URL is HTTPS with certificate verification enabled; redirects are not followed. Download failures or empty responses exit 3 without starting a scan. Standard input stays connected to the terminal for site selection. Existing proxy settings are honored; TLS debug-secret logging is suppressed for the download process.

**Reports are saved in `./reports/` under the directory where you run the command**, even if no repository checkout exists. The downloaded program and embedded manifests stay in memory; no installation or temporary extraction directory is created. Generated TXT/JSON files and exit codes are the same as local execution.

The URL uses the published `main` bundle with a versioned query to avoid reusing a cached response from a previous release. It serves v0.1.8 only after the commits are pushed to `main`; check the printed version before using a new release. The VM needs outbound access to `raw.githubusercontent.com` for the download and `github.com` for the default latest stable Agent version lookup, in addition to the Datadog destinations being tested. If GitHub access is unavailable, transfer the reviewed `dist/dd-network-check.sh` file through your approved channel and run `bash dd-network-check.sh --agent-version X.Y.Z`; it also works without companion files. Remote execution trusts this repository and GitHub's HTTPS delivery; the embedded source digest is build provenance, not an independent signature.

For unattended execution, append `-- --site us1` after the closing quote of the one-command invocation. With no arguments, interactive selection remains the default. See [distribution design and tests](docs/DISTRIBUTION.md).

## Run from a local checkout

Use a Linux VM with Bash 4+ and curl. Keep the project directories together, make the entry point executable if your distribution method did not preserve its mode, then run:

```bash
./dd-network-check.sh
```

Select US1, US3, US5, EU1, AP1, AP2, UK1, US1-FED, or US2-FED. The full scan starts immediately. No sudo is needed. The current user needs write access to this tool's `reports/` directory.

For automation, `./dd-network-check.sh --site us1` runs the same full scan. `--help` prints usage. `--quick` and `--category` are intentionally reserved for a future release; they currently return exit code 3 rather than silently reducing coverage.

The tool never installs software, changes configuration, restarts services, or sends telemetry payloads. **Its only filesystem writes are reports and private intermediate report files under `reports/`.** HTTPS requests, DNS queries, TCP connections, and TLS handshakes generate normal network/server logs. Installation domains are probed at `/`; no installers or packages are downloaded or executed. A bounded HTTPS HEAD request discovers the latest stable Agent release. Agent configuration files are not read.

## Supported sites

| Selection | Site parameter | Browser RUM domain |
|---|---|---|
| US1 | datadoghq.com | browser-intake-datadoghq.com |
| US3 | us3.datadoghq.com | browser-intake-us3-datadoghq.com |
| US5 | us5.datadoghq.com | browser-intake-us5-datadoghq.com |
| EU1 | datadoghq.eu | browser-intake-datadoghq.eu |
| AP1 | ap1.datadoghq.com | browser-intake-ap1-datadoghq.com |
| AP2 | ap2.datadoghq.com | browser-intake-ap2-datadoghq.com |
| UK1 | uk1.datadoghq.com | browser-intake-uk1-datadoghq.com |
| US1-FED | ddog-gov.com | browser-intake-ddog-gov.com |
| US2-FED | us2.ddog-gov.com | browser-intake-us2-ddog-gov.com |

These mappings come from [Datadog Sites](https://docs.datadoghq.com/getting_started/site/) and [RUM SDK domains](https://docs.datadoghq.com/real_user_monitoring/). Product availability differs by site. A hostname appearing in documentation does not establish product entitlement or availability for a specific organization.

## Project layout

```text
dd-network-check.sh          Interactive selection, validation, orchestration
config/sites.conf           Explicit site and RUM mappings
config/endpoints.conf       Destination data, applicability, policy, provenance
lib/{dns,tcp,tls,http,ntp}.sh Independent diagnostics
lib/utils.sh                Manifest validation and deterministic result rules
lib/reporting.sh            Terminal, TXT and JSON serialization
docs/ENDPOINTS.md            Source review, exclusions and maintenance process
docs/TESTING.md              Test strategy and live validation instructions
tests/                      Offline regression suite and opt-in live smoke tests
reports/                    Generated reports; ignored by Git
dist/dd-network-check.sh     Generated standalone distribution (committed)
scripts/build_standalone.py  Maintainer-only deterministic bundle builder
```

## What is checked

The manifest covers installation, versioned Agent metrics/flare requirements, API access, APM, logs, live processes/containers, USM/cloud network monitoring, orchestration and container lifecycle, Remote Configuration, DBM, profiling, instrumentation telemetry, LLM Observability, SBOM/security, software inventory/device intake, network devices/path, IP ranges, private Synthetic workers, registries, RUM, RUM Remote Configuration, and Browser Profiling quota. Conditional third-party public-IP discovery destinations are also represented.

The following stages have independent results:

1. **DNS:** bounded `getent ahosts` uses the VM's NSS resolver. `dig` collects A/AAAA answers when available, otherwise bounded `nslookup` can supply addresses. Answers are deduplicated. NSS/DNS disagreement is exposed rather than silently hidden.
2. **CNAME:** `dig` follows up to eight aliases, recording errors and loops. A hostname without CNAMEs can pass. `nslookup` provides partial information with a warning; otherwise detailed inspection is skipped. A chain is evidence, not proof that every CDN address works or that filtering caused a failure.
3. **TCP:** direct connections to up to four resolved addresses, each with a five-second limit. IPv4 and IPv6 are supported. A successful address with another real timeout/refusal is WARN; all sampled addresses failing is FAIL. An IPv6 `network unreachable` result is recorded but does not warn when an IPv4 address worked. Sampling only four addresses is disclosed as a coverage note, not a failure. Without `timeout`, the raw TCP stage is skipped.
4. **TLS:** OpenSSL connects to the first reachable IP with SNI, hostname verification, certificate-chain verification and an eight-second limit. An inconclusive timeout gets one retry, preferring another IP that passed TCP. Success on retry is WARN, retaining the failed attempt. A verified negotiated TLS session followed by an OpenSSL process timeout is WARN; verification code zero alone is insufficient for that exception. Certificate errors remain FAIL and are not retried. Subject, issuer, expiry, probe IP, exit code and attempts are reported. Unknown issuers do not imply inspection. Missing OpenSSL, hostname-verification support, or `timeout` skips detailed inspection; curl still provides verified HTTPS evidence. OpenSSL and curl can have different trust stores.
5. **HTTP:** curl first checks the original endpoint **without following redirects**, using its environment-configured route, certificate verification, a five-second connect limit and a twelve-second total limit. Transient transport errors (curl 7/28/52/55/56) get one bounded retry; recovery is WARN and both attempts remain visible. Certificate errors are not retried. A reachable 3xx response triggers a separate follow-up request with at most three HTTPS-only redirects. The original status/IP and redirect result are retained separately. A failed follow-up warns about the redirect path; it does not erase the successful response from the original endpoint. One fully verified redirect back to the same hostname can PASS. A verified registry redirect to its observed expected host can also PASS. An unexpected cross-host target or multi-hop chain remains WARN because it may add allowlist requirements.

A GET with a byte range limits requested body size. Response capture is capped; raw bodies and headers are never written to reports. HTTP status, redacted URL, remote IP, redirects, Server and Via are reported, along with cumulative DNS, TCP-connect, TLS-completion, first-byte and total times in seconds. These times are measured from request start, not individual phase durations. Timeout messages use available timings to distinguish connection, TLS/proxy negotiation, response-wait and response-transfer phases; missing timing evidence remains explicitly unknown. URL paths, queries, fragments and userinfo are withheld because redirects can contain secrets.

All limits are at the top of `dd-network-check.sh`. Requests are sequential; successful endpoints receive no retry. HTTP performs at most two original-endpoint attempts plus one optional redirect diagnostic (up to four requests in that diagnostic). TLS performs at most two attempts. A full scan can take several minutes, especially with failed or slow routes. A successful sampled address does not validate every current or future IP, both IP families, sustained availability, throughput, payload upload limits, or every API path/method. The script uses ordinary hostnames; it does not separately validate trailing-dot behavior used by newer Agents.

## Terminal display and detailed reports

On a color-capable TTY, the progress spinner refreshes every 120 ms during a probe, using an optional `sleep` helper. Only the display runs in the background; diagnostics remain sequential in the parent shell. The helper is stopped and reaped before endpoint output and on exit/interrupt, restoring the cursor. Piped output, `NO_COLOR`, and `TERM=dumb` remain free of animation/control sequences. Visible terminal text replaces semicolons with periods; detailed TXT/JSON evidence retains its original wording. A verified `302>200` redirect does not explain a separate TCP warning: the terminal shows the failed sampled IP and reason instead.

NTP has a separate direct UDP stage. Requests use NTPv3 like the Agent default; replies must have a valid server mode/version, matching originate timestamp, usable stratum, nonzero transmit timestamp and synchronized-server indicator. A socket opening or unrelated bytes never pass. A request has a five-second deadline, probes at most two resolved addresses, and stops on a matched usable, unsynchronized or Kiss-o'-Death response. TCP/TLS/HTTP are NOT APPLICABLE for NTP. No clock changes, clock-offset measurement, or server authentication are performed.

The terminal shows a Datadog banner after site selection. It uses the block-letter version in a UTF-8 terminal at least 64 columns wide, ASCII art in other locales, and a compact header below 64 columns or with `--quiet`. Use `--no-banner` to hide it. A pipe receives one plain title line. Each category heading and endpoint row streams during the scan; a TTY with color enabled shows a single temporary progress footer. Endpoint rows align DNS, TCP, TLS, and HTTP stages. Narrow terminals stack those stages below each endpoint and show the full name under a shortened hostname. `WARN` and `FAIL` reasons use up to two indented lines, while expected registry redirects share one allowlist note. Manual targets and unresolved versioned destinations say `REVIEW` and are marked not tested. Wildcard firewall guidance stays in TXT/JSON documentation notes, outside terminal test rows and counts. A redirect appears as `307>200` when the original endpoint responded 307 and its follow-up returned 200.

The boxed summary gives the readiness verdict, direct-check counts, per-category counts, categories needing attention, manual-review counts, and the RUM limitation. Report paths show the directory once and one complete filename per line. RUM checks are VM-side sanity checks; end-user browser connectivity remains untested. Terminal color appears only on a TTY, and `NO_COLOR=1` or `TERM=dumb` disables it. Piped output and report files contain no ANSI codes. [Six offline captures](docs/terminal-captures/) show color TTY, `NO_COLOR=1`, `LC_ALL=C`, `COLUMNS=50`, piped output, and Ctrl-C; regenerate them with `python3 -B tests/capture_terminal.py`.

```text
  STATUS DESTINATION                                      DNS  TCP  TLS HTTP

 CONTAINER REGISTRIES ---------------------------------------------------------
  PASS   registry.datadoghq.com                            ok   ok   ok 302>206
  PASS   gcr.io                                            ok   ok   ok 302>200
  WARN   us-docker.pkg.dev                                 ok   ok   ok 302>200
       -> Unexpected redirect target; possible proxy/captive portal block page.
       -> Allow docs.datadoghq.com, accounts.google.com.

+- SUMMARY --------------------------------------------------------------------+
|  [!!]  READY WITH WARNINGS                                                   |
|  [OK] 11 pass   [!!] 1 warn    [XX] 0 fail    [??] 1 review                  |
|  By category                                                                 |
|    container registries: 5 pass, 1 warn, 0 fail, 0 review                    |
|  Needs attention                                                             |
|    [!!] container registries: 1 unexpected redirect(s); inspect proxy       |
|  Manual review: 1 other requirement(s)                                      |
|  RUM: VM-side sanity only; end-user browser connectivity untested            |
+------------------------------------------------------------------------------+

  Reports: /home/ave/reports
  TXT  dd-network-preflight-eminerba-lab-<stamp>.txt
  JSON dd-network-preflight-eminerba-lab-<stamp>.json
```

This is an illustrative excerpt, not evidence about your VM. The TXT report keeps every DNS/CNAME answer, IP probe, certificate detail and response timing; JSON keeps the machine-readable fields. The compact terminal view and detailed files report the same readiness result.

## Interpreting results

Per-test states are PASS, WARN, FAIL, SKIPPED, NOT APPLICABLE and NOT DIRECTLY TESTABLE. Documented wildcard firewall patterns are configuration guidance, outside endpoint test results.

| Evidence | Interpretation |
|---|---|
| Verified HTTPS and HTTP 200/400/401/403/404/405 | Reachable; application response received |
| HTTP 5xx or proxy 407 | WARN; a service or proxy returned an error |
| Diagnostic response-body cap after verified HTTPS response | PASS; sampling stopped intentionally and is noted |
| Single same-host HTTPS redirect with verified follow-up | PASS; original and follow-up responses remain visible |
| Verified registry redirect to its expected host | PASS; redirect host recorded and shared terminal allowlist note shown |
| Unexpected cross-host or multi-hop redirect | WARN; review all destinations in the chain |
| Working IPv4 with IPv6 `network unreachable` | TCP PASS; the IPv6 result is recorded separately |
| Additional DNS answers beyond four sampled addresses | Coverage note; sampled results determine TCP status |
| Original endpoint responds, redirect follow-up fails | WARN for original endpoint; separate redirect FAIL stays visible |
| Transient failure followed by successful bounded retry | WARN; both attempts retained |
| Verified TLS session negotiated, then OpenSSL process times out | WARN; process timeout is not labeled handshake failure |
| TLS/DNS/TCP failure, reset, timeout, no HTTP response | FAIL for the affected stage |
| Vendor plus explicit denial/filter wording | WARN: POSSIBLE SECURITY FILTERING; not definitive proof |
| Generic “access denied”/“blocked” wording | Report note only; does not change verified HTTPS connectivity status |
| Optional detailed test unavailable | SKIPPED; coverage warning |
| Valid matched NTP server reply | NTP PASS; direct UDP reachability, not proof of local clock synchronization |
| NTP Kiss-o'-Death or unsynchronized-server reply | NTP WARN; server responded without usable synchronized time |
| NTP timeout, invalid reply, or request timestamp mismatch | NTP FAIL; timeout alone does not establish filtering |
| Version/port requirement without concrete target | NOT DIRECTLY TESTABLE; coverage warning |
| Documented wildcard firewall pattern | TXT/JSON documentation note; no test result or readiness impact |
| Windows-only, excluded traffic, or site excluded by manifest | NOT APPLICABLE; neutral in aggregation |

A body-size cap is a deliberate exception: if TLS was verified and HTTP headers arrived, curl exit 63 does not make network readiness warn or fail. Curl metadata is captured separately from the bounded response sample, so large bodies cannot discard the HTTP status or actual exit code. On older curl versions, closing the sample pipe can produce exit 23; it is accepted only when the independent response-sample byte count confirms the limit was reached. The cap remains visible in the HTTP detail and notes. Other write errors and transport failures remain failures even if an earlier response arrived. Missing diagnostic metadata is reported as SKIPPED, never as a fabricated curl exit code or a proven network blocker. HTTP reachability cannot conclusively identify a transparent intermediary that presents a trusted certificate; block-page detection is only a conservative heuristic.

Generic denial wording alone is recorded without raising WARN. A verified, completed `403 Access Denied` response from the RUM SDK configuration endpoint demonstrates HTTPS reachability, but does not validate retrieval of remote settings. [CloudFront documents](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/http-403-permission-denied.html) that S3 permissions, incorrect paths, missing objects, and WAF rules can all cause 403 responses; their source cannot be established from that status or generic denial text alone. [curl documents](https://github.com/curl/curl/blob/master/docs/cmdline-opts/fail.md) that HTTP error responses do not fail the transfer by default. The checker still warns for vendor-plus-denial signatures, HTTP 407/5xx, failed redirects, and recovery on retry; transport and certificate failures retain their failure status. It does not use AmazonS3/CloudFront headers as an exception to these rules.

An endpoint's **status** is its worst stage result (FAIL, then WARN/SKIPPED/unverified, then PASS). Its **impact** determines readiness:

- Required server endpoints: any stage failure produces FAIL impact after the bounded retries above. A redirect follow-up is a separate diagnostic; its failure contributes WARN when the original endpoint was reachable. If that destination is itself a required manifest endpoint, its own failed check still blocks readiness.
- Informational endpoints: failures remain visible, but impact is WARN. These include browser sanity checks, optional public-IP lookups, alternative registries, legacy API/flare and private-worker destinations, and conditional software/device inventory.
- If a proxy environment is configured and curl establishes verified HTTPS, direct-path failures produce WARN impact. They remain FAIL in the individual stages. This is route evidence, not confirmation that the Agent uses the same proxy. The script does not infer exact proxy selection from environment presence.
- Manual requirements and skipped diagnostics produce WARN impact. They can never become PASS merely because a related hostname resolves. Documented wildcard patterns do not affect the readiness verdict or exit code.
- Category status is its worst endpoint impact. Excluded-only categories are PASS (no applicable blockers); their endpoint rows remain NOT APPLICABLE.

| Overall | Exit code | Rule |
|---|---|---|
| READY | 0 | All applicable checks pass, no unresolved coverage requirements |
| READY WITH WARNINGS | 1 | No FAIL impact, but at least one warning or unverified requirement |
| BLOCKED | 2 | At least one required endpoint has FAIL impact |
| Script/configuration/internal error | 3 | Invalid input, missing required tools, unsupported OS, report failure or interrupted scan |

On US1/EU1, **the shipped full manifest normally cannot reach READY**, because custom autoscaling and RC development requirements still lack concrete destinations. Other sites can reach READY when all applicable checks pass. READY WITH WARNINGS is not an unconditional all-clear. BLOCKED refers to the declared full POC scope: it does not imply every product is unusable. Review blockers against the agreed scope.

## NTP targets

The [Datadog NTP integration](https://docs.datadoghq.com/integrations/ntp/) documents private cloud-provider servers when available, otherwise `0.datadog.pool.ntp.org` through `3.datadog.pool.ntp.org`. NTP ignores HTTP proxy settings. This checker tests the four public fallback pools by default, independently of the selected Datadog site. It does not detect cloud providers or read customer Agent/OS NTP configuration.

Replace the public pools with the actual customer targets when appropriate:

```bash
bash dd-network-check.sh --site us1 --ntp-host ntp.internal.example --ntp-host 192.0.2.10
```

Up to eight distinct hostname or unbracketed IPv4/IPv6 targets are accepted on UDP/123. For the one-command invocation, append `-- --site us1 --ntp-host HOST`. Explicit targets receive no public fallback. Default pool failures have informational WARN impact because the Agent may use a different server; an explicit customer target is required and failure blocks readiness. Missing `timeout`, `dd`, or `od` skips NTP with WARN impact and never fabricates a pass. These are one-off connectivity probes; avoid continuously scanning public NTP pools.

## RUM and wildcards

RUM intake, quota, Browser Logs, and applicable `sdk-configuration` endpoints are **SERVER-SIDE SANITY CHECK ONLY**. A VM PASS does not validate an end-user's DNS, firewall, FortiGate, Zscaler, browser security product, CSP, SDK configuration, or corporate proxy. RUM failure alone does not block server readiness. RUM Remote Configuration is marked NOT APPLICABLE on government sites because its documentation explicitly excludes them.

The [Agent Network Traffic documentation](https://docs.datadoghq.com/agent/configuration/network/) specifies `*.agent.<site>` for firewall inclusion, and [RUM Remote Configuration](https://docs.datadoghq.com/real_user_monitoring/remote_configuration/) specifies a regional browser-intake wildcard covering intake and `sdk-configuration` requests. These are configuration instructions, so the checker stores the applicable patterns as TXT guidance and in JSON `allowlist_requirements`. They are excluded from JSON `endpoints`, terminal rows, progress totals, category counts, REVIEW counts, readiness, and exit codes. No literal wildcard is queried or replaced with an invented sample hostname. The checker tests the documented concrete destinations, including the current versioned Agent app/flare hostnames and mapped RUM intake, `sdk-configuration`, quota, and logs hostnames. Connection success does not verify wildcard firewall configuration.

By default, each scan discovers the latest stable Agent release from [Datadog's official latest release](https://github.com/DataDog/datadog-agent/releases/latest), even if an older Agent is installed. A HEAD request follows at most three HTTPS redirects, with a five-second connection timeout and a twelve-second total limit. Only an exact official release URL with a stable `X.Y.Z` tag is accepted. The checker probes the documented `X-Y-Z-app.agent.<site>` and `X-Y-Z-flare.agent.<site>` hostnames without installing the Agent. `--agent-version X.Y.Z` takes precedence over `DD_PREFLIGHT_AGENT_VERSION`; either bypasses the lookup and can target a planned or installed version when GitHub is unavailable. If lookup fails or returns no supported version, both versioned entries remain REVIEW and the terminal, TXT, and JSON reports explain why. The source (`latest-release`, `flag`, `environment`, or `none`) is shown alongside the Agent version.

## Proxy behavior and privacy

Startup inspects uppercase/lowercase HTTP_PROXY, HTTPS_PROXY, NO_PROXY and ALL_PROXY. Values are entirely withheld, including NO_PROXY, to avoid exposing credentials or internal network names. curl honors existing proxy settings and exclusions; uppercase HTTP_PROXY alone is ignored by curl and does not configure an HTTPS proxy. DNS, raw TCP and OpenSSL are direct diagnostics. NO_PROXY can cause individual curl requests to bypass a configured proxy; proxy presence alone does not establish the route used.

No proxy configuration is changed. curlrc is disabled so user options cannot inject credentials, output paths or insecure settings. An inherited `SSLKEYLOGFILE` is suppressed for curl and OpenSSL probe children to prevent TLS-secret logging. No API key, payload, cookies, verbose transcript, raw response body, proxy URL, or Agent configuration is stored. Reports still contain hostnames, OS, DNS answers, certificate metadata and network results: treat them as internal operational information.

## Dependencies and reports

Required: Bash 4+, curl, and ordinary Linux utilities (`awk`, `sed`, `grep`, `head`, `tee`, `wc`, `tr`, `date`, `hostname`, `mktemp`, `mkdir`, `mv`, `rm`, `rmdir`, `dirname`, `uname`). Expected: `getent`. Optional: `dig`, `nslookup`, `openssl`, `timeout`, `dd`, `od`. `nc` availability is displayed but it is not needed. No jq, yq or Python runtime dependency. On systems lacking `timeout`, only inherently bounded DNS tools and curl are used; detail stages are skipped.

TXT and JSON reports are automatically saved under `reports/` with host, UTC timestamp and a collision-resistant suffix. Files use a restrictive umask; the directory must be owned by the current user and must not be a symlink. Reports contain no ANSI colors. JSON schema version 1.4 (tool 0.1.8) includes metadata, site, dependency/proxy detection, categories, endpoint stages, certificate metadata, direct endpoint PASS/WARN/FAIL counts, allowlist requirements, untested requirements, blockers and overall status. Agent metadata also includes `agent_version_source` and `agent_version_detail` (empty when resolution succeeds). NTP metadata records `ntp_target_source`; `ntp_result` records status, detail, IP, version, stratum, leap indicator, Kiss-o'-Death code, target source and attempt history. Each endpoint has a `redirect_host` field (empty if no redirect); TXT includes a `Redirect host` line. HTTP numeric metadata is represented as strings, with empty strings for unavailable values. `http_result` describes the original endpoint; `http_result.redirect_result` holds follow-up status, URL, IP, TLS result, redirect count and elapsed time. `attempts` arrays retain bounded HTTP/TLS probe histories. Summary blockers include the failure reason, not just a status code. Interrupted runs leave private intermediate files under `.run-*`; these are incomplete and must not be treated as final reports.

Illustrative excerpt (not evidence about your VM):

```text
trace.agent.datadoghq.com - APM traces
DNS              PASS - getent/NSS exit 0
CNAME            PASS - CNAME chain observed; each hop queried
TCP              PASS - 2 successful, 0 failed address probes; direct path
TLS              PASS - Direct SNI, hostname and certificate chain verified
HTTP             PASS - Endpoint reachable; application-level response received; environment route
http_status      403

Documented firewall allowlist patterns (configuration guidance; excluded from test results and readiness):
  *.agent.datadoghq.com
  *.browser-intake-datadoghq.com

Overall: READY WITH WARNINGS
```

## Sources, maintenance and tests

**Last verified against Datadog docs: 2026-09-29.** The manifest is a reviewed snapshot, not a live discovery service. Review it before each POC/release and periodically as Datadog changes destinations. See [endpoint provenance and update instructions](docs/ENDPOINTS.md) for exact sources, schema, site exceptions and exclusions.

The Agent/RUM wildcard distinction was checked again on 2026-10-03 using Context7 and the official documentation source. This was a targeted review, not a refresh of the entire manifest.

Run the offline suite on Linux with `bash tests/run.sh` (Python 3 is needed only for tests). It runs ShellCheck if already available and never installs it. See [test strategy](docs/TESTING.md) for opt-in real network tests. Context7's official curl documentation was consulted for curlrc suppression, proxy behavior, redirect restrictions, and certificate verification.

See the [validation record and real sample output](docs/VALIDATION.md) for completed test results and development-machine scan evidence.

MIT licensed. This is an independent internal diagnostic tool, not a Datadog product or a guarantee of service readiness.
