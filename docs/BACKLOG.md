# Technical Backlog

Status: Production backlog remains planning-only; DF-M0-001 through DF-M0-009
have durable spike/assurance/design evidence; DF-M0-008/009 external reviews
remain open and no production item is implemented

Last updated: 2026-08-01

Priorities: P0 safety/architecture blocker, P1 milestone-critical, P2 important, P3 later. Complexity: S/M/L/XL. Each item is independently reviewable; any scope discovered to be larger must be split before implementation.

## Milestone 0 — Discovery and architecture

### DF-M0-001

**ID:** DF-M0-001

**Title:** Prove versioned C ABI bounded streaming and cancellation

**Epic:** Swift/Rust bridge spike

**Priority:** P0

**Complexity:** M

**Dependencies:** ADR-0002, ADR-0003, performance/test plans

**User story:** As an architecture team, we need evidence that Swift can consume a Rust stream safely before building database features.

**Description:** Build a disposable fake Rust producer and Swift consumer using opaque handles, ABI handshake, row/byte chunk caps, pull/ack, terminal status and cancel.

**Technical notes:** No driver, network, credential or production module; catch panic at every export; record copies/RSS/latency.

**Security considerations:** Malformed lengths, stale/double-released handles, panic, allocation failure and secret-like canary must produce controlled errors.

**Acceptance criteria:** 1M generated typed rows remain within budget; slow consumer backpressures; ABI mismatch rejects; cancel at each state terminates without post-terminal callbacks/leaks.

**Tests required:** Swift/Rust integration, sanitizers where supported, ownership/concurrency/panic/cancel/property and performance tests.

**Out of scope:** Real database, permanent production API, UI beyond a test harness.

**Definition of done:** Spike code deleted/replaced; report contains commands, measurements, failures, contract recommendation and ADR confirmation/change.

### DF-M0-002

**ID:** DF-M0-002

**Title:** Evaluate PostgreSQL driver, TLS, stream, transaction and cancellation

**Epic:** PostgreSQL adapter spike

**Priority:** P0

**Complexity:** M

**Dependencies:** Disposable PostgreSQL/TLS fixture, dependency gate, DF-M0-001 findings

**User story:** As an adapter owner, I need verified driver semantics before committing the core to a crate.

**Description:** Evaluate exact `tokio-postgres` candidate against supported-version hypotheses and required protocol behavior.

**Technical notes:** Measure typed row stream, cancel-token race, post-cancel session, transaction loss and TLS integration.

**Security considerations:** Bad CA/hostname/client certificate, malicious length/metadata, redaction and no connection-string log.

**Acceptance criteria:** All required paths have evidence; limitations become conditional/unsupported capabilities; license/advisory/transitive/arm64/size review recorded.

**Tests required:** Disposable integration for success/auth/TLS/query/cancel/rollback/network loss/large stream.

**Out of scope:** Production adapter/UI, SSH and non-PostgreSQL engines.

**Definition of done:** Prototype deleted; driver adopted/rejected with exact evidence and risk owner.

**M0 disposition (2026-07-30):** Evidence complete; exact stack deferred by
[ADR-0009](adr/0009-m0-postgres-driver-disposition.md). See
[DF-M0-002 evidence](reports/DF-M0-002-postgres-driver-evidence.md). The
production adapter gate remains closed until a hard backend-frame cap, bounded
request admission, logging policy and credential-memory decision are verified.

### DF-M0-003

**ID:** DF-M0-003

**Title:** Benchmark TextKit 2 SQL editor feasibility

**Epic:** SQL editor spike

**Priority:** P0

**Complexity:** M

**Dependencies:** ADR-0001, BF-01 fixture

**User story:** As a Mac user, I need responsive native editing on large SQL files.

**Description:** Prototype `NSTextView`/TextKit 2 visible-range highlighting, background incremental analysis, find, selection and undo.

**Technical notes:** Avoid accessing APIs that force legacy layout unintentionally; instrument MainActor and memory.

**Security considerations:** Treat SQL file/parser output as untrusted; no query execution/history/secret.

**Acceptance criteria:** 10 MB budget passes; 100 MB stress has documented graceful large-file mode; keyboard/VoiceOver/undo work.

**Tests required:** BF-01 edit/start/middle/end/find/cancel, Instruments, accessibility and recovery.

**Out of scope:** Full completion/formatter/execution and production editor architecture.

**Definition of done:** Prototype disposed; editor component decision and measured limits documented.

**M0 disposition (2026-07-30):** TextKit 2 is conditionally retained as the
planning candidate by [ADR-0010](adr/0010-m0-textkit-editor-disposition.md).
See the [DF-M0-003 evidence](reports/DF-M0-003-textkit-editor-evidence.md).
Bounded analysis/find, large-file degradation, native undo and fallback
detection have positive developer-host evidence. Production remains gated on
true input-to-frame paint on the M1/16 GiB floor, an editor RSS ceiling, real
shortcut/VoiceOver behavior, durable recovery and signposted cancellation.

### DF-M0-004

**ID:** DF-M0-004

**Title:** Benchmark virtualized typed AppKit grid feasibility

**Epic:** Result grid spike

**Priority:** P0

**Complexity:** L

**Dependencies:** ADR-0001, BF-02/BF-03, `DATABASE_ADAPTERS.md` §10 and
`ARCHITECTURE.md` §10 normalized type/style contracts

**User story:** As a data user, I need a grid that remains responsive and preserves safe edit state at scale.

**Description:** Prototype view-based `NSTableView`, bounded page cache, generated stream, frozen-column synchronization, pending-edit overlay and visible style invalidation.

**Technical notes:** Measure cell reuse, horizontal/vertical scroll, memory pressure and custom accessibility needs.

**Security considerations:** Generated data only; prove not-loaded/NULL/empty distinction and stable logical identity.

**Acceptance criteria:** BF-02/03 budgets, selection/scroll/edit preservation, Light/Dark/non-color indicators and VoiceOver table semantics pass or fallback selected.

**Tests required:** UI/snapshot/accessibility, RSS/frame/signpost, eviction/pending-edit/theme tests.

**Out of scope:** Live DB, SQL writes, all editor types.

**Definition of done:** Prototype deleted; grid decision/limits and follow-up tasks documented.

**M0 disposition (2026-07-30):** The full-grid `NSTableView` plus frozen-table
composition is rejected by
[ADR-0011](adr/0011-m0-grid-disposition.md). See the
[DF-M0-004 evidence](reports/DF-M0-004-appkit-grid-evidence.md). The bounded
model/cache/identity contracts have positive synthetic evidence, but BF-03
materializes the wide column/view graph and fails the one-logical-table
accessibility contract. A bounded custom native two-dimensional renderer is
the replacement planning candidate; production remains gated on its own
presented-frame, M1/16 GiB, accessibility, memory and soak evidence. The spike
source was removed in disposal commit `c775b8e`; its evidence source remains
auditable at `7acdec0`.

### DF-M0-005

**ID:** DF-M0-005

**Title:** Evaluate SSH tunnel and host-trust candidates

**Epic:** Secure connections spike

**Priority:** P0

**Complexity:** L

**Dependencies:** Ephemeral SSH/jump-host fixtures, threat model, dependency review

**User story:** As a user, I need tunnels that authenticate hosts and never bypass trust or leak keys.

**Description:** Compare patched `russh`, system OpenSSH and libssh2-class alternatives for key/password/agent/jump host/tunnel/cancel needs.

**Technical notes:** Account for 2026 `russh` advisories; no shell interpolation; bounded frames and clean lifecycle.

**Security considerations:** Unknown/changed key, malicious server/agent, key permissions, passphrase lease, no direct fallback.

**Acceptance criteria:** Selected candidate passes scoped auth/trust/jump/cancel/cleanup and adoption gate; unsupported modes explicit.

**Tests required:** MITM/host-change, oversized frames, agent/jump/tunnel failure, cancellation/leak and secret scan.

**Out of scope:** Production connection UI and broad algorithm compatibility promises.

**Definition of done:** Candidate decision, patched floor/fallback and threat/test evidence recorded; spike disposed.

**M0 disposition (2026-07-30):** No SSH candidate is adopted by
[ADR-0012](adr/0012-m0-ssh-disposition.md). See the
[DF-M0-005 evidence](reports/DF-M0-005-ssh-tunnel-evidence.md). The tested
system OpenSSH build and native `ProxyJump/-J` are rejected; the exact
`ssh2`/libssh2 source is rejected on its current security floor; exact
`russh 0.62.4` remains only a conditional planning candidate. Password,
complete agent failure handling, connector-level no-direct fallback,
local-listener echo and comprehensive cleanup remain unsupported. Production
SSH is disabled until every ADR re-entry gate passes.
The disposable source remains auditable at `875dd46` and was removed in
separate disposal commit `0b80f7e`.
ADR-0015 later supersedes only the conditional exact-version statement:
official `GHSA-m65r-rprj-r5rg` affects `russh 0.62.4`, so that exact source is
now rejected; a newer source must rerun the complete gate.

### DF-M0-006

**ID:** DF-M0-006

**Title:** Prove direct signing, notarization and secure update chain

**Epic:** Distribution spike

**Priority:** P0

**Complexity:** L

**Dependencies:** Apple signing environment, ADR-0006, empty Swift/Rust shell

**User story:** As a user, I need Gatekeeper-verifiable binaries and tamper-resistant updates.

**Description:** Build an empty arm64 app/core and optional empty helper; sign nested code, enable Hardened Runtime, notarize/staple and exercise updater candidate.

**Technical notes:** Verify each nested item/designated requirement/entitlement; retain notary logs and artifact manifest.

**Security considerations:** Offline update key handling, tamper/downgrade/replay/channel and helper identity.

**Acceptance criteria:** Clean Mac install passes; altered/wrong/downgraded update rejects; rollback/key rotation procedure demonstrated.

**Tests required:** codesign/spctl/notary/update/security/architecture-slice/secret/SBOM checks.

**Out of scope:** Product features, public feed or production signing-key workflow.

**Definition of done:** Findings and release runbook captured; disposable shell regenerated later from approved scaffold.

**M0 disposition (2026-07-30):** ADR-0013 retains direct Developer ID
distribution as the first-channel plan but keeps production distribution and
updater adoption disabled. See the
[DF-M0-006 evidence](reports/DF-M0-006-distribution-evidence.md) and
[release runbook](RELEASE_RUNBOOK.md). Local arm64/ad-hoc Hardened Runtime,
tamper and exact Sparkle `2.9.4` offline signing smokes pass; Developer ID,
secure timestamp, notarization, stapling, clean-Mac Gatekeeper and real updater
install/rollback/key-rotation remain unsupported or partial. Production must
regenerate an approved scaffold for the credentialed lane. The exact source
remains auditable at `f0457dd` and was removed in separate disposal commit
`38c7441`.

### DF-M0-007

**ID:** DF-M0-007

**Title:** Prove SQLite metadata and Keychain separation

**Epic:** Local persistence and secrets spike

**Priority:** P0

**Complexity:** M

**Dependencies:** ADR-0004/0005, GRDB adoption review candidate

**User story:** As a security owner, I need evidence that profiles/workspaces persist without secret leakage.

**Description:** Prototype transactional migration for synthetic workspace/profile metadata referencing Keychain canary credentials.

**Technical notes:** Test WAL decision, corruption/rollback/retention and Security.framework data-protection keychain behavior.

**Security considerations:** Locked/denied/duplicate Keychain, no plaintext fallback, database/log/export/snapshot canary scan.

**Acceptance criteria:** Migration and CRUD recover safely; secret only exists in Keychain; deleting diagnostics/history does not accidentally delete credentials and vice versa.

**Tests required:** Persistence migration/crash/corruption/concurrency, Keychain ACL/error, seeded-secret negative scans.

**Out of scope:** Production schema, real credentials, helper access.

**Definition of done:** Prototype disposed; schema/security contracts and dependency decision recorded.

**M0 disposition (2026-07-30):**
[DF-M0-007 evidence](reports/DF-M0-007-persistence-keychain-evidence.md)
and [ADR-0014](adr/0014-m0-persistence-keychain-disposition.md) retain the
SQLite-behind-a-Swift-port and Keychain-only boundaries. The exact matrix is
`15 pass / 3 partial / 2 unsupported / 0 fail`: migrations, rollback,
future-version refusal, crash/corruption, bounded concurrency, retention,
backup, permissions and secret-negative surfaces passed. Actual Data
Protection Keychain add/attributes were unsupported because the unsigned CLI
returned `errSecMissingEntitlement`; injected duplicate/missing/locked/denied
and independent deletion are not substitutes for signed-app integration.
Exact GRDB `7.11.1` is conditional only, XCTest/full Xcode did not run, no
journal mode is selected and production persistence remains disabled. The
source is auditable at `6388860` and was removed in separate disposal commit
`02c86b7`.

### DF-M0-008

**ID:** DF-M0-008

**Title:** Complete dependency and license adoption dossiers

**Epic:** Supply-chain assurance

**Priority:** P0

**Complexity:** M

**Dependencies:** Results of DF-M0-002–007

**User story:** As a release owner, I need evidence that proposed dependencies are legally and operationally distributable.

**Description:** Record exact version/source/checksum/license/transitives/advisories/maintenance/MSRV or Swift/Xcode/macOS/arm64/size/replacement for each selected candidate.

**Technical notes:** Generate prototype SBOM and configure planned cargo/Swift audit policy; do not add rejected packages.

**Security considerations:** Provenance, compromised release/source, GPL/AGPL/unclear binary and advisory response.

**Acceptance criteria:** Every proposed dependency is approve/reject/defer with owner/date; no unresolved license/advisory blocker.

**Tests required:** SBOM reproducibility, checksum/source verification, advisory/license policy dry run.

**Out of scope:** General dependency upgrades and product licensing decision.

**Definition of done:** Dossiers reviewed by engineering/security/legal; ADR/backlog updated with exact decisions.

**M0 engineering disposition (2026-08-01):** The
[DF-M0-008 dossier](reports/DF-M0-008-dependency-adoption-dossiers.md),
[dependency policy](DEPENDENCY_POLICY.md), prototype SPDX inventory and
[ADR-0015](adr/0015-m0-dependency-disposition.md) record
`0 approve / 10 defer / 3 reject`; production dependency adoption remains
false. Fresh official `GHSA-m65r-rprj-r5rg` affects exact `russh 0.62.4`, so
ADR-0015 rejects that exact source in addition to the previously rejected
tested system OpenSSH/native `-J` and `ssh2`/libssh2 source. The candidate
coverage, immutable lock/checksum reconstruction and planned policy dry run
are recorded, but the dry run correctly blocks: exact legal/notices reviews,
several unselected identities, product manifests/size/release SBOM and
independent engineering/security/legal approvals are absent. Consequently the
task Definition of Done is **not met**; the artifact is ready for external
review and no dependency was added.

The [M0 external review packet](reports/M0-external-review-packet.md) pins the
DF-M0-008 evidence and keeps independent engineering/security/legal slots
pending without treating packet-level concurrence as dependency adoption.

### DF-M0-009

**ID:** DF-M0-009

**Title:** Review original shell wireframes and accessibility annotations

**Epic:** Native macOS UX foundation

**Priority:** P1

**Complexity:** S

**Dependencies:** ADR-0001, `docs/USER_FLOWS.md`, `docs/UX_WIREFRAMES.md`

**User story:** As a macOS user, I need a reviewed keyboard- and VoiceOver-first shell before application UI implementation begins.

**Description:** Review the low-fidelity shell, connection, editor/grid, destructive-confirmation and transaction-close wireframes; record terminology, focus order, production/read-only language and accessibility acceptance decisions.

**Technical notes:** This is a design gate, not a SwiftUI/AppKit implementation. Validate resizing, Light/Dark, Increase Contrast, Differentiate Without Color, Reduce Motion and localized consequence text against the M0 budgets.

**Security considerations:** Production and destructive warnings must remain text/icon/VoiceOver-visible; no color-only or shortcut-only bypass may be approved.

**Acceptance criteria:** Product, macOS interaction design,
Accessibility/VoiceOver, Database Safety and Security reviewers approve or
explicitly disposition every wireframe; unresolved focus, warning, resize or
VoiceOver issue has an owner and revisit trigger; owning M1/M2 items link the
reviewed artifact without treating static review as executable evidence.

**Tests required:** Keyboard/focus walkthrough, accessibility-label review, appearance/contrast checklist, resize/localization review and traceability check to UF-01/02/04/05/06.

**Out of scope:** Production UI, database calls, credentials, assets, pixel-perfect measurements and competitor comparison.

**Definition of done:** Review record and artifact status are current; owning
M1/M2 items can reference the decision without relying on an untracked design
assumption.

**M0 engineering disposition (2026-08-01):** The revised
[wireframe artifact](UX_WIREFRAMES.md),
[DF-M0-009 review](reports/DF-M0-009-wireframe-accessibility-review.md),
machine-readable matrix and
[ADR-0016](adr/0016-m0-wireframe-accessibility-disposition.md) conditionally
retain all five flows. Ten low-fidelity contract revisions clarify current SSH
unsupported state, terminology, focus lifecycle, cancellation/result limits,
appearance/localization and dangerous confirmation behavior. Twelve tracked
actions remain (`0 Critical / 5 High / 6 Medium / 1 Low`), each with owner and
revisit trigger. No executable UI/AX/VoiceOver/contrast/resize/localization
evidence or independent Product/Design/Accessibility/Database-Safety/Security
sign-off exists, so `df_m0_009_definition_of_done_met=false`; neither M1 nor M2 UI
implementation is authorized by this record.

The [M0 external review packet](reports/M0-external-review-packet.md) pins the
DF-M0-009 evidence and tracks the five required independent reviewer roles; all
remain pending and no runtime or implementation authority is inferred.

## Milestone 1 — Application shell

### DF-M1-001

**ID:** DF-M1-001

**Title:** Scaffold feature modules and architecture fitness tests

**Epic:** Application foundation

**Priority:** P1

**Complexity:** M

**Dependencies:** M0 exit, explicit production implementation authorization

**User story:** As a contributor, I need buildable module boundaries so dependencies cannot silently collapse.

**Description:** Create the minimal Xcode/Cargo workspace and empty modules listed in Architecture, plus automated forbidden-dependency checks.

**Technical notes:** Strict Swift concurrency and Rust lint policy; no live database feature.

**Security considerations:** Minimal entitlements/dependencies, no secrets/build artifacts in Git.

**Acceptance criteria:** Clean arm64 build; UI cannot import driver modules; adapter cannot import UI; FFI handshake target builds.

**Tests required:** Build/lint/format, architecture dependency tests, clean checkout.

**Out of scope:** Feature UI, connection or database driver.

**Definition of done:** CI evidence, module ownership docs and commands checked in.

### DF-M1-002

**ID:** DF-M1-002

**Title:** Implement native window, tabs and command shell

**Epic:** AppShell and Workspace

**Priority:** P1

**Complexity:** L

**Dependencies:** DF-M1-001, ADR-0001, reviewed shared/WF-01/non-live WF-02
contract from DF-M0-009

**User story:** As a Mac user, I need keyboard-first windows/tabs/panes and standard commands.

**Description:** Implement shell layout, menus, command palette, tab identity, resizable panels and empty/loading/error/cancel states.

**Technical notes:** MainActor state; system components; no business logic in views.

**Security considerations:** Production/read-only visual component uses text/icon; no connection behavior yet.

**Acceptance criteria:** Multi-window/tab/menu/focus/resize/Light/Dark and VoiceOver baseline meet UX/budget.

**Tests required:** Swift unit, UI/keyboard/accessibility/snapshot, launch/frame performance.

**Out of scope:** Persistence, live connection, SQL editor/grid.

**Definition of done:** Tests/build/lint pass; accessibility labels and docs complete.

### DF-M1-003

**ID:** DF-M1-003

**Title:** Implement transactional workspace metadata migrations

**Epic:** Local persistence

**Priority:** P1

**Complexity:** M

**Dependencies:** DF-M1-001, ADR-0004, approved dependency dossier

**User story:** As a user, I want drafts and layouts restored without corrupting or leaking secrets.

**Description:** Implement bounded SQLite schema/migrations for workspace, drafts, preferences and non-secret connection references.

**Technical notes:** Persistence port, atomic migrations, integrity/recovery, retention and file permissions.

**Security considerations:** Deny secret columns/models; canary scan; no live transaction restore.

**Acceptance criteria:** Fresh/upgrade/crash/corruption paths safe; 20-tab restore budget; delete controls correct.

**Tests required:** Migration/rollback/concurrency/corruption/recovery/performance/secret scans.

**Out of scope:** Query history content beyond minimal schema and Keychain implementation.

**Definition of done:** Schema docs/tests/commands pass; remaining recovery risk documented.

### DF-M1-004

**ID:** DF-M1-004

**Title:** Implement Keychain credential store and lease API

**Epic:** KeychainSecurity

**Priority:** P0

**Complexity:** M

**Dependencies:** ADR-0005, DF-M1-001, M0 Keychain evidence

**User story:** As a user, I need credentials stored only by macOS Keychain and exposed briefly when required.

**Description:** Add typed CRUD/reference/lease service with data-protection Keychain and injected protocol.

**Technical notes:** Secret values non-Codable/non-printable; map OSStatus to typed user-safe errors.

**Security considerations:** Locked/denied/access control/no sync default/no fallback/zeroization where practical.

**Acceptance criteria:** CRUD/duplicate/locked/denied/missing works; canary appears nowhere else; lease lifetime bounded.

**Tests required:** Unit with fake, Security.framework integration, ACL/error, seeded-secret diagnostics/persistence/export scans.

**Out of scope:** Background helper access and OAuth renewal.

**Definition of done:** Threat review and tests pass; docs state accessibility/access policy.

### DF-M1-005

**ID:** DF-M1-005

**Title:** Implement non-secret connection profile validation

**Epic:** Connections

**Priority:** P1

**Complexity:** M

**Dependencies:** DF-M1-003/004, adapter capability schema

**User story:** As a user, I want clear typed connection options, environment and read-only policy before connecting.

**Description:** Implement immutable profile/domain validation, groups/colors/environment and secret reference; import/export metadata without secret.

**Technical notes:** UI does not build connection strings; adapter-specific fields are capability-driven.

**Security considerations:** Production indicator cannot be hidden; export redaction and invalid references handled.

**Acceptance criteria:** Valid/invalid profiles and roundtrip metadata pass; export never includes secret; production/read-only persist correctly.

**Tests required:** Unit/property, persistence migration, export leakage, UI/accessibility.

**Out of scope:** Live test/connect/TLS/SSH.

**Definition of done:** Test/build/lint/docs pass with typed error cases.

### DF-M1-006

**ID:** DF-M1-006

**Title:** Implement structured redacted diagnostics and exact export preview

**Epic:** Diagnostics and privacy

**Priority:** P0

**Complexity:** L

**Dependencies:** DF-M1-003, threat model, logging schema

**User story:** As a privacy-conscious user, I need useful diagnostics that I can inspect before export.

**Description:** Add allowlisted structured events, correlation IDs, redaction-before-sinks, bounded retention, preview/export/delete UI.

**Technical notes:** Preview bytes must equal exported bytes; no always-on network sink.

**Security considerations:** Deny secrets, connection strings, params, row/clipboard/file content and stack trace display.

**Acceptance criteria:** Seeded canaries absent; exact preview/export; delete retention; fresh install sends no traffic.

**Tests required:** Schema/redaction/property/leak, SQLite retention, atomic file, UI/privacy/network tests.

**Out of scope:** Third-party crash vendor and telemetry product analytics.

**Definition of done:** Security/privacy review and tests pass; user documentation complete.

### DF-M1-007

**ID:** DF-M1-007

**Title:** Implement workspace draft crash recovery

**Epic:** Workspace

**Priority:** P1

**Complexity:** M

**Dependencies:** DF-M1-002/003

**User story:** As a developer, I need unsaved SQL recovered after a crash without silently rerunning it.

**Description:** Add debounced atomic draft persistence, disconnected restoration, conflict/recovery UI and independent deletion.

**Technical notes:** Bound draft/history storage; structured cancellation; preserve stable tab IDs.

**Security considerations:** SQL may be sensitive; local-only, no telemetry/snapshot; no secret field captured.

**Acceptance criteria:** Crash at save boundaries recovers last confirmed draft; no query/connection/transaction starts; large restore meets budget.

**Tests required:** Crash/fault injection, migration, UI restore/focus, performance and canary scans.

**Out of scope:** File collaboration/version control.

**Definition of done:** Recovery matrix and tests pass; limitations documented.

### DF-M1-008

**ID:** DF-M1-008

**Title:** Establish release, dependency and security CI gates

**Epic:** Build and supply chain

**Priority:** P0

**Complexity:** M

**Dependencies:** DF-M1-001, M0 distribution/dependency reports

**User story:** As a maintainer, I need repeatable evidence for every build before features expand.

**Description:** Pin toolchains; add format/lint/build/unit/FFI/secret/advisory/license/SBOM jobs and arm64 artifact verification.

**Technical notes:** Lock dependencies/images; preserve provenance and command output without environment dumps.

**Security considerations:** Least-privilege CI secrets, protected signing jobs, untrusted PR separation.

**Acceptance criteria:** Clean checkout gates pass; intentional lint/secret/vulnerable dependency failures block; artifacts identify commit/toolchain.

**Tests required:** CI self-tests, secret canary, SBOM/checksum reproduction and failure-path drills.

**Out of scope:** Public release signing credentials and production update feed.

**Definition of done:** Required checks protected/documented; no skipped blocker.

## Milestone 2 — PostgreSQL vertical slice

### DF-M2-001

**ID:** DF-M2-001

**Title:** Implement PostgreSQL connection, TLS and capability handshake

**Epic:** PostgreSQL adapter

**Priority:** P0

**Complexity:** L

**Dependencies:** M1, DF-M0-002, reviewed live WF-02 contract and adopted
PostgreSQL/TLS dossiers; DF-M0-005 and an adopted SSH dossier only if this item
enables an SSH capability

**User story:** As a PostgreSQL user, I need a validated connection whose safety capabilities are truthful.

**Description:** Build adapter option transformation, connect/test/close,
TLS/custom CA/client cert, pool ceilings and capability snapshot. Add only an
explicitly adopted SSH subset; otherwise expose direct TLS connections only.

**Technical notes:** Credentials enter only as leases; no UI connection string; tunnel owns DB lifecycle.

**Security considerations:** Hostname/certificate verification always;
host-key verification and no-direct-fallback only when SSH is enabled;
read-only/production context and redacted errors in every mode.

**Acceptance criteria:** Declared matrix passes; invalid trust/auth blocks; cancel/cleanup works; capability conditions are source/version aware.

**Tests required:** Disposable PG oldest/current,
TLS/auth/timeout/cancel/pool/leak/security; add the full SSH matrix only when
that capability is enabled.

**Out of scope:** Query UI, metadata and writes.

**Definition of done:** Conformance subset/build/lint/security/performance and documentation pass.

### DF-M2-002

**ID:** DF-M2-002

**Title:** Implement lazy PostgreSQL metadata explorer service

**Epic:** ObjectExplorer

**Priority:** P1

**Complexity:** L

**Dependencies:** DF-M2-001, normalized metadata contract

**User story:** As a DBA, I need lazy searchable PostgreSQL objects without full catalog load.

**Description:** Add scoped introspection for database/schema/table/column/key/index/view/materialized view/routine/extension and DDL/details.

**Technical notes:** Stable IDs, limited-privilege partial results, bounded cache/invalidation and per-node cancellation.

**Security considerations:** Parameterized catalog queries; metadata/DDL treated as untrusted display; no row data logs.

**Acceptance criteria:** Expand fetches only scope; refresh/search/cache budgets; capability/privilege gaps clear.

**Tests required:** Conformance/quoted Unicode/limited privilege/large schema/cache/cancel/UI/accessibility/performance.

**Out of scope:** Object mutation and dependency graph editing.

**Definition of done:** UF-08 and BF-04 evidence pass; cache policy documented.

### DF-M2-003

**ID:** DF-M2-003

**Title:** Implement SQL document and TextKit editor component

**Epic:** QueryEditor

**Priority:** P1

**Complexity:** L

**Dependencies:** M1 Workspace, DF-M0-003 and reviewed WF-03 editor contract

**User story:** As a developer, I need native SQL editing with exact selections and recovery.

**Description:** Implement TextKit 2 document, line/find/selection/undo/highlighting baseline and run-current/selection/script intents.

**Technical notes:** Incremental visible work, background analysis cancellation, MainActor state, large-file mode.

**Security considerations:** No execution in view body; SQL remains local user data; parser output untrusted.

**Acceptance criteria:** BF-01 budgets/keyboard/VoiceOver/recovery; exact execution bytes are stable.

**Tests required:** Unit/UI/keyboard/accessibility/snapshot/large-file/cancellation/performance.

**Out of scope:** Full formatter/multi-cursor/semantic completion/plan rendering.

**Definition of done:** Build/lint/tests/budgets/docs pass.

### DF-M2-004

**ID:** DF-M2-004

**Title:** Implement PostgreSQL statement classifier and safety policy

**Epic:** Query safety

**Priority:** P0

**Complexity:** XL

**Dependencies:** DF-M2-003, dialect parser decision, DATABASE_SAFETY and
reviewed WF-04 destructive-confirmation contract

**User story:** As a production user, I need destructive and unknown SQL blocked or confirmed based on exact effects.

**Description:** Parse/split/classify statements, read-only enforcement, R0–R4 policy, canonical preview digest and target-specific confirmation.

**Technical notes:** Regex only for hints; procedural/dynamic unknown; changed context invalidates preview; core rechecks.

**Security considerations:** Shortcut/stale target/parser gap/production/read-only bypasses are release blockers.

**Acceptance criteria:** DROP/TRUNCATE/unconditional writes/equivalents classified; unknown production R3 blocked; typed confirmation cannot be replayed.

**Tests required:** Unit/property/fuzz/corpus, adapter semantic, UI shortcut/stale-digest/accessibility/security.

**Out of scope:** MySQL/SQLite dialects and unsafe override.

**Definition of done:** Threat/test traceability passes with no unclassified claimed-safe path.

### DF-M2-005

**ID:** DF-M2-005

**Title:** Implement bounded PostgreSQL query stream over FFI

**Epic:** QueryExecution

**Priority:** P0

**Complexity:** XL

**Dependencies:** DF-M2-001/004, accepted FFI contract

**User story:** As a user, I need typed results and messages without loading all rows into memory.

**Description:** Add immutable execution context, row/byte chunks, multiple result/status/message order, row limit, deferred large value, timeout and cancellation.

**Technical notes:** Pull/ack/backpressure; supervised task; cancel outcome and post-cancel session status.

**Security considerations:** Malicious lengths/types, redaction, no write retry, panic containment.

**Acceptance criteria:** 10M stream bounded; slow consumer backpressures; cancel truth/error categories; multiple results ordered.

**Tests required:** FFI/driver/unit/property/malicious server/timeout/cancel/leak/performance.

**Out of scope:** Editable grid and export encoder.

**Definition of done:** UF-04 stream lifecycle and budgets pass; all terminal states documented.

### DF-M2-006

**ID:** DF-M2-006

**Title:** Implement PostgreSQL transaction session state

**Epic:** Transactions

**Priority:** P0

**Complexity:** L

**Dependencies:** DF-M2-005 and reviewed WF-05 transaction-close contract

**User story:** As a developer, I need explicit begin/commit/rollback and close warnings with authoritative state.

**Description:** Pin adapter session; model transaction states, autocommit choice, commit/rollback, loss/unknown and close/termination flows.

**Technical notes:** UI projects core state; DDL/aborted semantics surfaced; no auto-commit/reconnect resume.

**Security considerations:** Wrong-session commit, hidden commit and write retry blocked; logs redacted.

**Acceptance criteria:** UF-06, failure/aborted/lost/close flows pass; transaction ID/target visible.

**Tests required:** Integration success/failure/cancel/network loss/close/UI/accessibility/rollback.

**Out of scope:** Cross-connection/distributed transactions.

**Definition of done:** Transaction safety tests and docs pass.

### DF-M2-007

**ID:** DF-M2-007

**Title:** Implement virtualized typed result grid

**Epic:** ResultGrid

**Priority:** P0

**Complexity:** XL

**Dependencies:** DF-M2-005, DF-M0-004, ADR-0011, reviewed WF-03 grid contract
and normalized type/theme contract

**User story:** As a user, I need smooth typed browsing at million-row scale.

**Description:** Implement a reviewed bounded custom native two-dimensional renderer, page/cache/prefetch, type renderers, NULL/empty/not-loaded, sort/filter intents, deferred BLOB and baseline scoped appearance.

**Technical notes:** Virtualize rows and columns with bounded overscan/object inventory; expose one logical accessibility table; keep pending edits separate; visible-style invalidation; byte+item cache limits and memory pressure.

**Security considerations:** Untrusted cell metadata/text, clipboard lifecycle, no row logging.

**Acceptance criteria:** BF-02/03 budgets; Light/Dark/contrast/non-color; selection/scroll preserved; large BLOB deferred.

**Tests required:** UI/snapshot/accessibility/type/cache/eviction/theme/clipboard/performance/soak.

**Out of scope:** Write apply and every advanced cell editor.

**Definition of done:** Grid contract/budgets and tests pass with cache inventory.

### DF-M2-008

**ID:** DF-M2-008

**Title:** Implement key-safe PostgreSQL row editing

**Epic:** DataEditor

**Priority:** P0

**Complexity:** XL

**Dependencies:** DF-M2-002/007, edit adapter and safety policy

**User story:** As a user, I need previewed pending edits that affect exactly the intended row or remain read-only.

**Description:** Add identity plan, pending overlay, typed validation, parameterized preview/apply/rollback, optimistic predicate, affected-row assertion and reconciliation.

**Technical notes:** No-key read-only; zero conflict; >1 critical failure; preserve edits on failure/scroll/refresh warning.

**Security considerations:** Wrong-row highest severity; no SQL concatenation; target/production/read-only recheck.

**Acceptance criteria:** Exactly-one success; concurrent/zero/multiple/constraint/cancel/loss safe; no-key cannot edit.

**Tests required:** Unit/adapter/UI/wrong-row/concurrency/rollback/trigger/generated/key-null/security.

**Out of scope:** Arbitrary expert no-key override and cross-table batch editor.

**Definition of done:** UF-10/11 and database-write Definition of Done pass.

### DF-M2-009

**ID:** DF-M2-009

**Title:** Implement streaming formula-safe CSV export

**Epic:** ImportExport

**Priority:** P1

**Complexity:** L

**Dependencies:** DF-M2-005/007, file security

**User story:** As a user, I need current results exported without unbounded memory, overwrite surprise or spreadsheet injection.

**Description:** Export page/all/selection/columns with encoding/null/date/formula policy to atomic restricted file and cancel/cleanup.

**Technical notes:** Encoder receives typed chunks; no hidden refetch/write; estimated/unknown size.

**Security considerations:** CSV escaping/formula prefixes/path/symlink/overwrite/temp permissions/no secret.

**Acceptance criteria:** Standards roundtrip; hostile cells neutralized per policy; disk full/cancel leaves clean/marked result; 10 GB budget.

**Tests required:** Property/roundtrip/formula/path/permission/disk/cancel/security/performance.

**Out of scope:** Import and non-CSV formats.

**Definition of done:** UF-17, leak/security and performance gates pass.

### DF-M2-010

**ID:** DF-M2-010

**Title:** Complete PostgreSQL end-to-end vertical-slice evidence

**Epic:** M2 release integration

**Priority:** P0

**Complexity:** L

**Dependencies:** DF-M2-001–009

**User story:** As a reviewer, I need proof that the advertised PostgreSQL workflow is coherent and safe.

**Description:** Run full connection→browse→query→cancel→transaction→grid→edit→export flows and document supported versions/capabilities/limits.

**Technical notes:** Release-like arm64 build, disposable fixtures, exact commands/artifacts.

**Security considerations:** Secret/trust/destructive/wrong-row/update gates all release blocking.

**Acceptance criteria:** Every M2 exit criterion has authoritative evidence; no skip/unknown is labeled supported.

**Tests required:** Full unit/FFI/adapter/integration/UI/security/performance/soak/distribution subset.

**Out of scope:** M3 engines and public release unless separately authorized.

**Definition of done:** Evidence report reviewed; roadmap/capabilities/risks/docs current.

## Milestone 3 — MySQL, MariaDB and SQLite

### DF-M3-001

**ID:** DF-M3-001

**Title:** Add MySQL vertical adapter conformance

**Epic:** MySQL adapter

**Priority:** P1

**Complexity:** XL

**Dependencies:** M2 stable ports, approved driver/auth/TLS dossier

**User story:** As a MySQL user, I need the safe MVP workflow with truthful MySQL semantics.

**Description:** Implement declared connect/metadata/query/cancel/transaction/grid/edit/export and MySQL dialect/type mapping.

**Technical notes:** Auth plugins, charset/collation, unsigned/zero-date, storage-engine/implicit-commit; LOCAL INFILE off.

**Security considerations:** TLS/auth, malicious server, local-file requests, parser/generation/read-only.

**Acceptance criteria:** Per-version matrix passes; conditional cancel/transaction truth; no PostgreSQL semantics leak.

**Tests required:** Oldest/current disposable auth/TLS/type/dialect/transaction/cancel/wrong-row/performance/security.

**Out of scope:** MariaDB support claim and backup tools.

**Definition of done:** Capability matrix/docs/tests pass.

### DF-M3-002

**ID:** DF-M3-002

**Title:** Add separate MariaDB capability and regression matrix

**Epic:** MariaDB adapter

**Priority:** P1

**Complexity:** L

**Dependencies:** DF-M3-001 shared wire infrastructure, MariaDB dossier

**User story:** As a MariaDB user, I need differences tested rather than assumed from MySQL.

**Description:** Implement/version-gate MariaDB auth/dialect/JSON/returning/metadata/optimizer/type differences and UI labels.

**Technical notes:** Reuse only validated protocol pieces; separate capability snapshot and fixtures.

**Security considerations:** Same trust/safety gates plus dialect classifier differences.

**Acceptance criteria:** Separate supported matrix; known divergences tested/documented; unsupported states disabled.

**Tests required:** MariaDB oldest/current auth/TLS/type/SQL/cancel/transaction/security/UI/performance.

**Out of scope:** Claiming full MySQL parity.

**Definition of done:** Independent conformance evidence and docs pass.

### DF-M3-003

**ID:** DF-M3-003

**Title:** Add safe user-file SQLite adapter

**Epic:** SQLite adapter

**Priority:** P1

**Complexity:** XL

**Dependencies:** M2 ports, approved `rusqlite`, file/bookmark policy

**User story:** As a user, I need to browse/query/edit a selected SQLite file without confusing it with app metadata or blocking UI.

**Description:** Implement read-only/read-write open, bounded blocking lane, metadata/query/interrupt/transaction/grid/edit/export and SQLite dialect/type semantics.

**Technical notes:** Busy/WAL/journal, attached DB, affinity/strict/WITHOUT ROWID, external replacement/corruption.

**Security considerations:** User-selected bookmark, symlink/path, extension loading off, metadata DB exclusion.

**Acceptance criteria:** Interrupt/transaction/file-change truth; safe identity; app metadata cannot open; no main-thread I/O.

**Tests required:** File/permission/symlink/corruption/WAL/busy/type/dialect/interrupt/edit/security/performance.

**Out of scope:** Arbitrary SQLite extensions and remote filesystem guarantees.

**Definition of done:** Separate capability/version/file policy evidence passes.

### DF-M3-004

**ID:** DF-M3-004

**Title:** Verify capability-driven cross-engine UI

**Epic:** Adapter architecture validation

**Priority:** P0

**Complexity:** M

**Dependencies:** DF-M3-001–003

**User story:** As a user, I need features enabled from actual capabilities, not engine-name assumptions.

**Description:** Add fake/stale/unknown/conditional capability scenarios across explorer/editor/grid/transactions and run all four engines concurrently.

**Technical notes:** Commands revalidate snapshot; UI preserves engine-specific descriptors and errors.

**Security considerations:** Stale capability cannot bypass read-only/destructive/transaction rules.

**Acceptance criteria:** Unsupported controls absent/explained; snapshot drift blocks; global caches/pools bounded.

**Tests required:** Unit/UI/accessibility/fake adapter/stale capability/multi-connection performance/security.

**Out of scope:** M4 tools and Phase-2 engines.

**Definition of done:** ADR-0007 validated or superseded; M3 exit report complete.

## Milestone 4 — Professional data tools

### DF-M4-001

**ID:** DF-M4-001

**Title:** Implement capability-aware object designer and migration preview

**Epic:** ObjectDesigner

**Priority:** P1

**Complexity:** XL

**Dependencies:** M3 metadata/dialect/edit safety

**User story:** As a DBA, I need validated forms and exact SQL before altering an object.

**Description:** Add scoped forms for table/columns/keys/indexes/views/routines/triggers/sequences and immutable desired-state migration intent.

**Technical notes:** Adapter options, lock/rewrite/implicit-commit annotations, drift digest and unsaved state.

**Security considerations:** No form-driver call; R2/R3 production confirmation and no auto-apply.

**Acceptance criteria:** Invalid/unsupported forms block; deterministic preview and drift/partial report; refresh verifies.

**Tests required:** Validation, dialect snapshot/semantic, DDL rollback/partial/permission, UI/accessibility.

**Out of scope:** Generic unsupported options and batch schema sync.

**Definition of done:** Each supported object type has capability/tests/docs and database-write gates.

### DF-M4-002

**ID:** DF-M4-002

**Title:** Implement deterministic schema comparison and reviewed apply

**Epic:** SchemaDiff

**Priority:** P0

**Complexity:** XL

**Dependencies:** DF-M4-001, normalized metadata, BF-05

**User story:** As a release engineer, I need source/target differences and destructive migration consequences reviewed before apply.

**Description:** Build compare graph, confidence rename proposals, include/exclude, dependency order, dry-run/preflight, apply and verify report.

**Technical notes:** Target/plan digest; cycles and nontransactional DDL; compare service cannot import apply service.

**Security considerations:** Production/R3, stale drift, backup recommendation, local redacted audit.

**Acceptance criteria:** Compare never applies; ambiguous rename explicit; target drift blocks; exact partial outcomes.

**Tests required:** Property/graph/rename/cycle/snapshot/disposable apply/rollback/partial/security/performance/UI.

**Out of scope:** Auto-resolving ambiguous rename and unsupported engine transforms.

**Definition of done:** UF-14 and BF-05 gates pass for declared engines.

### DF-M4-003

**ID:** DF-M4-003

**Title:** Implement streaming file import framework and initial formats

**Epic:** ImportExport

**Priority:** P1

**Complexity:** XL

**Dependencies:** M3 adapters, file security, BF-06

**User story:** As a user, I need to preview and import untrusted CSV/TSV/JSON with explicit mapping/error/transaction policy.

**Description:** Add bounded parse/preview/map/dry validation/parameterized batch/apply/error-row/cancel pipeline; extend XML/XLSX only as separate subreviews.

**Technical notes:** Byte/row/field/nesting/decompression limits and explicit encoding/type inference.

**Security considerations:** Path/symlink/archive/XXE/formula/malformed input, secure temp and no secrets.

**Acceptance criteria:** Mapping review; hostile fixtures contained; cancellation/rollback/partial exact; 10 GB bounded.

**Tests required:** Parser property/fuzz/roundtrip/security, adapter transaction, disk/cancel/performance.

**Out of scope:** Parquet, unrestricted XML entities and automatic irreversible inference.

**Definition of done:** Each format has its own capability/security/test evidence.

### DF-M4-004

**ID:** DF-M4-004

**Title:** Implement bounded cross-engine transfer with mapping checkpoints

**Epic:** DataTransfer

**Priority:** P1

**Complexity:** XL

**Dependencies:** M3, normalized type mapping, DF-M4-003 pipeline

**User story:** As a data engineer, I need explicit cross-engine mapping and resumable partial outcomes.

**Description:** Add table/column/type mapping, schema/data modes, bounded batch pipeline, checkpoint, error rows, cancel, verification and report.

**Technical notes:** Idempotency/deduplication per checkpoint; loss classification; target transaction boundaries.

**Security considerations:** Production target, no write retry by default, path/report redaction and permission.

**Acceptance criteria:** Lossy/overflow/timezone/collation warnings; resume cannot duplicate; exact batch outcomes; bounded 100 GB scenario.

**Tests required:** Cross-engine property/integration/rollback/crash/resume/security/performance.

**Out of scope:** Bidirectional continuous replication.

**Definition of done:** Supported mapping matrix and reconciliation runbook pass.

### DF-M4-005

**ID:** DF-M4-005

**Title:** Implement one-way keyed data diff and synchronization

**Epic:** DataDiff

**Priority:** P1

**Complexity:** XL

**Dependencies:** DF-M4-004, stable key/consistency contracts

**User story:** As a data engineer, I need dry-run inserts/updates/deletes with explicit keys and verification.

**Description:** Build streaming key comparison, mappings/filter/batch, sample/summary, delete opt-in, reviewed apply, checkpoint and verify.

**Technical notes:** Consistent snapshot limitations and source/target drift; deterministic operation digest.

**Security considerations:** Deletions R3, no blind retry, production target, exact partial audit.

**Acceptance criteria:** Dry run reproducible; stale target blocks; cancel/resume/verify correct; no ambiguous key.

**Tests required:** Large synthetic data, conflict/drift/delete/rollback/crash/resume/security/performance.

**Out of scope:** Bidirectional conflict resolution.

**Definition of done:** One-way declared matrix passes; bidirectional remains disabled.

### DF-M4-006

**ID:** DF-M4-006

**Title:** Implement first adapter-specific backup and restore workflow

**Epic:** BackupRestore

**Priority:** P0

**Complexity:** XL

**Dependencies:** Distribution/tool dossier, file/process security, one selected MVP engine

**User story:** As a DBA, I need a verified backup and consequence-aware restore using a trusted engine method.

**Description:** Implement one engine's official tool/API discovery, argv/env/temp policy, progress/cancel, artifact validation, restore preview/apply/verify.

**Technical notes:** Signed compatible executable, no shell; credentials via protected supported channel; exact partial state.

**Security considerations:** Restore R3, production target, tool/path injection, secret arguments, artifact permissions.

**Acceptance criteria:** Missing/unsigned/incompatible tool blocks; disposable backup/restore verifies; cancel consequence and cleanup accurate.

**Tests required:** Signature/version/argv/malicious filename/permission/disk/cancel/disposable restore/security/performance.

**Out of scope:** Claiming parity for other engines or rebuilding their backup engine.

**Definition of done:** Capability is enabled only for the exact passing combination.

## Milestone 5 — Modeling and monitoring

### DF-M5-001

**ID:** DF-M5-001

**Title:** Implement scalable physical ER model workspace

**Epic:** Modeling

**Priority:** P2

**Complexity:** XL

**Dependencies:** M4 metadata/diff/designer, graph spike

**User story:** As an architect, I need reverse-engineered relationships and reviewed model changes at scale.

**Description:** Add nodes/edges, incremental auto/manual layout, zoom/pan/minimap/search/groups/notes, safe export and compare/generate plan.

**Technical notes:** Level of detail, deterministic layout/export and model IDs separate from display position.

**Security considerations:** No row/secret export; model changes use schema safety and target digest.

**Acceptance criteria:** 500-table interactive and 5,000 stress budgets; keyboard/VoiceOver; no auto-apply.

**Tests required:** Graph/layout/property/export/UI/accessibility/performance/migration safety.

**Out of scope:** Conceptual/logical collaborative versioning.

**Definition of done:** BF-05, original-design/IP and safety evidence pass.

### DF-M5-002

**ID:** DF-M5-002

**Title:** Implement bounded session/lock/query monitoring and safe cancel

**Epic:** Monitoring

**Priority:** P2

**Complexity:** L

**Dependencies:** Adapter administration ports and permission matrix

**User story:** As an operator, I need current server activity without overloading or disrupting it accidentally.

**Description:** Poll bounded sessions/queries/locks/blockers/transactions/sizes and add stable-identity cancel/kill preview.

**Technical notes:** Rate/backoff, per-connection cache, stale marker, cancel vs kill semantics.

**Security considerations:** Permission check, R2/R3 consequence, no retry, no row/query parameter leakage.

**Acceptance criteria:** Poll budgets/soak; stale identity cannot act; unsupported action absent; outcome honest.

**Tests required:** Disposable load/permission/stale/cancel/kill/UI/accessibility/security/soak.

**Out of scope:** Generic server configuration mutation.

**Definition of done:** Per-engine capability evidence and operations guide pass.

### DF-M5-003

**ID:** DF-M5-003

**Title:** Implement capability-aware user and role change preview

**Epic:** UserRoleManagement

**Priority:** P2

**Complexity:** XL

**Dependencies:** Adapter admin/dialect ports, safety

**User story:** As an authorized DBA, I need exact privilege diffs and partial outcome reports.

**Description:** Add list/membership/database/schema/table privilege desired-state diff, generated SQL, apply and verify for one engine first.

**Technical notes:** Separate privilege scope semantics per adapter; no generic grant assumptions.

**Security considerations:** Least privilege, R2/R3/production, generated credentials Keychain-only, no retry.

**Acceptance criteria:** Preview matches server diff; permission/unsupported/partial states exact; no secret leak.

**Tests required:** Least-privilege disposable users, SQL snapshots, rollback/partial/security/UI.

**Out of scope:** Unimplemented engines and identity-provider administration.

**Definition of done:** Enabled only for passing engine/capability matrix.

## Milestone 6 — Additional engines

### DF-M6-001

**ID:** DF-M6-001

**Title:** Add SQL Server model and adapter vertical slice

**Epic:** SQL Server adapter

**Priority:** P2

**Complexity:** XL

**Dependencies:** Driver/license/auth spike, M3/M4/M5 stable ports

**User story:** As a SQL Server user, I need the supported macOS auth and relational workflows truthfully scoped.

**Description:** Implement proven TLS/auth/connect/metadata/query/cancel/transactions/types/edit/plans/admin subset.

**Technical notes:** TDS driver, Azure/AD/Kerberos constraints, multiple results and temporal/spatial types.

**Security considerations:** Token/credential renewal, TLS, permissions, destructive classifier.

**Acceptance criteria:** Every advertised auth/version/capability passes; unsupported auth is explicit.

**Tests required:** Topology/auth/TLS/type/cancel/transaction/security/UI/performance.

**Out of scope:** Auth modes and native tools without passing macOS evidence.

**Definition of done:** Independent capability/support matrix reviewed.

### DF-M6-002

**ID:** DF-M6-002

**Title:** Add Redis model-specific bounded keyspace workflow

**Epic:** Redis adapter

**Priority:** P2

**Complexity:** XL

**Dependencies:** Driver/topology/security spike and non-relational UX review

**User story:** As a Redis operator, I need type-aware keys without blocking the server or pretending it is relational.

**Description:** Add TLS/auth/cluster/sentinel capabilities, bounded SCAN, TTL/type viewers/editors and dangerous command classification.

**Technical notes:** No `KEYS *`; cursor/backpressure; binary key/value fidelity; per-node topology.

**Security considerations:** ACL, command injection, production destructive commands and untrusted values.

**Acceptance criteria:** Large keyspace stays bounded; topology/cursor/cancel truth; dangerous commands gated.

**Tests required:** Cluster/sentinel/TLS/auth/ACL/scan/type/danger/security/performance.

**Out of scope:** Relational grid/schema semantics.

**Definition of done:** Redis-specific product/capability evidence passes.

### DF-M6-003

**ID:** DF-M6-003

**Title:** Add MongoDB BSON/cursor and collection workflow

**Epic:** MongoDB adapter

**Priority:** P2

**Complexity:** XL

**Dependencies:** Official driver/auth/topology review and non-relational UX

**User story:** As a MongoDB user, I need BSON-accurate, cursor-bounded collection and aggregation tools.

**Description:** Implement TLS/SRV/auth/topology, database/collection/index/validator metadata, BSON cursor results, aggregation explain and safe document edits.

**Technical notes:** Preserve BSON types; transaction conditional on topology; stable `_id`/optimistic strategy.

**Security considerations:** Credential tokens, untrusted BSON/deep docs, query/operator injection and production edits.

**Acceptance criteria:** Supported topology/auth/type/cursor/transaction matrix passes; no relational fiction.

**Tests required:** Replica/sharded fixtures as scoped, TLS/auth/BSON/deep/cancel/edit/security/performance.

**Out of scope:** Unsupported cloud proprietary administration.

**Definition of done:** MongoDB-specific capability and UX review passes.

## Milestone 7 — Automation and advanced features

### DF-M7-001

**ID:** DF-M7-001

**Title:** Define immutable job model and state machine

**Epic:** Automation

**Priority:** P1

**Complexity:** L

**Dependencies:** Stable M4 operations, persistence/safety/audit

**User story:** As a team lead, I need a reviewed job definition whose target and behavior cannot drift silently.

**Description:** Add versioned operation/target/capability/preview digest, timeout/limits/overlap/retry/idempotency/credential/notification policy and terminal/partial states.

**Technical notes:** Job definition references interactive operation spec; migration invalidates review where needed.

**Security considerations:** No secret in definition; no production R3 initial jobs; stale target blocks.

**Acceptance criteria:** Serialization/migration/property states; any behavior change invalidates approval; no generic write retry.

**Tests required:** Unit/property/migration/stale capability/idempotency/security/canary.

**Out of scope:** Scheduler/helper/execution.

**Definition of done:** Threat/safety review and state invariants pass.

### DF-M7-002

**ID:** DF-M7-002

**Title:** Implement bounded app-open job runner

**Epic:** Automation

**Priority:** P1

**Complexity:** XL

**Dependencies:** DF-M7-001, operation checkpoint APIs

**User story:** As a user, I need manual/scheduled-in-app jobs with cancel and exact partial reports.

**Description:** Add scheduler clock, bounded workers/per-connection limits, overlap, credential lease, checkpoint/cancel/restart reconciliation and logs/notifications.

**Technical notes:** Runs only while app open; no hidden wake/logout promise; supervised tasks.

**Security considerations:** Least privilege, immutable digest recheck, no plaintext/fallback, safe notifications.

**Acceptance criteria:** Overlap/crash/cancel/partial/unknown exact; resource limits; changed target/credential blocks.

**Tests required:** Fake clock/state/crash/restart/checkpoint/duplicate/Keychain/tunnel/security/performance/soak.

**Out of scope:** LaunchAgent and logged-out execution.

**Definition of done:** Operations runbook and all supported job matrices pass.

### DF-M7-003

**ID:** DF-M7-003

**Title:** Evaluate and implement consented LaunchAgent helper

**Epic:** Background automation

**Priority:** P2

**Complexity:** XL

**Dependencies:** DF-M7-002, `SMAppService`/XPC/Keychain/update spike and explicit authorization

**User story:** As a user, I want approved jobs to run in my session with truthful platform limitations.

**Description:** Build signed bundled LaunchAgent, registration/status/disable UI, authenticated versioned XPC and update/rollback parity.

**Technical notes:** User-session only; logout/sleep behavior tested/documented; no LaunchDaemon.

**Security considerations:** Designated requirement, least-privilege Keychain group, no arbitrary XPC command, helper tamper/update.

**Acceptance criteria:** Consent/status accurate; unauthorized client rejected; disable/upgrade/rollback/cleanup work; locked credential blocks safely.

**Tests required:** XPC auth/fuzz, signature/update, Keychain/logout/sleep/tunnel/cancel/leak/soak.

**Out of scope:** Guaranteed logged-out/sleep execution and privileged daemon.

**Definition of done:** Security/distribution/privacy review and clean-machine tests pass.

### DF-M7-004

**ID:** DF-M7-004

**Title:** Add enterprise policy and approval seams without gating safety

**Epic:** Enterprise governance

**Priority:** P3

**Complexity:** XL

**Dependencies:** M7 runner, licensing/legal decision, policy threat model

**User story:** As an organization, I need enforceable connection/write/job policy while every edition retains core safeguards.

**Description:** Define signed/versioned policy inputs for production read-only, blocked statements, limits, retention and optional approval integration.

**Technical notes:** Policy conflict resolution and offline/failure behavior fail safe; audit source/version.

**Security considerations:** Policy signature/admin authorization, rollback/replay, privacy and denial of service.

**Acceptance criteria:** Invalid/stale policy fails safe; Community remains Keychain/TLS/destructive/row-safe; decisions explain source.

**Tests required:** Signature/replay/conflict/offline/bypass/UI/accessibility/security.

**Out of scope:** Choosing a commercial license/vendor or weakening base safeguards.

**Definition of done:** Legal/product/security approval and policy conformance pass.

## Backlog operating rules

- Before implementation, replace planning dependencies with exact issue/ADR/test IDs and split any item that no longer fits an independent review.
- A task cannot close on code alone: formatter/linter/build, required tests, security/database/performance review, docs and residual risks are its Definition of Done.
- No task may introduce a real credential/database fixture, production implementation during this planning request, or scope beyond its stated `Out of scope` without a new user decision.
