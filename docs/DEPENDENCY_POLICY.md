# Dependency and Supply-Chain Policy

Status: Proposed M0 policy; production adoption remains disabled

Last updated: 2026-08-01

## 1. Purpose

This policy turns the dependency rules in `AGENTS.md`, `CONTRIBUTING.md` and
the security threat model into an auditable adoption workflow. It covers code,
frameworks, OS-provided executables, database utilities, build tools, container
images, CI actions and hosted SDK/service combinations.

An item appearing in architecture, a spike, an SBOM or a candidate table is
**not** approval to add it to a product manifest. The current M0 inventory has
`0 approve / 10 defer / 3 reject`; production dependency adoption is disabled.

## 2. Disposition meanings

| Disposition | Meaning | Allowed action |
| --- | --- | --- |
| `approve` | Exact immutable source passed technical, security, legal and product review | A separate implementation change may propose the exact source; normal code review still applies |
| `defer` | Evidence, identity, integration or approval is incomplete | Keep behind a port/capability gate; do not add to production manifests or advertise support |
| `reject` | Exact source/build violates a current gate | Do not adopt it; a different version/source starts a new dossier and full rerun |

No agent, engineer or scanner may convert a permissive-looking license or a
clean advisory result into legal approval. No risk owner approves their own
exception without independent security/product review.

## 3. Required dossier

Every exact candidate records:

1. package name, exact version or immutable revision, canonical source and
   SHA-256/checksum;
2. minimal enabled features, lock/resolution file, complete transitive graph
   and absence or explicit review of non-registry/Git/binary sources;
3. exact license files, copyright notices, redistribution obligations,
   commercial-use position and qualified legal decision;
4. current registry, RustSec, repository, vendor and OS/project-build
   advisories, including an owner and response SLA;
5. maintenance activity, supported toolchain/MSRV/Swift/Xcode/macOS versions,
   Apple Silicon evidence and replacement cost;
6. release-like product binary-size delta and nested-code/signing/entitlement
   impact;
7. feature-specific success, failure, cancellation, hostile-input,
   bounded-resource, secret/logging, cleanup and rollback evidence;
8. generated SBOM/provenance reconciliation, review date, owner roles and
   explicit re-review triggers.

Unknown facts produce `defer`, not optimistic defaults. A newer semver is a
new exact candidate; it does not inherit approval or runtime evidence.

For the current inventory, five candidate groups lack an exact selected
identity (`mysql_async`, `rusqlite`, tree-sitter, SQLx and Sentry Cocoa), while
seven lack a full package graph. The larger graph count also includes the exact
rejected system OpenSSH build and `ssh2`/vendored libssh2 source; recorded
provenance for a rejected source is not a resolved dependency graph.

## 4. Source and license rules

- Allowlist canonical registries and immutable upstream revisions. Reject
  mutable branches, dependency confusion, unclear binaries and private APIs.
- Pin CI actions and container images to immutable commits/digests. Review
  tool and image licenses even when they do not ship in the app.
- GPL/AGPL, unclear redistribution, commercial SDK/service terms and bundled
  native notices require explicit legal resolution before use.
- Keep source/archive/license hashes in durable evidence. Release-time source
  must reproduce the locked package checksums.
- The repository's final product license and Community/Pro terms are a Product
  + Legal decision. Engineering must not fabricate license text to make a
  scanner pass.

## 5. Security and maintenance rules

- Run multiple sources: package registry/yank state, RustSec or ecosystem
  scanner, official repository advisories, vendor notices and Apple
  project-build/OS advisories. A clean scanner does not override a finding in
  another authoritative source.
- Any affected exact source, unpatched malicious-input path, trust bypass,
  secret leak, shell execution or unmanaged lifecycle blocks adoption.
- Record the responsible dependency owner, backup owner, advisory response
  target, disable/kill-switch path and replacement plan.
- Re-run on every lock change, release candidate, upstream advisory, supported
  OS/toolchain change, feature expansion or expired exception.
- Exceptions require rationale, scope, compensating controls, named approver,
  independent reviewer, expiry and an automatic re-review trigger.

DF-M0-008 demonstrates why the multi-source rule is mandatory: `cargo audit`
and `cargo deny` passed the frozen SSH lock on 2026-08-01, while the official
`russh` repository had just published `GHSA-m65r-rprj-r5rg` affecting the
locked `0.62.4`. Exact `0.62.4` is therefore rejected.

## 6. Platform, performance and integration rules

- Build/test the exact minimal feature set on the supported minimum and current
  macOS releases, initially Apple Silicon. A developer-host spike is not a
  supported-platform claim.
- Measure a release-like product artifact against the same scaffold with and
  without the candidate. A standalone probe delta is diagnostic only.
- Database/network/file work must stay off the main thread. Queues, tasks,
  frames, caches and result streams require explicit limits and cancellation.
- Credential-bearing dependencies must prove no persistence/log/diagnostic/
  argv/environment fallback and must document unavoidable memory copies.
- OS-provided tools still require exact project/build identity, source/backport
  evidence, argument/no-shell behavior, typed error mapping and lifecycle
  ownership.
- Framework/XPC/helper candidates require nested signing, entitlement,
  Hardened Runtime, notarization and clean-machine evidence.

## 7. What is needed to close the current “Not tested” items

| Open item | Prerequisites | Work and evidence required | Gate owner |
| --- | --- | --- | --- |
| Full Xcode build/test | Supported full Xcode, checked-in production scaffold authorized in a separate request, macOS 14 minimum and current Apple Silicon runners | Build/test/lint with exact schemes; retain toolchain, commit and failure list; run XCTest/UI/accessibility lanes | macOS + QA |
| Cargo production checks | Authorized Cargo workspace, pinned toolchain, manifests and locks | `cargo fmt`, strict Clippy, unit/integration tests, `cargo audit`, `cargo deny`, graph/source diff and generated SBOM | Core + Security |
| Disposable database integration | Pinned container digests, isolated network/schema, fake CI secrets, destructive guards and cleanup reaper | Run success/auth/TLS/query/cancel/transaction/failure/rollback/large-stream matrix; prove no production/shared-staging endpoint is reachable | Adapter + QA + Security |
| Swift/Rust FFI executable | Reviewed versioned C ABI scaffold and fake adapter | Ownership, ABI mismatch, panic containment, pull/ack backpressure, cancellation races, leak/sanitizer and 1M-row bounded-memory tests | FFI owner |
| SQL editor runtime | Full Xcode and reviewed TextKit 2 prototype/replacement | True input-to-frame latency, keyboard/IME, VoiceOver, large-file, incremental parser and cancellation measurements | Editor + Accessibility |
| Result grid runtime | Reviewed bounded custom renderer, deterministic 1M/10M and 500-column fixtures | Row/column virtualization, retained objects/RSS/frame time, keyboard/VoiceOver, theme and pending-edit identity tests | Grid + Accessibility + Performance |
| SSH | A new exact candidate such as `russh 0.62.5+`; current SSH remains disabled | Rerun every ADR-0012 trust/auth/no-shell/no-direct/malicious-rekey/agent/cleanup/Keychain/FFI/signing/minimum-host/1,000-cycle/8-hour gate | Security + Connections |
| Distribution | Apple Developer membership, protected Developer ID and notary credentials, full Xcode, clean test Macs and approved updater candidate | Archive/export, nested DR/Team/signatures, Hardened Runtime, notarize/staple/Gatekeeper, tamper/downgrade/replay/install/rollback/key-rotation tests | Release Security |
| Signed Keychain | Signed Team/bundle/entitlement test app and full XCTest | Actual Data Protection Keychain CRUD/attributes/duplicate/missing/lock/deny/cancel/access-group migration/helper tests; prove no fallback | Keychain Security |
| Product performance budget | M1/16 GiB/macOS 14 minimum runner plus current runner, release build and named realistic fixtures | Record p50/p95/max/RSS/energy/retained-object results, variance and regression threshold; update provisional budgets only through review | Performance owner |
| Final dependency licenses/notices | Exact locked artifacts and their complete notices, chosen distribution model and commercial terms | Legal reviews commercial compatibility, attribution/notice bundle, service/DPA/privacy terms and replacement obligations in writing | Legal + Product |
| Community/Pro model | Product packaging proposal, safety-feature invariants, entitlement threat model and counsel | Decide proprietary/open-core/SKU terms; prove Keychain/TLS/destructive/row-safety controls are never paywalled | Product + Legal + Security |

These lanes cannot be honestly completed while the repository has no
production source/manifest/test target, or without credentials and human
authority held outside engineering. Their absence is a release blocker, not a
reason to weaken the definition of done.

## 8. GitHub and CI setup once production work is authorized

The repository already has a GitHub remote. Before implementation merges,
configure protected required checks for:

- formatter/linter/build/unit and architecture-boundary checks;
- secret scanning and dependency/source/license diff;
- ecosystem advisory scans plus official upstream/vendor refresh;
- deterministic SPDX SBOM generation and lock/artifact reconciliation;
- disposable database/security matrices on protected runners;
- signed release jobs isolated from untrusted pull requests;
- immutable CI action/image pins and artifact provenance attestations.

GitHub availability alone does not authorize adding a dependency, storing
signing secrets or running destructive integration tests. Repository settings
and credential writes need their own approved operational task.

## 9. Planned dry-run commands

The checked-in production commands become authoritative when manifests exist.
The M0 evidence lane currently uses equivalents of:

```sh
cargo audit --file <Cargo.lock> --deny warnings
cargo deny --manifest-path <Cargo.toml> check advisories licenses bans sources
jq empty docs/reports/data/DF-M0-008/*.json
```

It also queries official crates.io and repository advisory APIs, verifies
immutable historical Git blobs and validates SPDX document/package/relationship
structure. Release CI must use checked-in scripts and pinned tooling rather
than copying these illustrative shell lines.

## 10. Current fail-closed outcome

No candidate is approved. Exact `russh 0.62.4`, the tested Apple OpenSSH build
and exact `ssh2 0.9.6`/`libssh2-sys 0.3.2` source are rejected. The other ten
candidates are deferred with explicit re-entry gates. Product manifests,
database capabilities, SSH, telemetry and updater integration remain disabled
until separately authorized work earns the required evidence and reviews.
