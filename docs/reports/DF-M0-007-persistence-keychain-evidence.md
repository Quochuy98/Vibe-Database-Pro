# DF-M0-007 SQLite metadata and Keychain separation evidence

Status: Evidence and disposal complete; SQLite/Keychain architecture retained
for planning, GRDB conditional, production persistence and credential gates
closed

Evidence date: 2026-07-30

Disposable source revision:
`638886064b563aa3f472191c8edbf365a86d3feb`

Related decision: [ADR-0014](../adr/0014-m0-persistence-keychain-disposition.md)

Sanitized raw evidence: [`data/DF-M0-007`](data/DF-M0-007/)

## 1. Decision question and scope

DF-M0-007 asked whether synthetic connection/workspace metadata can migrate,
recover, retain, back up and run bounded local concurrency in SQLite while the
corresponding fake credential is represented only by a random Keychain
reference and never falls back to plaintext persistence.

The disposable Swift package contains no product target, UI, remote database,
database driver, real connection, real credential, user data, helper, public
FFI contract, production schema or reusable migration. All profiles,
workspaces, history rows, SQLite files, Keychain service/account identifiers
and canary bytes were generated for one owner-only `/tmp` run and removed.

The result separates three evidence boundaries:

1. SQLite metadata behavior and secret-negative surface checks that ran;
2. injected credential-store policy and actual unsigned-CLI
   Security.framework behavior; and
3. signed application, ACL/access-group, full-Xcode and long-soak behavior that
   did not run.

## 2. Disposition

- Retain ADR-0004's SQLite-behind-a-Swift-port architecture and ADR-0005's
  Keychain-only secret architecture.
- Retain exact GRDB `7.11.1` only as a conditional planning candidate. Do not
  add it to a production target or treat this spike schema/migration as a
  production foundation.
- Keep production persistence and credential capabilities closed. Actual Data
  Protection Keychain add returned `errSecMissingEntitlement` (`-34018`) on
  the Command Line Tools executable, so real CRUD and returned accessibility
  attributes are unsupported, not passed.
- Select neither DELETE nor WAL for production. The single named-host sample
  records a speed/space trade-off but is not a minimum-host benchmark or a
  workload decision.
- Regenerate models, migrations, Keychain access and tests under a separately
  reviewed production request. The disposable source is evidence only.

The frozen matrix is `15 pass / 3 partial / 2 unsupported / 0 fail` across 20
rows. `complete_keychain_gate_passed=false`,
`production_dependency_adopted=false`, and
`production_persistence_enabled=false` are the only valid task-level
conclusions.

## 3. Evidence identity and environment

| Item | Exact value |
| --- | --- |
| Source commit | `638886064b563aa3f472191c8edbf365a86d3feb` |
| Spike Git tree | `e4c339ba312e55e9d620b1185155b3fef13ee6e3` |
| Source `git archive` SHA-256 | `c1a680d8f083b6d504607032a95534ab13f97031a737bc6ff7d0af97bdce5e0b` |
| Host | Mac15,3, arm64, 24 GiB, 8 logical CPUs |
| OS | macOS 26.5.2, build 25F84 |
| Developer tools | `/Library/Developer/CommandLineTools`; full Xcode unavailable |
| Swift / SwiftPM | Apple Swift 6.3.3 / SwiftPM 6.3.3 |
| System SQLite | `3.51.0` |
| Valid code-signing identities | `0`; names and Keychain paths were not enumerated |

The host is newer than the provisional macOS 14/M1/16 GiB floor. This run
does not establish the minimum host, another machine, an Apple-signed
application identity, sandbox behavior or a production workload.

## 4. Commands and validation result

The source ran these relevant commands:

```bash
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
./scripts/test.sh
DATAFORGE_REQUIRE_CLEAN=1 ./scripts/run-evidence.sh \
  <absolute-empty-evidence-directory>
swiftc -frontend -parse Tests/PersistenceKeychainCoreTests/*.swift
```

The test wrapper passed Zsh syntax, strict Swift formatting, the release
warnings-as-errors build, executable runtime assertions, evidence JSON/schema
assertions, secret/path scans and cleanup assertions. The exact clean runner
returned:

```text
DF-M0-007 evidence complete: 15 pass, 3 partial, 2 unsupported, 0 fail
```

The runner also invoked `swift test ... -Xswiftc -warnings-as-errors`. It
exited `1` while emitting the test module because this Command Line Tools
installation has no `XCTest` module. The 19 XCTest source cases were retained
and parsed, but their XCTest runtime did not run. This limitation is recorded
as `xctest_available=false`; executable assertions are not relabelled as
XCTest success.

No `xcodebuild build`, `xcodebuild test`, signed-app Keychain integration,
session lock, ACL denial, access-group/Team migration, helper access, minimum
macOS 14 run or long soak ran.

## 5. Metadata schema and migration behavior

The exact allowlist is stored in [`schema.json`](data/DF-M0-007/schema.json).
The non-internal tables are:

```text
connection_profiles
  id, display_name, host, port, environment, read_only,
  credential_reference

workspaces
  id, profile_id, title, updated_at_milliseconds

query_history
  id, profile_id, executed_at_milliseconds, operation_kind
```

The only additional table is GRDB's `grdb_migrations(identifier)`. There is no
password, passphrase, private key, API key, access/refresh token, client
secret, secret value or query text column. Credential references are
independent random UUIDs, not hashes or other secret-derived values.

Migration evidence:

- `v1_metadata` created profiles, workspaces and minimal history;
- `v2_history_kind` added a non-null `operation_kind` with deterministic
  legacy default `query` and a retention index;
- a v1 profile, workspace and history row survived migration to v2;
- a deliberately throwing migration left no partial table, row or migration
  marker; and
- a synthetic unknown `future_v3` marker was refused before migration, with
  the SQLite file byte-for-byte unchanged and no auto-rebuild.

`eraseDatabaseOnSchemaChange` remained false. Every value mutation used bound
arguments. History retention ran inside the same transaction as insertion and
removed only rows beyond the fixed newest-first limit.

## 6. Crash, corruption, concurrency, retention and backup

| Scenario | Exact observation |
| --- | --- |
| Crash recovery | Child exited `86` inside an explicitly uncommitted history insert; marker was absent after reopen and integrity passed. |
| Corruption | A copied file with a damaged header returned the typed corrupt-database path; it was not deleted/rebuilt, and the original reopened with its profile intact. |
| Bounded concurrency | One WAL pool used four fixed workers/readers, completed 100 writes and reads with deterministic count and zero reported errors. |
| Retention | 25 synthetic history rows were trimmed to the newest 10; profile metadata remained. |
| Backup | A checkpointed online SQLite backup reopened, passed integrity/foreign-key checks and retained profile/workspace metadata. |
| Permissions | Run root was `0700`; SQLite, WAL/SHM when present, backup, export, snapshot and log files were `0600` or stricter. |

The child received only an owned SQLite path and random marker, never the
canary, Keychain service or credential reference. No operation used a remote,
production or shared database.

## 7. DELETE versus WAL observation

Both modes executed 100 fixed synthetic history writes on the named host:

| Mode | Connection | Elapsed | Open SQLite bytes |
| --- | --- | ---: | ---: |
| DELETE | `DatabaseQueue` | 26.881 ms | 90,112 |
| WAL | `DatabasePool`, maximum four readers | 9.113 ms | 1,837,336 |

In this one run WAL was about 2.95 times faster while its open main/WAL/SHM
footprint was about 20.4 times larger. There were no repeated samples,
minimum-host measurements, realistic workspace/history volumes, concurrent
long readers, interruption soak or product launch/RSS data. Therefore the
result satisfies the comparison row but selects no production journal mode.

## 8. Keychain and independent-deletion result

Every actual query was scoped to a unique disposable generic-password
service/account, `kSecUseDataProtectionKeychain=true`, and synchronization
off. Add policy additionally requested
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

On this unsigned Command Line Tools executable:

- `SecItemAdd` returned `errSecMissingEntitlement` (`-34018`);
- the exact reference lookup returned `errSecItemNotFound` (`-25300`), proving
  the failed add created no item;
- the service-wide outer delete also returned missing entitlement and was not
  reported as successful cleanup; and
- no login/default Keychain was locked, reconfigured, enumerated or added to a
  search list.

Consequently `KC-01` and `KC-03` are unsupported. Duplicate/missing behavior
and independent deletion are partial because their full actual-system
sequence could not run. An injected store proved typed duplicate, missing,
locked, denied and missing-entitlement behavior with no fallback bytes.

Deleting metadata history preserved the model credential; deleting the model
credential preserved the actual profile and workspace/reference. This proves
the architectural separation in the test double, not a signed-app Keychain
integration. Actual lock/ACL denial was not manufactured by disrupting the
user's session.

## 9. Secret-surface and cleanup evidence

The random fake canary entered the process only through an owner-only file,
not a value in argv or the environment. Before deletion, the runner scanned:

- SQLite main/WAL/SHM files, backup, export, snapshot and log artifacts;
- probe stdout/stderr, build/resolve/test logs and cleanup output;
- retained JSON/text evidence and a process-command snapshot; and
- Git-tracked content.

The exact canary was absent. The probe JSON was itself scanned before the final
runtime file was deterministically derived from it. Retained evidence was also
rejected if it contained a personal or transient absolute path.

The final exact-reference lookup was missing, and the entire temporary build,
checkout, canary and fixture tree was removed before `CL-01` was emitted. This
does not prove memory zeroization; Swift `Data` makes secret lifetime only a
best-effort boundary.

## 10. Exact GRDB candidate dossier

| Item | Evidence |
| --- | --- |
| Version / revision | `7.11.1` / `b83108d10f42680d78f23fe4d4d80fc88dab3212` |
| Published | 2026-06-18T12:15:08Z |
| Source archive SHA-256 | `015b476733e6c34f567ef78071d2ac3b92b6249805496966856f3c7f03080e05` |
| License file SHA-256 | `9853f9dce81365fcc1d9b46004633354450164b8d17904e92e80c444545f7e87` |
| Preliminary license posture | MIT; application notices and final legal review still required |
| Upstream advisories API | Empty array at evidence time; point-in-time only; endpoint/API version, reported evidence date, commit context and the missing exact query date/timestamp are recorded in the companion provenance artifact |
| Normal package graph | Root → GRDB; GRDB has zero normal Swift package dependencies and uses system SQLite |
| Requirements | Swift 6.1+, Xcode 16.3+, upstream macOS 10.15+/SQLite 3.20+; spike target macOS 14 |
| Release arm64 probe | 5,830,696 bytes |
| Tiny Swift baseline | 50,648 bytes |
| Probe delta | 5,780,048 bytes |

The binary value is the complete standalone probe delta, not an incremental
shipping-app estimate: it includes the spike's migration, evidence and
Keychain code as well as GRDB. A product-size measurement must compare an
otherwise identical production scaffold with and without the exact candidate.

Post-run review on 2026-08-01 preserved the immutable empty advisory array and
added a companion provenance record instead of changing its consumer-visible
shape. The same review renamed two ambiguous derived package-graph fields:
the probe package has one normal external dependency named GRDB, while GRDB
itself has zero transitive normal Swift package dependencies. Values,
measurements and the deferred adoption disposition did not change.

Replacement remains possible behind the Swift persistence port, but moving to
the SQLite C API or another wrapper requires migration/query rewrites and a
fresh conformance/security run. The dossier is technical evidence, not
dependency approval or legal advice.

## 11. Retained raw evidence

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`environment.json`](data/DF-M0-007/environment.json) | Source, host, toolchain and non-enumerating signing inventory | `42d4e0134b26592973cf1989f57d1df2b03ecfc2cbeb93e5fd982a8d0bd97d7c` |
| [`runtime.json`](data/DF-M0-007/runtime.json) | Frozen scenario matrix, measurements and closed gates | `ca7ff64474de203b614e33140280cf935201b784bae7afa49b0ea3fe8cfd69b6` |
| [`schema.json`](data/DF-M0-007/schema.json) | Exact table/column/index/foreign-key allowlist | `3880544bac5904299dd9b7873797a1ebe4ce0bdf1f18ade0bb821f0fe179ed9a` |
| [`grdb-candidate.json`](data/DF-M0-007/grdb-candidate.json) | Exact candidate provenance, requirements and binary evidence | `4792806c02b185215f7e8ca3e97078c98d066c58811f15cd0e2ce1dfd73dba46` |
| [`grdb-advisories.json`](data/DF-M0-007/grdb-advisories.json) | Sanitized upstream repository advisory snapshot | `37517e5f3dc66819f61f5a7bb8ace1921282415f10551d2defa5c3eb0985b570` |
| [`grdb-advisory-query.json`](data/DF-M0-007/grdb-advisory-query.json) | Post-run companion with endpoint, API version, evidence/commit context, missing exact query time, raw-result identity and interpretation limit | `d2eeb3a84fb13237f547caa7d5ce6c794c26dc26389c80fef45811abf40dfb6b` |
| [`package-graph.json`](data/DF-M0-007/package-graph.json) | Sanitized Swift package graph | `1c182cd35252c59e4ef3a7932f46b9bb2665c4849f720b3f1c377f907c2cb5c7` |
| [`runner-completion.txt`](data/DF-M0-007/runner-completion.txt) | Outer canary/cleanup and closed-gate marker | `9dac97059c6560f385cdeb5669e1b4e7ae4a4bc703b41c6daf143188ea28173f` |

## 12. Frozen matrix

| ID | Status | Evidence boundary |
| --- | --- | --- |
| `EN-01` | Pass | Sanitized host/tool/source/signing inventory; no environment dump. |
| `MD-01` | Pass | Exact schema allowlist; zero prohibited secret columns. |
| `MG-01` | Pass | v1→v2 atomic upgrade retained profile/workspace/history. |
| `MG-02` | Pass | Throwing migration rolled back schema/data/marker. |
| `MG-03` | Pass | Unknown future marker refused without file mutation/rebuild. |
| `TX-01` | Pass | Uncommitted crash row rolled back; integrity passed. |
| `CR-01` | Pass | Corrupt copy failed closed; original remained intact. |
| `CO-01` | Pass | Four fixed workers/readers; 100 writes; zero errors. |
| `RT-01` | Pass | 25→10 deterministic retention; profile preserved. |
| `BK-01` | Pass | Checkpointed backup integrity and metadata retention. |
| `FP-01` | Pass | Owner-only run root and file surfaces. |
| `WL-01` | Pass | Named-host DELETE/WAL observation; no production selection. |
| `KC-01` | Unsupported | Actual add missing entitlement; exact lookup missing. |
| `KC-02` | Partial | Injected duplicate/missing typed; actual duplicate could not run. |
| `KC-03` | Unsupported | No returned actual accessibility/synchronization attributes. |
| `KC-04` | Partial | Injected locked/denied pass; actual lock/ACL not changed. |
| `DL-01` | Partial | Model independent deletion pass; actual Keychain sequence unavailable. |
| `SC-01` | Pass | Canary absent from specified file/output/argv-snapshot/Git surfaces. |
| `DP-01` | Pass | Exact source/license/advisory/graph/toolchain/arm64/size/replacement dossier. |
| `CL-01` | Pass | Failed add left exact item missing; transient tree removed. |

## 13. Required re-entry evidence

Implementation may be reconsidered only after a separately approved scaffold
proves:

- full Xcode/XCTest build and all 19 retained test intents on minimum macOS 14
  and current supported hardware;
- a signed app with the intended bundle ID, Team, entitlements and Data
  Protection Keychain CRUD/attributes;
- actual duplicate, missing, locked, denied, user-cancel, ACL/access-group,
  signing-identity migration and helper-access behavior with no fallback;
- crash/corruption/migration/backup behavior under production schema size,
  cancellation/interruption, launch/RSS and long concurrency soak;
- a repeated realistic DELETE/WAL workload and product binary-size delta;
- exact license/notices, SBOM, maintenance/advisory review and independent
  dependency/security approval; and
- seeded secret scans across the signed app's SQLite, backups, exports, logs,
  diagnostics, crash capture, clipboard, process/IPC and helper surfaces.

## 14. Disposal

The report, ADR and sanitized evidence were recorded in commit
`8cfa4b5125959eb70765d6807c508d5681bb3ee6`. The complete disposable package
was deleted in separate disposal commit
`02c86b7d05bdb0649fc9b2838b73c1eddfb2fa42`; the exact source remains
auditable at `638886064b563aa3f472191c8edbf365a86d3feb`. Production code must
be regenerated rather than copied from this package.
