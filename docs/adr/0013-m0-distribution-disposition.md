# ADR-0013: Retain direct distribution planning; keep release gate closed

- **Status:** Accepted for planning; production distribution and updater gated
- **Date:** 2026-07-30
- **Related:** ADR-0006, DF-M0-006, R-21, R-25, R-33, T16, T17

## Context

ADR-0006 recommends direct Developer ID distribution, Hardened Runtime,
notarization, stapling and a signed update channel before a separately
engineered Mac App Store channel. DF-M0-006 had to determine whether an empty
Swift/Rust/helper topology and the leading Sparkle candidate supplied enough
evidence to open implementation.

The exact findings are recorded in the
[DF-M0-006 evidence report](../reports/DF-M0-006-distribution-evidence.md) and
the future credentialed procedure is recorded in the
[direct release runbook](../RELEASE_RUNBOOK.md).

## Findings

The disposable arm64/macOS-14 shell built and launched on the developer host.
Its Swift executable loaded a relative `@rpath` Rust core and invoked a fixed
helper. Nested code was signed from the inside out using local ad-hoc
signatures with Hardened Runtime and no entitlement exceptions. Strict
verification passed; sealed-resource mutation and a wrong-requirement helper
replacement rejected.

This local result cannot establish publisher identity. With an explicit ad-hoc
requirement containing only the identifier, a separately built helper signed
ad-hoc with the same identifier still satisfied outer verification. A real
release therefore needs the expected Apple/Developer ID anchor, Team and
identifier in the effective designated requirement for every nested item.

The host had Command Line Tools but not full Xcode and reported zero valid
code-signing identities. No identity names or notary profiles were enumerated,
and no credentialed submission was attempted. Gatekeeper rejected the ad-hoc
artifact; no notarization ticket existed to staple. Developer ID, secure
timestamp, notarization, stapling and clean-Mac acceptance remain unsupported.

Exact Sparkle `2.9.4`, tag commit
`b6496a74a087257ef5e6da1c5b29a447a60f5bd7`, was downloaded from its upstream
release and matched SHA-256
`ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9`.
Its framework/tools expose arm64 slices and strict signatures. The license file
is preliminarily permissive but contains notices that still require legal
review. Current upstream advisories list two medium issues through `2.9.1`;
this is point-in-time evidence, not future safety assurance.

The exact `sign_update` tool accepted an unchanged fake-key-signed archive and
rejected altered and wrong-key cases. A sample signed feed verified. Version,
channel, bundle and architecture negatives, pre-replacement rollback and
fake-key overlap were only local models. Sparkle framework/XPC embedding,
pre-extraction host configuration, download, install, relaunch, interruption,
rollback and Developer ID/update-key rotation did not run.

The frozen summary is `13 pass / 6 partial / 4 unsupported / 0 fail`, with the
complete release gate, distribution capability and updater adoption all false.

## Decision

1. **Retain ADR-0006's direct Developer ID channel as the planning baseline.**
   The evidence does not justify changing to the Mac App Store, a custom
   updater or unsigned distribution.
2. **Do not enable production distribution.** No artifact may be described as
   Developer ID-signed, notarized, stapled, Gatekeeper-accepted or releasable
   until the full credentialed lane passes on clean supported hardware.
3. **Retain exact Sparkle `2.9.4` only as a conditional candidate.** Do not add
   it to a production manifest or accept its framework/XPC/helper entitlements
   until exact integration, security, legal, size and replacement gates pass.
4. **Never replace identity proof with ad-hoc DR evidence.** Production nested
   requirements must constrain publisher Team/Apple anchor plus identifier.
5. **Fail closed to manual verified delivery when no updater passes.** Manual
   delivery does not waive Developer ID, notarization, stapling, Gatekeeper,
   checksum, SBOM or provenance requirements.
6. **Regenerate production scaffolding.** The disposable shell is evidence,
   not a foundation to promote wholesale.

## Required credentialed lane

Implementation may be reconsidered only after a new approved scaffold proves:

- full Xcode archive/export on macOS 14 minimum and current supported hosts;
- Developer ID Application signature, secure timestamp and correct effective
  nested designated requirements;
- reviewed minimal entitlements and Hardened Runtime without unexplained
  exceptions;
- accepted `notarytool` request/log, stapled/offline ticket and quarantined
  clean-Mac Gatekeeper/launch behavior;
- exact Sparkle or replacement integration, Ed25519 archive plus signed-feed
  and pre-extraction validation;
- valid, altered, wrong-key, downgrade, replay, wrong-channel, architecture,
  minimum-OS, permission, interruption, atomicity, relaunch and rollback tests;
- Developer ID and update-key rotation/revocation/recovery without changing
  both trust anchors in one unsafe step;
- final license/notices, SBOM, provenance, checksums, clean build-worker secret
  scan and incident tabletop; and
- an independent release reviewer who did not control both signing identities.

## Consequences and residual risk

- M0 obtains useful bundle/signing/test contracts, but no release capability.
- Sparkle remains replaceable by manual verified updates or another separately
  reviewed updater; no custom updater is authorized by this ADR.
- R-21, R-25 and R-33 remain release-blocking. This spike narrows their test
  design but does not reduce their critical impact.
- The current repository's absent final license intentionally makes the full
  Cargo license lane fail; legal text cannot be fabricated by engineering.
- No database, FFI, Keychain, user-interface or App Sandbox behavior was
  established.

## Disposal

After this ADR, report, sanitized raw evidence and runbook are committed, the
whole `spikes/distribution` directory is deleted in a separate commit. The
final disposal hash is then recorded here. A future release scaffold must be
generated under ADR-0006, this ADR and the runbook rather than copied from the
probe.
