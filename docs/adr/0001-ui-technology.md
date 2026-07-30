# ADR-0001: Native SwiftUI shell with focused AppKit components

Status: Accepted for planning; implementation gated by M0 prototypes

Date: 2026-07-29

## Context

DataForge is a keyboard-first, multi-window macOS productivity application. Common forms and shell composition benefit from SwiftUI, while a professional SQL editor, lazy object tree, and virtualized editable grid need mature AppKit behavior, responder-chain integration, fine-grained performance control, and accessibility.

## Options considered

1. SwiftUI only.
2. SwiftUI shell with focused AppKit views.
3. AppKit only.
4. Electron/web application.
5. Tauri/web frontend with Rust backend.

## Decision

Use SwiftUI for application shell, settings, inspectors, ordinary forms and composition. Wrap AppKit behind narrow presentation interfaces for `NSTextView`/TextKit 2 SQL editing, `NSOutlineView` object navigation and a view-based `NSTableView` result grid. AppKit coordinators are `@MainActor`; business/database logic remains in application services.

## Reasons

- Native menu, window, command, keyboard, accessibility and appearance behavior are product requirements.
- AppKit provides direct control for text, outline and table workloads without embedding a browser runtime.
- SwiftUI remains productive for the majority of non-grid/editor screens.
- The split keeps platform UI concerns above application/domain/database boundaries.

## Trade-offs and risks

- Two UI state systems require explicit ownership and coordinator discipline.
- `NSTableView` may struggle with very wide datasets/frozen columns.
- TextKit 2 compatibility fallbacks and large-file behavior require measurement.
- Custom AppKit views need explicit accessibility work.

Electron/Tauri are rejected for the initial product because runtime size, native semantics, accessibility integration and two UI/runtime stacks conflict with the macOS-first goal. This is not a judgment that those frameworks are generally unsuitable.

## Consequences

- No database/file/network call in SwiftUI `body`.
- Visible state updates on `MainActor`; work occurs in cancellable services.
- SharedUI contains presentation primitives, not business rules.
- Editor/grid/tree prototypes are disposable M0 spikes, not production shortcuts.

## Validation before implementation

- Large SQL file typing/edit/scroll latency and memory meet `PERFORMANCE_BUDGET.md`.
- Million-row/wide-table grid meets scroll, memory, edit-identity, theme-update and VoiceOver budgets.
- Keyboard/focus/undo/restore tests cover SwiftUI–AppKit boundaries.

## Revisit when

Measured prototypes cannot meet critical performance/accessibility goals, or Apple materially changes the platform APIs. A custom native renderer may replace only the failing component; a whole-stack change needs a superseding ADR.
