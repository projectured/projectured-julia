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
7. **Two helpers for lazy lists** (option A, the owner, 2026-10-16). Helper 1,
   `make_mapped_list(source, f)` in the collection module: the node at count k
   holds `f(source_node, k, neighbor)`, built when a walk first reaches it and
   linked both ways, where `neighbor` is the mapped node that the walk came
   from. It replaces the links built by hand in ten files (19 computations of a
   link): `LayoutList.jl`, `GridList.jl`, `GridColumnList.jl`,
   `WidgetTableParts.jl` (with its private `_make_mapped_node`),
   `WidgetTableHeaderLevels.jl`, `TextToGraphics.jl`, `SyntaxToText.jl`,
   `Copying.jl`, `CollectionToSyntax.jl` and `make_index_list`. Helper 2, the
   kept prints of a list, in the collection module, which knows nothing of
   grids: the prints of this head and of the head before it, the counts of a
   head with their reach, the count of one element, the rule of an element at
   two places, the take of a kept print and the record of a new one. It takes
   over the code of 2b from `GridList.jl`. The order: helper 1 as a pure
   refactor, then helper 2 as a pure refactor, each shown by the tests that
   stand, then the users.
8. **The projections that print the elements of a list keep their prints**
   (the owner, 2026-10-16): `Copying.jl` and `CollectionToSyntax.jl` use helper
   2, so a new head prints only the elements that are new to it.

The two ideas for the cell engine, a stop for the same object and a detach with
no scan, wait for the measure of step 10, by decision 3.

## Steps

Each step is one commit, with its tests, in the worktree `kept-children`. The owner wants small
parts, each landed after its tests (2026-10-16): part 1 is steps 1 to 3, part 2
step 4, part 3 steps 5 and 6, part 4 step 7, part 5 steps 8 and 9, then steps
10 and 11.

- [x] **1. Helper 1, the lazy mirror of a list** (decision 7), and the ten files
  on it. No behavior changes: the tests of the layouts of a list, the tables, the
  syntax and the text pass as they are.
  - Done 2026-10-16. Helper 1 is two functions in `ListNode.jl`:
    `set_lazy_link!(node, direction, make_neighbor)`, the link that builds its
    neighbor when first read and links it back, and
    `make_mapped_list(f, source; at, computed)` on it. Three places do not mirror
    one node for one node (the lines of `SyntaxToText.jl`, the running offset
    of `TextToGraphics.jl`, the two lists of `GridColumnList.jl`), so they use
    `set_lazy_link!`; 36 computations of a link in ten files are on it, the
    turned row of the table parts too, and the private `_make_mapped_node` of
    the table parts is `make_mapped_list` with `computed = true`.
  - Tests: two testsets in `CollectionDocumentTest.jl`. The platform suite
    gives the result of `main` (one failure of the layering guard: the slice
    undo uses `NaturalModule`, from `b5739a653`), and the data frame suite too
    (44 failures and 7 errors in the edit of a cell, which `main` has; see the
    fix after this step).
- [x] **2. Helper 2, the kept prints of a list** (decision 7), and the grid of a
  list on it. No behavior changes: the tests of 2b pass as they are.
  - Done 2026-10-16 in `KeptListPrints.jl` of the collection module:
    `KeptListPrints` and `KeptListPrint`, and `make_kept_list_prints`,
    `start_kept_list_head!`, `note_kept_list_link!`, `make_kept_list_count`,
    `take_kept_list_print!` and `record_kept_list_print!`. The keep counts the
    lowest and the highest count linked under a head itself, where the grid
    read the keys of `built`. The grid keeps its row data (`_GridListRow`: the
    documents, the IO maps, the outputs, the cells and the height) and its own
    check, `_is_grid_list_row_current`, which `take_kept_list_print!` calls.
  - Tests: a testset of the helper in `CollectionDocumentTest.jl` (a new head
    keeps three elements at their new counts, an element goes after two heads,
    an element at two places is kept at neither). The list layout (71), the
    tables of a list (250), the roster and the data frames (608) give the
    counts of before.
- [x] **3. The dispatch by path confines a change of its path** (decision 3). A
  test: a dispatch whose path moves and whose choice stays leaves the output
  cell of its IO map valid.
  - Done 2026-10-16. `_make_dispatch_choice` in `ReferenceDispatching.jl`: at
    a path that can move, a computed path cell, the choice is a cell and the
    reconciled IO map reads only a cell of its `objectid`. At a fixed path, an
    `ImmutableCell`, the IO map reads the choice itself, as before: the first
    form split every choice, and a fresh print then had two more cells for
    each dispatch, which made S4b with no window 21 % dearer (1533 → 1856
    computes).
  - Counts, per step, with a new probe (`count-s4bw.jl`, the probes of the
    roster plan are gone), step 2 → step 3: S4b-w 1166 → 978 computes, S4b
    with no window 1533 → 1533. The detach walk stays at 1.47 M entries in
    S4b-w: it does not come from the cascade. A choice of the arranged
    dispatch still computes when its path moves, and it reads cells that every
    place of the arrangement reads (its base, its picks), so each detach of a
    choice scans a long list. This goes to the owner with the two ideas for the
    engine at step 10.
  - Tests: `test_reference_dispatching_path` in `HigherOrderTest.jl` (a reader
    of the output of a dispatch whose path moves runs once; a new choice
    prints again).
  - The platform suite (162719, 7 broken, no failure) and the data frame suite
    (608) pass. Part 1 lands with this step.
- [x] **4. The reconciler of a vector keeps a child by its object** (decision
  1), and its 15 callers. A test: a delete of the first member of a JSON object
  keeps the prints of the other members, with the paths of their new places.
  - Built 2026-10-16. `make_reconciled_child_iomaps_cell` keys a child by the
    element in an `IdDict`, with the index of its last placing. One computed
    cell maps each element to its index for each change, and each child gets a
    cell of its index that reads the map; an element at two places gets a fixed
    index and is not kept. `make_element_context(ctx, [current_doc,] index,
    make_steps)` in `PrinterContext.jl` makes the context of an element from
    its index cell: `make_steps(i)` gives the steps to the element at `i`, and
    the path is an `ImmutableCell` when the path of the context and the index
    are fixed. The template has `_make_template_element_context`, which types
    the steps by the type of the document, as `_make_template_child_context`
    does.
  - The callers: eleven read the index only in the path and use
    `make_element_context` (Reversing, Copying, Sorting, ObjectToSyntax,
    WorkspaceToFileSystem, ScreenToScreen, two in PaneToWidget, the menu, two
    in the template); four do not read it (the composite, the tabbed pane, the
    toolbar, the accordion). No caller reads it for a form, such as a comma.
  - Tests: the reconciler test pins the new rule (a delete or a front insert
    keeps the children that stay, and their index cells give the new indexes;
    an object at two places is not kept), and `ObjectFieldToSyntaxTest.jl` has
    a delete at the front of a collection that keeps the outputs of the others.
    The test of the plan named a JSON object; the collection form of
    `ObjectToSyntax` is the caller, so the test uses it.
  - The kernel suite (4772), the platform suite (162732, 7 broken), the data
    frames (608) and the 19 domain suites pass (yaml has 2 broken). The process
    suite hung once at `ProcessDebugTest.jl:185` under the load of the other
    suites: a race in that test, which passed 315 of 315 three times alone, as
    on `main`. Part 2 lands with this step.
- [x] **5. The linear list keeps its children** (decision 4), on helper 2.
  - Done 2026-10-16 in `LayoutList.jl`. `_LayoutListChild` is the print of a
    child: its IO map, the output of the IO map at the print, the output that
    the layout draws, and its width and height. `_link_layout_list_child` takes
    a kept print when its IO map gives the same output; each link makes a new
    wrapper with new `x` and `y` cells. The path of a child is
    `make_element_context(ctx, doc, count, ...)` from step 4: it gives the same
    path as the row context of the grid, so no new helper is needed.
  - Tests: two testsets in `LayoutListTest.jl` (a filter keeps the children
    that stay, at their new places and paths, and a child that comes back
    prints again; a child at two places is kept at neither). The file passes
    86 checks, 71 before.
- [ ] **6. The grid whose columns are a list keeps its cells** (decision 5), on
  two of helper 2.
- [ ] **7. The view of a data frame keeps its row objects** (decision 6). A
  test: a filter keeps the drawn text of a row that stays.
- [ ] **8. `Copying.jl` and `CollectionToSyntax.jl` keep the prints of their
  elements** (decision 8), on helper 2.
- [ ] **9. The test of an insert inside one head** (decision 2): the rows and
  their paths are right.
- [ ] **10. The counts and the time**: S4b-w, S4b, S4d, and a filter of a data
  frame, base against branch, on an idle machine with the owner's word. The
  numbers go back to the owner with the two ideas for the engine.
- [ ] **11. The texts**: the guides of the collection, the layout, the
  projection system, the data frames and the roster.
