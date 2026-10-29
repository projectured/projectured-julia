# A roster and its arrangement cost what changed

Status: pending. Written 2026-10-29. Started 2026-10-29 on the branch
`lazy-arrangement` (worktree `projectured-julia-lazy-arrangement`).

Applies to projectured-julia. omnet-julia uses it for the views of its tasks.

## The ask

The plan `a-runner-for-each-kind-of-test.md` of omnet-julia (step 5) measured
the arrangement of the platform over a roster of 22,731 tasks: a filter of
13.9 ms, a sort of 45.9 ms, a quick text of 66.5 ms, and 2.08 s for the rows of
the roster the first time. A frame at 60 Hz is 16.7 ms.

The owner, 2026-10-29:

- "Let's wait with the data table change until we are sure we can't make it fast
  otherwise." The data table change is a table of typed columns, with the filter
  language of the data frame table moved to the platform.
- "My instinct tells me it could be fast enough easily if it would be lazy and
  incremental, which are the first principles. I also don't know why does a
  roster make one row for each task eagerly, that's bad."
- To the proposal below, which uses the cells as they are and measures before
  and after: "Yes, I agree with these changes and measurements".

## What the code does now

- **A roster makes a row for each item eagerly.** `_compute_roster_slots`
  (`RosterDocument.jl`) walks every item of the source and makes a `RosterRow`
  for each, with one cell for each column. The value cells of a row are lazy,
  but the row objects are not. The table of a roster is lazy: it makes the
  widgets of a row only when the row comes into view.
- **A filter is one computation over all items.** `compute_filter_rows`
  (`Picking.jl`) checks every item. When one value that it read changes, the
  next read checks every item again.
- **A sort is one computation over all items.** `compute_sort_rows` reads the
  keys of every item into a `Vector{Any}` and sorts all of them. When one key
  changes, the next read sorts all items again.
- **Each value takes the general path.** A condition and a sort key find the
  column of a key from its path, for each item, and compare values of type
  `Any`.

## The design

Lazy: nothing computes what no reader reads. Incremental: a change of one item
computes the cells of that item, and the picks move only its row. Both use the
cells as they are: no new kernel mechanism, no new event, no new channel through
the projections. The cells are pull-based, so a computation that reads many
cells runs again as a whole. The pick therefore still walks one cell for each
item, but each of those cells holds its value already.

**D0. The gather stops at each item that it finds** (added after step 1; the
owner, 2026-10-29: "Yes"). The search of a part reports each item of the type and
reads nothing inside it: `walk_document` takes `enter_matches = false`. The inside
of each found item is a part of its own, with a computed cell of its own: the
roster asks the source for it with a new generic of the roster slice,
`get_roster_item_inside(source, entry)`, which answers `nothing` by default, and
keeps the cell by the identity of the item. `ItemsWithin` answers the inside of
each document that it finds. So the start of one task walks the inside of that one
task again, and no other. The search of an inside does not enter the item of the
outer source, which a document can name, and a `TaskDocument` no longer lets a
walk enter its field `group`: that `Ref` names the group that holds the task, and
its docstring already said that a walk must not go round through it.

**D1. A roster makes a row when a reader first reads it.** The slot of an item
is a computed cell that makes the row at its first read, and it keeps the same
row while the item stays. The gather of the parts and the one row for an item
that two parts give stay as they are. With no filter and no sort, a table makes
only the rows that it shows. A filter or a sort reads every row, so it still
makes every row.

**D2. A filter keeps one cell for each item.** The stage of a filter over a
`CellVector` keeps, for each element cell of its input, a computed cell that
says whether the conditions hold for that item. It keeps them from one
computation to the next by the identity of the element cell, as the roster
keeps its rows by the identity of the item. The rows of the filter read these
cells. When one task starts, only the cell of that task computes again; the
others answer the value they hold. A change of the conditions computes all of
them, as a new filter must. The quick text is a condition, so it gets the same.

**D3. A sort keeps one key cell for each item and its last order.** The stage of
a sort over a `CellVector` keeps a computed cell of the keys of each item, by the
identity of the element cell, and the order and the keys that it sorted last.
When the input holds the same element cells in the same order, the sort compares
the keys with the keys it sorted, takes out the rows whose keys changed, and puts
each back at its place with a binary search. Items with equal keys keep the
order of the input, as now. When the input changed, or many keys changed, it
sorts all items again.

**D4. What stays.** The pick keeps its last final rows while a value is
provisional (`make_final_holding_cell`). The IO map, the maps of the paths and
the output stay. A stage over a plain `AbstractVector` has no element cells, so
it stays as it is.

The cells of D2 and D3 are local state of a stage, as the memo of the roster and
the held value of `make_final_holding_cell` are. A computation that runs twice
over the same values answers the same.

## The steps

- [ ] **Step 1 — Measure now.** The script
  `/var/tmp/claude-julia/lazy-arrangement/measure.jl` builds a roster of 22,731
  tasks in `ProjecturedPlatform` alone. It reads the real cells of the stages,
  and it counts the computations. It measures the rows of a roster (cold, and
  warm on a second roster), a new filter, a new sort and a quick text, and the
  start of one task while each is on.

  **Done, 2026-10-29** (Julia 1.13.1, `ProjecturedPlatformTest` environment, a
  load average of about 2):

  | Work | Time | Computations |
  | --- | --- | --- |
  | rows of a roster, first (cold) | 1793 ms | 45,464 |
  | rows of a second roster (warm) | 382 ms | 45,464 |
  | filter `status == :running`, first | 462 ms | 22,733 |
  | the same filter after one task starts | 479 ms | 9 |
  | sort by status after one task starts | 449 ms | 9 |
  | sort by name after one task starts | 455 ms | 8 |
  | quick text after one task starts | 511 ms | 11 |

  The case "a filter, then a sort" of the script read the IO map field
  `output` as a cell holding the vector, so it measured nothing. The script
  must read `iomap.output`.

  A profile (`profile.jl`, ten task starts, each read of the filter cell after
  one start) shows where the 400 to 480 ms go:
  - About 65 % is the gather of the roster: `ItemsWithin` searches the whole
    group of 22,731 tasks again with `search_documents`. The walk read cells
    inside each task (`running`, `executions`, the task, the shadows), so the
    start of one task invalidates the items of the whole part.
  - About 9 % is the filter itself: 16 ms as a direct call, about 40 ms inside
    a computation that reads 22,731 cells.
  - About 6 % is the slots of the roster, which rebuild their dictionaries.
  - The rest is the bookkeeping of a computation with 22,731 dependencies: the
    removal of repeats in an `IdSet` at the end of each run
    (`_remove_repeated_dependencies!`) and the record of each read.

  The estimate of omnet, "about 60 ms" for the end of one task, was wrong: the
  omnet script called `compute_filter_rows` directly, and it did not start a
  task. Step 2 of this plan (lazy rows) does not touch the main cost. The
  gather is the first cost to fix; the owner decides how.
- [x] **Step 2 — D0, the gather stops at each item.**

  **Done, 2026-10-29.** What the work found and decided:
  - A computed cell stops its readers only when it gives the same plain value
    (`isbits`, a `String` or a `Symbol`, `===` to the old one). A vector never
    stops them. So the first form of the change still made every reader of the
    rows compute again: the inside cell of the task that started gave a new empty
    vector, the slots gave a new vector of the same slots, and a sort by name
    sorted again. The cell of an inside now gives `nothing` when the item holds no
    items (`_collect_inside_items`), so a change inside such an item stops at that
    cell. A change inside an item that holds items still gathers the slots again.
  - `collect_roster_parts(::ItemsWithin)` gathers the items of the inner source
    with their insides (`_collect_items_and_insides`), so an `ItemsWithin` of an
    `ItemsWithin` still finds the documents inside documents.
  - The index of the roster reads the places of the parts and of the insides.
  - The numbers, with the same script (median of five, after one task starts):

    | Work | Before | After |
    | --- | --- | --- |
    | filter `status == :running` | 479 ms | 120 ms |
    | sort by status | 449 ms | 118 ms |
    | sort by name | 455 ms | 8 ms |
    | quick text | 511 ms | 187 ms |
    | a filter, then a sort by status | (not measured) | 126 ms |

    The rows the first time stay the same: 2.05 s cold, 395 ms warm. Each item has
    one more computation now, the cell of its inside: 68,195 in place of 45,464.
    What remains after one start is the filter or the sort over every row: steps 4
    and 5.
  - Tests: `test_document_contract` 151, `test_roster` 69, `test_roster_table` 34,
    `test_roster_sources` 19, `test_roster_facets` 30, `test_roster_program` 21,
    `test_arrangement` 10, `test_arrangement_filter_sort` 18,
    `test_task_document` 126, `test_task_views` 70 and `test_task_group` 84 pass.
    The new tests: a walk with `enter_matches = false` reads nothing inside a
    match, and `ItemsWithin` finds the steps inside a step, keeps the rows when a
    step changes, and places a new inner step.
- [ ] **Step 3 — D1, lazy rows of a roster.** The owner asked whether the rows
  should be a lazy list instead; the answer waits until step 2 is measured.
- [x] **Step 4 — D2, a filter keeps one cell for each item.**

  **Done, 2026-10-29.** What the work found and decided:
  - The stage of a filter takes a callable `_FilterRows <: Function` in place of
    a closure, so that `_make_rows_computation` gives a filter over a
    `CellVector` its own computation with `_ItemCells`: the description that the
    cells were made for, the element cells that they follow, and one cell for
    each. A stage over a plain vector, and the first items of a group, keep the
    computation of their function.
  - The conditions are read as plain values (`_read_conditions`: the key, the
    operator and the value of each), so the cells of the items capture no cell of
    a condition. A new description makes new cells for every item.
  - The cell of an item gives a `Bool`, which is a plain value, so a change of an
    item that keeps its answer stops at the cell of that item, and the rows stay
    the same vector.
  - The numbers (after one task starts): the filter 120 ms -> 6.4 ms, the quick
    text 187 ms -> 2.7 ms, a filter of the running tasks and then a sort by
    status 126 ms -> 4.9 ms. A filter the first time takes 476 ms: it computes
    one cell for each item.
  - Tests: the new testset "a change of one item computes the rows of a filter
    only when its answer changes"; `test_arrangement_filter_sort` 21,
    `test_arrangement` 10, `test_arrangement_quick_text` 24,
    `test_arrangement_group` 24, `test_arrange_collection_operation` 20,
    `test_roster` 69, `test_roster_table` 34 and `test_task_views` 70 pass.
- [ ] **Step 5 — D3, a sort keeps one key cell for each item.**
- [ ] **Step 6 — Measure again.** The same script, the numbers to the owner, and
  the cost section of `documentation/package/platform/roster/roster.md`.

## Tests

`test_roster`, `test_roster_table`, `test_roster_sources`, `test_roster_facets`,
`test_roster_program`, `test_arrangement`, `test_arrangement_filter_sort`,
`test_arrangement_quick_text`, `test_arrangement_group` and
`test_arrange_collection_operation`. Steps 3 and 4 add a test that a change of
one item computes the cell of one item, and moves one row.

## Not in this plan

- The table of typed columns and the filter language of the data frame table in
  the platform. It waits until the steps here are measured.
- A kernel mechanism that tells a computation which of its inputs changed. It is
  a new mechanism, and it needs the owner's answer first.
- The filter and sort of the table of a run in omnet-julia (step 5 of its plan).
