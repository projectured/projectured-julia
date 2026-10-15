# A window watches its open files

Status: a proposal. Decided by the owner, 2026-10-15: D15 A of
[the-editor-always-answers-the-person.md](../done/the-editor-always-answers-the-person.md),
as a step of its own after that plan ("agreed A"). Nothing is built. D15a is
decided too (A, 2026-10-15), so every decision is made. STARTED 2026-10-15 (the
owner: "let's start, ask if design questions come up"), on the branch
`window-watches-files` in the worktree `projectured-julia-watch`.

**The owner, 2026-10-15, on the band:** "don't create synthetic event for the
band, it should be just some document on the file document or something like
that". So the state of the band is a document that the file document holds, the
view of the file document draws it, and its buttons answer operations.

## 1. The goal

A file that a tab shows and that another program changes on disk reaches its tab.
A save never writes over a newer file without the person knowing.

## 2. The facts (2026-10-15)

- `watch_document_file!(file; store)` and `unwatch_document_file!(file; store)`
  (`source/platform/filechange/FileChangeStore.jl`) watch the folder of a file
  document. A watcher reads and parses a changed file off the loop, after it
  settles for 50 ms. `FileChangeFeed` brings the parsed content to the document:
  a document with no edits takes it, a file that holds the last save of the
  document is left as it is (D13), and a document with unsaved edits keeps them,
  while the log says that its file changed.
- No code outside the tests calls `watch_document_file!` or registers
  `make_file_change_feeds()`, on `main` too. The live check of step 8.4 confirmed
  it: a file changed on disk, and its tab showed the old content.
- The store is one for the process (`SESSION_FILE_CHANGE_STORE`), against the
  rule that the owner set on 2026-10-14: no global state.
- A tab that opens acquires each layer of its content
  (`acquire_document!(editor, tab::PaneTab)` in `PaneSurgery.jl`). A tab that
  closes releases only the outer layer (`ReleaseDocumentOperation(tab.content)`),
  so a file document inside a history wrapper is not released.
- `save_file_text!` writes the text and does not look at the file on disk first,
  so a save after a change of another program writes over it.

## 3. The steps

- [ ] 1. The store belongs to the editor: the feed of the editor owns it
  (§3.1).
- [ ] 2. A file document is watched while a tab shows it: `acquire_document!` of
  a `FileDocument` watches it in the store of the editor, and `release_document!`
  stops it. The release of a closed tab reaches each layer of its content, as the
  acquire does.
- [ ] 3. The window of the application registers the feed, in `run_application`
  and `make_application_window`, which the IDE of omnet-julia uses too.
- [ ] 4. A save compares the file on disk with the last load or save of the
  document before it writes, and a newer file goes to the person (D15a).
- [ ] 5. What the person sees, by the decision of D15a.
- [ ] 6. The tests of each layer, and a live check in the application: a change
  of an open file reaches its tab; a change under unsaved edits, and a save over
  a newer file, show what D15a decided.

## 3.1 The design of the steps (2026-10-15, after D15b to D15d)

- Step 1 (filechange): `FileChangeFeed(; store = FileChangeStore())` owns its
  store, so each editor that has the feed has its own, and
  `SESSION_FILE_CHANGE_STORE` goes. `get_session_file_change_store(; editor)`
  keeps its name and gives the store of the feed of the editor, or a new store
  that nothing keeps, as the logs of the session do. The default store of
  `watch_document_file!`, `unwatch_document_file!` and
  `is_document_file_watched` is the store of the feed of the editor of the
  evaluation; with none, they do nothing (D15d). `close_file_change_store!`
  stops the watchers of a store.
- Step 2: `AcquireDocumentOperation` and `ReleaseDocumentOperation` are each
  other's inverse (D15c). The close of a tab posts `ReleaseDocumentOperation(tab)`,
  and `release_document!(editor, tab::PaneTab)` reaches each layer, as the
  acquire does. The file-change slice adds `acquire_document!` and
  `release_document!` for a `FilePage` (the watch keeps the page, which shows the
  band) and for a bare `FileDocument` (no band). New edge: filechange → domain.
- Step 3: the wrapper `file_change = true` (filechange) adds the feed, and its
  stop step closes the store; `make_application_wrappers` turns it on. The
  application needs no new edge: it passes a keyword.
- Step 4: the file-format slice declares `request_file_save!(editor, file)`,
  `true` by default, which `SaveFileOperation` asks before it writes. The
  file-change slice answers it: `true` when the file on disk is the text that the
  document last loaded or saved (`base_hash` of the watched file, or the hash of
  its last save), else it shows the band of a save over a newer file and answers
  `false`.
- Step 5 (fileformat): `FilePage(content; band = nothing)`, the document around
  the scrolled file, which `make_file_tab_content` and the open of a file give a
  tab, and `FileBand(; message, choices)`, a sentence and its choices, each a
  label and the operation that its button answers. `FilePageToWidget` draws the
  band above the content in a `VerticalLayout`, in the warning colors of the
  widget theme, and maps every path of the content, as `FindBarViewToWidget`
  does; a button answers its operation through a `GestureBinding` of a click.
  The file-change slice makes the band and its operations: load the file, or
  keep the edits (and, for a save, write them).

## 4. The decision

- **D15a. Decided by the owner, 2026-10-15: A** ("the band looks good", after a
  picture of the band drawn with the widgets of the editor: a light yellow strip
  between the title of the tab and its content, one sentence and two buttons,
  which fills the width of the tab). What the person sees when a file with
  unsaved edits changes on disk, and when a save would write over a newer file. Today a line in the log
  says the first, which a person does not see, and the second happens with no
  sign.
  - A: a band at the top of the tab: "data.json changed on disk", with "Load it"
    and "Keep mine". A save over a newer file shows the same band and writes only
    after "Keep mine". The band is a layer of the tab content, made of a label and
    two buttons; the plan asks before it adds any new event or payload.
  - B: a notice on the status bar and in the log. A save over a newer file does
    not write, and says so on the status bar; Ctrl+O loads the file again.
  - C: the log only, as now, and a save over a newer file does not write and
    records a fault.
  Recommended (mine): A. The person sees it where they work, and each choice is
  one click.

- **D15b. Decided by the owner, 2026-10-15: A** ("agreed, it's A"). Where the document of the band lives.
  - A: a document around the scrolled file in the tab, which holds the file and
    the state of the band (`make_file_tab_content` makes it). The band stays at
    the top of the tab while a long file scrolls, no file type changes, and it
    works for every file type, also those of omnet-julia. The layer walk of a tab
    reaches the file through it.
  - B: a field on each file type (ten here, and those of omnet-julia). The band
    draws in the view of the file, inside the scroll pane, so it scrolls away
    with a long file.
  Recommended (mine): A.
- **D15c. Decided by the owner, 2026-10-15: yes.** An undo of an open or a close of a tab. The inverse of the
  acquire and of the release is "do nothing" today, so an undo of an open leaves
  the watch running, and an undo of a close leaves the file unwatched. Each one
  becomes the inverse of the other. Recommended (mine): yes.
- **D15d. Decided by the owner, 2026-10-15: yes** ("agreed"). A watch with no editor. The store belongs to the feed of an
  editor, so each editor has its own. A call of `watch_document_file!` where no
  editor with the feed is bound does nothing, rather than fill a store of the
  process that nothing drains and that keeps a watcher task forever. It touches
  `get_result_file` and the fingerprint store of omnet-julia, which watch from
  a cache of the process, when they run outside a frame. Recommended (mine): yes.

## Not in this plan

A watch of the Files pane for new and deleted files · a merge of the edits with
the change on disk · a file that a tab shows under another name after a rename.
