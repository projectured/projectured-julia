# Guards keep the frame short at any size

Status: PENDING, 2026-10-21. Step 1 runs: the record is done, the live measurement
is open. No decision is open: D1 is decided, in [The decision](#the-decision).

## The ask

The owner, 2026-10-20: "the editor frame time is sometimes 5ms sometimes
80-100ms. I would like to have a plan which adds guards for the frame time to be
small. we should check each part of the editor, we should drive the parts with
large scale inputs to see how they scale. e.g. printer, evaluator, reader, feeds,
tasks, MCP tools, etc. of course only those parts which should not affect the
responsiveness of the editor. we need tests which will guard the performance"

## The problem

The facts at `main` `2ec1262c5`. Find each function by its name. Three surveys of
the code found them. Nothing below is measured, unless a number says so.

1. **The record of a frame can not show why a frame is slow.**
   - `record_frame_performance!` records `:frame_time` in every build. It records
     `:read_time`, `:evaluate_time` and `:print_time` only when the preference
     `performance_counters` compiled the counters in, and the preference is off by
     default.
   - The record has no time of the garbage collector, no compile time and no
     count of allocated bytes.
   - `:frame_time` includes the held frames of a code unit. The report of a slow
     frame subtracts them, but the record does not. So a tool call of 80 ms shows
     as one frame of 80 ms in *Editor › Frame times*, although held frames painted
     the window during the call.
   - `_time_frame_stage` keeps only the slowest stage, and `_report_slow_frame!`
     writes a line only above `SLOW_FRAME_SECONDS = 1.0`.
2. **The code holds candidates for a frame of 80 to 100 ms.** None is measured.
   - `receive_folder_change!` calls `start_document_read!` for a changed
     sub-folder. That call waits on the owner task for up to
     `DOCUMENT_READ_WAIT = 0.05` s. Two such changes in one drain of the
     `FileChangeFeed` can wait 100 ms.
   - Each delta of an assistant answer, each chunk of terminal output and each
     step of a formula posts a `RunFunctionOperation`, so its drain is a code
     unit. For each unit, `prepare_held_frames!` draws about 15 texts for each
     window.
   - `_append_text_delta!` makes the whole text block again for each delta, so
     each delta of a long answer costs more than the delta before it.
   - Four feeds wake the loop every 0.25 s: the frame statistics and the
     background work log while a view reads them, the task feed while it holds
     an entry, and the agent events while a subagent or a background task runs.
     The flush of the frame statistics makes a summary of each name over the ring
     of 1000 frames, and copies the ring for the chart. So the view that shows the
     frame times also makes frames. The application turns on the frame
     statistics, the background work log, the message log, the fault log and the
     file change by default.
   - The SDL backend paints the whole window again when its records pass
     `2 × baseline + _PAINTED_RECORD_SLACK`. It destroys every text texture when
     `_text_texture_cache` reaches `_TEXT_TEXTURE_CACHE_CAP = 16384`.
   - A garbage collection stops every thread. The compile of a new method runs
     inside the frame that calls it first. The record shows neither.
3. **Many parts have no bound on the work of one frame.** The bounds that exist
   are `MAX_OPERATIONS_PER_FRAME = 32`, `INBOX_CAPACITY = 64`, 64 faults, 32 dirty
   rectangles and the capacities of the stores. There is no bound on:
   - the operations that the owner task posts to its own editor;
   - the events that one drain of the `AgentEventFeed` takes;
   - the lines that one drain of the `MessageLogFeed` takes, and the calls that
     one drain of the `McpLogFeed` takes;
   - `_retry_marked_barriers!`;
   - the graphics that the dirty walk visits in a canvas with no layout, which
     is the subject of [a-frame-walks-only-what-changed.md](a-frame-walks-only-what-changed.md);
   - the run time of a `RunFunctionOperation`.
4. **The guards that exist count the rows of lazy collections only.**
   - `LayoutListTest`, `WidgetTablePartsTest`, `WidgetTreeTest`, `TreeTest`,
     `ExplorerTest` and `DataFrameViewTest` count the rows that a print makes,
     at 10^6 or 10^7 elements.
   - No test measures a whole frame at two sizes. No test measures a feed, the
     inbox, the report of the faults, MCP, the assistant or the paint at scale.
   - The time assertions that exist are absolute, for example `elapsed < 5.0` in
     `test_chart_scale`. A downstream test that compares two wall clock times
     failed once at 591 times its bound, under the load of a full suite.
5. **The headless backend reads every part of the output in each frame.**
   `_paint_headless!` visits each part that the print made, and up to 200 new
   links of a list. So a frame on a `HeadlessBackend` grows with the output,
   whatever the part does. A guard of the print or of the paint must use a
   backend that paints as a window paints: the SDL backend with
   `SDL_VIDEODRIVER=offscreen`. The domain test packages do not load SDL.

## The model

### The rule

The work of one frame has two limits: what the window shows, and a fixed count
for each frame. It never grows with the size of a document, a store, a queue or a
burst. Work above the count waits for the next frame. Work that takes longer runs
off the loop. `MAX_OPERATIONS_PER_FRAME` and `INBOX_CAPACITY` apply this rule now.

A guard checks the rule for one part. It drives the part at three sizes of its
input, each 10 times the size before it. Then it compares the work of a frame at
the largest size with the work at the smallest size.

A guard measures only the work on the owner task. These parts run off the loop,
and a guard does not measure how long they take:
- the call of a model;
- the body of a tool;
- the code that a person evaluates;
- a sort or a read in the background;
- the read of a file or of `/proc`.

For these parts, the guard measures the frames that their posts cause while they
run.

### The record of a frame

In every build, each frame records these values in `editor.frame_measurements`,
beside `:frame_time`:

| Name | Unit | Value |
|---|---|---|
| `:feed_time`, `:read_time`, `:evaluate_time`, `:print_time`, `:report_time` | second | the sum of each stage, from `_time_frame_stage`; `:print_time` holds the print and the paint |
| `:held_time` | second | the held frames of a code unit |
| `:garbage_collection_time` | second | the garbage collections, from `Base.gc_num()` |
| `:compile_time` | second | the compiler, from `Base.cumulative_compile_time_ns()` |
| `:yielded_time` | second | the time that the loop task did not run, from `Base.Experimental.task_running_time_ns`; only when the process starts with `--task-metrics=yes` |
| `:allocated_bytes` | count | the bytes that the process allocated in the frame |

The body of one turn of the loop after the wait becomes one function,
`run_measured_frame!`. It writes the clock, drains the feeds, runs the frame and
records it. The loop and the guards call it, so a guard measures the frame that
the loop runs.

A probe on 2026-10-20, Julia 1.13.1: `Base.gc_num()` costs 35 ns, and
`task_running_time_ns` costs less than 1 ns. `task_running_time_ns` answers
`nothing` for a task that started before the metrics were on. So the record
reads it only when the process started with `--task-metrics=yes`.

### The harness

The harness is in the kernel test package. Every test package above the kernel
can use it.

- A `FrameScene` names a part and its three sizes. It has a function that makes
  the editor at a size, and a function that gives the input of a frame. An input
  is a gesture, a post from another task, a change in a store, or nothing for an
  idle frame.
- The input of a burst comes once. The scene then runs frames until
  `compute_wait_timeout` is not 0 and no wake waits.
- A scene of a deadline waits until its feed is due, outside the measured time.
- `measure_frame_work` runs 30 frames to warm up, and then 50 measured frames
  for each size. It answers one row for each size: the minimum and the median
  frame time, the median of each stage, the allocated bytes, the garbage
  collection and compile times, and a count of work where the part keeps one.
  `paint.drawn` of the SDL paint and the `built` counts of the lazy collections
  are counts of work.
- `compute_frame_growth` answers the ratios of the largest size to the smallest:
  the minimum time, the allocated bytes and the count of work. A burst also
  answers its count of frames.
- A guard asserts each ratio against its bound with `@test`, so a failure shows
  the number. A guard that fails prints its rows.

The first bounds for a flat part, at 100 times the size, are 3 for the time, 2
for the allocated bytes and 2 for a count. Step 2 sets the bounds from the
self-test of the harness.

A scene on the `HeadlessBackend` shows a view of a fixed size, or no view. A
scene whose input grows in the window uses SDL.

### The parts and their steps

| Part | Step |
|---|---|
| inbox, posts of the owner task, faults, cell writes, code units | 3 |
| the door of MCP tools | 3 |
| feeds and stores: message log, background work, tasks, file change, terminal, agent events, frame statistics; formulas | 4 |
| printer, reader and evaluator of the documents that a person opens; the assistant transcript; the MCP log view | 5 |
| the paint of the SDL backend: the walk, the texture cache, the full paint, held frames | 6 |
| the whole application window at a large state | 7 |

## The decision

**D1. What a guard asserts about time. Decided by the owner, 2026-10-20: A, with
the budget of a median of 8 ms and a 99th percentile of 16 ms** ("Agreed").

- **A. Growth in every suite, a budget in a suite of its own.** A guard in a
  package suite compares a part with itself at two sizes in one process. It
  compares the allocated bytes, the minimum frame time, and a count of work
  where the part keeps one. These do not depend on the speed or the load of the
  machine. Only `test_frame_budget()` asserts absolute times: a median of 8 ms
  and a 99th percentile of 16 ms for each scene, without `:held_time`. It runs
  alone in the measurement lane, and not in `test_all()`.
- **B. A budget in every suite.** Each guard also asserts the absolute times of
  A. This is simpler. But a suite then fails when the machine is busy, as the
  downstream ratio test did at 591 times its bound.
- **C. A, and counts of the cells.** A test environment with
  `performance_counters = true` lets each guard also assert the reads and the
  computations of the cells in a frame. These counts are exact. But each change
  of the preference compiles every package again, and the environment is one
  more to keep up to date.

Claude's reason for A: a guard must fail for a change of the code and never for
the load of the machine. A ratio of the minimum times and a ratio of the
allocated bytes do that. A part whose work grows 100 times with its input shows
a ratio near 100, and noise moves a minimum time by less than 2 times.

## Keep

1. Do not change a sealed file. `PerformanceModule.jl`, `PerformanceCounter.jl`,
   `FrameMeasurement.jl` and `CellModule.jl` are 🔒. The record uses
   `record_frame_measurements!` as it is.
2. Add no event, payload or channel. The record adds names to the store that each
   editor has.
3. The state stays with its editor (`PAR-PER-EDITOR-STATE`). The compile timer
   of Julia is a switch of the process: the loop turns it on at its start and
   off at its end. Step 1 checks that the switch counts nested calls.
4. The record costs less than 5 µs for each frame. Step 1 measures it.
5. Each new name follows [naming-rules.md](../../documentation/rule/naming-rules.md).
6. A guard asserts a measured number against a bound, never only that a value
   exists.

## Rule of measurement

A number is a time, a count of allocated bytes, a count of work or a count of
frames. Take each time for [As built](#as-built) and for `test_frame_budget()`
in the measurement lane, `taskset -c 28,30,31`, with `main` and the branch
interleaved as A/B/A. Write the load of the machine beside the time. A count
needs no idle machine.

## Steps

Do the work in a worktree on a branch of its own. Commit each step. Do not land
on `main` before the owner approves. A guard that fails on `main` gets
`@test_broken` with a `# @broken:` line that names its cause, and a row in
[As built](#as-built). This plan fixes no part.

1. [ ] **The record of a frame, and the cause of the slow frames.**
   - [x] `_FrameStages` keeps the sum of each stage beside the slowest stage.
     `record_frame_performance!` records the names of
     [The record of a frame](#the-record-of-a-frame) in every build. The three
     `@measure_performance_time` in `run_frame!` go, because the stage sums time
     the same stages.
   - [x] Make `run_measured_frame!`, and let `_run_editor_loop!` call it.
   - [x] Tests: `test/kernel/editor/FeedsTest.jl` and
     `test/kernel/editor/FrameDrainTest.jl`. A new testset: a frame with a code
     unit records its `:held_time`; a frame that calls `GC.gc()` records a
     `:garbage_collection_time` above 0; a frame that compiles a new method
     records a `:compile_time` above 0. Run `test_kernel()`, and
     `test/projectured/editor/FrameStatisticsFeedTest.jl` for the view of the
     new names.
   - [ ] Measure the cost of the record and of `--task-metrics=yes` on a frame.
   - [ ] In the live application, with `--task-metrics=yes`, record the frames of
     10 minutes of use. Use the window and the work in which the owner sees the
     slow frames. The owner, 2026-10-20: "In the assistant pane I saw every
     second or third or so frame to be more than 50ms." So use the default
     window with the Explorer, a large file and the Assistant pane, with and
     without an assistant turn. Write the frames as CSV with `write_frame_measurements!`. Sort each
     frame above 16 ms by its largest value: a stage, `:held_time`,
     `:garbage_collection_time`, `:compile_time` or `:yielded_time`. Write the
     table in [As built](#as-built).
   - Commit.
2. [ ] **The harness.** `FrameScene`, `measure_frame_work` and
   `compute_frame_growth` in `test/kernel/performance/`, exported by
   `ProjecturedKernelTest`.
   - A self-test with three synthetic parts: one that does fixed work, one whose
     work grows with the logarithm of its size, and one that does 10 ns of work
     for each element of its input.
   - Run the self-test five times, also once beside a full suite. Set the bounds
     so that the first two parts pass with a margin of 2 times in each run, and
     the third part fails in each run. Write the spread and the bounds in
     [As built](#as-built).
   - Commit.
3. [ ] **The kernel and the door of MCP.** `test_kernel_frame_guards()` in
   `test/kernel/editor/` and `test_mcp_frame_guards()` in `test/adapter/mcp/`,
   on the `HeadlessBackend` with a small view:
   - **Inbox:** a burst of 100, 1_000 and 10_000 operations from another task.
     Each frame stays flat, and the burst ends in at most `ceil(N / 64) + 1`
     frames.
   - **Posts of the owner task:** an operation that posts 100, 1_000 and 10_000
     operations to its own editor.
   - **Faults:** a burst of 10, 100 and 1_000 faults with distinct keys.
   - **A cell write:** a document of 1_000, 100_000 and 10_000_000 cells, of which
     the view shows one. One write to the shown cell in each frame. The frame
     stays flat.
   - **Code units:** a burst of 10, 100 and 1_000 calls of `run_on_editor_task!`
     with an empty body.
   - **The door of MCP:** 1, 10 and 100 tool calls in flight, each a tool with
     an empty body, through `render_mcp_tools`.
   - Run `test_kernel()` and `test_mcp_tools()`. Commit.
4. [ ] **The feeds and the stores.** `test_feed_frame_guards()` in
   `test/platform/editor/` and `test_formula_frame_guards()` in
   `test/domain/formula/`, on the `HeadlessBackend` with a view of a fixed size
   or no view:
   - **Message log:** a burst of 10, 100 and 1_000 lines while the log view
     shows.
   - **Background work log:** 1, 10 and 100 records with the view open; the
     frame of the flush.
   - **Tasks:** 10, 100 and 1_000 entries in the task feed, one of which changes
     before each flush.
   - **File change:** 10, 100 and 1_000 watched files in one folder, and one
     file that changes. Also a burst of 1, 10 and 100 changed sub-folders.
   - **Terminal:** a burst of 1 kB, 100 kB and 10 MB of output.
   - **Agent events:** a burst of 10, 100 and 1_000 events of an external agent
     into an `AgentEventFeed`, with no view.
   - **Frame statistics:** the view open after 1_000, 10_000 and 100_000 frames
     since the start; the frame of the flush.
   - **Formulas:** 10, 100 and 1_000 formulas that depend on one input; a change
     of the input. The view shows only the input.
   - Run `test_platform()` and `test_formula()`. Commit.
5. [ ] **The documents in the window.** `test_window_frame_guards()` in
   `test/projectured/performance/`, in `ProjecturedTest`, on an `SdlBackend` with
   `SDL_VIDEODRIVER=offscreen`. The window is the application window, built as
   the application tests build it (`make_application_document`,
   `make_application_projection`, `build_editor`). Each document has six
   inputs: an idle frame, a key that inserts a character, a caret move by one
   line, a wheel step, a click on a line, and a pointer move over the document.
   - a Julia file of 1_000, 10_000 and 100_000 lines;
   - a JSON file with an array of 1_000, 10_000 and 100_000 objects;
   - a Markdown file of 100, 1_000 and 10_000 paragraphs;
   - a data frame of 10_000, 1_000_000 and 10_000_000 rows, with a virtual
     column as `DataFrameViewTest` makes it. Also the edit of a cell, and a sort
     by a column: each frame while the sort runs stays flat;
   - the Explorer on a folder of 1_000, 100_000 and 10_000_000 lazy entries, as
     `ExplorerTest` makes them. Also the expand of a folder and a letter in the
     filter;
   - a chart of 10_000, 1_000_000 and 10_000_000 samples;
   - the window with 10, 100 and 1_000 open tabs, and a switch to the next tab;
   - the assistant transcript of 10, 100 and 1_000 turns while a `ScriptedLlm`
     streams an answer. A second guard measures the frame of a delta when the
     answer holds 1_000, 10_000 and 100_000 characters;
   - the MCP log view with 5, 50 and 500 calls, and one new call.

   Run the new suite and `test_application()`. Commit.
6. [ ] **The paint.** `test_sdl_paint_frame_guards()` in
   `test/backend/sdl/backend/`, in `ProjecturedSDLTest`, with the offscreen
   renderer:
   - an idle frame of a canvas with a layout and 1_000, 100_000 and 10_000_000
     rows, as a `CellVector` and as a `ListNode` list;
   - an idle frame of a canvas with no layout and 100, 1_000 and 10_000
     graphics;
   - one moving dot beside 1_000, 10_000 and 100_000 texts;
   - a frame that adds one new text when the texture cache holds 1_000, 4_000
     and 16_000 textures;
   - the first frame after the records pass the slack, with 1_000, 10_000 and
     100_000 records;
   - a code unit in each frame, beside a document of 1_000, 10_000 and 100_000
     lines: the setup of the held frames stays flat.

   Run `test_sdl()`. Commit.
7. [ ] **The budget of the whole window.** `test_frame_budget()` in
   `test/projectured/performance/`, outside `test_all()`. The application window
   on SDL holds the Explorer on this repository, a Julia file of 100_000 lines,
   a data frame of 1_000_000 rows, an assistant transcript of 100 turns, and the
   default views of the logs and the frame statistics. Each scene runs 60 frames
   to warm up and 600 measured frames:
   - idle, with the deadlines of the feeds;
   - typing at 10 keys each second in the Julia file;
   - a scroll of the data frame with the wheel;
   - a `ScriptedLlm` that streams a long answer;
   - an MCP client that calls a tool every 50 ms;
   - a burst of 1_000 lines in the message log;
   - 100 changed sub-folders.

   For each scene, assert the budget of D1. Assert also that the live heap after
   a full collection at the end of the scene is at most 10 MB larger than at its
   start. Write the frames of each scene as CSV. Run the suite in the lane and
   write its table in [As built](#as-built). Commit.
8. [ ] **The guides.**
   - [testing-guide.md](../../documentation/guide/testing-guide.md): a section
     "Frame guards: does a part keep the frame short at any size?". It gives the
     rule, how to write a scene, the bounds, how to read a failure, and when to
     run the budget suite.
   - [performance.md](../../documentation/package/kernel/performance.md) and
     [editor.md](../../documentation/package/kernel/editor.md): the names of the
     record and `run_measured_frame!`.
   - [statistics.md](../../documentation/package/platform/statistics/statistics.md):
     the new rows of the view.
   - In [As built](#as-built), one table of all guards: the part, the sizes, the
     ratios on `main`, and pass or broken with its cause. The owner chooses the
     fixes that get a plan.
   - Move this plan to `plan/done/`. Commit.

## Not in this plan

- The fix of each part whose guard fails.
- The walk of the SDL backend, in [a-frame-walks-only-what-changed.md](a-frame-walks-only-what-changed.md).
- The read of the clipboard in a paste, in [a-paste-never-holds-the-window.md](a-paste-never-holds-the-window.md).
- The run time of the body of a tool and of the code of a person. A code unit
  runs it with held frames, as [the-editor-always-answers-the-person.md](../done/the-editor-always-answers-the-person.md)
  decided.
- The domains that step 5 does not name, for example SQL, pivot, FSM and graph.
- The start time of the application and the precompile.

## Wait on long jobs

- While a build, a test run, a sweep, a CI script or a subagent runs, wait with one foreground `until` loop that checks every 15 s, with a timeout of up to 600000 ms, and repeat only that loop until the job ends.
- Do not end a turn to wait. Do not run filler commands such as `echo ok`. Do not print "Waiting" or any status line while a job runs. Report once, when the job has ended.
- Put this rule verbatim into the prompt of every subagent that may wait on a job.

## As built

### Step 1

- **The record.** `_FrameStages` keeps the sum of each stage beside the slowest
  stage, and the counters of the process at the start of the frame: the
  allocated bytes (`Base.gc_bytes()`), the time of the garbage collector
  (`Base.gc_time_ns()`), the compile time and the running time of the task.
  `record_frame_performance!` records the names of the table in every build.
- **Decision: a retry of a part that failed counts as print.**
  `_retry_marked_barriers!` prints again each part that a barrier marked, and it
  has no bound. It now runs in `_time_frame_stage(..., :print, ...)`, so its time
  is in `:print_time` and not in no stage.
- **Decision: each frame turns the compile timer on and off.**
  `run_measured_frame!` calls `Base.cumulative_compile_timing(true)` at its start
  and `false` in a `finally`. A probe on Julia 1.13.1: the switch counts nested
  calls (on, on, off still measures; a second off stops), and one on and off
  costs 9 ns. So a frame that a test runs outside the loop measures its compile
  time too, and a frame inside another measurement turns off only its own switch.
- **Decision: the guides of the record change in step 1.** `editor.md` lists the
  names of the record and shows `run_measured_frame!` in the sketch of the loop;
  `performance.md` says that the editor records its stages with no macro. Step 8
  adds only the guide of the guards.
- **A counter whose name the record has already** keeps the value of the record,
  because `record_frame_measurements!` keeps the last value of a name that comes
  twice in one group.
- **Tests.** `test_editor_frame_performance()` 33 pass, `test_editor_held_frames()`
  56 pass, `test_editor_frame_drain()` 30 pass, `test_kernel()` 4906 pass; no
  failure, no broken test.
