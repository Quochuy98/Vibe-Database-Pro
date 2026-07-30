# DataForge UX wireframes and accessibility annotations

Status: Low-fidelity planning artifact; requires product/design review before M1

Last updated: 2026-07-30

These wireframes define original information hierarchy and safety language for
the first shell. They are not pixel specifications, assets, or an imitation of
another database product. Geometry is intentionally approximate; M1 must
measure resizing, Dynamic Type, keyboard focus and VoiceOver behavior against
the performance/accessibility budgets.

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
  status actions, with a visible focus ring and no fixed minimum that prevents
  a usable editor.
- VoiceOver exposes named regions (`Connections`, `Document`, `Results`,
  `Inspector`, `Status`) and announces busy/empty/error/cancelling state.
- `⌘K` opens the command palette; every toolbar action has a menu command and
  an accessible label. Reduce Motion removes pane animations.

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
transaction is restored.

## WF-02 — Connection and trust form

```text
+---------------------- New connection ----------------------------+
| Adapter [PostgreSQL ▾]     Environment [Development ▾]            |
| Host [                       ] Port [      ] Database [          ] |
| Authentication [Keychain ▾]  [Store secret in Keychain]           |
| TLS [Required ✓]  CA [System roots ▾]  [Choose CA…]               |
| SSH tunnel [Off ▾]  Known-host policy [Verify ✓]                  |
|                                                                  |
| [Cancel]                         [Test connection] [Save profile] |
+------------------------------------------------------------------+
```

Only capabilities declared by the adapter reveal fields. Secret controls are
announced as Keychain-backed and never echo values into drafts. `Test
connection` reports separate SSH/TLS/authentication phases and has a visible
Cancel action. Invalid certificate/hostname or changed host key is an error
heading with the consequence and next action; there is no global insecure
bypass. Choosing `Production` adds a persistent text badge and requires the
same keyboard-accessible confirmation path as a mouse click.

ADR-0012 currently leaves SSH unadopted, so a production UI must hide or
disable the SSH row with an explicit unsupported explanation until a future
candidate passes every re-entry gate. The wireframe preserves the conditional
layout only; it is not evidence that SSH is available.

## WF-03 — Query editor, result stream and grid

```text
+----------------- Query — Development / app ----------------------+
| [Run ⌘R] [Stop ⌘.] [Commit] [Rollback]   timeout [30s] rows [200] |
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
main actor. `Stop` changes to `Cancelling` immediately and then reports the
driver truth; it never promises a server-side stop without evidence. The grid
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
| Preview digest: 8F…     [Copy generated SQL]                     |
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
only warning signal.

## WF-05 — Transaction and pending-edit close protection

```text
+-------------------- Close query tab? -----------------------------+
| Development / app   Transaction: ACTIVE (tx-42)                   |
| 3 pending row edits are not applied. Closing can change outcome.  |
|                                                                  |
| [Keep tab open] [Review pending SQL] [Roll back and close]        |
| [Close and acknowledge unknown outcome]                           |
+------------------------------------------------------------------+
```

The safest action is first in focus order and is the default only for Escape;
close never silently commits. If rollback is unsupported or the connection is
lost, the dialog says `Outcome unknown` and offers read-only reconciliation,
not automatic retry. Pending edits remain recoverable until the user chooses a
discard/rollback path. VoiceOver reads the transaction ID, target and count of
pending edits; keyboard navigation reaches every action without relying on
color.

## Review and acceptance checklist

- [ ] Product/design review accepts original hierarchy and terminology.
- [ ] M1 UI tests cover focus order, menu/shortcut parity, VoiceOver labels,
      Light/Dark, Increase Contrast, Differentiate Without Color and Reduce
      Motion for all five flows.
- [ ] Resizing and localized text do not hide production, transaction, cancel
      or consequence text.
- [ ] Wireframes remain a planning artifact; no database call or credential
      handling is implemented by this document.
