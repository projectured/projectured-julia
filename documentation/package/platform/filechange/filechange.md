# File change

> **Kind:** design · **Status:** current · **Stands on:** [fileformat.md](../fileformat/fileformat.md), [editor.md](../../kernel/editor.md)

The file-change slice of `ProjecturedPlatform` brings a change of a file on disk to the document that the file holds. Another program changes a file: a tool in a terminal, a checkout of git, a task that writes a store. A file document that watches its file reads the change, on the editor task, with no action of a person. This document says how a change is noticed, how it reaches the document, and what happens to edits that are not saved.

## How it works

| Part | What it is |
| --- | --- |
| `FileChangeStore` | the watched file documents, a watcher for each folder that holds one, and the paths that changed since the last drain |
| `watch_document_file!(file)` | the file document watches its file; `unwatch_document_file!` stops it |
| `drain_file_changes!(; store, editor)` | brings each stored change to its document, on the task that reads the documents |
| `FileChangeFeed` | the feed of a window: a watcher wakes the editor, and the drain runs once a frame |

### A change is noticed by a watcher of the folder

A watcher task watches each folder that holds a watched file, with a `FolderMonitor` of `FileWatching`, which takes the notifications of the system (inotify on Linux). An event of the folder marks every watched file of the folder as changed, because a program that writes a file at once writes another file and renames it over the first, and the event then names the other file. A folder where the system gives no notification, such as some network file systems, is polled: every `poll_interval` seconds, one second by default, the watcher compares the time and the size of each watched file with what it saw at its last look, or at the start of the watch of the file, so a change before the first look counts too.

A watcher writes only the store, from its own task, and wakes each editor that drains the store. The watcher of a folder stops when the last watched file of the folder stops watching.

### A change reaches the document on the editor task

The drain reads each changed file and compares three texts: the text of the file on disk, the text that a save of the document writes now (`compute_file_text` of the file-format slice), and the hashes of both from the last sync.

| What the drain finds | What it does |
| --- | --- |
| The file holds the same text as at the last sync | nothing |
| The file holds what the document writes | nothing: a save of the document wrote it |
| The document was not edited since its last load or save | reads the file again, as `ReloadFileOperation` does |
| The document has edits that are not saved | keeps them, and logs that the file changed on disk |

A document that keeps its edits keeps them until the person decides: Ctrl+O reads the file again, Ctrl+S writes the document over it. The log names each change once.

A file of a type that a person does not edit (`is_editable_file_type` answers `false`), such as the result file of a run that writes it while it runs, has no edits to keep and can be too large to read whole. The drain compares only the time and the size of its file with those of the last sync, and when they changed, it reads the file again. The text of such a file is never read to compare.

`drain_file_changes!` answers how many documents read their file again. A caller with no window drains the store itself, on the one task that reads the documents.

## How it fits

The code is in `source/platform/filechange/`. The slice depends on the file-format slice for `ReloadFileOperation` and `compute_file_text`, on the serialization slice for `FileDocument`, and on the feed of the kernel. No slice depends on it. A program that watches its files calls `watch_document_file!` for each file document that it opens, and gives its editor the feed with `make_file_change_feeds()`.

## Design decisions

- **The feed is generic.** Any file document can watch its file; the slice names no domain. See [plan/pending/pending-edits-and-file-changes.md](../../../../plan/pending/pending-edits-and-file-changes.md).
- **A watcher for each folder, not for each file.** A program writes a file at once by a rename, which a watch of the file itself loses, and a session with many files of one folder needs one handle of the system.
- **The text decides, not the time.** A save of the document changes the time of its file too; the comparison with the text that the document writes separates the save from a change of another program, with no hook in the save.
- **An edit that is not saved is never lost.** The drain reads a file again only into a document whose text is the text of its last sync.

## Usage

```julia
store = get_session_file_change_store()
tab   = make_file_tab("notes.txt")
watch_document_file!(tab)                      # the session store
editor = build_editor(tab; feeds = make_file_change_feeds())
drain_file_changes!()                          # a caller with no window
unwatch_document_file!(tab)
```

- Examples: none.
- Tests: `test_filechange()` in `test/platform/filechange/FileChangeSuite.jl` runs `test_file_change_store()`: a change reaches a document that was not edited, a file written by a rename is seen, a save is no change, an edit that is not saved stays, the feed drains and is woken, and a polled folder.

## Limits

- The drain reads the file again with `ReloadFileOperation`, which writes no selection; a selection that pointed into the old content can point at nothing.
- No program of this repository watches its files yet; the application does not call `watch_document_file!` for the files that it opens.
- A file that is removed keeps its document as it is.
