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
| [0008](0008-m0-ffi-spike-disposition.md) | M0 C ABI spike evidence and caller-owned buffer refinement | Evidence recorded; implementation gated |
| [0009](0009-m0-postgres-driver-disposition.md) | Defer exact PostgreSQL driver stack pending hard resource/security caps | Candidate deferred; production gated |
| [0010](0010-m0-textkit-editor-disposition.md) | Conditionally retain TextKit 2 after the M0 editor spike | Planning candidate retained; production gated |
| [0011](0011-m0-grid-disposition.md) | Reject full-grid `NSTableView`; evaluate a bounded custom native renderer | Replacement planning candidate selected; production gated |
| [0012](0012-m0-ssh-disposition.md) | Defer SSH capability after the tunnel/host-trust spike | Superseded only for exact russh 0.62.4 retention by ADR-0015; production SSH disabled |
| [0013](0013-m0-distribution-disposition.md) | Retain direct distribution planning after the M0 release-chain spike | Developer ID/updater implementation gated |
| [0014](0014-m0-persistence-keychain-disposition.md) | Retain SQLite/Keychain separation after the M0 persistence spike | GRDB conditional; production persistence/Keychain gated |
| [0015](0015-m0-dependency-disposition.md) | Keep dependency adoption closed; reject exact russh 0.62.4 after fresh advisory | Accepted for M0 planning by ADR-0017; 0 approved, production adoption disabled |
| [0016](0016-m0-wireframe-accessibility-disposition.md) | Conditionally retain five M0 wireframes with a focus/accessibility/safety contract | Accepted for M0 planning by ADR-0017; production UI gated |
| [0017](0017-m0-owner-review-waiver.md) | Waive independent external review as an M0 exit gate without fabricating approval | M0 planning exit accepted; production implementation/adoption/release still gated |

## ADR lifecycle

1. Proposed: alternatives and evidence are ready for review.
2. Accepted for planning: other plans may depend on the recommendation.
3. Accepted for implementation: required spike/security/legal evidence passed and implementation is separately authorized.
4. Superseded: a later ADR changes the decision and retains this context.
5. Rejected: recommendation must not be used.

Public FFI, security model, persistence schema ownership, distribution channel, database capability semantics, or plugin boundary changes require an ADR.
