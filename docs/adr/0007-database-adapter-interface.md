# ADR-0007: Capability-based, driver-per-engine adapter ports

Status: Accepted for planning; PostgreSQL conformance spike required

Date: 2026-07-29

## Context

PostgreSQL, MySQL, MariaDB, SQLite and later engines differ in schemas, types, metadata, transactions, cancellation, DDL, backup, authentication and administration. A lowest-common-denominator API would hide dangerous semantic differences; driver models exposed to UI would destroy boundaries.

## Options considered

1. One generic multi-database/`Any` driver abstraction.
2. Driver types used directly by application/UI.
3. Capability-based domain ports with a driver selected per adapter.
4. Third-party plugins from MVP.

## Decision

Define small versioned domain ports for connection, capabilities, query stream, cancellation, transactions, metadata, dialect/generation, editing, transfer and optional administration. Implement each engine with the driver that best satisfies fidelity, safety, streaming and cancellation. Return normalized semantic models plus lossless engine descriptors. Plugins are absent in MVP; internal adapters preserve a future versioned seam.

## Reasons

- Capability snapshots make unsupported/conditional behavior explicit.
- Driver-per-adapter avoids silently losing engine-specific types and operations.
- Small ports permit conformance testing and UI independence.
- Normalized + lossless metadata supports common UX without destroying fidelity.

## Trade-offs and risks

- More code and CI matrices than one generic driver.
- Capability/version negotiation and normalized schema evolution are complex.
- Driver maintenance/licensing may force adapter replacement.
- Over-generalization remains possible without vertical-slice evidence.

## Consequences

- UI never guesses capabilities from engine names.
- Commands revalidate the capability snapshot and safety context at execution.
- Database-specific SQL and driver types remain inside their adapter.
- Every generated SQL dialect/version branch has deterministic snapshot and semantic tests.
- Optional operations are absent/unsupported, never dangerously emulated.
- Candidate drivers are recommendations only until dependency adoption gates pass.

## Validation before implementation

- PostgreSQL vertical conformance proves connect/TLS, lazy metadata, typed bounded stream, cancellation race, transactions, errors, keyed edits and export.
- Fake adapters verify capability-driven UI and stale-capability rejection.
- MySQL/MariaDB/SQLite M3 design review demonstrates no PostgreSQL-only assumptions.
- Dependency/license/advisory/Apple Silicon/binary-size/replacement evidence for each driver.

## Revisit when

Two or more adapters cannot express required semantics safely, a driver becomes unmaintained/incompatible, or an out-of-process plugin model is approved. Changes version the contract and preserve compatibility/migration evidence.
