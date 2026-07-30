# DF-M0-006 disposable direct-distribution spike

This standalone spike tests one planning hypothesis: an empty Apple Silicon
Swift application with a Rust dynamic core and a separate helper can be
packaged with an auditable nested-code layout, hardened and signed from the
inside out, and protected by a candidate update-verification chain.

It is not a product scaffold. It has no database driver, connection, network
service, credential, Keychain item, Swift/Rust production FFI, updater UI,
public feed, production signing key, update key, or release automation. The
entire source tree is disposable after sanitized evidence and a disposition
are recorded.

## Environment truth

The protocol distinguishes four evidence states:

- `pass`: the exact frozen scenario ran and met its stated contract;
- `partial`: a narrower local or model smoke ran, with the missing production
  boundary stated explicitly;
- `unsupported`: the required identity, credential, tool, host, or integration
  is unavailable and the scenario did not run; and
- `fail`: the scenario ran and violated its contract.

An ad-hoc signature is never relabelled as Developer ID evidence. A local
`codesign` verification is not Gatekeeper acceptance, notarization, stapling,
a secure timestamp, clean-Mac installation, or proof that two versions share a
trusted Team identity. If the host has no valid Developer ID identities or
notarization credentials, the runner records the affected rows as
`unsupported` without probing or enumerating secret material.

## Frozen topology

```text
DataForgeDistributionProbe.app/
  Contents/Info.plist
  Contents/MacOS/DataForgeDistributionProbe
  Contents/Frameworks/libdataforge_distribution_core.dylib
  Contents/Helpers/DataForgeDistributionHelper
  Contents/Resources/probe-version.txt
```

The app and helper are empty Swift command-line probes compiled for
`arm64-apple-macosx14.0`. The dependency-free Rust `cdylib` exports one fixed
probe version function. The app invokes that function only to prove the
loader, runpath, architecture, and nested-signature layout. No reusable
application service or FFI contract is created.

## Security invariants

- Sign nested code explicitly from the inside out. `codesign --deep` may be
  used for verification, never as the signing procedure.
- Hardened Runtime is requested for every executable and library. The local
  shell has no entitlement exceptions; any future exception requires its own
  threat review and test.
- Every executable has an explicit bundle/signing identifier and its
  designated requirement is captured and checked. Ad-hoc requirements prove
  only local mechanics, not publisher authenticity.
- Altering a sealed resource must invalidate strict verification. Substituting
  nested code that does not satisfy the requirement recorded by the outer
  signature must reject. Whether a separately signed same-identifier ad-hoc
  helper satisfies the deliberately weak local requirement is captured as a
  limitation, never as publisher-authenticity evidence.
- The update archive is authenticated independently of HTTPS with an
  ephemeral fake Ed25519 seed. Correct, wrong-key, and tampered cases are all
  required.
- Fake private seeds are generated under a unique owner-only temporary
  directory, passed by file descriptor/path rather than value in argv, never
  printed, never copied into evidence or Git, and deleted on every exit path.
- Version, channel, architecture, bundle identity, signature, and payload hash
  are checked before a model install step. Downgrade, replay, wrong-channel,
  wrong-bundle, wrong-architecture, and altered payload fail closed.
- A rollback smoke must preserve or restore the exact previously accepted
  artifact after an injected pre-replacement failure. It cannot weaken the
  downgrade rule.
- Candidate packages, notices, checksums, advisories, binary slices, nested
  code, signature state, replacement cost, and unsupported integration gates
  are recorded before any adoption decision.

## Frozen evidence matrix

| ID | Scenario | Required evidence |
| --- | --- | --- |
| `EN-01` | Host/tool/identity inventory | Record host, OS, CLT/Xcode, Swift, Rust, `codesign`, `spctl`, `notarytool`, `stapler`, architecture and only the count of valid code-signing identities. Never dump environment or keychain contents. |
| `AR-01` | Empty nested build | App, Rust core and helper build as `arm64` Mach-O files with minimum macOS 14 metadata and deterministic bundle layout. |
| `AR-02` | Load and launch | The app loads the bundled core through `@rpath`, returns the expected probe version and invokes the helper; no absolute developer path is linked. |
| `SG-01` | Inside-out local signing | Each nested item and then the app are ad-hoc signed explicitly with Hardened Runtime and no signing-time `--deep`. |
| `SG-02` | Strict nested verification | Every item and the outer app pass strict signature verification; recursive verification is an additional check only. |
| `DR-01` | Designated requirements | Exact local requirements are captured, each item satisfies its own identifier, wrong identifiers reject, and versions 100/101 retain the intended identifiers. Authentic Team/Apple anchor equivalence remains a separate Developer ID gate. |
| `ET-01` | Entitlement inventory | App, core and helper have no entitlement exceptions; Hardened Runtime flags are present. |
| `TM-01` | Resource tamper | Changing one sealed resource after signing makes strict outer verification fail. |
| `TM-02` | Nested-code substitution | A replacement with the wrong designated requirement rejects. Same-identifier ad-hoc replacement behavior is recorded to show why a Developer ID Team/Apple anchor is required. |
| `GK-01` | Gatekeeper clean-Mac install | A quarantined Developer ID, securely timestamped and notarized artifact is accepted by Gatekeeper on a clean supported Mac. Ad-hoc rejection is diagnostic only and cannot pass this row. |
| `NT-01` | Notarization | A Developer ID-signed archive is submitted with `notarytool`, accepted, and its sanitized request ID/log is retained. No submission occurs without dedicated test credentials. |
| `ST-01` | Stapling | The accepted ticket is stapled and validates offline. A no-ticket failure cannot pass this row. |
| `SP-01` | Sparkle candidate dossier | Exact Sparkle release tag/commit/asset digest, license/notices, advisories, maintenance snapshot, architecture slices, nested signatures, binary bytes, toolchain/runtime requirements and replacement path are recorded. |
| `SP-02` | Ed25519 valid archive | Exact candidate tooling signs a generated update archive using a fake seed and verifies the unchanged archive. |
| `SP-03` | Ed25519 negative cases | Altered archive and independent wrong key both reject; no private seed appears in output or retained files. |
| `SP-04` | Signed feed/pre-extraction policy | Candidate support for signed feed and pre-extraction verification is inspected; an exact signed-feed integration must run before this row can pass. |
| `UP-01` | Valid update policy | A signed version-101 stable/arm64/same-bundle fixture passes the local policy model from installed version 100. This is model evidence, not Sparkle install evidence. |
| `UP-02` | Downgrade/replay/channel | Version 99, version 100 replay, beta-on-stable, wrong bundle, wrong architecture and altered payload reject in the model. |
| `UP-03` | Rollback | An injected failure before replacement leaves the installed artifact hash unchanged; a real updater interruption/rollback remains required. |
| `KR-01` | Key rotation | Old/new fake keys demonstrate overlap and wrong-key rejection in a model; Sparkle plus Developer ID rotation rules remain an integration gate. |
| `SB-01` | SBOM/provenance | Sanitized SPDX/provenance records exact source revision, toolchains, package checksums, licenses/unknowns, slices and artifact hashes. |
| `SC-01` | Secret surface | Generated fake seeds/canary are absent from Git, stdout/stderr, retained JSON/text, archives, process snapshots and final temporary state. |
| `CL-01` | Cleanup | No temporary key, unsigned/signed app, downloaded framework, update archive or staging/backup directory remains after the runner exits. |

## Exact Sparkle candidate

The frozen candidate is upstream Sparkle `2.9.4`, tag commit
`b6496a74a087257ef5e6da1c5b29a447a60f5bd7`, release asset
`Sparkle-2.9.4.tar.xz`, and release SHA-256
`ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9`.
The download is allowed only from the exact upstream GitHub release URL and
must match that digest before extraction. Evaluation does not add Sparkle to a
product manifest or approve its framework/helper entitlements.

## Expected commands

The checked-in validation runner will execute applicable equivalents of:

```bash
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features
swiftc -target arm64-apple-macosx14.0 ...
lipo -archs <each Mach-O>
otool -L <app>
codesign --sign - --options runtime ... <each nested item, then app>
codesign --verify --strict --verbose=4 <each item>
codesign --verify --deep --strict --verbose=4 <app>
codesign --display --requirements - <each item>
codesign --display --entitlements :- <each item>
spctl --assess --type execute --verbose=4 <app>
xcrun stapler validate <app>
./scripts/run-evidence.sh
```

`notarytool submit` is deliberately absent from the default runner. It requires
a separately authorized Developer ID artifact and dedicated Apple test
credential. A release operator runs the documented credentialed lane later;
the spike never searches for, prints, or guesses a profile.

## Decision rule

The direct-distribution production gate opens only when `AR`, `SG`, `DR`,
`ET`, `TM`, `GK`, `NT`, `ST`, `SP`, `UP`, `KR`, `SB`, `SC`, and `CL` all pass
at their full stated boundaries on the provisional minimum and a clean
supported Mac. Local ad-hoc or model results may retain the architecture or a
candidate for further planning, but cannot authorize external distribution.

Any untrusted payload accepted, signature/identity mismatch, downgrade,
replay, wrong channel, leaked key, unreviewed entitlement, unsigned nested
code, unexplained executable, failed cleanup, or unsupported notarization gate
keeps the release capability closed. Manual, checksum-published downloads are
the safe fallback if no updater candidate passes; they still require Developer
ID, notarization, stapling and Gatekeeper evidence.

## Disposal

After exact commands, sanitized raw evidence, limitations, candidate
disposition, release runbook and a new ADR are committed, this entire directory
is deleted in a separate disposal commit. Production release scaffolding must
be regenerated later from an approved design; spike code is not copied into a
product target.
