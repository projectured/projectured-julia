# A window watches its open files

Status: a proposal. Decided by the owner, 2026-10-15: D15 A of
[the-editor-always-answers-the-person.md](the-editor-always-answers-the-person.md),
as a step of its own after that plan ("agreed A"). Nothing is built. D15a is open.

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

- [ ] 1. The store belongs to the editor: a document of its session
  (`get_session_document!`), and `FileChangeFeed` takes the store of its editor.
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

## 4. The decision

- **D15a. Open:** what the person sees when a file with unsaved edits changes on
  disk, and when a save would write over a newer file. Today a line in the log
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

## Not in this plan

A watch of the Files pane for new and deleted files · a merge of the edits with
the change on disk · a file that a tab shows under another name after a rename.
