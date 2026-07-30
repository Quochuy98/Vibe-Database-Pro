# ADR-0012 — Defer SSH capability after the M0 tunnel and host-trust spike

- **Status:** Accepted as a spike disposition; no candidate adopted;
  production SSH disabled
- **Date:** 2026-07-30
- **Supersedes:** None; refines the SSH candidate in the architecture plan
- **Related:** DF-M0-005, R-07, R-15, R-29

## Context

DataForge needs SSH tunnels that authenticate every hop, do not expose
credentials, never interpret connection fields as shell syntax, never bypass a
required tunnel and terminate every owned resource after failure or
cancellation. DF-M0-005 compared exact `russh`, macOS system OpenSSH and
`ssh2`/libssh2-class candidates with disposable local fixtures and fake
credentials.

The durable command, result, limitation and candidate-dossier record is
[`DF-M0-005-ssh-tunnel-evidence.md`](../reports/DF-M0-005-ssh-tunnel-evidence.md).
The final disposable source is commit
`875dd468221ad1c6c3c35b34a83c0af48ae3f9ad`, spike tree
`88c8419d8082aa48ad9cafe9505c2fe1283ab300`.

Earlier `ROADMAP.md` and `ARCHITECTURE.md` wording grouped “SSH/TLS”. That
conflicts with the backlog: DF-M0-002 owns PostgreSQL TLS and DF-M0-005 owns
SSH tunnel/host trust. This decision does not reopen or replace the TLS
disposition.

## Findings

### `russh 0.62.4`

An exact minimal `russh 0.62.4` graph with only `aws-lc-rs` and no RSA or
compression produced useful but incomplete evidence:

- bounded exact/hashed Ed25519 trust distinguished known, unknown, changed and
  revoked hosts without mutating the trust store;
- bastion and target sessions were explicitly composed and authenticated with
  independent trust;
- fake `0600` Ed25519 key auth, partial agent evidence, bounded hostile banner/
  packet/partial-peer smokes, one active-forward cancellation and 25 direct
  connect/close cycles completed on the developer host;
- the outer runner passed its fake-secret scan, cleanup and one short
  `leaks --atExit` smoke; and
- Rust format, warnings, Clippy, nine unit tests, RustSec lock scan, license/
  source policy, arm64 release build and a targeted release-string scan passed.

The candidate matrix is explicitly incomplete: 12 rows passed, seven are
unsupported and `complete_matrix_passed` is false. Password is disabled;
agent failure/socket cases, a connector-level no-direct trap, local-listener
echo, comprehensive failure cleanup, malicious rekey, Keychain/FFI,
distribution, minimum-hardware and long-soak evidence are absent. Upstream
password auth retains an ordinary `String` in session state and the crate has
sensitive Debug/Trace formatting paths, so the spike compiles Debug/Trace out
of release rather than claiming sink redaction is sufficient.

### macOS system OpenSSH

The tested macOS 26.5.2 binary is Apple project `OpenSSH-354.120.2`, upstream
version 10.2p1. Source review shows it predates the OpenSSH 10.4 client rekey
fix represented by `CVE-2026-60002`. Native `ProxyJump/-J` constructs a
`ProxyCommand` executed through the user’s shell, and the local 10.2 parser
accepted a metacharacter-bearing jump value. A valid on-disk code signature
was observed, but the probe did not evaluate an Apple anchor requirement.

The tested system client and native `ProxyJump/-J` are rejected. Apple owns
the update schedule, so a version string alone cannot prove a backport.

### `ssh2 0.9.6` / `libssh2-sys 0.3.2`

The exact sys crate vendors fork commit
`090f23d1852a0b62e081bd12c4d05adc1c4af47a`. It includes several June
security backports but omits current fixes including CVE-2026-7598 and
CVE-2026-66032 through CVE-2026-66035. Some omitted fixes cover
pre-authentication memory safety against a malicious server. The candidate was
rejected before build/runtime; DataForge will not own an internal security
fork to make it eligible.

## Decision

**Do not adopt or enable an SSH implementation.**

Retain exact `russh 0.62.4` only as a conditional planning candidate around
the positive Ed25519 trust/key and typed multi-hop mechanics. This is not a
dependency approval, supported auth subset or authorization to copy spike code
into a production target.

Reject the tested system OpenSSH build and native `ProxyJump/-J`. Reject the
exact `ssh2`/libssh2 candidate. If no future candidate satisfies every current
gate, DataForge ships direct TLS connections without SSH rather than using
permissive trust, a shell bridge or silent direct fallback.

Any future tunnel-required architecture must enforce:

```text
Connection application service
        ↓
typed SSH transport policy and per-hop trust
        ↓
TunnelLease(127.0.0.1, owned port, cancellation handle)
        ↓
database adapter
```

The database adapter must never receive the remote database endpoint when the
policy requires SSH. Tunnel death invalidates the lease and any associated
pool; it cannot trigger a direct reconnect.

## Re-entry criteria

An exact new candidate may be reconsidered only after all of these pass:

1. Current upstream, RustSec, transitive, source, license/notices, maintenance,
   arm64, size, SBOM and replacement review.
2. Fail-closed per-hop Ed25519 trust, rekey-host-change and malformed/bounded
   trust-store cases with no generic insecure mode.
3. A declared auth subset with Keychain/FFI secret-lifetime tests. Password and
   keyboard-interactive remain off until upstream retention/logging is fixed.
4. Agent socket identity/owner/mode plus missing, malformed, stalled,
   oversized and malicious-agent tests.
5. Real loopback-listener echo, connector/socket trap proving zero direct
   attempts and a database adapter that only sees the tunnel lease.
6. Cancellation/failure tests at every phase with explicit nested-task,
   channel, socket, listener, child/process and hop counts after cleanup.
7. Final release logging compile-out/redaction proof, signed/notarized app,
   Hardened Runtime, Finder launch and any claimed App Sandbox channel.
8. Apple M1/16 GiB/macOS 14 measurements, 1,000-cycle lifecycle test and an
   eight-hour soak. A short leak snapshot cannot substitute for these.

A known unpatched advisory, trust bypass, secret exposure, shell execution,
unmanaged resource or direct endpoint attempt closes the gate immediately.

## Consequences and residual risk

- SSH is not a prerequisite for a direct PostgreSQL/TLS vertical slice. UI and
  capability matrices must hide or disable SSH until a later ADR enables it.
- Positive trust and multi-hop findings can inform future conformance tests,
  but incomplete rows cannot be relabelled as passes.
- System components require an OS/project-build advisory gate in addition to
  Cargo/SBOM review.
- Final AWS-LC notices, legal approval, password/commercial auth scope and
  distribution feasibility remain open.
- No database write, retry, transaction, rollback or credential-storage safety
  was established by this spike.

## Disposal

The report and sanitized raw evidence were committed before the whole
`spikes/ssh-tunnel` directory was deleted in separate disposal commit
`0b80f7e155391a5e7d072bc944623d55fceed24b`. Production implementation must
be rebuilt under the reviewed Connections, KeychainSecurity and DatabaseCore
boundaries; the disposable probe is not promoted wholesale.
