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
bash -c 's=$(SSLKEYLOGFILE= curl -qfsSm60 https://raw.githubusercontent.com/avecenabasuni/datadog-network-check/main/dist/dd-network-check.sh) || exit 3; exec bash -c "${s:-exit 3}" -- "$@"'
```

Select a Datadog site when prompted; the **entire scan** runs automatically. The generated single-file distribution includes every runtime module and both manifests. No clone, unpacking, package installation, API key, or product selection is needed. Runtime requirements remain Bash 4+, curl and the standard Linux utilities listed below; Python and Git are not required on the customer VM.

The download completes successfully before execution begins. The compact `-qfsSm60` options disable curlrc, reject HTTP download errors, show errors without a progress meter, and cap the entire transfer at 60 seconds. The URL is HTTPS with certificate verification enabled; redirects are not followed. Download failures or empty responses exit 3 without starting a scan. Standard input stays connected to the terminal for site selection. Existing proxy settings are honored; TLS debug-secret logging is suppressed for the download process.

**Reports are saved in `./reports/` under the directory where you run the command**, even if no repository checkout exists. The downloaded program and embedded manifests stay in memory; no installation or temporary extraction directory is created. Generated TXT/JSON files and exit codes are the same as local execution.

The URL above runs the current `main` version and requires outbound access to `raw.githubusercontent.com` in addition to the Datadog destinations being tested. For a reviewed immutable version, replace `main` in the URL with a full Git commit SHA from this repository. If GitHub access is unavailable, transfer the reviewed `dist/dd-network-check.sh` file through your approved channel and run `bash dd-network-check.sh`; it also works without companion files. Remote execution trusts this repository and GitHub's HTTPS delivery; the embedded source digest is build provenance, not an independent signature.

For unattended execution, append `-- --site us1` after the closing quote of the one-command invocation. With no arguments, interactive selection remains the default. See [distribution design and tests](docs/DISTRIBUTION.md).

## Run from a local checkout

Use a Linux VM with Bash 4+ and curl. Keep the project directories together, make the entry point executable if your distribution method did not preserve its mode, then run:

```bash
./dd-network-check.sh
```

Select US1, US3, US5, EU1, AP1, AP2, UK1, US1-FED, or US2-FED. The full scan starts immediately. No sudo is needed. The current user needs write access to this tool's `reports/` directory.

For automation, `./dd-network-check.sh --site us1` runs the same full scan. `--help` prints usage. `--quick` and `--category` are intentionally reserved for a future release; they currently return exit code 3 rather than silently reducing coverage.

The tool never installs software, changes configuration, restarts services, or sends telemetry payloads. **Its only filesystem writes are reports and private intermediate report files under `reports/`.** HTTPS GETs, DNS queries, TCP connections, and TLS handshakes generate normal network/server logs. Installation domains are probed at `/`; no installers or packages are downloaded or executed. An installed Agent's `version` command is optional and bounded; Agent configuration files are not read.

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
lib/{dns,tcp,tls,http}.sh    Independent diagnostics
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
3. **TCP:** direct connections to up to four resolved addresses, each with a five-second limit. IPv4 and IPv6 are supported. Any success with other failures is WARN, all failures are FAIL. Address sampling is disclosed. Without `timeout`, the raw TCP stage is skipped.
4. **TLS:** OpenSSL connects to the first reachable IP with SNI, hostname verification, certificate-chain verification and an eight-second limit. Subject, issuer, expiry and verification result are reported. Unknown issuers do not imply inspection. Missing OpenSSL, hostname-verification support, or `timeout` skips detailed inspection; curl still provides verified HTTPS evidence. OpenSSL and curl can have different trust stores.
5. **HTTP:** curl uses its environment-configured route, certificate verification, a five-second connect limit, a twelve-second total limit, and at most three HTTPS-only redirects. A GET with a byte range limits requested body size. Response capture is capped; raw bodies and headers are never written to reports. HTTP status, redacted final URL, remote IP, redirects, Server and Via are reported. URL paths, queries, fragments and userinfo are withheld because redirects can contain secrets. Any redirect warns, including expected CDNs, because allowlists may need its final destination.

All limits are at the top of `dd-network-check.sh`. Requests are sequential. A full scan can take several minutes, especially with failed or slow routes. A successful sampled address does not validate every current or future IP, both IP families, sustained availability, throughput, payload upload limits, or every API path/method. The script uses ordinary hostnames; it does not separately validate trailing-dot behavior used by newer Agents.

## Interpreting results

Per-test states are PASS, WARN, FAIL, SKIPPED, NOT APPLICABLE and NOT DIRECTLY TESTABLE. `ALLOWLIST REQUIREMENT` is a classification, not a passed test.

| Evidence | Interpretation |
|---|---|
| Verified HTTPS and HTTP 200/400/401/403/404/405 | Reachable; application response received |
| HTTP 5xx or proxy 407 | WARN; a service or proxy returned an error |
| Redirect or diagnostic body-size limit | WARN; partial or redirected evidence requires review |
| TLS/DNS/TCP failure, reset, timeout, no HTTP response | FAIL for the affected stage |
| Vendor plus explicit denial/filter wording | WARN: POSSIBLE SECURITY FILTERING; not definitive proof |
| Generic “access denied”/“blocked” wording | WARN; may be an ordinary application rejection |
| Optional detailed test unavailable | SKIPPED; coverage warning |
| Wildcard/version/port requirement without concrete target | NOT DIRECTLY TESTABLE; coverage warning |
| Windows-only, excluded traffic, or site excluded by manifest | NOT APPLICABLE; neutral in aggregation |

A body-size cap is a deliberate exception: if TLS was verified and HTTP headers arrived, curl exit 63 is a warning. Curl metadata is captured separately from the bounded response sample, so large bodies cannot discard the HTTP status or actual exit code. On older curl versions, closing the sample pipe can produce exit 23; that becomes a warning only when the independent response-sample byte count confirms the limit was reached. Other write errors and transport failures remain failures even if an earlier response arrived. Missing diagnostic metadata is reported as SKIPPED, never as a fabricated curl exit code or a proven network blocker. HTTP reachability cannot conclusively identify a transparent intermediary that presents a trusted certificate; block-page detection is only a conservative heuristic.

An endpoint's **status** is its worst stage result (FAIL, then WARN/SKIPPED/unverified, then PASS). Its **impact** determines readiness:

- Required server endpoints: any stage failure produces FAIL impact.
- Informational endpoints: failures remain visible, but impact is WARN. These include browser sanity checks, optional public-IP lookups, alternative registries, legacy API/flare and private-worker destinations, and conditional software/device inventory.
- If a proxy environment is configured and curl establishes verified HTTPS, direct-path failures produce WARN impact. They remain FAIL in the individual stages. This is route evidence, not confirmation that the Agent uses the same proxy. The script does not infer exact proxy selection from environment presence.
- Unverified wildcard/manual requirements and skipped diagnostics produce WARN impact. They can never become PASS merely because a related hostname resolves.
- Category status is its worst endpoint impact. Excluded-only categories are PASS (no applicable blockers); their endpoint rows remain NOT APPLICABLE.

| Overall | Exit code | Rule |
|---|---|---|
| READY | 0 | All applicable checks pass, no unresolved coverage requirements |
| READY WITH WARNINGS | 1 | No FAIL impact, but at least one warning or unverified requirement |
| BLOCKED | 2 | At least one required endpoint has FAIL impact |
| Script/configuration/internal error | 3 | Invalid input, missing required tools, unsupported OS, report failure or interrupted scan |

**The shipped full manifest normally cannot reach READY**, because wildcard coverage and non-HTTPS/manual requirements cannot be proven automatically. READY WITH WARNINGS is intentionally not an unconditional all-clear. BLOCKED refers to the declared full POC scope: it does not imply every product is unusable. Some listed server features may be unnecessary for a particular POC; review blockers against the agreed scope.

## RUM and wildcards

RUM intake, quota, Browser Logs, and applicable `sdk-configuration` endpoints are **SERVER-SIDE SANITY CHECK ONLY**. A VM PASS does not validate an end-user's DNS, firewall, FortiGate, Zscaler, browser security product, CSP, SDK configuration, or corporate proxy. RUM failure alone does not block server readiness. RUM Remote Configuration is marked NOT APPLICABLE on government sites because its documentation explicitly excludes them.

`*.agent.<site>` and applicable `*.<RUM domain>` are reported separately as **ALLOWLIST REQUIREMENT / NOT DIRECTLY TESTABLE**. No literal wildcard is queried. For installed stable Agent releases, the documented `<version>-app.agent.<site>` and `<version>-flare.agent.<site>` convention is used. Unknown/prerelease versions remain untested. No Agent is installed, and resolving the parent domain never satisfies a wildcard.

## Proxy behavior and privacy

Startup inspects uppercase/lowercase HTTP_PROXY, HTTPS_PROXY, NO_PROXY and ALL_PROXY. Values are entirely withheld, including NO_PROXY, to avoid exposing credentials or internal network names. curl honors existing proxy settings and exclusions; uppercase HTTP_PROXY alone is ignored by curl and does not configure an HTTPS proxy. DNS, raw TCP and OpenSSL are direct diagnostics. NO_PROXY can cause individual curl requests to bypass a configured proxy; proxy presence alone does not establish the route used.

No proxy configuration is changed. curlrc is disabled so user options cannot inject credentials, output paths or insecure settings. An inherited `SSLKEYLOGFILE` is suppressed for the curl child to prevent TLS-secret logging. No API key, payload, cookies, verbose transcript, raw response body, proxy URL, or Agent configuration is stored. Reports still contain hostnames, OS, DNS answers, certificate metadata and network results: treat them as internal operational information.

## Dependencies and reports

Required: Bash 4+, curl, and ordinary Linux utilities (`awk`, `sed`, `grep`, `head`, `tee`, `wc`, `tr`, `date`, `hostname`, `mktemp`, `mkdir`, `mv`, `rm`, `rmdir`, `dirname`, `uname`). Expected: `getent`. Optional: `dig`, `nslookup`, `openssl`, `timeout`. `nc` availability is displayed but it is not needed. No jq, yq or Python runtime dependency. On systems lacking `timeout`, only inherently bounded DNS tools and curl are used; detail stages are skipped.

TXT and JSON reports are automatically saved under `reports/` with host, UTC timestamp and a collision-resistant suffix. Files use a restrictive umask; the directory must be owned by the current user and must not be a symlink. Reports contain no ANSI colors. JSON schema version 1.0 includes metadata, site, dependency/proxy detection, categories, endpoint stages, certificate metadata, allowlist requirements, untested requirements, blockers and overall status. HTTP numeric metadata is represented as strings, with empty strings for unavailable values. Interrupted runs leave private intermediate files under `.run-*`; these are incomplete and must not be treated as final reports.

Illustrative excerpt (not evidence about your VM):

```text
trace.agent.datadoghq.com - APM traces
DNS              PASS - getent/NSS exit 0
CNAME            PASS - CNAME chain observed; each hop queried
TCP              PASS - 2 successful, 0 failed address probes; direct path
TLS              PASS - Direct SNI, hostname and certificate chain verified
HTTP             PASS - Endpoint reachable; application-level response received; environment route
http_status      403

*.agent.datadoghq.com - Agent metrics and flare allowlist
Classification   ALLOWLIST REQUIREMENT
DNS              NOT DIRECTLY TESTABLE - Manual review required; no network probe issued

Overall: READY WITH WARNINGS
```

## Sources, maintenance and tests

**Last verified against Datadog docs: 2026-09-29.** The manifest is a reviewed snapshot, not a live discovery service. Review it before each POC/release and periodically as Datadog changes destinations. See [endpoint provenance and update instructions](docs/ENDPOINTS.md) for exact sources, schema, site exceptions and exclusions.

Run the offline suite on Linux with `bash tests/run.sh` (Python 3 is needed only for tests). It runs ShellCheck if already available and never installs it. See [test strategy](docs/TESTING.md) for opt-in real network tests. Context7's official curl documentation was consulted for curlrc suppression, proxy behavior, redirect restrictions, and certificate verification.

See the [validation record and real sample output](docs/VALIDATION.md) for completed test results and development-machine scan evidence.

MIT licensed. This is an independent internal diagnostic tool, not a Datadog product or a guarantee of service readiness.
