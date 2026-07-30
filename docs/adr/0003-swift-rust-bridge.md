# ADR-0003: Versioned C ABI for the Swift/Rust bridge

Status: Accepted for planning; implementation gated by an ownership/streaming spike

Date: 2026-07-29

## Context

Swift and Rust must exchange commands, typed metadata, errors and bounded result chunks. The boundary must define ownership, lifecycle, cancellation, threading, version compatibility and panic containment without transferring an entire result set.

## Options considered

1. UniFFI-generated Swift bindings.
2. Hand-designed C ABI with generated C header and Swift facade.
3. C++/Swift interoperability layer.
4. Separate XPC process/protocol for all core calls.

## Decision

Use a narrow versioned C ABI with fixed-width small records, tagged enums, length-delimited buffers and opaque integer handles. A hand-written Swift facade exposes typed `async` APIs/`AsyncSequence`. Swift pulls bounded chunks, acknowledges ownership, and propagates cancellation. Each exported Rust entry catches panic and returns a controlled error. Runtime ABI handshake rejects incompatible pairs.

## Reasons

- Maximum control over streaming demand, allocation ownership and cancellation semantics.
- Stable platform toolchain interop without exposing Rust layout/lifetimes.
- Explicit contracts are appropriate for a safety-critical database stream.
- Does not require the entire core to be out of process in MVP.

## Trade-offs and risks

- More boilerplate and manual compatibility tests than generated binding tools.
- Callback executor/reentrancy mistakes can deadlock or update UI off-main.
- Handle leaks/use-after-release/double release are severe risks.
- ABI evolution requires disciplined additive versioning.

UniFFI remains a viable alternative and has production-quality Swift support, but its fit for this product's chunk backpressure, cancellation, binary stability and lifecycle model must be proven, not assumed. XPC remains appropriate for future plugin/helper isolation, not a replacement for every high-throughput in-process call unless security/performance evidence changes.

## Contract consequences

- No borrowed cross-boundary references, complex lifetimes, Rust enums/traits/classes, Swift closures retained without an explicit token, or raw secret-bearing debug strings.
- Result chunk limits use both bytes and rows.
- Release is idempotent; invalid/stale handles return typed errors.
- Cancellation outcome is distinct from operation completion.
- FFI thread contract and callback ordering are documented per function.

## Validation before implementation

- 1M-row fake stream demonstrates bounded RSS under slow consumer/backpressure.
- Cancel at every lifecycle point; no post-terminal callbacks.
- Panic, allocation failure, malformed buffers, ABI mismatch, double release, leak and concurrent release tests.
- Thread/Address sanitizers where supported plus Swift/Rust integration suite.
- Copy/latency overhead meets the performance budget.

## Revisit when

UniFFI or another supported generator proves equivalent semantics with lower risk, XPC isolation becomes mandatory, or the contract needs a breaking shape. Any change uses a superseding ADR and compatibility migration.
