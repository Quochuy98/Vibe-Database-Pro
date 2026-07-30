# Test Strategy

Status: Proposed quality contract

Last updated: 2026-07-29

Owners: Quality Engineering with feature, Database Core, macOS and Security owners

## 1. Objective

Tests must prove that DataForge is safe and correct under success, failure, cancellation, concurrency, partial progress and malicious input. A green narrow suite cannot support a broad capability claim. Production and shared staging databases are never automated-test targets.

The repository has no production implementation. A separately scoped
`spikes/ffi-streaming` artifact has its own evidence runner; its pass/fail
results do not establish production capability. The commands and suites below
remain future production gates unless an exact command is recorded as run.

## 2. Quality principles

- Every production change includes happy path, failure, edge and cancellation tests where applicable.
- Every database write includes success, failure and rollback/partial-outcome tests.
- Every bug fix first adds a regression that demonstrates the old failure.
- Capabilities are tested as contracts; UI cannot expose unsupported/conditional behavior.
- Safety/security assertions are never weakened or skipped to make CI pass.
- Timeouts are product behavior and deadlines, not flaky-test concealment.
- Tests use deterministic clocks, seeds, fixtures, locale/timezone and bounded resources where relevant.
- Logs, snapshots and failure output are seeded-secret scanned.
- Performance is measured in release-like builds on named hardware; unit timing is not a performance claim.

## 3. Test layers

| Layer | Primary responsibility | Typical scope | Required on |
| --- | --- | --- | --- |
| Rust unit/property/fuzz | Parser/classifier, types, diff, generation, stream/backpressure, redaction | Pure core/adapter logic with fakes | Every relevant PR; fuzz nightly/continuous |
| Swift unit | Application service state, persistence, Keychain mapping, presentation models, theme/accessibility rules | No live DB/UI where avoidable | Every relevant PR |
| FFI contract | ABI/version, ownership, error, panic, stream, thread, cancel | Swift facade + Rust fake adapter | Every FFI change; release full matrix |
| Adapter conformance | Driver/server semantics, capability truth, TLS, transactions, cancellation, types | Disposable engine fixtures | Adapter PR subset; nightly/full release matrix |
| Integration/workflow | Cross-module operation and persistence/Keychain/file behavior | App services + core + disposable dependencies | Relevant PR and nightly |
| UI/snapshot/accessibility | User flows, keyboard/focus, warnings, grid/editor, Light/Dark/contrast | Built macOS app with controlled services | Relevant UI PR; nightly matrix |
| Security | Trust, hostile input/server, leakage, update/signature, command/path injection | Unit through release artifact | Security PR/nightly/release |
| Performance/soak | Budgets, leaks, backpressure, interruption, long-run stability | Release build and named datasets | Baseline PR when sensitive; scheduled/release |
| Distribution | Signing, Hardened Runtime, notarization, updater, helper identity | Final nested artifact on clean Macs | Release candidate |

## 4. Unit and property tests

### 4.1 Rust core

Required domains:

- SQL tokenization, statement boundaries and destructive classification by dialect;
- generated SQL quoting, binding, deterministic output and migration dependency ordering;
- normalized data types plus lossless engine descriptor mapping;
- schema/data diff, rename-proposal uncertainty and type mapping;
- capability snapshots and stale/unknown/conditional policy;
- connection configuration validation and secret-free debug output;
- typed error mapping and structured redaction;
- bounded channel/page/chunk/cache behavior and cancellation state machine;
- CSV/TSV escaping and spreadsheet formula-injection policy;
- untrusted CSV/JSON/XML/XLSX/archive parsing limits;
- row identity and optimistic-concurrency planning;
- import/export/transfer checkpoint and partial-outcome models.

Property tests generate Unicode/reserved identifiers, quotes/delimiters/comments, null/empty/not-loaded values, numeric boundaries, timestamps/time zones, deep/nested documents within limits, random chunk boundaries and concurrent cancel/release orderings.

Fuzz targets include statement parser/classifier, result decoders, identifier/literal handling, import parsers, metadata decoders, FFI buffer validation, archive paths and redaction schemas. A crash, panic, unbounded allocation or timeout on a minimized input is a failing security test.

### 4.2 Swift application and presentation

- use-case state transitions and cancellation propagation;
- MainActor isolation and no database/file work initiated from view rendering;
- connection environment/read-only/production policy presentation;
- transaction and pending-edit close warnings;
- workspace draft/restoration without silently restoring live sessions;
- Keychain reference CRUD/error mapping and non-`Codable` secret model checks;
- SQLite migrations, rollback/corruption/retention/deletion;
- command enablement driven by capabilities and revalidation failure;
- theme cascade, contrast warnings, non-color indicators and visible-cell-only invalidation;
- error messages contain consequence/action but no raw driver stack/secret;
- diagnostics preview bytes equal exported bytes.

## 5. FFI verification

The C ABI suite is independently release-blocking. It covers:

- exact ABI version/feature handshake and incompatible pair rejection;
- fixed-width record layout/size/alignment on supported architectures;
- null, malformed length, unknown enum, stale/invalid handle and allocation-failure behavior;
- caller-owned destination lifetime, idempotent release, double release, use
  after terminal, stale-generation and leak detection;
- panic containment for every exported entry point;
- pull/ack streaming with row and byte limits under a slow/failed consumer;
- callback ordering, documented executor, reentrancy and no UI mutation off MainActor;
- cancel before start, during driver wait, during chunk, after terminal and concurrent with release;
- typed error fidelity and seeded-secret redaction;
- one-million-row bounded-memory run and large-cell deferred behavior.

Use Address/Thread sanitizers where supported, Rust sanitizing/interpreter tools where practical, and a test-only fake adapter so rare ordering/error paths are deterministic. No borrowed lifetime or pointer crosses the boundary.

## 6. Disposable database infrastructure

### 6.1 Isolation

Preferred infrastructure is pinned container images in an isolated CI network. Local execution may use Docker-compatible tooling, but commands must name a test profile and never default to a real endpoint.

Each run receives:

- unique test run ID and database/schema/container names containing `dataforge_test`;
- deterministic fixture and engine/version/TLS/auth configuration;
- per-run credentials generated by CI and never echoed;
- network isolation and explicit port mapping;
- cleanup on success/failure/cancel with an orphan reaper;
- image digest/provenance and license review.

### 6.2 Destructive guard

Before any destructive fixture setup, require all of:

- explicit `DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1` set by the test launcher;
- host/container identity on an allowlist (`localhost`/CI isolated network), never arbitrary URL;
- target database/schema prefix `dataforge_test_`;
- expected disposable marker table/value created in the same run;
- environment classification `test` and no production/staging tag;
- CI secret scope specific to test infrastructure.

Any mismatch aborts without cleanup SQL. Test code never prints the environment or connection string.

### 6.3 Engine matrix

| Milestone | Engines | Matrix dimensions |
| --- | --- | --- |
| M2 | PostgreSQL | oldest supported/current; TLS valid/bad CA/hostname/client cert; password/auth modes in scope; high latency/interruption |
| M3 | MySQL | oldest/current; auth plugin; TLS; charset/collation; storage engine/transaction/implicit commit |
| M3 | MariaDB | separate oldest/current; auth/TLS; JSON/type/dialect/capability differences |
| M3 | SQLite | minimum/current system/bundled policy; read-only/read-write; WAL/journal; external file change/corruption |
| M6 | SQL Server, Redis, MongoDB | only after individual support policy and fixture threat review |

Never broaden “supported versions” beyond the matrix that passes.

## 7. Adapter conformance scenarios

Each declared capability maps to a stable test ID and evidence:

- valid/invalid config, connect, auth failure, timeout, disconnect, graceful close, reconnect policy;
- TLS trust/hostname/custom CA/client certificate and no global bypass;
- SSH valid/unknown/changed host key, agent/key/password/jump host as scoped, cancellation and no direct fallback;
- lazy metadata, limited privilege, quoted/unicode objects, refresh/invalidation and bounded large schema;
- query/script success, syntax/constraint/auth/network errors, warnings/messages, multiple results;
- typed streaming, slow consumer, row/byte limit, deferred BLOB, server interruption;
- cancellation outcome and connection/transaction usability afterward;
- begin/commit/rollback/savepoint, aborted/lost state, implicit DDL commit semantics;
- generated SQL snapshot and semantic execution;
- edit exactly one keyed row, insert/delete, conflict, zero/multiple affected, rollback and no-key read-only;
- capability denied/conditional/unknown never shown as supported;
- import/export/transfer/diff/backup scenarios only when the capability is in phase.

## 8. End-to-end workflows

High-value integration flows:

1. Create profile → Keychain save → test connection → connect → lazy browse → disconnect/cleanup.
2. Production profile → destructive statement → analysis → typed confirmation → target recheck → execute/audit.
3. Query with million-row fixture → bounded visible pages → load more/export → cancellation.
4. Begin transaction → write → close tab warning → rollback/keep open; repeat with lost connection/unknown outcome.
5. Edit keyed row → preview → concurrent server update → optimistic conflict → preserve pending edit.
6. Table without unique identifier → grid remains read-only and explains why.
7. Theme/palette change while scrolled with selection/pending edit → visible cells update only and state remains.
8. Schema/data compare → target changes after preview → apply blocked as stale.
9. Malicious import/archive/spreadsheet fixture → bounded failure/no traversal/no formula injection/no partial write beyond policy.
10. Export cancellation/disk-full/overwrite → atomic or clearly marked/cleaned artifact.
11. Tunnel failure → DB operation fails and tunnel closes; no direct fallback.
12. Restore/privilege/kill-session flows → capability/permission/confirmation and partial consequence handling.

## 9. UI, keyboard and accessibility tests

Use stable accessibility identifiers for controls, not localized visible strings as selectors. Test:

- connection, query execution, result grid, edit apply/rollback and export flows;
- destructive query and production confirmations, including shortcut paths;
- transaction/pending-edit close protection and workspace restoration;
- loading, empty, error, cancellation and partial-result states;
- full keyboard navigation, focus order, menu commands, standard shortcuts, context menu and undo/redo;
- VoiceOver labels/roles/value/action for icon buttons, tree, editor, table, warnings and progress;
- Light/Dark, Increase Contrast, Differentiate Without Color and Reduce Motion;
- resize, minimum usable size, multi-window, tab restoration and long/localized text;
- data-type style groups, primary/foreign/generated/NULL/modified traits with icon/text/tooltip fallback;
- selection/scroll/pending-edit persistence across theme changes.

Snapshot tests cover controlled appearance matrices but do not replace semantic accessibility/UI tests. Snapshot fixtures never contain real data, credentials or production screenshots.

## 10. Security tests

The threat IDs in [SECURITY_THREAT_MODEL.md](SECURITY_THREAT_MODEL.md) map to tests. Required suites include:

- Keychain storage/ACL/locked/denied behavior and no plaintext fallback;
- seeded secret scan across SQLite, UserDefaults, exports, logs, crash payload, diagnostics, snapshots, temp files, process arguments and clipboard lifecycle;
- valid/invalid/expired/mismatched TLS certificate, custom CA scope and bypass absence;
- SSH unknown/changed host key, known-host policy, jump-host isolation and tunnel cleanup;
- malicious database server frames/metadata/lengths/type values, bounded allocation and no panic;
- SQL injection in generated operations and identifier/literal quoting;
- path traversal/symlink race, archive/ZIP bomb, XXE, deep JSON, malformed XLSX/CSV and encoding attacks;
- spreadsheet formula injection round trip;
- native-tool command/argument/environment injection and malicious filenames;
- secure temporary permissions, atomic write and error cleanup;
- update feed/artifact tamper, downgrade/replay/channel/signature/helper identity;
- dependency advisory/license/SBOM/provenance and secret scanning;
- plugin loading absent in MVP; future unsigned/unauthorized capability requests denied;
- telemetry/crash fresh install sends no data; opt-out immediately stops future sends.

## 11. Performance and reliability tests

Use the named datasets and budgets in [PERFORMANCE_BUDGET.md](PERFORMANCE_BUDGET.md). Scenarios include:

- cold/warm launch and window restoration;
- high-latency connect and metadata lazy load;
- 10 MB/100 MB SQL files and incremental edit/completion latency;
- 1M/10M streamed rows, 500-column wide table, large JSON and deferred 100 MB BLOB;
- large schema/object tree and 5,000-table ER model;
- import/export/transfer throughput with slow disk/network/consumer;
- schema/data diff memory and runtime;
- repeated connect/cancel/close, 8-hour stream/monitoring soak and leak checks;
- cancellation under slow server, blocked socket, full queue and connection interruption.

Measurements use release builds, fixed fixtures, clean machine state, signposts/profilers and recorded hardware/OS/compiler/commit. Regressions beyond threshold block unless a reviewed baseline change explains product impact.

## 12. CI and release gates

### 12.1 Planned PR gates

Once manifests/configuration exist, the repository should run commands equivalent to:

```bash
swiftformat --lint .
swiftlint
xcodebuild build -scheme DataForge -destination 'platform=macOS'
xcodebuild test -scheme DataForge -destination 'platform=macOS'
cargo fmt --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo deny check
cargo audit
```

The exact checked-in commands, schemes, toolchain versions and lockfiles become authoritative; this list is not executable until scaffolding is separately approved.

PR selection uses a dependency-aware test map but always runs safety classifier, redaction, FFI smoke and relevant adapter contract tests when those shared boundaries change.

### 12.2 Nightly

- full disposable engine/version/TLS/auth matrix in scope;
- fuzz/property corpus and sanitizers;
- UI appearance/accessibility/keyboard matrix;
- security hostile-input/server/leak suites;
- million-row/large-schema and selected performance baselines;
- orphan fixture cleanup and dependency/SBOM refresh.

### 12.3 Release candidate

- clean build from pinned source/toolchain and locked dependencies;
- all unit/FFI/adapter/integration/UI/security/performance suites;
- `arm64` slice for MVP (Universal slices only after a superseding release decision);
- nested code signature/designated requirement/entitlement verification;
- Hardened Runtime, notarization, stapling and Gatekeeper clean-machine install;
- update valid/tamper/downgrade/rollback/channel tests;
- crash/telemetry consent payload inspection;
- license notices, SBOM, provenance, checksums, secret scan and signed release evidence.

## 13. Flake, quarantine and skip policy

- A failing safety/security/correctness test blocks; it is not retried until green as a substitute for diagnosis.
- A test can be quarantined only with an issue, owner, expiry, failure evidence and risk approval; quarantine cannot make the affected capability releasable.
- Never increase timeout without measuring the expected operation and retaining a cancellation/deadline assertion.
- Tests using real time/network randomness require controllable substitutes or documented bounded integration conditions.
- Removed/weakened assertions require the same review as production behavior change.

## 14. Test data policy

- Synthetic deterministic data only; no production dumps or customer screenshots.
- Credentials are obvious canaries such as generated `DF_TEST_SECRET_<run-id>` supplied through protected CI channels and never printed.
- PII-like fixtures are fictional and labeled.
- Large fixtures are generated deterministically or stored with license/provenance/checksum; avoid bloating Git.
- Failure artifacts are bounded, redacted, access-controlled and retention-limited.

## 15. Traceability and evidence

Before implementation, each backlog item must be assigned stable test IDs.
The current planning backlog records required test categories in prose and
DF-M0-001 records its spike test evidence separately. Each capability must link
to conformance tests, each threat to controls/tests and each performance budget
to benchmark jobs before its milestone gate. Release evidence records commit,
toolchains, dependency lock/SBOM, fixture image digests, commands,
pass/fail/skip list and artifact signatures.

“Pass” may be reported only for commands actually run. If infrastructure prevents a suite, the completion report states the exact unrun tests, reason, remaining risk and reviewer command.

## 16. Quality definition of done

- Required success/failure/edge/cancellation/rollback/security tests exist and pass.
- Test scope matches the claimed capability, engine/version and architecture surface.
- No production/shared staging database or real credential/data was used.
- Formatter/linter/build warnings and static/security findings are resolved or explicitly release-blocking.
- Bounded resource and performance evidence meets budget.
- No seeded secret appears in any artifact.
- Documentation, capability matrix, threat/safety/risk registers and release evidence are current.
- Unverified behavior remains explicitly unsupported/conditional, never labeled complete.
