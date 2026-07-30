# Risks and Unknowns

Status: Initial planning register

Last updated: 2026-07-29

Scoring: Probability (L/M/H), impact (L/M/H/Critical). Any Critical impact with non-low probability is release-blocking until mitigated or explicitly rejected.

## 1. Risk register

| ID | Risk / uncertainty | Prob. | Impact | Detection strategy | Mitigation | Contingency | Owner role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R-01 | Scope is too large for a coherent first release | H | Critical | M0 capacity review; milestone burn-up; unimplemented acceptance inventory | PostgreSQL vertical slice; hard phase labels; no feature creep; exit gates | Cut/defer M4+ features; ship a safe smaller slice | Product lead |
| R-02 | SQL dialect differences cause unsafe or incorrect generated SQL | H | Critical | Per-dialect parser/snapshot/semantic tests; adapter conformance | Driver-per-adapter; normalized + lossless model; no generic fallback | Mark capability unsupported; require manual SQL | Database core lead |
| R-03 | Database metadata differs or is privilege-limited | H | High | Catalog fixtures, least-privilege integration, introspection drift tests | Lazy scoped metadata; capability `unknown`; engine descriptors | Read-only/limited explorer; user refresh/permission guidance | Adapter lead |
| R-04 | Driver licensing or terms block distribution | M | Critical | License/provenance/SBOM review before dependency lock | Permissive candidates; legal sign-off; replacement notes | Swap driver or defer engine; never ship unapproved client | Legal + dependency owner |
| R-05 | Oracle client licensing/distribution is incompatible | H | High | Legal/vendor review and clean packaging spike | Phase-3 evaluation only; no bundled client assumption | Defer Oracle or require user-installed approved client | Product + legal |
| R-06 | SQL Server authentication on macOS is incomplete | M | High | Azure/AD/Kerberos/auth matrix on supported macOS/driver | M6 spike; explicit auth capability matrix | Support password/TLS subset only or defer engine | SQL Server adapter owner |
| R-07 | SSH implementation mishandles host keys, agents or jump hosts | M | Critical | Adversarial SSH fixture; changed-key/MITM/cancel/tunnel tests; advisory scan | In-process candidate only after audit; strict known-host policy; no shell interpolation | Reject candidate; use vetted alternative or disable SSH | Security + connection owner |
| R-08 | TLS trust or custom CA handling permits MITM | M | Critical | Invalid/expired/wrong-host/custom-CA tests; dependency advisories | Platform-root/cert validation, per-connection CA, fail closed; no global bypass | Block connection and provide remediation; no insecure mode | Security + adapter owner |
| R-09 | Query cancellation is racy or leaves a session unsafe | H | High | Slow-query/interruption/connection-reuse tests per driver | Model requested vs confirmed; poison/close session when required | Tell user outcome unknown; require reconnect/reconcile | Query execution owner |
| R-10 | Large results exhaust memory or freeze UI | M | Critical | 1M/10M row, slow consumer, hostile length, RSS/frame metrics | Pull streaming, byte+row caps, bounded queues/pages, virtualization; driver must cap decrypted backend frames before buffering | Stop fetch/export stream; defer/reject driver when frame cap is unavailable | Performance + core owner |
| R-11 | Editable grid updates the wrong row | M | Critical | Wrong-key/concurrency/zero-multiple affected regression suite | Primary/unique key plan, optimistic predicate, affected-row assertion, read-only fallback | Roll back/disable editing for source; incident workflow | Data editor owner |
| R-12 | Schema diff mistakes rename/drop or dependency order | M | Critical | Synthetic rename/cycle/drift/rollback fixtures; plan review | Confidence-scored rename proposal; preview/dry-run; deterministic dependency graph | Block apply; require explicit manual mapping/SQL | Schema diff owner |
| R-13 | Cross-engine type mapping silently loses data | H | High | Boundary/overflow/timezone/collation/JSON/BLOB fixture comparisons | Explicit mapping table, lossiness warnings, verification and error rows | Stop transfer or require per-column mapping; no silent coercion | Transfer owner |
| R-14 | Backup/restore tools are unavailable or unsafe to package | M | Critical | Signature/license/version/path/cancel/restore validation spike | Adapter-specific official-tool policy; direct argv; secure temp; verify output | Mark native backup unsupported; document user-run workflow | Backup owner + release |
| R-15 | App Sandbox blocks SSH/files/subprocess/backup/automation | H | High | Separate MAS entitlement/helper/file/tool prototype | Direct distribution first; separate channel matrix; feature capability gating | Do not ship affected capability in MAS; no entitlement overreach | macOS/release owner |
| R-16 | Background jobs cannot run across logout/sleep or Keychain lock | H | High | SMAppService lifecycle, logout/sleep/locked-keychain tests | In-app MVP; explicit LaunchAgent consent/status; no guarantee claims | Require app-open execution; report skipped job | Automation owner |
| R-17 | Rust/Swift FFI ownership/cancellation bugs | M | Critical | Sanitizers, ABI mismatch, leak/double-release/panic/concurrency tests | Versioned C ABI, opaque handles, pull/ack chunks, integration gate | Freeze FFI changes; revert to last compatible ABI; disable feature | Core/FFI owner |
| R-18 | UI performance/regressions from SwiftUI/AppKit split | M | High | Instruments, frame/RSS/editor/grid/accessibility budgets | Narrow AppKit bridges, MainActor state, incremental work, spikes | Replace failing component with measured native renderer; defer feature | macOS UI owner |
| R-19 | ER graph layout is slow or unreadable at scale | H | Medium | 500/5,000-table layout/pan/zoom benchmarks and usability tests | Level of detail, incremental/worker layout, manual pinning, hide/filter | Limit visible scope; defer auto-layout/large export | Modeling owner |
| R-20 | Destructive-operation safety is bypassed by parser gap or stale UI | M | Critical | Fuzz classifier, stale digest/target-switch/shortcut/production tests | Core revalidation, typed confirmation, unknown=block, audit | Emergency disable writes/feature flag; incident/reconciliation | Security + query owner |
| R-21 | Supply-chain dependency/update compromise | M | Critical | `cargo audit/deny`, SBOM/provenance, signature/tamper/reproducible checks | Pin/lock, review advisories/licenses, offline release keys, signed updates | Revoke release/key, halt feed, ship verified rollback | Security + release |
| R-22 | Adapter contract becomes lowest-common denominator or leaks driver types | M | High | Architecture review, fake adapters, phase conformance and API diff | Small capability ports; normalized+lossless descriptors; ADR for change | Split port or defer engine; no UI workaround | Principal architect |
| R-23 | Local history/diagnostics leak secrets or sensitive SQL/data | M | High | Seeded canary scans of SQLite/log/crash/export/clipboard/temp; upstream driver log-source review | Redaction schema before sinks, opt-in network, retention/delete controls; disable/redact driver SQL/parameter/notice logs | Purge artifacts, rotate affected credentials, disable diagnostics | Security/privacy owner |
| R-24 | Query parser/grammar dependency license or quality is unsuitable | M | High | Grammar fuzz/coverage, license/maintenance review, malformed SQL corpus | Prototype only; permissive grammar candidates; parser fallback is not safety parser | Use highlighting-only mode and adapter parser; defer advanced completion | Editor/core owner |
| R-25 | Native driver/tool binary size, Apple Silicon or signing breaks release | M | High | Clean arm64 build, size/sign/notarization CI, dependency graph | Candidate review, build matrix, signed nested artifacts, size budget | Remove/defer engine/tool; ship arm64 subset | Release + dependency owner |
| R-26 | Community/Pro split creates unsafe feature gating or licensing uncertainty | M | High | Legal/product review, entitlement and offline-license threat tests | Safety controls common to all tiers; license seam not in DB path | Ship one tier; defer commercial packaging | Product + legal |
| R-27 | Observability/telemetry violates user privacy or regulation | M | High | Payload preview, consent/opt-out network tests, privacy review | Off by default; allowlisted fields; deletion and retention policy | Disable upload; local diagnostics only | Privacy owner |
| R-28 | Automation retries duplicate writes or applies stale targets | M | Critical | Checkpoint/crash/overlap/idempotency/target-drift tests | Immutable job digest; no write retry by default; explicit resume/verification | Stop job, mark unknown, require manual reconciliation | Automation + DB owner |
| R-29 | Security fixes in a candidate dependency are not noticed | M | High | Scheduled advisory/RustSec/GitHub/vendor scans and SBOM diff | Pin patched floor; owner/expiry for exceptions; update playbook | Disable affected capability and release patched build | Dependency owner |
| R-30 | Product identity unintentionally copies a commercial product | L | High | Design/IP review, asset/source/copy provenance checks | Original name/artwork/copy/interaction; no reverse engineering/private API | Remove/rewrite asset/feature; legal review before release | Design + legal |
| R-31 | Test infrastructure accidentally targets production/shared staging | L | Critical | Destructive guard, hostname/schema marker, CI secret scope, audit | Disposable containers/isolated schema and hard abort guards | Revoke credentials/stop run; incident review; quarantine fixture | QA + security |
| R-32 | Future plugin becomes an arbitrary code/secret escape | M | Critical | Plugin threat-model/XPC capability prototype and signature tests | No plugins MVP; signed out-of-process, permissioned, crash-isolated API | Remove plugin support; revoke plugin keys/capabilities | Platform security |
| R-33 | Auto-update verification is bypassed or key is compromised | M | Critical | Feed/artifact tamper, downgrade/replay/channel and key-rotation tests | EdDSA + Apple signature, offline keys, rollback/revocation process | Disable updater/manual verified release, revoke keys | Release security |
| R-34 | Long-term adapter maintenance lags server/database evolution | H | High | Version matrix, upstream release/advisory monitoring, conformance drift | Supported-version policy, adapter owners, capability unknown/deprecation | Freeze engine version/support or retire adapter | Engineering manager |

## 2. Prioritization

Release-blocking before M2: R-01, R-02, R-07, R-08, R-09, R-10, R-11, R-12, R-14, R-17, R-20, R-21, R-28, R-31, R-33. The remaining risks still require an owner and evidence before the milestone where they become relevant.

No risk is silently accepted. An accepted exception records rationale, residual impact, compensating control, named approver, expiry date and trigger for re-review. A risk owner cannot approve their own exception without an independent security/product reviewer.

## 3. Detection and review cadence

- Every PR: changed-scope threat links, dependency/license diff, secret scan, relevant unit/integration/UI tests.
- Nightly: advisories, SBOM/provenance, fuzz corpus, disposable TLS/SSH/database matrix, leak scan and selected soak/performance.
- M0/Milestone exit: risk register review, spike disposition, owner/expiry check, open-unknown list and release-blocker audit.
- Release candidate: signing/update/entitlement/toolchain review, full safety/security suite and clean-machine distribution test.
- Quarterly after launch: supported engine/version, legal/license, privacy, update-key, incident tabletop and dependency owner review.

## 4. Unknowns requiring spikes

1. Exact PostgreSQL/MySQL/MariaDB/SQLite driver versions, licenses, cancellation and TLS behavior.
2. SSH candidate after the 2026 `russh` advisories and fallback comparison.
3. TextKit 2 large-file and dialect parser strategy.
4. `NSTableView` wide/frozen-column virtualization and VoiceOver contract.
5. C ABI chunk encoding/copy overhead and safe cancellation.
6. Direct updater/helper signing and optional App Sandbox feasibility.
7. Official backup tools, licenses, native binaries and cancellation per engine.
8. Keychain accessibility/access groups for future background jobs.
9. Bidirectional diff conflict model and resumable cross-engine transfers.
10. ER layout complexity and export fidelity.

Each spike has a bounded hypothesis, success criteria, disposable artifact and documented decision. A spike is not a production feature.

## 5. Risk acceptance format

```text
Risk ID:
Decision:
Residual probability/impact:
Evidence:
Compensating controls:
Owner:
Independent reviewer:
Accepted until:
Revisit trigger:
```

## 6. Current posture

The repository is planning-only; no implementation risk is being claimed as mitigated by code. The strongest current evidence is the architecture/safety/test plan and primary-source dependency/platform review. The first implementation request must begin by closing M0 risks rather than building broad feature surfaces.
