# DF-M0-007 disposable SQLite and Keychain separation spike

This standalone spike tests one planning hypothesis: synthetic workspace and
connection metadata can migrate transactionally in a bounded local SQLite
store while the corresponding fake credential exists only in the macOS Data
Protection Keychain and never falls back to plaintext persistence.

It is not a product persistence module. It has no database driver, remote or
production database, real credential, production schema, Swift/Rust FFI,
signed helper, UI, telemetry or reusable migration. Every SQLite file,
workspace, profile, log, export, snapshot, Keychain service/account and secret
is generated for one disposable local run.

## Exact dependency candidate

The frozen candidate is upstream GRDB `7.11.1`, Git tag `v7.11.1`, commit
`b83108d10f42680d78f23fe4d4d80fc88dab3212`. Swift Package Manager must
resolve exactly that revision. The candidate uses the operating system SQLite
library; SQLCipher and custom SQLite builds are outside this spike.

Passing the runtime matrix does not approve GRDB. Adoption also requires exact
license/notices, source/revision, advisory, maintenance, transitive package,
Swift/Xcode/macOS, Apple Silicon, binary-size, system-SQLite support and
replacement-cost evidence.

## Security and ownership invariants

- SQLite contains only non-sensitive metadata and an independent random UUID
  credential reference. It has no password, token, passphrase, private key,
  client secret, secret-derived identifier or plaintext fallback column.
- The fake secret is a small generic-password item accessed with
  `kSecUseDataProtectionKeychain = true`, synchronization disabled, and
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Every Keychain query is scoped by a unique disposable service and random
  account/reference. The runner never enumerates unrelated items or prints the
  secret, Keychain contents, environment or user Keychain path.
- The login/default Keychain is never locked, reconfigured or added to a
  custom search list. Actual locked/denied behavior is not simulated by
  disrupting the user's session.
- Duplicate, missing, interaction-not-allowed and authorization failures map
  to typed errors. A failure never writes the secret to SQLite, a file,
  `UserDefaults`, JSON, logs, process arguments or a fallback cache.
- Keychain and metadata deletion are independent, explicit operations.
  Deleting history/metadata cannot delete a credential; deleting a credential
  cannot silently delete or rewrite profile metadata.
- Versioned migrations are transactional. An unknown future migration,
  corruption or integrity failure blocks use without deleting/recreating the
  original file.
- SQLite files are owner-only. WAL, SHM, backup, export, log and snapshot
  artifacts are bounded, synthetic and removed on every runner exit path.
- No secret value is `Codable`, printable or equatable by value. The fake
  `SecretValue` lifetime is still only a Swift best-effort boundary; this spike
  cannot prove memory zeroization.

## Frozen evidence matrix

| ID | Scenario | Required evidence |
| --- | --- | --- |
| `EN-01` | Host/tool inventory | Record source, host/OS/arm64, Swift/SPM, system SQLite, Security.framework, full-Xcode/signing availability and no environment dump. |
| `MD-01` | Metadata schema allowlist | Exact tables/columns/indices/foreign keys are recorded; no prohibited secret field exists and credential references are random UUIDs. |
| `MG-01` | Upgrade success | A v1 database migrates to v2 atomically and retains the synthetic profile/workspace/history semantics. |
| `MG-02` | Failed migration rollback | A deliberately throwing migration leaves no partial table/data/migration marker. |
| `MG-03` | Future/downgrade refusal | A database containing an unknown future migration is rejected without mutation or auto-rebuild. |
| `TX-01` | Crash transaction recovery | A child process exits during an uncommitted write; reopening rolls back the row and passes integrity check. |
| `CR-01` | Corruption handling | A copied database with a corrupted header fails closed with a typed database error; the original remains intact. |
| `CO-01` | Bounded concurrency | A fixed DatabasePool reader/writer matrix completes with deterministic counts, no busy leak and no unbounded worker creation. |
| `RT-01` | Retention | History exceeds a fixed limit, is trimmed deterministically to the newest bounded rows and never deletes profiles/credentials. |
| `BK-01` | Backup/integrity | A closed/checkpointed metadata backup reopens, passes integrity check and contains no secret canary. |
| `FP-01` | File permissions | SQLite, WAL/SHM when present, backup, export, snapshot and log files are owner-only or more restrictive. |
| `WL-01` | Journal-mode comparison | Exact DELETE/DatabaseQueue and WAL/DatabasePool synthetic timings/bytes are recorded on the named host; result is not a minimum-host performance claim. |
| `KC-01` | Data Protection Keychain CRUD | Fake item add/read/update/delete succeeds through Security.framework; final lookup returns missing. |
| `KC-02` | Duplicate and missing | Duplicate add and missing lookup/delete map to explicit typed outcomes, not overwrite or plaintext fallback. |
| `KC-03` | Accessibility and synchronization | Returned attributes prove Data Protection behavior, `WhenUnlockedThisDeviceOnly`, synchronizable false and the exact disposable service/account. |
| `KC-04` | Locked/denied policy | Injected `errSecInteractionNotAllowed` and `errSecAuthFailed` return typed locked/denied errors and no fallback bytes; actual session lock/ACL denial is explicitly unsupported unless safely available. |
| `DL-01` | Independent deletion | Deleting history/metadata preserves the Keychain item; deleting the item preserves the profile/reference and produces a typed missing credential. |
| `SC-01` | Secret surface | Exact fake canary is absent from SQLite main/WAL/SHM, backup, export, snapshot, logs, stdout/stderr, process argv, retained JSON/text and Git. |
| `DP-01` | Dependency dossier | Exact GRDB revision/archive/license/advisories/package graph, system SQLite, toolchain requirements, arm64 build, binary-size delta and replacement path are recorded. |
| `CL-01` | Cleanup | No Keychain item, SQLite/WAL/SHM/backup, package checkout/build, canary file or test directory remains after the runner exits. |

## Measurement and fixture contract

- The runner uses a unique `/tmp/dataforge-persistence-keychain-*` directory
  with mode `0700`, a unique Keychain service prefix, and an outer cleanup
  phase that verifies both filesystem and Keychain absence.
- The Keychain canary enters the probe through an owner-only file path. The
  value itself never appears in argv or retained evidence.
- All loops have fixed counts. Concurrency uses a bounded number of workers;
  history and captured output have explicit limits.
- Journal timings are monotonic wall-clock observations on the named developer
  host. They select no production mode by themselves.
- The child crash case receives only an owned SQLite path and synthetic row ID,
  never the secret or Keychain service.
- Raw evidence contains statuses, counts, hashes, bytes, durations, error
  categories and sanitized versions. It omits SQL row contents, secret data,
  Keychain paths, environment variables and personal absolute paths.

## Expected commands

The checked-in runner executes applicable equivalents of:

```bash
swift package resolve --disable-dependency-cache --cache-path <owned-temp>
swift build -c release --scratch-path <owned-temp>
swift test --scratch-path <owned-temp>
swift package show-dependencies --format json
file <release-probe>
lipo -archs <release-probe>
./scripts/run-evidence.sh <absolute-empty-output-directory>
```

It also verifies `Package.resolved`, archives the exact GRDB checkout, hashes
the license, queries the upstream release/advisory APIs, records SQLite compile
options, compares a tiny Swift baseline binary, scans every observable fixture
for the generated canary, and proves cleanup.

## Decision rule

GRDB may remain a planning candidate only if every migration, corruption,
crash, concurrency, retention, backup, permission, Keychain CRUD, separation,
secret-surface and dependency scenario either passes at its full boundary or
is explicitly partial/unsupported with the production capability still closed.

Any secret outside Keychain, unscoped item query, lost metadata/credential,
partial migration, silent database rebuild, corruption treated as empty,
plaintext fallback, unsafe file permission, unbounded work, unexplained
dependency/advisory or failed cleanup rejects the candidate immediately.

Actual locked/denied, signed-app access-group/Team migration, helper access,
minimum macOS 14 hardware, long interruption/soak and final legal evidence are
separate adoption gates. A fake-injected error cannot pass those real system
boundaries.

## Disposal

After exact commands, sanitized raw evidence, limitations, schema/security
contracts and a dependency disposition are committed in a report and new ADR,
this entire directory is deleted in a separate disposal commit. Production
models, migrations and Keychain code must be regenerated under review; spike
code is not copied into a product target.
