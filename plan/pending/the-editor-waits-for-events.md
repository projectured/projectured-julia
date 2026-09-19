# The editor waits for events

> **Kind:** plan · **Status:** pending · **Written:** 2026-09-19
> **Stands on:** [architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
> [editor.md](../../documentation/package/kernel/editor.md),
> [devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md),
> [the-editor-survives-a-fault.md](../done/the-editor-survives-a-fault.md) (landed)

Remove the busy loop from the editor. The editor must sleep until an event
arrives, from the backend or from any other producer. A generic feed
mechanism moves data from producers into normal documents, once per frame, on
the editor task. A producer wakes the editor; the editor never polls for work.

## 1. What the editor does today

`run_editor!` runs a frame and then calls `sleep(0.01)`
([EditorModule.jl:640](../../source/kernel/editor/EditorModule.jl#L640)). That
is 100 wakeups, 100 clock writes and 100 paints per second on an idle editor.
The `sleep` also has a second job: it is the only point where cooperative
tasks on the same thread run — the MCP server
([Mcp.jl:74](../../source/mcp/Mcp.jl#L74)), the assistant task, and any
driver.

Input is a poll too. `read!` calls `read_from_devices`, and the SDL method
calls `SDL_PollEvent` and answers `nothing` when the queue is empty
([Sdl.jl:2613](../../source/sdl/Sdl.jl#L2613)).

Data enters a running editor today in four ways, and three of them are wrong:

| way in | who uses it | problem |
| --- | --- | --- |
| the inbox (`post_operation!`) | the omnet watch | none — this is the model |
| a direct write to `editor.document` | the MCP handler, the assistant | races the frame; the fault plan section 9 records it |
| a direct write to a log document from the logging task | `MessageLogLogger` ([MessageLogCapture.jl:38](../../source/log/MessageLogCapture.jl#L38)) | races the frame |
| a store drained once per frame | the fault store (`report_frame_faults!`, [EditorModule.jl:559](../../source/kernel/editor/EditorModule.jl#L559)) | none — but it is a one-off, not a mechanism |

The fourth way is the right one, and this plan makes it the mechanism.

## 2. The design

### 2.1 The feed

A feed is one registered inflow of the editor. Every feed has the same
three stations:

```
producer (any task) ──writes──► store ──drain step──► target document ──projection──► screen
        └────────────── wake ──────────────► the editor's wait
```

- **The producer** runs on any task. It writes the store and never blocks.
- **The store** is a plain object, not a document. Its shape encodes the
  policy: a queue keeps every item, a slot keeps the newest, a fold keeps an
  aggregate. A store write never writes a cell, so it is legal inside a thunk
  (the carve-out of the fault plan, section 3.2, generalised).
- **The drain step** runs on the editor task, once per frame, before `read!`.
  It moves what is new from the store into the target document. It writes only
  what is new: an empty store writes no cell and repaints nothing.

The target is a normal document. The embedder mounts it in the shown tree,
gives it a projection, and registers the feed — all before `run_editor!`. A
person opens views on it with the normal document machinery. The kernel never
learns what a fault, a log line, a shadow tree or a statistic is.

### 2.2 The use cases

| use case | producer | store shape | target document | wakes? |
| --- | --- | --- | --- | --- |
| operations (the inbox) | `post_operation!` callers | queue, ordered, backpressure | the edited document | yes |
| faults | the barriers of the fault plan | coalesces by fault key | the fault log | yes |
| log messages | any task that logs | ring buffer | the `MessageLog` | yes |
| omnet shadow trees | the watch task | one slot, newest wins | the shadow document | yes |
| frame statistics | the editor loop itself | fold: min/max/mean/stddev | the statistics document | no — deadline |

The statistics feed must not wake. Its data comes from frames, so a wake
would make frames feed themselves: paint, new sample, wake, paint. It folds
every frame into its store and flushes on a deadline.

### 2.3 The wait and the wake

The frame loop becomes: wait, drain everything, run the frame, compute the
next timeout, wait again. The backend owns the wait, because the SDL event
queue is a C-side queue that cannot notify a Julia condition. A wake from
Julia is injected into the same queue as a user event. The queue is the one
meeting point of OS input and producer wakes.

```
OS input (keys, mouse, window) ──────────┐
                                         ▼
wake_editor! ── push a user event ──► SDL event queue ◄── the editor blocks here,
  (post_operation!, a store's           │                  with the deadline as timeout
   wake callback, MCP, assistant)       ▼
                                  one frame runs:
                                  drains → read → evaluate → print
```

### 2.4 The lost-wakeup rule

This rule carries the correctness of the design. A wake can arrive while the
editor is in the middle of a frame. The frame's `read!` can consume the SDL
user event, and the next wait would then sleep on work that is already
waiting.

The answer is a flag, and the flag is the truth:

1. `wake_editor!` sets an atomic `wake_pending` flag on the editor. Only the
   false-to-true transition calls `wake_backend!`, so the queue holds at most
   one user event per wait.
2. Before each wait, the loop clears the flag with an atomic exchange. If the
   flag was set, the loop skips the wait and runs the next frame at once.
3. The backend's user event is only the kick that ends a wait in progress. A
   consumed kick costs nothing, because the flag decides.

The worst case is one spurious frame per wake, and a spurious frame drains
nothing, changes nothing and repaints nothing.

The flag starts set. The first frame therefore runs before the first wait,
and an editor nothing has happened to still paints once.

### 2.5 The deadline

A wait without a bound freezes three timed things. Each contributes a
deadline, and the timeout is the minimum:

1. **Animation.** While anything subscribes to the editor's clock, the
   timeout is at most `FRAME_INTERVAL` (0.01 s, today's cadence). The query is
   `has_dependents` on the clock's time cell — the `dependents` vector exists
   ([ReactiveCell.jl:57](../../source/kernel/cell/ReactiveCell.jl#L57)); the
   query only needs to check it for a live `WeakRef`. No subscriber means no
   tick and no paint.
2. **Feed deadlines.** `compute_wake_deadline(feed)` answers at most how
   many seconds the editor may sleep, or `nothing` for "forever". The
   statistics feed answers its flush interval while it holds an unflushed
   sample. Every other feed answers `nothing`.
3. **The held motion sample.** The SDL backend holds a rate-limited hover
   sample in `pending_motion`
   ([Sdl.jl:2638](../../source/sdl/Sdl.jl#L2638)). Its own wait method caps
   the timeout at the remainder of `_HOVER_MOTION_INTERVAL` while it holds
   one, so the last sample of a pointer that stopped is not delayed.

### 2.6 What a feed is not

The inbox stays. `post_operation!` keeps its signature, its ordering and its
backpressure, and becomes the built-in queue-shaped feed. The rule for
choosing between the two doors:

| the payload is | use |
| --- | --- |
| an edit that must apply once, in order, with backpressure | `post_operation!` |
| state or an aggregate, where only the newest or the sum matters, from a producer that must never block | a store plus a feed |

Input is neither. It stays on the `read!` path: the wait ends, and the frame
polls, recognises gestures and runs the projection reader as today.

## 3. The new code

### 3.1 The `Feed` seam — editor layer, new module `source/kernel/editor/FeedModule.jl`

```julia
abstract type Feed end

drain_changes!(feed::Feed, editor) -> Int
# Move everything new from the feed's store into its target document.
# Runs on the editor task, once per frame, before read!. Answers how many
# items moved. Must write only what is new. No default — a feed that
# cannot drain is a bug, not a no-op.

compute_wake_deadline(feed::Feed, editor) -> Float64 or nothing
# At most this many seconds until this feed needs a frame, or nothing for
# "no bound". The editor is passed because the data may live on it, as the
# frame sample store does. Default: nothing.

attach_wake_callback!(feed::Feed, wake) -> Nothing
# Hand the feed the editor's wake function, once, at registration. The
# feed passes it to its producer-side store. Default: nothing — a feed
# whose producers never wake (statistics) declines it.
```

The contract is its own module, `FeedModule`, not a fragment of
`EditorModule`: the editor layer holds one module per concept
(`EditorModule`, `PlaybackModule`), and the contract names no editor.
`FeedModule.jl` loads before `EditorModule.jl` in
[EditorLayer.jl](../../source/kernel/editor/EditorLayer.jl), so `Editor` can
hold `Vector{Feed}`.

Naming: `Feed` names the role — what feeds the editor — and it is standard
data vocabulary, so `MessageLogFeed`, `FrameStatisticsFeed` and
`editor.feeds` read as English. The verb for the emptying motion stays
drain, the word the code already has: `drain_changes!` joins
`drain_operations!` and `drain_faults!`, and the landed fault names do not
change. `FaultSink` was rejected as a metaphor in the fault plan; a data
feed is literal technical English and clears that bar.
`compute_wake_deadline` puts the produced kind last; the subject comes from
dispatch.

### 3.2 The editor side — `EditorModule.jl` (not sealed)

```julia
mutable struct Editor
    ...existing fields...
    feeds::Vector{Feed}
    wake_pending::Threads.Atomic{Bool}
end

Editor(backend, document, projection, devices;
       clock = Clock(), tools = ToolSet(), feeds = Vector{Feed}())
# Prepends the built-in InboxFeed, then calls
# attach_wake_callback!(feed, () -> wake_editor!(editor)) on every feed.
# The feed list is fixed at construction; there is no add_feed!.

wake_editor!(editor) -> Nothing
# Thread-safe, non-blocking, coalescing (section 2.4). post_operation!
# calls it after put!.

struct InboxFeed <: Feed end
drain_changes!(::InboxFeed, editor) = drain_operations!(editor)
```

The loop in `run_editor!` becomes:

```julia
while true
    timeout = Threads.atomic_xchg!(editor.wake_pending, false) ? 0.0 :
              compute_wait_timeout(editor)
    timeout > 0 && wait_for_input(editor.backend, editor.devices, timeout)
    with_performance_counters() do
        set_clock_time!(editor.clock, Base.time() - t_start)
        _run_barrier(editor, :evaluate) do
            for feed in editor.feeds          # the inbox first
                drain_changes!(feed, editor)
            end
        end
        run_frame!(editor)
        _run_barrier(editor, :report) do
            perf!(editor)
        end
    end
end
```

The fault barriers of the landed loop stay where they are; the feed loop
replaces the bare `drain_operations!` call inside the `:evaluate` barrier.

`compute_wait_timeout(editor)` is a private helper: the minimum of
`FRAME_INTERVAL` (when the clock has dependents) and every feed's
`compute_wake_deadline`, else `Inf`.

Feeds run in the live loop only. `run_frame!` and `PlaybackModule` do not
change: a harness that drives frames directly gets no feeds, by design — a
scripted timeline must not apply foreign posts. `report_frame_faults!` is the
deliberate opposite ([EditorModule.jl:552-560](../../source/kernel/editor/EditorModule.jl#L552)):
faults are the frame's own product, so the frame reports them, and this plan
does not move that call.

### 3.3 The backend seams — `BackendInterface.jl`, `BackendDefaults.jl`, `BackendModule.jl` (sealed)

```julia
wait_for_input(backend, devices, timeout_seconds) -> Nothing
# Block until input arrives, wake_backend! is called, or the timeout
# passes. Inf is legal; a backend may slice a long wait internally.
# Default: sleep(min(timeout_seconds, 0.01)) — the cadence the loop has
# today, so a backend that answers nothing behaves as before.

wake_backend!(backend) -> Nothing
# End a wait_for_input in progress, from any task or thread.
# Default: nothing — correct against the sleeping default wait.
```

The three files are sealed. The user gave permission to unseal them for this
change on 2026-09-19. Show the exact diff and get acceptance before the edit,
and record the edit for re-audit in `SEALING.md`'s protocol.

### 3.4 The SDL implementation — `Sdl.jl` (not sealed)

1. Register one SDL user event type at `initialize_backend!`
   (`SDL_RegisterEvents(1)`); keep the id on the backend struct.
2. `wake_backend!` pushes that event with `SDL_PushEvent`, which is
   thread-safe by SDL's contract.
3. `wait_for_input` loops `SDL_WaitEventTimeout` slices and re-queues what it
   pops, or peeks with `SDL_PeepEvents`; the simplest correct form waits, and
   leaves all reading to `read!`. Cap the timeout at the hover remainder while
   `pending_motion` or `pending_input` is held (section 2.5).
4. `_poll_window_input` skips the wake event type, as it skips other unknown
   events.
5. **Slicing policy:** with `Threads.nthreads() == 1`, slice the wait at
   10 ms and `yield()` between slices, so the MCP server and the assistant
   task run exactly as often as they do today. With more threads, block for
   the full timeout and mark the `ccall` GC-safe (`gc_safe = true`), so a
   collection on another thread does not hang behind the wait. Check that the
   workspace Julia accepts the `gc_safe` option; if it does not, slice at
   50 ms regardless of thread count.

### 3.5 The console implementation — `Console.jl` (not sealed)

One persistent reader task blocks on the TTY through libuv, appends to
`inbuf`, and notifies a `Threads.Condition` on the backend. `wait_for_input`
waits on that condition with a `Timer` that notifies it at the timeout.
`wake_backend!` notifies it directly. Everything is cooperative; no OS block.

### 3.6 The cell helper — `ReactiveCell.jl`, `CellModule.jl` (not sealed)

```julia
has_dependents(cell) -> Bool   # true when any WeakRef in dependents is live
```

A stale `WeakRef` that the sweep has not removed yet can answer a false
`true`. The cost is a few timed frames after the last animation dies, and
each of them repaints nothing.

## 4. How each use case lands

### 4.1 Faults — landed; only the wake is missing

The fault plan is done and merged: the kernel `fault` layer exists, `Editor`
holds `faults` and `fault_policy`, and `report_frame_faults!` drains the
store at the top of every frame — inside `run_frame!`, so a hand-driven frame
collects its faults too. This plan does not move any of it, and faults do
**not** become a registered feed.

One piece is missing. A fault recorded in frame N is reported at the start of
frame N+1, and a blocking editor runs frame N+1 only on a wake. So:

1. `FaultStore` gains a wake slot, in the same shape as
   `attach_fault_target!` (`FaultStore.jl` is not sealed). `record_fault!`
   calls it on a new key. A count bump on a known key does not wake; the next
   frame shows the new count.
2. The `Editor` constructor attaches its own wake to its own store.
3. The wake-pending flag makes a wake from inside a frame safe: the loop
   skips the next wait, and the report at the top of the next frame drains
   the store at once.

### 4.2 Log messages — retrofit `source/log`

`MessageLogLogger` writes the `MessageLog` document from the logging task
today. Change it to write a ring-buffer store and wake. A `MessageLogFeed`
in `ProjecturedLog` appends the buffered rows to the `MessageLog` document.
The logger keeps forwarding to the terminal unchanged. This closes the race,
and it also makes the editor's own `@info "[operation] …"` line safe wherever
it runs.

### 4.3 Omnet shadow trees — no change here

The watch posts operations and now gets an immediate wake for free through
`post_operation!`. A slot-shaped feed for still images is omnet-julia's own
later choice, in its own plan.

### 4.4 Frame statistics — the deadline path's first user

The producer is the loop itself: after `run_frame!`, fold this frame's
performance counters (`:reads`, `:computes`, `:invalidations`, `:writes`,
`:read_time`, `:evaluate_time`, `:print_time`) into a per-editor sample store
(Welford fold for mean and standard deviation, plus min and max). The fold is
plain arithmetic on a plain object; it costs no cell.

The feed flushes the aggregate into a statistics document at
`compute_wake_deadline` = 0.25 s while unflushed samples exist — and only
while a view subscribes to the document. The probe is `has_dependents` on
the document's `frame_count` cell, which every view reads. So a watched
table refreshes four times a second, and an unwatched editor folds for free
and never flushes: without the probe, the flush would fold a new sample of
its own frame and the loop would feed itself forever. The store and the
fold live in the editor layer. The document, its projection and the feed
live in a new substrate package, `ProjecturedStatistics`
(`source/statistics/`), which mirrors the shape of `ProjecturedLog`.

### 4.5 MCP and the assistant — the minimal fix now

Both write `editor.document` directly. With a blocking editor their writes
would not paint until an unrelated wake. Add `wake_editor!` after their
writes now. Routing them through `post_operation!` remains its own plan, as
the fault plan section 9 already records.

## 5. The phases

### Phase 1 — The feed seam and the inbox feed ✅ (2026-09-19)

1. ✅ Write `source/kernel/editor/FeedModule.jl`: `Feed`, `drain_changes!`,
   `compute_wake_deadline`, `attach_wake_callback!`. `InboxFeed` lives in
   `EditorModule`, beside the inbox it wraps.
2. ✅ Add the include to `EditorLayer.jl`, before `EditorModule.jl`, and the
   inventory row to `SEALING.md`.
3. ✅ Add `feeds` and `wake_pending` to `Editor`; add the `feeds` keyword;
   prepend `InboxFeed`; attach the wake callbacks at construction.
4. ✅ Add `wake_editor!`; call it from `post_operation!`. The loop clears
   `wake_pending` at the top of each frame: the frame takes ownership of
   every wake posted before it.
5. ✅ Add `drain_feeds!` and run it each frame in `run_editor!`, in place of
   the bare `drain_operations!` call, inside the `:evaluate` barrier. The
   `sleep(0.01)` stays in this phase.
6. ✅ Tests (`test_editor_feeds`, 16 assertions): registration order, drains
   on the editor task, totals, callback attachment, wake on post, wake
   coalescing, the default deadline. The inbox, frame-drain and layering
   suites stay green.

### Phase 2 — The wait seam and the loop rewrite ✅ (2026-09-19)

1. ✅ The user accepted the diff for `BackendInterface.jl`,
   `BackendDefaults.jl` and `BackendModule.jl` (shown in full on
   2026-09-19); applied exactly as shown. The three files stay `🔒` and
   await re-audit.
2. ✅ Add `has_dependents` to `ReactiveCell.jl`; export from `CellModule.jl`;
   testset in the cell suite covers the edge cases, a swept `WeakRef`
   included.
3. ✅ Replace the `sleep` with the wait. The ownership exchange runs **after**
   the wait, not before it: the loop skips the wait when the flag is set,
   waits otherwise, and then takes the flag — so a wake during a frame costs
   at most one spurious frame, and a wake between the timeout computation
   and the block is covered by the backend kick (an autoreset or queued kick
   survives until the wait looks). Add `FRAME_INTERVAL` and
   `compute_wait_timeout`.
4. ✅ Tests (`test_editor_wait`, 12 assertions), with `ProbeWaitBackend` in
   the test package (`PAR-NO-TEST-DOUBLES-IN-MAIN`): the idle timeout is
   `Inf`; the nearest feed deadline bounds it; a clock subscriber bounds it
   to `FRAME_INTERVAL`; only the false-to-true transition kicks the backend;
   a posted operation ends an unbounded wait and quit ends the loop; the
   default wait is one poll slice. The kernel suite's editor, cell, quit and
   layering suites stay green; the suite's only failures reproduce on
   unmodified `main` (document macro, reference layout, tool scratch) and
   predate this branch.

### Phase 3 — The SDL wait ✅ (2026-09-19, manual check open)

1. ✅ `initialize_backend!` registers one user event per SDL life
   (`wake_event_type` on the backend; zero when the pool refuses, and the
   sliced wait then covers the loss). `wake_backend!` pushes it through
   `SDL_PushEvent` — SDL's documented thread-safe entry — by writing the
   type into a zeroed `SDL_Event` blob.
2. ✅ `wait_for_input` blocks in `SDL_WaitEventTimeout` with a NULL event
   pointer — SDL's look-only form, so everything stays queued for `read!`.
   An owed `pending_input` skips the wait; a held `pending_motion` caps the
   timeout at the rest of the hover interval.
3. ✅ `_poll_window_input` needed no change: an unmatched event type falls
   through its dispatch and is skipped, the wake event included.
4. ✅ `gc_safe` exists on this Julia (1.13.0) and is prefix syntax:
   `@ccall gc_safe=true lib.f(…)::T`. Every slice blocks GC-safe. The slice
   is 10 ms single-threaded (today's cadence, and the only moment
   cooperative tasks on the thread run) and 100 ms multi-threaded — bounded
   because `@async` tasks (the MCP server) stick to the spawning thread
   until the plan that moves them; a slice of `Inf` waits for that plan.
5. ✅ Tests (`test_sdl_wait_wake`, 9 assertions, real SDL queue): the wake
   registration, the timeout, a cross-task wake ending a long wait, the
   look-only property, the owed-event skip. Timing bounds are one-sided and
   generous.
6. ✅ Measured (2026-09-20, real SDL window, same machine and script both
   sides): idle CPU fraction over 5 s is **0.006 on `main`** (one hundred
   wakeups a second) and **0.000 on this branch** (below one clock tick); a
   posted operation lands with no input and quit ends the loop cleanly on
   both. What stays manual: typing, animation and an omnet sync inside the
   full application.

### Phase 4 — The console wait ✅ (2026-09-19)

1. ✅ A watcher task blocks on the TTY (`Base.wait_readnb`), notifies an
   autoreset `Base.Event` gate, and holds until the editor consumed the
   bytes. The gate stores a notification that arrives before the wait, so
   no wake is lost. A `Timer` notifying the same gate bounds the wait.
   `wake_backend!` notifies the gate directly. An input without a watcher —
   an `IOBuffer` in tests — degrades to the default poll slice.
2. ✅ Tests inside `test_console_backend` (43 assertions total): buffered
   bytes skip the wait, a stored wake is not lost, a cross-task wake ends a
   long wait, the timeout fires, quit still works through Ctrl-C parsing.

### Phase 4 — The console wait ⬜

1. Add the reader task, the condition and the timer wait per section 3.5.
2. Test: a keystroke ends the wait; a wake ends the wait; Ctrl-C still
   quits.

### Phase 5 — Producers wake ✅ (2026-09-19)

1. ✅ The MCP wire handler wakes after every tool call (`Mcp.jl`), fault
   included, so what a client changed — or broke — paints at once. The
   assistant wakes per streamed LLM event (the `on_event` closure in
   `_run_agent_loop!`) and once more at turn end, so the stream paints as
   it arrives; without the per-event wake a blocking editor would freeze
   the chat until the turn ends.
2. ✅ The omnet watch wakes through `post_operation!` with no change on its
   side.

### Phase 6 — The message log becomes a feed ✅ (2026-09-20)

1. ✅ `MessageLogStore` (ring, lock, wake, dropped counter) is the producer
   side; `MessageLogLogger` records into the store, never the document, and
   its wake fires per line. The drain reports dropped lines as one warning
   line in the log.
2. ✅ `MessageLogFeed` in `ProjecturedLog`, with the session store beside
   the session log. The `feeds` keyword now flows through the bootstrap
   `run_editor!` and `run_window_editor`, and the application registers
   `MessageLogFeed()` beside its capture install.
3. ✅ Tests (`test_message_log_feed`, 11 assertions): a captured line stays
   out of the document until the drain and wakes the editor; a foreign-task
   line the same; the bound drops oldest and the drain says so. One trap
   recorded: the transparent wrapper defers filtering to the logger it
   wraps, so a test must wrap one that accepts Info.

### Phase 7 — The fault wake ✅ (2026-09-19)

1. ✅ `attach_fault_wake!(store, wake)` mirrors `attach_fault_target!`; the
   `Editor` constructor attaches its own wake. `record_fault!` wakes at the
   queue moment — a new key, or a count that grew a bucket — never on a
   plain count bump, and the wake is swallowed if it throws
   (`PAR-REPORT-NEVER-THROWS`).
2. ✅ Tests: the store suite covers wake-on-queue, silence on a bump, and a
   throwing wake (25 assertions); the feed suite asserts a fault recorded
   on `editor.faults` sets `wake_pending`.

### Phase 8 — The frame statistics feed ✅ (2026-09-20)

1. ✅ `FrameSampleModule` in the editor layer: `MeasurementSummary` (count,
   minimum, maximum, mean, total, Welford deviation) and `FrameSampleStore`.
   `Editor` always holds one, and the loop folds the frame time — plus the
   performance counters when they are compiled in — at the end of every
   frame (`record_frame_measurements!`).
2. ✅ `package/ProjecturedStatistics/` and `source/statistics/`, mirroring
   `ProjecturedLog`: `FrameStatistics`/`FrameMeasurement` (session
   singleton, tab alias `statistics`), `FrameStatisticsFeed`,
   `FrameStatisticsToSyntax`. Registered in the `Projectured` umbrella,
   `environment/all` and the application's feed list.
3. ✅ Tests: the kernel fold against a reference computation
   (`test_frame_samples`, 16); the feed's watched/unwatched behaviour and
   in-place row update (`test_frame_statistics_feed`, 14). The export
   collision and package graph guards stay at their `main` baseline.
4. Two changes this phase forced on the phases before it, both recorded
   above: `compute_wake_deadline` gained the `editor` argument, and the
   wake-pending flag starts set so the first frame paints before the first
   wait.

### Phase 9 — Documentation ✅ (2026-09-20)

1. ✅ [editor.md](../../documentation/package/kernel/editor.md) shows the
   waiting loop and gains "The feeds" (the contract, the wake, the concrete
   feed table);
   [devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md)
   gains the two seams and the SDL and console wait bullets.
2. ✅ **Not generalised, and the plan was wrong to ask for it.** Only the
   fault store is written from inside thunks, and only its keyed idempotent
   write qualifies for the carve-out. The other feed stores are written by
   ordinary tasks, outside every thunk, so the ban is not in play for them.
   `PAR-NO-WRITE-IN-THUNK` now says exactly that; `PAR-PURE-THUNK` stands
   unchanged.
3. ✅ `PAR-STORE-THEN-DRAIN` is written, after `PAR-NO-WRITE-IN-THUNK`. The
   exact text awaits the user's review.

## 6. The footprint on the code that exists

| file | change | sealed |
| --- | --- | --- |
| `source/kernel/editor/FeedModule.jl` | new | no |
| `source/kernel/editor/EditorLayer.jl` | one include | no |
| `source/kernel/editor/EditorModule.jl` | two fields, the loop rewrite, `wake_editor!` | no |
| `source/kernel/backend/BackendInterface.jl` | two declarations | **yes — permission given 2026-09-19** |
| `source/kernel/backend/BackendDefaults.jl` | two defaults | **yes — permission given 2026-09-19** |
| `source/kernel/backend/BackendModule.jl` | two exports | **yes — permission given 2026-09-19** |
| `source/kernel/cell/ReactiveCell.jl`, `CellModule.jl` | `has_dependents` | no |
| `source/sdl/Sdl.jl` | the wait, the wake event | no |
| `source/console/Console.jl` | the reader task, the wait | no |
| `source/mcp/Mcp.jl`, `source/assistant/AssistantTurn.jl` | one wake call each | no |
| `source/log/MessageLogCapture.jl` + `ProjecturedLog` | the store, the feed | no |
| `source/kernel/fault/FaultStore.jl` | the wake slot | no |
| `package/ProjecturedStatistics/`, `source/statistics/` | new | no |

No document type changes. No projection changes. No domain package changes.

## 7. The hazards, and what stops each

| hazard | what stops it |
| --- | --- |
| a wake during a frame is lost, and the editor sleeps on ready work | the atomic flag protocol of section 2.4; the flag is the truth, the SDL event only a kick |
| a producer floods the SDL queue with user events | only the false-to-true transition pushes |
| the wait starves the MCP server on one thread | the 10 ms slice with `yield()` when `Threads.nthreads() == 1` — today's cadence exactly |
| a blocked wait hangs garbage collection on another thread | `gc_safe = true` on the ccall, or the 50 ms slice fallback |
| the statistics feed wakes on its own output and spins | it never wakes; it flushes on a deadline |
| animation freezes while the editor sleeps | the clock-dependents deadline caps the timeout at `FRAME_INTERVAL` |
| the last hover sample is delayed by a long wait | the SDL wait caps its own timeout while it holds a sample |
| a stale clock subscriber keeps timed frames alive | a false `true` from `has_dependents` costs empty repaint-free frames until the sweep |
| a feed that blocks stalls every other feed and the frame | the contract says never block; a test drives a full store and asserts the frame time |
| a fault recorded mid-frame sits undrained while the editor sleeps | `record_fault!` wakes on a new key; the flag skips the next wait |
| a backend without a wait regresses | the default is today's sleep; nothing gets worse |

## 8. The decisions taken, and the ones that are open

**Taken.**

- The type is **`Feed`** — it names the role: what feeds the editor. The
  seam functions are **`drain_changes!`**, **`compute_wake_deadline`** and
  **`attach_wake_callback!`** (section 3.1). The verb for the emptying step
  stays drain, so the landed `drain_operations!` and `drain_faults!` do not
  change. The rejected candidates: `Drain` (names the motion, not the role,
  and reads store-outward), `Feeder`, `Source`, `Intake`.
- The statistics document lives in a new substrate package,
  **`ProjecturedStatistics`**, which mirrors `ProjecturedLog`, and Phase 8
  ships with this plan.
- Faults are **not a registered feed**. `report_frame_faults!` stays inside
  `run_frame!`; the fault store only joins the wake protocol (section 4.1).
- The wake pair is **`wake_editor!`** / **`wake_backend!`**; the wait is
  **`wait_for_input(backend, devices, timeout_seconds)`**, joining
  `read_from_devices` / `write_to_devices`.
- The feed list is **fixed at construction**. Everything is wired
  externally, before `run_editor!`; there is no `add_feed!`.
- Input is **not a feed**; it stays on the `read!` path.
- The inbox is **the built-in queue feed**; `post_operation!` does not
  change for callers.
- The thread policy is **degrade, do not require**: full block on a
  multi-thread run, a 10 ms slice on a single-thread run. Moving the MCP
  server off the editor thread waits for the plan that routes it through the
  inbox.

- The flush interval of the statistics feed is **0.25 s** and
  `FRAME_INTERVAL` is **0.01 s** — today's animation cadence, unchanged.

**Open.**

- The by-hand part of the Phase 3 check: typing, animation and an omnet
  sync inside the full application. The idle CPU and the wake liveness are
  measured (Phase 3, item 6).
- The user's review of the `PAR-STORE-THEN-DRAIN` text, and of the
  `PAR-NO-WRITE-IN-THUNK` paragraph that scopes the carve-out to the fault
  store alone.
