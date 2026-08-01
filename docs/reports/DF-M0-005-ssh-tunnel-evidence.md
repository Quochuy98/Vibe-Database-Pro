# DF-M0-005 SSH tunnel and host-trust evidence

Status: Evidence and disposal complete; no SSH implementation or dependency
adopted; exact `russh 0.62.4` rejected by the current ADR-0015 disposition

> Historical disposition notice: the conditional `russh 0.62.4` conclusion in
> this evidence record is superseded by
> [ADR-0015](../adr/0015-m0-dependency-disposition.md), which rejects that exact
> source after official advisory
> [`GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg).
> The measurements below
> remain historical spike evidence; they are not current adoption authority.

Evidence date: 2026-07-30

Disposable source revision:
`875dd468221ad1c6c3c35b34a83c0af48ae3f9ad`

Related decisions: [ADR-0012](../adr/0012-m0-ssh-disposition.md) and its
dependency-disposition update,
[ADR-0015](../adr/0015-m0-dependency-disposition.md)

## 1. Decision question and scope

DF-M0-005 asked whether a patched in-process Rust SSH client, macOS system
OpenSSH, or an `ssh2`/libssh2-class client could safely provide DataForge
database tunnels. The gate covered host trust, a declared authentication
subset, independently authenticated jump hops, loopback forwarding, no direct
fallback, bounded hostile input, cancellation, cleanup, secret leakage and
dependency provenance.

The spike did not implement a production connection service. It had no
database driver, database endpoint, Swift/Rust FFI, Keychain item, production
credential, user trust store, connection UI, SQL or database write path. Every
server, key, password, agent socket, trust file and port was generated for one
local disposable run.

TLS is not part of DF-M0-005. The backlog assigns PostgreSQL TLS evidence to
DF-M0-002. Earlier architecture/roadmap wording that combined “SSH/TLS” was a
traceability conflict; the final documentation keeps the two gates separate.

## 2. Disposition

No candidate is adopted for production:

| Candidate | Exact evidence identity | Disposition |
| --- | --- | --- |
| `russh` | `0.62.4`, checksum `b8b67b5a…064f`, `default-features = false`, only `aws-lc-rs` | **Reject exact source by current ADR-0015.** Historical Ed25519/trust measurements remain evidence only; they grant no candidate or adoption status |
| macOS system OpenSSH | Apple `OpenSSH-354.120.2`, `OpenSSH_10.2p1`, macOS 26.5.2 build 25F84 | Reject the tested build and reject native `ProxyJump/-J` |
| `ssh2`/libssh2 | `ssh2 0.9.6`, `libssh2-sys 0.3.2`, vendored fork commit `090f23d…f47a` | Reject before build/runtime because the exact vendored source omits current security fixes |

The `russh` result is not dependency approval. `DP-01` remains external to the
runtime probe, password authentication is unsupported, and signed app,
Keychain/FFI, minimum-hardware, distribution and long-soak evidence is still
missing. Until those re-entry gates pass under a separately reviewed
production design, DataForge must ship without SSH rather than silently fall
back to a direct connection or a weaker trust mode.

## 3. Frozen safety contract

The disposable protocol required:

- fail-closed unknown, changed and revoked host keys;
- independent logical host and port trust for bastion and target;
- no generic accept-all callback and no trust-store mutation during connect;
- no shell interpolation and no untrusted value interpreted as command syntax;
- a transport policy in which a tunnel-required plan cannot see or attempt the
  direct database endpoint;
- loopback-only forwarding, bounded packet/channel/agent/trust inputs and
  monotonic deadlines;
- explicit cleanup of listener, socket, channel, SSH session, process and
  disposable fixture ownership; and
- fake secret absence from argv, logs, JSON, retained fixture files and Git.

The runtime runner had two destructive-test guards, required exact `test`
environment labels, tagged every Docker object with a random ownership marker
and refused to delete a mismatched object. The bastion was exposed only on a
random `127.0.0.1` port. The target existed only on the disposable Docker
network. No Internet SSH server, production/staging system, user agent or
`~/.ssh/known_hosts` was accessed.

## 4. Evidence identity

### 4.1 Source and host

| Item | Value |
| --- | --- |
| Source commit | `875dd468221ad1c6c3c35b34a83c0af48ae3f9ad` |
| Spike Git tree | `88c8419d8082aa48ad9cafe9505c2fe1283ab300` |
| `git archive` SHA-256 | `55dca26075d4907360947fe93f4b4f24a6673559b4fceb52c4e22e0df139b710` |
| `Cargo.lock` SHA-256 | `634d476eca69b75645841611fe88ad6a2620c365477296bcb0f5b6fba19a2514` |
| Developer host | Mac15,3, arm64, 24 GiB, 8 logical CPUs |
| OS | macOS 26.5.2, build 25F84 |
| Rust | `rustc 1.97.1`, `cargo 1.97.1`, `aarch64-apple-darwin` |
| Docker | client/server 28.4.0, API 1.51, arm64 |
| Xcode | Not selected; active developer directory was Command Line Tools |

The host is newer and has more memory than the provisional Apple M1/16 GiB/
macOS 14 minimum. These measurements are developer-host evidence only.

### 4.2 Disposable fixture

The fixture used
`alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b`
and exact package `openssh-server-10.3_p1-r0` for Linux arm64. A clean rebuild
produced image ID
`sha256:2a03bcfbe467eef828c9825d1339ca8cda5f514547aeea80385ef7db4c876767`
at 5,259,626 bytes. The image, containers and network were deleted after each
run.

### 4.3 Release probes

| Binary | Architecture | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `dataforge-russh-probe` | arm64 | 5,912,168 | `377cbaf7e4e93d28fdccdac994b2d2a10f56ae12ff6af7f080f518b793eed1e6` |
| `dataforge-openssh-probe` | arm64 | 530,984 | `1f24f70086e40a958cceb5c755421a4125c089a1e9beaeac4765357df581599b` |
| `/usr/bin/ssh` | x86_64 + arm64e | 1,555,472 | `470f812f6e71ee4ca1b49c79f9c2982c054493e22502d4648bd010feb4b2a9b2` |

The probe sizes are feasibility diagnostics, not projected product deltas.
System OpenSSH adds zero bundled executable bytes if executed in place, but
the app would still need orchestration code and would inherit Apple’s update
schedule and process-integration risks.

## 5. Exact validation commands and results

From `spikes/ssh-tunnel` at the source revision above, the final run executed:

```bash
cargo fmt --all -- --check
RUSTFLAGS='-D warnings' cargo check --workspace --all-targets
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features
cargo build --workspace
cargo audit
cargo deny check
cargo tree -p dataforge-russh-probe -e normal
RUSTFLAGS='-D warnings' cargo build --release --workspace
/usr/bin/strings target/release/dataforge-russh-probe
/usr/bin/lipo -archs target/release/dataforge-russh-probe
DATAFORGE_TEST_ALLOW_DESTRUCTIVE=1 \
  DATAFORGE_TEST_ENVIRONMENT=test \
  ./scripts/run-evidence.sh
```

The evidence runner additionally exercised:

```bash
/usr/bin/leaks --noContent --nostacks --atExit -- \
  target/release/dataforge-russh-probe <ephemeral fake-fixture arguments>
```

| Gate | Result |
| --- | --- |
| Rust format | Pass |
| Warnings-as-errors check | Pass |
| Strict Clippy | Pass |
| Unit tests | Pass: 9 total; 1 OpenSSH + 8 russh; 0 failures |
| `cargo audit` | Pass; 179 locked packages scanned against the fetched RustSec database |
| `cargo deny check` | Advisories, bans, licenses and sources all pass |
| Post-run official repository advisory | **Block exact 0.62.4:** `GHSA-m65r-rprj-r5rg` declares `<=0.62.4` affected and reports `0.62.5` patched; current ADR-0015 rejects the tested source |
| Minimal russh graph | Pass; neither `rsa` nor `flate2` is present |
| Release sensitive-format scan | Pass for targeted upstream Debug/Trace strings; the debug binary supplied a positive scanner control |
| arm64 release build | Pass |
| Candidate rows | 12 pass, 0 fail, 7 explicitly unsupported; `complete_matrix_passed=false` |
| Secret canary and sensitive-pattern scan | Pass across artifacts, transient logs and one end-of-run process-table snapshot |
| Outer runner completion | Atomic marker written only after canary scan and cleanup passed |
| Cleanup | Pass; no owned container, network, image, agent or temporary directory retained |
| Leak smoke | Exit 0; zero leaked nodes/bytes reported for one additional complete runtime-matrix process |

The current upstream russh GitHub advisory list was reviewed separately because
RustSec did not expose all repository advisories through the scanner data path.
The 2026-08-01 post-run correction records the exact official advisory in the
machine-readable manifest without changing historical measurements. Therefore
a clean `cargo audit` is necessary but not sufficient evidence.
The exact tools were `cargo-audit 0.22.2`, `cargo-deny 0.20.2`, RustSec DB
commit `7c7ccac53056b87f69ac677f15ea2d9a98a6f8e2`, and Apple `leaks` project
`SamplingTools-64575.39.1`.

## 6. `russh 0.62.4` runtime evidence

### 6.1 Deliberately narrow build

The exact crate is pinned to `=0.62.4` with `default-features = false` and only
`aws-lc-rs`. The normal graph has 131 third-party package/version pairs; the
whole lock contains 179 packages. Compression and RSA are absent. Host keys
are restricted to Ed25519 by the probe. This avoids the unpatched RustCrypto
RSA advisory in the default graph and avoids compression until a tunnel need
justifies it.

This graph is not small: AWS-LC, cryptographic primitives, Tokio and SSH key
parsing remain transitive dependencies. The technical license scan found only
allowlisted permissive paths for this exact graph, but final notices, legal
review and release SBOM remain mandatory.

### 6.2 Host trust

The probe took one bounded trust-store snapshot before connection: at most
64 KiB, 256 lines and 4 KiB per line. Its callback held parsed keys and never
read or wrote a file. It accepted exact and OpenSSH `|1|` hashed host/port
identities, classified matching `@revoked` entries and rejected wildcard,
negation and `@cert-authority` syntax instead of partially emulating it.

| ID | Result | Final-run evidence |
| --- | --- | --- |
| TR-01 exact known host | Pass | Correct Ed25519 key matched and authentication continued; 32 ms |
| TR-02 unknown host | Pass | Typed unknown result, SHA-256 fingerprint observation, trust file unchanged; 12 ms |
| TR-03 changed host | Pass | Typed changed result and trust file unchanged; 13 ms |
| TR-04 hashed host | Pass | Scoped OpenSSH hashed identity matched; 40 ms |
| TR-05 revoked host | Pass | Typed revoked result, fail closed, trust file unchanged; 10 ms |

TR-03 changes the fixture key before a new handshake. It is not a malicious
mid-session rekey test. Rekey-specific hostile-server coverage remains a
production re-entry gate.

### 6.3 Authentication subset

| ID / mode | Result | Evidence and limit |
| --- | --- | --- |
| AU-01 local Ed25519 key | Pass for exercised mode path | Source wrapper uses `O_NOFOLLOW`, same-descriptor metadata/read, regular-file/current-owner/permission and 64 KiB checks; `0600` succeeds and `0644` rejects before auth; separate symlink/wrong-owner/oversize negatives were not run |
| AU-02 password | Unsupported | No password entered the candidate; upstream retains an ordinary `String` in session auth state and has sensitive Debug formatting paths |
| AU-03 agent | Partial; frozen row unsupported | Ephemeral agent authentication and oversized-frame rejection completed in 30 ms; a 256 KiB+1 frame rejects, while missing, malformed, stalled, socket-identity and failure-cleanup cases were not run |

The private-key input buffer owned by the probe uses zeroizing storage, but the
decoded upstream key object and future Keychain/FFI copies do not yet have an
end-to-end lifetime proof. The agent test does not establish Finder launch,
App Sandbox, user-agent socket owner/mode validation or malicious signing
semantics. Keyboard-interactive, FIDO/security-key, RSA, SSH certificates and
password MFA are not supported by this disposition.

### 6.4 Jump host, forwarding and no fallback

The positive path explicitly composed two typed sessions: connect and
authenticate the bastion, open `direct-tcpip` to the target, then connect and
authenticate the target over that channel. No `ProxyJump` or shell command was
used.

| ID | Result | Final-run evidence |
| --- | --- | --- |
| JP-01 per-hop trust | Pass | Both hops authenticate; independent bastion and target mismatches each reject; 113 ms |
| JP-02 no direct fallback | Model smoke; frozen row unsupported | Tunnel-required model records one jump branch and zero direct branches; no connector trap or network observation ran |
| TN-01 forwarding | Banner smoke; frozen row unsupported | `direct-tcpip` reaches a bounded SSH banner, but no local listener or echo round trip was exercised |
| TN-02 active cancellation | Narrow pass | One active single-hop forward closes its listener; cleanup reported 0 ms at millisecond resolution, within 2,000 ms; scenario 39 ms total |
| TN-03 failure cleanup | Partial; frozen row unsupported | Refused destination port cleanup passes; comprehensive auth/trust/jump failure and post-cleanup resource counts were not run |

JP-02 is a deterministic transport-plan model, not a completed frozen gate or
packet capture from a real database adapter. Production must preserve the stronger architecture: the
adapter receives only a loopback tunnel lease and never receives the remote
database endpoint when SSH is required. A socket trap and packet-level zero-
attempt assertion remain mandatory before capability enablement.

### 6.5 Hostile input and lifecycle

The client rejected a 4 KiB banner line, a packet length of `u32::MAX`, and a
partial banner stalled for the bounded 501 ms case. Final-run RSS deltas were
48, 0 and 0 KiB respectively, each below the 16 MiB spike ceiling. These are
targeted cases, not the complete frozen hostile-input/resource gate, fuzzing
or proof against every protocol state.

Twenty-five direct key-auth connect/close cycles completed in 839 ms with
file-descriptor delta 0 and endpoint RSS delta -288 KiB. A separate
`leaks --atExit` process ran one additional complete probe scenario set and
reported 0 leaks for 0 total leaked bytes in that process snapshot. These
results are a short lifecycle/leak smoke only. They do not establish leak-free
or long-term bounded behavior, repeat forward/cancel/jump/failure cycles, replace
explicit task/process/socket/channel counts, or satisfy a 1,000-cycle run or
eight-hour soak.

### 6.6 Logging and secret surface

The candidate process marks SC-01 unsupported because it cannot validate its
own outer logs, process snapshot or cleanup. The runner initialized no logger,
performed the external canary scan, completed cleanup and only then atomically
wrote `runner-completion.txt`. The release graph enables
`log/release_max_level_info`, and the test fails if targeted upstream strings
for authentication payload or plaintext encrypted-packet formatting survive
in the release probe. A random fake password/canary prefix, private-key
headers, password assignments and agent-socket assignments were scanned across
retained artifacts and transient logs; the random password was also checked
against one end-of-run process-table snapshot. No match was retained. This
does not prove that a transient argv value could never have existed earlier.

This compile-out profile is a candidate constraint, not a general redaction
solution. A production release must prove every final binary uses the same or
stronger compile-time ceiling and must keep application structured logging
redacted before serialization.

## 7. Static candidate gates

### 7.1 macOS system OpenSSH

The local system binary reported `OpenSSH_10.2p1, LibreSSL 3.3.6` and project
`OpenSSH-354.120.2`. `codesign --verify --strict` established an on-disk valid
signature, but the probe did not evaluate an Apple anchor requirement. Static
source comparison and current OpenSSH release notes show that this build
predates the OpenSSH 10.4 client fix for `CVE-2026-60002`, a use-after-free
reachable when a server changes host key during rekey. The probe did not run a
malicious network test against a client with evidence of an unpatched
memory-safety issue.

The same source shows native `ProxyJump/-J` constructs an implicit
`ProxyCommand` and executes it through the user’s shell. Parse-only local
tests accepted a metacharacter-bearing jump value on this 10.2 build. OpenSSH
10.3 added command-line `-J` validation, but config-file `ProxyJump` still does
not satisfy DataForge’s no-shell invariant. Native `-J` is therefore rejected,
not retained as a fallback.

System OpenSSH also exposes localized stderr rather than a structured host-
trust callback, cannot dynamically allocate a local forward port using
`-L ...:0:...` on the tested build, and delegates security updates to Apple.
Re-entry requires Apple build/backport evidence equivalent to the current
upstream security floor plus a separately proven no-shell, per-hop, typed
process lifecycle. A version string alone is insufficient because Apple may
backport without changing it.

### 7.2 `ssh2 0.9.6` / `libssh2-sys 0.3.2`

The exact crates.io checksums are recorded in the raw candidate artifact.
`libssh2-sys 0.3.2` vendors `Manishearth/libssh2` commit
`090f23d1852a0b62e081bd12c4d05adc1c4af47a`, reported as `1.11.1_DEV`.
That fork includes backports for CVE-2025-15661, CVE-2026-55199 and
CVE-2026-55200, but it predates or omits the fixes for CVE-2026-7598 and
CVE-2026-66032 through CVE-2026-66035. The latter set includes pre-auth
memory-safety failures relevant to a malicious SSH server.

The exact candidate was rejected before build/runtime. Its binary-size delta
is therefore deliberately recorded as unavailable, not zero. Even after an
upstream security refresh it would need explicit host-trust enforcement, a
reviewed nonblocking pump, bounded cancellation and multi-hop/session/socket
ownership around a synchronous C API. DataForge will not create an internal
security fork simply to keep this option eligible.

## 8. Acceptance mapping

| Frozen requirement | Disposition |
| --- | --- |
| TR-01…TR-05 | Met for exact russh Ed25519 bounded trust subset |
| AU-01 private key | Met in fake local-file wrapper; Keychain/FFI lifetime not established |
| AU-02 password | Explicitly unsupported |
| AU-03 agent | Not met; success and oversized-frame smoke only |
| JP-01 independent hop trust | Met for explicit russh typed composition |
| JP-02 zero direct fallback | Not met; deterministic branch model only, no connector/network trap |
| TN-01 forwarding | Not met; bounded destination banner only, no local-listener echo round trip |
| TN-02 cancellation | Partial; one active single-hop happy-path cancellation under 2 seconds |
| TN-03 failure cleanup | Not met; destination failure only, not the complete failure/resource matrix |
| MI-01…MI-03 | Partial targeted smoke; three inputs rejected, but the frozen hostile-input/resource gate is not fully met |
| SC-01 secret surface | Candidate row unsupported; outer runner canary scan and atomic completion marker pass |
| LC-01 lifecycle | Partial smoke; 25 direct connect/close cycles and one process snapshot do not meet the frozen lifecycle/leak gate |
| DP-01 dependency adoption | Not met; current ADR-0015 rejects exact russh 0.62.4 and the other tested candidates remain rejected |
| Candidate adoption | Not met; production SSH remains disabled |
| Spike disposal | Met; source removed in separate disposal commit `0b80f7e155391a5e7d072bc944623d55fceed24b` |

The definition of done permits an explicit reject/defer disposition. It does
not permit weakening host trust or silently enabling a candidate that failed
the dependency/adoption gate.

## 9. Production re-entry criteria

Before an SSH capability can enter implementation review, all of the following
must be true for a newly pinned exact candidate:

1. Re-run upstream GitHub, RustSec and transitive advisory checks; keep RSA and
   compression absent unless a reviewed need and test matrix adds them.
2. Preserve Ed25519 fail-closed host trust and explicit per-hop composition;
   add rekey-host-change, multiple-key/algorithm, malformed trust-store and
   actual network no-direct-fallback tests.
3. Define the supported authentication subset. Keep password and keyboard-
   interactive disabled unless upstream secret retention/logging is fixed and
   Keychain-to-FFI lifetime/canary tests pass.
4. Validate agent socket identity/owner/mode, malicious signing responses,
   Finder launch and any App Sandbox channel that claims support.
5. Own and await every connection task, channel and hop; test cancellation at
   DNS, TCP, trust, auth, channel-open, forward and teardown states.
6. Prove release compile-time logging limits, structured redaction and absence
   of tunneled data/credentials in logs, crash reports and diagnostics.
7. Run signed/notarized Developer ID app integration, Hardened Runtime,
   minimum M1/16 GiB/macOS 14 evidence, a 1,000-cycle process/FD/socket test
   and an eight-hour soak.
8. Complete legal notices, SBOM, maintenance owner, advisory response SLA and
   replacement plan. A future crate version is not approved by semver alone.

Any trust bypass, secret exposure, shell execution, unmanaged task/process,
direct database attempt or current unpatched advisory closes the gate.

## 10. Not established

- No real database connection, driver handshake, query, transaction, write,
  rollback or production retry path was exercised.
- No Swift/Rust FFI, Keychain lease, app UI, connection pool or application
  service was built.
- No signed/notarized app, Hardened Runtime, App Sandbox, MAS, Finder launch,
  helper or distribution artifact was tested.
- No malicious mid-session rekey server, fuzz campaign, 1,000-cycle run,
  eight-hour soak, crash/SIGKILL recovery or minimum-hardware matrix was run.
- No password, keyboard-interactive, certificate host key, wildcard/negation
  trust, FIDO, RSA or compression capability is approved.
- The key wrapper did not run separate symlink, wrong-owner, encrypted-key,
  wrong-passphrase or oversize negative fixtures despite enforcing several of
  those checks in source.
- The libssh2 candidate was intentionally not built or contacted after failing
  the static current-advisory gate.
- TLS remains outside this report.

## 11. Disposal

The exact disposable source is retained in Git history at
`875dd468221ad1c6c3c35b34a83c0af48ae3f9ad`; its spike tree is
`88c8419d8082aa48ad9cafe9505c2fe1283ab300`. Report, ADR and raw evidence were
recorded in commit `11ea2c100aa212831b5e3c02659d5b25e97156d9`; the whole
`spikes/ssh-tunnel` directory was then deleted in the separate disposal commit
`0b80f7e155391a5e7d072bc944623d55fceed24b`. Future production code must be
designed under the reviewed Connections/security boundaries and must not
promote this probe wholesale.

## 12. Durable raw evidence

The sanitized evidence directory contains no credential, key body, agent
message, connection string, environment dump, personal path or customer data.

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`evidence-manifest.json`](data/DF-M0-005/evidence-manifest.json) | Source, host, toolchain, fixture, binary and validation identity | Manifest intentionally does not self-hash |
| [`russh-runtime.json`](data/DF-M0-005/russh-runtime.json) | Complete 19-row record with explicit incomplete-gate semantics | `253197545b2f018d13b7d4c69d79890a51f047b354da362f9ea76ca80cbdd92f` |
| [`openssh-static.json`](data/DF-M0-005/openssh-static.json) | Tested local build observations plus labeled source-review conclusions | `5212931b975e7c1288625433b71b3e59371a405163e20b2435f8cbe5bfcb9978` |
| [`libssh2-static.json`](data/DF-M0-005/libssh2-static.json) | Exact crates/fork and missing-fix rejection | `b82601a5a9458b17e4bb42cf881c65538c14b293809b319ebce21a2756a6b7e7` |
| [`russh-advisory-snapshot.json`](data/DF-M0-005/russh-advisory-snapshot.json) | Evidence-date upstream advisory floors, preserved before the later blocking GHSA appeared | `32bb0f19114e619d049da87ebdda1a267511afe6b1025d3e4576128f6e408472` |
| [`build-metrics.txt`](data/DF-M0-005/build-metrics.txt) | arm64 and logical-byte metrics | `5a219b57969fb745a27b60dc5b49d9ba34f089d5b979edd8aef5ec32fd65658d` |
| [`leak-smoke.txt`](data/DF-M0-005/leak-smoke.txt) | Short `leaks --atExit` summary and scope warning | `6db09a6f127f60c870b63fa061c601edb09583f3b3e73806c81aa9bb3eb9c337` |
| [`runner-completion.txt`](data/DF-M0-005/runner-completion.txt) | Atomic outer canary-scan/cleanup completion marker | `43a7b8c7a13afdbfbe7619bfe58de663d9d35240f92031614abf9d6449de97e0` |

## 13. Primary references

- [`russh 0.62.4` release](https://github.com/Eugeny/russh/releases/tag/v0.62.4)
- [`GHSA-m65r-rprj-r5rg`](https://github.com/Eugeny/russh/security/advisories/GHSA-m65r-rprj-r5rg)
- [russh upstream security advisories](https://github.com/Eugeny/russh/security/advisories)
- [russh exact source tag](https://github.com/Eugeny/russh/tree/v0.62.4)
- [Apple OpenSSH `OpenSSH-354.120.2` source](https://github.com/apple-oss-distributions/OpenSSH/tree/OpenSSH-354.120.2)
- [OpenSSH 10.3/10.4 release notes](https://www.openssh.org/releasenotes.html)
- [OpenSSH client rekey fix](https://github.com/openssh/openssh-portable/commit/e8bdfb151a356d0171fea4194dd205fbb252be23)
- [`ssh2-rs` 0.9.6 source](https://github.com/rust-lang/ssh2-rs/tree/0.9.6)
- [Exact vendored libssh2 fork commit](https://github.com/Manishearth/libssh2/tree/090f23d1852a0b62e081bd12c4d05adc1c4af47a)
- [libssh2 upstream release](https://github.com/libssh2/libssh2/releases/tag/libssh2-1.11.1)
- [CVE Program API records](https://cveawg.mitre.org/api/cve/CVE-2026-66035)
