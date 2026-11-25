# The editor shows a JSON file through its views

**Status:** approved by the owner on 2026-11-19 ("yes", to "Do you approve this
plan, so that I start it in a worktree?"). Done on 2026-11-20 on the branch
`json-tab-views`: all ten steps.

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

The session proposed them, and the owner approved them with the plan on
2026-11-19.

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

- [x] **1. The JSON domain turns the views on for its files.** Proposed
  decision 1. The five tests of the first plan that compare a file view with no
  views pass `views = false`.
  *Check:* `test_json()` passes whole. The 48 failure lines of the measurement
  are the failures of the branch now.

  Done on 2026-11-19. The function is `is_file_shown_through_views(file)`, in
  `FileView.jl`, exported by the file format module. `JsonFile.jl` answers
  `true` for a `JsonFile`. `test_json()` has 1443 of 1443, with the layering
  guard of the JSON package, and `test_markdown()` has 358 of 358. The step did
  not run the integration suite again: the source of the branch is the source of
  the copy of the measurement, and each later step runs the tests of its cause.
- [x] **2. The two functions of a view, and the three maps.** Proposed decision
  3. The row of a file on the page of the explorer, the card of a dashboard and
  the open of a page call the functions.
  *Check:* cause D passes. New tests: a JSON file on a card of a dashboard and
  on the page of the explorer takes a click, and the caret shows at the
  character under the pointer; a key there edits the file.

  Done on 2026-11-19, in four commits. The functions are `get_content_path` and
  `get_view_path`, with `find_content_path` and `find_view_path` for a path from a
  root (found facts 1 and 2). After the decision of the owner (found fact 3), the
  selection of each place goes through the view that the place keeps, when that
  view keeps a selection of its own: `FileSystemFile.document_view` on the page
  of the explorer, `content_view.view` of a card of a dashboard, and
  `page_view.view` of a navigator. Each of the three holders has the two
  functions, so `find_content_path` gives the path through the content of the
  holder. The navigator had a fourth map that added the step of the view by
  hand, and it reads its own selection in three places: all go through the two
  functions now. Three tests, one for each place: a click on the text of a JSON
  file puts the caret in the view, the same place has its path through the
  content, and a key edits the file at the caret. `test_explorer` has 521 of 522,
  and the one failure is cause F, for step 7. `test_navigator` has 416 of 420,
  and the four failures are lines of `NavigatorChoicesTest.jl` that fail on
  `main`.
- [x] **3. A change for a part of a file reaches the view.** Proposed decision
  4.
  *Check:* cause A passes: the editing verbs, a command of a part, a group of
  changes, and one undo step of the file for each. The test "a value found by
  identity at two places has no reference" passes as on `main`.

  Done on 2026-11-19. The forward map of `FileViewToWidget` takes a path through
  the field `file` and answers the path of the views (`get_view_path`), and a
  chain of stages passes a change on to the view of a place (found fact 4).
  `test_assistant_verbs` has 98 of 98. `test_referenced_document_editor` has 131
  of 134: the 15 lines of cause A pass, and the 3 that fail are lines of cause G
  (`:431`, `:436`, `:454`), which step 9 changes. The test of a value at two
  places passes.
- [x] **4. The selected part and the part under the pointer are content.**
  Proposed decisions 5 and 7.
  *Check:* causes C and E pass. A new test: `find_part_under_pointer` over a
  JSON string in a tab answers the `JsonString`.

  Done on 2026-11-19. `find_selected_part` and `find_part_under_pointer` read the
  path of the window through `find_content_path`. The tooltip of a file with
  views is found fact 7, and an index of a document in a path is found fact 8.
  Cause E passes: `test_pointed_part` has 3 of 3. Of cause C, the lines that
  evaluate the selection pass (Alt+Up to the `JsonString` and to the `JsonFile`,
  the file after F5, the string after a click from the explorer): the tests
  evaluate `find_content_path` of the selection now, because the selection is a
  path of the views. The lines of cause C that need the clipboard, the note of a
  part and "Copy reference", pass with step 6. New assertions in
  `AssistantVerbsTest.jl`: a selection and a pointer that go through the views
  give the content part, with a reference through the file.
- [x] **5. A selection for a part of a content shows in the view.** Proposed
  decision 6: `select_part!`, `open_page!` at a part of a file, a visit of the
  navigator, a search link of the explorer, and a row of the document tree.
  *Check:* new tests, one for each of the five: the caret or the selection frame
  is drawn at the part. The test of `select_part!` that compares the selection
  of the window with the reference of the part compares it with the reference
  through the views.

  Done on 2026-11-19, with two of the five new tests not written.
  `select_part!` writes `find_view_path` of the reference of the part. Its test
  asks for the path through the views, for the content of the view at that path,
  for the part of the path that the file view keeps, and for a part that is named
  with an index and a key. A visit of the navigator writes the selection through
  the view of its page since step 2, and a new test visits a part of a JSON file
  and goes Back: the caret is where it was, in the view of the page.
  `open_page!` at a part has its test on `main`, which passes.
  **Not written:** a test of a search link of the explorer and a test of a row of
  the document tree, each with a JSON file. Each of the two opens the page of a
  part inside the file. Such a page shows the part as content with no view in
  this plan ("Not in this plan"), so the code of the two did not change, and the
  tests of the explorer and of the tree on `main` pass (`test_explorer` 522 of
  522). Plan 4c gives the page of a part its view, and it needs these two tests.
- [x] **6. The clipboard keys at a caret of a view.** Proposed decisions 5 and
  6, at the one place where the clipboard reads the selection.
  *Check:* cause B passes, with the helper `_ce_file` on the new shape. A copy
  in one tab and a paste in a second tab of the same file is one new test.

  Done on 2026-11-19. The clipboard reads its selection through
  `_find_content_selection`, which gives the path through the content, at each of
  its nine reads but the one of the text mode. An answer that selects the same
  place again goes back through `_find_shown_path`. An edit that the clipboard
  places goes down by its route, which reaches the view since step 3, and its
  selection comes back through the stages of the views. "Copy reference" writes
  the code of the content path. `test_clipboard_edits` has 39 of 39, with the new
  test of two tabs of one file: the second tab is a pane that opens on a new view
  of the file, because a pane of a file view has no duplicate. The rest of cause
  C passes: `test_application` has 420 passes and the one failure of `main`
  (`ApplicationTest.jl:1050`).
- [x] **7. Alt with the arrow keys, and the reload.** Alt+Down from a file view
  goes into what the view shows. After F5, after "Load it" and after Back to a
  page whose file changed, the page shows only the new text, and the caret is at
  a valid place.
  *Check:* cause F passes. New tests: Alt+Down and Alt+Up through a file view,
  and the caret after a reload of a file that got shorter.

  Done on 2026-11-19. The walk is found fact 9, and cause F is found fact 10.
  `_repair_selection!` writes the selection again after a load also when the
  caret is in the views of the file, so the views of the new document take their
  parts of the path. `test_file_view_walk` is new, with 16 of 16.
  `test_file_watch_window` has two new cases, a file that gets shorter under the
  caret and a key after "Load it", with 22 of 22. `test_explorer` has 522 of 522.
  The tests of the walk on `main` pass: `test_selection_walking` 36,
  `test_widget_text_editing` 97, `test_text_view` 36 and
  `test_conversation_transcript` 194.
- [x] **8. The find and the filter of a JSON tab.** A test first: Ctrl+F and the
  filter menu on a JSON array in a tab, on `main` and on the branch. The branch
  must do what `main` does.
  *Check:* the new test. If the arrangement needs more than the functions of
  decision 3, the work stops and the session asks, because point 6 of the order
  moves the arrangement into the view of a collection.

  Done on 2026-11-20, with no change of the code. Found fact 11 has the result of
  the probe on `main` and on the branch: the find and the filter of a JSON array
  in a tab do not work on `main`, so the branch has nothing to keep. The new test
  `test_json_tab_arrangement`, with 14 of 14, asks for what the two sides share:
  Ctrl+F puts the arrangement around the file view, with a find at the list of
  the views of the elements, the menu of a value offers its items, its choice
  arranges the tab, and the file is as it was.
- [x] **9. The tests that spell the shape of today.** Cause G, and each of the
  twelve places that still spells a path through `file` for what a tab draws.

  Done on 2026-11-20. `FileTabTest.jl` asks for the path of a press through the
  field `content` of the view. `ReferencedDocumentEditorTest.jl` asks that the
  scroll pane of a tab holds the view of what the file holds, and it reads the
  history of the file with `get_file_content(view)`. The two helpers that put the
  focus in the file of a tab, in `ApplicationTest.jl` and in
  `WindowFrameGuardTest.jl`, write the selection through `find_view_path`. The
  helper of the clipboard test changed in step 6, and the four places of
  `ApplicationTest.jl` that evaluate the selection changed in step 4. The other
  places of the list read the content of a file, and not a path of what a tab
  draws, so they stay. The docstring of `get_file_content` said that the scroll
  pane of a file tab is a layer that shows a file. It names the tab and the view
  of a file now. `test_referenced_document_editor` has 135 of 135, `test_file_tab`
  35 of 35, and `test_window_frame_guards` 39 passes and 3 broken.
- [x] **10. The wide check and the guides.** `test_platform()`,
  `test_integration()`, the suites of JSON, Markdown and MCP, the suites of the
  backends, and the six guards, on the branch and at its base. The time of the
  first frame of a JSON tab, on the branch and at its base. The guides of the
  file format, of JSON, of the explorer and of the assistant. "The code now" in
  the design document. `Pkg.precompile` of `omnet-julia` against the branch,
  with a count of the compiled packages. The plan moves to `plan/done/`. Then
  the session asks for the landing, and for the push apart.

  Done on 2026-11-20. The branch had 19 commits over `66b437f73`, and a second
  worktree at `66b437f73` was the base. The results:

  | Check | Base | Branch |
  | --- | --- | --- |
  | The six guards | 249 lines | the same 249 lines, 5 line numbers moved |
  | `test_json`, `test_markdown` | 1443 of 1443, 358 of 358 | the same |
  | `test_platform` (pass, fail, error, broken) | 236615, 15, 0, 21 | 236637, 15, 1, 21 |
  | `test_integration` (pass, fail, error, broken) | 3233010, 627, 18, 2830 | 3233068, 627, 18, 2830 |
  | SDL (pass, fail, error) | 1358, 4, 1 | the same |
  | MCP, video, console, PDF, web | 550, 82, 150, 54, 161 | the same |
  | The first frame of a JSON file of 60 objects in the application window | 428 ms, 49.1 s with the compile | 508 ms, 52.7 s with the compile |

  The 15 failure lines of the platform suite and the 650 of the integration
  suite are the same lines on both sides. Five line numbers moved, in the three
  test files that the branch changed, and they are the same assertions. The new
  passes are the new tests.

  The one new error is `TaskWorkItemTest.jl:171`: a call to an editor that is
  busy with its first compile waits longer than its limit of 30 s
  (`EditorCallTimeoutException`). The test alone, three rounds in one process,
  two times on each side: on the branch the first round failed in one of the
  two runs and took 1m18.7s when it passed; at the base it passed in both runs,
  in 1m08.7s and 1m10.0s. So the first compile on the branch is about one tenth
  longer, and under load it crosses the limit more often. The test stays as it is.

  The integration suite took 111 minutes on the branch and 78 at the base. In
  the check of plan 4b1 the same suite took 114 minutes at its base and 97 on its
  branch, so its time varies too much to show a cost of the branch. The test of
  a file tab takes 31 s instead of 1 s, because it is the first test of its
  group that opens a JSON tab, so it compiles the printers of the views. The
  assistant verbs test after its compile, six times in one process: 8.0 s on the
  branch and 7.1 s at the base, so about 12 % more.

  `Pkg.precompile` of the downstream program against the branch, in a copy:
  265 packages compiled in 981 s, 229 ready, no error, and the warning that is
  known on `main` (533 of 3186 recorded calls of `ProjecturedJulia` do not
  resolve). The guides of the file format, of focus, of the clipboard, of the
  navigator, of the explorer, of JSON and of the higher-order projections, and
  "the code now" in the design document, changed in steps 1 to 9. The
  orientation guide names the verbs of the assistant and no path, so it stays.

  Then `main` moved by 23 commits, and the branch took a rebase onto `e0dbc7f97`
  with no conflict. In `FileSystemFileToWidget.jl` the path of `main` for a file
  with no document comes first, and then the path through the view. The wide
  check ran again on the rebased branch: `test_json` and `test_markdown` pass,
  `test_platform` has 237160 passes, 15 failures, no error and 21 broken,
  `test_integration` has 3233558 passes, 627 failures, 18 errors and 2830 broken,
  and the backends give the same counts. The failure lines are the lines of the
  branch before the rebase, and the task test passed this time. The guards give
  the same lines, with two line numbers moved in a file that `main` changed. The
  narrow tests of the plan, 36 cases, fail only at lines that fail on `main`.

  Three more rebases followed `main`. The third, onto `11ea56169`, had no
  conflict. The fourth, onto `8e792dc15`, had a conflict in `Clipboard.jl`: the
  paste of `main` gets the selection as a keyword, and its default is now
  `_find_content_selection(input)`, so the new paste of `main` also reads the
  path through the content. The new insertion paste of `main` in
  `ClipboardSliceToAny.jl` reads it in the same way. The 42 narrow cases then
  failed only at lines of `main`, and `test_insertion_in_tab` passed 12 of 12.
  The fifth, onto `567b5665b`, 181 commits later, had two conflicts in
  `ProjecturedSuite.jl`, because the suites of `main` are tables of parts now.
  The two new tests of the branch are two parts of that table.

  The checks after the fifth rebase ran at the neutral path of `julia-worktree`
  (found fact 13), on the branch and on a worktree at `567b5665b`:

  | Check | `main` at `567b5665b` | The branch |
  | --- | --- | --- |
  | The six guards | 261 lines | the same 261 lines, 6 line numbers moved in 3 files that the branch changed |
  | `test_json`, `test_markdown` | 1443 of 1443, 361 of 361 | the same |
  | `test_platform` (pass, fail, error, broken) | 239042, 0, 0, 46 | 239069, 0, 0, 46 |
  | `test_integration` (pass, fail, error, broken) | 3262948, 3, 0, 3469 | 3263007, 2, 0, 3469 |
  | MCP, SDL, video, console, PDF, web | 550, 1383 and 5 broken, 94, 150, 54, 161 | the same |
  | The 42 narrow cases | | 1 failure line, a line that fails on `main` too |

  Two failure lines are on both sides, with no mark: `ApplicationTest.jl:2002`
  (2006 on the branch), where an Alt+double click on a row of the Files pane does
  not select the file of the row, and `ScrollWorkTest.jl:195`, a count of the
  work of the Files pane. They are new failures of `main`. The third failure of
  `main` is the time ratio of `WindowFrameGuardTest.jl:309`, 8.54 against the
  bound 3.0, and the branch passed it. Each suite shared the machine with other
  jobs, so its time shows no cost of the branch. The integration suite of the
  branch keeps about 1.5 GiB more live memory from `test_window_frame_guards`
  on, and its largest resident size is 15.8 GiB against 14.4 GiB (found facts 14
  and 15).

## Found during the work

1. **One of the two functions existed.** `get_content_path(view, path)` gives the
   path of the content for a path of a view of one content, and the syntax, the
   text and JSON call it. So the pair of proposed decision 3 is
   `get_content_path` and the new `get_view_path`, with no second name for the
   same job. The forms for a path from a root are `find_content_path(root, path)`
   and `find_view_path(root, path)`.
2. **The four functions are in the focus slice**, in `ContentPath.jl`. The
   function of the selected part is in that slice, and the slice of the
   projections is above it. The module of the projections exports them too, so no
   slice gets a new edge. `get_content_field(node)` says at which field a path
   from a root can change: the field that `get_edited_field` names, and `nothing`
   for a view of one content, whose path has the steps of its content until
   plan 4c and point 11.
3. **A page and a card keep the file view in a slot, and a view with views gets
   no caret there.** A tab holds the file view, so the caret path goes through
   the view. The row of a file on the page of the explorer and a card of a
   dashboard hold the file, and they keep the file view beside it in a slot that
   a walk does not enter (`document_view`, `content_view`). The selection of the
   window goes through the file. A file view with no views follows the caret of
   its file (`follow_content_selection!`). A file view with views keeps a caret
   of its own, and nothing writes it there. A probe on the branch, with the maps
   of step 2: after a click on the text of a JSON file on the page of the
   explorer, the file has the caret, the file view has none, and a key changes
   nothing. A second probe, with a change that is not committed: the map of the
   row answers the path through `document_view`, and then the views have the
   caret and the key edits the file (`"abc"` becomes `"xabc"`). The plan does not
   name where the caret path of such a place goes, so the session asks the
   owner. Steps 3, 4 and 6 are for a tab and do not wait.

   **Decided by the owner on 2026-11-19:** "Generally, the selection should go
   through the view", and "I would assume the final solution would just be a
   selection through the views so we can have different selections per view."
   So for a file view with views, the selection of the window goes through the
   view that the place keeps: `FileSystemFile.document_view`, the view in
   `DashboardCard.content_view`, and the view in the `page_view` of a
   `Navigator`. Each place has a caret of its own. The three holders get methods
   of `get_content_path` and `get_view_path`, so a path through the content of a
   holder and the path through its view change one into the other. A file view
   with no views stays as it is: its selection follows the selection of its
   file. The owner also said that the name `document_view` sounds strange. The
   three fields and their names are from 2026-11-06, and point 7 of the order
   gives the three holders one form. This plan renames nothing.
4. **A chain of stages passed a change only to the same object.** A change with
   a route names a place of the input. `_read_routed_chain` in `Chaining.jl`, a
   file of the platform, maps the route forward through each stage, and it went
   on to the next stage only when the route named the same object there. A stage
   that draws the views of its input holds the view of the place, so the change
   for a part of a file stopped at the first stage of the file view. The chain now
   goes on also when the next stage holds a document that names the place as what
   it shows (`get_edited_field`), which a view of a content does. When a path
   through the views ends in the step `.viewed`, in plan 4c, the path names the
   content itself, and this rule can go.
5. **The box of a view is a document now.** A card of a dashboard and a
   navigator keep the view of what they show in a `NavigatorViewSlot`, a box that
   a walk does not enter. It was a plain struct, and the write of a selection
   stops at a node that has no selection field. It is a `@document` now, so the
   selection of a card goes through `content_view.view`. The test
   `is_following_content_selection(view)` says whether a view copies the selection
   of its content. A place sends its selection through a view that keeps its own,
   and through the content otherwise.
6. **A card makes its view only in an editor that holds the dashboard.** The
   acquire of the dashboard makes the view of each card. In an editor that holds
   nothing, a card has no view, and it shows a JSON file as content with no view.
   That works while the JSON content keeps a caret. Plan 4c must give such a card
   its view.
7. **A row of a key table gets the answer of the child, not a path.** The
   function of a row is called with the document, the gesture and the answer of
   the child. Only the condition of a row gets the selection. So the row of the
   tooltip of a file can not get the pointer of the file view. The file view
   answers a dwell itself: with no other answer, it asks
   `make_file_part_note(file, path)` for the note of the part under its own
   pointer. The function is new, its default answers `nothing`, and the JSON
   package gives the method. The row of the file stays for a file that no view
   shows.
8. **A path of the assistant can use an index of a document.** `people[2]` is
   the step `[2]` on the `JsonArray` itself, and `object["name"]` is a step with
   the name of a key on the `JsonObject`. A view holds the views of its children
   in the fields of its content, so it takes neither step. `get_view_path` of a
   view of one content first writes each such step through the fields that hold
   the child (`_make_field_path`, with `find_document_path` of the kernel). No
   test of `main` sends a change or a selection to a part that is named so.

9. **The walk of Alt with the arrows listed each field of a document.** From the
   view of a file it went first to the file, which the tab does not draw, and
   from a view of one content it went to the content. The walk now asks the
   functions of step 2: a document that shows its content through views gives the
   view as its child, and not the content, and it gives no field that a walk of a
   document does not enter, such as the scroll pane of a file view. A view of one
   content does not give the field `viewed`. A walk down ends at a text in a
   view, such as the key of an entry.
10. **A file kept its document only for a place that the document keeps.** When
    the page of a file closes, the file forgets its document unless the document
    has an edit or keeps the place of the keys. With views, the view keeps that
    place, so the document was forgotten and read again, and Back showed another
    document. The rule reads the place of the view too. This was cause F.

11. **The find and the filter of a JSON array in a tab do not work on `main`.**
    A probe ran the same keys on `main` and on the branch, on a file with an array
    of five strings in a tab. On both sides Ctrl+F puts an arrangement around the
    file view with one find, and the menu of a value offers its six items. On both
    sides no count shows, and "Hide items like this" hides no element: the printer
    of a JSON array reads no arrangement. One thing differs. On `main` the caret
    stays in the string after Ctrl+F, so a text that a person types for the find
    goes into the JSON string (`"apple"` became `"apapple"`). On the branch the
    caret goes to the field of the find, and the typed text changes nothing. The
    arrangement of a JSON array is work of point 6 of the order, which moves the
    arrangement into the view of a collection. This plan changes nothing of it.
12. **An editor of the application stays after its test, on `main` too.** A
    probe ran `test_assistant_verbs` six times in one process, with three full
    collections after each run. The live memory grew by 84 MiB per run, from
    357 MiB to 778 MiB at the base and from 361 MiB to 782 MiB on the branch. The
    test starts the application and never stops its editor. The fault F10 of
    the plan of the editor for the assistant of the catch-up, where the IDE grows
    to 10 GB in 27 hours, can have the same cause. Found fact 14 names what
    keeps such an editor.
13. **The manifest of `main` names the sibling packages by a path of the
    sandbox.** Since `b3c3b911c`, `environment/all/Manifest.toml` gives
    `AgentClientProtocol`, `AutoIntegration`, `ClaudeCodeACP` and
    `ModelContextProtocol` the path `../../../../../workspace/<name>.jl`. The path
    is correct at the neutral path of `julia-worktree`,
    `~/.cache/julia-work/projectured-julia`. In a checkout in
    `~/workspace`, it names `/home/workspace/<name>.jl`, which does not exist, so
    `ProjecturedACP` does not compile and `ProjecturedTest` does not load. The
    checks of the fifth rebase that load `ProjecturedTest` ran through
    `julia-worktree run`.
14. **An editor that never runs its loop keeps its start steps.** `build_editor`
    runs the start steps of the wrappers (`EditorBuild.jl`), and only the end of
    the loop runs their stop steps (`EditorLoop.jl`). A test that draws frames
    with `run_frame!` never runs the loop, so the message log capture stays in the
    global logger, and other start steps stay too. Each such editor stays for the
    life of the process. A probe made three editors of the frame guard test, with
    a weak reference to each: all three stayed with `SdlBackend`, with
    `HeadlessBackend`, with no `start_application!`, with no settings and with no
    message log. When the probe ran the stop steps of each editor, none stayed. So
    `test_window_frame_guards` keeps about 2.6 GiB per run on `main`, and 4.1 GiB
    on the branch. This plan does not change it.
15. **The print of the views makes an editor of a JSON file 2.3 times as large.**
    The live memory that one editor of the frame guard test holds, with the caret
    in the file, after a full collection:

    | JSON objects in the file | `main` | The branch |
    | --- | --- | --- |
    | 10 | 67 MiB | 73 MiB |
    | 100 | 101 MiB | 161 MiB |
    | 1000 | 441 MiB | 1035 MiB |

    Each object, with two fields, costs about 0.38 MiB on `main` and 0.97 MiB on
    the branch. A count of the objects that the editor of 1000 objects reaches:
    7.2 million on `main` and 21.3 million on the branch. The branch adds about
    3.2 million `ReactiveCell`, 3.6 million `_Dependency` and 0.8 million
    `ConcreteReference`, and it makes 20004 `ViewingIoMap` and 20004
    `ViewRecursion`, about 20 per object. The view documents themselves are few:
    10005 `TextView` and 7003 `CellVectorView`. So most of the cost is in the
    print of each view node through its own IO map, with about 160 cells for each.
    After the stop steps, the live memory goes back to the same value on both
    sides, so the branch adds no leak.

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
