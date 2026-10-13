# The editor always answers the person

> **Status (2026-10-12): PROPOSAL.** The owner asked on 2026-10-12: "The editor
> cannot become unresponsive in any circumstances. [...] If this needs new tasks,
> threads, etc. then we should design it that way. Of course, race conditions,
> dead locks, live locks should be avoided at all costs." Nothing is built.
> **Decided by the owner, 2026-10-13:** the rules a, b, c and d of §5.7, with d
> in its narrow form, and D7. The decisions D1 to D6 wait for the owner, one at a
> time.
>
> This plan takes in three earlier plans: `a-long-evaluation-does-not-hold-the-editor.md`
> (on the branch `plan-evaluation-off-editor`, deferred on 2026-10-09),
> `the-pointer-shows-the-hourglass.md` (deferred on 2026-10-02), and the parts
> POLICY-6-inbox and POLICY-6-time of `kernel-audit-fixes.md` (not decided).

## 1. The conclusion

One task does all the work of an editor today: it reads the window events, runs
every operation, every feed, every tool call and every print, and paints. Julia
does not preempt a task. So any slow piece of work stops the window.

The window can answer in all circumstances only when the thread that talks to
the window system never runs document work. The proposal (D1, option B):

- A **window loop** on thread 1 owns the backend. It does only work with a fixed
  bound: it reads the events of the window system, paints, and presents.
- A **document loop**, one for each editor, owns every cell. It runs all the work
  that touches a document: the feeds, the inbox, the read stage, the operations,
  the tool calls, the print.
- The two loops hand the cells to each other twice in each frame. So one task
  touches the cells at any time, and the cell engine needs no lock.
- When the document loop is late, the window loop shows a **held frame**: the last
  picture, a busy bar that names the work, the hourglass pointer, and a stop
  control. It keeps the input in order for later.
- A **unit** of code (a tool call, an evaluation) runs in a child task on the
  thread of the document loop. A stop ends our own waits at once, and model code
  at its next wait (D6).

## 2. The requirements

A professional tool meets these. The plan meets all of them, except where §7
says that Julia can not.

- **R1 The window answers the window system** at all times: expose, move,
  resize, close, and the ping of the window manager. GNOME marks a window "not
  responding" when the window does not answer its ping for 5 s. SDL answers the
  ping while it pumps events.
- **R2 Feedback within 100 ms of a gesture:** the effect of the gesture, or a
  sign that the editor works.
- **R3 A long piece of work shows what it is,** and the person can stop it.
- **R4 Input is not lost.** Input during a held frame keeps its order.
- **R5 One writer.** At any time, one task writes the documents of an editor
  (PAR-STORE-THEN-DRAIN).
- **R6 No wait without a bound on the window thread.** The window thread takes no
  lock that another thread holds for an unbounded time. No task waits for itself.
- **R7 No starvation.** A service task (network, process reader, MCP, ACP) does
  not share a thread with work that has no bound.
- **R8 A stall is seen.** A frame of the document loop that passes a limit is
  recorded with the name of its work.

## 3. The facts (2026-10-12)

### 3.1 Threads

- Julia 1.13.1 gives these thread pools (measured 2026-10-13, with no
  `JULIA_NUM_THREADS`):

  | Option | Interactive threads | Default threads |
  |---|---|---|
  | none | 1 (the main task) | 1 |
  | `-t 1` | 0 | 1 (the main task) |
  | `-t 2` | 1 (the main task) | 2 |

  With no option, thread 2 runs only the file watchers and the meaning search.
- The thread policy is "degrade, do not require"
  (`plan/done/the-editor-waits-for-events.md:603`). With one thread, the editor
  must work as it does today.
- `bin/projectured` passes no thread option. The application runs `run_editor!`
  on the main task, so the loop, SDL and every `@async` task share thread 1
  (`Application.jl:549`).
- HTTP.jl starts its server with `Threads.@spawn :interactive`, and each
  connection is an `@async` child of it
  (`~/.julia/packages/HTTP/Y97L1/src/Servers.jl:340-363`). So the MCP server and
  the web backend run on thread 1 too.
- `run_editor!(...; wait = false)` pins the loop to a default thread, because SDL
  answers only the thread that started it (`EditorLoop.jl:388-428`). On macOS the
  window system needs the main thread.
- Only three places use a real second thread: the file watchers
  (`FileChangeStore.jl:118,121`), the meaning search (`MeaningSearch.jl:213,296`),
  and HTTP.jl.

### 3.2 Work that holds the window today

- **Every tool call.** `run_on_editor_task!` posts a `RunFunctionOperation`, and
  the drain of the inbox runs it on the loop task (`Inbox.jl:104-127`). The
  native turn (`AgentLoop.jl:96`), the MCP handler (`McpServer.jl:246-280`) and
  through it every ACP agent use this door. No timeout, no stop.
- **The evaluations of a person.** `SubmitJuliaOperation`,
  `ComposerEvaluateOperation` and `EvaluateSelectedFormOperation` run
  `execute_julia_code!` inside the evaluation of an operation.
- **A formula.** `evaluate_formula` runs `Core.eval` inside a cell
  computation, so a print can run code of the person
  (`FormulaDocument.jl:489-507`).
- **The paint reads cells.** `GraphicsCanvas` is a `@document`, and the SDL walk
  reads it in `write_to_devices!` (`SdlBackend.jl:3016-3125`). A cell that the
  print left out of date computes in the paint.
- **Feeds that do I/O in the drain.** The file-change drain reads files
  (`FileChangeStore.jl:189`), and the task feed reads `/proc`.
- **The MCP start** waits up to 10 s on the loop task (`McpServer.jl:119-122`).
- **Starvation.** The assistant turn (`AssistantTurn.jl:287`), the ACP tasks, the
  MCP server loop, the terminal and task readers and the process debugger are
  `@async` tasks on thread 1. They run only when the loop waits.

The guides state the limit: "a tool that runs for a second keeps the window from
drawing for a second" (`editor.md:228-229`, `mcp.md:89,110`,
`assistant.md:224,229`).

### 3.3 What exists and helps

- The SDL backend keeps the last picture of each window in the texture
  `res.target` (`SdlBackend.jl:144`). A copy of it to the window and a present
  read no cell.
- `wake_backend!` of SDL is `SDL_PushEvent`, which is safe from any thread.
- The flag `wake_pending` is atomic, and a wake from any task is safe
  (`Inbox.jl:43-47`).
- A tool handler can answer a `Task`, and the turn waits for it on its own task
  (`agent.md:531-539`).
- `ToolScratch` code finds its editor through a `ScopedValue`, which a task
  that the code starts inherits (`CodeExecution.jl:397`).
- The owner decided L18-10 C: in the code tool, an interrupt is the answer of the
  call (`kernel-audit-fixes.md:1572-1581`).
- The owner prefers a live window to a pause: "what are we trying to solve here
  with pause? Because it takes away the usefulness of the UI a lot"
  (`view-and-edit-a-data-frame.md:548-554`).

### 3.4 What constrains the design

- **PAR-STORE-THEN-DRAIN** (`architecture-invariants.md:260-275`): only the
  editor task writes a document that a running editor shows.
- **The cell engine has no lock.** A read of a reactive cell can compute and
  store, so a read is a write too.
- **The fault store is sealed** (`FaultStore.jl:28-30` 🔒): "all code that writes
  it must run on the thread of the editor task".
- **The MCP guide promises** that "a change from a client never meets a frame
  half way" (`mcp-guide.md:73`).
- **Flags shared with services are plain fields** today, safe only because one
  thread runs all tasks: `AssistantTurnControl` (`AssistantTurn.jl:98-104`),
  `ExternalAgentSession.is_cancelled`, `TaskGroup.stopping`.
- **ACP posts while it holds a lock.** `receive_notification` calls `on_event`
  under `turns_lock`, and `on_event` posts into the inbox, which blocks when it is
  full (`AcpConnection.jl:452-486`).

## 4. The options (D1)

- **A. Code units off thread 1.** The loop stays on thread 1. A code unit (a tool
  call, an evaluation) runs on thread 2. While it runs, the loop runs held frames
  (§5.3) and touches no cell (§5.7). A fixes the four problems that exist today:
  the window freezes during a code unit, the stop can not act, no hourglass
  shows, and the window does not answer the window system. It does not cover work
  whose length is not known before it starts: a formula in a print, a slow
  operation from a gesture, a slow feed drain. What A needs in addition to §5:
  - The default threads are enough: thread 1 for the loop, thread 2 for the unit.
    With one thread, or in the form `wait = false` that already puts the loop on
    thread 2, the unit runs on the thread of the loop, as today.
  - A small task on thread 2 waits for the unit and for its stop, so that the
    interrupt of D6 comes from the thread of the unit.
  - The unit does not write the fault store, which the sealed rule keeps on the
    thread of the editor task. It hands its faults to the loop, which records
    them after the unit.
  - The services stay on thread 1. They run during a unit, because thread 1 is
    then free. A move of the services off thread 1 needs `-t 2`.
- **B. Two loops, one handoff in each direction per frame.** §5. The window
  thread never touches a cell while the document loop runs. It meets R1 to R8,
  with the limits of §7.
- **C. Two loops and a picture made of plain data.** The document loop makes an
  immutable list of draw commands, and the window loop draws it at any time, as
  the compositor of a browser does. The window could then also scroll during a
  long frame. The SDL backend would split into two halves, which is the largest
  change by far.

**My recommendation: A first, and B only if a slow print, formula or operation
is a real case.** On 2026-10-12 I recommended B. The fact that moved the view:
A and B use the same three parts, which are the held frames, a second thread for
document work, and the handoff of the cells. So A is a step toward B, not a
different road. A fixes the four problems that exist today. B adds the work of
unknown length, at the cost of a split of the SDL backend (4700 lines) and of the
pull of the output. C gives more than B, at a much larger cost.

## 5. The model (option B)

### 5.1 Threads and tasks

- **Thread 1, interactive pool: the window loop.** One for the process, because
  the backend is one for the process. It owns the backend, the windows, the
  retained pictures and the pointer. It runs nothing else of ours.
- **The document loop: one task for each editor,** pinned to a thread of the
  default pool. It is "the editor task" of PAR-STORE-THEN-DRAIN. It owns the
  cells, the IoMap, the fault store, the tool set and the drain of the inbox.
- **Service tasks** start with `Threads.@spawn` in the default pool, never with
  `@async` from either loop. They reach a document only through the inbox, as
  today.
- **The process starts with at least three default threads** (`-t 3,1`): one for
  the document loop and two for services.
- Only HTTP.jl puts tasks into the interactive pool next to the window loop. By
  the contract of that pool, they do short work.

### 5.2 One frame

1. The window loop pumps the events of the window system. It puts each
   `WindowInput` into the input queue of its editor. A newer pointer motion
   replaces an older one in the queue.
2. When the document loop is idle and work is due (input, a wake, a deadline),
   the window loop hands it the cells with the frame time. From that moment the
   window loop reads no cell.
3. The document loop runs the frame: the feeds with the inbox first, the read
   stage from the input queue, the operations, and the print. Then it **pulls the
   output**: it reads each cell that the paint will read, so the paint finds every
   cell computed. It hands the cells back with the output and the time of its
   next deadline, and it waits for the next frame.
4. The window loop paints the output and presents. The document loop waits during
   the paint, so the reads of the paint are safe.
5. When the document loop does not hand back within the hold threshold
   (100 ms), the window loop runs **held frames** until it does.

Each handoff is one message through a `Threads.Condition`. The lock of the
condition is held only for the time to set a field. The handoff also orders the
memory of the two threads, so each side sees the writes of the other.

`run_frame!` stays as it is: the form for one task, which the tests, the playback
and the video recorder use. The video recorder never holds a frame, so its time
stays exact.

### 5.3 A held frame

The window loop, in a held frame:

- copies the retained picture to each window and presents it. After a resize it
  draws the old picture at the top left and fills the rest;
- shows the hourglass pointer (`SDL_SetCursor` on the SDL thread, which is now
  free);
- after 0.5 s, draws a busy bar over the picture with the name of the unit, its
  time, and a stop control;
- keeps every other input in the queue, in order (D2);
- reads the stop gesture (D3) and the close of a window (D4).

The window loop reads the name and the start time of the unit from an atomic
reference that the document loop sets. It reads no cell.

### 5.4 Units and the stop

- **A unit** is a piece of work that the document loop runs: a tool call, a call
  of `run_on_editor_task!`, an evaluation of code. It has a description, a start
  time and a stop flag (`Threads.Atomic{Bool}`).
- **A code unit runs in a child task** that is sticky to the thread of the
  document loop. While the child runs, it owns the cells, and the document loop
  only waits for it. So R5 holds.
- **`run_on_editor_task!` runs at once** when the caller is the owner of the
  cells: the document loop or the child of the unit. A call with `wait = true`
  from a task that the unit started, while the unit runs, throws at once. That
  call would wait for the unit that waits for it.
- **The stop.** The window loop sets the stop flag and notifies the document
  loop. It does not block and does not post.
- **Our own long waits** (a stream of a model, an ACP request, a wait for a task
  group, a verb with `wait = true`) read the stop flag through a scoped value and
  close their connection or process. This route has no race.
- **Model code that waits** (`sleep`, a channel, I/O) can only be stopped by an
  interrupt (D6). The document loop runs on the same thread as the child, so the
  child does not run at that moment. The document loop calls
  `schedule(child, InterruptException(); error = true)`, which takes the child
  out of the queue that it waits in. The code tool turns the interrupt into the
  answer of the call (L18-10 C).
- **Code that computes without a wait** does not let the document loop run, so
  no stop acts until its next wait. If the stop has no effect after 3 s, the busy
  bar says so, and offers to quit (D4).
- **A stall watchdog** on a service thread reads the unit reference. A unit that
  runs longer than 10 s is recorded once, through the next frame of the document
  loop, with its description.

### 5.5 Faults

- Only the document loop and the child of its unit write the fault store. Both
  run on the pinned thread of the document loop, so the sealed rule holds
  without an edit.
- The window loop keeps its own faults (a failed pump, a failed paint) in a list
  of its own under a short lock, and keeps its own counts for `:device_read` and
  `:device_write`. The document loop records the list at the start of its next
  frame.
- When the document loop ends with an exception, the window loop closes the
  windows of that editor and passes the exception on, as `run_editor!` does today.

### 5.6 Deadlocks, races and livelocks

| Hazard | How the model prevents it |
|---|---|
| The window loop waits for the document loop | It never does. It waits only on its event source, with a timeout, and reads the state of the document loop from atomics. |
| A unit waits for work that only the document loop can do | `run_on_editor_task!` runs at once for the owner, and throws at once for a task of the running unit (§5.4). |
| The editor task posts into its own full inbox (L21-5, L22-4) | A second queue with no bound for the owner of the cells (POLICY-6-inbox I3). |
| A late post after the end of the loop (L22-3) | The end closes both queues, and a later post throws (POLICY-6-inbox I5). |
| A lock held across a wait | Rule: no lock is held across a `wait`, a `put!`, a callback or I/O. ACP calls `on_event` after it releases `turns_lock`. |
| Two threads write a cell | The handoff gives the cells to one side at a time. The window loop paints only while the document loop waits. |
| Two threads write the fault store | The window loop never writes it (§5.5). |
| A flag shared with a service | Each such flag becomes atomic, or goes through the inbox. Step 5 lists each one. |
| An MCP resource read on the server task (`McpServer.jl:334-362`) | It goes through `run_on_editor_task!`. |
| A wake storm | Each frame has a bound of work. An animation draws at most 30 frames a second. |
| A part that the person stopped computes again at once | It keeps its fault mark, and the editor tries it again after the next operation, as for any fault. |

### 5.7 Who touches a document during a code unit

**Decided by the owner, 2026-10-13: the rules a, b, c and d below.**

While a code unit runs, it owns every document of its editor. Model code keeps
its API: the fields of a document, the search verbs, the edit verbs and
`evaluate_operation`. Nothing else touches a document:

- The loop on thread 1 runs held frames only. It drains no inbox and no feed, it
  reads input only into the queue, it reports no fault, it does not tick the
  clock, and it prints and paints nothing.
- The cells pass to the unit through one lock at the start, and back through the
  same lock at the end, so each side sees the writes of the other.
- Units are serial. A second call waits in the inbox until the first one ends.

These tasks touch a document outside the door today. They are safe only because
they share thread 1 with the loop:

- a task that model code starts, with `@async` or `Threads.@spawn`, while the
  unit runs or after it ends. The edit verbs apply their operation on the task
  that calls them (`DocumentEdits.jl:82`, `PaneProgram.jl:570`);
- the MCP resource providers (`McpServer.jl:334-362`);
- `on_step` of the process debugger (`process.md:123`).

Step 5 lists each such task, and each one goes through the door. The rules:

- **a.** Every verb that reads or edits a document goes through
  `run_on_editor_task!`: at once for the owner, and a post for any other task.
- **b.** A call with `wait = true` from a task that the running unit started
  throws at once. That task and the unit would otherwise wait for each other.
- **c.** The description of the code tool tells the model that a task it starts
  uses the verbs, not the fields of a document.
- **d.** The cell engine checks each write, and each store of a computed value,
  to a cell that a computation reads. A write from a task that does not own the
  cells records a fault that names the task. The check costs one comparison for
  each write. A cell that no computation reads, such as a cell of a document that
  a service task builds before it posts it, is not checked. With no running loop,
  nothing is checked.

After a stopped unit, the first frame runs the repairs of a failed operation: it
prints from scratch, and it clears a selection that does not resolve.

## 6. Each circumstance

| Circumstance | Today | With the model |
|---|---|---|
| `execute_julia_code` from a native turn, MCP or ACP | holds the window | a unit: held frames, a stop at the next wait |
| An evaluation of the composer or the evaluator | holds the window | a unit |
| A formula in a print | holds the window | held frames, no stop |
| A slow operation from a gesture | holds the window | held frames, the watchdog records it |
| A feed drain that reads files | holds the window | the producer reads; the drain only moves data |
| Many posted operations | 64 for each frame | the same, and held frames when it is slow |
| A storm of faults | the frame reports them | the same, on the document loop |
| The document loop ends with an exception | the loop ends | the same; the window loop closes its windows |
| An MCP request while a unit runs | waits with no bound | waits in the queue with the bound T3 (30 s), then an error result |
| An ACP permission request | waits for the person | the same; the stop also releases it |
| A model stream or an ACP agent | starved by every frame | on a service thread |
| A terminal or a task group | readers starved by every frame | on a service thread |
| The MCP start | waits up to 10 s on the loop | waits on a service task |
| The person closes a window during a held frame | nothing happens | D4 |

## 7. What Julia can not give

- **Julia 1.13 has no API to cancel a task.** A loop that computes and never
  waits runs to its end. Only a separate process for code can stop it.
- **An interrupt of a task that waits has a small race.** `schedule(...; error =
  true)` takes the task out of the wait queue of a condition without the lock of
  that condition. A notify from another thread in the same microseconds can then
  break the queue. Julia's own Ctrl+C has the same race: it forwards the
  interrupt with `throwto`, and its comment calls the delivery "best-effort"
  (`base/task.jl:1199-1217`).
- **A loop that does not allocate also delays every garbage collection.** The
  collection stops all threads, and such a loop never reaches a safepoint. The
  window loop then waits in its next allocation. Step 1 measures how often this
  happens.
- **Compilation can take a lock of the process.** The window loop must run code
  that the precompile workload compiled. Step 1 measures a compile of model code
  during held frames.

## 8. The decisions

Each one waits for the owner. The recommendation is mine.

- **D1. The thread model:** A, B or C (§4). Recommended: A first, and B only if a slow print, formula or operation is a real case.
- **D2. Input during a held frame:** keep it in order and apply it after the hold,
  or drop it and say so. Recommended: keep it. A terminal, Emacs and a browser
  keep input.
- **D3. The stop gesture:** the stop control on the busy bar, and Escape while the
  bar shows. Before the bar shows, Escape stays input for the document. Recommended
  as written.
- **D4. Close during a held frame:** the first close stops the unit. A second
  close, or a close after a stop that had no effect, quits the process without a
  save. Recommended as written.
- **D5. POLICY-6-inbox A and POLICY-6-time T0, T3 and T4** of
  `kernel-audit-fixes.md` become part of this plan. Recommended: yes. The model
  needs I3, I5 and T3, and T0 and T4 agree with it.
- **D6. The stop of model code that waits:** A, an interrupt, with the small race
  of §7; or B, no interrupt, so a stop acts only on our own waits, and otherwise
  the person can wait or quit. Recommended: A, only after a stop through our own
  waits had no effect for 1 s, because it is the route of Julia's own Ctrl+C and
  the person asks for it.
- **D7. Decided by the owner, 2026-10-13:** "there should be no document which
  two editor owns or reads or writes. If it's ever needed it will use a feed from
  one to the other, copying and synching stuff." So each editor has its own
  owner, and a unit holds only the document work of its own editor. Rule d
  compares the task that writes with the owners of the running editors. The
  documents that two editors share today change in step 5 (L21-1).

## 9. The steps (after the decisions)

- [ ] **1. A probe**, in a throwaway program outside the repository: SDL on
  thread 1, a document task on a default thread, the handoff, held frames from
  the retained picture, the hourglass, and a busy bar. Two units: `sleep(10)` and
  a loop that computes for 10 s, once with and once without allocations. Measure:
  the window moves, redraws and closes, and GNOME shows no "not responding"; a
  stop ends the sleep within 100 ms, a thousand times in a row with a notify from
  another thread at the same time; the delay from a key press to its picture
  does not grow; the paint computes no cell after the pull; the effect of a
  collection and of a compile on the window loop.
- [ ] **2. The two loops in the kernel editor layer:** the document loop and the
  window loop, the handoff, the held frames, the pull of the output, the faults of
  the window loop, and POLICY-6-inbox. The backend seam splits into the calls of
  the window loop and the calls of the document loop. `run_frame!` stays the form
  for one task.
- [ ] **3. Units and the stop:** the unit reference, the child task of a code
  unit, `run_on_editor_task!` for the owner and for a task of the unit, the stop,
  T3, the budget of T4 in the description of the code tool, the watchdog, and
  the rules a to d of §5.7.
- [ ] **4. The backends:** SDL (a table of the owner of each field of
  `SdlBackend`, the retained present, the pointer, the busy bar), the web backend
  (a busy message and the `wait` pointer), the console backend (a status line),
  and the video backend (no held frame).
- [ ] **5. The services:** the thread option in `bin/projectured`, in the built
  program and in `run_application`; `Threads.@spawn` for each service task; each
  shared flag atomic; no lock across a post in ACP; MCP resources through the
  document loop; the MCP server off the document loop; the I/O of the file-change
  and task feeds on the producer side; and a list of each task that touches a
  document outside the door (§5.7), with each one moved to the door; and each
  document that two editors share today (L21-1: the session fault log, and the
  stores of the log and statistics feeds) becomes one for each editor, or a copy
  that a feed keeps in sync (D7).
- [ ] **6. The rules, the guides and the checks:** a new invariant for the window
  loop, the limits in `editor.md`, `mcp.md`, `mcp-guide.md` and `assistant.md`,
  the tests of each layer, and a live check of each row of §6 with the real
  application. The hourglass plan and the branch `plan-evaluation-off-editor`
  close.

## Not in this plan

Code in a separate process, which alone can stop a loop that never waits ·
formulas computed outside the print · the process-wide swap of stdout in the
code tool (L18-4) · editing of other documents while a code unit runs.
