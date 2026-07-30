# ADR-0009 — Defer the exact PostgreSQL driver candidate after M0

- **Status:** Accepted as a spike disposition; candidate deferred
- **Date:** 2026-07-30
- **Supersedes:** None
- **Related:** ADR-0007, ADR-0008, DF-M0-002 evidence report

## Context

DF-M0-002 evaluated a pinned PostgreSQL 17.10 arm64 disposable fixture with
`tokio-postgres 0.7.18`, `tokio-postgres-rustls 0.14.0` and `rustls 0.23.43`.
The durable command/results record is
[`DF-M0-002-postgres-driver-evidence.md`](../reports/DF-M0-002-postgres-driver-evidence.md),
and the exact disposable source is commit
`150ef5b200b8713d03592d91589d8ae54f8146c8`.

The matrix passed valid and invalid TLS/custom-CA/hostname/mTLS cases, typed
million-row streaming, row/byte/cell admission, cancellation and race cases,
commit/failure/rollback/lost-connection transaction cases, redaction scans and
fail-closed fixture cleanup. The dependency graph also passed the current
RustSec, license, source and ban checks after removing unmaintained
`rustls-pemfile`.

## Findings

The candidate does not satisfy the product safety contract as-is:

1. The normal `tokio-postgres` codec accumulates a complete backend frame
   before application row/cell admission. A safe full 8 MiB malicious frame
   was accepted by the wire buffer even though the application cap is 4 MiB.
   A header-only 8 MiB probe did not eagerly allocate the full body; the
   finding is the streamed-body behavior, not a claim about header-only
   preallocation.
2. The client request channel is unbounded. Response backpressure of one item
   does not bound concurrent request submission.
3. Upstream debug/query/parameter and server-notice logging requires an
   explicit deny/redaction policy before product diagnostics can be enabled.
4. Password and SCRAM process-memory copies are not end-to-end zeroized by the
   upstream types; the spike-owned copy alone is cleared.

These are security/data-availability and credential-lifetime concerns, not
performance polish. The exact candidate therefore cannot be marked adopted.

## Decision

**Defer the exact stack.** It remains a candidate for comparison only and must
not be copied into a production adapter or presented as a supported capability.

The architecture keeps a PostgreSQL driver factory behind the adapter boundary
so a reviewed connector can be substituted without leaking driver types into
UI or domain code. No global insecure TLS mode, automatic write retry or hidden
commit is introduced.

## Re-entry criteria

Reconsider only after a maintained upstream patch, reviewed fork or equivalent
decrypted-stream boundary provides a hard frame cap; a bounded request
admission/semaphore contract; an enforced diagnostic logging policy; and an
explicit Security decision on credential-memory zeroization. The full DF-M0-002
matrix, dependency dossier, arm64 size check and supported-version policy must
then pass again. A replacement such as `sqlx-postgres` or libpq is not presumed
safe and must run the same hostile-server and transaction tests.

## Consequences

- PostgreSQL production implementation remains blocked at the M0 gate.
- The positive TLS, typed-row, cancellation and transaction evidence is useful
  for future adapter conformance tests but does not grant capability approval.
- The disposable source is deleted after this ADR/report are committed; no
  prototype code is imported into the product.
- Dependency/legal review remains a release gate even though the technical
  license allowlist and advisory scan passed.
