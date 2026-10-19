# Background work

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [statistics.md](../statistics/statistics.md), [roster.md](../roster/roster.md), [collection.md](../collection/collection.md), [widget.md](../widget/widget.md)

The backgroundwork slice of `ProjecturedPlatform` shows the work that the editor does off the loop for its background cells, as a table that a person opens like any other document. This document says how a record of the kernel becomes a row of the table, and why a view costs nothing while it is closed.

## How it works

The kernel keeps a `BackgroundWorkRecord` for each work of a background cell, in the `BackgroundWorkStore` of the editor. [editor.md](../../kernel/editor.md#the-record-of-each-work) describes the store. This package only reads it.

`BackgroundWorkRow` is the document of one work. It holds `number`, `source` (the description of the source), `values` (the count of values), `started` as `HH:MM:SS`, `took` (the duration, or "running"), `state`, `failure` and `inputs`. The `state` is "running", "done" or "failed".

`BackgroundWorkLog` holds `rows`, newest first, and `change_count`, the count of the store that the rows show, or -1 before the first copy. It holds `table` too: an `ArrangementDocument` of a `Roster` of `CollectionItems` at `rows`, linked to the log. So a person filters and sorts the rows as in any table of the platform. `get_session_background_work_log(; editor)` returns the one log of a session. The insertion alias `background` gives it.

`flush_background_work_log!(log, store)` copies the store into the log. A record that the log shows already keeps its row, and the row gets only the fields that changed. A new record gets a new row. So a view that reads one field redraws only when that field changes.

`BackgroundWorkFeed(; log = nothing, flush_interval = 0.25, now = time)` calls the flush:

- It copies at most once in each interval, and only when the count of the store differs from the count of the log **and** something reads the rows of the log. The test for a view is `has_dependent_cells` on `rows`. So an editor with no view of the log copies nothing.
- It never wakes the editor. A record changes only in a frame, so a wake would add nothing. `compute_wake_deadline` returns the interval while the log is due.

The wrapper `background_work = true` of `build_editor` gives the editor the feed, in the layer `:screen` with the order 20. It is off by default. `run_application` turns it on beside `frame_statistics`, and `make_editor_explorer_content` puts the log in the Editor section after the frame time series.

`BackgroundWorkLogToWidget` draws the log as a `GridLayout` of two rows. The first row is a line such as "2 works · 1 running · 1 failed", or "No background work yet." The second row is the table. A path `table.<rest>` of the log maps to the second child of the grid, so a selection in the table reaches the document. The title is "Background work".

A row has the condition of its state, `:running`, `:failed` or `:done`, as a work item. The log has the icon `:loader`, `:running` with a pill "N running" while a row runs, and `:failed` with the count of failed rows.

A worked example: a person opens two folders in a tree in one frame, while the page of the log shows.

| When | The store | The log |
| --- | --- | --- |
| The frame ends | Record 7 starts: "the listings of folders", 2 values | No change |
| The next deadline | No change | Row 7 comes at the top, state "running" |
| The answers are written | Record 7 ends, and `finished` is set | At the next deadline, row 7 gets `took` and state "done" |

## How it fits

The slice depends on the kernel for the store and the feed contract, and on the arrangement, collection, domain, layout, projection, roster, serialization, style and widget slices for the table and its page. It depends on no domain. It loads after the statistics slice.

A `.pred` file writes no field of the log: the log of a window is the one of the session that loads it.

## Design decisions

- **The kernel keeps a plain store, and the platform owns the document.** The kernel records the works, and the documents of an editor belong to the platform. The store has no cell, so a record costs the kernel one value. See [the plan](../../../../plan/done/the-editor-shows-its-background-work.md).
- **The feed copies only while a view shows the log.** As with the frame statistics, `has_dependent_cells` answers the question, so the feed needs no registry of tabs.
- **The feed has a deadline, not a wake.** The records change in frames, so the feed waits for the interval and does not make frames.
- **The table is an arrangement of a roster.** It is built as a page of a table of files is, so the filter and the sort come from the arrangement slice, and this slice has no code of its own for them.
- **A row keeps its identity.** A flush writes a field only when it changed, so a view of a row that did not change stays still.

## Limits

- The store keeps the last 100 works that ended, and every work that runs. No setting changes the capacity.
- The works of `start_background_work` that no background cell starts are not in the log.
- The interval of the feed is 0.25 seconds. The wrapper gives no setting for it.
- The wrapper is off by default. An editor without it keeps records in the store and shows none.

## Layer structure

The slice is the folder [source/platform/backgroundwork/](../../../../source/platform/backgroundwork/), and `BackgroundWorkModule` is its module.

```
backgroundwork/BackgroundWorkModule.jl        (BackgroundWorkModule): the module, its exports and its include order
    ├─ BackgroundWorkDocument.jl      : BackgroundWorkRow, BackgroundWorkLog, the flush and the session log
    ├─ BackgroundWorkFeed.jl          : BackgroundWorkFeed and the wrapper background_work
    └─ BackgroundWorkLogToWidget.jl   : the page: the line and the table
```

## Tests

- `test_background_work()` in [BackgroundWorkTest.jl](../../../../test/platform/backgroundwork/BackgroundWorkTest.jl). A view of the log fills it, newest first, and a row runs, ends and fails. A folder that an explorer opens leaves a row, and a log that no view shows stays empty. The test drives the frames as the loop does, with `drain_feeds!` before each `run_frame!`, because `run_frame!` alone drains no feed.
- The kernel test in [BackgroundCellTest.jl](../../../../test/kernel/editor/BackgroundCellTest.jl): each work leaves a record in the store of its editor, and the store keeps the last ones.
