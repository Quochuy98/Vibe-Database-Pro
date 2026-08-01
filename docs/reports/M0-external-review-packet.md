# M0 external review packet

Status: ready for independent review; `0/8` reviewer slots completed; no M0
exit, dependency adoption or production implementation authorized

Packet date: 2026-08-01

## 1. Purpose and authority boundary

This packet turns the remaining DF-M0-008 and DF-M0-009 external gates into a
single attributable review workflow. It identifies immutable source evidence,
the exact reviewer roles, review questions, allowed results and closure rules.

It does **not** provide a signature, legal opinion, dependency approval,
accessibility pass, security exception or implementation request. The evidence
author, an agent, scanner or risk owner cannot fill an independent review slot
on its own behalf. A reviewer who concurs accepts the current fail-closed or
conditional record only; concurrence cannot override a missing exact identity,
advisory, runtime test, safety invariant or milestone gate.

Do not commit privileged legal advice, private reviewer contact details,
signatures, credentials, database data or customer information. Record only a
non-privileged disposition summary and, where appropriate, a counsel-controlled
reference.

## 2. Pinned evidence under review

| Scope | Branch and commit | Primary evidence | Current outcome |
| --- | --- | --- | --- |
| DF-M0-008 dependency dossiers | `codex/m0-dependency-dossiers` at `a5948a7bf9a46fbe1e01d93dc2f21a862a865a63` | [Dossier](DF-M0-008-dependency-adoption-dossiers.md), [policy](../DEPENDENCY_POLICY.md), [ADR-0015](../adr/0015-m0-dependency-disposition.md) | `0 approve / 10 defer / 3 reject`; adoption false; DoD false |
| DF-M0-009 wireframe review | `codex/m0-wireframe-review` at `42bbdf54384895d862594daef3324de22689cce9` | [Review](DF-M0-009-wireframe-accessibility-review.md), [wireframes](../UX_WIREFRAMES.md), [ADR-0016](../adr/0016-m0-wireframe-accessibility-disposition.md) | Five conditional wireframes; 12 actions; M1/M2 authority false; DoD false |
| Review corrections overlay | `codex/m0-external-review-packet` at `2fb7d0618f2535a47d8899416cdf7e6aa42744d0` | Corrected reports, ADRs and machine-readable evidence/provenance referenced by this packet | Clarifications/corrections applied; all eight independent review slots remain pending |

Review the three named commits, including the correction overlay, not a mutable
branch tip. If evidence changes, the review result must name the new commit and
re-evaluate affected questions.

## 3. Planning-completeness preflight

Before preparing this packet, the repository planning baseline was checked
against `MASTER_PROMPT.md` sections 15–21:

| Check | Result |
| --- | --- |
| Required root/docs/ADR files | `24/24` present |
| Required roadmap milestones | `8/8`; every milestone has Goal plus all nine required scope/review/exit sections |
| Backlog schema | `47/47` items contain all 14 required fields; IDs unique |
| Required decision register | `20/20` ordered decisions, each with options, recommendation/reasons, trade-offs/risks and revisit condition |
| Required risk topics | All 21 mandated topics present; 34 total rows with probability, impact, detection, mitigation, contingency and owner |
| Feature cards | `17/17` ordered cards |

This preflight proves document structure and traceability, not external
acceptance or executable behavior.

The machine-readable preflight is scoped to correction commit
`2fb7d0618f2535a47d8899416cdf7e6aa42744d0`. The pinned DF-M0-008 commit
`a5948a7…a63` and DF-M0-009 commit `42bbdf5…5e9` are sibling commits over common
base `d628753…f3bb`; the former is not an ancestor of the latter. The packet
commit contains corrected descendants of the pinned DF-M0-008 report/data
lineage; it is not byte-identical to that pinned content and does not portray
the relationship as Git ancestry or a merge. Counts above deliberately exclude
DF-M0-008/009 completion, external review closure and executable behavior.

## 4. DF-M0-008 review lanes

### Independent engineering — `M0R-DEP-ENG`

Confirm candidate counts/dispositions, distinguish the five identity gaps from
the seven graph gaps, reconstruct the historical locks/resolution, verify raw
hashes/source policy and confirm no spike or standalone size result is promoted
as product evidence.

Concurrence accepts the engineering record only. Every future exact version or
source still needs an adoption change, minimal feature set, lock graph,
integration evidence and normal review.

### Independent security — `M0R-DEP-SEC`

Verify multi-source advisory behavior and the RustSec/repository blind spot;
the exact `685d32f…922` advisory-database checkout and offline/no-fetch binding
for both historical scanners; the three exact SSH-related rejections;
provenance/SBOM reachability; advisory ownership/disable paths; and the rule
that a clean scanner cannot override an authoritative affected range or missing
runtime evidence.

Concurrence is not approval for a deferred dependency, SSH, updater, telemetry
SDK or release artifact.

### Qualified legal — `M0R-DEP-LEGAL`

Review exact license files, notices, commercial redistribution/attribution and
hosted-service/privacy terms for selected identities. Unselected identities
remain deferred. Final DataForge license text and Community/Pro terms are a
separate Product + Legal decision.

Only a non-privileged result summary belongs in this repository. A permissive
license label or packet-level concurrence is not blanket approval of future
versions or transitive artifacts.

## 5. DF-M0-009 review lanes

| Review ID | Independent role | Required disposition scope |
| --- | --- | --- |
| `M0R-UX-PRODUCT` | Product | Hierarchy, terminology, consequences, capability truth, result limits, unknown outcomes, 12 actions and M1/M2 ownership |
| `M0R-UX-DESIGN` | macOS interaction design | Native interaction intent, focus/default behavior, pane/resize/localization and independent visual identity |
| `M0R-UX-ACCESSIBILITY` | Accessibility/VoiceOver | Forward/reverse focus, announcements, keyboard parity, editor/grid semantics, VoiceOver plan, contrast/non-color/motion/larger text |
| `M0R-UX-DB-SAFETY` | Database Safety | Production/read-only context, canonical preview digest, typed confirmation, stale revalidation, transactions/pending edits, cancellation-vs-execution truth |
| `M0R-UX-SECURITY` | Security | SSH unavailable/direct-phase truth, authentication-vs-Keychain storage, bounded unstored-secret lease, serialized cancel/auth/close/error ordering, same-path safeguards and no secret/insecure bypass |

Static review closure does not constitute `xcodebuild`, UI/AX, manual
VoiceOver, contrast, localization, database or runtime evidence. M1 owns the
shared shell, WF-01 and non-live WF-02; M2 owns live WF-02 and WF-03/04/05.

## 6. Allowed results and capture rules

Each review slot records exactly one result:

- `concur`: agree with the current fail-closed/conditional record within the
  lane's stated scope;
- `changes_required`: identify an actionable correction, owner and evidence
  required for re-review; or
- `defer`: the reviewer cannot conclude until a named input or authority is
  available.

For an attributable update to
[`review-status.json`](data/M0-external-review/review-status.json):

1. Change the slot `status` from `pending` only after receiving the review.
2. Record `result`, an appropriate public `reviewer_reference` and ISO review
   date; never invent or infer them.
3. Capture corrections/deferrals as owned actions with a revisit trigger in
   the source dossier/matrix, not only in this packet.
4. Update the source report/ADR and their DoD flags only after every closure
   rule is actually satisfied.
5. Recompute the raw status hash and rerun JSON, links, secret/personal-path
   and diff validation.

A task-level `concur` never changes candidate-level `defer`/`reject`, enables
SSH, marks accessibility runtime passed, or authorizes production code.

## 7. Current fail-closed status

| Task | Required slots | Completed | Pending | Definition of Done |
| --- | ---: | ---: | ---: | --- |
| DF-M0-008 | 3 | 0 | 3 | false |
| DF-M0-009 | 5 | 0 | 5 | false |
| **Total** | **8** | **0** | **8** | M0 exit not authorized |

The safe next action is to give this packet and the pinned commits to qualified
independent reviewers. Until attributable results arrive, dependency adoption,
M1/M2 production UI and overall M0 exit remain blocked by their existing gates.

## 8. Durable machine-readable status

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`review-status.json`](data/M0-external-review/review-status.json) | Eight pending independent review slots, evidence questions, authority limits and closure rules | `de4da200bfafa78cf62e23a0d329bbd1d780783293bb1717f553a882a2dfbf47` |
