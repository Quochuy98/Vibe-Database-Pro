# Database Adapter Architecture and Roadmap

Status: Proposed

Last updated: 2026-07-29

Related: [Architecture](ARCHITECTURE.md), [Database safety](DATABASE_SAFETY.md), [ADR-0007](adr/0007-database-adapter-interface.md)

## 1. Purpose

Database adapters isolate protocol, SQL dialect, metadata, type, cancellation, transaction, backup, and administration differences from the rest of DataForge. An engine is “supported” only when its adapter declares a versioned capability snapshot and passes conformance tests against a documented server-version matrix.

The UI must never infer a capability from an engine name, version string, or object label. The application/core layer repeats capability checks when executing a command so stale presentation state cannot bypass a restriction.

## 2. Support roadmap

| Delivery phase | Engines | Product intent | Exit condition |
| --- | --- | --- | --- |
| M2 vertical slice | PostgreSQL | Prove the complete safe workflow: connect, browse, execute/cancel/stream, transact, edit keyed rows, export CSV | Adapter contract, TLS, cancellation, type fidelity, metadata, write safeguards and disposable integration suite pass |
| M3 MVP expansion | MySQL, MariaDB, SQLite | Validate that the model is capability-based rather than PostgreSQL-shaped | Separate engine matrices pass; no lowest-common-denominator regression |
| M6 | SQL Server, Redis, MongoDB | Add relational and non-relational experiences after core maturity | Driver/auth/license/product UX spikes accepted per engine |
| Evaluation after M6 | Oracle, Snowflake, Redshift, ClickHouse, CockroachDB, TiDB, OceanBase, cloud services | Research only; no implied support | Business demand, legal/distribution, drivers, auth and conformance plan approved |

MariaDB initially shares the MySQL wire-protocol family but receives its own capability/version test matrix and dialect branches. Redis and MongoDB require model-specific object/result editors and cannot be treated as SQL adapters with cosmetic renaming.

## 3. Adapter contract

The conceptual port is split by responsibility to avoid a monolithic interface:

| Port | Responsibility |
| --- | --- |
| `ConnectionAdapter` | Validate non-secret options, connect using a credential lease, health check, graceful close, connection limits |
| `CapabilityProvider` | Produce versioned static and server-negotiated capability snapshot with evidence/source |
| `QueryAdapter` | Prepare/bind or execute scripts, stream typed results/status/messages, enforce timeout/row/byte policy |
| `CancellationAdapter` | Expose cancel handle and outcome semantics (`confirmed`, `requested`, `unsupported`, `connectionClosed`) |
| `TransactionAdapter` | Begin/commit/rollback/savepoint where supported; report authoritative transaction state |
| `MetadataAdapter` | Lazy introspection by scope; return normalized plus lossless engine descriptors |
| `DialectAdapter` | Quote identifiers, bind parameters, classify/parse statements, generate deterministic preview SQL |
| `EditAdapter` | Build parameterized key-safe mutations, optimistic concurrency predicates, affected-row verification |
| `TransferAdapter` | Bounded read/write batches, type mapping, checkpoint/resume policy, verification |
| `AdministrationAdapter` | Optional monitoring, users/roles, explain, backup/restore operations guarded by capabilities |
| `ErrorMapper` | Map driver/server errors to typed categories and allowlisted redacted diagnostics |

An adapter is not required to implement an optional port. Absence is an explicit unsupported capability, not a runtime “best effort” path.

### 3.1 Versioned capability snapshot

Each snapshot carries:

- contract schema version;
- adapter identifier/build version;
- engine family and normalized server version;
- acquisition time and connection/session identity;
- each capability as supported/unsupported/unknown/conditional;
- conditions such as server version, privilege, object type, storage engine, connection mode, or driver limitation;
- semantic notes needed for safe execution;
- expiration/invalidation triggers.

`unknown` is fail-closed for destructive or write behavior. Privilege failures during probing do not become “unsupported by engine”; they remain conditional/unknown with a user-actionable explanation.

## 4. Capability catalog

The initial schema includes at least:

### Connection and execution

- transactions, savepoints, transaction isolation/read-only transactions;
- query cancellation and whether cancellation is confirmed or only requested;
- statement timeout and session timeout;
- streaming and cursor/server-side pagination;
- multiple statements and multiple result sets;
- prepared statements, named/positional parameters, returning clause;
- connection pooling and session reset safety;
- TLS modes, client certificates, custom CA, hostname validation;
- SSH transport compatibility is a connection-service capability, not inferred from the DB adapter.

### Catalog and SQL

- catalogs/databases, schemas, tables, views, materialized views;
- indexes, primary/foreign/unique/check constraints;
- sequences, functions, procedures, triggers, events, extensions;
- users, roles, privilege introspection/management;
- generated/computed columns, arrays, enum/domain types, JSON, XML, spatial, large objects;
- explain and explain-analyze, stored routines, native backup/restore;
- transactional DDL and implicit-commit conditions;
- identifier case folding, maximum identifier length, parameter marker form.

### Data tools

- safe row identity discovery;
- optimistic concurrency support;
- bulk insert/copy protocol;
- consistent snapshot semantics;
- change tracking/checksum helpers;
- native import/export/backup progress and cancellation;
- schema dependency discovery.

## 5. Illustrative capability matrix

This matrix is a planning hypothesis only. Runtime snapshots and tested server/version matrices are authoritative. `C` means conditional and must include conditions; `—` means not planned for that phase.

| Capability | PostgreSQL M2 | MySQL M3 | MariaDB M3 | SQLite M3 | SQL Server M6 | Redis M6 | MongoDB M6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Transactions | Yes | Yes/C by engine/table | Yes/C by engine/table | Yes | Yes | C by command/workflow | Yes/C by topology |
| Schemas | Yes | C (database-as-schema UX) | C | Attached DB model | Yes | No | No |
| Query cancellation | Yes, request is racy | Requires spike | Requires spike | Interrupt handle | Requires spike | Command/client dependent | Driver/session dependent |
| Streaming | Yes | Yes, verify backpressure | Yes, verify backpressure | Bounded row stepping | Requires spike | Cursor/scan dependent | Cursor-based |
| Returning clause | Yes | Version/statement conditional | Version/statement conditional | Version conditional | Yes | No | Operation-specific |
| Explain | Yes | Yes | Yes | Query plan | Yes | Limited command diagnostics | Explain command |
| Explain analyze | Yes, dangerous-side-effect policy | Conditional | Conditional | Limited | Conditional | No | Execution stats conditional |
| Materialized views | Yes | No | No | No | Indexed-view semantics differ | No | No |
| Stored procedures | Yes | Yes | Yes | No | Yes | No | No |
| Native backup | Official tools | Official tools | Official tools | SQLite backup API/file-safe flow | Official tools | Engine-specific snapshot | Official tools/service |
| Transactional DDL | Broad but not universal | Generally no/implicit commits | Generally no/implicit commits | Conditional | Conditional | N/A | N/A |
| User management | Yes/C privilege | Yes/C privilege | Yes/C privilege | No server users | Yes/C privilege | ACL conditional | Yes/C privilege |
| Relational editable grid | Yes | Yes | Yes | Yes | Later | No | Model-specific editor |

No generated operation may rely solely on this table; adapters encode exact version/condition behavior and tests.

## 6. Connection configuration

Presentation collects typed fields into a non-secret `ConnectionProfile`. Application services validate it and request a short-lived credential lease from Keychain. The UI never builds a URL/connection string and profiles never serialize passwords, tokens, private-key passphrases, client secrets, or access/refresh tokens.

Common non-secret fields:

- stable profile ID, display label and group;
- adapter ID and endpoint(s);
- database/schema defaults;
- environment (`development`, `staging`, `production`, custom) and read-only policy;
- connect/read/statement timeouts and row/byte limits;
- TLS policy and references to user-selected CA/client-certificate material;
- optional SSH policy and non-secret host/jump-host/key references only after
  a candidate is adopted; ADR-0012 currently keeps these unavailable;
- pool ceiling, idle timeout, keepalive, and safe reconnect policy.

Adapters transform typed options to driver configuration internally. Full connection strings are never logged. Export omits all secrets by default and warns before including any sensitive certificate/key material; production credentials cannot be exported.

### 6.1 Reconnect and retry

- reconnect applies to a disconnected idle session or explicitly re-opened read operation;
- no write is automatically retried unless the operation supplies a proven idempotency model and the adapter can establish execution outcome;
- an interrupted transaction is `unknown/lost`, never assumed rolled back until server semantics or reconnect evidence permits that conclusion;
- pooled sessions are reset and validated before reuse; failure destroys the session;
- if SSH is enabled, tunnel failure closes the database transport and never
  falls back to a direct connection.

## 7. Query and stream model

One execution may emit an ordered sequence of:

1. result-set schema;
2. bounded typed row chunks;
3. command status/affected rows;
4. notices/warnings/messages;
5. additional result sets;
6. terminal success/failure/cancel/partial/unknown state.

Chunks are limited by rows **and bytes**. A large cell/BLOB is represented as deferred/truncated metadata and loaded/exported on explicit demand. The consumer requests and acknowledges chunks; the adapter cannot outpace the bounded channel. Row-limit behavior stops fetch, offers explicit load-more/stream-to-export, and states whether the server query itself continued or was cancelled.

Result values retain normalized type, lossless engine descriptor, null state, and typed/binary payload. Presentation formatting is separate.

### 7.1 Cancellation

Cancellation propagates from UI to application service, FFI operation, core task, and driver. Each adapter documents:

- how it obtains and scopes the cancellation token;
- whether a separate control connection is required;
- race behavior and terminal evidence;
- whether the original connection remains safe to reuse;
- how transactions and tunnels are affected;
- fallback: close/poison connection only when documented and user-safe.

PostgreSQL cancellation requests are racy; success of the control request is not proof the statement stopped before completion. SQLite uses an interrupt handle from another thread. MySQL/MariaDB behavior must be proven by spike before the capability is declared.

## 8. Transactions

Transaction state is owned by a pinned adapter session and identified by a stable transaction ID. UI state is a projection, never the source of truth.

Required states include `none`, `starting`, `active`, `failed/aborted`, `committing`, `rollingBack`, `lost/unknown`, and `closed`. Closing a tab/connection with an active, failed, unknown transaction prompts with consequences. The product never commits automatically on close or reconnect.

Adapters declare DDL transaction semantics and implicit-commit statements. Schema migration planning cannot wrap DDL just because generic transactions are supported.

## 9. Metadata normalization

Metadata records have two layers:

- normalized semantic fields used by common product features;
- opaque/versioned engine-specific descriptors retained for fidelity and adapter-specific inspectors/generation.

Stable normalized object IDs are scoped to connection + catalog/database + schema/namespace + object kind + adapter identity. Display names are not identity. Introspection is lazy, cancellable, paged where possible, and cached with scope, byte/item ceiling, server/catalog version evidence where available, TTL, and invalidation rules.

Rename detection in schema diff is a scored proposal with explanation and confirmation; it is never silently accepted as identity.

## 10. Normalized data types

The core taxonomy includes:

| Group | Required fidelity fields/examples |
| --- | --- |
| Integer | signedness, bit width, precision |
| Decimal / floating point | precision, scale, exact/approximate, special values |
| String / text | length, collation, charset, fixed/variable |
| Boolean | native vs emulated representation |
| Date, time, datetime/timestamp | timezone semantics, precision, calendar assumptions |
| Interval | fields and precision |
| UUID | native/binary/text physical form |
| JSON / JSONB, XML | binary/text form and validation semantics |
| Binary / BLOB / large object | inline/deferred, length, locator lifetime |
| Enum / domain | allowed labels/base type/constraints |
| Array / composite / record | element/field descriptors and dimensions |
| Spatial / geometry | subtype, SRID, encoding |
| Network / bit string | family/length |
| Unknown/database-specific | raw type identity and lossless bytes/text policy |

SQL `NULL` is a value state, not a type group. Primary key, foreign key, generated/computed, modified, invalid, and deferred are orthogonal semantic/style traits.

Adapters perform raw-to-normalized mapping. The `ResultGrid` theme resolver maps normalized group and traits to text/background/font/icon/tooltip using app/connection/database/grid scope. No adapter chooses UI colors. Snapshot/UI tests cover Light, Dark, High Contrast, Color Blind Friendly, Minimal, non-color indicators, contrast warnings, theme-only invalidation, selection/scroll preservation, and pending edits.

## 11. Safe editing

An adapter produces a `RowIdentityPlan` from a primary key or proven unique non-null key. It records column identities, original typed values, null semantics, and any version/checksum predicate. If no safe plan exists, the grid is read-only by default.

The edit flow is:

1. collect pending changes without applying on scroll/refresh;
2. validate types and constraints locally where reliable;
3. generate deterministic parameterized SQL/operation preview;
4. show target connection/database/schema/table and production/read-only state;
5. obtain confirmation appropriate to risk;
6. execute under explicit transaction policy;
7. require expected affected-row count;
8. reconcile returned/refetched values or report optimistic conflict;
9. preserve or explicitly discard pending changes after failure.

Tests cover success, constraint failure, timeout, cancellation, rollback, zero/multiple affected rows, concurrent modification, key mutation, nullable unique keys, triggers, generated columns, lost connection, and tables/views without identifiers.

## 12. SQL parsing and generation

The dialect port supplies a tokenizer/parser/classifier appropriate to the adapter. Regex may provide highlighting hints but is never the only safety-critical parser.

Generated SQL must:

- quote identifiers and bind parameters according to exact dialect/version;
- avoid concatenating user input;
- escape literals only where parameter binding is impossible and test every case;
- be deterministic and displayable before dangerous execution;
- encode dependency ordering and reversible/irreversible markers;
- state transaction/implicit-commit behavior;
- preserve engine-specific options that normalization cannot safely rewrite.

Snapshot plus semantic integration tests cover Unicode identifiers, reserved words, case folding, embedded delimiters, comments/dollar quoting, multiple statements, procedural bodies, version branches, and malicious input.

## 13. Engine plans

### 13.1 PostgreSQL — M2

Candidate driver: `tokio-postgres`, subject to M0 adoption gate. DF-M0-002
completed its disposable matrix, but ADR-0009 defers the exact
`tokio-postgres 0.7.18`/`tokio-postgres-rustls 0.14.0` stack because upstream
backend frames are buffered without a product hard cap, request admission is
unbounded, and logging/credential-memory controls require an explicit adapter
policy. No production capability is approved from the spike.

Prove SSL modes with hostname verification/custom CA/client certificate, cancel-token race handling, row streams/portals, arrays/enums/domains/composites/ranges/JSONB/large objects, notices, multiple result sets/script semantics, search path, transaction-aborted state, materialized views/extensions/routines, `EXPLAIN` safety, `COPY` streaming, and official `pg_dump`/`pg_restore` orchestration constraints.

### 13.2 MySQL — M3

Candidate driver: `mysql_async`, subject to adoption gate.

Prove MySQL authentication plugins, rustls/platform roots, server certificates, text/binary protocol type fidelity, unsigned integers, zero dates/timezone behavior, result streams, multi-result sets, cancellation strategy, `sql_mode`, charset/collation, generated columns, events/routines, storage-engine transaction conditions, implicit commits, `EXPLAIN`, and official tool packaging.

`LOCAL INFILE` is disabled by default. If later enabled, it uses a one-operation allowlisted user-selected file source with size/path controls; a malicious server cannot request arbitrary local files.

### 13.3 MariaDB — M3

Reuse only validated wire-level infrastructure. Maintain separate server-version, authentication, SQL mode, JSON/type, generated/returning, metadata, optimizer, backup-tool, and capability tests. Product copy must not promise MySQL parity.

### 13.4 SQLite — M3

Candidate driver: `rusqlite` on a bounded dedicated blocking lane.

Open user-selected database files with explicit read-only/read-write-create mode and bookmark handling. Prove busy timeout, WAL/journal behavior, interrupt, attached databases, pragma safety, affinity versus declared type, strict tables, generated columns, `WITHOUT ROWID`, `RETURNING` version gates, transaction/savepoint semantics, file-change coordination, backup API, corruption errors, symlink/path policy, and safe atomic-copy/export behavior.

The app's local metadata SQLite database is a separate infrastructure store and can never be selected as a user database target.

### 13.5 Phase 2 engines — M6

- SQL Server: evaluate TDS driver maintenance/license, TLS, Azure/AD authentication on macOS, integrated auth constraints, cancellation, multiple results, plans, schemas, temporal/spatial types, and official tools.
- Redis: capability-driven command browser, keyspace scan without blocking, TTL/type-aware views, cluster/sentinel/TLS/auth behavior, dangerous command classification; no relational schema fiction.
- MongoDB: official Rust driver candidate, TLS/SRV/auth, cursor streaming, transactions/topology conditions, BSON fidelity, collection/index/validator model, aggregation explain, and model-specific editing.

### 13.6 Phase 3 evaluation

Oracle requires a separate legal/client-library/distribution decision; never bundle an Oracle client without license approval. Cloud engines require authentication/token renewal, endpoint verification, cost/warehouse semantics, and terms review. Compatible-wire engines still receive separate capability tests because protocol compatibility does not prove dialect/metadata/transaction compatibility.

## 14. Backup, restore, monitoring, and administration

These are optional capability families, never simulated dangerously.

Native tool execution uses `Process`/direct executable APIs with an argument vector, sanitized minimal environment, no shell interpolation, secure temporary files, restricted permissions, stdout/stderr redaction, cancellation/termination escalation, signature/version discovery, and cleanup. Credentials prefer protected channels supported by the tool; they are never written to command arguments or long-lived temp files. Restore validates target/environment and shows consequences before execution.

Monitoring/kill/cancel actions check capability and server permission, show target/session context, classify risk, and require confirmation. User/role changes display deterministic SQL/operation preview and never expose generated credentials.

## 15. Adapter conformance suite

Every declared capability maps to tests. At minimum:

- connect/disconnect/reconnect, invalid config, auth failure, TLS trust/hostname/client certificate;
- when SSH is enabled, tunnel integration at the connection-service layer,
  per-hop changed/revoked keys, connector-level no-direct trap and complete
  tunnel cleanup;
- read-only enforcement and production context;
- query success, syntax/constraint/network errors, timeout, cancellation race, connection reuse/poisoning;
- bounded million-row stream, slow consumer/backpressure, large cell/deferred BLOB, multiple result sets;
- begin/commit/rollback/savepoint, close warning state, connection loss, implicit DDL commit behavior;
- metadata lazy load/refresh/cache invalidation, quoted/unusual identifiers, privilege-limited catalogs;
- normalized type round trips and database-specific descriptor retention;
- generated SQL snapshots plus execution semantics;
- row edit success/failure/conflict/rollback/wrong-row prevention;
- import/export/transfer cancellation and partial artifacts when capability enters scope;
- capability truthfulness: unsupported/conditional functions never appear enabled.

Tests use disposable containers or ephemeral isolated databases with deterministic fixtures and cleanup. Destructive suites require a test-only hostname/database marker and abort on production/staging/shared targets. Supported oldest/current server versions and relevant TLS/auth modes form the CI matrix; no production credential enters logs.

## 16. Adapter definition of done

An adapter/feature is complete only when:

- capability schema and server/version conditions are documented;
- driver dependency has license, advisory, maintenance, transitive, Apple Silicon, binary-size and replacement review;
- success, failure, cancellation, timeout, transaction/rollback, security and type/dialect regressions pass;
- result and metadata paths are demonstrably bounded;
- TLS/SSH policies fail closed and secret-leak tests pass;
- generated SQL is previewable, deterministic and tested;
- user-facing errors are typed, redacted and actionable;
- performance budgets pass on named fixtures;
- documentation and risk register are updated;
- no unsupported capability is represented as complete.

## 17. Open questions and spikes

- Measure driver cancellation and post-cancel connection safety for every MVP engine.
- Decide platform trust integration versus bundled roots per Rust TLS stack without introducing a global bypass.
- Validate all required MySQL/MariaDB authentication modes and whether a single driver is sufficient.
- Define SQLite file coordination behavior when another process modifies/replaces the database.
- Establish supported server-version policy and deprecation cadence before beta.
- Decide how to expose engine-specific objects without leaking driver types into common domain/UI contracts.
- Benchmark normalized value representation and FFI chunk encoding against the performance budget.
- Evaluate official backup tool license, signature, availability, version compatibility, progress and cancellation separately per engine.
