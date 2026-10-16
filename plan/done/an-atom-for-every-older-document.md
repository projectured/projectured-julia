# An atom for every older document

**Status (2026-10-16): DONE.** The owner asked for this step after
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

- [x] **Step 1: an atom for each type.** A function that makes one instance with no file on
  disk, no process, no window and no network, its `AtomicDocument` row, and the name off
  `_NO_ATOM`.
- [x] **Step 2: the testers on each new atom.** A small fault gets its fix; a fault of a known
  kind gets a mark of the catalog with its reason; a type that no test can make goes back
  on `_NO_ATOM` with its reason.
- [x] **Step 3: the check.** `test_catalog`, `test_catalog_coverage` and `test_catalog_typeins`
  show no unmarked failure.

## 3. What was built

- **34 atoms** (`655993c0b`). A Sonnet agent wrote the drafts, and the lead ran every test.
  Each atom makes one instance with no file on disk, no process, no window and no network;
  the assistant answers from a `FakeLlm`, and the file chooser holds a directory of explicit
  entries. `DataFrameView` and `DataFrameViewRow` stay on `_NO_ATOM`: they hold a
  `DataFrame`, and the catalog loads no package of the DataFrames adapter.
- **Marks of a known kind:** `text/bare_spacing` and `text/bare_graphics` as the other bare
  spans (`WordWrapping` has no method for a lone span); `inspector/selection` and
  `projection/fault_report` in the navigation set, views in which Ctrl+Home finds no caret.
  `_NO_NATURAL_RENDER` takes the two bare spans, `text/gutter` (from the step before, so
  `test_natural_renders_every_atom` failed on `main` from `97c1c0ef6` until this step), the
  file chooser and the document of an appearance.
- **A fix** (`187f99ce0`): a line of the frame times read `plot.frames`, a list of cells by the
  list rule, and the chart searched it for its visible range with `searchsortedfirst`, which
  has no method for it. The live plot of the frame times can reach the same line.
- **A finding, not fixed:** the natural renderer has no row for `AppearanceDocument`, and its
  view of an object stops at a slot with nothing in it in a `Memory`
  (`ObjectToSyntax.jl:224`, `_is_slot_assigned` takes only an `Array`). With the slot
  skipped, the view walks the whole graph of the appearance and does not end, and
  `precompile_workload` renders every atom, so a build would hang. The atom fails at once as
  it is, and is on `_NO_NATURAL_RENDER`.
- **The check:** `test_catalog` 747542 and 2284 broken, `test_catalog_coverage` and
  `test_natural_renders_every_atom` no failure, `test_catalog_typeins` and
  `test_natural_round_trips_every_atom` no failure, `test_chart` 377,
  `test_frame_statistics_feed` 138, the documentation and naming guards.
