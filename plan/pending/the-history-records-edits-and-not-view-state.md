# The history records edits, and not view state

**Status (2026-09-25): IN PROGRESS** on the branch `history-view-state`, in the
worktree `projectured-julia-history-view-state`. Steps 1 to 3 are done.
Step 4 is next. Steps 3 and 4 start with a design that the owner decides.

**Goal:** the undo history holds the edits a person makes, and nothing else. A
gesture that only changes what the window shows adds no step, and a run of typing
does not fill the history.

## 1. The request and the rulings

> a scroll should not go into the undo history

> check what goes into the history that maybe should not go there. I'm
> specifically worried about filling up the history with unnecessary stuff, but
> of course there are other cases which should not go there such as selection
> changes, etc.

The owner's rulings, 2026-09-25:

| Question | Ruling |
| --- | --- |
| A scroll | Not in the history. Done on `main` (`d1584c27`): every scroll write in the widget layer is view state. |
| A list of fields that are view state, by type (`is_view_state_field`) | Rejected: "some state is a view when it's interpreted as that but it can also be edited as a document". The meaning of a write comes from the projection that interprets the gesture. |
| A whitelist of operation types, so the history records only what is on it | Not chosen. The same type, `ReplaceReferencedValueOperation`, writes an edit (a checkbox) and view state (`hovered`), and an edit that nobody listed must still reach the history (see §2). |

## 2. What exists

| Fact | Where |
| --- | --- |
| The filter drops `nothing`, a `DoNothingOperation`, a bare `ReplaceSelectionOperation`, a `ReplaceViewStateOperation`, and a `CompoundOperation` whose members are all view state. Everything else is recorded. | `source/undo/UndoDocument.jl`, `is_undo_step`, `_is_view_state` |
| A history holds 100 steps (`capacity`). It merges nothing: each recorded operation is one step. | `UndoBuffer` |
| An operation whose inverse is `DoNothingOperation` changes no document, and recording drops it: a save, a font zoom. | `evaluate_operation(editor, ::RecordUndoOperation)` |
| An operation with no inverse is recorded as a barrier, and undo stops there. The history must see such an edit: if it skipped it, an older step would apply its inverse to a changed document. The default inverse is `nothing`. | `source/kernel/operation/Inversion.jl` |
| A selection change is never recorded, and it is invertible anyway. Each entry keeps the selection from before its step, and an undo puts it back. | same places |
| Every value write, `ReplaceReferencedValueOperation`, has a generic inverse. So invertibility does not tell an edit from view state. | `Inversion.jl` |
| A reader marks view state with `_write_view_state` (a `ReplaceViewStateOperation`). The widget readers do it for `hovered`, `pressed`, `dragging`, a divider drag, and every scroll. | `source/widget/WidgetDocument.jl`, `WidgetToGraphics.jl` |
| The window history is the innermost wrapper of the window. The key help, the palette, the tooltip, the context menu and the clipboard wrap it from outside, so the history never sees their operations. | `source/shell/WindowWrap.jl` |
| Each file tab holds its own history, and the window history records a copy of each file step ("this inner buffer took one step"). The copy keeps one order across the two levels, and its undo asks the file's history to undo. An undo in a file is copied as a step too. | `_record_operation` in `source/undo/UndoBufferToAny.jl` |
| The navigator's `WidgetTree` and its scroll pane are the output of `FileSystemToWidget`. `ChartPlot` is the output of `ChartToChartPlot`, and `SequenceChartPlot` of `SequenceChartToSequenceChartPlot`. A syntax fold targets a node of the syntax output. None of them is a node of the document that a history holds. | `source/filesystem`, `source/chart`, `source/sequencechart`, `source/syntax/SyntaxToText.jl` |

Measured on `main` (`88b2fac9`) in the application window, offscreen, with a
JSON file, the navigator and the assistant (probe scripts in `/var/tmp/hist-probe`):

| Gesture | Window steps | File steps |
| --- | --- | --- |
| mouse moves over the whole window, the toolbar, the navigator | 0 | 0 |
| clicks, arrow keys, Alt+click, Alt+arrows, in the navigator and in the file | 0 | 0 |
| a wheel over the navigator, the file, the transcript | 0 | 0 |
| a click on a tab title | 0 | 0 |
| the File menu, `F1`, `Ctrl+Shift+P`, the context menu, `Ctrl+C` | 0 | 0 |
| a click on a folder chevron of the navigator | 1 per click | 0 |
| one character typed in the file | 1 | 1 |
| one character typed in the assistant draft | 1 | 0 |
| three characters typed in a file, then `Ctrl+Z` twice | 5 | 1 |

Measured on the readers directly, with the history's own filter (`is_undo_step`):

| Reader | Gesture | Recorded |
| --- | --- | --- |
| chart | 104 mouse moves (`cursor`, `hovered`) | 104 of 104 |
| chart | a wheel (`view`) | 2 of 2 |
| chart | a drag to zoom (`drag_anchor`, `drag_rect`, `view`) | 4 of 4 |
| sequence chart | 59 mouse moves (`cursor`, `hovered`) | 59 of 59 |
| sequence chart | a wheel (`view`, `cross_offset`) | 30 of 30 |
| accordion | a click on a header (`expanded`) | 5 of 5 |

## 3. The ways to exclude an operation

| Code | Way | Exists |
| --- | --- | --- |
| **F** | `is_undo_step` drops the operation by its kind. | yes |
| **R** | The reader that interprets the gesture marks the write as view state (`ReplaceViewStateOperation`). | yes |
| **D** | The inverse of the operation is `DoNothingOperation`, so recording drops it. | yes |
| **P** | The wrapper sits outside the history, so the history never sees it. | yes |
| **O** | The history skips a write whose target is a projection output, not a node of its document. | no, Step 3 |
| **M** | A run of steps merges into one step. It excludes nothing, but it stops the filling. | no, Step 4 |

## 4. The categories

| # | Category | Examples, and where | Today | Way |
| --- | --- | --- | --- | --- |
| 1 | Selection | a caret, a text range, a whole element, the pane focus | excluded | **F**. The gap of D2 remains. |
| 2 | Pointer state | widget `hovered`, `pressed`, `dragging` | excluded | **R**, done |
| | | chart and sequence chart `hovered`, `cursor` (`ChartPlotToGraphics.jl:1512`, `:1517`; `SequenceChartPlotToGraphics.jl:1163`, `:1165`), on each mouse move | recorded | **O** |
| 3 | Scroll, pan, zoom of a viewport | scroll pane, tab strip, transform pane | excluded | **R**, done |
| | | chart `view` (`ChartPlotToGraphics.jl:1381`); sequence chart `view` and `cross_offset` (`SequenceChartPlotToGraphics.jl:1111`, `:1192`, `:1221`) | recorded | **O**: each is a field of the output plot |
| 4 | A drag in progress | splitter, tab drag | excluded | **R**, done |
| | | chart rubber band `drag_anchor`, `drag_rect` (`ChartPlotToGraphics.jl:1430`–`1471`), on each move | recorded | **O** |
| 5 | Open and closed parts of a view | tree `collapsed` (`WidgetToGraphics.jl:8870`), accordion `expanded` (`WidgetToGraphics.jl:7590`) | recorded | **R**, Step 1 |
| | | syntax fold and card fold, `ToggleCollapseOperation` (`SyntaxToText.jl:867`, `ObjectToWidget.jl`) | recorded (from the code) | **O**: the target is a node of the output |
| 6 | Chrome and tool windows | key help, palette, context menu, tooltip, clipboard toggles, hover probe | not seen | **P**, done |
| | | the control bar of `ProjectionConfiguringProjection`, `Ctrl+F` and `Escape` (`ProjectionConfiguring.jl:138`, `:140`) | recorded (from the code) | **R**, Step 1 |
| 7 | Operations that change no document | font zoom, window zoom, quit, save | excluded | **D**, done |
| 8 | Copies of file steps in the window history | each file step, each `Ctrl+Z` in a file | recorded, on purpose | **M**, Step 4 |
| 9 | Runs of typed characters | a file, the assistant draft | one step per character | **M**, Step 4 |

Not measured: the turns that the model's answer adds to the transcript.

## 5. Decisions

### D1. The reader that interprets a gesture marks view state

A field is not view state by its type. When the widget renderer draws a tree and
a person clicks a chevron, the renderer uses the tree as a control, and the write
of `collapsed` is view state. When a projection shows the same tree as data, for
example an object inspector, a write of `collapsed` is an edit. So the mark stays
where the gesture is read (**R**), and no list of fields exists.

**O** is the one rule that needs no reader: a write to a projection output is
never an edit of the document, whatever the field is.

### D2. A compound of selections and view state is not a step

`_is_view_state` counts a compound as view state only when every member is view
state. A compound of a `ReplaceSelectionOperation` and a view-state write is
therefore recorded. The measurement found no such compound, but a reader can make
one. **F** treats a selection as droppable inside a compound: a compound whose
members are all selections or view state is not a step. A compound that holds
one real write is recorded, as now.

### D3. A sweep test keeps the history clean

A test presses the gestures that change no content and fails when a history
grows. It has two parts:

- **The application window:** the gestures of the probe (pointer moves over the
  whole window, a wheel, clicks and keys that select, a tab title, the menus,
  `F1`, the palette, the context menu, a copy, a chevron), each asserting that
  the window history and the file history keep their length.
- **The readers:** every example with a graphics output gets a grid of mouse
  moves and a wheel, and each answer must pass `!is_undo_step`. A case that fails
  until Step 3 is marked `@test_broken`, with a `# @broken:` comment that names
  the step.

### D4. The test for "a projection output" (Step 3, owner decides)

**O** needs to know whether the object a write carries is a node of the document
the history holds. Two candidates:

1. **Search at recording time.** The history looks for the target in its
   document before it records. It is exact, but a hover over a chart makes one
   write for each mouse move, so the cost of the search must be measured first.
2. **Mark at the stage that made the output.** An operation that carries its own
   target travels up the reader chain unchanged. The stage whose output holds the
   target is the place where it enters the input domain without a map back, and
   there the generic reader can mark it as view state. It is cheap, but the stage
   must tell its output objects from others, which is also a search, only in a
   smaller tree.

Step 3 measures both and records the numbers here. The owner then chooses.

**Sizes, 2026-09-25** (a count of the documents a walk visits, which does not
depend on the load of the machine; `search_documents` with a predicate that
accepts everything):

| Candidate | What it walks | Documents |
| --- | --- | --- |
| 1 | the document of the window history, with a small JSON file | 37 |
| 1 | the same, with a second JSON file of 500 entries | 3045 |
| 2 | the navigator's output | 3 |
| 2 | the syntax output of the small file | 36 |
| 2 | the syntax output of the 500-entry file, where a fold's target is | 14512 |

A chart's write targets the output plot of the stage itself, so candidate 2 finds
it by identity. A fold targets a node deep in a syntax output, which is larger
than the document it shows. So neither candidate is always the smaller walk.

**Rule of measurement.** A time runs only on an idle machine and with the owner's
word for that run, in the measurement lane (`taskset -c 28,30,31`). The load was
19 when the sizes were taken, so no time is taken yet.

**Times, 2026-09-25** (the owner said to continue; the median of 200 searches that
find nothing, `-t 1` in the measurement lane; the load was 9 before the run and
17 after it, so the numbers are rough):

| Candidate | Documents | Median |
| --- | --- | --- |
| 1, window history, small file | 37 | 0.045 ms |
| 1, window history, with a 500-entry file | 3045 | 4.6 ms |
| 2, syntax output, small file | 36 | 0.10 ms |
| 2, syntax output, 500-entry file | 14512 | 68 ms |

**Decision, 2026-09-25.** Neither candidate is built. Candidate 2 costs 68 ms for a
fold in a large file, and candidate 1 costs 4.6 ms for each mouse move over a chart
while a large file is open. The cases that **O** was for are each read by one
reader that interprets them, which is the owner's rule of D1:

- the chart and sequence chart readers mark `view`, `cursor`, `hovered`,
  `drag_anchor`, `drag_rect` and `cross_offset` as view state (**R**);
- `ToggleCollapseOperation` is the flip of a fold that a reader made of a chevron
  click, so the filter drops it by its kind (**F**). Editing `collapsed` as data
  is a plain value write, which the filter keeps.

**O** as a safety net over every write is candidate 1. It is a new mechanism, so it
waits for the owner.

### D5. What a run of typing is (Step 4, owner decides)

**M** merges a run of steps into one. Questions for the owner:

- What ends a run: a caret move, a non-character key, a pause, a word boundary?
- The window copies file steps. When the file history merges a character into its
  last step, the window must not add a copy. So a copy is made only when the file
  history pushed a new step.
- The inverse of a run is the inverses of its steps in reverse order, which the
  inversion of `CompoundOperation` already gives.

## 6. Steps

- [x] **Step 1.** **R** for category 5 and 6, and the gap of D2.
  - `_wtree_toggle_collapse` and the accordion header write with `_write_view_state`.
  - `_toggle_operation` of `ProjectionConfiguring.jl` writes `visible` with a
    `ReplaceViewStateOperation`.
  - `_is_view_state` counts a `ReplaceSelectionOperation` inside a compound as
    droppable.
  - Tests: `test_undo()` for the filter, the widget suites for the three readers,
    `test_application()` for the chevron of the navigator.

  Done. What the work showed:
  - `SelectNextInsertionOperation` (a Tab to the next hole of Julia code) only
    moves the selection, but the filter recorded it. It is a selection change, so
    the filter now drops it too. The filter is one function, `_is_no_edit`: a
    do-nothing, a selection move, a view-state write, and a compound of nothing
    else.
  - A tree that gets shorter scrolls back, so a row moves after a fold; the
    application test reads the chevron again after each click.
  - Tests: `test_undo` 94 of 94, `test_widget_tree` 33 of 33, the card and
    accordion folds 39 of 39, `test_projection_configuring` 16 of 16 and one
    broken case that was marked before, `test_application` 324 of 324, the naming
    guard.
- [x] **Step 2.** The sweep test of D3, in `ProjecturedTest`, beside
  `test_application`. The chart and sequence chart cases are `@test_broken` until
  Step 3.

  Done: `test_history_sweep()` in `test/projectured/editor/HistorySweepTest.jl`,
  run by `test_all` after `test_undo_round_trip`. What the work showed:
  - The window part presses 24 gestures and passes. The example part reads the
    answers to a grid of pointer moves and a wheel over each of the 105 examples.
    Only ten record anything, all through `cursor`, `hovered` and `view`:
    `chart_line`, `chart_bar`, `chart_histogram`, `chart_scatter`, `chart_strip`,
    `chart_inspector`, `sequencechart`, `sequencechart_vertical`,
    `sequencechart_linear`, `sequencechart_inspector`. They are in the broken
    registry `history_broken`. The examples `chart` and `sequencechart_pair` record
    nothing.
  - The answers are read and not applied, so each one answers the printed state.
  - Checked by a mutant: with the tree fold written as a plain edit again, the
    window part fails with `("a folder closes and opens", (2, 0))`.
  - Result: 119 pass, 10 broken. `test_exports` fails on `main` in
    `source/help/HelpModule.jl`, which this branch does not touch.
- [x] **Step 3.** **O**: measure the two candidates of D4, record the numbers, ask
  the owner, then build the chosen one. The broken cases of Step 2 become `@test`.

  Done as the decision under D4 says: **R** in the two chart readers and **F** for
  `ToggleCollapseOperation`, and no **O**. The broken registry of the sweep is
  gone, and the ten chart cases are `@test`. Tests: `test_undo` 95 of 95,
  `test_chart` 345 of 345, `test_sequencechart` 279 of 279,
  `test_collapse_roundtrip` 18 of 18, `test_history_sweep` 129 of 129,
  `test_application` 324 of 324. `test_assistant_mvp` fails four times in "the
  assistant card fills its page", a clip box one pixel off, with and without
  this step.
- [ ] **Step 4.** **M**: the owner answers D5, then the merge of runs in the undo
  package, and the copy rule of the window history. The sweep test gets a case
  that types 150 characters and asserts that the window history still holds a
  step made before them.
- [ ] **Step 5.** The guides: `documentation/package/undo/undo.md` (what the
  history records and why) and `documentation/package/widget/widget.md` (the list
  of view-state writes).
