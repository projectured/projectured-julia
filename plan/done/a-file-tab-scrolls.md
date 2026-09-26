# A file tab scrolls

> **Status:** done. Written and landed 2026-09-26.

## 1. The request

In the take of S2 (`plan/pending/feature-video-screenplays.md`), the assistant adds
a sixth person at the end of `people.json`, and the file's end is below the part
of its tab that shows. A wheel over the file does nothing. The owner
(2026-09-26): "the json file should scroll, I think FileDocument should scroll by
default, no?", then "yes and do it before the take".

## 2. What exists

- **The rule.** A tab page gets no scroll pane by default
  (`plan/done/a-popup-shows-every-item-on-a-popover-and-a-help-page-scrolls.md`,
  G3, the owner on 2026-09-25: "No scroll by default in a tab page, what if a page
  needs two below each other for example? That is a bad idea."). Content scrolls
  where it is made: the Help menu opens its two lists as `WidgetScrollPane(list)`,
  and the navigator and the assistant put their content in a scroll pane in their
  projections. A file tab holds one document, so a scroll made where a file tab is
  made keeps that rule.
- **The makers of a file tab.** `make_application_document`
  (`example/projectured/Application.jl`) makes the first tabs with
  `make_file_tab(path, UndoBuffer)`; `OpenFileOperation`
  (`source/filesystem/FileSystemDocument.jl`) makes the tab of a file that the
  navigator opens with `make_file_tab(op.path, op.wrap)`. `make_file_tab`
  (`source/fileformat/DocumentFile.jl`) answers the file document. omnet-julia
  makes no file tab with either.
- **The readers of a file tab.** `get_pane_file_group` (`source/pane/PaneFile.jl`)
  puts a new file in the group that holds a tab whose content
  `is_file_document`. `get_edited_document` follows `get_edited_field` from a tab
  to the document a person edits. `_reach_tool!` titles a tool in a scroll pane by
  what it shows, through its own `_get_tool_document`.
- **A saved window.** `WidgetScrollPane` is a `.pred` type written with its content
  (`pred_arguments` in `WidgetDocument.jl`), so a load makes the scroll pane again.
- **The route of an edit.** An edit of a verb is routed through the widget stage
  to the file's history (`_RoutingContainerProjection` in `WidgetToGraphics.jl`).
  `WidgetScrollPaneToGraphicsCanvas` has an IoMap of its own with one
  `content_iomap`, and it follows no route.
- **Packages.** `ProjecturedFileFormat`, `ProjecturedFileSystem` and
  `ProjecturedPane` depend on `ProjecturedWidget`.

## 3. Decisions

- **D1. The content of a file tab is `WidgetScrollPane(file)`.** One function
  makes it, in the file format package, next to `make_file_tab`:
  `make_file_tab_content(path, wrap = identity)`, the file document of
  `make_file_tab` in a scroll pane. Both makers use it. `make_file_tab` stays: it
  answers the file document, and a caller that wants the file alone keeps it.
- **D2. A scroll pane is a layer that a person sees through.**
  `get_edited_field(::WidgetScrollPane) = :content`, so `get_edited_document` of a
  file tab reaches the document of the file through the pane, the file and its
  history; and a scroll pane is titled by what it shows,
  `get_document_title(pane) = get_document_title(pane.content)`, so a file tab is
  called by the name of its file.
- **D3. `get_pane_file_group` finds a file through the layers a tab keeps it in**,
  following `get_edited_field` from the content of each tab, so a file in a scroll
  pane still marks its group as the group of files.
- **D4. An edit is routed through a scroll pane.** `WidgetScrollPaneToGraphicsCanvas`
  follows a route to its content, with the helper of the containers, so an edit of
  the assistant in a file that scrolls still reaches the file's history (D23 of
  `the-assistant-reaches-a-referenced-document.md`).

## 4. Steps

- [x] **Step 1: the content of a file tab** (D1, D2). Done (2026-09-26):
      `make_file_tab_content` in `DocumentFile.jl`, exported by
      `FileFormatModule`; `make_application_document` and `OpenFileOperation` use
      it; `WidgetDocument.jl` gives the scroll pane `get_edited_field` and
      `get_document_title`.
- [x] **Step 2: the readers** (D3, D4). Done: `_find_tab_file` in
      `PaneFile.jl`; `WidgetScrollPaneToGraphicsCanvas` has a four-argument reader
      that follows a route to its `content_iomap`, and `_read_routed_child` takes
      the input and the list of children, so both readers share it.
- [x] **Step 3: the tests.** Done: a test in
      `ReferencedDocumentEditorTest.jl` opens a window on a JSON file of sixty
      records and checks each part: the tab holds the file in a scroll pane,
      `get_edited_document` reaches the array, ten turns of the wheel over it
      scroll it and add no step to the window's history, `insert_elements!` puts
      one step in the file's history, Ctrl+S saves the file with the new record,
      and a file that `OpenFileOperation` opens goes into the same group. Two
      tests read the tab's content as the file and now look into the scroll pane
      (`ApplicationTest.jl`, the history in `ReferencedDocumentEditorTest.jl`).
      Pass: `test_referenced_document_editor()` 95, `test_file_tab()`,
      `test_filesystem()`, `test_file_dialog()`, `test_window_shell()`,
      `test_tool_views()`, `test_gesture_log_in_tab()`, `test_gesture_log()`, the
      pane tests, `test_scroll_pane_axis_size()`, `test_scroll_pane_hover()`, the
      substrate layering, `test_naming()`, `test_documentation()`;
      `test_application()` 336 of 338, its 2 errors the same on `main`.
      The step as planned: A file tab longer than its pane scrolls with the
      wheel; Ctrl+S saves a file in a scroll pane; `get_edited_document` of a file
      tab reaches its document; a file opened from the navigator goes to the
      group of files; an edit through `insert_elements!` into a file that scrolls
      is recorded in the file's history. Then `test_application()`, the pane,
      file-tab, window-shell, gesture-log and referenced-document tests.
- [x] **Step 4: the documentation.** Done: `fileformat.md`
      (`make_file_tab_content`, and why the scroll is made there), `filesystem.md`,
      `pane.md` (`get_pane_file_group`), `widget.md` (a scroll pane is a layer a
      person sees through). The orientation guide does not name the content of a
      file tab. The writing guard counts the same lines as `main`.
- **Found in the S2 take (2026-09-26), and fixed.** The system text of the
  application tells the model to read a tab with `print_natural_text(tab.content)`
  and to use `get_file_content`; with a scroll pane as the content of a file tab,
  the first failed ("no natural text for WidgetScrollPane") and the second
  answered the file and not its content. Both now see through a layer that
  `get_edited_field` names (`NaturalNotation.jl`, `FileProject.jl`), as D2 says a
  scroll pane is. The scroll test checks both; `test_referenced_document_editor()`
  97, `test_file_tab()`, `test_filesystem()`, `test_file_project()` 134,
  `test_json()` 194 and `test_naming()` pass, `test_application()` 336 of 338 as on
  `main`.
- [x] **Step 5: the landing.** Done (2026-09-26), on the owner's word ("Land the
      scroll"). The branch was rebased onto `main` at 7b667d83 with no conflict.
      Pass on the rebased branch: `test_referenced_document_editor()` 97,
      `test_file_tab()` 13, `test_filesystem()` 80, `test_file_project()` 134,
      `test_window_shell()` 114, `test_gesture_log()` 50, `test_naming()`,
      `test_documentation()`; `test_application()` 336 of 338, its 2 errors in
      "the navigator scrolls a tree taller than its pane" the same as on `main`.
      The s2-video branch is rebased onto it.
