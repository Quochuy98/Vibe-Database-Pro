# DF-M0-002 — PostgreSQL driver, TLS, streaming and transaction evidence

Status: complete as a disposable feasibility spike; candidate disposition:
**DEFER**

Evidence date: 2026-07-30
Evidence source commit: `150ef5b200b8713d03592d91589d8ae54f8146c8`

## 1. Decision question and scope

This spike asks whether the pinned `tokio-postgres` stack can be used as the
first PostgreSQL adapter candidate while preserving DataForge's requirements
for TLS identity, typed streaming, cancellation truth, transaction safety,
bounded resources and credential hygiene.

The artifact is disposable evidence only. It is not a production adapter, a
domain interface, an FFI contract or a macOS application implementation.
PostgreSQL 17.10 is the only server/version fixture exercised, and it is an
arm64 local container. No production/shared-staging endpoint, real credential,
customer row or commercial source/assets were used.

## 2. Evidence identity

| Item | Recorded value |
| --- | --- |
| Host | Apple Silicon Mac, `arm64` |
| OS | macOS 26.5.2, build 25F84 |
| Docker | 28.4.0 client/server |
| Rust toolchain | 1.97.1 (pinned by `rust-toolchain.toml`) |
| Effective target MSRV | Rust 1.85.0, verified with an arm64 check |
| PostgreSQL image | `postgres@sha256:b797483593b82cbea9a7ee41c88f324a90d10d9c2504d40e755d91c75456366d` |
| Image platform/size | `linux/arm64`, 114,970,806 bytes |
| Fixture network | Docker random port published only on `127.0.0.1` |
| Run identity | 16 lower-case hex marker; database/container names include marker |
| Dependency graph | 124 lockfile package records (123 registry + spike root); 90 unique target-tree nodes |

The exact lockfile is part of the evidence source commit. All external
packages resolve from crates.io with checksums; no Git dependency is present.
The target graph has three intentional duplicate-version warnings:
`const-oid` 0.9/0.10, `getrandom` 0.2/0.4 and `syn` 2/3. They arise from the
TLS certificate and PostgreSQL/crypto branches and were not silently hidden.

## 3. Fixture and safety design

`scripts/test.sh` fails closed unless both
`DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1` and
`DATAFORGE_TEST_ENVIRONMENT=test` are explicitly supplied. It additionally
requires the immutable image digest, validates the random loopback port,
matches the database/container marker, verifies a server-side custom GUC and
fixture table, and checks certificate/key containment and permissions.

The fixture creates a fake SCRAM owner credential through a mode-0600 file,
custom CA/server/client/wrong-client certificates, an mTLS role pair and a
transaction probe table. Private keys are never printed. Captured PostgreSQL,
OpenSSL and harness logs are scanned for the generated canaries, private-key
headers and connection-string/password patterns before any output is shown.
Cleanup is label- and marker-scoped and runs on success, failure and HUP/INT/
TERM. A dedicated SIGTERM run exited 143 with no disposable container,
volume, network, process or temp directory remaining.

All writes in the matrix are explicit transactions. There is no automatic
write retry or hidden commit. A connection loss is reported to the client as
`unknown_lost`; a separate session verifies the uncommitted row is absent, but
that observation is not presented as proof that a client observed a commit
outcome.

## 4. Commands and results

The commands below were run against the evidence source commit (the final
runtime matrix was rerun after the PEM parser and lifetime fixes).

```text
cargo fmt --manifest-path spikes/postgres-driver/Cargo.toml -- --check       PASS
cargo clippy --manifest-path spikes/postgres-driver/Cargo.toml \
  --locked --all-targets --all-features -- -D warnings                       PASS
cargo test --manifest-path spikes/postgres-driver/Cargo.toml \
  --locked --all-targets --all-features                                      PASS (6 tests)
cargo test --manifest-path spikes/postgres-driver/Cargo.toml \
  --locked --release --all-targets --all-features                            PASS (6 tests)
cargo +1.85.0 check --manifest-path spikes/postgres-driver/Cargo.toml \
  --locked --target aarch64-apple-darwin --all-targets --all-features        PASS
cargo audit --file Cargo.lock --deny warnings                                PASS (0 vulnerabilities)
cargo deny check advisories licenses bans sources                            PASS
zsh -n spikes/postgres-driver/scripts/test.sh                                PASS
```

The full disposable run was:

```sh
DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1 DATAFORGE_TEST_ENVIRONMENT=test \
  ./spikes/postgres-driver/scripts/test.sh
```

It exited 0. The negative guard invocation without the required variables
exited 64. The final successful evidence process reported 23,085,056 bytes
maximum RSS and 3.23 seconds wall time for the complete matrix; this is a
developer-host measurement, not the provisional release-floor budget.

## 5. Runtime matrix

| Evidence case | Result |
| --- | --- |
| Valid SCRAM password + custom CA + hostname + required channel binding | Pass |
| Wrong password | Rejected and classified authentication |
| Wrong CA | Rejected and classified TLS |
| Hostname `127.0.0.1` against a `localhost` certificate | Rejected and classified TLS |
| Valid mTLS client certificate | Pass |
| Missing/wrong mTLS identity | Rejected and classified authentication |
| Typed `query_raw` stream | 1,000,000 rows; deterministic FNV digest `1179329668318235738` |
| Row chunk cap | 1,000 rows; 1,000 chunks |
| Byte chunk cap | 3 chunks; maximum 3,900,104 bytes; maximum 13 rows |
| Cell cap | 1,048,577-byte cell rejected before chunk admission |
| Slow consumer | 1 ms pause at chunk boundaries; session remained bounded and usable |
| Slow-query cancellation | Server-confirmed cancellation in 12 ms; same session query passed |
| Cancellation race | Completed-before-cancel outcome accepted; cancel request not treated as proof |
| Commit | One-row write committed and independently verified |
| Constraint failure | Duplicate key classified; aborted transaction required rollback |
| Explicit rollback | Row absent after rollback |
| Cancellation inside transaction | Cancellation classified; aborted state and explicit rollback verified |
| Backend termination during transaction | Client classified network/lost; no retry/commit; separate verification row absent |
| Malformed length | Controlled connection error |
| Header-only 8 MiB advertisement | No eager full-frame allocation observed; probe explicitly does not claim a complete allocation measurement |
| Full streamed 8 MiB backend frame | Driver buffered `8,388,604` body bytes before application admission; recorded as a blocking limitation |
| Structured evidence/log scan | Allowlisted JSON only; seeded canary and connection-string scans passed |

The row/byte figures are application admission measurements. They do not mean
that the upstream driver has already enforced those limits at the wire-buffer
boundary.

## 6. Dependency and supply-chain dossier

Core direct candidates and lockfile checksums:

| Package | Version | License expression | Checksum |
| --- | ---: | --- | --- |
| `tokio-postgres` | 0.7.18 | MIT OR Apache-2.0 | `a528f7d280f6d5b9cd149635c8705b0dd049754bc67d81d31fa25169a93809d3` |
| `tokio-postgres-rustls` | 0.14.0 | MIT | `4c2ad44aa0ae96db89c4742212ed41645b2f597311ff6e1945542a4d9fadc2fb` |
| `rustls` | 0.23.43 | Apache-2.0 OR ISC OR MIT | `0283386ce02abc0151e1761d08802dfe86c173b0b494af5cbc086574e453da06` |
| `tokio` | 1.53.1 | MIT | `202caea871b69668250d242070849eb495be178ed697a3e98aebce5bc81a0bed` |
| `futures-util` | 0.3.33 | MIT OR Apache-2.0 | `a77a90a256fce34da66415271e30f94ee91c57b04b8a2c042d9cf3220179deaa` |
| `serde_json` | 1.0.151 | MIT OR Apache-2.0 | `c841b55ecdae098c80dcae9cf767f6f8a0c2cdb3416bbef72181df4d0fe73f14` |
| `uuid` | 1.24.0 | Apache-2.0 OR MIT | `bf3923a6f5c4c6382e0b653c4117f48d631ea17f38ed86e2a828e6f7412f5239` |

`cargo audit` used the RustSec snapshot loaded on 2026-07-30 (1,173
advisories) and found no vulnerability or unmaintained-package warning after
replacing the unmaintained `rustls-pemfile 2.2.0` direct dependency with the
maintained `rustls-pki-types::pem::PemObject` API. `cargo deny` passed
advisories, licenses, bans and sources. Its duplicate-version warnings remain
visible and are documented above. This is engineering evidence, not legal
approval; notices, commercial-use terms and final Community/Pro licensing
still require legal review.

The target graph uses `rustls`/`ring` and has no OpenSSL or native-tls
dependency. A release-like arm64 build completed as a Mach-O arm64 binary
(minimum macOS 11.0; SystemConfiguration/CoreFoundation and libSystem are the
only linked system libraries):

| Artifact | Bytes |
| --- | ---: |
| Evidence binary, unstripped | 5,092,584 |
| Evidence binary, `strip -x` | 3,797,104 |
| Same-profile empty stub, `strip -x` | 365,408 |
| Stripped evidence over empty-stub reference | 3,431,696 |

The size comparison is a spike measurement only; it is not an application
distribution size promise. The temporary size stub was not retained.

## 7. Security and correctness findings

### Positive evidence

- Rustls certificate and hostname validation are enabled; custom roots are
  per-connection and no insecure bypass exists.
- Error output is typed and allowlisted; passwords, URLs, raw server
  diagnostics and row data are excluded from evidence output.
- Driver task ownership and shutdown are explicit; connection loss is observed
  rather than silently retried.
- The exact patched floors cover the current `tokio-postgres`/`postgres-protocol`
  RustSec advisories for malformed `DataRow`, SCRAM iteration and malformed
  `hstore` inputs.

### Blocking or residual findings

1. **No backend frame hard cap.** `tokio-postgres` checks a signed frame header,
   but its `Framed<PostgresCodec>` accumulates a complete backend message before
   the application sees it. A safe full 8 MiB streamed frame therefore exceeds
   the 4 MiB application cap. The 8 MiB probe is intentionally bounded and does
   not attempt an OOM-sized payload.
2. **Unbounded request admission.** Upstream uses an unbounded request channel.
   The future adapter must acquire a bounded semaphore before creating or
   submitting any operation; a response channel of one item does not solve
   request accumulation.
3. **Sensitive upstream logging surface.** Upstream debug paths log query text
   and parameter `Debug` values, and the default connection future logs server
   notices. Production must disable/redact those targets or use a reviewed
   fork; the spike's allowlisted sink does not make upstream logging safe.
4. **Credential copies are not end-to-end zeroized.** The spike-owned password
   copy is cleared on drop, but upstream `Config::password` and SCRAM state make
   additional process-memory copies without a zeroizing drop. This is a
   residual memory-lifetime risk, not evidence of persistence or log leakage.

These findings prevent adoption of the exact stack as-is. They do not prove
that a bounded wrapper/fork or another PostgreSQL implementation is safe; the
same hostile-frame, queue, logging, credential, TLS, cancellation and
transaction matrix must be rerun for any replacement.

## 8. Disposition and re-entry conditions

**Disposition: DEFER `tokio-postgres 0.7.18` + `tokio-postgres-rustls 0.14.0`
as-is.** Do not import the spike into a production target and do not expose a
PostgreSQL capability as adopted on the basis of this report.

Re-entry requires all of:

1. A maintained upstream change, reviewed fork or rigorously tested decrypted
   stream/codec boundary that rejects a backend frame before it can grow past
   the product cap.
2. Bounded request admission with cancellation and a burst/memory regression
   test.
3. A logging policy that cannot emit SQL, parameters or server notices into
   product diagnostics, plus a credential-memory decision approved by Security.
4. A rerun of this exact fixture matrix, dependency/license/advisory review,
   arm64 size measurement and a supported-version policy.

The next bounded spike should compare `sqlx-postgres` and a libpq-based option
against the same protocol/resource/security tests. Switching to native-tls or
the synchronous `postgres` crate alone does not address the two core protocol
and queue findings.

## 9. Not established by this spike

- No Swift/Xcode build, UI runtime, SQL editor, data grid, SSH tunnel,
  Keychain, signing, notarization, updater or distribution behavior.
- No oldest/current PostgreSQL support claim beyond PostgreSQL 17.10 arm64.
- No production connection pool, metadata explorer, CRUD editor or FFI bridge.
- No guarantee that a commit racing with a network loss has a known server
  outcome; the tested policy remains `unknown_lost` until independently
  reconciled.
- No legal approval for the product license or Community/Pro commercial model.

The disposable `spikes/postgres-driver` directory must be removed after this
report and ADR are reviewed; only the durable report, decision record and
targeted planning updates remain.
