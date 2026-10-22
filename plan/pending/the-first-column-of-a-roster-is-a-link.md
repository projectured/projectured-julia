# The first column of a roster is a link

Status: PENDING, 2026-10-22. It follows the branch `open-files-roster`, in the
worktree `projectured-julia-open-files-roster`.

## The ask

The open item of [the-open-files-show-as-a-roster.md](../done/the-open-files-show-as-a-roster.md)
asked whether a click on the name of a row must open the file. The owner,
2026-10-22: "what do you suggest double click or single click? shouldn't it be
consistent?" The proposal: in every roster, the first column is a link when its
value is text. One click on it opens the item of the row, and a double click on
a row still opens it. To the question "Do you want the first column of every
roster to become a link?", the owner answered: "yes, agreed".

## The rule

The platform opens a part in two ways, and this plan keeps both:

- **A link opens on one click.** The names on the page of a folder, the titles
  in the Tasks pane, the entries on the page of a section and the items of the
  address bar are links. Ctrl and a click open the page in a new tab.
- **A row or a node opens on a double click.** The first click selects it. A
  node of a tree, a file in the Files tree, a row of a roster and the number of a
  row of a data frame open so.

A roster has no link today. So the page "Open files" opens a file on a double
click, and the page of a folder opens a file on one click on its name.

## The problem

1. **No roster cell is a link.** `_make_row_cells` in
   [RosterToGraphics.jl](../../source/platform/roster/RosterToGraphics.jl) makes
   a `WidgetLabel` for a value that is text, and shows a value that is a
   document as that document. A press on a label selects the item of the row.
2. **Three pages each keep a copy of the gestures of a link.** The page of a
   section (`_make_section_link` in `ExplorerSectionToWidget.jl`), the page of a
   folder (`_build_folder_row` in `FileSystemDirectoryToWidget.jl`) and the
   Tasks pane (`_make_open_gestures` in `TaskGroupToWidget.jl`) each bind a click
   to `OpenPageOperation(document, reference, :here)` and Ctrl and a click to
   `:new_tab`. A roster would be the fourth copy.

## The model

- **One maker of the gestures of a link.** The widget slice, which owns
  `OpenPageOperation`, gets `make_open_page_gestures(document, reference;
  domain)`: a click opens the page here, and Ctrl and a click open it in a new
  tab. The three pages call it.
- **The first cell of a row is a link.** When the value of the first column of
  a row is not a document, `_make_row_cells` makes a `WidgetButton` in place of
  the label. Its text follows the value, as the label does. Its gestures are
  those of `make_open_page_gestures(nothing, EmptyReference(); domain =
  "roster")`: the path form, which opens the part itself. The reader of the
  rows maps the path of the cell to the item of its row, as it does for a press
  on a label, so the link opens the same page as a double click on the row.
  Step 2 checks this mapping first.
- **What stays.** A press on any other cell selects the item of the row. A
  double click on a row opens it. A first column that holds a document shows
  that document, so a key there edits it. A roster with no column has no link.
- **Every roster takes the rule.** The open files, the log of the background
  work, the tasks of `:tasks`, the frames and the logs. No roster opts in or
  out.

## Steps

1. [ ] **One maker of the gestures of a link.** Add `make_open_page_gestures`
   to the widget slice, beside `OpenPageOperation`, and make the page of a
   section, the page of a folder and the Tasks pane call it. Test:
   `test_explorer()` and `test_task_views()` pass with no change.
2. [ ] **The first cell of a row is a link.** Change `_make_row_cells`. Test:
   new cases in `test_roster_table()`. A click on the link opens the item here,
   Ctrl and a click open it in a new tab, a press on another cell selects the
   item and opens nothing, and a first column that holds a document stays a
   document. In the testset of the open files in `test_explorer()`, one click on
   the name of a file opens the page of that file. Then run `test_roster()` and
   `test_background_work()`.
3. [ ] **The guides and a live check.** Update
   [roster.md](../../documentation/package/platform/roster/roster.md) ("A page
   from a row") and the guide of the widget slice for the maker. In a live
   window, take a picture of the page "Open files" with the link in the first
   column, and open a file with one click. Move this plan to `plan/done/`.

## Not in this plan

- A link in a column other than the first.
- A link look for a column that a person chooses.

## Open items

- How a link looks in a row that the person selected: the color of the link on
  the color of the selection.
