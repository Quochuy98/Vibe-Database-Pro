# Distribution Strategy

Status: Recommended direct-distribution baseline; channel decision gated by release spike

Last updated: 2026-07-29

## 1. Recommendation

DataForge should ship its first public product through direct Developer ID distribution. The initial release targets macOS 14+ and Apple Silicon. It uses Hardened Runtime, secure timestamps, signed nested code, notarization, stapled tickets and a cryptographically verified update channel. A Mac App Store edition is a separately engineered channel with its own entitlement, helper, file-access, update, review and test matrix; it is not assumed to be the same binary.

This recommendation is a planning decision, not evidence that a release artifact exists. Milestone 0 must prove the empty shell can be signed, notarized, installed, updated and tamper-rejected on a clean Mac.

## 2. Channel decision matrix

| Concern | Direct Developer ID (recommended first) | Mac App Store (separate future channel) |
| --- | --- | --- |
| Signing | Developer ID Application/Installer, Hardened Runtime, secure timestamp, notarization | Mac App Distribution/Store signing and App Review pipeline |
| Gatekeeper/trust | Notarization ticket stapled/online; release verifies `spctl`/codesign | Store distribution includes Apple review/security checks |
| App Sandbox | Optional for outside-Store distribution; initial app does not enable it, but least privilege still required | Mandatory App Sandbox; every file/network/helper entitlement justified |
| User-selected files | Security-scoped bookmarks/NSOpenPanel still used; no broad file assumption | Security-scoped bookmarks and sandbox extension lifecycle are mandatory |
| SSH tunnels | In-process library candidate; helper/XPC entitlement review | Same only if sandbox/network/Keychain constraints pass; no shell escape assumption |
| Native DB tools | Bundle only signed, licensed, supported executables; direct argv/no shell | Subprocess and embedded-tool review/entitlements may block some tools |
| Backup/restore | Easier to support user-selected binaries/files, still secure and signed | Sandbox path/tool/restore limitations can make capabilities unavailable |
| Network DB access | Outbound client policy documented and tested | `com.apple.security.network.client`, endpoint behavior and review required |
| LaunchAgent/background | Direct product can evaluate signed `SMAppService` helper; user approval and Keychain policy | Login/background/helper policies and review are stricter; no guarantee while logged out/sleep |
| Auto-update | Sparkle 2 candidate, EdDSA + Apple code-signature verification, signed feed | Store handles app updates; separate feature/config path |
| Release cadence | Team-owned feed, rollback, incident response and key rotation | Store review/propagation constraints |
| Plugins | None MVP; future signed out-of-process only | Same plus sandbox/store review |
| Crash/telemetry | Opt-in service or local diagnostics; no hidden collection | Store privacy disclosures and consent still required |
| Purchase/tiers | Direct licensing service or offline license, designed without secrets in metadata | StoreKit/receipt and review requirements; do not couple safety to tier |
| Primary risk | Update signing/feed compromise and broader process privileges | Capability gaps, entitlements, review rejection, two artifact matrices |

## 3. Direct artifact topology

```text
DataForge.app/
  Contents/MacOS/DataForge                 # signed arm64 executable
  Contents/Frameworks/DataForgeCore.dylib  # signed Rust core
  Contents/Library/LaunchAgents/...         # optional, post-MVP, signed and consented
  Contents/Library/LoginItems/...           # optional, separately reviewed
  Contents/Resources/                       # non-executable resources only
```

Nested code is signed with its intended designated requirement and entitlements. Release procedures verify each item individually; they do not use `codesign --deep` as a substitute for understanding nested code.

MVP is arm64-only. A Universal 2 artifact is not advertised or shipped until a superseding ADR defines driver/native-tool parity, Intel test hardware/CI, binary-size budget, FFI layout/atomicity checks and support policy.

## 4. Signing, notarization and provenance

Release pipeline requirements:

1. Build from a clean, pinned source revision and locked dependencies.
2. Generate an SBOM, dependency/license report, source provenance and reproducible artifact manifest.
3. Sign app, Rust dylib, helper/XPC/native tools and installer/DMG with correct Developer ID identities and secure timestamps.
4. Enable Hardened Runtime; every exception is documented, minimized, threat-reviewed and tested.
5. Verify entitlements/designated requirements and architecture slices before upload.
6. Submit with Apple’s supported notarization tooling; retain request ID/log and staple ticket.
7. Test Gatekeeper/install/launch on a clean supported Mac and after quarantine transfer.
8. Publish checksums, release notes, supported OS/architecture, dependency notices and rollback instructions.

No private signing key, update private key, notarization credential, database credential or cloud token enters Git, an artifact, a build log or a user-facing diagnostic.

Apple platform policy and tooling are time-sensitive. Revalidate [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Developer ID](https://developer.apple.com/support/developer-id/), [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) and [App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) at every release-candidate cycle.

## 5. Update strategy

Sparkle 2 is the leading candidate for direct updates because its planning documentation describes EdDSA and Apple code-signature verification, atomic-safe installs and sandbox support. Adoption remains gated on current license, maintenance, helper entitlements, signing workflow and a security review.

Required update policy:

- HTTPS transport with authenticated host/certificate validation;
- pinned application update public key embedded in a signed release-controlled resource;
- verify feed metadata, EdDSA signature, Apple code signature/designated requirement and expected channel/architecture/OS before install;
- reject altered, unsigned, expired, replayed, downgraded or wrong-channel artifacts;
- download to restricted temporary location, verify before replacing, and preserve rollback path;
- separate beta/stable channels with explicit user choice;
- critical security update can be highlighted, never silently install an unverified payload;
- key rotation has signed overlap/revocation procedure and offline recovery;
- update UI shows version, source, signature state and restart consequence;
- update logs contain IDs/status, not URLs with tokens or user data.

Manual update is the safe fallback if the updater is unavailable; the app must fail closed rather than execute an unverified downloaded binary.

## 6. App Sandbox impact assessment

If a Store channel is pursued, explicitly prototype and test:

- network client entitlement and any server discovery needs;
- user-selected import/export/backup paths with security-scoped bookmarks;
- bookmark persistence/restoration and stale/revoked access;
- bundled helper/XPC/native database tool execution and inherited/declared entitlements;
- Keychain access groups and helper identity;
- SSH agent/socket/known-host/private-key access;
- `SMAppService` LaunchAgent/LoginItem registration and user approval;
- restore tools that need child processes, temporary files, signals or broader file access;
- database driver dynamic libraries, code signing and library validation;
- App Review privacy/disclosure and background execution policy.

No feature is marked supported in the Store matrix merely because it works in the direct build. Unsupported capabilities are hidden/disabled with a consequence-focused explanation.

## 7. Background automation

MVP automation runs only while the app is open. A future direct-build helper can be a signed bundled LaunchAgent registered through `SMAppService` on macOS 13+, communicating over authenticated XPC. It requires:

- explicit user/job consent and visible enable/disable state;
- immutable reviewed job definition and target/capability digest;
- least-privilege Keychain access policy;
- no secret command-line/environment persistence;
- bounded workers/queues, overlap policy, timeout, cancel and audit;
- clean tunnel/process shutdown and partial outcome reporting;
- signed helper/update parity and rollback tests.

The product must state that a user-session LaunchAgent cannot guarantee execution while the user is logged out or the Mac is asleep. A LaunchDaemon would require a separate privileged/admin threat model and is deferred.

## 8. Crash reporting, diagnostics and telemetry

Default state is local-only diagnostics, no network telemetry, no crash upload. A user can separately opt into a previewable, redacted crash report. Before sending:

- show exact event fields/attachments and destination;
- remove secrets, connection strings, query parameters, row values, clipboard, file contents and private paths;
- provide cancel and delete-local-copy controls;
- persist consent version and allow immediate opt-out;
- retain only bounded local artifacts and document deletion.

Sentry Cocoa is a candidate only after privacy/legal/vendor/security review. A service choice must not make diagnostics or product functionality unavailable to users who decline telemetry.

## 9. Community and Pro readiness

The app is not split into unsafe/safe tiers. Future Community/Pro packaging may gate advanced convenience features (for example, automation scale, enterprise policy, modeling/export formats or support), but the following remain in every edition:

- Keychain-only secrets, TLS/SSH validation, read-only/production indicators;
- destructive-query protection, previews, transaction warnings and row-identity safeguards;
- redacted logs, opt-in privacy, cancellation and bounded streaming;
- testable generated SQL and user-visible errors.

The planning recommendation is a proprietary commercial application with one codebase and possible Community/Pro entitlements, while using permissive reviewed dependencies. Final license text and commercial terms remain a legal decision before the first distributed binary. Product entitlements and offline license artifacts must not contain or expose database credentials, and license failure must not silently alter database safety defaults.

## 10. Release gates

### M0 shell gate

- clean arm64 app/Rust artifact signs and verifies;
- Hardened Runtime has no unreviewed exceptions;
- notarization/stapling/Gatekeeper pass on a clean Mac;
- update tamper/downgrade/channel tests pass;
- SBOM/license/provenance/secret scan is retained;
- no real database or credential is included.

### Pre-beta gate

- PostgreSQL vertical slice has adapter/security/performance evidence;
- Keychain, TLS, SSH candidate and native file/tool paths pass their spikes;
- crash/telemetry consent and diagnostics preview tests pass;
- privacy policy/support/disclosure are approved;
- rollback/key rotation/incident tabletop completed.

### Every release candidate

- exact architecture/OS support is published;
- dependency advisories/license changes reviewed;
- signatures, entitlements, nested code and update feed verified;
- all required test suites pass with no unexplained skip;
- release artifact and update can be reproduced/rolled back by an independent reviewer.

## 11. Distribution risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Update signing/feed compromise | Offline keys, EdDSA + Apple signature, key rotation, tamper tests, rapid revocation |
| Hardened Runtime exception creep | Entitlement diff, ADR/security review, per-exception test and expiry |
| Unsigned native tool/driver | Provenance/sha/signature check, no execution on mismatch, explicit unsupported state |
| App Sandbox incompatibility | Separate channel matrix; user-selected bookmarks; feature-level capability gating |
| Keychain/helper access failure | Consent/status UI, typed error, no plaintext fallback, interactive-only safe mode |
| Stale/notarization policy | Recheck Apple docs/toolchain every RC and retain logs |
| Crash/telemetry leakage | Off by default, preview/redaction canary suite, bounded deletion |
| Intel/Universal drift | Arm64-only claim until dedicated ADR, CI and hardware evidence |

## 12. Technical spikes

- sign/notarize/staple empty Swift/Rust shell and nested helper;
- Sparkle 2 feed/signature/update/rollback/tamper test, including license and helper review;
- App Sandbox prototype for user-selected file, Keychain, SSH, helper, subprocess and bookmark flows;
- `SMAppService` LaunchAgent/XPC lifecycle with consent, logout/sleep behavior and Keychain access;
- native backup tool packaging/signature/argument/temporary-file/cancel behavior per engine;
- crash/diagnostics canary and exact opt-in payload inspection;
- arm64 size/startup and future Universal build feasibility.
