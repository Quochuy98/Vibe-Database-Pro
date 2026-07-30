# DF-M0-005 disposable SSH tunnel and host-trust spike

This standalone spike tests one planning hypothesis: an SSH candidate can
provide database tunnels on macOS while authenticating every hop, containing
untrusted protocol input, accepting short-lived fake credentials without
logging them, and cleaning up deterministically after failure or cancellation.

It is not a product module. It has no database driver, database credential,
Swift/Rust FFI, production connection UI, production Keychain item, SQL, or
database write path. All servers, keys, agent sockets, passwords, echo
services, known-host stores, and ports are ephemeral local test fixtures.

## Candidates

The frozen comparison covers:

1. patched `russh`, pinned at or above every advisory floor current on the
   evidence date;
2. the macOS system OpenSSH client, invoked through direct argument vectors and
   never through a shell;
3. the Rust `ssh2` binding over a pinned libssh2-class implementation.

Passing one candidate does not approve a dependency. The final adoption gate
also requires current primary-source license, maintenance, advisory,
transitive, Apple Silicon, binary-size, replacement, and distribution review.

## Security invariants

- The default trust outcome for an unknown key is rejection plus a typed,
  non-secret observation suitable for a later explicit trust decision.
- A changed or revoked key fails closed. There is no generic "accept all"
  callback and no global insecure mode.
- Bastion and target identities are scoped independently by logical host and
  port. Trust from one hop is never reused for another.
- Tunnel or jump failure never attempts the database endpoint directly.
- SSH processes are launched with explicit executable paths and argument
  arrays. No user-controlled value becomes shell syntax.
- Passwords are read from a protected input channel only for the scenario that
  needs them. They never appear in argv, JSON evidence, logs, fixtures in Git,
  snapshots, or environment dumps.
- Private keys are generated per run in an owner-only temporary directory.
  The probe must reject an overly permissive key before handing it to a client.
- Agent frames, SSH banners, packets, channel queues, captured output, retries,
  tasks, and deadlines are bounded.
- Cancellation closes listeners, accepted sockets, channels, SSH sessions,
  child processes, and jump-hop resources before reporting terminal state.

## Frozen evidence matrix

| ID | Scenario | Required evidence |
| --- | --- | --- |
| `TR-01` | Exact known host | Modern Ed25519 host key matches the scoped entry and key authentication succeeds. |
| `TR-02` | Unknown host | Connection is rejected; no trust file is mutated; a SHA-256 fingerprint observation is returned without key material. |
| `TR-03` | Changed host | Same logical host/port with a different key is rejected as mismatch, not offered as a routine first-use prompt. |
| `TR-04` | Hashed known host | A scoped OpenSSH hashed-host entry matches, or the mode is explicitly unsupported and rejected. |
| `TR-05` | Revoked host | A revoked entry is rejected; any inability to distinguish revoked from unknown is recorded. |
| `AU-01` | Private key | Fake Ed25519 key succeeds at mode `0600`; mode `0644` is rejected before authentication. |
| `AU-02` | Password | Fake password succeeds only when it can be supplied without argv/log persistence; otherwise the candidate records unsupported. |
| `AU-03` | Agent | Ephemeral `ssh-agent` authentication succeeds; absent/malformed/oversized agent responses fail within deadline and memory bounds. |
| `JP-01` | Jump host | Bastion and target are independently authenticated; a target mismatch and a bastion mismatch each fail closed. |
| `JP-02` | No direct fallback | A deterministic connector/trap proves tunnel failure produces zero direct endpoint attempts. |
| `TN-01` | Forwarding | A loopback-only local forward performs a bounded echo round trip through the intended hop chain. |
| `TN-02` | Cancellation | Cancellation during an active forward reaches terminal state in at most two seconds and closes the listener and all owned resources. |
| `TN-03` | Failure cleanup | Auth, trust, destination, and jump failures leave no listener, accepted socket, child process, or live session owned by the probe. |
| `MI-01` | Oversized banner | A server banner beyond the protocol/product limit is rejected within the deadline and memory ceiling. |
| `MI-02` | Malicious packet length | An advertised oversized packet is rejected without allocating from the untrusted length. |
| `MI-03` | Slow/partial peer | A stalled banner/handshake is cancelled or times out without an unmanaged task. |
| `SC-01` | Secret leakage | The seeded fake secret is absent from stdout, stderr, JSON, process arguments, retained fixture files, and committed artifacts. |
| `LC-01` | Repetition/leak | Repeated connect/forward/cancel cycles have bounded file descriptors, tasks/processes, and resident footprint; leak-tool limitations are explicit. |
| `DP-01` | Dependency gate | Exact versions/checksums, licenses, advisories, features, transitives, source, maintenance, arm64 slices, binary-size delta, and fallback cost are recorded. |

## Measurement contract

- The minimum host is the repository's provisional M1/16 GiB/macOS 14 floor.
  Developer-host results on different hardware or macOS versions are labeled
  as such and do not establish the minimum-machine gate.
- Each network scenario has a monotonic deadline. `TN-02` uses a two-second
  cleanup ceiling; ordinary local handshake samples use a five-second ceiling.
- Malicious-input cases record wall time, process physical-footprint delta, and
  maximum captured output. A crash, panic, hang, unbounded allocation, or
  secret-bearing diagnostic is a failure.
- The evidence runner emits aggregate status, typed category, elapsed time,
  bounded-resource counters, and sanitized tool versions. It never emits raw
  credentials, private/public key bodies, agent messages, connection strings,
  environment variables, or absolute personal paths.
- Container/image digests and toolchain versions are captured. No production,
  staging, shared server, Internet SSH endpoint, or real user known-host store
  is contacted or modified.
- Capability claims are candidate-and-version specific. A system OpenSSH pass
  does not prove the in-process candidates, and a library pass does not prove
  a future Swift/Rust or Keychain integration.

## Expected commands

The checked-in runner will execute the applicable equivalents of:

```bash
cargo fmt --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo audit
cargo deny check
./scripts/run-evidence.sh
```

It will also inspect dependency trees/licenses, build separate release probes,
verify arm64 slices and binary sizes, scan artifacts for a generated canary,
exercise `/usr/bin/leaks` or document why a candidate process cannot be
inspected reliably, and verify fixture cleanup.

## Decision rule

A planning candidate may be selected only if `TR-01` through `TR-05`, its
declared auth subset, `JP-01`, `JP-02`, `TN-01` through `TN-03`, `MI-01`
through `MI-03`, `SC-01`, `LC-01`, and `DP-01` pass with no Critical open
trust, credential, cancellation, or supply-chain issue. A mode may remain
unsupported; it may not silently degrade to direct transport or permissive
trust. If no candidate meets that gate, SSH remains disabled for production
planning until a replacement is evaluated.

## Disposal

After exact commands, raw sanitized samples, limitations, and disposition are
recorded in `docs/reports/DF-M0-005-ssh-tunnel-evidence.md` and a new ADR, this
entire directory is deleted in a separate disposal commit. Production code
must be designed later from the reviewed contracts; spike code is not copied
into a product target.
