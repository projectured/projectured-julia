# Children that move keep their print

`plan/done/roster-follow-ups.md` made the path of a printer context a cell, and
taught the grid of a list to keep the print of a row that moves. It recorded
limits and two ideas for the cell engine. The owner goes through them one at a
time (2026-10-16); this plan holds each decision.

## Decisions

1. **The reconciler of a vector keeps a child by its object** (option A, the
   owner, 2026-10-16). `make_reconciled_child_iomaps_cell` in
   `source/kernel/iomap/IoMapReconcile.jl` keys a child by the element itself,
   in an `IdDict`, which also keeps the element alive. One computed cell maps
   each element to its index for each change of the vector, and each child
   gets an index cell that reads it; an element at two places is not kept, and
   each of its prints takes its own index. `make_iomap(index, x)` gets the
   index cell, so the 15 callers build the context of a child from it. Today
   an insert or a delete at the front prints every child after it again, for
   example every member of a JSON object after a deleted member.
2. **A change inside one head keeps its reach** (option B, the owner,
   2026-10-16). The counts of a head reach the rows linked under it and under
   the head before it, and no farther. An insert in the middle of a list under
   the same head, with no new head, prints the rows after it again; the result
   is correct. No code edits a list in the middle in place today (`push!` adds
   at the end, `pushfirst!` before the head), and the producers that a grid of
   a list shows make a new head for each change. A test pins the behavior: an
   insert under the first head gives the right rows and paths. A lazy chain of
   segments of counts is the model for the first producer that edits a list in
   place.
3. **The dispatch by path confines a change of its path** (the owner,
   2026-10-16, on the owner's question of what depends on the count). Today the
   choice and the reconciled IO map are one cell in `ReferenceDispatching.jl`,
   so a new path with the same choice gives the same IO map, an object, which
   the engine passes on as a change: to the output cell, to the cells of a row
   that read it, and to the readers of the edges of the columns. That is the
   cascade of about 33 computations for a moved row in S4b-w, and most of the
   1.34 M entries per step of the detach walk. The choice becomes a cell of the
   projection and a cell of its `objectid`, plain data, which the reconciled
   cell reads; the same choice then stops at the dispatch. S4b-w is measured
   again after it, before the two ideas for the engine are decided.
4. **The linear list keeps its children** (option A, the owner, 2026-10-16).
   `_print_layout_list` in `LayoutList.jl` keeps the print of a child by the
   child document, as the grid of a list keeps a row; no view in `source/` uses
   the linear list today, only tests and examples.
5. **The grid whose columns are a list keeps its cells** (option A, the owner,
   2026-10-16): a cell is kept by its row document and its column document,
   with counts for the head row and for the head column. Its one user is the
   view of a data frame with more than 64 columns.
6. **The view of a data frame keeps its row objects** (option A, the owner,
   2026-10-16). `_make_row_list` in `DataFrameView.jl` makes a new `CellVector`
   for each row each time it builds its list, so after a filter, a sort or a
   move of the anchor the grid of a list finds no kept print. The view keeps
   the row of each row of the frame by its number in the frame, as the roster
   keeps `made`, and forgets the rows that left.
