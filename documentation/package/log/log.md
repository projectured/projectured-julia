# Message log

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../kernel/editor.md), [domain-anatomy.md](../../design/domain-anatomy.md)

`ProjecturedLog` shows the messages that the program logs with `@info`, `@warn` and `@error` as a document in a tab. This document says how a message from any task reaches the document without a write to a cell from that task.

## How it works

A message travels through three parts. This is the feed pattern of the editor; [the feeds](../kernel/editor.md) in editor.md describe the contract.

1. **`MessageLogLogger`** is an `AbstractLogger` that wraps the logger that was installed before it. It writes each message into the store, and then gives it to the previous logger, so the terminal shows what it showed before. `install_message_log_capture!()` installs it, and a second call does nothing, so no message is recorded twice. `remove_message_log_capture!(previous)` puts the previous logger back.
2. **`MessageLogStore`** is a plain object with a lock and a ring of up to 1000 lines. Any task can write it. After a write it calls the wake function of the editor, outside the lock.
3. **`MessageLogFeed`** empties the store once per frame, on the editor task, into the `MessageLog` document. If the ring dropped lines since the last frame, the feed first adds a `Warn` entry that says how many.

`MessageLog` holds `entries`, a `capacity` of 200 and a `count` of all messages so far. One log exists for each session, `get_session_message_log()`. Two log tabs are two views of the same document, and the insertion name `log` gives that document, not a new empty one.

`MessageLogToSyntax` prints one line for each entry, newest first, so the newest line keeps its place on the screen. The level and the message are two columns in DejaVu Sans Mono, because a glyph that falls back to another font has another width and breaks the columns. The view has no reader: a log is not edited.

## How it fits

`ProjecturedLog` depends on the kernel for the feed contract, and on `ProjecturedSyntax` and `ProjecturedText` for the view. Its `__init__` registers the view with `register_natural_syntax!(:messagelog, …)` and `MessageLog` as a `.pred` type. `pred_arguments` saves only the capacity, so a loaded log starts empty.

`ProjecturedShell` uses it: `run_with_window_tools` installs the capture and gives the editor a `MessageLogFeed`, and the toolbar has a button that opens the log.

## Design decisions

- **No task writes a document cell except the editor task.** A write from the logging task raced the frame. The store is the only shared state, and the drain is the only writer. See `plan/done/the-editor-waits-for-events.md` and the invariant `PAR-STORE-THEN-DRAIN`.
- **A lost line is reported, not hidden.** The warning entry shows that the ring was full.
- **One log for the session.** A second log document would never fill, because the one capture writes the one store.

## Usage

```julia
previous = install_message_log_capture!()
run_window_editor(document, projection, "Title"; backend = SdlBackend(),
                  feeds = Feed[MessageLogFeed()])
remove_message_log_capture!(previous)
```

`run_with_window_tools(run)` in `ProjecturedShell` does these steps for you. `run_message_log_feed_example()` in `example/projectured/FeedExamples.jl` opens a window with a log.

- Tests: `test_message_log_feed()` and `test_message_log()`, in the application test package. `test_message_log()` installs the capture of the session, drains the feed by hand, and checks the log and its view. The package has no suite of its own.

## Limits

- Two different bounds exist: 1000 lines in the store between frames, and 200 entries in the document.
- If a program installs the capture but gives the editor no `MessageLogFeed`, the lines stay in the store and no view shows them.
