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

## The model

- **A held roster of the holder's own collection.** The rule applies when the
  holder keeps in a field, such as `table`, an `ArrangementDocument` around a
  `Roster`, or the `Roster` alone, whose source is
  `CollectionItems(<reference>)` and whose link is the holder. The reference
  is the place of the collection in the holder, such as `files` or `rows`. The
  rule reads it from the source, so a page names only the field of its table.
- **Two functions in the roster slice.**
  - `find_held_item_path(holder, step, path)`: for a path below the field
    `step` that reaches the item of a row, `step.document.rows[k].item.<rest>`,
    the place of the item in the holder, `<reference>[j].<rest>`. `j` is the
    index of the item in the collection, by identity. `nothing` for any other
    path, such as a cell of a facet, an entry of the arrangement or the bar.
  - `find_held_row_path(holder, step, path)`: the inverse, for
    `<reference>[j].<rest>`: the path of the row that shows that item,
    `step.document.rows[k].item.<rest>`, with `k` the index of its row in
    `rows` of the roster, by the identity of the item. `nothing` when no row
    shows the item.
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
- **The cost.** Each direction scans one list: the collection for `j`, or the
  rows of the roster for `k`. The open files are a few files. Step 2 counts the
  rows of the log in a long session of the live check, and records whether a
  scan of that size in a map of a path is fast enough.

## Steps

1. [ ] **The shared rule.** Add `find_held_item_path` and
   `find_held_row_path` to the roster slice. Test: new cases in `test_roster()`
   with a small holder that keeps an arrangement of a roster of its own
   collection: a path to an item and below it maps both ways, a filter and a
   sort do not change the place of the item, and a path to a facet cell, to an
   entry of the arrangement or to an item that no row shows answers
   `nothing`.
2. [ ] **The two pages use it.** Change the two maps of `OpenFileListToWidget`
   and of `BackgroundWorkLogToWidget`. Test: in the testset of the open files
   in `test_explorer()`, after one click on a name the address of the navigator
   is `files[j]` of the list, the bar draws "Open files" once before
   "todo.txt", and a press on a label of a row selects `files[j]`. In
   `test_background_work()`, a double click on a row opens its record at
   `rows[j]` of the log. Then run `test_roster_table()`,
   `test_navigator_gestures()` and `test_document_tree()`.
3. [ ] **The guides and a live check.** Update
   [roster.md](../../documentation/package/platform/roster/roster.md),
   [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md)
   and [backgroundwork.md](../../documentation/package/platform/backgroundwork/backgroundwork.md).
   In a live window, open a file from the page "Open files" by its name, take a
   picture of the address, and press Parent. Move this plan to `plan/done/`.

## Not in this plan

- The address of a roster that is the content of a navigator itself, such as a
  roster in a tab. Its rows are its own place, and its address stays
  `rows[k].item`.
- A source other than `CollectionItems` of the holder's own collection.
- The look of a link and of a link in a selected row (the open item of the plan
  of the link).

## Open items

- Whether a scan of the rows of the log in a map of a path is fast enough
  (step 2 measures it).
