# A window watches its open files

Status: a proposal. Decided by the owner, 2026-10-15: D15 A of
[the-editor-always-answers-the-person.md](../done/the-editor-always-answers-the-person.md),
as a step of its own after that plan ("agreed A"). Nothing is built. D15a is
decided too (A, 2026-10-15), so every decision is made. STARTED 2026-10-15 (the
owner: "let's start, ask if design questions come up"), on the branch
`window-watches-files` in the worktree `projectured-julia-watch`. D15e
(2026-10-15) changes the design of steps 4 and 5: the watcher knows nothing of
editing.

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

- [x] 1. The store belongs to the editor: the feed of the editor owns it
  (§3.1). Done 1d0f377a9: `get_session_file_change_store(; editor)`,
  `close_file_change_store!`, a watch with no editor does nothing; the store
  test 56.
- [x] 2. A file document is watched while a tab shows it: `acquire_document!` of
  a `FileDocument` watches it in the store of the editor, and `release_document!`
  stops it. The release of a closed tab reaches each layer of its content, as the
  acquire does. Done e30c4e6f4, with the edge filechange → domain. A window
  posts the acquire at its start outside the undo history, so no Ctrl+Z
  releases a window. The store test 59, the pane test 105. The guard of the
  edges between the slices fails on `main` too: the task slice uses the
  filesystem and the navigator slices, which its row does not allow.
- [x] 3. The window of the application registers the feed, in `run_application`
  and `make_application_window`, which the IDE of omnet-julia uses too. Done:
  the wrapper `file_change = true`, which `make_application_wrappers` turns on.
  The campaign window and the IDE of omnet-julia do not use these wrappers: they
  give `make_file_change_feeds()` themselves, which now has a store of its own,
  and no stop step closes it when their loop ends. The store test 62.
- [x] 4. A save compares the file on disk with the last load or save of the
  document before it writes, and a newer file goes to the person (D15a). Done
  together with step 5, in one commit: once the history holds no hash, only a
  page that the watcher reports to can tell its own save, so the two can not land
  apart. The facts are in §3.2.
- [x] 5. What the person sees, by the decision of D15a. Done: the page decides
  what a reported change means, and shows its band (§3.2).
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
- Step 4 (fileformat, D15e): `FilePage` holds the hash of the text of its file
  at the last load or save. Before the save writes, the page reads the file on
  disk and compares the two hashes. The same hash writes, and the hash of the
  text that it wrote becomes the hash of the page. Another hash shows the band of
  a save over a newer file and writes nothing. No watcher takes part.
  `saved_text_hash` leaves `UndoBuffer`, with `get_saved_text_hash` and the
  keyword `text_hash` of `record_saved_state!`. The history keeps `saved_entry`
  and `has_unsaved_edits`. The page sees the save by A of D15e: its reader
  answers one save operation of the file-format slice in place of the
  `SaveFileOperation` of its file, and the file dialog of "Save as" gives that
  operation too. Its way back is `DoNothingOperation()`, as for a file write, so
  a history above the page adds no step for a save.
- Step 5 (fileformat): `FilePage(content; band = nothing)`, the document around
  the scrolled file, which `make_file_tab_content` and the open of a file give a
  tab, and `FileBand(; message, choices)`, a sentence and its choices, each a
  label and the operation that its button answers. `FilePageToWidget` draws the
  band above the content in a `VerticalLayout`, in the warning colors of the
  widget theme, and maps every path of the content, as `FindBarViewToWidget`
  does; a button answers its operation through a `GestureBinding` of a click.
  The page makes the band and its operations: load the file, or keep the edits
  (and, for a save, write them). The watcher reports a change to the page, by a
  function that the file-format slice declares and the page answers: the hash of
  the new text and the parsed content, or the failure of the parse. The page
  chooses (D15e): the hash of its last load or save does nothing; a content with
  no edits loads the change; a content with edits, or one that keeps no history,
  shows the band.

## 3.2 What steps 4 and 5 built (2026-10-15)

The work of steps 4 to 6 is in the worktree `projectured-julia-watch-save`, on the
branch `watch-save` from `window-watches-files`. The part "the history loses its hash"
came from the session that did steps 1 to 3, as a patch.

- The names. `FilePage` has the field `file_hash`; `make_file_page(content)` sets
  it from the file as it was read, and `make_file_tab_content` and the open of a
  file use it. `compute_file_text_hash(path)` is the one hash of a file text, for
  the page and for the watcher. `SaveFilePageOperation(page; force = false)`,
  `LoadFilePageOperation(page; content, file_hash)` and
  `KeepFilePageEditsOperation(page, file_hash)` are the operations of the page.
  `receive_file_change!(editor, receiver, file_hash, content)` is declared in
  fileformat. `WatchedFile` has a `receiver`, `watch_document_file!` takes the
  keyword `receiver`, and filechange acquires and releases a `FilePage`.
- The reader of the page answers its own save and load in place of a
  `SaveFileOperation` and a `ReloadFileOperation` (with no document) of its file:
  two 3-argument `read_intent` methods, which the default reader reaches for each
  member of a compound too. "Save as" (`save_file_dialog!` with a page) answers
  the save of the page with `force = true`.
- A save and a keep have the way back `DoNothingOperation()`. A load has none, as
  `Ctrl+O` has none. A `SaveFileOperation` has no way back, so a history above it
  records a barrier for each `Ctrl+S`; in a page, a save adds no step.
- A file with no page: a file that a person does not edit loads the change; any
  other keeps what it holds and logs, because it can not tell its own save from a
  change. This is the rule of D13 A for a file with no history, given now to a
  file with no page. Every file tab of the source is a page.
- A page of a file that a person does not edit reads no text for a hash, because
  such a file can be large and a save never writes it.
- The watcher still reads `is_editable_file_type`, to choose between the text of
  a file and its time and size. It reads no edit and no save.
- A fact of the tests: an `UndoEntry` is a value, so two entries with equal
  fields are `===`, and a test that pushes equal entries sees no edits. A real
  entry carries its time.

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
- **D15e. Decided by the owner, 2026-10-15: the watcher knows nothing of
  editing.** The owner, on a proposal to keep the hash of the last save in the
  `WatchedFile` of the store: "storing the hash of the edited file on the
  watched file seems wrong, it's in the wrong dependency order. the watcher
  watches, doesn't know and should not know about editing at all". Then "yes" to
  the design in §3.1, steps 4 and 5:
  - The watcher watches, reads, hashes and parses a changed file, and reports
    the change. It keeps no hash of a load or a save, reads no edit, makes no
    band and writes no message about edits.
  - The page (`FilePage`, D15b) holds the state of its file against the disk:
    the hash of the text of the last load or save, and the band. It decides what
    a change means, and it checks the disk before a save.
  - The history keeps `saved_entry` and `has_unsaved_edits`, because only the
    history knows that an undo came back to the saved step. `saved_text_hash`
    leaves `UndoBuffer`: it is a fact about the disk, not about the history.
  - On `main`, `_bring_file_change!` in `FileChangeStore.jl` reads
    `get_saved_text_hash` and `has_unsaved_edits`, chooses between a reload and a
    keep, and logs a message about edits. That choice moves to the page.
  - How the page sees a save. **Decided by the owner, 2026-10-15: A** ("agreed,
    it's A"). `Ctrl+S` gives `SaveFileOperation(file)` on the file document, so
    the page must see the save to check the disk and to keep its hash.
    - A: the reader of the page reads its content first, and when the content
      answers `SaveFileOperation` of its own file, the page answers a save of its
      own, as `UndoBufferToAnyProjection` wraps each operation of its content.
      "Save as" gives the save of the page too, so the hash of the page follows
      the new file.
    - B: the page binds `Ctrl+S` itself, before its content.
    - C: the hash on each file type, so the save of the file checks the disk.
    - Not a `CompoundOperation` (the owner asked): a compound runs every member,
      and no member can stop the next, so a check can not keep the write from
      running. A choice in the reader would make the reader read the disk, and
      the hash of the written text is not known before the write.

## Not in this plan

A watch of the Files pane for new and deleted files · a merge of the edits with
the change on disk · a file that a tab shows under another name after a rename.
