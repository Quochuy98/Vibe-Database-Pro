# DF-M0-008 — Dependency and license adoption dossiers

Status: engineering evidence recorded; **production adoption blocked**;
independent engineering, security and legal reviews pending

Evidence date: 2026-08-01

Base planning revision: `3d61867`

## 1. Decision question and scope

DF-M0-008 asks whether every dependency candidate retained or mentioned by
DF-M0-002 through DF-M0-007 has an exact, reproducible, legally and
operationally distributable adoption record.

This work is an assurance/planning gate. It does not create a production
manifest, add a dependency, reopen a disabled capability or implement product
code. No real credential, database, customer data, signing identity or
commercial source/asset was used.

The candidate inventory covers 13 dossier rows:

1. Tokio;
2. the `tokio-postgres`/rustls connector stack;
3. `mysql_async`;
4. `rusqlite`;
5. the rustls ecosystem;
6. exact `russh 0.62.4`;
7. the tested macOS system OpenSSH build;
8. exact `ssh2 0.9.6`/`libssh2-sys 0.3.2`;
9. GRDB `7.11.1`;
10. tree-sitter runtime/SQL grammars;
11. SQLx;
12. Sparkle `2.9.4`; and
13. Sentry Cocoa.

Apple frameworks and system SQLite are separately indexed as platform
components; they are not counted as third-party package approvals.

## 2. Outcome

| Result | Count | Meaning |
| --- | ---: | --- |
| Approve | 0 | No source may enter a production manifest |
| Defer | 10 | Candidate or alternative remains an evaluation input with a closed gate |
| Reject | 3 | Exact source/build must not be adopted |

`production_dependency_adoption_allowed=false` and
`df_m0_008_definition_of_done_met=false`.

Machine-readable summary: `0 approve / 10 defer / 3 reject`.

The three rejected exact candidates are:

- `russh 0.62.4`, because official upstream advisory
  [`GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg),
  published after the DF-M0-005 evidence run, now
  declares `<=0.62.4` affected;
- Apple `OpenSSH-354.120.2`/OpenSSH 10.2p1 and native `ProxyJump/-J`, for the
  already recorded security-floor and shell-execution findings; and
- `ssh2 0.9.6`/`libssh2-sys 0.3.2`, whose exact vendored source lacks current
  security fixes.

Upstream reports `russh 0.62.5` as patched for the new advisory. It is **not**
adopted or technically cleared: it has a new checksum/source and must rerun all
ADR-0012 trust, auth, resource, cleanup, integration and distribution gates.

## 3. What is required to close the previously reported gaps

The short answer is: those “Not tested” and “Risks” are real work gates, not
documentation wording to delete. Closing them requires four different kinds
of authority/evidence.

### 3.1 Build and executable evidence

- A separately authorized production Xcode/Cargo scaffold with manifests,
  schemes and test targets.
- Full supported Xcode, initially minimum macOS 14 and current Apple Silicon
  runners, plus checked-in formatter/linter/build/test commands.
- Rebuilt FFI, editor, bounded custom grid, driver, persistence/Keychain, SSH
  and distribution lanes using their retained contracts. Spike binaries and
  standalone size deltas cannot be promoted as product proof.

### 3.2 Safe database integration evidence

- Pinned disposable container images, loopback/isolated networks, deterministic
  fixtures, fake CI-managed credentials and destructive guards.
- Success/auth/TLS/query/cancel/transaction/failure/rollback/streaming tests,
  with cleanup on success, failure and cancellation.
- An explicit hard block against production or shared staging. No developer
  should enter a real database credential merely to close an M0 row.

### 3.3 Performance and platform evidence

- Release-like product builds on the provisional M1/16 GiB/macOS 14 floor and
  a current supported host.
- The named 1M/10M-row, 500-column, large SQL/schema/BLOB and interruption
  fixtures from `PERFORMANCE_BUDGET.md`.
- Recorded p50/p95/max latency, RSS, retained objects, frame behavior, energy,
  cancellation and variance. Budgets remain provisional until this evidence
  passes review.

### 3.4 Human/legal/product decisions

- Qualified counsel reviews exact license files, bundled/transitive notices,
  redistribution obligations, hosted-service/DPA/privacy terms and
  commercial-use compatibility.
- Product + Legal choose final product license and Community/Pro model.
- Security verifies that Keychain, TLS, destructive-query, row-identity and
  other base safeguards are never paywalled.
- Independent engineering/security reviewers sign the exact dossier. The
  evidence author cannot self-approve those roles.

The operational checklist, owner roles and required evidence are maintained
in [`DEPENDENCY_POLICY.md`](../DEPENDENCY_POLICY.md). Having a GitHub remote is
useful for branches and future CI, but it does not supply Xcode, signing/legal
authority, production manifests or safe database fixtures.

## 4. Evidence identity and reproducibility

### 4.1 Immutable disposed-spike graphs

| Evidence | Commit/tree | Immutable digest/result |
| --- | --- | --- |
| PostgreSQL Cargo lock | commit `150ef5b200b8713d03592d91589d8ae54f8146c8`, tree `6ec35aaffabb503ee70faa6ba1714b209e940075` | SHA-256 `dd2322ad327267c9c91b0954012aa9775657d3755fd34d25206a7888f00744aa`; 124 records, 123 registry, no Git source |
| SSH Cargo lock | commit `875dd468221ad1c6c3c35b34a83c0af48ae3f9ad`, tree `88c8419d8082aa48ad9cafe9505c2fe1283ab300` | SHA-256 `634d476eca69b75645841611fe88ad6a2620c365477296bcb0f5b6fba19a2514`; 179 records, 177 registry, no Git source |
| GRDB resolution | commit `638886064b563aa3f472191c8edbf365a86d3feb`, tree `e4c339ba312e55e9d620b1185155b3fef13ee6e3` | `Package.resolved` SHA-256 `f9630fe714cc974caf85c09ac201d4fbc07761dfe2002dd4405b1abe10ce51f9`; GRDB revision `b83108d…3212` |

The disposed source remains auditable through Git. Repeating lockfiles in the
current tree would create an ambiguous active manifest; the raw graph index
instead records exact Git blob paths, hashes, counts and reconstruction
commands.

### 4.2 Commands actually run

```text
cargo audit 0.22.2 / cargo deny 0.20.2
RustSec DB 685d32fd681b540aa64019820639613c5a4fd922 (1,177 advisories)

cargo audit --db <verified 685d32f...922 checkout> --no-fetch \
  --file <historical PostgreSQL Cargo.lock> --deny warnings
  PASS — 124 dependency records

cargo audit --db <verified 685d32f...922 checkout> --no-fetch \
  --file <historical SSH Cargo.lock> --deny warnings
  PASS — 179 dependency records, but official repository advisory blind spot

cargo deny --config <explicit db-path/db-urls config> --offline ... \
  check advisories licenses bans sources
  PostgreSQL: PASS with duplicate warnings for const-oid/getrandom/syn
  SSH: PASS

official crates.io exact-version checksum/yank queries
  PASS for all eight queried crate/version records

official GitHub repository advisory queries
  russh: 15 advisories; GHSA-m65r-rprj-r5rg blocks exact 0.62.4
  Sparkle: 2 advisories declaring <=2.9.1; 2.9.4 outside declared ranges
  GRDB: empty point-in-time response

jq JSON and SPDX structural assertions
  PASS
```

The post-review reconstruction cloned the official RustSec repository, checked
out and `rev-parse`-verified exact commit
`685d32fd681b540aa64019820639613c5a4fd922`, and bound both scanners to that
checkout. `cargo audit` used explicit `--db` plus `--no-fetch`; `cargo deny`
used an isolated temporary `CARGO_HOME`, explicit `[advisories] db-path`/
`db-urls`, a verified checkout and `--offline` for the scan. The exact runnable
sequences and cleanup are retained in `policy-dry-run.json`; no default mutable
advisory database can satisfy those reconstruction records.

The fresh `russh` result demonstrates that RustSec, `cargo audit` and
`cargo deny` are necessary but not sufficient. The policy resolves conflicting
evidence fail-closed: an official current affected range blocks the exact
source even when another scanner has not ingested it.

## 5. Candidate dispositions

| Candidate | Exact identity / evidence | License and graph posture | Technical/platform finding | Disposition and owner |
| --- | --- | --- | --- | --- |
| Tokio | `1.53.1`, checksum `202cae…0bed`, non-yanked | MIT declared; present in two frozen locks; legal review open | arm64 observed only inside spikes; production task supervision/shutdown and isolated size unproven | **Defer** — Core runtime owner |
| `tokio-postgres` stack | `0.7.18` + connector `0.14.0`; checksums `a528f7…09d3` / `4c2ad4…c2fb` | Technical Cargo policy passes frozen 123-external graph; legal review open | arm64/TLS/stream/cancel/transaction positives, but full-frame cap, unbounded request admission, logging and credential-copy blockers remain | **Defer** — PostgreSQL adapter owner |
| `mysql_async` | No exact version/checksum/features | No full graph, notices or legal review | No auth/TLS/cancel/MariaDB/arm64/size evidence | **Defer** — MySQL/MariaDB adapter owner |
| `rusqlite` | No exact version/checksum or SQLite linkage choice | No full graph/notices/legal review | No unsafe-boundary, bounded blocking, arm64 or size evidence | **Defer** — SQLite adapter owner |
| rustls | `0.23.43`, checksum `028338…3da06`, non-yanked | Apache-2.0/ISC/MIT declared; provider/transitive notices open | arm64 observed in PG spike; platform roots, custom CA, provider, cross-driver behavior and isolated size open | **Defer** — Transport security owner |
| `russh` | Exact `0.62.4`, checksum `b8b67b…464f` | Apache-2.0; 177 external workspace records/131 normal third-party pairs; AWS-LC/legal open | Fresh GHSA affects exact source; DF-M0-005 also left seven rows unsupported | **Reject** — Security + Connections |
| System OpenSSH | Apple `OpenSSH-354.120.2`/10.2p1 on tested OS | OS project/build gate; zero bundled bytes; notices open | Below reviewed security floor; native `-J` shell behavior; lifecycle/integration gaps | **Reject** — macOS Platform Security |
| `ssh2`/libssh2 | `0.9.6`/`0.3.2`, exact checksums and vendored commit | Rust licenses declared; vendored notices open | Exact source omits current fixes; rejected before runtime/size | **Reject** — Security + Connections |
| GRDB | `7.11.1`, revision `b83108d…3212`, source/license hashes | MIT declared; zero normal Swift package dependencies; legal open | Positive metadata recovery evidence, but full XCTest, signed Keychain, realistic product size/performance/minimum-host open | **Defer** — Persistence owner |
| tree-sitter | No exact runtime/grammar versions | Every grammar needs its own source/license graph | No fuzz/corpus/arm64/size evidence; never the sole safety parser | **Defer** — Editor + SQL Safety |
| SQLx | No exact per-adapter version/features | No lock/advisory/license graph | No hostile-frame/cancel/transaction/arm64/size comparison | **Defer** — Database Core lead |
| Sparkle | `2.9.4`, tag `b6496a…bd7`, asset/license hashes | MIT plus bundled notices; legal open | arm64 upstream artifact observed; Developer ID/XPC/install/rollback/key rotation/product-size open | **Defer** — Release Security |
| Sentry Cocoa | No exact SDK/service identity | SDK/service/DPA/privacy/notices not reviewed | No payload allowlist, no-network default, arm64/size or deletion/retention evidence | **Defer** — Privacy + Diagnostics |

The machine-readable source of truth is
[`candidate-dispositions.json`](data/DF-M0-008/candidate-dispositions.json).

## 6. Prototype SBOM and policy dry run

[`sbom.spdx.json`](data/DF-M0-008/sbom.spdx.json) is a valid SPDX 2.3
**candidate evaluation inventory**. Its root uses `OTHER` relationships with
the explicit comment `EVALUATES; not adopted`; exact component dependency
edges are included only where frozen spike evidence exists. Unselected
candidates deliberately have no invented version.

It is not a release SBOM because no production manifest, lock or artifact
exists. Release SBOM reproducibility remains unsupported until a separately
authorized product scaffold builds the final nested artifact.

The planned policy dry run is `block`, even though the historical Cargo policy
commands pass. It blocks because:

- an official current advisory affects exact `russh 0.62.4`;
- five candidate groups have no exact identity, while seven have no full
  package graph (the latter also includes two exact rejected system/vendored
  sources whose provenance is recorded without a resolved package graph);
- technically measured candidates still have runtime/integration gates;
- final license/notices and independent reviews are missing; and
- no product artifact exists for true size/SBOM reconciliation.

The policy does not reject all future use of dependencies. It prevents an
unknown or unsafe exact input from silently becoming a shipped dependency.

## 7. Backlog acceptance and definition-of-done mapping

| DF-M0-008 requirement | Result | Evidence / remaining work |
| --- | --- | --- |
| Record version/source/checksum/license/transitives/advisories/maintenance/toolchain/arm64/size/replacement | Partial by design | Exact retained spike candidates are recorded; unselected candidates explicitly lack identity and therefore defer |
| Every proposed dependency has approve/reject/defer, owner and date | Pass | 13/13 have a unique disposition, owner role and 2026-08-01 date |
| No unresolved license/advisory blocker | **Not met** | Fresh russh advisory is resolved fail-closed by rejection, but exact legal/notices reviews and several candidate identities remain unresolved |
| Prototype SBOM | Pass for candidate-inventory scope | SPDX 2.3 structure and internal references pass; it explicitly denies release/adoption scope |
| Release SBOM reproducibility | Unsupported | No production manifest/build/artifact |
| Checksum/source verification | Pass for the exact queried/historical inputs | Git blob and registry checksums reproduce; point-in-time API response hashes retained |
| Advisory/license policy dry run | Block as intended | Multi-source advisory gate catches russh blind spot; legal gate remains closed |
| Engineering/security/legal review | **Not met** | This report prepares evidence but cannot impersonate independent human reviewers or counsel |
| ADR/backlog exact decision update | Prepared | ADR-0015 and planning documents record no-adoption/defer/reject posture |

The engineering work package is ready for external review, but the backlog
Definition of Done is not satisfied. Keeping the gate false is the correct
safe outcome; it does not block the independent DF-M0-009 wireframe review.

## 8. Not established

- No dependency is legally approved, adopted, linked or distributed.
- No production Swift/Rust source, Xcode project, Cargo/SPM manifest, test
  target or release artifact exists.
- No xcodebuild, UI runtime, FFI integration, signed Keychain, real updater,
  Developer ID/notarization or clean-Mac test ran in this task.
- No automated database integration ran; no database endpoint or credential
  was needed for a documentation/supply-chain consolidation task.
- No minimum-host or product performance budget is claimed as met.
- No product license or Community/Pro commercial model was selected.
- A clean advisory query is never represented as proof of no vulnerability.

## 9. Durable raw evidence

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`candidate-dispositions.json`](data/DF-M0-008/candidate-dispositions.json) | 13 candidate dispositions, owners, blockers and re-entry paths | `c53ddaa76eb07a9aa89c612d34a749a04e847d59f65ab59c826ec6ee1ae403bc` |
| [`transitive-graphs.json`](data/DF-M0-008/transitive-graphs.json) | Immutable lock/resolution identities and graph gaps | `ec84c5f930fca3aa68a7eb7f106571190820a964f6eb6df325a9a175dc75cec3` |
| [`upstream-refresh.json`](data/DF-M0-008/upstream-refresh.json) | Official registry/release/advisory refresh and scanner blind spot | `d10ab61dd7f3e137f1ddface1d39f7aff8b52918b6e0f408e34addea4aaf71f7` |
| [`sbom.spdx.json`](data/DF-M0-008/sbom.spdx.json) | SPDX 2.3 non-adoption candidate inventory | `b8aa9b7513a1b607520426e1718f33c0a10b6bafdc3ec178a086ece1c480b337` |
| [`policy-dry-run.json`](data/DF-M0-008/policy-dry-run.json) | Planned gate rules, reproducible command sequences, results and blocking reasons | `72e3055c924fff4ebe8feb85d1965a1cad537b7914eebd92b3e9634e09c238e4` |

## 10. Primary references

- [crates.io API](https://crates.io/data-access)
- [RustSec advisory database](https://github.com/RustSec/advisory-db)
- [`russh` advisory `GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg)
- [`russh` upstream advisories](https://github.com/Eugeny/russh/security/advisories)
- [Sparkle upstream advisories](https://github.com/sparkle-project/Sparkle/security/advisories)
- [GRDB upstream advisories](https://github.com/groue/GRDB.swift/security/advisories)
- [Swift package URL type definition](https://github.com/package-url/purl-spec/blob/main/types/swift-definition.json)
- [SPDX 2.3 specification](https://spdx.github.io/spdx-spec/v2.3/)
- [GitHub dependency review](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/about-dependency-review)
- [Apple open source releases](https://opensource.apple.com/releases/)
