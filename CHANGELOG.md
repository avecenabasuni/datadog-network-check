# Changelog

## Unreleased

- Tool 0.2.0 adds interactive and CLI proxy routing for every HTTPS probe and Agent version lookup, optional Basic authentication via hidden prompt/stdin, and forced direct mode. Explicit proxy readiness uses CONNECT/TLS/HTTP evidence independently of direct diagnostics. JSON schema 1.5 adds route and CONNECT metadata. NTP remains direct. Proxy settings and credentials are process-local and withheld from reports. The standalone bundle budget is 120,000 bytes, below Linux's per-argument limit.
- Tool 0.1.8 explains recovered NTP warnings as a reply after an earlier address failed, retaining each attempt and server metadata. Prepare spinner frames before starting the helper and reset its signal traps to default, avoiding a reproduced Bash trap parser error and shutdown hang during frame rendering.
- Tool 0.1.7 shows successful NTP endpoints as compact rows, consistent with other passing endpoints. Only WARN/FAIL rows show an NTP note. TXT and JSON retain full reply details.
- Tool 0.1.6 fixes terminal warning attribution: a successful registry redirect no longer hides TCP/DNS/TLS warnings, and origin retry warnings retain the endpoint row. All visible terminal text uses periods instead of semicolons. The TTY spinner now refreshes every 120 ms during foreground probes, is stopped and reaped before results, and restores the cursor on normal exit or interruption. Probes remain sequential in the parent shell.
- Add direct UDP/123 NTP probes for the four documented Datadog public fallback pools. Validate matched replies and report timeout, invalid-response, unsynchronized-server and Kiss-o'-Death results. Repeatable `--ntp-host` replaces pools with required customer targets; default pool failures remain informational. NTP ignores HTTP proxies and needs no Python or package installation. Tool version is 0.1.5; additive JSON schema 1.4 records NTP results, history and target provenance.
- Treat generic denial wording such as `Access Denied` as a report note, preserving PASS for verified HTTPS reachability. This removes the false connectivity warning on RUM Remote Configuration S3/CloudFront 403 responses. Vendor-plus-denial signatures, service/proxy errors, retries, and transport/TLS failures retain their existing impact.
- Show Proxy, Tools, Scope, and Agent on separate terminal lines, including wrapped output on narrow terminals.
- Default to the latest stable Agent release from the official GitHub release redirect instead of detecting a local installation. Explicit flag/environment version overrides still take precedence and avoid GitHub access.
- Probe both versioned Agent destinations after successful lookup. Keep them in REVIEW with a reported reason if discovery fails; record version source and lookup detail in JSON metadata.
- Keep documented Agent/RUM wildcard firewall patterns as TXT/JSON guidance, outside endpoint tests and terminal rows. They no longer add REVIEW counts, category warnings, readiness warnings, or exit-code changes. Concrete hostnames from the docs are tested normally.

## 0.1.4 — 2026-09-30

### Changes that can alter PASS/WARN/REVIEW totals

- A registry endpoint's single verified redirect now passes when its final host matches the observed expected-host map: `registry.datadoghq.com` to `docs.datadoghq.com`; `gcr.io`, `eu.gcr.io`, `asia.gcr.io`, and `us-docker.pkg.dev` to `accounts.google.com`; and `docker.io` to `www.docker.com`. These were previously WARN. An unexpected host remains WARN with a proxy or captive-portal note. When registry redirects were the only warnings, the same environment can now return exit 0 instead of 1; the meanings of exit codes are unchanged.
- Known stable Agent versions now turn the two versioned app and flare requirements from REVIEW into direct probes. Their results can be PASS, WARN, or FAIL and can therefore change category totals and the overall exit code. Version detection uses `--agent-version`, `DD_PREFLIGHT_AGENT_VERSION`, `datadog-agent version`, `dpkg -s datadog-agent`, then `rpm -q datadog-agent`. The wildcard requirement remains REVIEW.
- Without a known Agent version, both versioned requirements remain REVIEW. A proposed sample 7.x hostname was not used because its DNS resolution could not be verified with `dig` in the development environment. No sample result is counted as tested.

### TXT and JSON changes

- JSON schema version is **1.3**, up from 1.2. Every endpoint now has a top-level `redirect_host` string; it is empty when no redirect host is available.
- Each TXT endpoint record now includes `Redirect host`, showing `none` when unavailable. The Agent version header now records the version source. Both report formats record tool version 0.1.4.

### Terminal presentation

- Endpoint rows and category headings stream as checks run. Interactive color terminals show one temporary progress footer; Ctrl-C clears it and restores the cursor.
- Rows use aligned stage columns, middle-shortened names with a full-name continuation only when narrow, and complete short notes. Category totals moved to the boxed summary.
- Expected registry redirect hosts share one allowlist note. The summary groups WARN/FAIL by category, keeps REVIEW under manual review, lists other-requirement descriptions, and prints complete report filenames below one directory line. New report filenames use a six-character random suffix instead of eight.
- The standalone bundle was regenerated from source. Six offline terminal captures cover color, `NO_COLOR`, ASCII locale, 50 columns, piped output, and Ctrl-C.
