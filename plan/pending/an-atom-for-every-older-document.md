# An atom for every older document

**Status (2026-10-16): IN PROGRESS.** The owner asked for this step after
[the-suites-of-main-pass-again.md](../done/the-suites-of-main-pass-again.md): "continue with
the older types". The rule is the owner's from that plan: "ideally all testable documents
should be in the atomic catalog, that's an automated test suite primarily, not an end user
concept".

**Goal:** each of the 36 document types on the list `_NO_ATOM` of
`test/projectured/projection/CatalogCoverageTest.jl` has an atom of the catalog, or stays on
the list with the reason that no test can make it. When the list is empty, the check
`@test_broken isempty(gap)` becomes `@test`.

## 1. The types

`AboutPage`, `AppearanceDocument`, `ArrangementChips`, `ArrangementDocument`, `Assistant`,
`AssistantList`, `CommandPalette`, `ContextMenuWindowState`, `DataFrameView`,
`DataFrameViewRow`, `DragTrackingState`, `EvaluatorForm`, `EvaluatorToplevel`, `FaultLog`,
`FaultReport`, `FileSystemChooser`, `FrameStatistics`, `FrameTimeSeries`, `GestureLog`,
`GestureTrackingState`, `JuliaToplevel`, `McpLog`, `MessageLog`, `ObjectField`, `PaneGroup`,
`PaneSplit`, `PaneTree`, `SelectionInspector`, `Settings`, `SettingsDocument`, `TextGraphics`,
`TextSpacing`, `TooltipContent`, `TooltipWindowState`, `WidgetHighlight`, `WidgetToolbarItem`.

## 2. The steps

- [ ] **Step 1: an atom for each type.** A function that makes one instance with no file on
  disk, no process, no window and no network, its `AtomicDocument` row, and the name off
  `_NO_ATOM`.
- [ ] **Step 2: the testers on each new atom.** A small fault gets its fix; a fault of a known
  kind gets a mark of the catalog with its reason; a type that no test can make goes back
  on `_NO_ATOM` with its reason.
- [ ] **Step 3: the check.** `test_catalog`, `test_catalog_coverage` and `test_catalog_typeins`
  show no unmarked failure.
