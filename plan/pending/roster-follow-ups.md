# The roster: scroll, kept rows, and the record of a new reader

The work of `plan/done/cross-cutting-views.md`, `plan/done/roster-table-cost.md`,
`plan/done/computed-cell-stop.md` and `plan/done/dependency-reads.md` left four
findings, which the owner asked to fix on 2026-10-15:

1. **A long roster can not scroll in a tab.** A tab gives its content a free
   height, and the table of a roster makes no scroll of its own, so the rows below
   the pane can not be reached.
2. **A new list of rows prints the whole table again.** When a filter or a sort
   changes its answer, every row prints again: about 44 computations for each row
   (S4b, 2212 computations for 50 rows).
3. **A new reader scans the list of the readers of a cell.** After the check of
   the end of the list, S4b still walks 4.6 million entries for each step, from
   the records of new readers.
4. **The time of the check of the end of the list ran under load.**

## Steps

- [x] **1. The roster scrolls in a tab.** The table of a roster takes the form
  that the other long views in a tab use, and scrolls its own rows. A test shows
  a roster of 200 rows in a tab and reaches its last row with the wheel.
  - Done 2026-10-15. The cause: a tab gives its content its height as a slot,
    and the layout rules say that a table that gets a slot fills it and scrolls
    its rows (`layout-rules.md` §3b). Two `VerticalLayout`s took the slot away,
    because a stack gives a slot only to a weighted child (§4): the bar of an
    arranged place, and the layout around the table of a roster.
  - The bar is a `VerticalLayout` whose children fill its width and share its
    height (`child_width = Fill`, `child_height = Fill`), with the chips in a
    `LayoutConstraint(chips; height = Content)`, so the items take what the
    chips leave. The items stay at `children[2]`, because they can be a value
    that is no document, such as a reflected `Vector`, which a
    `LayoutConstraint` can not hold; the chips go to `children[1].child`, in the
    bar and in `Finding.jl`.
  - A `GridLayout` in the bar failed: a grid keeps the output of a child from
    its print, and the chips print a new canvas when their count changes, so
    the count stayed old. The table of a roster and the table of the groups sit
    in a `GridLayout` of one `Fill` column and one `Fill` row, which keeps their
    paths at `children[1]`; a table keeps one canvas, so the grid follows it.
  - A test in a window: a roster of 200 rows in a tab draws its last row below
    the window, and the wheel brings it into view. Without a window an editor
    has no height to give, and its canvas is as tall as its content.
  - The roster tests and every arrangement test pass.
- [ ] **2. A row that stays keeps its print.** When a filter or a sort makes a
  new list of rows, a row that is in the old list and in the new one keeps the
  print of its cells. A test checks that the drawn text of such a row is the
  same object after a change of the filter; the counts of S4b before and after.
  The owner chose on 2026-10-15 the form that lasts ("backward compatibility is
  not an issue"): the grid of a list keeps the print of a row by the row, and
  the table of a roster becomes a table of a list, so the grid of a list prints
  its rows. Three parts, one commit each:
  - [x] **2a. The path of a printer context is a cell.** A print keeps its
    printer context: the fault barrier keeps it for a retry, and the dispatch
    by path keeps it in the computation of its choice. The context holds the
    path of the input as a value, and a row of a list names its place by its
    count from the head. So a kept print of a row that moves gives the old row
    to every reader of that path: the dispatch by path, the base and the picks
    of an arrangement, and the origin of a fault. The owner's form
    (2026-10-15): the context carries the computation in a cell, which gives
    the projection the value that is always correct. The first form, a `place`
    field beside the path, was wrong (the owner, 2026-10-15).
    - `PrinterContext.reference` is an `AbstractCell` of the path, and a reader
      reads `ctx.reference[]`. A fixed path is an `ImmutableCell`, and the
      child of a fixed path is computed at once, as now, so a context that can
      not move costs what it costs now. The child of a path that can move is a
      computed cell that extends the path of its parent. A constructor that
      gets a `Reference` wraps it in an `ImmutableCell`.
    - What a print keeps for later keeps the cell, and reads it when it is
      used: the dispatch by path, the base of an arrangement (`_Arrangement`),
      the picks (`_with_picked_rows`), and the origin of a fault. A printer that
      reads the path during the print reads it in a computation of its own, or
      with `peek`, so the computation that runs the print does not depend on
      it.
    - The field `reference` of `ReferenceDispatchingIoMap` has no reader, and
      goes. `ConversationToWidget.jl` passes `ctx` and `ProjectionTemplate.jl`
      extends the context, where each now makes a context from a copy of the
      path.
    - `FaultStore.jl` (🔒) has `reference = ctx.reference` in the example of
      `record_fault!`. It becomes `ctx.reference[]` only with the owner's
      permission for that file.
    - Tests: the context of a fixed path holds an `ImmutableCell`; a
      computation that reads the path of a child of a path that can move
      computes again when the parent moves; the dispatch by path chooses again
      when its path moves, and keeps the inner IO map for the same choice.
    - A child of a vector (`make_reconciled_child_iomaps_cell`) is kept by its
      object and its index, because its path held the index. With the path in
      a cell it can be kept by its object alone; that is not part of this plan.
    - Done 2026-10-15. The field is `Union{ImmutableCell{Any}, Cell}`, so the
      read has two cases. `make_reference_cell(f, ctx)` makes a cell of `f` of
      the path: `make_child_context` uses it, the template (`ProjectionTemplate.jl`)
      and the picks of an arrangement too. A new method
      `make_child_context(ctx, cell)` gives a child the cell as its path.
    - A read at the print, or in the origin of a fault, is `peek`, so the
      computation that runs it does not depend on the path: the dispatch with a
      fixed choice, the type of a place (`InsertionToSyntax`), the three reads
      of the fault barrier, and the example in `FaultStore.jl` (the owner gave
      the permission for that line; the file stays sealed). The choice of the
      dispatch reads `ctx.reference[]` in its computation.
    - The base of an arrangement is the cell, and a pick holds one cell of its
      `source` and its `place`. Whether a place is below the arrangement is
      read once, at the print, because a move does not take it out.
    - omnet-julia has three copies of the path, as `ConversationToWidget.jl`
      had (`SimulationBatchToWidget.jl`, `LegacySimulationResultToWidget.jl`,
      `SimulationToWidget.jl`). They pass the cell to `make_child_context`,
      which gives the same path, so they work with no change.
    - Tests: `test_printer_context_range` (53), and the tests of the readers:
      the template, the fault barrier, the type-in, the conversation, the
      window shell and wrap, the clipboard, every arrangement test, every roster
      test, and the insertion; all pass. The naming guard passes.
  - [ ] **2b. The grid of a list keeps the print of a row** (`GridList.jl`).
    - The grid keeps the print of each row by the row document itself, in an
      `IdDict` that keeps the row alive: the IO maps of its cells, the cells in
      their slots, and the height of the row. A new head, and a new link after
      the head, take the kept print of their row, and only a new row prints.
      The grid keeps the prints of the rows linked under the head and under the
      head before it, so a row that left goes out after two heads. The same
      keeps the rows when a table moves its head far down (S6).
    - A link makes a new canvas for its row around the kept cells, with the `y`
      that follows the row before or after it. A computation must not write a
      cell (`fault.md`), so a link never moves a kept canvas.
    - The path of the context of a kept row is a computed cell (2a) that
      extends the path of the grid by `children[k]`, and `k` is a computation:
      the count of links from the head of `children` to the row, walked from
      the head both ways in turn. So the path follows any change of the list
      between the head and the row, and no computation writes it. The count is
      plain data, so the stop of a computed cell keeps the readers of a row
      whose count stays the same.
    - A row object that is in the list two times keeps its print only at the
      place nearest the head. The other place prints the row again, with the
      count of its link fixed, and the grid does not keep that print.
    - The walk reads only a row that is in the list: the grid reads it when it
      links the row, and a reader of the place reaches the row through a link.
    - Tests in the test of the grid of a list: a new head with the same rows
      keeps the IO maps of their cells (`===`); a dispatch by path sees the new
      count of a moved row; the `y` of each row; a row in the list two times; a
      row that left goes out after two heads.
  - [ ] **2c. The table of a roster is a table of a list**
    (`RosterRowsToWidget`). The owner agreed on 2026-10-15, with the equal
    share of the columns and the two forms of the table.
    - With an exact height in its context, the body of the table is a list of
      the cells of the rows (`made`, the same object for a row that stays),
      from the row `anchor`, a cell of the IO map. With no height, as in a print
      with no window, the table keeps the vector form, because a table of a
      list needs an offered height.
    - Every column takes an equal share of the width and is at least as wide as
      its header, as in the table of a data frame. A row is as tall as its
      cells.
    - The table moves its head far down by a write of `cells`
      (`_add_top_row`). The roster turns that write into a write of `anchor`,
      as the view of a data frame does. The selection of the rows names a row
      of `rows`, so the maps follow `anchor`, and the roster drops the shift of
      the selection.
    - The docstring of `RosterRowsToWidget` says what the table keeps.
    - Tests: a change of the filter keeps the drawn text of a row that stays
      (the same object); a wheel past 200 rows moves `anchor`, and the
      selection stays on its row; the roster tests, the arrangement tests and
      the test of step 1 pass. The counts of S4b and S6 before and after.
- [ ] **3. The record of a new reader.** Done only when, after step 2, the probe
  of `plan/done/dependency-reads.md` still walks more than one million entries
  in a step of S4b or S4d. Then a record that knows the reader is new to the
  list puts it at the end with no scan, and the dead readers go out in a bounded
  way, so the list can not grow with no limit; a test pins the bound.
- [ ] **4. The time.** The six scenarios of the measure on an idle machine,
  `main` at the start of this plan against the branch, two rounds each, with a
  wait for an idle machine.
- [ ] **5. The texts.** The limits and the cost of a change in
  `documentation/package/platform/roster/roster.md`, with the counts of steps 2
  to 4. The place that follows its row in the document of the projection
  system, and the kept rows in the document of the layout.
