# ADR-0014: Retain SQLite/Keychain separation; keep implementation gated

- **Status:** Accepted for planning; GRDB and production persistence/Keychain implementation gated
- **Date:** 2026-07-30
- **Related:** ADR-0004, ADR-0005, DF-M0-007, R-16, R-21, R-23, R-25, R-29, T01

## Context

ADR-0004 recommends non-sensitive application metadata in SQLite behind a
small Swift persistence port. ADR-0005 requires every secret to remain in the
macOS Data Protection Keychain, with only an independent random credential
reference outside Keychain and no plaintext fallback.

DF-M0-007 had to test this boundary before production planning could depend on
it. The exact findings are recorded in the
[DF-M0-007 evidence report](../reports/DF-M0-007-persistence-keychain-evidence.md).

## Findings

Exact GRDB `7.11.1` migrated a synthetic v1 metadata database to v2 while
retaining profile, workspace and bounded history semantics. A deliberately
throwing migration left no partial schema, data or marker. An unknown future
marker was rejected without byte mutation or auto-rebuild. An uncommitted
child-process write rolled back after exit, a corrupt copy failed closed while
the original remained intact, four fixed pool workers completed 100 writes,
retention was deterministic, and a checkpointed online backup passed
integrity/foreign-key checks.

The schema contained only non-sensitive metadata and a random UUID credential
reference. Owner-only permissions covered SQLite, WAL/SHM when present,
backup, export, snapshot and log surfaces. The fake canary was absent from the
specified transient/retained files, output, process-command snapshot and Git.

Actual Data Protection Keychain CRUD did not pass. The unsigned Command Line
Tools executable received `errSecMissingEntitlement` on add. The exact item
lookup returned `errSecItemNotFound`, so the failure created no item and no
plaintext fallback occurred. Returned accessibility/synchronization
attributes, actual duplicate, locked/denied ACL and independent actual-system
deletion therefore remain unsupported or partial. No user Keychain was
locked, reconfigured or enumerated to manufacture evidence.

The host had no full Xcode, XCTest module or code-signing identity. The
runner's `swift test` command failed at test-module emission with `no such
module 'XCTest'`; executable assertions passed, but they do not replace the 19
XCTest runtime intents.

Exact GRDB source, revision, MIT license file hash, empty point-in-time
upstream advisory result, normal dependency graph, toolchain requirements,
arm64 build and replacement path were recorded. The standalone probe was
5,780,048 bytes larger than a tiny Swift baseline; this is not an incremental
product binary estimate. GRDB has no normal Swift package dependency beyond
the system SQLite boundary, but legal and independent adoption review remain
open.

One 100-write observation measured DELETE/`DatabaseQueue` at 26.881 ms and
90,112 open bytes versus WAL/`DatabasePool` at 9.113 ms and 1,837,336 open
bytes. This one-host synthetic speed/space trade-off cannot select a product
journal policy.

The frozen outcome is `15 pass / 3 partial / 2 unsupported / 0 fail`, while
the complete Keychain, dependency-adoption and production-persistence gates
are false.

## Decision

1. **Retain SQLite behind a Swift persistence port.** The migration,
   corruption, crash, retention, backup and bounded-concurrency contracts are
   suitable planning inputs. The spike schema and code are not production
   assets.
2. **Retain exact GRDB `7.11.1` only conditionally.** Do not add it to a
   production manifest until full-Xcode tests, realistic size/performance,
   maintenance/security and final legal/notices gates pass.
3. **Retain macOS Data Protection Keychain as the only small-secret store.**
   Missing entitlement, lock, denial or cancellation must fail closed; SQLite,
   files, `UserDefaults`, logs, exports, diagnostics and memory caches are
   never fallbacks.
4. **Do not enable production persistence or credential handling.** A signed
   app with the intended Team/bundle/entitlement boundary must establish
   actual CRUD and attributes first.
5. **Select no production journal mode.** Repeat DELETE/WAL measurements with
   realistic workload, interruption, launch/RSS and minimum-host data.
6. **Keep credential and metadata deletion independent.** History/diagnostic
   deletion cannot delete a Keychain item; forgetting a credential cannot
   silently delete or rewrite profile/workspace metadata.
7. **Regenerate production code under review.** Do not promote or copy the
   disposable package wholesale.

## Required implementation lane

Implementation may be reconsidered only after a separately authorized
scaffold proves:

- full Xcode build/test and the retained migration, rollback, future-version,
  corruption, crash, concurrency, retention, backup, redaction and typed-error
  intents on minimum/current supported macOS hardware;
- signed Data Protection Keychain CRUD, returned
  `WhenUnlockedThisDeviceOnly`/non-synchronizable attributes, duplicate,
  missing, locked, denied, user-cancel and no-fallback behavior;
- explicit bundle ID/Team/access-group migration and separately reviewed
  helper/background access without weakening interactive credentials;
- production-schema migration/backup recovery, cancellation/interruption,
  realistic DELETE/WAL performance, launch/RSS, binary-size and long soak;
- seeded secret-negative tests across all persistence, export, diagnostics,
  crash, clipboard, process, IPC and helper surfaces; and
- exact license/notices, SBOM, provenance, advisory/maintenance review and an
  independent security/dependency approver.

## Consequences and residual risk

- M0 gains a concrete schema allowlist and recovery/security test contract but
  no production storage implementation.
- GRDB remains replaceable by direct SQLite or another reviewed wrapper behind
  the port; replacement requires migration/query and conformance work.
- Keychain availability is part of authentication configuration, never a
  reason to persist secret bytes elsewhere.
- R-16, R-21, R-23, R-25 and R-29 remain open. This evidence narrows their
  implementation tests but does not close signing, helper, dependency, secret
  memory or minimum-host risk.
- The canary never entered a successful actual Keychain item, so the run proves
  fail-closed/no-fallback behavior, not signed-app secret-at-rest integration.

## Disposal

The source is auditable at
`638886064b563aa3f472191c8edbf365a86d3feb`. The report, ADR and sanitized raw
evidence were recorded at `8cfa4b5125959eb70765d6807c508d5681bb3ee6`;
the disposable package was removed in separate commit
`02c86b7d05bdb0649fc9b2838b73c1eddfb2fa42`. Future production code must be
regenerated from this contract rather than copied from the spike.
