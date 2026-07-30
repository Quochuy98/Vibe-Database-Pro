# ADR-0006: Direct Developer ID distribution first

Status: Accepted for planning; release pipeline spike required

Date: 2026-07-29

## Context

The app needs arbitrary database network endpoints, SSH tunnels, user-selected files, signed helper processes, native backup/restore tools and future background jobs. Distribution must preserve macOS trust while supporting these professional workflows.

## Options considered

1. Direct distribution with Developer ID.
2. Mac App Store with App Sandbox.
3. Both channels from one binary.
4. Unsigned/manual distribution.

## Decision

Ship the first product directly: Developer ID Application signing, Hardened Runtime, secure timestamp, notarization, stapled ticket and a signed update channel. Do not enable App Sandbox for the initial direct build, but use least privilege, minimal entitlements, user-selected file access, secure helpers and process isolation. Sparkle 2 is the leading updater candidate after security/license/integration review.

MVP targets macOS 14+ and Apple Silicon. Keep source portable; Universal 2 becomes a separate measured release decision. The Mac App Store is a separately engineered product/channel, not a build flag on the same artifact.

## Reasons

- Direct distribution better fits native database utilities, helpers, SSH/file workflows and professional release cadence.
- Developer ID + notarization integrates with Gatekeeper.
- A single initial channel limits entitlement, packaging and test matrices.

## Trade-offs and risks

- The team owns secure update hosting/signing, rollback, availability and incident response.
- No App Sandbox increases the consequence of a compromise; isolation and least privilege become critical.
- Direct acquisition has less App Store discovery/purchase integration.
- Apple policy/tooling and dependency signing requirements can change.

## Consequences

- Sign every nested executable/library/helper correctly; never rely on `codesign --deep` as a release procedure.
- CI produces SBOM, provenance/checksums, entitlement diff, signature verification, notarization log and tamper tests.
- Update private keys are separated from build workers with rotation/revocation procedures.
- Crash reporting/telemetry remain independent opt-ins, not bundled into updates.
- MAS feasibility is reviewed later against sandbox file bookmarks, subprocess/native tools, helpers, background execution, updates and review policy.

## Validation before implementation

- Empty Swift/Rust shell archives, signs, validates Hardened Runtime, notarizes, staples and passes Gatekeeper on a clean supported Mac.
- Update feed accepts a valid newer artifact and rejects altered payload, signature, downgrade and wrong channel.
- Helper/XPC signatures and designated requirements are verified.
- Apple Silicon driver/native tool/binary-size tests pass; Universal claims are absent.

## Revisit when

App Store demand justifies a separate constrained SKU, enterprise deployment needs signed packages/MDM, Apple policy changes, or Sparkle fails its adoption/security gate.
