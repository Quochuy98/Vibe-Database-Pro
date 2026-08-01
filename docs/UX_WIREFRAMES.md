# DataForge UX wireframes and accessibility annotations

Status: Low-fidelity planning artifact; engineering review complete;
independent Product/Design/Accessibility/Database-Safety/Security review
required before milestone implementation

Last updated: 2026-08-01

These wireframes define original information hierarchy and safety language for
the first shell. They are not pixel specifications, assets, or an imitation of
another database product. Geometry is intentionally approximate; M1 must
measure the shared shell/WF-01/non-live WF-02, and owning M2 tasks must measure
live WF-02 plus WF-03/04/05, against the resizing, larger-text/accessibility-
display, keyboard, VoiceOver and performance budgets.

## Shared shell contract

```text
+--------------------------------------------------------------------------+
| DataForge | Workspace title       [New] [Command] [Settings]             |
+----------------------+-----------------------------------+---------------+
| Connections           | Tabs / document title             | Inspector      |
|  ▸ Development        |                                   | context        |
|  ▸ Staging            |        editor / object view       | properties     |
|  ● PRODUCTION         |                                   | capabilities   |
|                       +-----------------------------------+---------------+
| Object tree (lazy)    | Results | Messages | Plan | Jobs                 |
|                       +-----------------------------------+---------------+
|                       | connection • database • read-only • transaction   |
+----------------------+-----------------------------------+---------------+
```

Annotations:

- The window title, toolbar context and bottom status line repeat the active
  connection/environment in text; color and icons are supplementary only.
- Sidebar, center document, inspector and bottom panel are independently
  resizable. Focus order is sidebar → tab/editor → result panel → inspector →
  status actions, skipping hidden/collapsed regions. Reverse traversal is the
  exact inverse, with a visible focus ring and no fixed minimum that prevents a
  usable editor.
- VoiceOver exposes named regions (`Connections`, `Document`, `Results`,
  `Inspector`, `Status`), coalesces repeated progress updates and announces
  busy/empty/error/cancelling/partial/unknown state without stealing focus.
- `⌘K` opens the command palette; every toolbar action has a menu command and
  an accessible label. Menu, palette, toolbar and shortcut invoke the same
  application intent and safety path.
- Light/Dark/System accent, Increase Contrast and Differentiate Without Color
  use semantic tokens plus text/icon/shape traits. Reduce Motion removes
  decorative pane/progress transitions without hiding state changes.
- Larger macOS text/accessibility settings and pseudo-localized strings reflow.
  Target, consequence, transaction state, disabled reason and cancel action are
  never truncated away. Pane collapse preserves the initiating logical focus.

### Shared focus lifecycle

| Event | Required focus behavior |
| --- | --- |
| Open ordinary flow | First incomplete field or primary safe action |
| Open destructive/close warning | Consequence heading or safest non-destructive action; never Apply/Close |
| Validation error | Error summary announces once, then focus moves to the first invalid control on user navigation |
| Async success/failure/cancel | Announce status without stealing editor input; explicit View details can move focus |
| Close modal | Return to the exact initiating control when it still exists; otherwise the owning region heading |
| Collapse/hide region | Move to the nearest owning region/control, never a dangerous action |
| Escape | Cancel/keep work open; never apply, discard, commit or acknowledge unknown outcome |

## WF-01 — Empty workspace and restoration

```text
+--------------------------- DataForge ----------------------------+
| [Connections] [Documents]                              [⌘K]       |
|                                                                  |
|                 No workspace is connected                         |
|       [New connection]   [Open database file]   [Open SQL file]   |
|                                                                  |
|  Restored drafts appear as disconnected tabs; nothing auto-runs.  |
+------------------------------------------------------------------+
```

The first focus lands on `New connection`. The empty-state message is a
heading, not placeholder text; VoiceOver announces the three buttons and their
keyboard equivalents. Restored drafts show a text badge `Disconnected` and a
repair action if their non-secret reference is missing. No credential or live
transaction is restored. Completing or cancelling repair returns focus to the
originating disconnected draft; background restoration never steals focus.

## WF-02 — Connection and trust form

```text
+---------------------- New connection ----------------------------+
| Adapter [PostgreSQL ▾]     Environment [Development ▾]            |
| Host [                       ] Port [      ] Database [          ] |
| Authentication method [Password ▾]                                |
| Credential storage [Store secret in Keychain ✓]                    |
| Transport security (TLS) [Required ✓]                              |
| Certificate authority (CA) [System roots ▾] [Choose CA…]          |
| SSH tunnel [Unsupported — no implementation adopted]              |
|                                                                  |
| [Cancel]                         [Test connection] [Save profile] |
+------------------------------------------------------------------+
```

Only capabilities declared by the adapter reveal fields. Authentication method
and credential storage are separate concepts. With Keychain storage off, a
secret receives only a short in-memory lease for the current test/connect
action; Save profile persists non-secret metadata only and never puts the
secret in a draft, history, log or ordinary profile model.

`Test connection` reports only configured layers and has a visible Cancel
action. In the current direct-only contract it reports TLS, database
authentication and selected-database phases—never an SSH phase or host-key
result. Invalid certificate/hostname is an error heading with the consequence
and next action; there is no global insecure bypass. Choosing `Production`
adds a persistent text badge and requires the same keyboard-accessible
confirmation path as a mouse click.

ADR-0012/0015 currently leave SSH unadopted, so a production UI must hide or
disable the SSH row with an explicit unsupported explanation until a future
candidate passes every re-entry gate. The disabled row above documents current
capability truth. A future field layout for known-host/auth/jump-host settings
remains conditional and is not evidence that SSH is available. Only after an
exact SSH implementation is adopted **and configured for this profile** may
Test connection add an SSH phase or changed-host-key error.

Every abbreviation has expanded visible or accessibility help, every field
has a programmatic label, and an error is associated with both its field and a
consequence/action summary. Returning from Test connection restores focus to
that action or the first failing field without exposing credential content.

## WF-03 — Query editor, result stream and grid

```text
+----------------- Query — Development / app ----------------------+
| [Run Query ⌘R] [Cancel Query ⌘.] [Commit] [Rollback]              |
| timeout [30s]  initial fetch limit [200 rows]                     |
|  1 | SELECT ...                                                   |
|  2 |                                                               |
|--------------------------------------------------------------------|
| Results (200 loaded) | Messages | Explain                          |
| key | name       | amount | created       | NULL / not loaded      |
| ... virtualized rows ...                                        ↕ |
| connection • schema • transaction: idle • Read-only              |
+------------------------------------------------------------------+
```

Typing and selection stay in the editor while parsing/completion runs off the
main actor. `Cancel Query` changes to `Cancelling` within the UI budget. It
reports cancellation outcome separately as `Confirmed`,
`Requested — server outcome not yet known`,
`Connection closed — execution outcome unknown` or `Unsupported`. Execution
is shown as `Cancelled` only after adapter confirmation; otherwise it reports
`Completed before cancellation`, `Failed` or `Outcome unknown` as supported by
evidence. A closed connection is never presented as proof that the server
stopped or rolled back. The loaded count, initial fetch limit,
limit-reached state and explicit Load more/stream export choices are distinct.
The grid
announces row/column headers, sort state, selection and loading/partial/error
state. NULL, empty and not-loaded values have text/icon/tooltip fallbacks, and
theme changes preserve selection, scroll and pending edits.

## WF-04 — Production/destructive confirmation

```text
+-------------------- Review destructive operation ----------------+
| PRODUCTION  PostgreSQL / finance                                 |
| Risk: HIGH — unconditional DELETE may affect an unknown row count |
|                                                                  |
| Target: db.schema.table     Transaction: not guaranteed           |
| SQL preview (immutable)                                        ▾ |
| Preview identity: 8F… [Details] [Copy generated SQL]             |
|                                                                  |
| Type  DELETE finance.table  to confirm: [                       ] |
| [Back]                                      [Apply operation]     |
+------------------------------------------------------------------+
```

The dialog states target, consequence, SQL, transaction behavior and preview
freshness in text. `Apply operation` is disabled until the typed target token
matches; stale target/SQL/capability/read-only state invalidates the preview.
VoiceOver announces the risk heading and disabled reason, and the keyboard
shortcut enters this same dialog rather than bypassing it. Red is never the
only warning signal. The core binds and revalidates a canonical preview digest
over the exact target/SQL/transaction/capability context. The short identity is
a human correlation label; Details exposes the full identity, canonical digest
and stale reason programmatically without forcing VoiceOver to read a long
digest by default. Users are never asked to validate cryptography manually.

## WF-05 — Transaction and pending-edit close protection

```text
+-------------------- Close query tab? -----------------------------+
| Development / app   Transaction: ACTIVE (tx-42)                   |
| 3 pending row edits are not applied. Closing can change outcome.  |
|                                                                  |
| [Keep tab open] [Review pending SQL] [Roll back and close]        |
| [Close with unknown outcome…]                                     |
+------------------------------------------------------------------+
```

The safest action is first in focus order and is the default only for Escape;
close never silently commits. If rollback is unsupported or the connection is
lost, the dialog says `Outcome unknown` and offers read-only reconciliation,
not automatic retry. Pending edits remain recoverable until the user chooses a
discard/rollback path. VoiceOver reads the transaction ID, target and count of
pending edits; keyboard navigation reaches every action without relying on
color. `Close with unknown outcome…` opens a separate consequence step bound
to the exact target and transaction; it is never triggered by Return or Escape
and requires explicit acknowledgement before closing.

## Review and acceptance checklist

- [x] Engineering review records terminology, focus, VoiceOver, appearance,
      resize/localization and safety actions in
      [DF-M0-009 evidence](reports/DF-M0-009-wireframe-accessibility-review.md).
- [ ] Product, macOS interaction design, Accessibility/VoiceOver, Database
      Safety and Security reviewers accept or explicitly disposition the
      hierarchy, terminology and open actions.
- [ ] M1 tests cover the shared shell, WF-01 and the non-live profile portion
      of WF-02; owning M2 tasks cover live WF-02 plus WF-03/04/05.
- [ ] Each owning milestone covers focus order, menu/shortcut parity,
      VoiceOver labels, Light/Dark, Increase Contrast, Differentiate Without
      Color and Reduce Motion for its executable flows.
- [ ] Resizing and localized text do not hide production, transaction, cancel
      or consequence text.
- [ ] Wireframes remain a planning artifact; no database call or credential
      handling is implemented by this document.
