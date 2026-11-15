# A row opens at the place of its item

Status: DONE, 2026-10-22, on the branch `open-files-roster`, in the worktree
`projectured-julia-open-files-roster`. Not landed on `main`.

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
  - `retarget_held_row_open(operation, holder, step)`: each open of a page in
    `operation` whose path `find_held_item_path` maps, retargeted to the place
    of the item, through a compound and a wrapping operation, as
    `keep_held_arrangement` walks them.
- **The two pages use them.** The reader of `OpenFileListToWidget` and of
  `BackgroundWorkLogToWidget` calls `retarget_held_row_open` after
  `keep_held_arrangement`. So the open of a row, by its link or by a double
  click, reaches the navigator as `files[j]`. The maps of the paths stay, so a
  selected row stays selected at the path of the row, which the table shows.
  (Step 2 changed this part of the model: see its notes.)
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
2. [x] **The pages open a row at the place of its item.** Add
   `find_held_item_path` and `retarget_held_row_open`, and call it in the
   readers of `OpenFileListToWidget` and of `BackgroundWorkLogToWidget`. Test:
   in the testset of the open files in `test_explorer()`, after one click on a
   name the address of the navigator is `files[j]` of the list, the bar draws
   "Open files" once before "todo.txt", and a press on a label of a row selects
   the row. In
   `test_background_work()`, a double click on a row opens its record at
   `rows[j]` of the log. Then run `test_roster_table()`,
   `test_navigator_gestures()` and `test_document_tree()`.
   **Done 2026-10-22.** What the step found and decided:
   - **The first version mapped every path, and it lost the selected row.** It
     mapped the paths of the pages both ways: backward from a row to the place
     of the item, and forward from the place, through `find_held_row_path`, to
     the row. The tests passed, but the live check showed a selection at
     `files[1]` with no selected row in the table. Each document on the path of
     the selection holds its part of the path, and the printers of the table
     read the selection of their own documents. A selection at `files[1]` goes
     from the list to the file and not through the table, so the table has no
     selection to show, and the forward map of the page can not give it one.
   - **So only the open names the place.** `retarget_held_row_open` rewrites
     the opens in the answer of the reader, as `keep_held_arrangement` rewrites
     the answer of "Show all". The maps of the paths of the two pages are as
     before the step. `find_held_row_path` is gone. `find_roster_row` and the
     rows of `RosterIndex` stay from step 1, with their tests, and no page reads
     them now.
   - The two rules are in `RosterDocument.jl`, after `find_roster_row`.
     `_find_held_roster(holder, step)` reads the field and answers the roster,
     alone or in an arrangement, only when its link is the holder.
     `_drop_reference_steps` keeps the types of the rest of a path.
   - The test of the open files presses a label of a row, which selects
     `rows[1].item`, and then filters the table to the file `b.txt` alone, so its
     row is the first that the table shows. One click on its name opens it at
     `files[2]`, and the window draws "Open files" twice, in the tree and in the
     address, and no `rows[`.
   - Pass: `test_roster()` 63 of 63, `test_explorer()` 267 of 267,
     `test_background_work()` 21 of 21, `test_roster_table()` 28 of 28,
     `test_navigator_gestures()` 26 of 26, `test_document_tree()` 130 of 130.
3. [x] **The guides and a live check.** Update
   [roster.md](../../documentation/package/platform/roster/roster.md) (the
   place of an item, the index, the rule of a held roster),
   [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md)
   and [backgroundwork.md](../../documentation/package/platform/backgroundwork/backgroundwork.md).
   In a live window, open a file from the page "Open files" by its name, take a
   picture of the address, and press Parent. Move this plan to `plan/done/`.
   **Done 2026-10-22.** `roster.md` has the paragraphs "The place of an item"
   and "A roster that a page holds", which says why the selection stays the
   path of the row, and the row of `CollectionItems` in the table of the
   sources gives the place. `fileformat.md` and `backgroundwork.md` say that
   the reader of the page opens a row at its place.

   The live check, with the script of the plans before: a press on the state of
   `notes.txt` selects its row, and the table shows it selected. One click on
   the name `todo.txt` opens its page with the address "Explorer › Open files ›
   todo.txt"; the tree opens "Open files" and marks `todo.txt`. Parent shows
   the list again. The navigator then selects the page that it left,
   `files[2]`, so the table shows no selected row after Parent.

## Not in this plan

- The place of an item of `TabDocuments`, `ItemsWithin`, `StoreRecords` or
  `SystemProcesses`. Their items keep `place = nothing`.
- The address of a roster that is the content of a navigator itself, such as a
  roster in a tab. Its rows are its own place, and its address stays
  `rows[k].item`.
- The look of a link and of a link in a selected row (the open item of the plan
  of the link).

## Open items

- After Parent, the navigator selects the page that it left at its place,
  `files[j]`, and the table shows no selected row: the selection of a row is
  the path of the row.
