# DF-M0-009 — Shell wireframe and accessibility review

Status: engineering review complete; five wireframes conditionally retained;
external M0 review waived by ADR-0017; executable UI evidence remains open

Review date: 2026-08-01

Evidence base: `docs/UX_WIREFRAMES.md`, `docs/USER_FLOWS.md`,
`docs/PERFORMANCE_BUDGET.md`, ADR-0001 and the current safety/security plans

## 1. Decision question and scope

DF-M0-009 asks whether the original low-fidelity shell, connection,
editor/grid, destructive-confirmation and transaction-close wireframes are
specific enough for their future M1/M2 macOS UI owners to preserve keyboard,
VoiceOver, appearance, resizing, localization and database-safety invariants.

This is a static design review. It does not create SwiftUI/AppKit production
views, assets, database calls, Keychain access, pixel measurements or a copy of
another product. The ASCII geometry communicates hierarchy only.

## 2. Outcome

All five wireframes are **conditionally retained for planning** after ten
low-fidelity contract revisions. The review records 12 tracked actions:

- 0 Critical;
- 5 High;
- 6 Medium; and
- 1 Low.

No executable accessibility or visual claim is made. In particular:

- ASCII cannot prove contrast, clipping, native control roles, VoiceOver
  navigation, keyboard events or frame performance;
- the repository has no production UI or UI test target; and
- no independent human reviewer has signed the artifact; ADR-0017 waives those
  reviews only as an M0 planning gate.

Therefore:

```text
engineering_review_status = complete
external_review_status = owner-waived for M0; no sign-off claimed
external_review_complete = false
external_review_required_for_m0_exit = false
df_m0_009_definition_of_done_met = true at planning-artifact scope
m1_ui_implementation_allowed_by_this_review = false
m2_ui_implementation_allowed_by_this_review = false
```

The safe result is a more precise planning artifact and milestone-owned test
contract, not permission to implement M1 or M2 production UI.

## 3. Planning revisions applied

The engineering review updated `UX_WIREFRAMES.md` without turning it into a
pixel specification:

1. Current SSH capability truth is explicit: WF-02 shows
   `Unsupported — no implementation adopted`, and current direct test/connect
   paths omit SSH phases and host-key errors, consistent with ADR-0012/0015.
2. TLS/CA terminology is expanded; database authentication method and
   Keychain storage are separate. For an unstored secret, the interactive
   `ConnectionAttempt` service solely owns one non-renewable lease whose
   provisional deadline is the earlier of the action timeout and 60 seconds.
   Success, cancellation request, authentication failure, terminal error,
   connection close or deadline revokes it; retry acquires a new lease. Cleanup
   denies later access, releases owned references and overwrites lease-owned
   mutable buffers where practical, while Swift and driver/runtime copies remain
   a best-effort lifetime boundary rather than a zeroization claim. Security
   review and fake-clock/trigger/race/use-after-revoke/canary tests remain open.
   One serialized `ConnectionAttempt` and attempt ID orders every race. Accepted
   cancel records `requested`, revokes/denies secret access, publishes
   `Cancelling`, then forwards driver cancel/close; revocation itself never
   confirms server stop. Success linearized first stays successful. Cancel
   linearized first makes later success stale, suppresses Connected and closes
   any late session. Only explicit driver acknowledgement yields `confirmed`
   and permits `Cancelled`; close first yields `connectionClosed` plus unknown
   outcome, a typed terminal error remains Failed, `unsupported` fails/closes
   without reusing the lease, and teardown deadline remains unconfirmed/timeout.
   Repeated cancel is idempotent, wrong/late-attempt callbacks are ignored and
   the first terminal attempt outcome is monotonic.
3. `Stop` is renamed `Cancel Query`; `requested`/`confirmed`/
   `connectionClosed`/`unsupported` cancellation outcomes are separate from
   execution outcomes, and only confirmation permits `Cancelled`.
4. `rows [200]` is replaced by `initial fetch limit [200 rows]`; loaded count,
   limit-reached and explicit load-more/export choices are separate concepts.
5. A shared focus-lifecycle table specifies safe initial focus, reverse order,
   modal return, error, async completion, pane collapse and Escape behavior.
6. VoiceOver announcements must be coalesced and must not steal editor focus.
7. Appearance text now covers semantic tokens, non-color traits, Increase
   Contrast, Differentiate Without Color and motion-independent state.
8. Larger text and localization reflow may never hide target, consequence,
   transaction, disabled reason or cancellation.
9. Unknown transaction outcome close now opens a separate exact
   target/transaction acknowledgement step and cannot be Return/Escape/default.
10. The destructive preview uses a short correlation identity plus details/
    programmatic access to the canonical digest, full identity and stale reason;
    users and VoiceOver are not forced to compare/read the digest manually.

These revisions resolve ambiguity in the planning contract. They do not close
the corresponding executable M1/M2 evidence gates.

## 4. Wireframe dispositions

| Wireframe | User-flow trace | Accepted planning controls | Remaining gate | Disposition |
| --- | --- | --- | --- | --- |
| WF-01 Empty/restoration | UF-01 | Safe first focus, heading/actions, disconnected restore, no auto-run/credential/transaction restore | Focus return, live announcement, larger/localized text and executable launch budget | Conditional |
| WF-02 Connection/trust | UF-02/03 | Capability-driven fields/phases, separate auth/storage, leased unstored secret, direct-mode TLS truth, persistent textual Production context | M1 non-live profile semantics; M2 live trust/cancel behavior; external copy review | Conditional |
| WF-03 Editor/grid | UF-04/09/12 | Honest cancellation, connection/read-only/transaction context, NULL/empty/not-loaded distinction, stable theme state | AX grid/editor semantics, loaded/limit behavior, keyboard virtualization, palette/contrast and timing | Conditional |
| WF-04 Destructive confirmation | UF-05 | Textual target/consequence/transaction/SQL, typed token, stale revalidation, no shortcut/color bypass | Full preview identity/AX contract, safe focus and localization/reflow execution | Conditional |
| WF-05 Transaction close | UF-06 | Safest-first, no auto-commit, honest unknown state, pending edit preservation | Separate acknowledgement execution, dangerous-default prevention, multi-tab/target navigation | Conditional |

## 5. Findings and owners

| ID | Sev. | Finding / decision | Owner | Revisit trigger |
| --- | --- | --- | --- | --- |
| UX-001 | High | Initial SSH controls/phases contradicted current capability; artifact now shows unsupported state and direct paths omit SSH/host-key results | Connections + Security | A future SSH ADR adopts an exact implementation |
| UX-002 | Medium | TLS/CA labels and auth-vs-Keychain storage semantics were ambiguous; contract now separates them and defines provisional owner/deadline/revocation/best-effort cleanup for an unstored secret | Connections + Security + Content design + Accessibility | Before M1/M2 connection copy/API freeze |
| UX-003 | Medium | Cancellation wording conflated cancellation and execution outcomes; `Cancel Query` now uses the canonical separate taxonomy | Query UX + Database Core | M2 cancellation state review |
| UX-004 | High | `rows [200]` confused page/fetch/hard limit; initial-fetch and loaded/limit actions now separated | Query UX + Performance | Before M2 result streaming UI |
| UX-005 | High | Modal/error/async/collapse/reverse focus lifecycle was incomplete; shared table added, executable proof open | macOS UI + Accessibility | Before M1 shell state/API acceptance |
| UX-006 | High | Named regions alone do not prove roles/values/actions/coalescing/manual navigation | Accessibility + QA | When executable views/test identifiers exist |
| UX-007 | Medium | No actual palette tokens/contrast measurements exist | Visual design + Accessibility | When M1 theme tokens are proposed |
| UX-008 | Medium | Localization expansion/reflow evidence is absent; safety text priority now explicit | Content design + Localization QA | Before localized M1 snapshots/minimum-size acceptance |
| UX-009 | High | Direct unknown-outcome close was too easy; a separate target/transaction-bound step is now required | Database Safety + Product design | Before transaction close implementation |
| UX-010 | Medium | Short preview digest did not define accessible/full identity; details contract added | Database Safety + Accessibility | Destructive-preview domain contract review |
| UX-011 | Low | Reduce Motion initially covered panes only; state must remain textual without decorative motion | macOS UI + Accessibility | M1 animation/progress selection |
| UX-012 | Medium | Larger macOS text/minimum-size behavior remains executable evidence | macOS UI + Accessibility | M1 typography/minimum-window review |

No issue permits weakening a safety mechanism. An unresolved High item blocks
the affected M1/M2 flow; it is not converted to an ordinary visual polish
ticket.

## 6. Keyboard and focus walkthrough contract

The static walkthrough passes only as a **specified intent**:

- forward and reverse region traversal are deterministic and skip hidden
  regions;
- command palette, menu, toolbar and shortcut reach one application intent;
- modal entry starts at consequence/safest review control, never destructive
  Apply/Close;
- Escape cancels or keeps work open; Return cannot execute a dangerous default;
- closing a modal returns to the exact initiating control when possible;
- errors announce a summary without erasing field context; and
- async progress/cancel/error announcements do not steal editor input.

M1 must test shared shell, WF-01 and non-live WF-02 paths; the owning M2 tasks
must test live WF-02 and WF-03/04/05 with actual keyboard events and focus
identifiers. Text review cannot report keyboard navigation as passed.

## 7. VoiceOver and appearance contract

Use native AppKit/SwiftUI controls where appropriate because standard controls
provide platform accessibility behavior. The custom editor/grid still need
explicit roles, names, values, actions, stable row/column/header semantics and
manual VoiceOver navigation.

Apple's guidance says important meaning must not rely on color alone when the
user enables Differentiate Without Color, and macOS exposes increased contrast
and reduced-motion preferences. The artifact therefore requires text/icon/
shape fallbacks, semantic colors and motion-independent busy/cancel state.
Actual colors must later meet the repository's 4.5:1 ordinary-text threshold;
an ASCII diagram supplies no contrast evidence.

Required executable matrix, run by each owning M1/M2 task for its flows:

- Light and Dark appearance;
- standard and Increase Contrast;
- Differentiate Without Color;
- Reduce Motion;
- larger text/accessibility display settings;
- Full Keyboard Access and reverse traversal;
- automated AX role/name/value/action assertions; and
- manual VoiceOver navigation with editor and logical virtual grid.

## 8. Resize and localization contract

The future UI must test minimum/current/large windows with sidebar, inspector
and result panel expanded, collapsed and resized. A pane may collapse before
the central editor becomes unusable, but no fixed pixel value is approved by
this review.

Pseudo-localization must expand:

- production environment/target;
- destructive consequence and typed-token instruction;
- transaction/unknown outcome and pending edit count;
- cancellation/error/disabled reason; and
- connection trust/Keychain explanation.

Those fields wrap or reflow; they are never silently truncated. Right-to-left
layout is reviewed where the chosen localization set supports it. Focus order
follows logical reading order rather than hardcoded screen coordinates.

## 9. Safety and security review

Accepted planning invariants:

- no wireframe calls a database, driver or Keychain API;
- restoration never auto-runs, reconnects or restores a transaction;
- Production/read-only/transaction/target/cancel context is textual;
- pointer and keyboard commands share the same safety path;
- destructive apply revalidates exact target/SQL/capability/read-only state and
  the canonical preview digest;
- close never commits; network loss never triggers a write retry;
- unsupported capability is absent or explicitly explained; and
- `NULL`, empty and not-loaded remain different values.

There was no database write, credential, TLS/SSH connection, export, clipboard
or production endpoint in this review. Database safety is preserved by keeping
the artifact non-executable and making the future safeguards explicit.

## 10. Acceptance mapping

| DF-M0-009 requirement | Result | Evidence / remaining work |
| --- | --- | --- |
| Review all five wireframes | Pass | Five conditional dispositions and per-flow tests recorded |
| Terminology, focus, Production/read-only language | Pass at planning-contract level | Ten artifact revisions applied; executable behavior remains M1/M2 |
| Keyboard/focus walkthrough | Specified, not executed | Shared lifecycle and per-flow test intents exist; no UI target |
| Accessibility labels/VoiceOver | Partial | Region/control semantics specified; AX tree and manual VoiceOver absent |
| Light/Dark/contrast/non-color/motion | Partial | Semantic rules specified; no palette/runtime measurement |
| Resize/localization | Partial | Priority/reflow contract and test matrix exist; no executable layout/bundle |
| UF-01/02/04/05/06 traceability | Pass | Every required user flow maps to one or more reviewed wireframes |
| Product/Design/Accessibility/Database-Safety/Security disposition | Waived for M0 only | ADR-0017 records no sign-off; all 12 actions retain owner/revisit trigger and executable gates |
| Milestone ownership current | Prepared | M1 owns shared shell/WF-01/non-live WF-02; M2 owns live WF-02 and WF-03/04/05 |

`df_m0_009_definition_of_done_met=true` at planning-artifact scope under
ADR-0017. No Product, macOS interaction design, Accessibility/VoiceOver,
Database Safety or Security sign-off is claimed, and implementation authority
remains false.

## 11. Not tested

- No `xcodebuild`, Swift compile, UI test, snapshot, Accessibility Inspector,
  VoiceOver session or Instruments run; there is no production source/project/
  test target and full Xcode was not introduced by this documentation task.
- No color, contrast, typography, clipping, localization bundle, RTL layout or
  native control rendering exists.
- No frame/launch/cancel timing is claimed from ASCII.
- No executable credential-lease owner, 60-second/action deadline, revocation,
  ordered cancellation race, late-session close, cleanup or seeded-canary
  behavior exists; those remain provisional Security and owning-milestone gates
  aligned with DF-M0-007's best-effort memory result.
- No Product, macOS interaction design, Accessibility/VoiceOver, Database
  Safety or Security sign-off exists.

## 12. Durable evidence

| Artifact | Purpose | SHA-256 |
| --- | --- | --- |
| [`review-matrix.json`](data/DF-M0-009/review-matrix.json) | Five wireframes, shared contract, owner-waiver scope, 12 findings, owners, triggers and tests | `41a8642cd51845e20a3aa59fceaa577d570c570badc80ada30fa59c6cc75d756` |

## 13. Primary references

- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)
- [Apple HIG: VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover/)
- [Apple HIG: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/)
- [Apple HIG: Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts/)
- [Apple HIG: Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons/)
- [Apple: Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [Apple: Differentiate Without Color](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshoulddifferentiatewithoutcolor)
