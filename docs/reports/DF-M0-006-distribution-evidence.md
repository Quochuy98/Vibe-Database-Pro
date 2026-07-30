# DF-M0-006 direct-distribution and secure-update evidence

Status: Evidence and disposal complete; direct-distribution recommendation
retained for planning, production release gate closed

Evidence date: 2026-07-30

Disposable source revision:
`f0457dd01bcfe3ff3dbbe5fb1f8e06c2c4f91203`

Related decision: [ADR-0013](../adr/0013-m0-distribution-disposition.md)

Release procedure: [Direct release runbook](../RELEASE_RUNBOOK.md)

## 1. Decision question and scope

DF-M0-006 asked whether the planned direct release chain is ready to move from
architecture into implementation: an empty Apple Silicon Swift app, Rust core
and helper must be signed as nested code with Hardened Runtime, notarized,
stapled, accepted by Gatekeeper, and updated only through a tamper-resistant,
monotonic, channel-bound path.

The disposable shell contains no product feature, database adapter, database
endpoint, SQL, database write, Keychain item, production credential, public
feed, telemetry, production FFI contract or reusable release scaffold. Two
versions (`100` and `101`) were created only to exercise bundle identity and
update-policy mechanics. Every update seed was fake, generated per run in an
owner-only temporary directory and deleted before the runner returned.

This report separates three evidence boundaries:

1. exact local arm64 build, load, ad-hoc signing and tamper behavior;
2. exact Sparkle `2.9.4` release provenance and cryptographic-tool smokes; and
3. credentialed Apple, clean-Mac and real updater integration that did not run.

## 2. Disposition

- Retain direct Developer ID distribution as the first-channel planning
  recommendation from ADR-0006. Do not claim an externally distributable
  artifact or open a production release gate.
- Retain exact Sparkle `2.9.4` only as a conditional update candidate. Do not
  add the dependency, framework, helpers, entitlements or feed configuration
  to a production target.
- Require a new credentialed evidence run with full Xcode, a dedicated
  Developer ID test identity, Apple notarization credentials and a clean
  supported Mac before implementation review.
- Keep manual verified downloads as the fail-closed fallback if Sparkle cannot
  pass the integration/adoption gate. Manual delivery still requires
  Developer ID, notarization, stapling and Gatekeeper evidence.

The frozen matrix is `13 pass / 6 partial / 4 unsupported / 0 fail` across 23
rows. `complete_release_gate_passed=false`,
`production_distribution_enabled=false`, and `updater_adopted=false` are the
only valid task-level conclusions.

## 3. Evidence identity and environment

| Item | Exact value |
| --- | --- |
| Source commit | `f0457dd01bcfe3ff3dbbe5fb1f8e06c2c4f91203` |
| Spike Git tree | `bdbba911c7538517917462b2dfc63772e22c6973` |
| Source `git archive` SHA-256 | `09f003315a20288e17c411e66828d74680038ca1bc49a92a5d028485226458b9` |
| Host | Mac15,3, arm64, 24 GiB, 8 logical CPUs |
| OS | macOS 26.5.2, build 25F84 |
| Developer tools | `/Library/Developer/CommandLineTools`; full Xcode unavailable |
| Swift | Swift driver 1.148.6; Apple Swift 6.3.3 |
| Rust | `rustc 1.97.1`; `cargo 1.97.1` |
| Notary tool | `notarytool 1.1.2 (41)` available through `xcrun` |
| Valid code-signing identities | `0`; names were not enumerated |
| Notary credential lookup | Not performed |

The host is newer and has more memory than the provisional M1/16 GiB/macOS 14
minimum. Architecture and deployment metadata were inspected, but this run
does not establish behavior on the minimum host or a separate clean Mac.

## 4. Commands and validation result

The exact clean source commit ran:

```bash
DATAFORGE_REQUIRE_CLEAN=1 ./scripts/test.sh
cargo metadata --manifest-path Cargo.toml --locked --format-version 1 --no-deps
cargo audit --file Cargo.lock
cargo deny --manifest-path Cargo.toml check
cargo deny --manifest-path Cargo.toml check advisories bans sources
DATAFORGE_REQUIRE_CLEAN=1 ./scripts/run-evidence.sh \
  <sanitized-evidence-directory>
```

`test.sh` ran Zsh syntax validation, `cargo fmt --check`, warnings-as-errors
`cargo check`, strict Clippy, the Rust test, two arm64 Swift/Rust builds and the
complete evidence runner. The Rust workspace contains one local disposable
crate and zero third-party Rust dependencies. `cargo audit` scanned the lock
without a reported vulnerability. `cargo deny` advisories, bans and sources
passed.

The unscoped `cargo deny check` license lane did not pass: the disposable
first-party crate and repository intentionally have no final license grant.
This is not converted into a permissive license merely to make a check green.
It remains a legal/release blocker and is recorded as `legal_approval=false`
in the SBOM evidence.

No `xcodebuild build/test/archive`, `notarytool submit`, Developer ID signing,
secure timestamp, staple, quarantine transfer, clean-Mac launch or real
updater install ran.

## 5. Empty arm64 artifact

The generated layout was:

```text
DataForgeDistributionProbe.app/
  Contents/MacOS/DataForgeDistributionProbe
  Contents/Frameworks/libdataforge_distribution_core.dylib
  Contents/Helpers/DataForgeDistributionHelper
  Contents/Resources/probe-version.txt
```

| Item | Bytes | SHA-256 | Evidence |
| --- | ---: | --- | --- |
| Swift app executable | 88,544 | `3904efee7b80e7b3751423054a61829d2cf13d6a942e451f247c636fd034b14b` | thin arm64; minimum macOS 14 |
| Rust `cdylib` | 34,944 | `25fef35428124557a4b16451a6823df4d3d295bbccdb29a41bed98b94e59649c` | thin arm64; dependency-free |
| Swift helper | 69,504 | `68f5644062485831a64dfae06a33f5ed9a5f8e047b24107cdff3adff713a1816` | thin arm64; fixed bounded output |
| Signed app tree | — | `a8f8e1d14cd4a8a2daba6bdb4cda4de3309391d85b43958c53f028647f6dc5fd` | local ad-hoc only |
| Generated update ZIP | 21,355 | `be87acc430dbbeec7ab34341b3b4e7272cbf353a0852c64ca0ff7b943861a193` | transient; not retained |

The app links the core as
`@rpath/libdataforge_distribution_core.dylib`; no developer or temporary
absolute path appears in its load commands. The signed app loaded the core,
called the fixed version marker and invoked the helper successfully. This is a
loader/topology smoke, not a production Swift/Rust FFI test.

## 6. Local signing, requirements and tamper behavior

Core and helper were signed first, then the app. No signing command used
`--deep`; recursive `--deep` was used only as an additional verification. All
three items reported ad-hoc signatures, Hardened Runtime, no Team identifier,
no secure timestamp and no entitlement plist.

The local designated requirements were:

```text
identifier "com.dataforge.distribution-probe"
identifier "com.dataforge.distribution-probe.core"
identifier "com.dataforge.distribution-probe.helper"
```

Versions 100 and 101 retained the app identifier. Each item satisfied its own
requirement, and a wrong identifier rejected. Modifying one sealed resource
invalidated strict outer verification. Replacing the helper with a separately
signed wrong-identifier helper also rejected.

The important negative finding is that a separately built helper, ad-hoc
signed with the same identifier, satisfied the outer app's deliberately weak
local nested requirement. This is expected to be possible when the requirement
contains no publisher anchor. It proves that an ad-hoc DR cannot stand in for
publisher authenticity. The credentialed lane must establish an Apple generic
anchor, the intended Developer ID Team and the exact identifier for app, core,
helper and updater code.

## 7. Apple trust chain not established

`security find-identity` reported zero valid code-signing identities. The
runner did not enumerate identity names, search Keychain profiles or attempt to
discover notarization credentials.

`spctl` rejected the ad-hoc app with exit `3`; this is the expected diagnostic,
not a Gatekeeper pass. `stapler validate` exited `65` because there was no
accepted notarization ticket. `notarytool submit` was deliberately not called.

Therefore these frozen rows remain unsupported:

- `GK-01`: quarantined clean-Mac Gatekeeper acceptance;
- `NT-01`: Developer ID + secure timestamp + notarization acceptance/log; and
- `ST-01`: stapled ticket and offline validation.

## 8. Exact Sparkle candidate dossier

| Item | Evidence |
| --- | --- |
| Version/tag | `2.9.4` / commit `b6496a74a087257ef5e6da1c5b29a447a60f5bd7` |
| Published | 2026-07-03T03:42:15Z |
| Release asset | `Sparkle-2.9.4.tar.xz`, 15,554,152 release bytes |
| Asset SHA-256 | `ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9` |
| License file SHA-256 | `389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe` |
| Preliminary license posture | MIT plus retained bundled third-party notices; legal review required |
| Framework | x86_64 + arm64, 3,133,440 extracted logical bytes; main binary 977,616 bytes |
| Tools | `sign_update` 1,378,608 bytes; `generate_keys` 1,308,528; `generate_appcast` 2,159,968; all x86_64 + arm64 where inspected |
| Nested code | Four app/XPC/Autoupdate items discovered; strict recursive signature verification passed |

The current upstream advisory API returned `CVE-2026-47121` and
`CVE-2026-47122`, each with a declared vulnerable range through `2.9.1`.
Exact `2.9.4` is outside those published ranges, but this is a point-in-time
candidate scan, not an approval. Release adoption must repeat advisory,
license/notices, source, entitlement, helper, maintenance and replacement
review.

The prebuilt framework was not embedded. Official Sparkle integration guidance
notes that an ad-hoc host can conflict with Hardened Runtime library validation
when loading a differently signed framework. The spike did not add
`disable-library-validation` or another exception to manufacture a local pass.

## 9. Update cryptography and policy smokes

Exact `sign_update` tooling used two independent, ephemeral 32-byte Ed25519
seeds:

- unchanged version-101 archive signed and verified with the old fake key;
- one appended byte caused verification failure;
- the independent wrong key rejected the old signature;
- the new fake key signed and verified the archive, while the old key rejected
  that signature; and
- the sample appcast was signed and its embedded signature verified.

No seed value entered argv, stdout/stderr, retained evidence, Git or the final
process snapshot. Transient logs, candidate binaries and archives were scanned
with the secret pattern before the whole run directory was removed.

The local model accepted same-bundle stable arm64 build 101 from build 100. It
rejected five cases: build 99 downgrade, build 100 replay, wrong bundle, beta
on the stable channel and x86_64 on the arm64 channel. These are policy-model
results. Sparkle did not download, extract, compare, install, relaunch or
restore an application.

The rollback smoke injected failure before replacement and observed the exact
installed-tree hash unchanged:
`3d04f6ece4cc3457b2552c604f087b93957d856cace974332b29b698492864ae`.
It does not establish rollback after a mid-install crash, permission failure,
power loss or updater-helper interruption. The key overlap smoke likewise does
not establish Sparkle/Developer ID rotation.

## 10. Acceptance mapping

| Frozen requirement | Disposition |
| --- | --- |
| `EN-01` | Met; sanitized host/tool/count-only identity inventory |
| `AR-01…AR-02` | Met for the disposable arm64/macOS-14 shell and local host |
| `SG-01…SG-02` | Met only for local ad-hoc inside-out signing/strict verification |
| `DR-01` | Partial; identifier mechanics pass, Developer ID Team/Apple anchor absent |
| `ET-01` | Met locally; Hardened Runtime requested with zero exceptions |
| `TM-01` | Met locally; sealed resource mutation rejects |
| `TM-02` | Partial; wrong DR rejects, same-ID ad-hoc replacement demonstrates missing publisher anchor |
| `GK-01` | Unsupported; no Developer ID artifact or clean-Mac quarantine run |
| `NT-01` | Unsupported; no credentialed submission |
| `ST-01` | Unsupported; no accepted ticket |
| `SP-01…SP-03` | Met for exact candidate provenance and offline Ed25519 tool smokes |
| `SP-04` | Partial; signed-feed tool smoke only, no host pre-extraction/framework integration |
| `UP-01…UP-03` | Partial models; no real updater install/interruption/rollback |
| `KR-01` | Partial fake-key overlap; no Developer ID/Sparkle rotation |
| `SB-01` | Met for sanitized provisional SPDX/provenance; legal approval remains false |
| `SC-01` | Met for exact fake-seed scans in the runner's observed surfaces |
| `CL-01` | Met; no key, app, archive, framework download or staging tree retained |
| Spike disposal | Met; source removed in separate commit `38c74417786807f0be421cbbec7e58fe95d5eac2` |

## 11. Release runbook and re-entry gates

The [release runbook](../RELEASE_RUNBOOK.md) records the future credentialed
lane without embedding an identity, Team ID, profile, private key or token.
Before production implementation review, a newly generated approved scaffold
must run the full lane and prove:

1. full supported Xcode archive/export on the minimum and current macOS;
2. Developer ID Application signatures, secure timestamps and expected
   Team/identifier requirements for every nested item;
3. exact entitlements with no unreviewed Hardened Runtime exception;
4. accepted notarization log/request, stapled ticket and offline validation;
5. quarantine transfer, Gatekeeper and launch on a separate clean Mac;
6. exact Sparkle integration with Ed25519 archive, signed feed and
   pre-extraction verification, or an independently reviewed replacement;
7. real valid/tamper/wrong-key/downgrade/replay/channel/architecture/OS,
   interruption, atomic install, rollback and relaunch tests;
8. Developer ID and update-key rotation/revocation tabletop with identities
   separated from hosting and ordinary build workers; and
9. final legal license/notices, SBOM, provenance, size, privacy/support and
   incident-response approval.

Any accepted altered payload, same-identifier code from the wrong Team,
unsigned nested code, missing timestamp/ticket, unreviewed entitlement,
downgrade, replay, leaked seed or unexplained skip closes the gate.

## 12. What is not established

- Developer ID, Team ID, Apple anchor, secure timestamp or certificate
  revocation behavior.
- Notarization acceptance, stapling, offline ticket or Gatekeeper clean-Mac
  acceptance.
- Xcode archive/export, DMG/PKG signing, quarantine transfer, install location,
  app translocation or OS 14 minimum-host behavior.
- Sparkle framework/XPC/helper embedding, library validation, entitlements,
  network/TLS, download, extraction, permission escalation, delta update,
  relaunch or install rollback.
- Real signed-feed/pre-extraction host configuration or public feed hosting.
- Developer ID/Ed25519 key rotation, revocation, loss, recovery or incident
  response.
- Final product license, Sparkle notices/legal approval or Community/Pro terms.
- Any product, database, credential-storage, FFI or user-interface behavior.

## 13. Disposal

The exact disposable source remains auditable at
`f0457dd01bcfe3ff3dbbe5fb1f8e06c2c4f91203`, with spike tree
`bdbba911c7538517917462b2dfc63772e22c6973`. Report, raw evidence, ADR and
runbook were recorded in commit
`ae1f94a2a6e6a4971d41df6f87d1f8062c7f3134`; the whole
`spikes/distribution` directory was then deleted in separate disposal commit
`38c74417786807f0be421cbbec7e58fe95d5eac2`. Production release scaffolding
must be regenerated rather than promoted from this probe.

## 14. Durable raw evidence

The retained directory contains no app binary, framework download, update
archive, signing seed, identity name, notary profile, credential, environment
dump, personal path or database data.

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`artifact-manifest.json`](data/DF-M0-006/artifact-manifest.json) | Source and transient artifact hashes/sizes | `ccafe02a65b3e32c23959cffbf462fa6c5c070b973f79bf5903a62f326998301` |
| [`codesign-summary.txt`](data/DF-M0-006/codesign-summary.txt) | Local DR/runtime/tamper and expected trust failures | `5e6504decf7d644b2c4e1fcdee394d899466c58f7e6984baf691832144b80a36` |
| [`environment.json`](data/DF-M0-006/environment.json) | Sanitized host/tool/signing availability | `c96bd2f23d4a796d28f4267107c6baa606288575c60dbc76711743213b8bb9a3` |
| [`runner-completion.txt`](data/DF-M0-006/runner-completion.txt) | Outer secret scan and cleanup marker | `71a17b0c6b36f87fd6d0ab37d5be1f80c31965dc7159bd273e26def60093ca1d` |
| [`runtime.json`](data/DF-M0-006/runtime.json) | Complete 23-row matrix with partial/unsupported semantics | `5313cbcd18a3338dafb6e1301ab81d85984741998b7b937f39e43ddb8949c95e` |
| [`sbom.spdx.json`](data/DF-M0-006/sbom.spdx.json) | Provisional SPDX 2.3 package/provenance record | `a783415a67134a65ffc33d7d5927e1d3d3d3c91b0bd8066140cf4bee381de1a2` |
| [`sparkle-candidate.json`](data/DF-M0-006/sparkle-candidate.json) | Exact release, license, advisory, architecture and integration gaps | `5731e97e496ae7c25900f5f7bb4d40a6b5e3041c6cd00266c4bc734313040edc` |

## 15. Primary references

- [Apple: notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [Apple TN2206: macOS code signing in depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Sparkle `2.9.4` release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.4)
- [Sparkle setup and update-signing guidance](https://sparkle-project.org/documentation/)
- [Sparkle security and reliability history](https://sparkle-project.org/documentation/security-and-reliability/)
