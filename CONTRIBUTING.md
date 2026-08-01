# Contributing to DataForge

DataForge is currently in planning. This document describes the gate for future implementation and does not authorize production code in this planning task.

## Before changing anything

1. Read the nearest `AGENTS.md`, the root `README.md`, relevant `docs/`, ADRs, and the issue/task scope.
2. Run `git status --short --branch`; preserve unrelated work and never use destructive Git commands to clean it.
3. Identify the feature module, application/domain/adapter boundary, security and database-safety impact, existing tests, and documentation that must change.
4. Write a short plan naming files, tests, performance measurement, database/write safeguards and risks. For public FFI, capability, persistence, security or distribution changes, add or update an ADR without rewriting history.
5. Do not add production code until the user/maintainer has explicitly requested implementation after reviewing the planning pack.

## Architecture rules

- UI calls application services, never database drivers directly.
- Application services depend on domain capability interfaces; adapters own dialect and driver behavior.
- Credentials are Keychain-only. Connection exports, local metadata, logs, diagnostics, snapshots and tests must not contain plaintext secrets.
- Rust database/core work is typed, cancellable, streaming and bounded; no avoidable `unsafe`, `unwrap`/`expect` on input/network/database/file paths, unbounded channels or unmanaged tasks.
- Swift UI state is `MainActor`; database/file/network work is off-main and cancellation-aware.
- FFI uses the versioned contract, opaque handles and chunked pull/ack semantics. A public contract change requires compatibility and integration tests.
- Destructive SQL, writes, migrations, synchronization, restore, administration and row edits must have preview/confirmation/transaction/rollback behavior appropriate to risk.
- Never copy source, assets, names, copywriting, private APIs or proprietary protocols from commercial products. Keep product identity original.

## Dependency gate

Before adding a dependency, follow the complete
[dependency and supply-chain policy](docs/DEPENDENCY_POLICY.md): record its
exact version/source/checksum, license and commercial-use compatibility,
maintenance activity, multi-source security advisories, Apple Silicon/macOS
support, binary-size delta, transitive tree and replacement cost. Prefer the
standard library or existing dependencies when adequate. GPL/AGPL, unclear
binaries or hosted-service terms require explicit legal review; no dependency
is approved merely because it appears in a planning table, spike or SBOM.

## M0 owner waiver and future reviews

[ADR-0017](docs/adr/0017-m0-owner-review-waiver.md) records the repository
owner's decision that the eight lanes in the
[M0 external review packet](docs/reports/M0-external-review-packet.md) are not
required for M0 planning exit. They are waived, not completed; no agent may
invent a reviewer, result or date.

The waiver does not approve a dependency, production implementation,
accessibility runtime result, license, security exception or release. Any
future review result must still be attributable, scoped and dated. Record only
a non-privileged disposition summary and never commit legal advice, private
contact details, signatures, credentials or customer/database data.

## Testing and database safety

Every production change needs relevant happy path, failure, edge, cancellation and security regression coverage. Database writes also need rollback/partial-outcome evidence. Integration tests use disposable containers, ephemeral databases or isolated schemas with a destructive guard; never production or shared staging. Test credentials are fake/CI-managed and are never printed.

Required test categories when applicable:

- unit/property/fuzz for classifier, SQL generation, normalization, redaction and import/export;
- FFI ownership, ABI, panic, streaming and cancellation;
- adapter integration for TLS/SSH, metadata, query, transaction, CRUD, cancel and capability truth;
- UI/accessibility/keyboard/dark-mode workflows;
- security hostile-input, secret-leak, formula/path/command injection, update-signature tests;
- performance/streaming/grid/diff benchmarks with named fixtures.

## Validation commands

Once Swift/Rust manifests exist, use the repository-pinned equivalents of:

```bash
swiftformat --lint .
swiftlint
xcodebuild build
xcodebuild test
cargo fmt --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo deny check
cargo audit
```

Do not claim a command passed unless it was run. If a command cannot run, report the exact command, reason, untested scope and remaining risk. Do not skip or weaken assertions, or increase timeouts to hide flakiness.

## Pull request checklist

- [ ] Scope and files match the approved task; no unrelated refactor or artifact.
- [ ] `AGENTS.md`, relevant ADR/capability/security/safety docs updated.
- [ ] No secret, real database data, build artifact or personal IDE state is included.
- [ ] Error category, retryability, user-safe message and redacted diagnostics are defined.
- [ ] Cancellation and transaction/pending-edit close behavior are handled.
- [ ] Generated SQL is deterministic, parameterized and previewable where risky.
- [ ] UI has loading/empty/error/cancel states, connection/production context, keyboard and accessibility labels.
- [ ] Memory/queue/cache ownership and performance measurement are documented.
- [ ] Unit/integration/UI/security/performance tests required by scope pass.
- [ ] Review commands and results, not intentions, are included in the handoff.

## Commit and release hygiene

Commits should be small and purposeful. Never commit credentials, `.env` secrets, real database dumps, crash payloads, update keys, build artifacts or unapproved licenses. Do not force-push without explicit direction. Release work additionally requires signatures, SBOM, dependency/license review, notarization evidence and update tamper tests described in [DISTRIBUTION_STRATEGY.md](docs/DISTRIBUTION_STRATEGY.md).
