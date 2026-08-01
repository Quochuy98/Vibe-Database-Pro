# Feature Matrix

Status: Planning baseline

Last updated: 2026-07-29

Legend: `MVP`, `Post-MVP`, `Advanced`, `Enterprise`, `Deferred`, and `Not recommended` classify scope; none indicates implementation status.

## 1. Phase summary

| Phase | Included outcome | Deliberately excluded |
| --- | --- | --- |
| MVP | Safe native shell, Keychain connections, PostgreSQL vertical slice, then MySQL/MariaDB/SQLite; explorer, editor/execution/cancel/stream, keyed grid edits, transactions, CSV export | Broad modeling, automation, additional engines, bidirectional sync, plugins |
| Post-MVP | Object designer, import/export, transfer, schema/data diff, backup/restore with previews and reports | Unreviewed destructive automation or generic lossy conversion |
| Advanced | ER modeling, monitoring/plans, SQL Server/Redis/MongoDB model-specific support | Unsupported engine claims and silent emulation |
| Enterprise | Policy-controlled jobs, approvals, audit/retention integration, advanced automation/governance | Safety controls hidden behind a paid tier |
| Deferred | Oracle/cloud analytical engines, conceptual/logical model, plugin ecosystem, logged-out jobs, bidirectional sync | Requires new ADR, threat model and capacity |
| Not recommended | Plaintext secrets, global TLS bypass, shell-interpolated tools, auto-retry writes, auto-commit close, no-key editing, compare-and-apply, in-process arbitrary plugins | Never implement or advertise |

## 2. Required feature cards

Every card contains user story, functional requirements (FR), non-functional requirements (NFR), dependencies, security concerns, technical risks, acceptance criteria (AC), test strategy and complexity.

### FM-01 — Application shell and workspace

**Phase / complexity:** MVP / XL

**User story:** As a Mac developer, I want native windows, tabs, drafts, menus and a command palette so that I can work keyboard-first without losing SQL.

**FR:** SwiftUI shell; AppKit bridges; sidebar/center/inspector/bottom panel; multi-window/tabs/menu/shortcuts; resizable panes; settings; Light/Dark/system accent; safe drag/drop; autosave, crash recovery and disconnected tab restoration.

**NFR:** macOS 14+, arm64 MVP, MainActor UI, off-main I/O, VoiceOver, Reduce Motion, bounded restore/drafts.

**Dependencies:** ADR-0001, Workspace, persistence, Connections, Diagnostics.

**Security:** No secrets in snapshots/bookmarks; restored transactions never auto-resume.

**Risks:** SwiftUI/AppKit ownership, restore races, large drafts, accessibility.

**AC:** Resize/window/keyboard/VoiceOver/appearance pass; crash recovery preserves draft but no live session; no main-thread DB/file calls.

**Tests:** UI/accessibility/keyboard, migration/recovery, launch/restoration performance, seeded-secret scan.

### FM-02 — Connection manager and credential security

**Phase / complexity:** MVP / XL

**User story:** As an operator, I want labeled, read-only-aware connections with secure authentication so that production and credentials are protected.

**FR:** Create/edit/delete/duplicate/group/color; test; connect/read timeouts;
keepalive/pool; controlled reconnect; environment/read-only labels; import/
export non-secret metadata; TLS/CA/client cert; SSH modes only after a future
candidate/adoption ADR; cloud/auth presets by capability; Keychain.

**NFR:** Typed validation/errors, no UI-built/logged URL, cancellation, bounded pool, channel capability differences.

**Dependencies:** ADR-0005/6/7/12, Keychain, adapter ports, TLS evidence,
persistence; all ADR-0012 re-entry gates before exposing SSH.

**Security:** Keychain-only, hostname/certificate and host-key validation, no shell/direct fallback, non-color production warning.

**Risks:** SSH/TLS libraries, auth variants, Keychain helper access, reconnect outcome.

**AC:** Bad auth/TLS fails closed; export has no secret; read-only blocks writes.
If SSH is later enabled, changed host keys fail closed and every tunnel
resource cleans up without a direct fallback.

**Tests:** Keychain/leak, TLS/SSH adversarial, timeout/cancel/pool/reconnect, production/read-only UI.

### FM-03 — Lazy object explorer

**Phase / complexity:** MVP / L

**User story:** As a DBA, I want to browse huge object hierarchies lazily so that connection does not load the entire catalog.

**FR:** Server/database/schema/table/column/index/keys/constraints/views/routines/triggers/sequences/events/users/roles/extensions/engine objects; lazy refresh/search/filter/favorites/virtual groups/copy name/keyboard open/details/DDL/dependencies.

**NFR:** Paged/cancellable metadata, bounded cache, stable IDs, explicit permission gaps, capability-driven categories.

**Dependencies:** Metadata/capabilities, normalized model, `NSOutlineView`, persistence.

**Security:** DDL is read-only preview until explicit designer; diagnostics redacted.

**Risks:** Catalog dialect/privileges, stale cache, scale.

**AC:** First useful page meets budget; expand fetches only its scope; refresh invalidates correctly; unsupported categories are absent/explained.

**Tests:** Conformance, lazy/cancel/cache, limited privilege, keyboard/accessibility, BF-04 performance.

### FM-04 — SQL editor and safe query execution

**Phase / complexity:** MVP / XL

**User story:** As a developer, I want a fast multi-tab editor with explicit execution/transaction context so that long and risky SQL is controllable.

**FR:** Highlight/lines/folding/multi-cursor/find/format/minify/comment/indent/brackets; snippets/history/saved/recent; parameters; run current/selected/script; auto-commit/commit/rollback; stop/timeout/duration/affected rows/multiple results/messages; explain/analyze/plan; dialect/schema/alias completion; error positions/safe mode; large-script/lost-connection/production handling.

**NFR:** TextKit 2 incremental/viewport work, off-main execution, streaming/limits/cancel, typed errors, no write retry.

**Dependencies:** ADR-0001/2/3/7, parser/classifier, QueryExecution, adapters, Diagnostics.

**Security:** Core reclassification, destructive/production confirmation, preview digest, no sensitive parameters in logs.

**Risks:** Parsing, cancel races, huge files/results, open transaction.

**AC:** Exact selection executes; changed target/SQL invalidates preview; bounded results; honest cancel; transaction close warning.

**Tests:** Parser property/fuzz, adapter/FFI, UI shortcut/production/transaction, large file/result performance.

### FM-05 — Result grid, data editor and data-type appearance

**Phase / complexity:** MVP baseline; Post-MVP advanced editors / XL

**User story:** As a data engineer, I want a virtualized typed grid with safe row identity and visible pending changes so that edits cannot target the wrong row.

**FR:** Server paging/page size/filter/sort/visibility/reorder/freeze/resize; copy cell/row/SQL/CSV/JSON; inline/insert/duplicate/delete/batch pending edits; preview/apply/rollback; NULL/bool/date/JSON/text/hex/binary/image/FK editors; read-only/PK/unique/optimistic concurrency/export. Appearance: font/size/row/grid/selection/modified/invalid/NULL/PK/FK, normalized type text/background/font by app/connection/database/table/grid; toggle/reset/live preview; Default/High Contrast/Color Blind Friendly/Minimal presets; tooltip/icon fallback and contrast warning.

**NFR:** Bounded pages/cache, no full table in RAM, typed values, visible-cell-only theme invalidation, Light/Dark/accessibility modes, deferred BLOB.

**Dependencies:** AppKit grid spike, row identity/type ports, safety, theme engine, persistence.

**Security:** No-key read-only; affected-row assertion; formula-safe export; no row/log/clipboard retention.

**Risks:** Wide/frozen virtualization, wrong row, type loss, accessibility, large cells.

**AC:** Million-row budget; theme preserves selection/scroll/edits; conflict/rollback safe; custom colors checked; non-color indicators available.

**Tests:** Grid UI/accessibility/snapshot, type mapping, identity/concurrency/rollback, large cell, RSS/frame.

### FM-06 — Object designer

**Phase / complexity:** Post-MVP / XL

**User story:** As a DBA, I want validated forms and SQL/migration previews so that schema changes are deliberate.

**FR:** Table/column/index/PK/FK/unique/check/view/function/procedure/trigger/sequence forms; engine options; validation; unsaved protection; migration preview.

**NFR:** Capability/transaction/implicit-commit aware; deterministic generation; cancellable introspection.

**Dependencies:** Metadata, dialect generator, schema diff, safety, forms.

**Security:** R2/R3 confirmation; no auto-apply; target/production/permission checks.

**Risks:** DDL rewrite/lock/rename and engine options.

**AC:** Invalid form cannot apply; preview lists destructive/lock/transaction effects; drift invalidates apply.

**Tests:** Validation, SQL snapshots/semantics, permission/rollback/partial DDL, unsaved UI.

### FM-07 — Schema diff and synchronization

**Phase / complexity:** Post-MVP / XL

**User story:** As a release engineer, I want a reviewed schema migration plan before any target change.

**FR:** Source/target introspect/normalize/add/remove/change/rename proposal/dependency order/generate/preview/include/exclude/dry-run/backup/transaction-if-supported/profile/history.

**NFR:** Deterministic bounded graph, cancellable, lossless descriptors, exact partial report.

**Dependencies:** Metadata/dialect/capability, designer, safety, persistence.

**Security:** Immutable target; production/R3 typed confirmation; compare never auto-applies; audit.

**Risks:** False rename, cycles, implicit commit, drift, loss.

**AC:** Compare cannot call apply; target drift blocks; destructive list separate; verification reports exact outcome.

**Tests:** Diff property/snapshot, graph/rename, disposable apply/rollback/partial, performance/UI safety.

### FM-08 — Data diff and synchronization

**Phase / complexity:** Post-MVP one-way; bidirectional Deferred / XL

**User story:** As a data engineer, I want a dry-run, keyed, resumable sync so that inserts/updates/deletes are reviewed and recoverable.

**FR:** Source/target, table/column/key/filter/batch mapping, change detection, one-way sync, preview sample/summary, generated operations, progress/cancel/resume, verification/audit; bidirectional only after conflict design.

**NFR:** Streaming/bounded comparison and deterministic checkpoints.

**Dependencies:** Transfer/edit ports, diff engine, safety, audit.

**Security:** Deletes opt-in/R3; no blind retry; target labels and partial outcome.

**Risks:** Key drift, consistency, conflict, cross-engine loss.

**AC:** Reproducible dry run; no review bypass; cancel/partial/resume evidence; verification catches mismatch.

**Tests:** Key/conflict/rollback/interruption/resume/security/large-scale.

### FM-09 — Data transfer

**Phase / complexity:** Post-MVP / XL

**User story:** As a data engineer, I want bounded same/cross-engine transfer with explicit mapping and error reports.

**FR:** Type/table/column mapping; batch/stream/retry-by-proof/resume/error rows/transactions/progress/cancel/report; schema/data/structure modes.

**NFR:** Backpressure, bounded temp/queues, explicit checkpoints, measured throughput.

**Dependencies:** Transfer adapters, normalized types, import/export, safety.

**Security:** Path/tool/target controls; secret-free report; production confirmation.

**Risks:** Lossy types/order/driver differences/duplicate retries.

**AC:** Mapping and loss preview; cancel identifies committed batches; resume cannot duplicate; bounded error report.

**Tests:** Cross-engine, numeric/timezone/collation, rollback/resume, malicious input/path, throughput.

### FM-10 — Import and export

**Phase / complexity:** MVP CSV export; Post-MVP CSV/TSV/JSON/SQL/XML/XLSX; Advanced Parquet / L–XL

**User story:** As a user, I want previewable bounded file exchange without code injection, traversal or silent coercion.

**FR:** Encoding/delimiter/header/type/null/date/error/batch/transaction preview; export page/result/selected rows/columns/stream/compression/encoding/date/null.

**NFR:** Streaming, byte/row/nesting limits, cancel, atomic writes, explicit partial/error report.

**Dependencies:** Pipeline, adapters, file security, results/grid.

**Security:** Formula injection, XXE/archive/path traversal, overwrite confirmation, no secrets.

**Risks:** Formats/inference/huge file/disk full.

**AC:** Reviewable mappings; hostile input bounded; cancelled output clean/marked; exact transaction/error policy.

**Tests:** Property/security/roundtrip, formula/path/encoding/disk-full/cancel/performance.

### FM-11 — Backup and restore

**Phase / complexity:** Post-MVP / XL

**User story:** As a DBA, I want adapter-specific trusted backup/restore with validation and consequences.

**FR:** Native utility/library/logical/physical choice; progress/cancel; validation; credentials; retention/encryption/compression; destination/target preview.

**NFR:** Signed/licensed tools, direct argv, restricted temp, bounded output.

**Dependencies:** Distribution, adapter administration, file security, Keychain, safety.

**Security:** No shell/secrets in args; restore R3; no silent fallback; verify result.

**Risks:** License/package/sandbox/version/partial restore.

**AC:** Unsupported combos explicit; backup/restore verified; cancel consequence/cleanup accurate.

**Tests:** Signature/argv/injection, disposable restore, permission/disk-full/cancel/production warning.

### FM-12 — ER diagram and data modeling

**Phase / complexity:** Advanced / XL

**User story:** As an architect, I want a searchable reverse-engineered model with reviewed SQL generation.

**FR:** Nodes/edges, auto/manual layout, zoom/pan/minimap, notes/groups/layers/search, PNG/PDF/SVG, generate/compare/review/apply, physical then conceptual/logical/versioning.

**NFR:** Incremental level-of-detail layout, bounded graph, keyboard/accessibility, deterministic export.

**Dependencies:** Metadata/diff/designer, graph spike.

**Security:** No auto-apply; target context; no secrets/rows in export by default.

**Risks:** Scale/staleness/export fidelity.

**AC:** 500-table budget; drift visible; apply reviewed; original visual identity.

**Tests:** Graph/layout, keyboard/VoiceOver, export, large-model performance, migration safety.

### FM-13 — Monitoring and execution plans

**Phase / complexity:** Advanced / L–XL

**User story:** As an operator, I want capability-aware sessions, locks and plans without accidentally disrupting users.

**FR:** Sessions/queries/locks/blockers/transactions/variables/sizes/connections/duration; cancel/kill; explain/analyze/visual plan.

**NFR:** Bounded/rate-limited cancellable polling; permissions; safe rendering.

**Dependencies:** Administration ports, plan renderer, safety/audit.

**Security:** Kill/cancel confirmation and permission; analyze classified because it may execute.

**Risks:** Privilege/semantics/polling load/plan formats.

**AC:** Unsupported actions absent; stale refresh explicit; kill consequence clear; raw plan preserved safely.

**Tests:** Capability/permission, load/cancel, hostile rendering, UI confirmation/accessibility.

### FM-14 — Users and roles

**Phase / complexity:** Advanced / XL

**User story:** As an authorized DBA, I want privilege changes previewed so that access changes are deliberate.

**FR:** List/create/edit/disable/drop; membership; database/schema/table privileges; SQL/operation preview and capabilities.

**NFR:** Least privilege, audit, typed errors, no generated secret display.

**Dependencies:** Administration/dialect/safety.

**Security:** R2/R3, permission/production gates, no retry, secret-free logs.

**Risks:** Vendor privilege semantics and partial grants.

**AC:** Preview matches requested diff; unsupported scopes disabled; partial grant exact.

**Tests:** Least-privilege integration, SQL snapshot, rollback/partial, leak/UI warning.

### FM-15 — Capability-based adapter platform and engine roadmap

**Phase / complexity:** MVP foundation and four relational adapters; Advanced additional engines; Deferred evaluations / XL

**User story:** As a product engineer, I want versioned capability-based adapters so that UI and domain behavior remain truthful across database engines.

**FR:** Split connection/capability/query/cancel/transaction/metadata/dialect/edit/transfer/administration ports; normalized plus lossless metadata/types; PostgreSQL then MySQL/MariaDB/SQLite; SQL Server/Redis/MongoDB later; Oracle/cloud engines evaluation only.

**NFR:** No driver/UI dependency leak; bounded streaming and caches; versioned conformance; exact license/advisory/maintenance/arm64/size/transitive/replacement dossier.

**Dependencies:** ADR-0002/3/7, disposable test infrastructure, FFI/error/cancellation and normalized-type contracts.

**Security:** Malicious servers/drivers, TLS/auth variation, dependency supply chain, capability uncertainty and native library distribution.

**Risks:** Dialect/metadata divergence, cancellation gaps, lowest-common-denominator design and long-term driver maintenance.

**AC:** UI derives support only from capability snapshots; commands revalidate; each advertised engine/version passes common plus engine-specific suites; unsupported returns typed state.

**Tests:** Port/fake-adapter, stale/conditional capability, dialect/type/property, malicious server, disposable version/auth/TLS/cancel/streaming/performance matrices.

### FM-16 — Automation and background jobs

**Phase / complexity:** Enterprise M7; app-open subset Advanced / XL

**User story:** As a team lead, I want reviewed observable jobs with explicit credentials and outcomes.

**FR:** Query/import/export/backup/transfer/comparison jobs; schedule/manual/retry policy/log/notification/failure; app-open first; future signed LaunchAgent/XPC.

**NFR:** Bounded workers, immutable reviewed definition, cancellation/checkpoint, retention, lock/logout/sleep truth.

**Dependencies:** Job engine, Keychain, safety, SMAppService/distribution, adapters.

**Security:** No initial production R3 jobs; no unproven write retry; least-privilege target/capability digest.

**Risks:** Sleep/logout, duplicates, tunnel/helper trust.

**AC:** Changed definition/target blocks; overlap/partial visible; unavailable credential never falls back; helper consent accurate.

**Tests:** State/idempotency/cancel/partial, Keychain/tunnel/helper/update/soak.

### FM-17 — Diagnostics, privacy, distribution and plugin readiness

**Phase / complexity:** MVP baseline; plugin ecosystem Deferred / L–XL

**User story:** As a privacy-conscious user, I want trustworthy binaries and exact diagnostics control.

**FR:** Structured redacted levels/IDs; preview/export/delete diagnostics; separate opt-in crash/telemetry; Developer ID/Hardened Runtime/notarization/signed updates/SBOM; future signed permissioned out-of-process plugins.

**NFR:** Redaction before sinks, bounded retention, atomic export, release verification.

**Dependencies:** Threat model, distribution, diagnostics, dependency tooling.

**Security:** Deny secrets/strings/params/rows/clipboard; update/plugin/supply-chain trust.

**Risks:** Entitlements/updater keys/privacy/vendor/plugin compatibility.

**AC:** Fresh install sends nothing; preview equals export/no canary; tampered artifact/plugin rejected; deletion works.

**Tests:** Leak/consent, signing/notarization/update, SBOM/license, security/accessibility.

## 3. Deferred and rejected inventory

| Feature | Classification | Entry condition/reason |
| --- | --- | --- |
| Oracle | Deferred | Legal client/distribution/auth spike and demand |
| Snowflake/Redshift/ClickHouse/CockroachDB/TiDB/OceanBase/cloud engines | Deferred | Driver/auth/cost/terms and semantics review |
| Bidirectional sync | Deferred | Conflict/tombstone/order/verification design |
| Logged-out/sleep automation | Deferred | Privileged helper/platform evidence |
| Third-party plugins | Deferred | Signed XPC API, capabilities, crash/security/legal model |
| Conceptual/logical modeling | Advanced/Deferred | Physical model/user/scale evidence first |
| Global ignore-TLS mode | Not recommended | Violates fail-closed trust |
| Arbitrary write retry/hidden commit | Not recommended | Unknown outcome/data integrity |
| Editing without safe key | Not recommended | Wrong-row critical risk |
| Plaintext credentials or always-on telemetry | Not recommended | Violates security/privacy contract |

## 4. Traceability gate

Cards trace to [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [USER_FLOWS.md](USER_FLOWS.md), [ROADMAP.md](ROADMAP.md), [BACKLOG.md](BACKLOG.md), [DATABASE_SAFETY.md](DATABASE_SAFETY.md), [TEST_STRATEGY.md](TEST_STRATEGY.md), and [PERFORMANCE_BUDGET.md](PERFORMANCE_BUDGET.md). A phase cannot advance without dependencies, capability contract, security/safety review, tests and measurable acceptance evidence.
