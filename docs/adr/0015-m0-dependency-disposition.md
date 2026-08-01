# ADR-0015: Keep dependency adoption closed after the M0 dossiers

- **Status:** Proposed for independent engineering/security/legal review;
  fail-closed dispositions effective; no dependency adopted
- **Date:** 2026-08-01
- **Supersedes:** The conditional-retention statement for exact `russh 0.62.4`
  in ADR-0012; SSH remains disabled and all other ADR-0012 gates remain
- **Related:** ADR-0009, ADR-0012, ADR-0013, ADR-0014, DF-M0-008, R-04,
  R-21, R-25, R-29, T17

## Context

Earlier M0 spikes recorded useful exact driver, SSH, updater and persistence
candidate evidence, while architecture documents also named unpinned future
candidates. None had completed a single consolidated adoption gate covering
identity, checksum/provenance, full graph, license/notices, advisories,
maintenance, toolchain/platform, product size, replacement and independent
review.

DF-M0-008 consolidates 13 candidate rows in
[`DF-M0-008-dependency-adoption-dossiers.md`](../reports/DF-M0-008-dependency-adoption-dossiers.md),
adds a proposed [`DEPENDENCY_POLICY.md`](../DEPENDENCY_POLICY.md), indexes the
immutable disposed-spike graphs, generates an SPDX 2.3 candidate inventory and
runs a multi-source policy dry run.

The repository still has no production source, Xcode/Cargo/SPM manifest, test
target or release artifact. Legal counsel and independent engineering/security
reviewers have not supplied approval. Those facts prohibit an `approve`
disposition even where technical spike evidence is positive.

## New evidence after ADR-0012

On 2026-08-01, the official `russh` repository exposed 15 advisories. The newly
published repository advisory
[`GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg)
declares `russh <=0.62.4` affected and reports `0.62.5` as patched. The frozen
SSH lock still passed `cargo audit` and `cargo deny` because that repository
advisory had not appeared in their data path.

This is not a reason to ignore scanners; it is evidence that the adoption gate
must combine registry, RustSec/ecosystem, official repository, vendor and OS
project/build sources. The strongest current applicable finding wins
fail-closed.

Exact `0.62.5` is a new candidate with a new checksum. It does not inherit the
runtime evidence or conditional status of `0.62.4` and has not run the
ADR-0012 re-entry matrix.

## Decision

1. **Approve no production dependency.** The M0 summary is
   `0 approve / 10 defer / 3 reject`. No package may be added to a production
   manifest on the authority of M0 planning or spike records.
2. **Reject exact `russh 0.62.4`.** Do not use its positive Ed25519/trust spike
   evidence to retain this affected source. A new exact release may be
   reconsidered only after every current ADR-0012 gate and this policy pass.
3. **Continue rejecting the tested Apple OpenSSH build/native `ProxyJump/-J`
   and exact `ssh2 0.9.6`/`libssh2-sys 0.3.2`.** No unsafe fallback is created.
4. **Defer Tokio, the `tokio-postgres` stack, `mysql_async`, `rusqlite`, rustls,
   GRDB, tree-sitter, SQLx, Sparkle and Sentry Cocoa.** Each remains behind its
   architecture port/capability boundary with the machine-readable blockers in
   DF-M0-008.
5. **Adopt the multi-source fail-closed policy as the planning contract.** A
   clean scan cannot override an official current affected range. Unknown
   version/source/license/platform facts produce `defer`, not a guessed latest
   version or implicit approval.
6. **Treat the prototype SPDX document as candidate evidence only.** A release
   SBOM must be regenerated reproducibly from a separately authorized locked
   production build and reconciled with the final nested artifact.
7. **Keep legal/product decisions external and explicit.** Engineering cannot
   grant commercial compatibility, invent final license text or choose the
   Community/Pro model merely to close a scanner or backlog row.

## Re-entry criteria

A candidate can move from `defer` or a new version can replace a rejected
source only when all applicable items pass:

- exact immutable identity, checksum, minimal features and complete graph;
- current multi-source advisories and source/provenance policy;
- exact license/notices/service terms and qualified legal approval;
- supported MSRV/Swift/Xcode/macOS and minimum/current Apple Silicon evidence;
- release-like product size, signing/entitlement and artifact/SBOM
  reconciliation;
- feature-specific correctness, hostile-input, bounded-resource,
  cancellation, failure/rollback, secret/logging and cleanup tests;
- named engineering/security/legal owners, replacement/disable plan, review
  date and re-review trigger; and
- independent review by someone who did not author and solely control the
  evidence or signing identities.

Changing only the version number, accepting a permissive-looking SPDX string,
or obtaining a clean single scanner result cannot satisfy re-entry.

## Consequences

- PostgreSQL production implementation remains blocked by ADR-0009's frame,
  request, logging and credential-memory gates, not merely licensing.
- SSH remains absent. The new reject disposition reduces ambiguity but does
  not require SSH for a future direct PostgreSQL/TLS slice.
- GRDB and Sparkle remain replaceable conditional planning inputs; no manifest
  or framework integration is authorized.
- Unpinned MySQL/SQLite/parser/alternative-driver/crash-SDK candidates remain
  visible without creating false precision.
- The M0 engineering dossier is ready for human review, but DF-M0-008's
  Definition of Done remains false until engineering/security/legal reviewers
  sign it.
- DF-M0-009 wireframe/accessibility review may proceed independently while the
  dependency adoption gate stays closed.

## Evidence integrity

The raw records live under `docs/reports/data/DF-M0-008/`. They contain no
credential, database row, production endpoint or active manifest. Historical
lock/resolution files are referenced by Git commit, path and SHA-256 so the
disposed spike sources remain auditable without being reintroduced as active
dependencies.
