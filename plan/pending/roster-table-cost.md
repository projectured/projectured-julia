# The cost of the table of a roster

A roster of 200 open files, with no filter, costs 5540 computations for each key
in one of the files. Without the roster the key costs 16. This plan removes the
two causes that the roster and the undo buffer own, and corrects the texts that
give the wrong cause.

## What the probe found

The probe counted each computation by the place of its code, and each
invalidation by the place of the cell and of its reader. It ran on a headless
window with 200 files, with a walk that reads the `x` and the `y` of every drawn
element, as a paint does.

- **The trigger.** A key replaces the newest entry of the undo list of the file.
  `has_unsaved_edits` reads that list, so the value `has_edits` of the row
  computes again, and gives `true` again. The cell engine stops a write of the
  same plain data, but here the write is a new entry, and every cell after it is
  a computed cell, which the write marks invalid before any of them computes.
- **The slots: 3258 of the 5540.** Each cell of a row in the table is a computed
  slot that reads the value to choose between the document and a text label.
  The table reads every slot when it prints, so one slot that computes again
  prints the whole table again: 603 new labels and a new grid.
- **The grid: 2282 of the 5540, 11 for each row.** One label that computes again
  makes its size invalid. The grid holds the heights of all rows in one cell
  (`_gl_extents_cell`), and each row height reads it. So the height and the top
  of every row become invalid, and the `x`, the `y` and the spanned width of
  every child. Each computes the value that it had. A plain `WidgetTable` costs
  the same, in a pane or with no pane. The pane has no part in it.

## Steps

- [x] **1. The slots of text values are plain cells.** `_make_row_cells` in
  `RosterToGraphics.jl` reads the value once, when it makes the row. A value
  that is text gets a plain cell that holds a label, and the text of the label
  reads the value. A value that is a document keeps a computed slot, so a new
  document shows. Expected: 5540 → about 2282 for the example.
  - Done 2026-10-14. A value that is text when the row is made and becomes a
    document later shows the text of the document. A value that is a document
    keeps the computed slot, so a change of it prints the table again, as
    before.
  - The test "a new value of text draws its label again, and no other cell" in
    `RosterTest.jl` checks that the text of another cell is the same object
    after a change. It fails with the computed slots.
- [x] **2. The undo buffer writes `has_unsaved_edits`.** `UndoBuffer` holds a
  `Bool` field that every change of its lists and of `saved_entry` writes, and
  `has_unsaved_edits` reads that field. A key in a file with edits writes `true`
  again, which invalidates nothing. Expected: the example costs about what it
  costs with no roster.
  - Done 2026-10-14. The field is `has_unsaved_edits`, and the private
    `_record_unsaved_edits!` writes it after `push_undo_entry!`, the join of a
    run of typing, an undo, a redo, `clear_undo_history!` and
    `record_saved_state!`. `_step_undo_history!` takes the buffer as an
    argument for it. All the writes of the lists are in `UndoDocument.jl`.
  - The test "has_unsaved_edits follows each change, and the same answer
    reaches no reader" in `UndoBufferTest.jl` checks each change, and that a
    reader stays valid after a new step and after a join. It fails with the
    computed answer.
  - The counts after steps 1 and 2, for each step after the first, with the
    walk of the paint:

    | | 50 files | 200 files |
    |---|---|---|
    | the history of file 1 grows | 0 | 0 |
    | keys in file 1 | 24 | 24 |
    | `has_edits` changes at each step: a save, then an edit | 632 | 2282 |

    Before the plan, a key in file 1 cost 5561 at 200 files. The last row is
    the cost of the grid, 11 computations for each row.
- [ ] **3. The texts give the measured causes.** The cost of step 7 in
  `plan/pending/cross-cutting-views.md` and "The cost of a change" in
  `documentation/package/platform/roster/roster.md` name the slots and the grid,
  with the counts after steps 1 and 2.

The grid stays as it is. A change of a text that the table shows still costs 11
computations for each row, also when the size of the text stays the same. A stop for a
computed cell whose value stays the same would remove it. That stop changes the
sealed `ReactiveCell.jl`, and is not part of this plan.
