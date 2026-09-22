# Frame statistics

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../kernel/editor.md), [log.md](../log/log.md)

`ProjecturedStatistics` shows what the editor loop measures about itself, such as the time of a frame, as a table in a tab. This document says how the table gets its numbers without a cost when no view is open.

## How it works

The kernel measures each frame into a `FrameSampleStore` on the editor, `editor.frame_samples`. This package only reads that store.

`FrameStatistics` holds `rows`, one `FrameMeasurement` for each measurement name, and `frame_count`. A row has the count, the minimum, the maximum, the mean, the standard deviation and the total, in seconds, over every frame since the start. One table exists for each session, `get_session_frame_statistics()`, and the insertion name `statistics` gives that table.

`FrameStatisticsFeed` moves the numbers into the table:

- It flushes only when the store has new samples **and** a view reads the table. The test for a view is `has_dependents` on the `frame_count` cell, which every view reads. So an editor with no statistics tab folds the samples and formats nothing.
- It never wakes the editor. Its data comes only with frames, so a wake would make frames that feed themselves. Instead `compute_wake_deadline` returns the flush interval, 0.25 seconds by default, while a view is open.
- `flush_frame_statistics!` updates a row field by field. A cell whose number did not change keeps its dependents valid.

`FrameStatisticsToSyntax` prints a header with the frame count, a column header, and one line for each row, in DejaVu Sans Mono so that the columns align. A value prints with four significant digits.

## How it fits

`ProjecturedStatistics` depends on the kernel for the feed contract and the performance layer, and on `ProjecturedSyntax` and `ProjecturedText` for the view. `ProjecturedShell` gives the editor a `FrameStatisticsFeed` in `run_with_window_tools`, and the toolbar has a button that opens the table.

`pred_arguments` saves nothing: the numbers of one session are not the numbers of the next.

## Design decisions

- **A feed can ask whether anyone looks.** `has_dependents` on a cell of the target document answers it, so the feed needs no registry of tabs.
- **This feed has a deadline, not a wake.** The log feed wakes on each message; this feed would wake itself. [log.md](../log/log.md) is the other side of the comparison.

## Usage

```julia
run_window_editor(document, projection, "Title"; backend = SdlBackend(),
                  feeds = Feed[FrameStatisticsFeed()])
```

Then open a tab and type `statistics`. `example/projectured/FeedExamples.jl` builds the view with `FrameStatisticsToSyntax()`.

- Test: `test/projectured/editor/FrameStatisticsFeedTest.jl` covers the flush and the gate. The package has no suite of its own.

## Limits

- The package registers no natural row for `FrameStatistics`. A statistics tab that the toolbar opens goes through the general renderer, which then shows the reflected fields and not `FrameStatisticsToSyntax`. `MessageLog` has the row that this package lacks.
- `run_with_window_tools` makes the feed with the default interval. No setting changes it.
