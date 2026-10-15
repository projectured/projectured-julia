# File change

> **Kind:** design · **Status:** current · **Stands on:** [fileformat.md](../fileformat/fileformat.md), [editor.md](../../kernel/editor.md)

The file-change slice of `ProjecturedPlatform` reports a change of a file on disk to the receiver of the file. Another program changes a file: a tool in a terminal, a checkout of git, a task that writes a store. A watcher reads the change off the loop, and the receiver of the file takes it on the editor task, with no action of a person. This document says how a change is noticed, how it reaches the receiver, and what happens to edits that are not saved.

## How it works

| Part | What it is |
| --- | --- |
| `FileChangeStore` | the watched file documents, a watcher for each folder that holds one, and the paths that changed since the last drain; each `FileChangeFeed` owns one, so each editor has its own (`get_session_file_change_store(; editor)`) |
| `watch_document_file!(file; receiver)` | the file document watches its file, in the store of the editor of the evaluation, and reports each change to `receiver`, which is the file itself by default; `unwatch_document_file!` stops it, and `close_file_change_store!` stops every watcher of a store |
| `drain_file_changes!(; store, editor)` | reports each stored change to the receiver of its file, on the task that reads the documents |
| `FileChangeFeed` | the feed of a window: a watcher wakes the editor, and the drain runs once a frame |

### A change is noticed by a watcher of the folder

A watcher task watches each folder that holds a watched file, with a `FolderMonitor` of `FileWatching`, which takes the notifications of the system (inotify on Linux). An event of the folder marks every watched file of the folder as changed, because a program that writes a file at once writes another file and renames it over the first, and the event then names the other file. A folder where the system gives no notification, such as some network file systems, is polled: every `poll_interval` seconds, one second by default, the watcher compares the time and the size of each watched file with what it saw at its last look, or at the start of the watch of the file, so a change before the first look counts too.

A watcher writes only the store, from its own task, and wakes each editor that drains the store. The watcher of a folder stops when the last watched file of the folder stops watching.

### A change reaches the receiver on the editor task

A watcher reads a changed file off the loop. It hashes the text, parses a new document, and keeps both in the store. The drain, on the editor task, reports each change once to the receiver of the file: `receive_file_change!(editor, receiver, file_hash, content)`. The file-format slice declares this function. The drain decides nothing: the receiver decides what the change means.

| Receiver | What it does with a change |
| --- | --- |
| a `FilePage`, with the hash it already holds | nothing: its own save or load wrote that text |
| a `FilePage`, for a file with no edits, or a file that a person does not edit | loads the new document |
| a `FilePage`, for a file with edits, or with no history that says | keeps what it holds, and shows its band with "Load it" and "Keep mine" |
| a file document with no page, for a file that a person does not edit | loads the new document |
| a file document with no page, for any other file | keeps what it holds, and logs a warning, because it can not tell its own save from a change |

The receiver of a file in a tab is its `FilePage`. A tab acquires its outer layer first, so the page watches the file with itself as the receiver. A file document with no page is its own receiver. The page and its band are described in [fileformat.md](../fileformat/fileformat.md).

A file of a type that a person does not edit (`is_editable_file_type` answers `false`), such as the result file of a run that writes it while it runs, has no edits to keep and can be too large to read whole. The watcher compares only the time and the size of its file with those of the last read, and never reads its text.

`drain_file_changes!` answers how many receivers took the new document. A caller with no window drains the store itself, on the one task that reads the documents.

## How it fits

The code is in `source/platform/filechange/`. The slice depends on the file-format slice for `receive_file_change!`, `FilePage`, `find_page_file` and `compute_file_text_hash`, on the serialization slice for `FileDocument`, and on the feed of the kernel. No slice depends on it. A program that watches its files calls `watch_document_file!` for each file document that it opens, or opens a tab, which watches its file itself, and gives its editor the feed with `make_file_change_feeds()`.

## Design decisions

- **The feed is generic.** Any file document can watch its file; the slice names no domain. See [plan/pending/pending-edits-and-file-changes.md](../../../../plan/pending/pending-edits-and-file-changes.md).
- **A watcher for each folder, not for each file.** A program writes a file at once by a rename, which a watch of the file itself loses, and a session with many files of one folder needs one handle of the system.
- **The text decides, not the time.** A save changes the time of its file too. The hash of the text separates a save from a change of another program, and the receiver compares it, not the drain.
- **The watcher knows nothing of editing.** It watches, reads, hashes and parses. The receiver owns the meaning of a change, so the slice reads no edit and makes no band. It names `FilePage` only to watch a file with its page as the receiver.
- **An edit that is not saved is never lost.** The receiver keeps the edits of a file that has them, and shows a choice. The drain never replaces a document.
- **No watch while Julia writes a precompile cache.** `watch_document_file!` does nothing in such a process. Julia ends a precompile only when every task of its workload has ended, and the task of a watcher ends only when its folder monitor closes, so one watch in a workload holds the precompile forever.

## Usage

```julia
tab    = make_file_tab("notes.txt")
editor = build_editor(tab; feeds = make_file_change_feeds())   # a feed with a store of its own
store  = get_session_file_change_store(; editor)               # the store of that feed
watch_document_file!(tab; store)               # in an evaluation of the editor, `store` is the default
drain_file_changes!(; store)                   # a caller with no window drains it itself
unwatch_document_file!(tab; store)
```

A watch where no editor with a `FileChangeFeed` is the editor of the evaluation does
nothing: no drain would bring its changes, and its watcher task would run forever.

- Examples: none.
- Tests: `test_filechange()` in `test/platform/filechange/FileChangeSuite.jl` runs `test_file_change_store()` in `FileChangeStoreTest.jl`. It covers a page whose file has no edits, a save of the page, a page with edits and its band, a page with no history, a file with no page, the save that checks the disk, the feed, a file type that an opener chose, a file that a person does not edit, a polled folder, one store for each editor, a tab that watches while it is open, and the `file_change` wrapper.

## Limits

- A load reads the file again with `ReloadFileOperation`, which writes no selection; a selection that pointed into the old content can point at nothing.
- A file that is removed keeps its document as it is.
