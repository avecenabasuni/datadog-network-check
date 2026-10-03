# Endpoint review and manifest maintenance

Last verified against Datadog docs: **2026-09-29**.

Targeted Agent/RUM wildcard review: **2026-10-03**, using Context7 and the official sources. Network Traffic describes concrete versioned app/flare destinations and a wildcard firewall inclusion instruction. RUM Remote Configuration describes wildcard allowlisting covering intake and `sdk-configuration` requests. The checker treats those instructions as documentation notes rather than endpoint tests.

## Sources and precedence

Targeted NTP review: **2026-10-03**, using Context7's Datadog NTP overview and troubleshooting references, then the official Agent implementation and RFC 5905. Private cloud servers may be selected by the Agent; the checker tests documented public fallback pools unless explicit customer targets replace them. It does not infer effective Agent/OS NTP configuration.

- [Agent Network Traffic](https://docs.datadoghq.com/agent/configuration/network/): primary destination inventory, installation domains, Agent version convention, site-gated DBM/EUDM, outbound ports, optional public-IP services and Operator registries.
- [Datadog Sites](https://docs.datadoghq.com/getting_started/site/): nine site parameters.
- [RUM](https://docs.datadoghq.com/real_user_monitoring/): explicit intake and Browser Profiling quota tables, including both government sites.
- [RUM Remote Configuration](https://docs.datadoghq.com/real_user_monitoring/remote_configuration/): SDK configuration subdomain, wildcard guidance, explicit government exclusions.
- [Logging endpoints](https://docs.datadoghq.com/logs/log_collection/#logging-endpoints): HTTPS Agent/custom forwarding and browser logging, linked from Network Traffic.
- [Official documentation region configuration](https://github.com/DataDog/documentation/blob/master/hugo/assets/scripts/config/regions.config.js): resolves placeholders in the rendered Network Traffic page, particularly `agent_http_endpoint`, `http_endpoint`, and `browser_sdk_endpoint_domain`.
- [Network Traffic source](https://github.com/DataDog/documentation/blob/master/hugo/content/en/agent/configuration/network.md): verifies site-region guards that are hidden in static text extraction.
- [NTP integration](https://docs.datadoghq.com/integrations/ntp/): four public fallback hosts, cloud-private preference, custom configuration and lack of HTTP proxy support.
- [Agent NTP implementation](https://github.com/DataDog/datadog-agent/blob/main/pkg/collector/corechecks/net/ntp/ntp.go): NTPv3 default, five-second timeout and UDP/123.
- [RFC 5905](https://www.rfc-editor.org/rfc/rfc5905.html): server response fields, origin matching, synchronization and Kiss-o'-Death responses.

Network Traffic uses JavaScript-populated site placeholders. A blank hostname suffix in a text-only scrape is not a real endpoint. Review the rendered site variants and the official region mappings. Prefix expansion in this manifest is limited to conventions actually documented by these sources.

## Coverage decisions

| Documented destination/requirement | v0.1 treatment |
|---|---|
| Linux installation domains | Required HTTPS tests of domain roots; no installers fetched |
| windows-agent.datadoghq.com | NOT APPLICABLE on Linux |
| Metrics / metadata / flare version domains | Latest stable Agent release by default, or explicit flag/environment override; concrete app/flare probes; REVIEW only if the version cannot be determined |
| `*.agent.<site>` | TXT/JSON documentation guidance; never probed or counted as an endpoint, REVIEW, or warning |
| API, trace, logs, process, orchestration, container images/lifecycle, profiling, telemetry, RC, LLM, SBOM, NDM/SNMP/flows/Network Path | Required server HTTPS tests; process destination also covers USM/cloud network monitoring |
| Software inventory and end-user-device intake | Included as conditional informational tests. The network page groups these under End User Device Monitoring; platform/feature applicability is not established by domain reachability |
| DBM and software/device inventory on government sites | NOT APPLICABLE to this documented scan: Network Traffic restricts these entries to commercial sites. This is not an assertion that the product never exists there; region config separately contains DBM hostnames. Resolve this documentation discrepancy with Datadog before extending government scope |
| Private Synthetic worker intakes | Informational conditional outbound destinations; the VM may host a private worker. Modern workers use intake.synthetics; intake-v2 is legacy |
| Legacy app API | Informational, only relevant to old Agents |
| IP ranges | Fetch root endpoint; no firewall changes or automatic CIDR expansion |
| Browser RUM, Browser Logs, quota | Informational SERVER-SIDE SANITY CHECK ONLY |
| RUM sdk-configuration | Official subdomain combined with explicit RUM origin mapping; informational on commercial sites, explicitly unsupported on government sites |
| RUM wildcard | TXT/JSON documentation guidance, excluded from test results and readiness; normalize regional wording with the explicit site mapping; the apex intake has its own concrete probe |
| Network Path third-party IP-discovery services | Informational optional feature, Agent 7.75+; a failure does not block core readiness |
| Container registries | Informational alternatives depending on selected registry. No image pulls/authentication tested; registry redirects may require additional hosts |
| UDP NTP/123 | Validated direct NTP probes to four documented public fallback pools; informational impact. `--ntp-host` replaces them with required customer targets. Agent/OS/cloud server selection is not detected |
| TCP/8443 custom autoscaling, TCP/8042 RC development probe | Manual on US1/EU1 where listed; primary page supplies ports without concrete hostnames. Never guess a hostname or test these as HTTPS/443 |
| Deprecated TCP/HIPAA logs | Unsupported legacy transport excluded; supported HTTPS logs tested |
| Lambda-only logging | NOT APPLICABLE TO SERVER-SIDE PREFLIGHT from a Linux application VM |
| Public Synthetic source ranges, webhook source ranges | NOT APPLICABLE TO SERVER-SIDE PREFLIGHT; these describe traffic originating elsewhere |
| Agent inbound receiver/debug/IPC ports | NOT APPLICABLE TO SERVER-SIDE PREFLIGHT; not outbound Datadog destinations |

SBOM is the security-specific hostname in the primary page. Security telemetry can also use shared Agent/logs/process destinations. No separate guessed security hostname was added. PrivateLink endpoint overrides, custom proxies, integration-specific third-party APIs, customer overrides and undocumented CDN/backend names are not exhaustively inventoried by this release.

## Manifest schema

Both manifests are plain UTF-8, LF-terminated, pipe-separated records. They are parsed as data, never sourced or evaluated. Blank lines and lines beginning `#` are allowed. Pipes/newlines are not allowed inside a field.

`sites.conf`: `code|label|site_parameter|rum_domain`.

`endpoints.conf` has exactly thirteen fields:

```text
id|category|label|hostname_template|port|protocol|applicable_os|test_type|requirement|sites|path|notes|source
```

- `id`: unique lowercase letters, digits, underscores or hyphens.
- `category`: stable machine key; grouping is derived from it.
- `hostname_template`: literal documented hostname, or `{site}`, `{rum}`, `{version}` substitutions. Only `wildcard` records can start with `*.`. Manual/excluded entries may use descriptive placeholders and are never queried.
- `port`: 1–65535. Active probes use HTTPS, or UDP/123 with `test_type=ntp`; manual records also represent TCP/UDP.
- `applicable_os`: `all`, `linux`, `windows`, or `desktop` (reserved for explicitly desktop-only records).
- `test_type`: `full`, `server_sanity_only`, `wildcard`, `version`, `ntp`, `manual`, `excluded`. Applicable `wildcard` records supply TXT/JSON guidance without endpoint results or readiness impact. `ntp` requires UDP/123; other active types require HTTPS. NTP CLI overrides are validated data, never evaluated as shell code.
- `requirement`: `required` blocks when failed; `informational` caps impact at WARN.
- `sites`: `all` or comma-separated site codes. A site exclusion is visible in the report.
- `path`: conservative absolute URL path without credentials/query strings. Default `/`.
- `notes`: applicability, caveats and derivation; use `-` if empty.
- `source`: official source URL.

The required header `# last_verified_against_datadog_docs=YYYY-MM-DD` is copied into reports. Validation rejects malformed fields, unknown enum values, duplicate IDs, invalid hostnames/ports, unsupported active protocols, unknown site references and executable-looking hostname text before any network probes.

## Update procedure

1. Review all nine site variants on Network Traffic and Sites. Inspect the official page source/region config when placeholders or feature gates are ambiguous.
2. Compare each destination section, the outbound-port table, and the registry section with the manifest. Follow relevant links for logs/RUM rather than guessing their domains.
3. Check RUM intake/quota mappings and Remote Configuration site availability independently. A generic `*.browser-intake-<DC_REGION>-datadoghq.com` pattern cannot encode EU or government mappings by itself.
4. Add or adjust records with a concrete source, OS/site scope, requirement policy and explanatory note. Use manual/excluded records for requirements that cannot be tested or should not originate here.
5. Update the verification-date headers in both manifests and this documentation. Do not update the date without reviewing the sources.
6. Run `bash tests/run.sh`, adjust the inventory-count assertion if records changed, and run opt-in live smoke tests. Inspect TXT/JSON for affected sites. Never interpret a successful DNS lookup as evidence a guessed hostname is official.
7. Ask the POC owner/network team to review unverified allowlist/port requirements and conditional product scope. A scan does not authorize firewall changes.
