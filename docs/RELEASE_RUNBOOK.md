# Direct release runbook

Status: Planning contract; credentialed lane not yet executed

Last updated: 2026-07-30

Related decisions: [ADR-0006](adr/0006-distribution-model.md),
[ADR-0013](adr/0013-m0-distribution-disposition.md)

Evidence baseline:
[DF-M0-006](reports/DF-M0-006-distribution-evidence.md)

## 1. Purpose and stop conditions

This runbook defines the future direct Developer ID release lane without
storing a certificate name, Team ID, notary profile, private key or token in
Git. It is not executable release approval. Stop before publication if any
identity, timestamp, nested signature, entitlement, notarization, ticket,
Gatekeeper, update, SBOM, provenance, legal or secret-scan gate is missing.

Never repair a release with signing-time `codesign --deep`, disable library
validation to make a distribution build load, reuse a production key in a
development worker, accept a downgrade, or publish an artifact whose result
cannot be reproduced by an independent reviewer.

## 2. Roles and key separation

| Role/system | Allowed material | Prohibited material |
| --- | --- | --- |
| Clean build worker | Source revision, locked public dependencies, build outputs | Developer ID private key, update private key, hosting credential |
| Apple signing/notary worker | Approved unsigned hash, Developer ID identity, dedicated notary profile | Update private key, public-feed write credential |
| Offline update-signing station | Final signed/stapled artifact hash, update private key | Apple Developer account session, hosting credential |
| Publisher/CDN worker | Final archive, appcast, public signatures, checksums, notices | Developer ID or update private key |
| Independent verifier | Public artifact/feed/checksums, SBOM, provenance, logs | Either private signing key |

Use dedicated least-privilege release identities, two-person approval and an
audited handoff of artifact hashes. A single worker must not control source
approval, both signing identities and publication.

## 3. Preconditions

1. The exact release source revision is protected, reviewed and clean.
2. Full supported Xcode is selected; deployment SDK/tool versions are pinned
   in release evidence.
3. Apple signing and notarization credentials exist only on the approved
   signing worker. The operator chooses the expected identity/profile
   interactively; scripts never search for or guess them.
4. The update candidate, exact version/checksum, license/notices, advisories,
   helpers/XPC services and entitlements have an approved adoption record.
5. Final product license, privacy/support text, version/channel and macOS/arm64
   policy are approved.
6. A separate clean supported Mac is available for quarantine/Gatekeeper and
   update tests.

## 4. Clean build and manifest

- Fetch only pinned sources over authenticated channels; verify every declared
  checksum before use.
- Build the arm64 app, Rust core, frameworks, XPC services, helpers and any
  native tool from the clean revision. Do not import disposable spike code.
- Record `file`, `lipo -archs`, deployment minimum, `otool -L`, bytes and
  SHA-256 for every Mach-O and distribution archive.
- Generate SPDX SBOM, dependency/license/notices report and provenance before
  signing. No package with unresolved source, license or advisory is allowed.
- Scan source, build logs, process arguments, environment allowlist and
  artifacts for seeded release-test canaries. Never dump the environment.

## 5. Nested signing and verification

Sign from the innermost code outward with Developer ID Application and a
secure timestamp:

```text
Rust dylibs/framework binaries
    -> framework/XPC/helper/native-tool bundles
    -> main application bundle
    -> distribution container when applicable
```

The operator supplies the approved identity as a quoted argument to each
explicit signing command. Signing-time `--deep` is forbidden. For every item,
retain sanitized output equivalent to:

```bash
codesign --verify --strict --verbose=4 <item>
codesign --display --requirements - <item>
codesign --display --entitlements - <item>
codesign --display --verbose=4 <item>
lipo -archs <mach-o>
```

Also run recursive strict verification on the final app as a secondary check.
Verify the effective requirement constrains the exact identifier, Apple/
Developer ID anchor and approved Team. Compare the entitlement set against a
reviewed allowlist; any addition blocks until threat-reviewed.

## 6. Notarization, stapling and Gatekeeper

Create the approved ZIP, DMG or package without changing signed content. On the
signing worker, submit with Apple's supported `notarytool` using a dedicated
Keychain profile selected by the operator. Do not put a password, API private
key or profile credential on the command line or in a log.

Retain the request identifier, accepted status and a sanitized notarization
log. Then run the equivalents of:

```bash
xcrun stapler staple <artifact>
xcrun stapler validate <artifact>
codesign --verify --deep --strict --verbose=4 <app>
spctl --assess --type execute --verbose=4 <app>
```

Transfer the final artifact through the real download path so it receives
quarantine metadata. On a separate clean supported Mac, verify Gatekeeper,
install/copy, first launch, relaunch, nested helper/core load and offline
ticket behavior. A developer-host launch cannot substitute for this step.

## 7. Signed update lane

Sparkle `2.9.4` is only a candidate until ADR-0013 re-entry passes. If it is
approved:

- embed and sign its exact framework/XPC/helper set under the intended
  Hardened Runtime and entitlement profile;
- set an incrementing `CFBundleVersion`, explicit stable/beta channel, exact
  public Ed25519 key, signed-feed requirement and pre-extraction verification;
- serve appcast, release notes and archives only through verified HTTPS;
- sign the final update archive on the offline update-signing station; pass a
  CI seed only through protected standard input or an approved key service,
  never as an argv value or ordinary environment dump;
- independently verify the Ed25519 signature, Apple code requirement,
  notarization/ticket, bundle identity, architecture, minimum OS, channel and
  monotonic build before publication; and
- publish only after valid update, tamper, wrong key, wrong Team, downgrade,
  replay, wrong channel, wrong architecture/OS, interrupted download,
  extraction, permission, install, relaunch and rollback tests pass.

The update UI must show source, version/channel, signature state, restart
consequence and actionable failure. It must never execute an unverified
payload or silently fall back to an unsigned/manual installer.

## 8. Rotation, rollback and incident response

- Store Developer ID and Ed25519 keys separately from each other, hosting and
  ordinary CI. Document owners, expiry, backup, recovery and revocation.
- For Sparkle regular app updates, rotate one trust anchor at a time: change
  the Developer ID identity or Ed25519 key in an accepted bridge release, not
  both simultaneously. Revalidate current upstream rules before every drill.
- A product rollback is a new signed/notarized release with a monotonically
  higher build number whose code restores known-good behavior. Never make
  clients accept an older/replayed build to implement rollback.
- On compromise: halt the feed, revoke affected credentials/tickets where
  supported, preserve evidence, publish verified communication/manual recovery
  and require independent approval before resuming.
- Run a rotation/revocation/rollback tabletop before beta and at least yearly.

## 9. Evidence package and publication checklist

Retain, without secrets:

- source revision/tree, clean-build log and toolchain/host identity;
- artifact manifest/checksums, architectures, minimum OS and size;
- SBOM, dependency/license/notices and advisory results;
- per-item signature, effective requirement, Team and entitlement diff;
- notarization request/accepted log and staple/Gatekeeper results;
- update feed/archive signatures and the complete positive/negative matrix;
- clean-Mac install/update evidence and rollback/rotation tabletop;
- secret-scan completion, approvers and publication timestamp.

An independent verifier recomputes hashes and repeats signature, ticket,
Gatekeeper, feed and update checks before the publisher changes public state.
