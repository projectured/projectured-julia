# The open files show as a roster

Status: PENDING, 2026-10-22. No branch and no worktree yet.

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
2. [ ] **One rule for a held arrangement.** Move `_keep_log_arrangement` to the
   arrangement slice as one function that takes the holder, the field and the
   answer. Give it a name that follows
   [naming-rules.md](../../documentation/rule/naming-rules.md). The log page
   calls it. Test: `test_background_work()` of the platform passes with no
   change.
3. [ ] **The list holds its table, and the table is its page.** Add the field
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
4. [ ] **The guides and a live check.** Update
   [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md)
   (the list and its page) and
   [roster.md](../../documentation/package/platform/roster/roster.md) (the rows
   of `FileDocument` and `FilePage` in the table of facets). Open two files in a
   live window, edit one, and take a picture of the page of "Open files". Move
   this plan to `plan/done/`.

## Not in this plan

- A facet `state` for every `Document`. Some document types have a field
  `state`, such as `FileSystemDirectory`, and the field would hide the facet.
- A condition "failed" of a file page. `FilePage` keeps no failure.
- Other columns, such as the count of lines or the time of the last save.

## Open items

- The name of the function of step 2.
- Whether a click on the name of a row must open the file, as a link does in
  the Tasks pane. A roster opens a page on a double click only.
