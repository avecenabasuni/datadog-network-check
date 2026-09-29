# Single-command distribution

The primary command is in [README](../README.md#run-with-one-command-recommended). It fetches one complete, self-contained Bash artifact over HTTPS and executes it in a child Bash with terminal input preserved. The compact `curl -qfsSm60` options put `-q` first to disable curlrc, use `-f` to reject HTTP error responses, use `-sS` to show errors without a progress meter, and use `-m60` to cap the whole transfer at 60 seconds. Unlike endpoint probes, artifact downloads must reject HTTP error responses. The canonical URL is HTTPS and redirects are deliberately not followed, so there is no redirected protocol to configure. Certificate verification remains enabled.

Command substitution is checked before any downloaded code is executed. Failed transfers, including a partial response followed by a nonzero curl exit, never launch the payload. An empty successful response is also rejected. There is no `curl | bash` pipeline consuming the menu's standard input. The child's exit code is preserved: 0, 1, 2 or 3 from the checker; download failures are mapped to 3. Arguments can be forwarded after `--`, but the default requires none.

`${s:-exit 3}` supplies an error-only program when a successful download is empty. `SSLKEYLOGFILE=` applies only to the downloader to prevent inherited TLS debug logging. The shorter command uses one total timeout instead of separate connection/transfer limits and omits the old download-size flag; the checked-in bundle still has a build-time size ceiling. The VM does not write the downloaded program to disk.

## Bundle architecture

`dist/dd-network-check.sh` is a generated and committed artifact. The source of truth remains `dd-network-check.sh`, `lib/*.sh`, and `config/*.conf`.

The deterministic Python standard-library builder:

1. Verifies the expected entry-point module list and replacement anchors.
2. Inlines those exact modules in the original load order.
3. Replaces the two manifest file inputs with quoted here-documents containing their exact source records. Manifest contents are data, never shell-expanded or evaluated.
4. Uses the caller's working directory as the report root and invokes `main` directly, including when run through `bash -c`.
5. Adds a digest of source paths and normalized source contents, rejects delimiter collisions, and enforces a bundle-size ceiling below Linux's per-argument execution limit.

No module download, runtime archive extraction, temporary source file, dependency installation, or customer-side Python/Git is involved. Existing report-directory protections apply. Local checkout behavior is unchanged; standalone reports live in the invocation directory's `reports/`.

## Maintenance

After changing any runtime module, main script or manifest:

```bash
python3 -B scripts/build_standalone.py
bash tests/run.sh
```

Commit the updated bundle alongside the source changes. `tests/run.sh` first checks that the distribution is fresh and parses as Bash. A stale bundle fails the suite. `python3 -B scripts/build_standalone.py --check` performs a read-only freshness check.

The README defaults to the moving `main` branch for convenient distribution. An engineer can substitute a reviewed full commit SHA for repeatable execution. SHA-pinning selects a reviewed repository version; the embedded source digest detects build drift and is not a signature or a separate trust anchor. GitHub access and its certificate chain are distribution prerequisites, distinct from the Datadog network results. In restricted environments, distribute the same single file offline.

## Verification

Distribution regression tests exercise the exact README command with a mock downloader, including failed/partial/empty downloads, argument forwarding, preserved terminal input, all checker exit codes, and a full bundled interactive scan with deterministic network responses. The full-scan test runs in a directory without `config/` or `lib/`, parses the final JSON, compares its entire endpoint ID inventory against the source manifest, and verifies that only `reports/` was created. No external calls are made by these tests.

Curl command behavior was reviewed with Context7 against the official [curl option syntax](https://github.com/curl/curl/blob/master/docs/cmdline-opts/_OPTIONS.md) and [curl FAQ](https://github.com/curl/curl/blob/master/docs/FAQ.md): short options can be grouped, `-q` must come first to disable curlrc, and redirects require `-L`. The compact command deliberately omits `-L`.
