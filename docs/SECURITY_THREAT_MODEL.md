# Security Threat Model

Status: Proposed baseline for Milestone 0

Owner: Security Engineering

Last reviewed: 2026-07-30

## 1. Scope and assumptions

This document defines the security and privacy baseline for DataForge for macOS. It is a planning contract, not evidence that controls have been implemented.

The system in scope is:

```text
SwiftUI/AppKit UI
    -> Swift application services and domain interfaces
    -> versioned C ABI v1 and Swift concurrency wrapper
    -> Rust core and capability-based database adapters
    -> database drivers -> remote/local databases

Supporting boundaries:
    macOS Keychain          secrets
    local SQLite/GRDB       non-sensitive metadata only
    TLS                     direct database transport boundary
    SSH                     optional tunnel/host-trust boundary; disabled until adopted
    user-selected files     import/export/backup/restore
    signed update service   Direct distribution only
    opt-in diagnostics      explicit preview before upload
```

Planning assumptions:

- The provisional deployment target is macOS 14 or later; it must be reassessed against `current/current-2` before public launch.
- MVP release artifacts are Apple Silicon (`arm64`) only. Source and contracts remain portable; Universal 2 requires a superseding distribution decision, Intel hardware/CI, driver/helper parity and separate security/performance evidence.
- The primary distribution channel is direct distribution with Developer ID, Hardened Runtime and notarization. A Mac App Store build is a separate feasibility track, not a build flag assumed to be equivalent.
- Plugins are not in MVP. Any future plugin host is out of process and denied secrets, files and network access until a capability is granted.
- PostgreSQL, MySQL, MariaDB and SQLite are the MVP adapter scope. Capabilities, not engine names, determine available operations.
- Database servers, imported files, update infrastructure, diagnostics endpoints and dependency artifacts are untrusted until verified.

## 2. Security objectives and non-negotiable invariants

1. A credential exists at rest only in macOS Keychain, never in SQLite, `UserDefaults`, logs, crash payloads, exports, fixtures or source control.
2. TLS certificate-chain and service-identity validation are enabled by default. There is no global “ignore TLS errors” switch.
3. SSH verifies host keys against an explicit known-host policy. A changed host key fails closed and requires an informed user decision.
4. UI code cannot call a database driver, build a connection string, or generate dialect SQL directly.
5. Internal SQL uses parameter binding for values and adapter-owned identifier quoting. User SQL is never concatenated into internal control queries.
6. Unknown or partially parsed SQL is not considered safe; it receives the most restrictive applicable policy.
7. Long-running work has a bounded queue, timeout and cancellation token. Panic or undefined ownership cannot cross the FFI boundary.
8. Imported content, server metadata and error messages remain data; they never become shell, SQL, XML entity, rich-text, URL or file-path instructions without validation.
9. Every executable is signed. Release updates are authenticated independently of transport and reject downgrade or replay.
10. Telemetry and crash upload are off until the user explicitly opts in. A diagnostics bundle is local and previewable before any upload.

Apple documents Keychain as storage for small secrets and cryptographic keys in [Keychain Services](https://developer.apple.com/documentation/security/keychain-services/). Apple trust evaluation is represented by [SecTrustEvaluateWithError](https://developer.apple.com/documentation/security/sectrustevaluatewitherror%28_%3A_%3A%29); implementations must perform equivalent chain and service-identity validation even when Rust TLS is used. TLS identity rules should be checked against [RFC 9525](https://datatracker.ietf.org/doc/html/rfc9525), and the SSH transport/host-key contract against [RFC 4253](https://datatracker.ietf.org/doc/html/rfc4253).

## 3. Assets and data classification

| Class | Assets | Storage/transit rule |
| --- | --- | --- |
| Secret | Database passwords, access/refresh tokens, SSH passphrases and private keys, client-certificate private keys, update signing keys | Keychain or dedicated offline release key store; short-lived memory only; never diagnostics or export |
| Sensitive data | Query text, parameters, result rows, schema names, hostnames, usernames, file paths, clipboard content, audit metadata | Local by default; encrypted transport; explicit export; redact diagnostics |
| Integrity-critical | Generated SQL, migration plans, row identity/version tokens, adapter capability manifests, binaries, appcast/update metadata, dependency locks | Versioned, deterministic, signed or checksummed as applicable; review before execution |
| Availability-critical | Connection/session state, transaction state, cancellation handle, pending edits, recovery drafts, job checkpoints | Bounded persistence; crash-safe writes; clear lifecycle and cleanup |
| Public | Product documentation, public keys, release notes | Integrity remains required even when confidentiality is not |

Secrets are modeled as handles across layers. A Swift `SecretReference` may identify a Keychain item; the Rust core receives secret bytes only for the narrow operation and must zero or drop buffers promptly where the language/runtime allows. Secret-bearing types must not conform to generic persistence or debug-description protocols.

## 4. Actors

- **Authorized user:** may intentionally execute powerful operations; mistakes and misunderstood scope are part of the threat model.
- **Local unprivileged attacker:** has access to the same account, clipboard history, logs, temp locations or process observation opportunities.
- **Malicious or compromised database server:** controls protocol frames, metadata, errors, certificates and result sizes.
- **Malicious or compromised SSH server/agent:** controls SSH frames, rekey,
  host identity, auth responses, agent messages and tunnel timing.
- **Network attacker:** can intercept, delay, replay, redirect or modify traffic but does not initially hold trusted signing keys.
- **Malicious file author:** supplies crafted import, workspace, backup or restore input.
- **Compromised dependency/build/update operator:** can attempt to inject code or replace release artifacts.
- **Malicious future plugin:** has code execution in its own constrained process and seeks capability escalation.
- **Support/diagnostics recipient:** is authorized to receive a user-approved bundle but should not receive database content or credentials.

## 5. Trust boundaries and entry points

| Boundary | Untrusted inputs | Required crossing control |
| --- | --- | --- |
| UI -> application service | User SQL, identifiers, paths, confirmation, settings | Typed commands, validation, authorization state, cancellation context |
| Swift -> C ABI -> Rust | Handles, buffers, callbacks, errors, cancellation | ABI version negotiation, explicit ownership, length limits, panic containment, thread contract |
| Adapter -> driver/server | Frames, metadata, result rows, notices, TLS identity | Capability check, protocol/library validation, bounds, timeouts, streaming and backpressure |
| App -> Keychain | Secret values and lookup metadata | Least-accessible item class that meets UX, scoped service/account keys, status checking, deletion |
| App -> local SQLite/files | Workspace, history, imports, exports, temporary data | No secrets, permissions, canonical paths, atomic write, size/depth limits, user approval |
| App -> native database tool/helper | Executable and arguments, environment, file descriptors | Trusted bundled/user-selected executable, argv API without a shell, minimal environment, signed helper |
| Adapter -> TLS/database endpoint | Certificate chain, hostname, custom CA, database frames | Chain/hostname validation, per-connection CA scope, protocol bounds and no global bypass |
| Tunnel provider -> SSH server/agent/process | Per-hop host key, auth challenge, agent response, tunnel bytes and process lifecycle | Bounded known-host/auth policy, no shell, no direct fallback, deadlines and explicit resource ownership |
| App -> updater | Appcast, archive, release notes | HTTPS plus signed metadata/archive, Developer ID verification, notarization, version monotonicity |
| App -> diagnostics service | Redacted events, crash/minidump, system metadata | Opt-in, local preview, allowlist schema, retention notice, deletion control |
| Main app -> future plugin | Messages and granted resources | Out-of-process isolation, signed package, versioned RPC, per-capability authorization |

## 6. Threat analysis

Each threat has an owner who must turn the controls and verification items into backlog work. “Residual risk” is what remains after those controls operate correctly.

### T01 — Credential theft

- **Assets:** database/SSH passwords, tokens, private-key passphrases, client private keys and Keychain item identifiers.
- **Actors:** local attacker, malicious dependency/plugin, compromised diagnostics operator.
- **Trust boundaries:** UI/application service, Keychain, Swift/Rust ABI, process memory, export/diagnostics.
- **Abuse path:** a broadly serializable connection model persists a password; a debug description or memory dump includes a secret; an overly broad Keychain access group lets another component retrieve it.
- **Controls:** store only opaque `SecretReference` values outside Keychain; narrow Keychain access groups; fetch on demand; never make secret types `Codable`, printable or equatable by value; minimize copies and lifetime; clear paste fields and temporary buffers where feasible; exports omit secrets by construction; helpers receive one-use secret material through a protected IPC channel, never argv/environment.
- **Verification:** unit tests reject secret fields in persisted/export schemas; canary-secret scans cover logs, crash fixtures, diagnostics bundles and snapshots; entitlement inspection verifies access groups; memory-lifetime review covers FFI and helpers; delete/rotate flows have integration tests.
- **Residual risk:** a compromised user account or process with equivalent rights may access live secrets; memory clearing is best effort with managed/runtime copies. Document this limit and prefer short-lived tokens where supported.

### T02 — Malicious database server

- **Assets:** app integrity/availability, local files, credentials, user attention, result memory.
- **Actors:** hostile server owner or compromised database/proxy.
- **Trust boundaries:** driver protocol, TLS, adapter normalization, FFI, UI rendering.
- **Abuse path:** malformed or oversized frames trigger driver/FFI bugs; metadata or error text becomes a path/URL/markup action; endless rows exhaust memory; authentication challenge causes unintended credential disclosure.
- **Controls:** maintained drivers selected after security/license review; strict frame/field/row/depth limits; bounded streaming channels; lazy BLOB fetch; sanitize and render server strings as plain text; do not auto-open links/files; negotiate only expected authentication mechanisms; scope credentials to the selected endpoint; isolate protocol parsing from UI; catch Rust panics before FFI; timeout and cancellation.
- **Verification:** protocol fuzzing and malformed-frame corpora; fake-server tests for oversized metadata, infinite result streams and auth downgrade; memory ceilings; FFI sanitizer runs where available; UI tests prove metadata remains inert.
- **Residual risk:** driver/parser zero-days remain possible. Rapid dependency response, kill switches for affected adapters and signed emergency releases are required.

### T03 — Man-in-the-middle

- **Assets:** credentials, query/result confidentiality and transaction integrity.
- **Actors:** network attacker, compromised proxy or DNS path.
- **Trust boundaries:** direct TLS, SSH tunnel, proxy/jump host.
- **Abuse path:** attacker redirects a host, presents an untrusted certificate, strips encryption where the protocol permits, or intercepts direct traffic after tunnel failure.
- **Controls:** TLS required/preferrable policy is explicit per adapter and defaults to verified encryption for remote presets; validate chain and hostname; support user-selected custom CA per connection; show negotiated security state; bind connection identity to host/port/database; never silently downgrade; SSH failure never falls back to direct connection.
- **Verification:** disposable TLS endpoints exercise valid, expired, wrong-host, unknown-CA, changed-CA and downgrade cases; packet-level assertions verify no credentials precede authenticated transport; tunnel-failure test verifies fail-closed behavior.
- **Residual risk:** a trusted but compromised CA or administrator-installed root can impersonate a server. Optional certificate pinning may be evaluated for high-assurance connections.

### T04 — SSH host impersonation

- **Assets:** database credentials and tunneled data.
- **Actors:** MITM, compromised bastion, local attacker modifying known-host metadata.
- **Trust boundaries:** SSH client, known-host store, jump-host chain, Keychain.
- **Abuse path:** first connection accepts an attacker key without context, changed keys are auto-accepted, or one jump-host decision is reused for a different host.
- **Controls:** explicit trust-on-first-use dialog with host, port, algorithm and fingerprint; known-host entries are scoped and integrity-protected; changed/revoked keys fail closed; support managed pre-provisioned fingerprints; validate every hop independently; do not accept weak/unknown algorithms without a reviewed compatibility policy; private keys remain Keychain/user-selected files with permission checks.
- **Verification:** integration tests for first use, exact match, rotation, mismatch, hashed host, multiple ports and multi-hop; UI tests require deliberate acceptance and make changed-key state non-bypassable by a generic confirmation.
- **Residual risk:** users can approve an attacker on first use. Managed pin import and out-of-band fingerprint guidance reduce but do not remove this risk.

### T05 — Certificate-validation bypass

- **Assets:** all TLS-protected credentials and data.
- **Actors:** user under time pressure, network attacker, developer accidentally shipping debug behavior.
- **Trust boundaries:** connection settings, TLS adapter, persisted metadata.
- **Abuse path:** a global “trust all” setting or persisted bypass disables chain/hostname checks across connections; debug trust code reaches production.
- **Controls:** no global bypass; custom CA is the supported recovery path; any exceptional compatibility override, if product review permits one, is one connection plus one session, requires typed confirmation, never disables hostname validation silently, expires on disconnect and is marked in every window; compile-time/release test rejects permissive trust callbacks.
- **Verification:** static rule and unit test find unconditional trust; release configuration test exercises invalid chains; persistence migration test proves override is not stored; screenshot/UI test verifies persistent warning.
- **Residual risk:** an explicitly accepted bad certificate can expose a session. The preferred release policy is to omit bypass entirely until a concrete interoperability case is reviewed.

### T06 — SQL injection in internal query generation

- **Assets:** database confidentiality/integrity and privilege boundary.
- **Actors:** malicious server metadata, crafted import/mapping names, user-supplied identifiers.
- **Trust boundaries:** application service, normalized schema, dialect adapter, driver.
- **Abuse path:** table/column name or value is concatenated into metadata, CRUD, diff, backup-control or monitoring SQL and changes statement meaning.
- **Controls:** bind every value; represent identifiers as validated typed components and quote through the active adapter; use structured SQL builders/AST where available; never accept a pre-quoted identifier; generated SQL passes the same risk classifier and is previewed for writes; capability-specific templates live only in adapters; least-privilege test roles.
- **Verification:** property tests across quoting edge cases and Unicode; malicious identifier fixtures for every dialect; snapshot/semantic tests for generated SQL; integration tests verify the intended object alone changes. Follow the primary defenses in the [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html).
- **Residual risk:** server-side dynamic SQL inside stored procedures is outside client control; show generated calls and do not imply safety beyond the client-generated statement.

### T07 — Malicious CSV/JSON/XML/XLSX input

- **Assets:** app availability/integrity, local files and target database.
- **Actors:** malicious file author or compromised download source.
- **Trust boundaries:** file picker, import parser, preview, mapping, batch writer.
- **Abuse path:** decompression bomb, oversized field/nesting, malformed encoding, XML external entity, crafted archive entry, parser bug or misleading type inference causes resource exhaustion, file disclosure or unintended writes.
- **Controls:** treat formats by verified content and explicit user choice; stream parse; cap compressed/uncompressed size, expansion ratio, row/column/field/nesting depth and error count; disable DTD/external entity/network resolution; validate XLSX ZIP entries and relationships; canonicalize paths; preview inferred types and target mappings; transactional batch policy with cancel/rollback; quarantine incomplete staging files.
- **Verification:** fuzz each parser; corpus includes zip bombs, XXE, traversal names, invalid UTF, huge numbers, deep JSON, oversized cells and malformed shared strings; memory/time budgets; integration tests cover partial failure and rollback.
- **Residual risk:** parser-library zero-days remain. Parser dependencies need fast patch ownership and imports should run in a constrained worker when feasible.

### T08 — Spreadsheet formula injection on export

- **Assets:** recipient workstation/data and product trust.
- **Actors:** malicious database row author.
- **Trust boundaries:** result row, export formatter, spreadsheet application.
- **Abuse path:** a cell beginning with a formula trigger is opened by a spreadsheet and executes/exfiltrates according to that application's behavior.
- **Controls:** provide explicit “CSV for spreadsheet” and “raw data CSV” modes; spreadsheet mode neutralizes formula-leading cells after trimming relevant control characters, quotes per CSV rules and records the transformation; XLSX writes strings as string cells, never formulas, unless the user explicitly creates a formula export feature; warn that raw mode preserves potentially active content. There is no universal downstream-safe CSV transformation, as noted by [OWASP CSV Injection](https://owasp.org/www-community/attacks/CSV_Injection).
- **Verification:** golden tests for `=`, `+`, `-`, `@`, tabs, CR/LF, quotes, delimiters and Unicode lookalikes; open exported fixtures in supported spreadsheet applications during release QA; round-trip raw mode separately.
- **Residual risk:** spreadsheet applications differ and may change behavior. The UI must state the selected compatibility policy and never label raw CSV as sanitized.

### T09 — Path traversal

- **Assets:** user files, app container, backup/export destinations.
- **Actors:** malicious archive/file author, hostile server-provided names.
- **Trust boundaries:** import archives, backup extraction, error-row export, temp-to-final move.
- **Abuse path:** `../`, absolute paths, symlinks, Unicode normalization or archive entries escape an approved root and overwrite/read another file.
- **Controls:** derive internal filenames from generated IDs; canonicalize destination and every entry; reject absolute, parent, device and symlink escapes; use file-descriptor-relative operations where possible; never use database object names as paths; require overwrite confirmation; use atomic finalization.
- **Verification:** table-driven traversal tests for separators, symlinks, case/Unicode variants and race attempts; assert all created paths remain under a per-operation root.
- **Residual risk:** filesystem races are possible when external tools operate on shared paths. Prefer private directories and pass already-open file descriptors when APIs support them.

### T10 — Unsafe temporary files

- **Assets:** secrets, query/result data, backups and local filesystem integrity.
- **Actors:** local attacker and another same-user process.
- **Trust boundaries:** import/export/backup workers and native tools.
- **Abuse path:** predictable names, permissive mode, symlink replacement or uncleared partial output exposes or overwrites data.
- **Controls:** create a unique private operation directory with owner-only permissions; use exclusive create, random names and atomic rename; do not put secrets in names/content; maintain cleanup manifests; encrypt sensitive backup artifacts when requested; delete partial files on error/cancel; never rely on `/tmp` naming alone. Use Foundation-managed replacement directories where appropriate; Apple documents `itemReplacementDirectory` in [FileManager](https://developer.apple.com/documentation/Foundation/FileManager/SearchPathDirectory/itemReplacementDirectory).
- **Verification:** permissions and symlink-race tests; crash-recovery cleanup test; cancellation test; scanner asserts no credential canary in temp roots.
- **Residual risk:** secure deletion cannot be guaranteed on modern copy-on-write storage. Minimize creation and disclose that deletion is logical, not forensic erasure.

### T11 — Command injection in native database tools

- **Assets:** local account, filesystem, database credentials and backup integrity.
- **Actors:** malicious input author, hostile database name/path, compromised tool binary.
- **Trust boundaries:** application service to `Process`/helper, environment, executable search path.
- **Abuse path:** interpolated shell command executes metacharacters; `PATH` resolves an attacker binary; secrets leak through argv/environment/process list.
- **Controls:** never invoke a shell; select a signed, allowlisted executable by canonical absolute URL; pass a structured argv array with per-option validation; minimal fixed environment and working directory; send secrets via protected descriptor/stdin or tool-supported credential file with owner-only permissions; capture bounded output with redaction; verify tool version/capability; no automatic privilege elevation.
- **Verification:** injection corpus across every argument; tests replace `PATH` and working directory; process inspection asserts no secret argv/environment; signature/hash and version mismatch tests fail closed. General interpreter-boundary guidance is in the [OWASP Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Injection_Prevention_Cheat_Sheet.html).
- **Residual risk:** an official native tool may itself be vulnerable or interpret a value unexpectedly. Keep a tested compatibility allowlist and allow library-level fallback only when semantically safe.

### T12 — Secrets in logs

- **Assets:** all secrets and sensitive database content.
- **Actors:** local reader, support recipient, log collector.
- **Trust boundaries:** every component to structured logger and diagnostics export.
- **Abuse path:** full connection URLs, parameters, row values, headers or debug descriptions enter a persistent log.
- **Controls:** allowlist event schemas; opaque operation/connection IDs instead of values; centralized redaction in Swift and Rust; never log full SQL parameters/rows/clipboard; classify fields at type level; bounded local retention; release builds disable unsafe tracing; adapters map raw errors to redacted typed context.
- **Verification:** canary corpus injected through connection, query, TLS/SSH, import and error paths; scan captured logs and signposts; schema test rejects unknown fields; manual release review of new event types.
- **Residual risk:** novel secrets may appear in server error text or query text. Default logs exclude both and user-added diagnostics notes are visibly outside the guarantee.

### T13 — Secrets in crash reports

- **Assets:** live process memory, credentials, SQL and result data.
- **Actors:** crash service operator, unauthorized support reader, compromised upload path.
- **Trust boundaries:** process to crash capture, local crash store, upload service.
- **Abuse path:** breadcrumbs, custom keys, stack locals or attachments contain sensitive values and upload without review/consent.
- **Controls:** crash reporting off by default; collect minimal stacks/build/runtime metadata; no heap dumps, SQL, row data, connection strings or attachment auto-collection; scrub breadcrumbs through the same logger; separate consent from telemetry; disclose recipient and retention; offer local deletion and per-report preview where the SDK permits.
- **Verification:** intentional crashes with credential canaries in recent operations; inspect exact outbound payload in a test endpoint; consent-state tests; privacy review before SDK/version changes.
- **Residual risk:** native stack or OS crash data can include unexpected memory-derived text. Do not promise perfect redaction; minimize capture and treat reports as sensitive access-controlled data.

### T14 — Secrets in clipboard

- **Assets:** passwords, tokens, private keys, result data.
- **Actors:** clipboard history tool, another local app, accidental paste recipient.
- **Trust boundaries:** app to system pasteboard.
- **Abuse path:** convenient copy actions place credentials or bulk sensitive rows on a globally observable pasteboard for an indefinite period.
- **Controls:** no “copy password” by default; use secure text entry; credential reveal is explicit; copying a secret requires a warning and offers a short best-effort clear; tag app-owned content and clear only if unchanged; bulk row copy shows scope; never use clipboard as an interprocess secret channel.
- **Verification:** pasteboard tests cover ownership-change race and timeout; UI automation confirms no implicit credential copies; telemetry/log scans exclude pasteboard content.
- **Residual risk:** another app can read content immediately and clipboard managers may retain it. The warning must state that auto-clear cannot revoke prior reads.

### T15 — Untrusted plugin

- **Assets:** main-process integrity, secrets, files, network and database authority.
- **Actors:** malicious/compromised plugin author.
- **Trust boundaries:** plugin package/install, host RPC, capability broker.
- **Abuse path:** in-process code gains all app privileges, steals Keychain material or sends arbitrary queries.
- **Controls:** no plugin system in MVP; future plugins are signed, versioned and out of process; deny-by-default manifest capabilities; user-approved connection/file/network grants; no raw Keychain access; narrowly typed RPC; quotas/timeouts; crash isolation; revocation and compatible API version negotiation; adapter interface stability does not imply public plugin trust.
- **Verification:** adversarial plugin harness attempts filesystem/network/secret access, malformed RPC, replay, resource exhaustion and signature substitution; revocation tests; host crash-isolation tests.
- **Residual risk:** a user-granted high-power plugin can abuse that authority. Permissions need plain-language scope, activity visibility and one-click revocation.

### T16 — Compromised auto-update

- **Assets:** code execution on every installed client and release identity.
- **Actors:** compromised web/CDN/CI account, stolen signing key, malicious maintainer.
- **Trust boundaries:** release CI, signing/notarization, appcast/CDN, updater helper.
- **Abuse path:** attacker serves a replaced archive/feed, replays a vulnerable version, steals an update key or modifies release notes to redirect users.
- **Controls:** direct builds use Developer ID signing, Hardened Runtime and notarization; updater candidate is Sparkle 2 after dependency review, with HTTPS, EdDSA-signed archive, signed feed when operationally ready, pre-extraction verification, version/channel monotonicity and staged rollout; store Developer ID and EdDSA keys separately from hosting and ordinary CI; two-person release approval; verify final stapled artifact hash; Mac App Store builds use only Store updates. Sparkle's current security guidance recommends Developer ID signing plus EdDSA archive signatures in its [official documentation](https://sparkle-project.org/documentation/).
- **Verification:** tampered feed/archive, wrong key, expired/revoked signature, replay/downgrade, interrupted install and key-rotation drills; verify code signature, notarization ticket and updater signature on a clean Mac.
- **Residual risk:** compromise of multiple signing identities or an authorized malicious release can still succeed. Maintain revocation and emergency communication runbooks plus an offline recovery key plan.

### T17 — Supply-chain attack

- **Assets:** source, build environment, release artifact, user systems and database access.
- **Actors:** compromised dependency/registry, contributor account, CI action or build worker.
- **Trust boundaries:** GitHub pull request, package registries, toolchains, CI, release storage.
- **Abuse path:** dependency confusion/typosquat, mutable CI action, malicious transitive update, stolen maintainer token or unreproducible build inserts code.
- **Controls:** lock all Swift/Rust dependencies; allowlist registries/sources; review license, maintainership, advisories, macOS/arm64 support and transitive graph before adoption; pin CI actions to immutable commits; least-privilege short-lived CI credentials; protected branches and two-person review for dependencies/release files; advisory scanning; secret scanning; generate an SPDX SBOM; attest provenance where the repository plan supports it; archive checksums, build logs and notarization ID; documented replacement/kill-switch owner.
- **Verification:** dependency-diff gate, scheduled advisory scan, SBOM completeness check, clean-room release rebuild comparison where feasible, provenance verification and compromised-token tabletop. GitHub documents [dependency review](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-review) and [artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations); the SBOM format must conform to the selected published [SPDX specification](https://spdx.dev/specifications/).
- **Residual risk:** signed and reviewed upstream code may still be malicious or vulnerable. Minimize dependencies, isolate high-risk parsers/drivers and preserve an emergency rollback/removal path.

### T18 — Malicious SSH endpoint, agent or process integration

- **Assets:** database/SSH credentials, tunneled query/result data, process
  integrity, local sockets/files and app availability.
- **Actors:** malicious SSH/bastion server, compromised agent, local attacker
  controlling config/socket paths, vulnerable OS/dependency client.
- **Trust boundaries:** tunnel application service, per-hop trust store,
  Keychain/FFI secret lease, agent socket, SSH protocol parser, optional child
  process and database adapter tunnel lease.
- **Abuse path:** a server sends malformed/rekey frames to a vulnerable client;
  an agent returns oversized/malicious identities or signatures; a jump value
  becomes shell syntax; password/key material reaches argv/logs; a failed
  tunnel leaves tasks/listeners/processes or retries the remote DB directly.
- **Controls:** ADR-0012 keeps SSH disabled. A future candidate must pin a
  current exact source, authenticate every hop, reject unsupported trust/auth
  syntax, compile sensitive upstream logging out, use direct typed APIs/argv
  without shell execution, give the adapter only a loopback `TunnelLease`, and
  own every task/channel/socket/listener/process through terminal cleanup.
- **Verification:** hostile rekey/banner/packet/agent fixtures; exact/hashed/
  revoked/multi-port trust; key/agent/password canaries for the declared
  subset; shell-descendant and connector-level zero-direct traps; cancellation
  at each phase; post-cleanup resource counts; signed app/minimum-host/soak and
  current advisory checks. Never exercise a known vulnerable platform client
  against a malicious rekey fixture.
- **Residual risk:** protocol/library zero-days and a compromised trusted
  agent remain possible. Capability kill switch, rapid signed update and an
  SSH-disabled fallback posture are required.

## 7. Privacy and diagnostics design

### 7.1 Default state

- Telemetry: off.
- Crash upload: off.
- Diagnostics upload: none; the application creates only a local bundle after an explicit user action.
- Local structured diagnostic logs: rotate at the earlier of 7 days or 50 MiB by default.
- Dangerous-operation audit metadata: retain 90 days or 50 MiB by default, configurable downward and deletable immediately.
- Query history is a separate user feature, local only, with its own retention controls. It is never silently repurposed as telemetry.

### 7.2 Event allowlist

Permitted diagnostic fields are build/version, macOS version, architecture, anonymous operation ID, adapter family, capability name, duration bucket, bounded counts, typed error category, retryability, cancellation state and redacted internal context.

Prohibited fields are credentials, connection strings, usernames by default, raw hostnames/IPs, SQL text, SQL parameters, schema/object names, row/cell values, file contents, full paths, clipboard contents, private keys/certificates and environment variables. If support needs a prohibited field, the user must add it manually after the preview warns that it is not automatically redacted.

### 7.3 Diagnostics bundle flow

1. Generate a manifest locally with file names, sizes, collection time and reason.
2. Run structural redaction in Swift and Rust, then a canary/pattern scan.
3. Show a preview with per-file include/exclude and full deletion controls.
4. Export to a user-selected location using an atomic write; do not auto-upload.
5. If a future upload is offered, obtain separate one-time consent, use authenticated TLS, show recipient/retention and return a case ID.
6. Delete staging data on completion, cancellation or startup recovery.

### 7.4 User rights and operational access

- Settings provides “Delete history and diagnostics” without deleting Keychain credentials unless the user separately chooses “Forget credentials”.
- Product analytics cannot gate core functionality or be bundled into license checks.
- Support access is least privilege, audited and time bounded; production diagnostics are never copied into development fixtures.
- Privacy-impacting schema changes require Security/Privacy review and updated user-facing disclosure before release.

## 8. Control ownership and verification gates

| Gate | Required evidence | Owner |
| --- | --- | --- |
| Architecture | Boundary review; capability and FFI contracts; data-flow update | Principal Architect |
| Pull request | Threat-linked tests, secret scan, dependency/license diff, no unsafe logging | Feature owner + Security reviewer |
| Nightly | Parser/driver fuzz corpus, disposable TLS/SSH/database integration, leak scan | Security Engineering + QA |
| Release candidate | Entitlement diff, declared architecture slice check (`arm64` for MVP), Hardened Runtime, signatures, notarization, SBOM, update tamper suite | Release Engineering |
| Privacy release gate | Exact event/crash/diagnostics payload inspection and consent UI tests | Privacy owner |
| Incident response | Key revocation, adapter/update kill switch and notification tabletop within preceding 12 months | Security lead |

Any failed credential, trust-validation, update-authenticity, wrong-row write or destructive-operation safeguard test blocks release. No risk may be accepted silently; acceptance requires an owner, rationale, expiry date and reviewer.

## 9. External facts and review cadence

The platform and dependency facts cited here were checked against primary project/platform documentation **as of 2026-07-30**. They are not promises about future Apple policy or dependency behavior:

- Apple requires App Sandbox for Mac App Store submission: [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).
- Apple describes Developer ID, Hardened Runtime and notarization requirements for outside-Store software: [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- Hardened Runtime exceptions weaken individual protections and therefore require explicit review: [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime).
- Revalidate these facts, App Review Guidelines, updater documentation and all entitlement needs at each release candidate and whenever the deployment target, helper model or distribution channel changes.

## 10. Open security decisions

- Select and audit the Rust TLS trust integration, including how platform roots and per-connection custom CAs are represented without creating a global bypass.
- ADR-0012 adopts no SSH implementation. Reconsider exact `russh` or another
  candidate only after every host-key, auth, no-direct, cleanup, advisory,
  Keychain/FFI, distribution, minimum-host and soak re-entry gate passes; rerun
  the full matrix if Universal 2 is later approved.
- Decide whether high-assurance certificate/public-key pinning is a Pro policy feature or an all-edition safety feature; security controls must not be paywalled if their absence makes a connection unsafe.
- Validate that Sparkle 2 license, maintenance, signing workflow and helper entitlements meet release requirements before adoption; otherwise design a minimal signed-update service or use manual updates.
- Define the privacy jurisdiction, controller/contact and retention policy before collecting any opt-in crash or telemetry data.
