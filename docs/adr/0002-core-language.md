# ADR-0002: Swift application with a Rust database/data core

Status: Accepted for planning; implementation gated by M0 build and FFI spikes

Date: 2026-07-29

## Context

The product needs native macOS UI plus safe, cancellable, streaming database protocols, metadata normalization, parsing, import/export, diff, transfer and background pipelines. The core must keep database-specific behavior out of UI and support bounded concurrency.

## Options considered

1. Swift only.
2. Swift UI/application plus Rust core.
3. Objective-C/C++ core.
4. Web/runtime application with Rust sidecar.

## Decision

Use Swift/SwiftUI/AppKit for presentation, macOS services and application orchestration. Use safe Rust for database adapters, query execution/streaming, cancellation, normalization, dialect/safety logic and data-intensive pipelines. Keep Keychain and native UI platform integration in Swift unless a later boundary decision proves otherwise.

## Reasons

- Swift is the first-class macOS UI and Security.framework language.
- Rust provides memory safety, strong typed errors, explicit ownership and a mature async/database ecosystem for untrusted servers and large streams.
- A portable core reduces duplicated engine logic if future approved surfaces appear.
- The split matches the repository's required architecture boundary.

## Trade-offs and risks

- FFI ownership, cancellation, build, packaging, symbolication and two-language expertise increase cost.
- Rust driver capabilities and licenses vary; no crate is approved by this ADR.
- Cross-language types must remain small and stable.
- A panic or secret leak at the boundary would be severe without containment/tests.

## Consequences

- Rust production code forbids avoidable `unsafe`, input/network/file/database `unwrap`/`expect`, unmanaged tasks, unbounded channels and blocking async workers.
- Swift strict concurrency is enabled where supported; UI state is `MainActor`.
- Database models and adapters do not depend on SwiftUI/AppKit.
- FFI and cross-language integration require tests and an ADR for public contract change.

## Validation before implementation

- Reproducible `arm64` build and signed/notarized empty shell with Rust library.
- Streaming/cancellation/panic/error/ownership spike passes sanitizers and bounded-memory test.
- Incremental/release build-time and binary-size budgets are recorded.
- Candidate drivers pass dependency and security adoption gates.

## Revisit when

The bridge cannot meet safety/performance/release requirements, staffing cannot responsibly maintain two languages, or Swift-native drivers demonstrably meet the complete capability/streaming/cancellation matrix with lower total risk.
