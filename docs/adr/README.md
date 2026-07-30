# Architecture Decision Records

ADRs preserve why a material decision was made. They are immutable once superseded: a changed decision receives a new ADR that links to the old one instead of rewriting history.

“Accepted for planning” means the recommended architecture is authoritative for specifications and spikes. It does **not** authorize production implementation or dependency adoption. Each ADR lists evidence required before its implementation gate opens.

| ADR | Decision | Planning status |
| --- | --- | --- |
| [0001](0001-ui-technology.md) | SwiftUI shell with focused AppKit components | Accepted for planning |
| [0002](0002-core-language.md) | Swift UI/application plus Rust data core | Accepted for planning |
| [0003](0003-swift-rust-bridge.md) | Versioned C ABI with opaque handles | Accepted for planning |
| [0004](0004-local-persistence.md) | SQLite metadata store behind a Swift persistence port | Accepted for planning |
| [0005](0005-secret-storage.md) | macOS Keychain for all secrets | Accepted for planning |
| [0006](0006-distribution-model.md) | Direct Developer ID distribution first | Accepted for planning |
| [0007](0007-database-adapter-interface.md) | Capability-based, driver-per-adapter ports | Accepted for planning |

## ADR lifecycle

1. Proposed: alternatives and evidence are ready for review.
2. Accepted for planning: other plans may depend on the recommendation.
3. Accepted for implementation: required spike/security/legal evidence passed and implementation is separately authorized.
4. Superseded: a later ADR changes the decision and retains this context.
5. Rejected: recommendation must not be used.

Public FFI, security model, persistence schema ownership, distribution channel, database capability semantics, or plugin boundary changes require an ADR.
