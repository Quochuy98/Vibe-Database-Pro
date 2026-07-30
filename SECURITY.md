# Security Policy

DataForge handles database credentials, privileged connections and potentially destructive data operations. Security and data-safety reports are treated as high priority.

## Reporting a vulnerability

Please use a private GitHub Security Advisory for this repository when available. If private advisories are unavailable, open a minimal issue asking for a private channel; do not include secrets, customer data or an exploit that exposes a live database. The maintainer will provide an encrypted contact path.

Include, where safe:

- affected commit/version and platform;
- feature/adapter and configuration prerequisites;
- concise reproduction steps using a disposable test database;
- security impact and whether confidentiality, integrity, availability or data safety is affected;
- logs or traces only after removing credentials, tokens, connection strings, query parameters, row data, private keys and personal paths.

Do not test against production, shared staging, another person’s database, or a service you do not own. Stop testing if a real credential or user data is encountered and report the exposure without copying it.

## High-priority report classes

- credential or secret persistence/leakage;
- TLS certificate/hostname or SSH host-key verification bypass;
- SQL injection or generated-operation injection;
- wrong-row update, read-only bypass, hidden commit, unsafe retry or destructive-confirmation bypass;
- malicious import/export path, formula, archive or native-tool command execution;
- unbounded allocation/queue/result stream or cancellation failure;
- unsigned/compromised update, helper or dependency;
- unauthorized plugin, telemetry or crash-data collection.

## Response goals

These are planning targets until an on-call process exists:

| Severity | Acknowledge | Triage target | Release action |
| --- | --- | --- | --- |
| Critical | 1 business day | 2 business days | Stop affected writes/updates/automation; emergency fix and regression evidence |
| High | 2 business days | 5 business days | Disable or constrain affected capability; patch before next release |
| Medium | 5 business days | 10 business days | Schedule with owner and expiry; document residual risk |
| Low | 10 business days | Next planning review | Track and address according to impact |

Actual commitments, security contacts and supported versions must be updated before public release.

## Disclosure and credits

We coordinate a fix, regression test, dependency update or mitigation, release notes and disclosure timeline with the reporter. We credit reporters only with permission. Never publish proof-of-concept data containing real credentials or database contents.

## Security development requirements

- Secrets live in macOS Keychain, never source, Git, UserDefaults, SQLite metadata, exports, logs, crash reports, analytics, snapshots or long-lived clipboard.
- TLS validation and SSH host-key verification are enabled by default; there is no global insecure bypass.
- Structured logs are redacted before serialization; diagnostics/crash/telemetry are previewable and opt-in.
- Native tools use direct argument vectors and restricted temporary files, never shell interpolation.
- Dependencies require license, maintenance, Apple Silicon, binary-size, transitive and advisory review; SBOM and secret scanning are release gates.
- Database writes and destructive operations require context, classification, preview/confirmation, transaction policy, cancellation and rollback/partial-outcome tests.

See [SECURITY_THREAT_MODEL.md](docs/SECURITY_THREAT_MODEL.md), [DATABASE_SAFETY.md](docs/DATABASE_SAFETY.md), [RISKS.md](docs/RISKS.md) and [AGENTS.md](AGENTS.md) for the full planning contract.
