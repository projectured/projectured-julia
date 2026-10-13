# The editor always answers the person

> **Status (2026-10-13): PROPOSAL.** The owner asked on 2026-10-12: "The editor
> cannot become unresponsive in any circumstances. [...] If this needs new tasks,
> threads, etc. then we should design it that way. Of course, race conditions,
> dead locks, live locks should be avoided at all costs." Nothing is built.
>
> **Decided by the owner, 2026-10-13:** D1 (option A), D2 (option B), D3
> (option A), D7, the
> rules a, b, c and d of §5.7 with d in its narrow form, the permission P1 for
> one sentence of a sealed file, and step 6 for formulas. **Open:** the
> decisions D4 to D6 and D8, one at a time.
>
> This plan takes in three earlier plans: `a-long-evaluation-does-not-hold-the-editor.md`
> (on the branch `plan-evaluation-off-editor`, deferred on 2026-10-09),
> `the-pointer-shows-the-hourglass.md` (deferred on 2026-10-02), and the parts
> POLICY-6-inbox and POLICY-6-time of `kernel-audit-fixes.md` (not decided).

## 1. The conclusion

One task does all the work of an editor today: it reads the window events, runs
every operation, every feed, every tool call and every print, and paints. Julia
does not preempt a task. So a long tool call or a long evaluation stops the
window, and the Stop button can not act until it ends.

The plan (D1, option A):

- The loop stays on thread 1, as today. It reads the input, applies the
  operations, drains the feeds, prints and paints. The printer, the reader and
  the gesture processing are lazy and incremental, so a frame is fast.
- A **unit** of code (a tool call, an evaluation) runs on thread 2. While it
  runs, it owns the documents of its editor (§5.7).
- While the loop waits for a unit, it runs **held frames**: the last picture,
  the hourglass pointer, a busy bar that names the unit, and a stop control. It
  touches no cell, and it leaves the other input for the frames after the unit.
- A stop ends our own waits at once, and model code at its next wait (D6).
- A formula computes off the loop, and the print reads its stored value (step 6).
- Julia's default threads are enough. With one thread, a unit runs on thread 1,
  as today.

## 2. The requirements

A professional tool meets these. The plan meets them for each unit, except where
§7 says that Julia can not. For the other work of a frame, the owner states that
the printer, the reader and the gesture processing are fast enough in all
circumstances (D1), and R8 shows a frame that is slow anyway.

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
- **R6 No wait without a bound on the thread of the window.** The loop takes no
  lock that another thread holds for an unbounded time. No task waits for itself.
- **R7 No starvation.** The services on thread 1 run while a unit runs.
- **R8 A slow frame is seen.** A frame that takes longer than 1 s is recorded with
  the stage and the work in it.

## 3. The facts (2026-10-12 and 2026-10-13)

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

### 3.2 Work that holds the window today

- **Every tool call.** `run_on_editor_task!` posts a `RunFunctionOperation`, and
  the drain of the inbox runs it on the loop task (`Inbox.jl:104-127`). The
  native turn (`AgentLoop.jl:96`), the MCP handler (`McpServer.jl:246-280`) and
  through it every ACP agent use this door. No timeout, no stop.
- **The evaluations of a person.** `SubmitJuliaOperation`,
  `ComposerEvaluateOperation` and `EvaluateSelectedFormOperation` run
  `execute_julia_code!` inside the evaluation of an operation.
- **A formula.** `evaluate_formula` runs `Core.eval` inside a cell computation,
  so a print can run code of the person (`FormulaDocument.jl:489-507`).
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
- **The fault store is sealed** (`FaultStore.jl:28-30` 🔒): "A store has no lock,
  so all code that writes it must run on the thread of the editor task." A unit
  writes it: the tool closures record faults (`AgentLoop.jl:110`,
  `McpServer.jl:267`), and the printer context carries `editor.faults`
  (`ReadEvaluatePrint.jl:182`), so a computation that a unit starts records into
  it too. See P1.
- **The MCP guide promises** that "a change from a client never meets a frame
  half way" (`mcp-guide.md:73`). A unit runs between two frames, so this holds.
- **ACP posts while it holds a lock.** `receive_notification` calls `on_event`
  under `turns_lock`, and `on_event` posts into the inbox, which blocks when it is
  full (`AcpConnection.jl:452-486`). The inbox is not drained while a unit runs.

## 4. The options (D1, decided: A)

- **A. Code units off thread 1.** The loop stays on thread 1. A code unit runs on
  thread 2, and while it runs, the loop runs held frames. It fixes the four
  problems that exist today: the window freezes during a code unit, the stop can
  not act, no hourglass shows, and the window does not answer the window system.
  It does not cover work whose length is not known before it starts, such as a
  formula in a print.
- **B. All document work off thread 1.** The worker runs the document half of
  each frame, and thread 1 only reads events, paints and presents. It also covers
  the work of unknown length. It costs a split of the SDL backend (4700 lines)
  between two threads. The paint on thread 1 can compute a cell on demand: the
  worker waits during the paint, so the computation is safe. The owner pointed
  this out on 2026-10-13. A pull of every cell before the paint is needed only if
  a computation in the paint can be slow.
- **C. B, and the picture becomes plain data.** The worker makes a list of draw
  commands, and thread 1 draws it at any time, as the compositor of a browser
  does. The owner, 2026-10-13: "it's up to the backend to copy the state,
  potentially in an image form, if necessary." So C is not an option of the
  architecture. A backend keeps the copy that it needs, as SDL keeps its last
  picture in `res.target`, and the worker makes no copy for it.

**Decided by the owner, 2026-10-13: A.** "A: agreed. The printer and reader and
gesture processing are designed and implemented to be lazy and incremental, so
fast enough in all circumstances." A and B share the held frames, a second
thread for document work and the handoff of the cells, so A does not close the
way to B.

## 5. The model (option A)

### 5.1 Threads and tasks

- **Thread 1, the main task: the loop,** as today. It owns the backend and, except
  while a unit runs, the cells of the editor.
- **Thread 2, the default pool: the units.** One unit at a time for each editor.
  A unit runs in a task pinned to thread 2, next to a small supervisor task pinned
  to the same thread (§5.4).
- **The services stay on thread 1** as `@async` tasks. They run during a unit,
  because the held frames of thread 1 wait for events and yield.
- **No new thread option.** With one thread (`-t 1`), or when the loop itself runs
  on thread 2 (`run_editor!(...; wait = false)` with the default threads), a unit
  runs on the thread of the loop, as today, and no held frame shows.

### 5.2 A unit

- **What a unit is:**
  - the call of a function that another task posts with `run_on_editor_task!`:
    every tool call of a native turn, of MCP, and through MCP of every ACP agent;
  - a run of code by the code tool from the loop task, which the operations
    `SubmitJuliaOperation`, `ComposerEvaluateOperation` and
    `EvaluateSelectedFormOperation` make. A run of the code tool inside a unit
    is part of that unit.
- **A description.** A unit has a description that the busy bar shows: the name
  of the tool, or the operation. `run_on_editor_task!` takes it as a keyword, and
  the default is "a call from another task".
- **The start.** The loop hands the cells to the unit through one
  `Threads.Condition`, starts the task of the unit on thread 2, and runs held
  frames until the unit ends.
- **The end.** The unit hands the cells back through the same condition. The
  loop then goes on where it waited: in the drain of the inbox, or in the
  operation, which writes the result as it does today.
- **The order of memory.** The handoff in each direction takes one lock, so each
  side sees every write of the other.
- **One at a time.** The inbox is not drained while a unit runs, so a second call
  waits in it until the first one ends.

### 5.3 A held frame

The loop, while it waits for a unit:

- pumps the events of the window system, so the window answers the ping of the
  window manager;
- presents the retained picture again on an expose, and after a resize draws the
  old picture at the top left and fills the rest;
- shows the hourglass pointer (`SDL_SetCursor` on thread 1, which is now free);
- after 0.5 s, draws a busy bar over the picture with the description of the
  unit, its time, and a stop control;
- reads the stop gesture (D3) and the close of a window (D4);
- leaves the keys in the queue of the backend, in order, for the frames after the
  unit, and drops each pointer press and motion that starts during a held frame.
  A press that started before the held frame keeps its release (D2).

A held frame reads no cell, applies no operation, drains no feed and writes no
fault store. It reads the description, the start time and the stop flag of the
unit, which are plain values.

### 5.4 The stop

- **A stop flag** (`Threads.Atomic{Bool}`) belongs to each unit. The held frame
  sets it on the stop gesture. It does not block and does not post.
- **Our own long waits** (a stream of a model, an ACP request, a wait for a task
  group, a verb with `wait = true`) read the stop flag through a scoped value and
  close their connection or process. This route has no race.
- **Model code that waits** (`sleep`, a channel, I/O) can only be stopped by an
  interrupt (D6). The supervisor task runs on the same thread as the unit, so the
  unit does not run when the supervisor runs. The supervisor calls
  `schedule(unit, InterruptException(); error = true)`, which takes the unit out
  of the queue that it waits in. The code tool turns the interrupt into the
  answer of the call (L18-10 C).
- **Code that computes without a wait** does not let the supervisor run, so no
  stop acts until its next wait. If the stop has no effect after 3 s, the busy
  bar says so, and offers to quit (D4).
- **After a stopped unit,** the first frame runs the repairs of a failed
  operation: it prints from scratch, and it clears a selection that does not
  resolve.

### 5.5 Faults

- A unit writes the fault store of its editor from thread 2, while the loop on
  thread 1 runs held frames and writes none. So one task writes the store at a
  time, and the handoff orders the writes. The sealed docstring says "on the
  thread of the editor task", so it must say "one task at a time: the task that
  owns the cells" (P1).
- A held frame keeps its own faults (a failed pump, a failed present) in a list,
  and the loop records them after the unit.

### 5.6 Deadlocks, races and livelocks

| Hazard | How the model prevents it |
|---|---|
| The loop waits for a unit with no bound | The loop runs held frames while it waits, and the stop and the close of D4 end the wait. |
| A unit waits for work that only the loop can do | `run_on_editor_task!` runs at once for the owner, and throws at once for a task of the running unit (rule b). |
| The loop task posts into its own full inbox (L21-5, L22-4) | A second queue with no bound for the owner of the cells (POLICY-6-inbox I3, D5). |
| A late post after the end of the loop (L22-3) | The end closes both queues, and a later post throws (POLICY-6-inbox I5, D5). |
| A lock held across a wait | Rule: no lock is held across a `wait`, a `put!`, a callback or I/O. ACP calls `on_event` after it releases `turns_lock`. |
| Two threads touch a cell | The handoff gives the cells to one side at a time. A held frame reads no cell. Rules a to d cover the other tasks (§5.7). |
| Two threads write the fault store | A held frame writes none (§5.5). |
| An MCP resource read on the server task (`McpServer.jl:334-362`) | It goes through `run_on_editor_task!`. |
| A part that the person stopped computes again at once | It keeps its fault mark, and the editor tries it again after the next operation, as for any fault. |

### 5.7 Who touches a document during a code unit

**Decided by the owner, 2026-10-13: the rules a, b, c and d below.**

While a code unit runs, it owns every document of its editor. Model code keeps
its API: the fields of a document, the search verbs, the edit verbs and
`evaluate_operation`. Nothing else touches a document:

- The loop on thread 1 runs held frames only (§5.3).
- The cells pass to the unit through one lock at the start, and back through the
  same lock at the end.
- Units are serial (§5.2).

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
  nothing is checked. The check compares the task that writes with the owners of
  the running editors (D7).

### 5.8 A slow frame

The loop measures each stage of a frame. A frame that takes longer than 1 s is
recorded once, with the stage and the work in it: the operation, the feed or the
part of the print. This shows whether a frame is slow in real use, and so whether
B is ever needed.

## 6. Each circumstance

| Circumstance | Today | With the plan |
|---|---|---|
| `execute_julia_code` from a native turn, MCP or ACP | holds the window | a unit: held frames, the stop |
| An evaluation of the composer or the evaluator | holds the window | a unit |
| Any other tool call | holds the window | a unit |
| A formula in a print | holds the window | the print reads a stored value; the formula computes off the loop (step 6) |
| An operation, a feed drain, a print | fast (D1) | as today; §5.8 records a slow frame |
| A storm of faults | the frame reports them | as today |
| An MCP request while a unit runs | waits with no bound | waits in the inbox with the bound T3 (30 s), then an error result (D5) |
| An ACP permission request | waits for the person | the same; the stop also releases it |
| A model stream, an ACP agent, a terminal, a task group | starved while a frame runs | run during a unit, because thread 1 waits in held frames |
| The MCP start | waits up to 10 s on the loop | the same |
| The person closes a window while a unit runs | nothing happens | D4 |

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
  loop on thread 1 then waits in its next allocation. Step 1 measures how often
  this happens.
- **Compilation can take a lock of the process.** The held frames must run code
  that the precompile workload compiled. Step 1 measures a compile of model code
  during held frames.

## 8. The permission and the decisions

- **P1. Permission for one sentence of the sealed `FaultStore.jl`.** The
  sentence "A store has no lock, so all code that writes it must run on the
  thread of the editor task. A task that the editor task starts with `@async`
  runs on that thread." becomes: "A store has no lock, so one task at a time
  writes it: the task that owns the cells of the editor. A task that hands the
  cells to another task hands the store with them." The same change goes into
  `fault.md:79`, which is not sealed. No code of the file changes.
  **Granted by the owner, 2026-10-13.** The sentence changes in the commit of
  step 2 that makes a unit write the store, so that it describes code that
  exists.
- **D1. Decided by the owner, 2026-10-13: A** (§4).
- **D2. Decided by the owner, 2026-10-13: B.** A held frame keeps the keys in
  order for the frames after the unit, as a terminal does, and drops the pointer
  presses and motion that start during it. A click aims at a picture, and the unit
  can change what is under the pointer. The other options were A, keep all input,
  and C, drop all input.
- **D3. Decided by the owner, 2026-10-13: A.** The stop gesture is the stop
  control on the busy bar, and Escape while the bar shows. That Escape stops the
  unit and is not kept for later. Before the bar shows, Escape is a key like any
  other (D2). A click on the Stop button of the assistant in the old picture is
  dropped as any other press (D2). The other options were B, A and also that
  button, which needs a way for a projection to name its stop button, and C, the
  control alone.
- **D4. Close during a held frame:** the first close stops the unit. A second
  close, or a close after a stop that had no effect, quits the process without a
  save. Recommended as written.
- **D5. POLICY-6-inbox A and POLICY-6-time T0, T3 and T4** of
  `kernel-audit-fixes.md` become part of this plan. Recommended: yes. The plan
  needs I3, I5 and T3, and T0 and T4 agree with it.
- **D6. The stop of model code that waits:** A, an interrupt, with the small race
  of §7; or B, no interrupt, so a stop acts only on our own waits, and otherwise
  the person can wait or quit. Recommended: A, only after a stop through our own
  waits had no effect for 1 s, because it is the route of Julia's own Ctrl+C and
  the person asks for it.
- **D7. Decided by the owner, 2026-10-13:** "there should be no document which
  two editor owns or reads or writes. If it's ever needed it will use a feed from
  one to the other, copying and synching stuff." So each editor has its own
  owner, and a unit holds only the document work of its own editor. The
  documents that two editors share today change in step 5 (L21-1).
- **D8. What starts the update of a formula** (step 6). A print must not start
  work (PAR-PURE-THUNK), and an edit of the code of a formula is an edit of its
  syntax, which no operation of the formula domain sees. A: a feed that the
  formula domain registers with the editor. Its drain runs on the loop, outside
  every computation, reads for each formula a key of its inputs (its code and the
  values of its dependencies, a pure and cheap cell), and starts the computation
  of each formula whose key changed. B: a new kind of cell whose computation runs
  off the loop and writes its value later through the door. Recommended: A. It
  uses the feed and the door that exist, and the cell engine stays as it is.

## 9. The steps (after the decisions)

- [ ] **1. A probe**, in a throwaway program outside the repository: the SDL loop
  on thread 1, a unit pinned to thread 2 with its supervisor, the handoff, held
  frames from the retained picture, the hourglass and a busy bar. Three units:
  `sleep(10)`, and a loop that computes for 10 s, once with and once without
  allocations. Measure: the window moves, redraws, resizes and closes, and GNOME
  shows no "not responding"; a stop ends the sleep within 100 ms, a thousand
  times in a row with a notify from another thread at the same time; the delay
  from a key press to its picture does not grow in a frame with no unit; the
  effect of a collection and of a compile on the held frames.
- [ ] **2. Units in the kernel editor layer:** the unit and its description, the
  task on thread 2 and its supervisor, the handoff, the held frames while the
  loop waits, `run_on_editor_task!` for the owner, the fallback on one thread,
  the faults of the held frames, the sentence of P1 in `FaultStore.jl` and
  `fault.md`, POLICY-6-inbox (D5), and the record of a slow frame (§5.8).
- [ ] **3. The stop and the bounds:** the stop flag, our own waits, the interrupt
  (D6), the repairs after a stop, T3, the budget of T4 in the description of the
  code tool, and the rules a to d of §5.7.
- [ ] **4. The backends:** SDL (the pump, the retained present, the resize, the
  pointer, the busy bar, the stop control, the close), the web backend (a busy
  message and the `wait` pointer), the console backend (a status line), and the
  video backend (a unit runs on the thread of the loop, so the video time stays
  exact).
- [ ] **5. The doors:** a list of each task that touches a document outside the
  door (§5.7), with each one moved to the door; the MCP resources through the
  door; no lock across a post in ACP; and each document that two editors share
  today (L21-1: the session fault log, and the stores of the log and statistics
  feeds) becomes one for each editor, or a copy that a feed keeps in sync (D7).
- [ ] **6. Formulas off the loop.** The owner, 2026-10-13: "the formula value
  should be stored in the document explicitly and updated by the projection on a
  task/thread out of the printer loop to avoid making the editor unresponsive".
  Today `result` is a cell whose computation runs the code of the formula, set by
  `wire_result!` (`FormulaDocument.jl:574`), so a print or any read runs it. The
  step:
  - `result` becomes a stored value of the document, with the key of the inputs
    that it was computed from. A print reads only the stored value, and shows a
    mark while the key of the inputs differs.
  - The computation runs on a task of the default pool. It gets its inputs as
    values, as `evaluate_formula` already binds them in a `let`, so it reads no
    document. Its value comes back through the door, and a value computed for a
    key that is no longer current is dropped. Formulas compute one at a time, in
    the order of their dependencies.
  - `get_formula_value` in a unit answers the value for the current inputs: it
    computes on the task of the unit when the stored value is not current. So a
    script that adds a formula and reads its value at once still works. Its users
    in omnet-julia (`StudyCheck.jl`, `StudyVerbs.jl`, `StudyToWidget.jl`,
    `StudyFile.jl`, `IdePrecompile.jl`) follow.
  - What starts an update is D8.
- [ ] **7. The rules, the guides and the checks:** a new invariant for the units
  and the held frames, the limits in `editor.md`, `mcp.md`, `mcp-guide.md` and
  `assistant.md`, the tests of each layer, and a live check of each row of §6
  with the real application. The hourglass plan and the branch
  `plan-evaluation-off-editor` close.

## Not in this plan

Option B · the services off thread 1, which needs `-t 2` · code in a
separate process, which alone can stop a loop that never waits · the
process-wide swap of stdout in the code tool (L18-4) · editing of other
documents while a code unit runs.
