# The open files show as a roster

Status: DONE, 2026-10-22, on the branch `open-files-roster`, in the worktree
`projectured-julia-open-files-roster`. Not landed on `main`.

## The ask

The owner, 2026-10-22, with a screenshot of the explorer of the omnet IDE: "open
files in the explorer uses the generic object notation?" The page of the entry
"Open files" showed `OpenFileList` and `files []`.

To the proposal of a table with one row for each open file (its name, its folder
and its state), the owner answered: "yes, looks better, is it a roster?" To the
question whether to write this as a plan, the owner answered: "yes".

## The problem

1. **The list has no page.** `OpenFileList` ([OpenFileList.jl](../../source/platform/fileformat/OpenFileList.jl))
   has a title, a decoration, the tree children `files` and a pred form. No
   method of `make_graphics_projection` and no row of a natural-graphics table
   names it. So the natural renderer draws it as an object: its type and its
   fields. Part 4b of [the-explorer-shows-what-the-editor-holds.md](../done/the-explorer-shows-what-the-editor-holds.md)
   made the list and its node, and planned no page.
2. **A file page has no facets.** The list holds a `FilePage` for a file that a
   tab or a page shows, and a `FileDocument` for a file that no page holds. Only
   `FileDocument` has the facets `name`, `folder` and `has_edits`
   ([DocumentFile.jl:282](../../source/platform/fileformat/DocumentFile.jl#L282)).
   A roster row of a `FilePage` would have no name.
3. **No facet says that a file changed on disk.** `has_edits` says only whether
   the file has unsaved edits. The conditions `:changed_on_disk` and `:conflict`
   come from the band of a `FilePage`
   ([FilePage.jl:41](../../source/platform/fileformat/FilePage.jl#L41)).

## The model

- **The list holds its table.** `OpenFileList` gets a field `table`, as
  `BackgroundWorkLog` has
  ([BackgroundWorkDocument.jl:54](../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L54)).
  The table is an `ArrangementDocument` with no entry, around
  `Roster(CollectionItems(<reference to files>); columns = ["name", "folder", "state"], title = "Open files")`.
  The roster is linked to the list. A maker `_make_open_file_list()` builds the
  list and its table. `get_session_open_file_list` calls the maker, also in the
  case with no editor. The maker is a function and not an outer constructor,
  because an outer constructor of a `@document` with the same arity fails the
  precompile.
- **The facets of a file.**
  - `FileDocument` gets the facet `state`: the `words` of the `ConditionLook` of
    each condition of `get_document_decoration(file)`, joined with ", ". The
    value is empty when the file has no condition. Examples: "unsaved edits",
    "read only".
  - `FilePage` gets `name`, `folder`, `has_edits` and `state`. The first three
    read the file of the page (`find_page_file`). `state` reads the decoration of
    the page, so it also says "changed on disk" and "unsaved edits, and the file
    changed on disk". A page with no file answers `nothing` for the first three.
  - No file type in projectured-julia or omnet-julia has a field with one of
    these names, so no field hides a facet.
- **The page.** `OpenFileListToWidget` draws a line and, below it, the table,
  as `BackgroundWorkLogToWidget` does
  ([BackgroundWorkLogToWidget.jl](../../source/platform/backgroundwork/BackgroundWorkLogToWidget.jl)).
  The line says "No file is open." or, for example, "3 open files · 1 unsaved".
  The paths map as `table.<rest>` ↔ `children[2].<rest>`. The page is a row of
  the natural-graphics table of the file format slice, beside `FilePage`
  ([FileToContent.jl:120](../../source/platform/fileformat/FileToContent.jl#L120)).
- **One rule for an arrangement that a document holds.** When a person removes
  the last entry of an arrangement, the answer replaces the arrangement with its
  roster. A page that holds its table in a field keeps the arrangement with no
  entry instead, so the next filter has an arrangement to go to. Today
  `_keep_log_arrangement` does this for the log only. The rule moves to the
  arrangement slice as one function, and both pages call it from their
  `read_intent`.
- **The edge.** The file format slice gets the edge `arrangement` in the layering
  table of [PlatformSuite.jl:80](../../test/platform/PlatformSuite.jl#L80). The
  arrangement slice loads before the file format slice.
- **What stays.** The tree children of the list stay `files`. The decoration of
  the list stays: the node shows its count of unsaved files. `find_open_file_document`,
  `add_open_file!` and `remove_open_file!` read and write `files` only. A file
  that keeps a tab with the list still saves no file and no row.

## Steps

1. [x] **The facets of a file.** Add `state` to `FileDocument`, and `name`,
   `folder`, `has_edits` and `state` to `FilePage`, in the file format slice.
   Test: new cases in `test_roster_facets()`. A file with an edit says "unsaved
   edits". A page with a band says "changed on disk". A page with a band and an
   edit says the conflict. A page gives the name and the folder of its file.
   **Done 2026-10-22.** `_format_file_state` in `DocumentFile.jl` joins the
   `words` of `collect_decoration_conditions(decoration)` with ", ", so the
   words come in the order that a tooltip says them. A `FilePage` is a
   `Document`, so it also has the facet `type`. The facets of `TextFile` are now
   `name`, `folder`, `has_edits`, `state` and `type`. `test_roster_facets()`:
   30 of 30 pass.
2. [x] **One rule for a held arrangement.** Move `_keep_log_arrangement` to the
   arrangement slice as one function that takes the holder, the field and the
   answer. Give it a name that follows
   [naming-rules.md](../../documentation/rule/naming-rules.md). The log page
   calls it. Test: `test_background_work()` of the platform passes with no
   change.
   **Done 2026-10-22.** The function is
   `keep_held_arrangement(operation, arrangement, step)` in `Arranging.jl`,
   beside `_take_away_when_empty`, whose answer it reverses. It takes the
   arrangement and its field step, not the holder, because the rule reads
   nothing else of the holder. The name is a plain verb: it answers the
   operation that keeps the arrangement. `test_background_work()` does not
   press "Show all", so a new case in `test_arrangement_menu()` tests the rule:
   a compound, an edit at another field, and an edit of the arrangement itself.
   `test_background_work()`: 19 of 19 pass. `test_arrangement_menu()`: 32 of 32
   pass.
3. [x] **The list holds its table, and the table is its page.** Add the field
   `table`, the maker, `OpenFileListToWidget`, its row in the natural-graphics
   table and the edge `arrangement`. Test: a new testset in
   [ExplorerTest.jl](../../test/platform/explorer/ExplorerTest.jl), beside the
   tests of the list.
   - The page of the entry shows one row for each open file.
   - A row comes when a file opens, and goes when its last holder releases it.
   - An edit in a file changes the `state` cell of its row, and of no other row.
   - A double click on a row opens the page of the file in the navigator.
   - A filter on `state` and the removal of the filter keep the arrangement.
   - `search_documents` and `find_open_file_document` find each open file once.
   Then run `test_explorer()`, `test_roster()` and `test_platform_layering()`.
   **Done 2026-10-22.** What the step found and decided:
   - The maker is `_make_open_file_list()` in `OpenFileList.jl`, and
     `get_session_document!(_make_open_file_list, editor, OpenFileList)` calls
     it. `_count_unsaved_files` gives the count to the decoration and to the line
     of the page.
   - `OpenFileListToWidget` is in its own file, `OpenFileListToWidget.jl`. Its
     paths use `_FILE_PAGE_SECOND_STEPS` of `FilePageToWidget.jl`, the place of
     the second child of a grid, so the slice has no second copy of those steps.
     Five other slices each keep a private `_find_path_below`; a shared helper
     belongs in the kernel and is not in this plan.
   - The test makes the filter with `make_arrangement_change_edit` on the table,
     and presses "Show all" on the page, so the removal goes through the reader
     of the page. A filter from the verb `filter_collection!` needs a reference
     from the root of the editor to the roster, which the explorer page does not
     give to a test.
   - "Of no other row" is checked by the identity of the other row and by its
     value; the test has no counter of computations.
   - `search_documents` finds each node at most once by its definition, so the
     test checks only `find_open_file_document`.
   - `test_platform_layering()`: 7 of 7 for each of the three packages.
     `test_explorer()`: 263 of 263 pass. `test_roster()`: 46 of 46 pass. No
     name of the step is in omnet-julia.
4. [x] **The guides and a live check.** Update
   [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md)
   (the list and its page) and
   [roster.md](../../documentation/package/platform/roster/roster.md) (the rows
   of `FileDocument` and `FilePage` in the table of facets). Open two files in a
   live window, edit one, and take a picture of the page of "Open files". Move
   this plan to `plan/done/`.
   **Done 2026-10-22.** The guides:
   - `fileformat.md` has a section "The open files": the list, its table, its
     page, the kept arrangement and a table of the facets of a file and of a
     page. Its "How it fits" names the edges to the tree, roster and arrangement
     slices and the three natural rows of the slice.
   - `roster.md` has the facet `state` of `FileDocument` and a row for
     `FilePage`.
   - There is no guide of the arrangement slice, so `fileformat.md` and
     `backgroundwork.md` describe `keep_held_arrangement` where their pages use
     it.
   - `explorer.md` lists the new testset.

   The live check: a script in the scratchpad built the application window as
   `run_application` builds it, with two text files, with `SdlBackend` on the
   display `:0`. It called `start_application!` with no MCP and no assistant. It
   pushed a step into the history of `notes.txt` with `push_undo_entry!`, and
   not a key press, because the check is about the page and not about an edit.
   A pushed SDL click on "Open files" in the tree showed the page. The window
   drew "2 open files · 1 unsaved", the headers `name`, `folder` and `state`,
   both files, and "unsaved edits" in the row of `notes.txt`. It drew no
   `OpenFileList`. `write_window_picture` wrote the picture; the node in the
   tree shows its pill "1 unsaved".

## Not in this plan

- A facet `state` for every `Document`. Some document types have a field
  `state`, such as `FileSystemDirectory`, and the field would hide the facet.
- A condition "failed" of a file page. `FilePage` keeps no failure.
- Other columns, such as the count of lines or the time of the last save.

## Open items

- Whether a click on the name of a row must open the file, as a link does in
  the Tasks pane. A roster opens a page on a double click only.
  **Answered 2026-10-22.** The owner agreed that the first column of every
  roster is a link, and a double click on a row still opens it. The plan is
  [the-first-column-of-a-roster-is-a-link.md](the-first-column-of-a-roster-is-a-link.md).
