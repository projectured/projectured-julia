# A frame measures its device read and its device write

Status: in progress, on the branch `device-times`, in the worktree
`projectured-julia-device-times`.

## The ask

The owner, 2026-10-22: "do we measure the writing to the backend and the reading
from the backend both in terms of time and cell counters (if enabled)?" No branch
did this work: `plan/done/frame-statistics-print-only-new-rows.md` lists the
times of the device read and of the device write under "Not in this plan". To the
question whether to write a plan for it, the owner answered: "yes, let's do this,
plan and implement".

## The problem

1. **The device read has no time of its own.** `take_from_devices!` runs in
   `_read_from_devices_guarded` (`FaultBarriers.jl`), inside the read stage. Its
   time is a part of `:read_time`, together with the reader of the projection.
   The read stage runs up to `MAX_OPERATIONS_PER_FRAME` reads in one frame.
2. **The device write has no time of its own.** `write_to_devices!` runs in
   `_write_output_to_devices!` (`ReadEvaluatePrint.jl`), inside the print stage.
   Its time is a part of `:print_time`. The print is lazy: `print_document`
   builds the cells, and most printer computations run when the backend reads
   the output in `write_to_devices!`.
3. **The cell counts are for the whole frame.** With the counters compiled in,
   `run_measured_frame!` binds one counter store for the frame. No stage and no
   device half has counts of its own.

## The model

- **Two times, in every build.** `:device_read_time` is the sum of the times of
  `take_from_devices!` in the frame. `:device_write_time` is the time of
  `write_to_devices!`. Each is a part of its stage: `:read_time` still holds the
  device read, and `:print_time` still holds the device write. So no name that
  exists changes its meaning. As in a stage, the time of held frames does not
  count.
- **Eight counts, with the counters only.** For each device half, the four cell
  counts of the scope that the half added: `:device_read_reads`,
  `:device_read_computes`, `:device_read_invalidations`, `:device_read_writes`,
  and the same four with `device_write`. They come from the difference of
  `get_performance_counters()` before and after the call. So the sealed
  `PerformanceCounter.jl` does not change. A count that `@count_performance`
  adds is not split: only the four cell counts are.
- **The record of a frame keeps them.** `_FrameStages` holds the two times and
  the two groups of counts as tuples, so a build without the counters allocates
  nothing more. `record_frame_performance!` records each time after the time of
  its stage, so the frame statistics show it on the next row.

### Names

The prefix names the part of the frame, and the suffix names the measure, as in
`:read_time`. A half is `device_read` or `device_write`, the words of the fault
counters of the device seam.

| Name | Unit | When |
| --- | --- | --- |
| `:device_read_time` | second | every build |
| `:device_write_time` | second | every build |
| `:device_read_<count>`, `:device_write_<count>` for `reads`, `computes`, `invalidations`, `writes` | count | counters compiled in |

## Steps

Do the work in this worktree. Commit each step. Do not land on `main` before the
owner approves.

1. [ ] **The measurement.** `_FrameStages` in `Editor.jl`, a timer of a device
   half in `Feeds.jl`, its two calls in `FaultBarriers.jl` and
   `ReadEvaluatePrint.jl`, the record in `record_frame_performance!`, and the
   docstrings. Tests in `test/kernel/editor/FeedsTest.jl`: a probe backend whose
   read and whose write take a known time, and with the counters, read a
   computed cell. Run `test_editor_frame_performance()`, `test_editor_feeds()`
   and the tests of the fault barriers. Commit.
2. [ ] **With the counters compiled in.** Run the same tests in a scratch
   environment with `performance_counters = true`. Commit a fix if one is
   necessary.
3. [ ] **A live check and the guides.** An editor on the SDL backend, offscreen,
   runs frames of an example; the plan gets the two times beside `:read_time`
   and `:print_time`. The guides `editor.md` and `performance.md` name the new
   measurements. The plan moves to `plan/done/`. Commit.

## Not in this plan

- The time of `get_frame_clock_time`, the other call of the backend in a frame.
- A split of the counts that `@count_performance` adds, and of the times that
  `@measure_performance_time` adds.
- The line that `_log_performance_counters!` logs.
