# DataForge for macOS — Product Specification

Status: Planning baseline

Version: 0.1

Last updated: 2026-08-01

Owners: Product, macOS, Database Core, Security, Quality Engineering

## 1. Document contract

This specification defines what DataForge must deliver and the evidence required before a feature is considered complete. It is not authorization to implement production code. Detailed phasing is in [FEATURE_MATRIX.md](FEATURE_MATRIX.md), interaction sequences are in [USER_FLOWS.md](USER_FLOWS.md), delivery gates are in [ROADMAP.md](ROADMAP.md), and independently reviewable work is in [BACKLOG.md](BACKLOG.md).

Phase labels have one meaning throughout the planning set:

| Phase | Meaning |
| --- | --- |
| MVP | M1–M3: a safe, coherent desktop client for PostgreSQL, MySQL, MariaDB, and SQLite after M0 discovery exits |
| Post-MVP | M4 professional data tools |
| Advanced | M5–M6 modeling, monitoring, and additional engines |
| Enterprise | M7 policy-heavy automation and operational controls |
| Deferred | Deliberately outside M0–M7 until a new decision record and capacity exist |
| Not recommended | Behavior that violates a safety, security, platform, or product invariant |

“Supported” always means an adapter has declared the capability and passed its conformance tests. The UI must not infer support from an engine name.

### 1.1 Repository assessment at planning start

The repository began at commit `6af6b9e` with only `AGENTS.md`,
`MASTER_PROMPT.md`, and a short planning-pack `README.md`. The planning
baseline then added the `docs/` tree and safeguards. It still has no production
app/module implementation. The separately authorized DF-M0-001 feasibility
spike was executed and then removed; its exact disposable source remains at
evidence commit `ce33ff1` and its durable result is recorded in
[ADR-0008](adr/0008-m0-ffi-spike-disposition.md). `.gitignore` excludes macOS
metadata, secret-bearing `.env` files, local diagnostics and build output.

Files read before planning changes: `AGENTS.md` (all 787 lines), `MASTER_PROMPT.md` (all 1,416 lines), and `README.md`. There was no `docs/` directory or nearer `AGENTS.md` to apply. Survey commands included `git status --short --branch`, `git remote -v`, `git log --oneline --decorate`, `git ls-files`, `find`, `rg --files`, `rg` heading/requirement searches, `wc -l`, and bounded `sed` reads. Current platform/dependency recommendations were checked against primary Apple/project documentation and are date-stamped; they must be revalidated at adoption/release.

The decisive constraint remains that production work is gated: this task may
create specifications, ADRs, risk analysis and bounded disposable spikes, but
cannot claim a production feature. Historical DF-M0-001 commands and results
are retained in its durable report and evidence commit;
[TEST_STRATEGY.md](TEST_STRATEGY.md) continues to define future production
commands and gates separately from the recorded M0 experiment.

## 2. Product vision

DataForge is a native, keyboard-first macOS workspace for developers, DBAs, and data engineers who need to inspect, query, edit, compare, transfer, and operate databases without sacrificing data safety. It combines a SwiftUI/AppKit presentation layer with capability-based database services and a streaming core. Its identity, interaction design, assets, and copy are original.

### 2.1 Goals

- Make connection context, environment, transaction state, and destructive-operation risk visible before an action executes.
- Provide a fast native macOS workflow with multi-window workspaces, tabs, command palette, keyboard navigation, restoration, Light/Dark Mode, and baseline VoiceOver support.
- Deliver a complete vertical slice before broad engine coverage: connect, browse, edit SQL, execute, cancel, stream results, safely edit keyed rows, transact, and export.
- Protect credentials with macOS Keychain, validated TLS, verified SSH host keys, redacted diagnostics, and explicit privacy consent.
- Keep large schemas and results bounded through lazy loading, virtualization, streaming, backpressure, and cancellation.
- Normalize metadata and data types while retaining lossless engine-specific information behind adapter boundaries.
- Make generated SQL and high-impact operations reviewable, deterministic, capability-aware, and testable.
- Establish module, adapter, FFI, security, quality, and distribution contracts that can support Community and Pro packaging later without premature product splitting.

### 2.2 Non-goals

- Feature parity with every database product or engine in the initial release.
- A web, Windows, Linux, iOS, or collaborative cloud client in M0–M7.
- Pixel-matching, copying assets/copy, or reverse engineering any commercial application.
- Hosting a database server, replacing vendor backup engines, or silently emulating unsupported database behavior.
- Running arbitrary in-process third-party plugins; a plugin ecosystem is Deferred.
- Bidirectional data synchronization without an explicit conflict model.
- Automatic retry of writes unless idempotency is proven for the exact operation.
- Editing rows that cannot be identified safely by a primary or unique key.
- A global control that disables TLS or SSH identity verification.
- Telemetry or crash upload before explicit opt-in and user-visible redaction controls.

## 3. Users and jobs to be done

### P1 — Application developer

Works across local, test, and production-like relational databases. Needs fast navigation, schema-aware editing, reliable results, snippets, history, and unmistakable environment context. Primary risk is issuing a destructive statement in the wrong connection.

### P2 — Database administrator

Manages schema, sessions, roles, backups, restores, and production incidents. Needs permission-aware operational tools, previews, auditability, cancellation, and exact dialect behavior. Primary risk is irreversible data or availability impact.

### P3 — Data engineer / analyst

Moves and validates large datasets, imports external files, exports results, and compares sources. Needs streaming, mappings, resumability, error-row reports, formula-injection protection, and bounded memory. Primary risk is silent truncation or semantic type loss.

### P4 — Security-conscious team lead

Defines connection and diagnostic policy, reviews credential handling and dependencies, and requires trustworthy distribution. Needs least privilege, local-only defaults, signed updates, SBOM, and evidence that secrets cannot enter logs, exports, or crash reports.

### P5 — Keyboard and assistive-technology user

Needs every core action without pointer dependence, predictable focus, VoiceOver labels, adequate contrast, Reduce Motion support, and non-color indicators for environment, keys, nulls, and edits.

## 4. Primary outcomes and measures

Initial targets are hypotheses to validate in M0; the performance budget document owns final numbers.

| Outcome | Measure | Target before M3 exit |
| --- | --- | --- |
| Safe operation | Destructive statements bypassing required gate | 0 in classifier/gate security suite |
| Secret protection | Plaintext secret findings in persistence, logs, exports, diagnostics, snapshots | 0 in automated leakage suite |
| Correct editing | Update/delete against an unintended row | 0; tables without safe identity remain read-only |
| Responsiveness | Main-thread database/file I/O regressions | 0 in instrumentation and UI responsiveness tests |
| Bounded results | Memory growth proportional to total result size | No; bounded by configured chunk/cache budgets |
| Recoverability | Unsaved query lost after simulated crash | 0 in restoration UI test |
| Accessibility | Core MVP flows operable by keyboard and labeled for VoiceOver | 100% of controls in the core-flow checklist |
| Adapter truthfulness | UI exposes a capability that adapter reports unsupported | 0 in capability-contract UI tests |

## 5. Product-wide invariants

1. Credentials and private-key passphrases live only in Keychain-backed secret references; metadata persistence and exports contain no secret by default.
2. TLS certificate and hostname validation are on by default. SSH verifies host keys and never silently falls back to a direct connection.
3. Every execution request names its connection, database/schema context, transaction mode, timeout, row limit, cancellation handle, execution ID, streaming policy, error policy, and logging policy.
4. `DROP`, `TRUNCATE`, unconditional `DELETE`, unconditional `UPDATE`, and dialect-equivalent destructive operations are classified structurally, not by regex alone, and pass an environment-aware safeguard.
5. Result sets, exports, imports, transfers, and object trees are streamed or paged with bounded queues; database and file I/O never run on the main thread.
6. Grid writes require a stable primary/unique key and optimistic-concurrency evidence. Pending edits survive theme/scroll changes and cannot auto-apply.
7. Generated SQL is deterministic, dialect-aware, properly quoted/bound, visible before dangerous operations, and covered by dialect tests.
8. Capability resolution occurs through domain interfaces. Presentation code never calls drivers, constructs connection strings, persists passwords, retries queries, or owns dialect logic.
9. Errors are typed, redacted, actionable, cancellation-aware, and mapped across the Swift/Rust boundary without allowing panic to cross it.
10. Production and read-only context use text/icon semantics in addition to color, and remain visible in toolbar/status/safety prompts.

## 6. Platform and release constraints

- Target native SwiftUI for shell and ordinary views, with AppKit for editor, outline, grid, document/window, and other desktop-intensive components where M0 spikes justify it.
- Prefer Swift plus Rust behind a versioned bridge, subject to M0 ADR evidence. UI state is MainActor-isolated; core work uses structured concurrency and bounded channels.
- Use macOS 14+ and Apple Silicon (`arm64`) as the planning baseline. M0 validates that baseline against the then-current support window and measures Universal Binary cost; Intel support remains a separate release decision, not an implicit requirement.
- Prefer direct Developer ID distribution with Hardened Runtime, notarization, and cryptographically verified updates, subject to the distribution ADR. Do not assume one binary can satisfy both direct and Store constraints.
- Local SQLite stores non-sensitive workspace metadata. Keychain stores secrets. Persistence migrations, retention, and deletion are explicit.
- Crash reporting and telemetry are opt-in. Diagnostics are previewable and redact connection strings, parameters, row data, paths where appropriate, tokens, certificates, and private keys.

## 7. Epic specifications

Unless an epic says otherwise, all UI requirements include loading, empty, failure, and cancellation states; keyboard navigation; accessibility labels; Light/Dark Mode; resize behavior; and user-safe error copy. All production work requires happy, failure, edge, cancellation (when applicable), security regression, and engine-dialect tests appropriate to its risk.

### EP-01 — Native application shell and workspace

**Phase / complexity:** MVP / XL

**User story:** As a macOS user, I want restorable multi-window workspaces and keyboard-first navigation so that query context survives interruption and large tasks remain organized.

**Functional requirements**

- Native menu bar, resizable sidebar/editor/inspector/bottom panel, toolbar, and status bar.
- Multi-window and tabbed workspace; tab/window restoration; recent files; autosaved draft queries; crash recovery.
- Command Palette, standard shortcuts, contextual menus, appropriate drag/drop, focus management, undo/redo, and system accent support.
- Settings surface for appearance, privacy, diagnostics, connection defaults, and feature flags.
- Explicit connection, environment, database, transaction, duration, row-count, and job state in relevant chrome.

**Non-functional requirements:** UI state stays on MainActor; restoration is atomic and versioned; no database/file I/O in view bodies or main-thread paths; core flows remain usable with VoiceOver, keyboard, high DPI, and Reduce Motion.

**Dependencies:** M0 UI/document architecture ADRs; persistence and error contracts; SharedUI accessibility conventions.

**Security concerns:** Restored state must reference, not serialize, secrets; crash snapshots and recent-file metadata require redaction and retention controls.

**Technical risks:** SwiftUI/AppKit focus interoperability, stale restoration references, large tab counts, crash-safe writes.

**Acceptance criteria:** A user can create two windows, restore tabs and unsaved drafts after forced termination, operate core navigation without a pointer, and identify active connection/environment/transaction without relying on color.

**Test strategy:** Unit tests for state migration; UI tests for window/tab restoration, crash recovery, keyboard focus, Light/Dark Mode, VoiceOver identifiers, and corrupt-state recovery.

### EP-02 — Connections, credentials, TLS, and conditional SSH

**Phase / complexity:** MVP direct TLS core; SSH deferred until a future
candidate passes ADR-0012; Post-MVP presets/auth expansion / XL

**User story:** As an operator, I want reusable secure connections with clear environment and read-only controls so that I can connect without exposing secrets or confusing production with development.

**Functional requirements**

- Create, edit, delete, duplicate, group, color-label, search, test, connect, disconnect, and cancel connection attempts.
- Configure connect/read timeout, keep-alive, bounded pooling, controlled reconnect, read-only mode, and development/staging/production labels.
- Import/export non-sensitive metadata; secrets excluded by default and represented only by unresolved secret requirements.
- Keychain-backed authentication modes declared by each adapter.
- TLS with system trust, custom CA, optional client certificate, hostname validation, and per-connection exceptional policy only when explicitly designed and warned.
- If a future ADR enables SSH: expose only its adopted password/key/agent
  subset, bounded known-host policy, per-hop host-key handling, clean tunnel
  lifecycle and connector-level no-direct fallback. ADR-0012/0015 currently
  keep the capability unavailable.
- Cloud presets may populate non-secret fields but cannot bypass validation or capability checks.

**Non-functional requirements:** Connection establishment is cancellable and off-main-thread; pool and reconnect policies are bounded; logs are structured and redacted.

**Dependencies:** EP-15 adapter contract, Keychain ADR, TLS/SSH threat model, error taxonomy.

**Security concerns:** Credential theft, MITM, host impersonation, certificate bypass, unsafe key permissions, secret lifecycle, malicious server responses.

**Technical risks:** Driver-specific auth/TLS behavior, SSH jump chains, Keychain access from background processes, reconnection transaction ambiguity.

**Acceptance criteria:** Metadata persists without secrets; a saved secret
round-trips through Keychain; invalid certificates fail closed; production/
read-only status is visible and enforced. If SSH is enabled later, changed
host keys fail closed and a failed tunnel produces zero direct attempts.

**Test strategy:** Unit configuration validation; fake-secret redaction tests;
disposable-engine TLS integration; cancellation, timeout, reconnect, Keychain
denial, export leakage and UI safety tests. Add the complete ADR-0012 SSH
matrix only for an enabled SSH capability.

### EP-03 — Database object explorer

**Phase / complexity:** MVP core; Post-MVP object breadth / L

**User story:** As a developer, I want to browse and search database objects lazily so that even large catalogs remain navigable.

**Functional requirements**

- Capability-filtered hierarchy for server, database, schema, table, column, keys, constraints, indexes, views, materialized views, functions, procedures, triggers, sequences, events, users, roles, extensions, and engine-specific objects.
- Lazy loading, per-node refresh, search, filter, favorites, virtual groups, keyboard open, copy qualified name, details, generated DDL, and dependency view.
- Preserve expansion/selection where valid across refresh; expose stale/loading/error state per subtree.

**Non-functional requirements:** Metadata requests are cancellable, cached with explicit size/lifetime/invalidation/thread-safety policy, and never load an entire server tree at connection time.

**Dependencies:** EP-15 normalized metadata/capabilities, EP-02 connection context, AppKit outline spike.

**Security concerns:** Quote copied identifiers correctly; treat catalog text as untrusted; avoid leaking hidden object names across authorization changes.

**Technical risks:** Catalog scale, permission-dependent metadata, cycles in dependencies, engine-specific hierarchy.

**Acceptance criteria:** A large-schema fixture opens only requested nodes, refreshes one branch without resetting unrelated state, and never shows unsupported object categories.

**Test strategy:** Metadata normalization unit tests; adapter integration fixtures; lazy-load/cache benchmarks; UI tests for keyboard, refresh, search, error recovery, and capability hiding.

### EP-04 — SQL editor and query execution

**Phase / complexity:** MVP core; Advanced visual plans / XL

**User story:** As a database user, I want a responsive, dialect-aware editor with explicit execution scope and cancellation so that I can run the intended SQL safely.

**Functional requirements**

- Multi-tab editor with line numbers, highlighting, folding, multiple cursors, find/replace, formatting/minify, comment toggles, indentation, bracket matching, snippets, history, saved queries, recent files, and parameter prompts.
- Schema- and dialect-aware completion for objects, columns, functions, and aliases; error-position highlighting.
- Explicit actions for current statement, selection, or entire script; statement boundaries from a real parser/tokenizer contract.
- Transaction mode, auto-commit control, commit, rollback, state indicator, timeout, stop/cancel, duration, affected rows, multiple result sets, messages/warnings, Explain, Explain Analyze, and later visual execution plan.
- Large-script handling, row limits, millions-row streaming policy, connection-loss state, production gate, and safe query mode.

**Non-functional requirements:** Keystrokes stay responsive on the agreed large-file fixture; completion has a latency budget and cancellation; execution never blocks main thread; write retry is disabled by default.

**Dependencies:** EP-02, EP-15, statement-classification service, streaming bridge, editor spike.

**Security concerns:** Parameter handling, generated internal SQL injection, production/destructive execution, query text retention, sensitive parameter logging.

**Technical risks:** SQL grammar breadth, multi-statement parsing, cancellation support, transaction ambiguity after network loss, editor performance.

**Acceptance criteria:** Scope is unambiguous before run; supported queries cancel at the driver; unsupported cancellation is stated; an open transaction blocks tab closure until user resolves it; large results stay bounded.

**Test strategy:** Parser/classifier/dialect unit tests; editor performance tests; disposable-engine execution/transaction/cancellation tests; UI tests for scope, production gates, errors, multiple results, tab-close warning, and recovery.

### EP-05 — Result grid, data editor, and type appearance

**Phase / complexity:** MVP core; Post-MVP advanced editors / XL

**User story:** As a data user, I want a fast typed grid with reviewable edits so that I can inspect and change the correct records without loading an entire table.

**Functional requirements**

- Virtualized grid with server-side pagination or streaming, bounded page/cache size, filtering, sorting, visibility, reorder, freeze, resize, and typed copy as cell/row/SQL/CSV/JSON.
- Distinguish unloaded, `NULL`, and empty string; retain native type metadata; defer large BLOB/image loading.
- Inline insert/duplicate/update/delete/batch edits with typed editors, pending-change indicators, generated SQL preview, explicit apply/rollback, safe key selection, and optimistic concurrency.
- Read-only behavior for no-key tables unless a separately reviewed safe strategy exists.
- Export current result through EP-10.
- Normalize and style integer, decimal/float, string/text, boolean, date, time, timestamp, UUID, JSON, XML, binary, enum, array, spatial, null, PK, FK, generated, and engine-specific types.
- Global/connection/database/table-grid overrides; independent Light/Dark palettes; enable toggle; text/background/font weight/style; reset; live preview; Default, High Contrast, Color Blind Friendly, and Minimal presets; import/export appearance profiles.
- Font, size, row height, alternating backgrounds, grid lines, selection, modified/invalid/null appearance, and non-color icons/tooltips.

**Non-functional requirements:** Theme resolution is outside adapters and execution models; changing theme must not rebuild the dataset or lose selection, scroll, or pending edits; contrast is validated or warned; scrolling meets performance budget.

**Dependencies:** EP-04 streaming, EP-15 normalized types, AppKit grid spike, EP-10 export.

**Security concerns:** Wrong-row writes, formula injection in copied spreadsheet content, sensitive clipboard lifetime, BLOB parsing, persistence separation from connection secrets.

**Technical risks:** Grid virtualization/edit state, stable row identity, pagination consistency, broad type editors, theme invalidation.

**Acceptance criteria:** Million-row fixture remains bounded; no-key table is read-only with explanation; concurrent row change produces a conflict rather than overwrite; theme changes preserve state and meet contrast policy.

**Test strategy:** Identity/concurrency unit tests; adapter CRUD integration success/failure/rollback; virtualization/memory/scroll benchmarks; snapshot/UI tests across type groups, themes, editing, conflicts, no-key state, and accessibility fallbacks.

### EP-06 — Object designer

**Phase / complexity:** Post-MVP / XL

**User story:** As a database designer, I want validated forms plus dialect SQL previews so that I can change objects deliberately.

**Functional requirements:** Form-based create/edit for tables, columns, indexes, primary/foreign keys, unique/check constraints, views, functions, procedures, triggers, and sequences; adapter-specific options; validation; unsaved-change protection; deterministic migration preview; explicit apply.

**Non-functional requirements:** Designer domain models are independent of UI and drivers; unsupported controls are hidden or explained by capabilities; destructive changes never auto-apply.

**Dependencies:** EP-15 metadata/DDL capabilities, EP-07 migration planning, EP-04 transaction/safety gate.

**Security concerns:** Identifier/literal injection, privilege escalation through generated DDL, sensitive routine bodies in history.

**Technical risks:** Lossless round-trip of engine options, non-transactional DDL, dependency ordering.

**Acceptance criteria:** Generated SQL is deterministic and previewed; validation catches unsupported/invalid inputs; failure reports partial-apply semantics accurately.

**Test strategy:** Model/validation unit tests; dialect snapshots and semantic integration; failure/rollback/partial-apply tests; UI unsaved-change and preview tests.

### EP-07 — Schema comparison and synchronization

**Phase / complexity:** Post-MVP / XL

**User story:** As a DBA, I want to compare normalized schemas and review an ordered migration so that synchronization never starts from an opaque diff.

**Functional requirements:** Source/target selection, introspection, normalization, added/removed/changed detection, cautious rename candidates, dependency order, deterministic migration SQL, include/exclude, dry run, backup recommendation, transaction wrapping only when supported, saved profiles, and history. Comparison and apply are separate states.

**Non-functional requirements:** Results are reproducible for unchanged sources; large schemas have budgeted memory/time; cancellation propagates; uncertainty remains visible.

**Dependencies:** EP-15 schema model/capabilities, EP-06 DDL generation, safety/audit services.

**Security concerns:** Target confusion, malicious identifiers, destructive migrations, credentials in profiles/history.

**Technical risks:** Rename false positives, cycles, engine metadata loss, non-transactional DDL.

**Acceptance criteria:** No synchronization can execute directly from compare; destructive steps require preview and typed confirmation; unsupported transaction wrapping is never claimed; verification compares post-state.

**Test strategy:** Normalization/diff/order property tests; deterministic snapshots per dialect; integration success/failure/rollback-or-partial semantics; UI source/target, review, confirmation, cancellation tests.

### EP-08 — Data comparison and synchronization

**Phase / complexity:** Post-MVP one-way; Deferred bidirectional until conflict ADR / XL

**User story:** As a data engineer, I want key-based, reviewable synchronization so that I can reconcile datasets with known conflict semantics.

**Functional requirements:** Source/target, table/column/key mapping, filters, batch size, insert/update/delete detection, one-way plan, dry run, preview sample, operation summary, resume/retry only at proven safe boundaries, progress, cancel, verification, and redacted local audit. Bidirectional mode requires an approved conflict strategy.

**Non-functional requirements:** Streaming/bounded memory, deterministic mapping, resumable checkpoint integrity, no automatic non-idempotent write retry.

**Dependencies:** EP-05 type/identity model, EP-09 mapping/checkpoints, EP-15 capabilities.

**Security concerns:** Source/target inversion, sensitive samples/audit, destructive deletes, cross-boundary credentials.

**Technical risks:** Key mismatch, concurrent mutations, semantic type conversion, ambiguous resume.

**Acceptance criteria:** Dry run precedes apply; summary identifies inserts/updates/deletes; cancellation stops at documented boundary; verification detects divergence; bidirectional is unavailable without strategy.

**Test strategy:** Diff/mapping unit tests; high-volume integration; cancellation/resume/failure/rollback tests; destructive confirmation and audit-redaction security tests.

### EP-09 — Data transfer

**Phase / complexity:** Post-MVP / XL

**User story:** As a data engineer, I want streaming same- and cross-engine transfers with explicit mappings so that large moves are observable and recoverable.

**Functional requirements:** Same/cross-engine source/target; type, table, and column mapping; schema+data/data-only/structure-only modes; batch transfer; progress; cancel; controlled retry/resume; error-row export; transaction boundaries; schema creation option; final report.

**Non-functional requirements:** Bounded channels/backpressure; checkpoints are atomic/versioned; throughput and memory measured on published fixtures.

**Dependencies:** EP-10 file safety for reports, EP-15 type/capability model, job runtime primitives.

**Security concerns:** Destination overwrite, credential separation, temporary files, row-data leakage in reports.

**Technical risks:** Lossy type mapping, partial batches, generated values, ordering/constraints.

**Acceptance criteria:** User reviews mappings and loss warnings; cancellation leaves documented state; resume cannot duplicate committed batches; report accounts for every attempted row without exposing secrets.

**Test strategy:** Type-mapping unit/property tests; cross-engine disposable integration; interruption/resume/idempotency tests; performance and redaction tests.

### EP-10 — Import and export

**Phase / complexity:** MVP CSV export; Post-MVP CSV/TSV/JSON/SQL/XML/XLSX import/export; Advanced Parquet / XL

**User story:** As a data user, I want previewable imports and safe streaming exports so that untrusted files cannot corrupt data or my workstation.

**Functional requirements:** Import encoding/delimiter/header mapping/type inference preview/null/date mapping/error policy/batch/transaction/cancel/error-row report; export current page/full result/selection/columns with streaming, compression, encoding, date format, null representation, and size warning; atomic no-overwrite writes.

**Non-functional requirements:** Input and decompression limits, bounded memory, cancellation, deterministic escaping, secure temp permissions, partial-file cleanup/marking.

**Dependencies:** EP-05 typed data, EP-04 streaming, file-access/distribution decision.

**Security concerns:** Malicious CSV/JSON/XML/XLSX, formula injection, path traversal, zip bombs, unsafe temporary files, secrets/row data.

**Technical risks:** Encoding ambiguity, type inference trust, format-library licensing, partial transactions.

**Acceptance criteria:** Import always presents reviewable mapping; spreadsheet-targeted exports neutralize formulas; existing files are not overwritten without consent; cancelled/failed export leaves no apparently complete file.

**Test strategy:** Parser fuzz/property tests; malicious corpus; formula/path/zip security tests; database transaction success/failure/rollback; large-file memory and cancellation benchmarks.

### EP-11 — Backup and restore

**Phase / complexity:** Post-MVP / XL

**User story:** As a DBA, I want capability-specific backup and restore workflows so that official tools are invoked safely and restore intent is validated.

**Functional requirements:** Per-adapter logical/physical/library/native-tool strategies; preflight; progress; cancel semantics; validation; retention; encryption/compression; restore preview/confirmation/report. Prefer trusted vendor tools instead of recreating complex engines.

**Non-functional requirements:** No shell interpolation; pinned/validated executable discovery; secure credential handoff and temporary permissions; explicit partial-state semantics.

**Dependencies:** Distribution/sandbox ADR, EP-02 credentials, EP-15 backup/restore capabilities, job engine primitives.

**Security concerns:** Command injection, tool substitution, secret process arguments, unsafe archives/paths, destructive restore.

**Technical risks:** Tool licensing/packaging, progress/cancel portability, version mismatch, Store restrictions.

**Acceptance criteria:** Unsupported adapters expose no action; command arguments are structured; restore requires typed confirmation and target identity; credentials never appear in process listings/logs; validation reports success or actionable failure.

**Test strategy:** Command-builder unit/security tests; fake-tool process tests; disposable-engine backup/restore; cancellation/partial restore; archive traversal and permission tests.

### EP-12 — ER diagrams and data modeling

**Phase / complexity:** Advanced physical/reverse engineering; Advanced-later conceptual/logical/versioning / XL

**User story:** As a designer, I want navigable models derived from database metadata so that relationships and proposed changes are understandable.

**Functional requirements:** Reverse engineering, table nodes, relationship edges, auto/manual layout, zoom/pan/minimap, notes, groups/layers, search, PNG/PDF/SVG export, SQL generation, model/database comparison, review-before-apply, physical models, then conceptual/logical models and versioning.

**Non-functional requirements:** Large-graph layout runs cancellably off main thread; model files are versioned and atomically saved; exports are deterministic where possible.

**Dependencies:** EP-03 metadata, EP-07 schema diff, graph-layout dependency review.

**Security concerns:** Sensitive schema names in model exports, malicious metadata labels, unsafe export paths.

**Technical risks:** Layout quality/performance, model round-trip, migration correctness.

**Acceptance criteria:** Large fixture stays interactive; manual positions persist; apply is impossible without schema-diff review; exported model contains only selected scope.

**Test strategy:** Graph/model unit tests; layout benchmarks; snapshot/UI navigation tests; export sanitization and comparison integration tests.

### EP-13 — Monitoring and execution plans

**Phase / complexity:** Advanced / L

**User story:** As an operator, I want capability-aware sessions, locks, running queries, and plans so that I can diagnose contention without accidental disruption.

**Functional requirements:** Sessions, queries, locks/blocking, transactions, variables, database/table size, connections, duration, Explain/Explain Analyze visualization, cancel query, and kill session where supported. Refresh interval and retention are bounded.

**Non-functional requirements:** Polling is cancellable/backoff-aware and never unbounded; high-impact controls require permission check and confirmation.

**Dependencies:** EP-04 plan data, EP-15 monitoring/admin capabilities, safety/audit service.

**Security concerns:** Privileged metadata exposure, kill/cancel misuse, query-text sensitivity.

**Technical risks:** Engine-specific semantics, polling load, race between confirmation and target state.

**Acceptance criteria:** Unsupported cards/actions are not shown; target identity is revalidated before kill; production action requires confirmation; sensitive SQL is redacted according to policy.

**Test strategy:** Capability and polling unit tests; permission/race integration tests; kill/cancel confirmations; load/backoff and redaction tests.

### EP-14 — Users and roles

**Phase / complexity:** Advanced / XL

**User story:** As a DBA, I want to inspect and preview account/privilege changes so that access control changes are explicit and dialect-correct.

**Functional requirements:** List/create/edit/disable/drop users; list/manage roles and membership; database/schema/table privileges; adapter capability checks; generated SQL or operation preview; explicit execution and result.

**Non-functional requirements:** Least-privilege metadata access; deterministic redacted plans; no password echo or ordinary persistence.

**Dependencies:** EP-15 user/role capabilities, EP-02 secure secret input, EP-04 safety/transaction service.

**Security concerns:** Privilege escalation, password handling, target/account confusion, audit leakage.

**Technical risks:** Divergent authorization models, non-transactional account changes, lockout.

**Acceptance criteria:** Every mutation has target and privilege diff preview; unsupported operations are absent; secrets go directly to secure operation channels; failure explains partial state.

**Test strategy:** Privilege-diff unit tests; least-privilege disposable integration; secret-leakage and authorization-denial tests; preview/confirmation UI tests.

### EP-15 — Adapter platform and engine roadmap

**Phase / complexity:** MVP foundation and four relational adapters; Advanced additional engines; Deferred evaluations / XL

**User story:** As a product engineer, I want versioned capability-based adapters so that UI and domain behavior remain truthful across engines.

**Functional requirements:** Versioned adapter interface for connection validation, auth modes, metadata, normalized types, quoting/binding, streaming, cancellation, transactions, DDL, plans, monitoring, users, backup/restore, and error mapping. M1–M3 target PostgreSQL, MySQL, MariaDB, SQLite; M6 targets SQL Server, Redis, MongoDB through model-appropriate experiences; Oracle, Snowflake, Redshift, ClickHouse, CockroachDB, TiDB, OceanBase, and cloud services are evaluations only.

**Non-functional requirements:** Driver code remains outside UI/domain models; conformance suites are mandatory; driver licenses, security, maintenance, Apple Silicon, size, and transitive risk are recorded before adoption.

**Dependencies:** Core/bridge/driver ADRs, disposable test infrastructure, error and cancellation contracts.

**Security concerns:** Malicious servers/drivers, supply chain, native library distribution, credential/TLS differences.

**Technical risks:** Metadata/dialect divergence, non-relational impedance mismatch, cancellation limitations, driver lifecycle.

**Acceptance criteria:** UI exposure derives from declared capabilities; each shipped adapter passes common plus engine-specific suites; unsupported operations produce typed `UnsupportedCapability`; no engine type leaks into shared domain APIs.

**Test strategy:** Contract, property, dialect snapshot, malicious-response, integration, cancellation, streaming/backpressure, and compatibility matrix tests.

### EP-16 — Automation and background jobs

**Phase / complexity:** Enterprise; manual job primitives may support M4 / XL

**User story:** As an operator, I want saved, observable jobs with explicit credential policy so that recurring work runs only under understood macOS lifecycle conditions.

**Functional requirements:** Saved query/import/export/backup/transfer/schema/data-comparison jobs; manual run; schedule; bounded retry; log; notification; failure report; cancellation; credential access policy; evaluation of background helper and launch agent. UI states distinguish app-open, background, logged-out, sleeping, SSH-required, and Keychain-locked cases.

**Non-functional requirements:** Durable versioned state machine, idempotency metadata, bounded queues, no unmanaged tasks, wake/sleep and crash recovery semantics.

**Dependencies:** M4 operations, distribution ADR, Keychain background-access decision, notification policy.

**Security concerns:** Unattended privileged writes, secret access while locked/logged out, helper/update compromise, log leakage.

**Technical risks:** macOS scheduling guarantees, sleep, user session lifecycle, SSH tunnel recovery, partial jobs.

**Acceptance criteria:** Scheduler never promises execution during unsupported lifecycle states; write retries require proven idempotency; locked credentials pause safely; every run has correlation ID, redacted log, outcome, and resumability semantics.

**Test strategy:** State-machine/property tests; fake-clock scheduler; sleep/wake/logout/Keychain-denial tests; crash recovery, bounded concurrency, cancellation, retry, and end-to-end job tests.

### EP-17 — Diagnostics, privacy, distribution, and extensibility readiness

**Phase / complexity:** MVP security/distribution; Deferred plugin ecosystem / L

**User story:** As a security-conscious user, I want trustworthy binaries and previewable diagnostics so that supportability does not trade away privacy.

**Functional requirements:** Structured redacted logs with operation/job/execution IDs; exportable previewable diagnostic bundle; delete-all history/diagnostics; opt-in crash and telemetry controls; code signing, Hardened Runtime, notarization, signed updates, dependency scanning, and SBOM. Internal adapter boundaries reserve versioning for future out-of-process, signed, permissioned plugins; no arbitrary plugin execution in MVP.

**Non-functional requirements:** Least privilege, secure update verification, atomic updates/rollback, bounded retention, offline-safe core use.

**Dependencies:** Distribution, security, observability, and adapter ADRs; release infrastructure.

**Security concerns:** Update compromise, supply chain, diagnostic leakage, untrusted plugin, analytics without consent.

**Technical risks:** updater integration, symbolication privacy, entitlement drift, future API compatibility.

**Acceptance criteria:** Release verification rejects tampered artifacts; fresh install sends no telemetry; diagnostic preview exactly matches export and contains no seeded secrets; unsigned plugins cannot load because plugin loading is absent.

**Test strategy:** Signing/notarization/update validation in release CI; seeded-secret leakage tests; opt-in/out network tests; SBOM/dependency policy checks; diagnostic retention/deletion UI tests.

## 8. Cross-epic error and lifecycle model

User-visible failures map to: Configuration, Authentication, Authorization, Network, TLS, SSH, Timeout, Cancellation, Database, Query Syntax, Constraint, Transaction, File, Import, Export, Internal, and Unsupported Capability. Each contains a user-safe message, suggested next action where possible, operation/execution ID, adapter identifier, retryability, and redacted diagnostic context. Raw stack traces and driver errors do not reach end users.

Long-running operations expose a lifecycle of `configured → validating → running → cancelling → succeeded | failed | cancelled | partiallyApplied`. Operations that can partially apply document transaction/checkpoint boundaries and remediation before release.

## 9. Product-level acceptance gate

An increment is releasable only when:

- Its feature-matrix phase and adapter capability are explicit.
- Architecture boundaries and any public FFI change are documented, versioned, and integration-tested.
- Success, failure, edge, cancellation, rollback/partial-apply, and relevant security regressions pass.
- No seeded secret appears in metadata, exports, logs, crash payloads, diagnostics, snapshots, or fixtures.
- Database write flows identify target, environment, transaction, generated operation, and safe row/object identity.
- Performance-sensitive behavior meets measured budgets on named fixtures with bounded memory/queues/caches.
- Core UI supports keyboard, VoiceOver labels, Light/Dark Mode, and non-color status cues.
- Formatter, linter, build, unit, integration, UI, security, and performance commands required by the changed scope pass.
- Documentation states remaining uncertainty and no unsupported capability is presented as complete.

## 10. Assumptions and open decisions

- M0 must validate the proposed macOS 14+/arm64 baseline (and measure, not promise, Universal cost), bridge technology, driver selection/licenses, editor/grid implementation, direct distribution, updater, SSH stack, and test orchestration before production implementation.
- Community/Pro packaging is an architectural seam, not an M0–M3 SKU promise; safety and credential protections can never be paywalled.
- Redis and MongoDB need model-appropriate explorers/editors, not a forced relational grid contract.
- Native backup tooling may be unavailable under some distribution or sandbox configurations; those combinations remain unsupported until proven.
- Bidirectional synchronization, third-party plugins, Phase-3 engines, unattended logged-out execution, and any TLS validation exception remain behind explicit future ADRs and threat-model review.
