# ADR-0016: Conditionally retain the M0 shell wireframes

- **Status:** Accepted for M0 planning by ADR-0017 owner waiver; production UI
  and executable accessibility/security evidence gated
- **Date:** 2026-08-01
- **Supersedes:** None; refines the M1/M2 UI evidence required by ADR-0001 and
  the milestone backlog
- **Related:** ADR-0001, DF-M0-009, UF-01/02/04/05/06, R-18, R-20

> **Later decision:** ADR-0017 waives the five independent static-review lanes
> as an M0 exit prerequisite. It does not supply accessibility/security
> approval or alter the executable M1/M2 evidence required below.

## Context

ADR-0001 selects a SwiftUI shell with focused AppKit components, but it does
not decide the shell's exact information hierarchy, focus lifecycle,
accessibility semantics or safety copy. `UX_WIREFRAMES.md` supplies five
original low-fidelity planning flows:

- empty workspace/restoration;
- connection/trust;
- query editor/result grid;
- production destructive confirmation; and
- active-transaction/pending-edit close protection.

DF-M0-009 reviewed those flows against the user flows, performance budget,
database safety, security model and current Apple accessibility/focus/alert
guidance. The complete result is
[`DF-M0-009-wireframe-accessibility-review.md`](../reports/DF-M0-009-wireframe-accessibility-review.md).

This review cannot render or operate macOS UI. The repository has no production
Xcode project, accessibility tree, palette, localization bundle or UI test
target, and no independent Product, macOS interaction design,
Accessibility/VoiceOver, Database Safety or Security reviewer has signed the
artifact.

## Findings

The information hierarchy and main safety invariants are suitable planning
inputs, but the initial text had preventable ambiguity:

- SSH controls/phases appeared even though ADR-0012/0015 keep SSH unsupported;
- authentication method was conflated with Keychain storage and did not state
  the non-persistence contract for an unstored secret;
- `Stop` and `rows [200]` did not freeze cancellation/limit meaning, and
  cancellation outcome was not separate from execution outcome;
- modal/error/async/pane focus transitions were incomplete;
- VoiceOver regions did not establish detailed roles/values/actions/manual
  navigation;
- appearance modes had no executable palette/contrast evidence;
- localization/larger-text reflow priorities were unstated;
- unknown-outcome close needed a separate target/transaction-bound step; and
- the shortened destructive preview digest did not define its user/AX role.

Ten low-fidelity contract revisions address the textual ambiguity. Twelve
tracked actions remain because only an executable UI can prove keyboard,
VoiceOver, contrast, resizing, localization and native control behavior;
independent review could add assurance but is owner-waived for M0 by ADR-0017.
The matrix has 0 Critical, 5 High, 6 Medium and 1 Low item.

## Decision

1. **Conditionally retain all five wireframes as original planning artifacts.**
   They define hierarchy and safety intent, not pixels, assets or production
   control implementation.
2. **Adopt the revised shared focus lifecycle as the M1/M2 contract.** Forward/
   reverse traversal skips hidden regions; modal entry uses the consequence or
   safest review action; Escape keeps work open; async announcements do not
   steal editor focus; closing returns to the initiating control.
3. **Require capability-truthful UI.** The connection wireframe shows SSH as
   unsupported until a future exact implementation passes its ADR. Direct
   test/connect paths omit SSH phases and host-key errors; UI cannot make a
   conditional layout look available.
4. **Separate authentication from credential storage.** Database auth method
   is adapter capability; Keychain is storage. With storage off, the interactive
   `ConnectionAttempt` service solely owns one non-renewable lease. Its
   provisional deadline is the earlier of the action timeout and 60 seconds;
   success, cancellation request, authentication failure, terminal error,
   connection close or deadline revokes it. Retry creates a new lease. Cleanup
   denies later access, releases every owned reference and overwrites
   lease-owned mutable buffers where practical, while explicitly treating Swift
   and driver/runtime copies as best-effort rather than guaranteed zeroization.
   The secret never enters a profile, draft, history or log, and production
   implementation remains gated on Security review and lifecycle/canary tests.
   A single serialized `ConnectionAttempt`/attempt ID defines race ordering:
   accepted cancel records `requested`, revokes/denies secret access, publishes
   `Cancelling`, then forwards driver cancellation. Success linearized first
   remains success; cancel linearized first makes later success stale, prevents
   Connected and closes any late session. Explicit driver acknowledgement alone
   yields `confirmed`/`Cancelled`; close first yields `connectionClosed` plus
   unknown execution outcome; a typed terminal error remains Failed;
   `unsupported` fails/closes without reusing the lease; teardown deadline
   remains unconfirmed/timeout. Repeated cancel is idempotent, stale callbacks
   are ignored and the first terminal attempt result is monotonic.
5. **Freeze cancellation and result-limit terminology at intent level.** Use
   `Cancel Query`; report `requested`/`confirmed`/`connectionClosed`/
   `unsupported` cancellation separately from execution outcome, and allow
   `Cancelled` only after confirmation. Distinguish initial fetch limit, loaded
   count, limit reached, load more and stream export.
6. **Keep destructive and unknown-outcome actions non-default.** Pointer,
   menu, command palette and keyboard share one safety path. Unknown close has
   a separate exact target/transaction acknowledgement and cannot be Return or
   Escape.
7. **Require semantic, non-color, motion-independent state.** Light/Dark,
   Increase Contrast, Differentiate Without Color, Reduce Motion and larger
   text must preserve meaning, target, consequence, cancellation and disabled
   reason.
8. **Do not call this an accessibility approval.** Automated AX assertions,
   manual VoiceOver, keyboard events, palette contrast, pseudo-localization,
   resize and performance evidence remain owning M1/M2 gates.
9. **Do not authorize production UI.** A separately requested implementation
   for either milestone may begin only after the project gate is explicit;
   owning executable evidence remains required even though ADR-0017 waives the
   static external-review lanes.

## Historical external-review plan and required milestone evidence

ADR-0017 later waived the five independent roles below as an M0 exit
prerequisite. They remain the historical review plan and may still be used
voluntarily; none is represented as completed:

- Product/Design accepts or explicitly dispositions terminology, hierarchy,
  button grouping and the 12 actions;
- Accessibility reviews focus order, labels/help/errors, live announcements,
  custom editor/grid AX contract and manual VoiceOver plan;
- Database Safety/Security approves Production/read-only/destructive/
  transaction/unknown-outcome language and no-bypass behavior;
- macOS UI defines native system controls, roles, text styles and collapse/
  minimum-size behavior without turning this ADR into a pixel spec; and
- QA records exact UI/keyboard/AX/snapshot/pseudo-localization/performance test
  IDs against their owning milestone when an executable target exists.

Executable ownership is deliberately split: M1 owns the shared shell, WF-01
and non-live profile portion of WF-02; M2 owns live connection/trust behavior
in WF-02 and query/destructive/transaction flows WF-03/04/05. Static external
disposition does not mark any executable lane as passed.

Each unresolved action keeps its owner and revisit trigger in
`review-matrix.json`. A missing reviewer is not represented by checking a box
on their behalf.

## Consequences

- M1/M2 receive a concrete, testable focus/accessibility/safety contract while
  retaining freedom to design an original native visual identity.
- Unsupported SSH cannot leak into a visible enabled flow.
- Destructive/transaction safety language is treated as behavior, not visual
  polish or a color choice.
- The custom grid/editor require both semantic AX tests and manual VoiceOver;
  metadata assertions alone cannot pass.
- ADR-0017 sets `df_m0_009_definition_of_done_met=true` only at
  planning-artifact scope; every executable action remains owned by M1/M2.
- No database, credential, source-code, asset or production entitlement change
  results from this ADR.
