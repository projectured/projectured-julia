# A divider drag leaves no history

**Status (2026-09-22): READY.** The owner asked on 2026-09-22 that a divider drag
add nothing to the undo buffer.

**Goal:** the grab, each move and the release of a divider add no undo step, in
a split of the pane tree and in a split that a tab's content builds. Ctrl+Z after
a drag takes back the edit before it.

**Repositories:** projectured-julia. omnet-julia needs no change: its one test
of a divider drag looks through a wrapper already.

## 1. What is wrong

`plan/done/hover-drag-and-tooltip-share-the-pointer.md` measured that a divider
drag of three moves adds five undo steps: the grab, each move and the release.
That plan kept them as steps, because the pane layer reads the three operations
of a drag by type, and it assumed a wrapper would hide them from those readers.

## 2. Decisions

- **The split pane's reader marks its three answers** with
  `ReplaceViewStateOperation`: `StartSplitterDragOperation`,
  `ResizeSplitPaneOperation` and `EndSplitterDragOperation`. This is the mark
  the hover, the press and the tab drag already carry, so `is_undo_step` drops
  them with no change of the undo slice.
- **The pane layer still reads them by type.** The generic `read_intent` of
  `ProjectionDefaults.jl` reads a `WrappingOperation` by reading the operation
  inside through the same projection and wrapping the answer again. The pane
  layer has no reader of its own for the wrapper, so its typed readers run on
  the operation inside, and their answers come back marked: the grab's
  `CompoundOperation`, which clears `sizes`, and the resize's weight write.
- **The mark goes at the source**, not in the pane layer: a split that a tab's
  content builds passes the pane layer unchanged, and it must be marked too.

## 3. Steps

### Step 1 — the split pane marks its drag

- [x] `_split_drag_read` in `WidgetToGraphics.jl` answers the three operations
      marked.
- [x] The tests that check the three types look through the mark:
      `SplitPaneDragTest.jl`, `WidgetShellTest.jl`, `PaneReaderTest.jl`,
      `TooltipProbeTest.jl`. The two negative assertions of
      `SplitPaneDragTest.jl` must unwrap, or they pass for the wrong reason.
      One assertion checks the mark itself.
- [x] `test_application()`: across a divider drag in the real window, the
      window's history does not grow, and the weights still change.
- [x] Run `test_substrate()` (baseline 63401 pass, 3 fail, 2 error, 1 broken),
      `test_shell()` (177) and `test_application()` (126). Measured:
      substrate **63404 pass, 3 fail, 2 error, 1 broken**, the 3 new passes
      being the mark's own assertions and the five failures the known
      split-pane cases, moved by the lines added above them; shell **177**;
      application **127**, one new assertion. The pane layer's typed readers
      run on the operation inside the mark with no change, as §2 expected:
      the application's drag still changes the weights.
      A new worktree has no manifest in `package/*Test`: run
      `Pkg.instantiate()` before the first `using`.

### Step 2 — the guides, and close

- [x] `shell.md`: the limit about a divider drag goes. `undo.md` and
      `widget.md`: the divider drag is view state. `pane.md` also says that its
      reader reads the operation inside the mark.
- [ ] omnet-julia after the landing: `test_ide_window_wrap()` (32).
- [ ] Move this plan to `plan/done/`.
