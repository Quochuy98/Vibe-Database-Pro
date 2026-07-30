# ADR-0004: SQLite metadata store behind a Swift persistence port

Status: Accepted for planning; library adoption gated by dependency review

Date: 2026-07-29

## Context

DataForge persists workspaces, drafts, saved queries, snippets, UI state, job summaries, preferences, non-sensitive connection metadata and bounded history. It must migrate deterministically, remain testable, support atomic transactions and never become a secret store.

## Options considered

1. SwiftData/Core Data.
2. SQLite via direct C API.
3. SQLite via GRDB in Swift.
4. SQLite owned by the Rust core.
5. JSON/plist files.

## Decision

Use one application SQLite metadata database behind a small Swift infrastructure protocol. GRDB is the leading implementation candidate, not yet an approved dependency. Use versioned transactional migrations, integrity checks, WAL only after measurement, bounded retention and minimal file permissions. Workspace/application models depend on the persistence port, not GRDB.

## Reasons

- Explicit schema and SQL migrations are inspectable and testable.
- Swift ownership serves UI/workspace state without FFI chatter.
- SQLite transactions and queries fit structured metadata/history.
- A port preserves replacement and helper-sharing options.

## Trade-offs and risks

- Migration and concurrency policy require ownership discipline.
- Query text/history may itself be sensitive and needs retention/deletion controls.
- A background helper would require a reviewed sharing/coordination model.
- GRDB adds a dependency and version/migration cost.

## Security and data rules

- Never store password, passphrase, private key, API key, token, client secret, or raw credential export.
- Store only random Keychain reference IDs; no recoverable secret-derived identifiers.
- No production row snapshots, clipboard data or full diagnostics payload by default.
- Crash-safe atomic drafts do not imply silently restoring a live connection/transaction.
- Users can delete history/diagnostics independently from credentials.

## Validation before implementation

- Migration upgrade/downgrade-failure, rollback, corruption, concurrent reader/writer and crash-recovery tests.
- Seeded-secret negative tests inspect the database and backups.
- Retention/secure deletion semantics and performance measured on large history/workspace fixtures.
- GRDB license, maintenance, advisories, Swift/Xcode/macOS requirements, binary size and alternatives reviewed.

## Revisit when

Helper sharing becomes a near-term requirement, GRDB fails adoption, encryption-at-rest requirements exceed platform/file protections, or a future schema needs a different storage model. Secrets remain Keychain-only under every alternative.
