# The editor shows a JSON file through its views

**Status:** proposed on 2026-11-19. Not approved, and not started.

This plan is the second of two plans in the place of plan 4b of point 4 of the
order in section 13.3 of `plan/tentative/content-and-view-for-the-whole-project.md`.
The first is `plan/done/a-file-and-its-undo-steps-have-views.md`, which is on
`main`. The design is `documentation/design/content-and-view.md`. The steps of
this plan come from a measurement, which the section "The measurement" gives.
Plan 4c, "The JSON content keeps no selection", comes after this plan, and then
the review of the JSON domain by the owner.

The plan lands nothing and pushes nothing: it ends with a request to land.

**If a step needs a change of a kernel file, or a mechanism that this plan does
not name, the work stops and the session asks.**

## The problem

A file view can hold the views of what its file holds since the first plan, but
no place of the editor asks for them. When each file view of a JSON file gets
its views, the tab draws the views, and the caret is a path of the views. Each
feature that names a place in the file by a path through the content then
misses what the tab draws.

```julia
tab_1 = open_file!("people.json")
people_1 = get_edited_document(tab_1)          # the JsonArray, with a path through the file

# the part, as each feature names it now:      tabs[1].content.file.content.content.elements[2]
# the same part, as the tab draws it:          tabs[1].content.content.content.elements[2]

replace_referenced_value!(people_1[2]["name"], JsonString("Adele"))
# on main:             the name changes, and the file has one more undo step
# with the views on:   the name changes, and the file has NO undo step

find_selected_part()                           # after a click in a name
# on main:             the JsonString that holds the caret
# with the views on:   a JsonStringView
```

Below the file view, the two paths have the same steps, because each view names
its child fields as its content does. They differ in the first step: `file` on
the side of the content, and nothing on the side of the views.

## The measurement

A copy of `main` at `0a4f46451` got one change: each new file view of a JSON
file shows the file through its views. Each suite ran in a process of its own,
in the copy and at `main`.

| Suite | `main` | The copy | New failure lines |
| --- | --- | --- | --- |
| `test_integration()` | 3232939 passed, 627 failed, 18 errored, 2830 broken | 3232889 passed, 661 failed, 29 errored, 2830 broken | 45 |
| `test_platform()` | 236605 passed, 15 failed, 21 broken | 236596 passed, 19 failed, 1 errored, 21 broken | 3 from the change, 2 not |
| `test_json()` | 1443 of 1443 | 1437 of 1443 | 6, all from the change of the copy itself |
| `test_markdown()` | 358 of 358 | 358 of 358 | 0 |
| `test_mcp()` | 550 of 550 | 550 of 550 | 0 |
| `test_sdl()` | 1342 passed, 4 failed, 1 errored | the same | 0 |
| `test_video()`, `test_console()`, `test_pdf()`, `test_web()` | 82, 150, 54, 161 | the same | 0 |

- The numbers of `main` for the platform, JSON and Markdown suites are from the
  wide check of the first plan. Its source is the source of `main` at
  `0a4f46451`. The other numbers of `main` are from a run of this measurement.
- No failure line of `main` is gone in the copy.
- The 650 failure lines of the integration suite at `main` are on 30 source
  lines. Most are in the sweeps that run each example, and the copy has the same
  ones.
- Two new failure lines of the platform suite are not from the change.
  `TaskWorkItemTest.jl:171` errored at `main` too in an earlier run.
  `TaskVerbsTest.jl:102` passes 3 of 3 times alone in the copy.
- The 6 failures of the JSON suite: one is the import form of the change of the
  copy, and five are tests of the first plan that compare a file view with no
  views against one with views (`JsonFileViewContentTest.jl:64`, `65`, `90`,
  `91`, `93`).
- The precompile of the copy has no error. The workload of the JSON package
  opens a JSON file in the application window, and it runs with the views.

The 48 new failure lines, by their cause:

| Cause | Lines | Where |
| --- | --- | --- |
| **A. A change for a part does not reach the tab.** `read_rooted_operation(editor, place, operation)` sends the operation down the path `place`, which goes through `file`. The tab draws the views, so no reader is on that path. The edit still runs on the content, but the undo buffer of the file does not record it, and a command of a part is not found. | 15 | `ReferencedDocumentEditorTest.jl:316`–`387` (11), `AssistantVerbsTest.jl:128`–`134` (4) |
| **B. The clipboard keys do nothing at a caret in a view.** The clipboard reads the selection, evaluates it, and gets a view where it expects a content: a cut of a range, a cut of an element, Delete on an element, a paste at a caret, a paste into an empty place, a paste over a whole string. | 14 | `ClipboardEditTest.jl:143`–`252`. 6 of them are errors of the test helper `_ce_file`, which spells the path through `file`. |
| **C. The selected part is a view.** Alt+Up selects a `JsonStringView` and then the `FileView`, where it selected the `JsonString` and the `JsonFile`. The note of a part (Ctrl+N) keeps the `FileView`. "Copy reference" writes the path of a view. | 10 | `ApplicationTest.jl:1398`–`1468`, `2088`, `2163` |
| **D. A file on the page of the explorer takes no caret.** The map of the file row adds and takes off the step `get_edited_field(view)`, which is `file`, and the page draws the views. | 2 | `ExplorerTest.jl:379`, `388` |
| **E. The tooltip for the part under the pointer does not open.** The row of `JsonFile` reads the pointer target of the file, and the pointer target is in the views. | 2 | `PointedPartTest.jl:6`, `18` |
| **F. The page of a file that changed on the disk shows the old text too.** | 1 | `ExplorerTest.jl:615` |
| **G. A test spells the shape of today**: the path of a caret through `file`, or the file as the content of the scroll pane. | 4 | `FileTabTest.jl:132`, `ReferencedDocumentEditorTest.jl:431`, `436`, `454` |

The first two lines of the example in "The problem" are measured. The answer of
`find_selected_part` there is read from the code and from cause C: no test of
the measurement calls it after a click.

## The decisions of the owner that this plan builds

- **Point 4 of the order is three plans, and plan 4b is two plans** (2026-11-18:
  "Yes", and "yes" with the first plan). This plan turns the views on for JSON
  files, and each feature that names a place by a path through the content
  takes the path through the views.
- **The JSON content keeps its selection field in this plan**, with no use in a
  tab. Plan 4c removes it, and brings the step `.viewed`.
- **`make_document_view` stays a function for a page only, with the name
  `make_page_view`** (2026-11-19). A file view is the page of a file in that
  sense. This plan does not do the rename.
- **A gesture at the caret belongs to the key table of the view**
  (2026-11-17).

## Proposed decisions

They are the decisions of the session. They become decisions of the owner when
the owner approves the plan.

1. **A file says whether a new view of it shows it through views.** One
   function of the file answers, with the default `false`, and the JSON package
   answers `true` for a `JsonFile`. It is the default of the keyword `views` of
   `make_file_view`. No caller changes. The function goes in point 11 of the
   order, when each file shows through views.
   *Not chosen:* the views for each file now. A Markdown file and a text have
   view types too, and their tabs wait for the review of the owner.
2. **The reference of a part of a file stays a path through the content.**
   `get_edited_field(::FileView)` stays `file`. So `get_edited_document`, the
   document tree, the search and each reference that the assistant holds do not
   change, and the same reference is correct for a tab with views and for a
   place with none. The reason: an operation belongs to the content.
   *Not chosen:* a reference through the views that ends in `viewed`. A child of
   such a reference does not follow the views, and the kernel must not know a
   view.
3. **Two functions of a view change a reference between the content and the
   view.** One takes a reference below the content that the view shows and
   answers the reference below the view of the same place, as the view draws it.
   The other is the reverse, and it answers `nothing` for a place that only the
   view has, such as its scroll pane. The default of the two is the step
   `get_edited_field(view)`, which is what three maps do by hand now. A file
   view with views has methods of its own. Point 4 of the order names these two
   functions already. In this plan the steps below a file are equal on the two
   sides. Plan 4c gives them the step `.viewed`.

   ```julia
   # proposed names
   map_content_reference_to_view(view, @reference(file, .content.content.elements[2]))
   #   a file view with views:    .content.content.elements[2]
   #   a file view with no view:  .file.content.content.elements[2]
   map_view_reference_to_content(view, reference)     # the reverse
   ```
4. **The file view sends a change for a part of its file to the view that shows
   the part.** A change whose route starts with the step `file` goes to what the
   scroll pane shows, with the reference of decision 3. So
   `read_rooted_operation` and each of its callers stay as they are, and the
   undo buffer of the file records the edit, because the edit goes through the
   printer of the view of the buffer.
5. **The selected part and the part under the pointer are content.**
   `find_selected_part`, `find_part_under_pointer`, the note of a part, "Copy
   reference" and the value that a clipboard key reads answer the content, with
   the reference through the content. So a part that a person selected and a
   part that `get_edited_document` reaches have one form. When Alt+Up reaches
   the file view, the selected part is the file.
6. **The code that selects a part of a content writes the caret of the view.**
   `select_part!`, the open of a page at a place, and the caret that a clipboard
   edit answers change their reference with decision 3 before they write the
   selection. The selection of the window is then a path of the views.
7. **The tooltip row of a file reads the pointer of its file view.** The
   function of the row gets the part under the pointer as content, with
   decision 5. `find_pointed_part` of a bare file stays for a file that no view
   shows.

## Facts of the code

- **Three maps add the step of the view by hand.** `FileSystemFileToWidget.jl`
  lines 27 to 56, `DashboardToWidget.jl` lines 271 to 292, and
  `_find_opened_content` in `NavigatorPageOpen.jl` lines 177 to 215. Each uses
  `get_edited_field(view)`.
- **`read_rooted_operation` is a kernel function** (`ReadEvaluatePrint.jl` line
  87). It makes an intent with the route `place`, and the readers pass it down.
  This plan does not change it.
- **The clipboard is a wrapper around the document of the window.** Its helpers
  evaluate the selection: `_selected`, `_find_text_target`,
  `_find_whole_value_target`, `_find_writable_slot`, `_find_paste_target` and
  `_make_whole_delete` in `Clipboard.jl`. It sends an edit to its place with
  `_read_placed_operation`, which is a route.
- **The selection walk lists each field.** `_child_document_refs` in `Focus.jl`
  does not ask `is_field_walked`, so Alt+Down from a file view sees `file`,
  `scroll` and `content`.
- **The reload repairs the selection of the window.** `_repair_selection!` in
  `DocumentFile.jl` line 669 cuts the selection of the root to a valid path. Its
  second branch reads the stored selection of the file, which a file with views
  does not have.
- **`find_pointed_part(file)` reads `file.mouse_target`** (`TooltipNote.jl` line
  76). `JuliaFile.jl` has a row of the same form.
- **The explorer puts the keys back from the stored selection of the page**
  (`ExplorerToWidget.jl` lines 262 to 296).
- **The arrangement of a tab names a place by a path from the content of the
  tab** (`PaneArrangement.jl`), which is the file view.
- **No test opens a JSON file** on a card of a dashboard, with the find or the
  filter of a tab, from a search link of the explorer, or by a visit of the
  navigator into a file.
- **About twelve places in the tests outside the JSON suite spell a path through
  `file`**, in `ApplicationTest.jl`, `ClipboardEditTest.jl`, `FileTabTest.jl`,
  `ReferencedDocumentEditorTest.jl`, `UserInterfaceFileTest.jl` and
  `WindowFrameGuardTest.jl`.

## Steps

Each step ends with a commit. Each step runs the tests that it names, and the
tests of the steps before it.

- [ ] **1. The JSON domain turns the views on for its files.** Proposed
  decision 1. The five tests of the first plan that compare a file view with no
  views pass `views = false`.
  *Check:* `test_json()` passes whole. The 48 failure lines of the measurement
  are the failures of the branch now.
- [ ] **2. The two functions of a view, and the three maps.** Proposed decision
  3. The row of a file on the page of the explorer, the card of a dashboard and
  the open of a page call the functions.
  *Check:* cause D passes. New tests: a JSON file on a card of a dashboard and
  on the page of the explorer takes a click, and the caret shows at the
  character under the pointer; a key there edits the file.
- [ ] **3. A change for a part of a file reaches the view.** Proposed decision
  4.
  *Check:* cause A passes: the editing verbs, a command of a part, a group of
  changes, and one undo step of the file for each. The test "a value found by
  identity at two places has no reference" passes as on `main`.
- [ ] **4. The selected part and the part under the pointer are content.**
  Proposed decisions 5 and 7.
  *Check:* causes C and E pass. A new test: `find_part_under_pointer` over a
  JSON string in a tab answers the `JsonString`.
- [ ] **5. A selection for a part of a content shows in the view.** Proposed
  decision 6: `select_part!`, `open_page!` at a part of a file, a visit of the
  navigator, a search link of the explorer, and a row of the document tree.
  *Check:* new tests, one for each of the five: the caret or the selection frame
  is drawn at the part. The test of `select_part!` that compares the selection
  of the window with the reference of the part compares it with the reference
  through the views.
- [ ] **6. The clipboard keys at a caret of a view.** Proposed decisions 5 and
  6, at the one place where the clipboard reads the selection.
  *Check:* cause B passes, with the helper `_ce_file` on the new shape. A copy
  in one tab and a paste in a second tab of the same file is one new test.
- [ ] **7. Alt with the arrow keys, and the reload.** Alt+Down from a file view
  goes into what the view shows. After F5, after "Load it" and after Back to a
  page whose file changed, the page shows only the new text, and the caret is at
  a valid place.
  *Check:* cause F passes. New tests: Alt+Down and Alt+Up through a file view,
  and the caret after a reload of a file that got shorter.
- [ ] **8. The find and the filter of a JSON tab.** A test first: Ctrl+F and the
  filter menu on a JSON array in a tab, on `main` and on the branch. The branch
  must do what `main` does.
  *Check:* the new test. If the arrangement needs more than the functions of
  decision 3, the work stops and the session asks, because point 6 of the order
  moves the arrangement into the view of a collection.
- [ ] **9. The tests that spell the shape of today.** Cause G, and each of the
  twelve places that still spells a path through `file` for what a tab draws.
- [ ] **10. The wide check and the guides.** `test_platform()`,
  `test_integration()`, the suites of JSON, Markdown and MCP, the suites of the
  backends, and the six guards, on the branch and at its base. The time of the
  first frame of a JSON tab, on the branch and at its base. The guides of the
  file format, of JSON, of the explorer and of the assistant. "The code now" in
  the design document. `Pkg.precompile` of `omnet-julia` against the branch,
  with a count of the compiled packages. The plan moves to `plan/done/`. Then
  the session asks for the landing, and for the push apart.

## Risks

1. **Other plans change the same files.** `a-reader-is-split-by-its-jobs.md`
   has three open steps, and its step 6 removes the form of `read_intent` with
   three arguments. The rename to `make_page_view` can land from another
   session. The branch follows `main` by a rebase, and the wide check runs again
   after it.
2. **A walk reaches a document two times**, through `file` and through
   `viewed`. A search by identity then finds two places and gives no reference.
   The measurement shows no such failure. Step 3 has the test for it.
3. **The clipboard has many helpers that evaluate the selection.** Step 6
   changes the reference at the one place where the wrapper takes the selection.
   If a helper needs the view itself, the step records which one and why.
4. **The arrangement.** Step 8 has a stop rule.
5. **The JSON content still keeps a selection field.** Two tabs of one file have
   two carets in their views, but a part that no view shows keeps one caret. It
   ends with plan 4c.
6. **The recorded precompile lists.** They name `FileView` with its type
   parameters. The reader split records the lists again in its step 8. This plan
   records again only when a list is over the limit.

## Not in this plan

- **The step `.viewed` in each caret, the selection field of the JSON content,
  the kernel hook, and the caret place in an operation.** Plan 4c.
- **The rename of `make_document_view` to `make_page_view`, and its new
  default.** Point 7 of the order, unless plan 4c needs them before.
- **A tab of another domain.** A Markdown file, a text and a Julia file show as
  they do now.
- **The page of the navigator for a part inside a JSON file.** It shows the part
  as content with no view, as now. It gets the view with the default of
  `make_page_view`.
- **The arrangement in the view of a collection.** Point 6 of the order.
- **`FileView` below `ContentView`, with the field `viewed`.** Point 7 of the
  order.
