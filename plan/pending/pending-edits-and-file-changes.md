# Pending edits, and the changes of files

> **Status:** design to decide. Nothing of it is built. It comes from step 6.1
> of the omnet plan `legacy-simulation-catalog-implementation.md`: the owner
> chose on 2026-10-08 that the pending edits of a store and the feed of the
> changes of its file are generic concepts of projectured.

## 1. The goal

Two generic concepts, which any document that a file holds can use:

- **Pending edits.** An edit of a person to such a document stays pending until
  the person saves it. The view marks each changed part: inserted, updated or
  removed. A removed part stays in the view, struck through, until Save.
  Revert drops every pending edit.
- **The changes of files.** When another program changes the file, the change
  reaches the documents that the file holds, on the editor task, with no action
  of a person. A document with pending edits keeps them on top of the new file.

The first user is the fingerprint store of omnet (`fingerprint.json`): an
update task writes the file at once, `opp_repl` in a terminal and a checkout of
git change it too, and a person removes and inserts entries by hand.

## 2. The owner's decisions (2026-10-08)

Answers to the questions of omnet step 6.1:

- Q-6.1-2: "yes": each entry shows a mark, inserted, updated or removed, and a
  removed entry stays, struck through, until Save.
- Q-6.1-3: "yes we need them but the pane has nothing to do with save/load":
  Save and Revert are operations, and a pane has no buttons for them.
- Q-6.1-4: "pending edits should be a generic projectured concept like undo
  buffers are".
- Q-6.1-5: "file modification feed should be a generic projectured concept".

## 3. What exists (facts, 2026-10-08)

- **A file document.** `FileDocument` holds `filename` and `content`.
  `SaveFileOperation` (Ctrl+S) writes the content through `save_file!` and the
  `emit_text` of the file type; `ReloadFileOperation` (Ctrl+O) reads the file
  again and gives it to the wrapper with `replace_wrapped_document!`. Both pass
  every reader unchanged. `make_file_tab(path, wrap)` puts a wrapper, such as an
  `UndoBuffer`, around the content. ([fileformat.md](../../documentation/package/platform/fileformat/fileformat.md))
- **No state "changed since the save"** exists, and no title or view marks one.
  No view marks a part as inserted, updated or removed.
- **The undo buffer** is the pattern that the owner names: a wrapper document
  (`UndoBuffer`: `content` and the lists of steps), and a transparent projection
  whose reader wraps each operation of the content (`RecordUndoOperation`), so
  the evaluation records it and the reader stays pure. `make_inverse_operation`
  gives the way back of an operation, and a compound is inverted member by
  member. Buffers stack, and the inner one takes the key. ([undo.md](../../documentation/package/platform/undo/undo.md))
- **The feed** of the kernel: a producer stores from any task without blocking,
  and the editor drains the store on its own task once a frame
  (`drain_changes!`), with a wake deadline. The task feed is a feed.
- **Julia's `FileWatching`** watches a file or a folder with the notifications
  of the system (inotify on Linux, through libuv: `watch_file`,
  `watch_folder`, `FolderMonitor`), and polls the time of a file
  (`poll_file`) where no notification works, such as some network file systems.

## 4. How other tools do it

- **The editors of an IDE** (VS Code, IntelliJ, Eclipse) mark a tab whose file
  has unsaved changes, and mark the added, changed and deleted lines in the
  gutter, against the saved file. A change on disk of a file with no unsaved
  change reloads it at once. A change on disk of a file with unsaved changes
  asks the person: keep the memory, load the disk, or compare the two.
  IntelliJ notices a change by a watcher of the system, and checks again when
  its window gets the focus.
- **The table editors of database tools** (DataGrip, DBeaver) in the mode of a
  manual commit keep an edit pending: an inserted row is green, an updated cell
  blue, a deleted row struck through and grey. Submit applies every pending
  change; Revert drops one row's change or all of them.
- **git** keeps the state of the work apart from the saved state, and computes
  the marks by a comparison of the two.

## 5. The model (my recommendations)

### 5.1 The pending edits: a buffer, as the undo buffer is

A **pending-edit buffer** is a wrapper document in the tree, between the file
document and its content: `file → buffer → content`.

| Part | What it is |
| --- | --- |
| `content` | the document as the person edits it |
| `base` | the document as the file holds it: read last, or saved last |
| `changes` | the pending changes, oldest first: each the operation that the person made, and the parts that it inserted, updated or removed |

- **Its projection is transparent**, as the projection of the undo buffer is:
  the output of the content, with a mark drawn over each changed part. Its
  reader wraps each operation of the content into a record operation, so the
  evaluation records the change and the reader changes nothing.
- **A removal stays in the view until Save** (Q-6.1-2). The buffer keeps the
  removed part in `content` and marks it removed; Save takes it out. So a
  removed part is still an element that the person can select and restore.
  (The other way: apply the removal, and let the projection draw the removed
  part of `base` at its old place. That way every projection of a collection
  must draw a part that is not in its input.)
- **Save** is `SaveFileOperation`, which exists. `get_wrapped_document` of the
  buffer answers the content without the removed parts, so the file gets what
  the person sees as kept; after the write, the buffer takes the saved content
  as its new `base` and empties `changes`.
- **Revert** is `ReloadFileOperation`, which exists:
  `replace_wrapped_document!` gives the buffer the document of the file as
  `base` and `content`, and empties `changes`, as an undo buffer empties its
  lists.
- **The mark of a part** is found by its slot, as the undo buffer finds an
  element again by its cell (`get_slot_at`), so a mark stays on its element
  when the elements before it move.
- **A title says that a file has pending edits**, as an IDE tab does.

### 5.2 The changes of files: a feed

A **file-change feed** is a `Feed` of the editor:

- A document that a file holds asks to be told: `watch_document_file!(file)`.
  The application watches each file tab that it opens.
- A watcher task, one for each folder, with the notifications of the system
  (`FileWatching.watch_folder`), stores the paths that changed. Where no
  notification works, a poll of the time of the file every second does it.
- The drain, on the editor task, gives each watched file document of a changed
  path the new file: with no buffer and no pending change, a reload
  (`ReloadFileOperation`); with pending changes, a rebase (5.3).
- A write of the editor itself does not count: the save records the time of
  the file that it wrote, and the feed skips a change with that time.

### 5.3 A change of the file while edits are pending

The buffer takes the new file as its `base`, and makes `content` again: the new
base, then each pending change replayed in order (Q-6.1-4: "keep them on
top"). A change that no longer applies, such as an update of an entry that the
file no longer holds, is dropped, and the log names it.

### 5.4 The fingerprint store with these

A file type of omnet for `fingerprint.json`, chosen by the opener and not by
the extension, whose `emit_text` writes the bytes that `opp_repl` writes and
whose reader makes a `LegacyFingerprintStore` document (a lazy list of
`LegacyFingerprintEntry` documents). The tab of the store is
`file → undo buffer → pending-edit buffer → store`. An update task writes the
file at once, and the feed brings the change to the tab.

## 6. Questions to the owner

- **Q1, a removed part.** (a) It stays in `content` with a mark, and Save takes
  it out. (b) It leaves `content`, and the projection draws it from `base`. My
  recommendation is (a).
- **Q2, undo and pending edits.** (a) The pending-edit buffer inside the undo
  buffer: an undo is an edit that passes through the pending-edit buffer, so it
  takes the pending change back too. (b) The pending-edit buffer outside. My
  recommendation is (a): Ctrl+Z then takes back an edit and its mark together.
- **Q3, a change on disk while edits are pending.** (a) Replay the pending
  changes on the new file, drop the ones that no longer apply, and say so in
  the log. (b) Ask the person, as an IDE does: keep the memory, load the disk,
  or compare. My recommendation is (a), because an update task must not wait
  for a person, and the person still sees each kept change marked.
- **Q4, the watcher.** (a) The notifications of the system, with a poll of the
  time where they do not work. (b) A poll only. My recommendation is (a).
- **Q5, the names.** `PendingEditBuffer`, `PendingEditBufferToAnyProjection`,
  `PendingEdit` for one change, and `FileChangeFeed`, in two new slices of the
  platform, `pendingedit` and `filechange`. These are my recommendations.

## 7. Steps

Each step is done when its tests pass, and the omnet step 6.1 continues after
step 4.

- [ ] **1.** The pending-edit buffer: the document, the record of a change, the
  marks of insert, update and remove, Save and Revert through the two file
  operations, and the title. A test with a JSON array in a file tab.
- [ ] **2.** The marks drawn: the projection draws a mark over an inserted,
  updated and removed part, and a removed part struck through, in the widget
  table and in the syntax views.
- [ ] **3.** The file-change feed: the watch, the drain, the reload of a file
  with no pending change, the skip of the editor's own write. A test that
  writes a watched file from another task.
- [ ] **4.** The rebase of pending changes on a changed file, with the log of a
  dropped change. A test that removes an entry, then changes the file on disk.
- [ ] **5.** The guide of each new slice in `documentation/package/platform/`.

## 8. Risks

- A replay of an operation recorded against an old base can land on the wrong
  element when the file moved its elements. The record keeps the identity of
  the element (its key in the file, for a store), not only its index.
- A watcher of each folder holds a task and a handle of the system; a session
  with many open files needs one watcher for each folder, not one for each file.
- The history and the pending edits can disagree when a step has no inverse;
  the undo barrier then stops at it, and the pending change stays.
