# DF-M0-002 — PostgreSQL driver/TLS/cancellation spike

Status: disposable feasibility spike complete; disposition is **DEFER**; not production code

## Hypothesis

The exact `tokio-postgres` candidate can provide typed row streaming, verified
TLS/custom CA/client certificates, explicit cancellation outcomes and
transaction semantics. The spike also tests whether the candidate enforces the
application's memory and queue safety contract. It does not: a streamed backend
frame can exceed the application cap before admission, and the request queue is
unbounded. The candidate is therefore deferred pending a maintained hard-cap
strategy, bounded admission and a logging/credential-memory review.

## Scope

Included:

- PostgreSQL 17.10 in an arm64 disposable Docker container pinned by digest;
- exact Rust dependency lockfile and dependency/license/advisory evidence;
- custom CA, hostname validation and mutual-TLS cases;
- typed one-million-row `RowStream` consumption with row/byte chunk caps;
- cancellation races and post-cancel session checks;
- commit, failure, explicit rollback and lost-connection transaction evidence;
- malformed PostgreSQL wire-frame probes, redacted errors and no secret output;
- fail-closed destructive-test guards and cleanup on every exit path.

Excluded:

- a production adapter, domain port, FFI contract or macOS UI;
- SSH, pooling, metadata browsing, editing and non-PostgreSQL engines;
- supported-version claims beyond the exact disposable fixture.

The prototype must be deleted after its durable disposition report is reviewed.

## Reproduce

The destructive guard is fail-closed and must be supplied explicitly:

```sh
DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1 \
DATAFORGE_TEST_ENVIRONMENT=test \
  ./scripts/test.sh
```

The runner creates only a fake-credential PostgreSQL 17.10 arm64 container,
binds it to `127.0.0.1`, and removes the container, network, volume,
certificates and logs on success, failure, cancellation or signal. It rejects
all non-test/non-loopback targets before any fixture setup.

The durable results and exact dependency disposition are recorded in
[`docs/reports/DF-M0-002-postgres-driver-evidence.md`](../../docs/reports/DF-M0-002-postgres-driver-evidence.md)
and [`ADR-0009`](../../docs/adr/0009-m0-postgres-driver-disposition.md).
