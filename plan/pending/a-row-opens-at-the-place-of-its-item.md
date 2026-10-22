# A row opens at the place of its item

Status: PENDING, 2026-10-22. It follows the branch `open-files-roster`, in the
worktree `projectured-julia-open-files-roster`.

## The ask

The live check of [the-first-column-of-a-roster-is-a-link.md](../done/the-first-column-of-a-roster-is-a-link.md)
found the address "Explorer › Open files › Open files › Open files › rows[2] ›
todo.txt" after one click on the name `todo.txt`. The proposal: the page that
holds the roster maps the path of a row to the place where it holds the item,
`files[2]`, with one shared rule for the open files and the log of the
background work. To the question "Do you want a plan for the address?", the
owner answered: "yes".

The first version of this plan found the place of an item by a search: the
index of the item in the collection, and the index of its row in the roster.
The owner, 2026-10-22: "wait, when the roster was created, it knew where the
document came from, now we are going to re-search it?" The source walks the
collection when it gathers the items, so it knows the place of each item then.
To the question whether to rewrite the plan so that the source gives the place
and the roster keeps it, the owner answered: "yes".

## The problem

1. **The open names the path of the row in the roster.** A click on the link
   of a row, and a double click on a row, answer
   `OpenPageOperation(nothing, <path>)`. The readers map the path up:
   `RosterRowsToWidget` gives `rows[k].item`, the arrangement puts `document`
   before it, and `OpenFileListToWidget` puts `table` before that. So the
   navigator gets `table.document.rows[k].item`, and the address names the
   arrangement and the roster, which take the title of the list, and the row.
2. **The list holds the item at another place.** `OpenFileList` holds each file
   at `files[j]`, and its node in the tree has the file as a child there. The
   log of the background work holds each record at `rows[j]`, with the same
   table of a roster of its own collection.
3. **The selection has the same path.** A press on a label of a row selects
   `table.document.rows[k].item`, so a key or a menu that acts at the selection
   names the row and not the place of the item.
4. **The roster drops the place that its source knows.** `CollectionItems`
   walks the collection at its reference to gather the items, so it knows the
   index of each item. `RosterItem` holds only the item and `within`, so the
   index is lost.

## The model

- **The source gives the place with the item.** `RosterItem` gets a third
  field, `place`: the path of the item from the link of the roster, or
  `nothing`. `RosterItem(item)` and `RosterItem(item, within)` stay, with
  `place = nothing`. `CollectionItems(<reference>)` gives `<reference>[j]` for
  the item at the index `j`, which it has while it walks the collection. A
  `CollectionItems` of a collection that is no reference, and every other
  source, give `nothing`.
- **The roster keeps the places where it computes its rows.**
  `_compute_roster_slots` walks every item that the source gives, and keeps the
  row of each item by identity. The roster gets a computed field `index`, which
  answers for each item its place and the index of its row in `rows`. It reads
  `rows` and the items that the parts already gathered, so it computes again
  after the rows compute again, and only when a map reads it. A change of the
  collection gathers its part again, so an item gets its new place when a file
  before it closes. The row of the item stays the same object, with its cells
  and its print.
- **Two reads of the index.** `get_roster_item_place(roster, k)` answers the
  place of the item of row `k`, or `nothing`. `find_roster_row(roster, item)`
  answers the index of the row of `item`, or `nothing`. Neither searches.
- **The rule of a held roster.** Two functions in the roster slice, for a
  holder that keeps in the field `step` an `ArrangementDocument` around a
  `Roster`, or the `Roster` alone, whose link is the holder:
  - `find_held_item_path(holder, step, path)`: for
    `step.document.rows[k].item.<rest>`, the place of the item of row `k` with
    `<rest>` after it, such as `files[2].<rest>`. `nothing` when the row has no
    place, and for any other path, such as a cell of a facet, an entry of the
    arrangement or the bar.
  - `find_held_row_path(holder, step, path)`: the inverse. For a path that
    starts with the reference of a `CollectionItems` source and an index, such as
    `files[j].<rest>`, it reads the item at `files[j]`, finds its row with
    `find_roster_row`, and answers `step.document.rows[k].item.<rest>`.
    `nothing` when no row shows the item.
- **The two pages use them.** `map_reference_backward` of
  `OpenFileListToWidget` and of `BackgroundWorkLogToWidget` answers
  `find_held_item_path` before the path of the table, and
  `map_reference_forward` maps a path at the place of an item through
  `find_held_row_path`. So the open of a row, by its link or by a double click,
  reaches the navigator as `files[j]`, and a selected row is selected at
  `files[j]`. A path that the rule does not map goes as it goes now.
- **The address.** After a click on `todo.txt` the address is "Explorer › Open
  files › todo.txt". Parent goes back to the list. The tree marks the node of
  the file under "Open files" when that node is open.

## Steps

1. [x] **The source gives the place, and the roster keeps it.** Add `place` to
   `RosterItem`, the places of `CollectionItems`, the field `index` of
   `Roster`, `get_roster_item_place` and `find_roster_row`. Test: new cases in
   `test_roster()`. A roster of `CollectionItems` at a reference answers the
   place of each row. An insert before an item gives the item its new place,
   and its row stays the same object. A roster of a plain collection answers
   `nothing`. `find_roster_row` finds the row of an item and answers `nothing`
   for an item that no row shows. Then run `test_roster_sources()` and
   `test_roster_table()`.
   **Done 2026-10-22.** What the step found and decided:
   - `RosterItem(item, within = nothing)` makes an item with `place = nothing`,
     so the seven sources that make an item, here and in the tests, stay as
     they are. omnet-julia makes no `RosterItem`.
   - `CollectionItems` of a reference gives
     `extend_reference(<reference>, ElementReferenceStep(j))` for the item at
     `j`. A collection given as itself gives no place, and a reference that
     reaches nothing gives no item, as before.
   - The field `index` of `Roster` comes after `link`, before the field
     `mouse_target` that `@document` adds. Its computation,
     `_compute_roster_index`, reads `rows` first, so the rows compute before it,
     and then the cell of the items of each part in the memo of the rows, which
     the rows computation already filled. `RosterIndex` holds the two `IdDict`s.
     An item that two parts give keeps the place of the first part.
   - `test_roster()`: 53 of 53 pass, 7 of them new. `test_roster_sources()`:
     19 of 19. `test_roster_table()`: 28 of 28. `test_roster_facets()`: 30 of
     30.
2. [x] **The pages map through the places.** Add `find_held_item_path` and
   `find_held_row_path`, and change the two maps of `OpenFileListToWidget` and
   of `BackgroundWorkLogToWidget`. Test: in the testset of the open files in
   `test_explorer()`, after one click on a name the address of the navigator is
   `files[j]` of the list, the bar draws "Open files" once before "todo.txt",
   and a press on a label of a row selects `files[j]`. In
   `test_background_work()`, a double click on a row opens its record at
   `rows[j]` of the log. Then run `test_roster_table()`,
   `test_navigator_gestures()` and `test_document_tree()`.
   **Done 2026-10-22.** What the step found and decided:
   - The two rules are in `RosterDocument.jl`, after `find_roster_row`.
     `_find_held_roster(holder, step)` reads the field and answers the roster,
     alone or in an arrangement, only when its link is the holder.
     `_drop_reference_steps` keeps the types of the rest of a path, as the maps
     of a page keep them.
   - The backward map of each page builds the path of the table as before and
     then answers `find_held_item_path` of it, or the path of the table. The
     forward map first answers `find_held_row_path` of the path, or the path,
     and then maps the path of the table as before. So the answer of "Show
     all", which names `table` alone, keeps its path, and
     `keep_held_arrangement` still finds it.
   - The test of the open files presses a label of a row, which selects
     `files[1]`, and then filters the table to the file `b.txt` alone, so its row
     is the first that the table shows. One click on its name opens it at
     `files[2]`, and the window draws "Open files" twice, in the tree and in the
     address, and no `rows[`.
   - Pass: `test_roster()` 62 of 62 (9 new), `test_explorer()` 267 of 267 (4
     new), `test_background_work()` 21 of 21 (2 new), `test_roster_table()` 28
     of 28, `test_navigator_gestures()` 26 of 26, `test_document_tree()` 130 of
     130.
3. [ ] **The guides and a live check.** Update
   [roster.md](../../documentation/package/platform/roster/roster.md) (the
   place of an item, the index, the rule of a held roster),
   [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md)
   and [backgroundwork.md](../../documentation/package/platform/backgroundwork/backgroundwork.md).
   In a live window, open a file from the page "Open files" by its name, take a
   picture of the address, and press Parent. Move this plan to `plan/done/`.

## Not in this plan

- The place of an item of `TabDocuments`, `ItemsWithin`, `StoreRecords` or
  `SystemProcesses`. Their items keep `place = nothing`.
- The address of a roster that is the content of a navigator itself, such as a
  roster in a tab. Its rows are its own place, and its address stays
  `rows[k].item`.
- The look of a link and of a link in a selected row (the open item of the plan
  of the link).

## Open items

- None.
