# The editor always answers the person

> **Status (2026-10-13): DECIDED, NOT STARTED.** The owner asked
> on 2026-10-12: "The editor cannot become unresponsive in any circumstances.
> [...] If this needs new tasks, threads, etc. then we should design it that way.
> Of course, race conditions, dead locks, live locks should be avoided at all
> costs." Nothing is built, and the work starts when the owner says so.
>
> **Decided by the owner, 2026-10-13:** D1 (option A), D2 (option B), D3
> (option A), D4 (option A), D5 (option A), D6 (option C), D7, D8, the rules a,
> b, c and d of §5.7 with d in its narrow form, the permission P1 for one
> sentence of a sealed file, step 6 for formulas, and the points A1 to A4 of the
> review (§8.1). All decisions are made. Step 6 still designs the gestures of
> the edit mode of a formula.
>
> This plan takes in `a-long-evaluation-does-not-hold-the-editor.md` (on the
> branch `plan-evaluation-off-editor`, deferred on 2026-10-09),
> `the-pointer-shows-the-hourglass.md` (deferred on 2026-10-02), and, by D5,
> POLICY-6-inbox A and T0, T3 and T4 of POLICY-6-time of `kernel-audit-fixes.md`.

## 1. The conclusion

One task does all the work of an editor today: it reads the window events, runs
every operation, every feed, every tool call and every print, and paints. Julia
does not preempt a task. So a long tool call or a long evaluation stops the
window, and the Stop button can not act until it ends.

The plan (D1, option A):

- The loop stays on thread 1, as today. It reads the input, applies the
  operations, drains the feeds, prints and paints. The printer, the reader and
  the gesture processing are lazy and incremental, so a frame is fast.
- A **code unit** (a tool call, an evaluation) runs on another thread. While it
  runs, it owns the documents of its editor (§5.7).
- While the loop waits for a unit, it runs **held frames**: the last picture,
  the hourglass pointer, a busy bar that names the unit, and a stop control. It
  touches no cell. It keeps the keys for the frames after the unit, and drops
  the pointer input that starts during a held frame.
- A stop ends our own waits and a `sleep` of model code at once (D6). Any other
  wait of model code, and code that computes, end with the quit of D4.
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
- **R4 Keys are not lost.** Keys during a held frame keep their order. Pointer
  input that starts during a held frame is dropped (D2), and the hourglass shows
  that the editor takes no click.
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
- `_scratch_module` makes the scratch module of the code tool before any model
  code runs in it (`CodeExecution.jl:96-98`), so it can give the module its own
  `sleep` first.
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
- **The backend has text state that the print and a unit share.** All text
  rendering and text measurement use one process-wide `_font_cache` with no lock,
  and TTF (`SdlBackend.jl:280`). `write_image`, which the assistant's picture and
  the picture of a part call, calls `_start_sdl_video!()` and `TTF_Init()` on the
  task that calls it (`SdlBackend.jl:3215-3225`). See A1.
- **No hook for a document that enters the window.** The domain layer has
  `release_document!` for a document that leaves it (`DocumentRelease.jl:5-27`),
  and no counterpart. See A3.
- **The MCP guide promises** that "a change from a client never meets a frame
  half way" (`mcp-guide.md:73`). A unit runs inside the drain of the inbox, before
  the read of the frame, so this holds.
- **The MCP server handles one request at a time.** Its loop takes a request,
  runs it and answers it before it takes the next one.
- **ACP posts while it holds a lock.** `receive_notification` calls `on_event`
  under `turns_lock`, and `on_event` posts into the inbox, which blocks when it is
  full (`AcpConnection.jl:452-486`). The inbox is not drained while a unit runs.

## 4. The options (D1, decided: A)

- **A. Code units off thread 1.** The loop stays on thread 1. A code unit runs on
  another thread, and while it runs, the loop runs held frames. It fixes the four
  problems that exist today: the window freezes during a code unit, the stop can
  not act, no hourglass shows, and the window does not answer the window system.
  It does not cover work whose length is not known before it starts, such as a
  slow operation or a slow print. Step 6 moves formulas off the print.
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

## 5. The design (option A)

### 5.1 The shape

```
 thread 1: the main task, interactive pool        a default thread, not the loop's
 ┌─────────────────────────────────────────┐      ┌─────────────────────────────┐
 │ the loop of the editor                  │      │ the task of a code unit     │
 │   a frame: drain the feeds, read,       │start │   tool calls, model code    │
 │   evaluate, print, paint                │─────>│   owns the cells and the    │
 │   held frames while a unit runs:        │      │   text state of the backend │
 │   pump, present, busy bar, stop, close  │<─────│                             │
 │                                         │ end  └─────────────────────────────┘
 │ the backend: windows, renderer, events, │      ┌─────────────────────────────┐
 │   pointer                               │      │ the formula task of each    │
 │                                         │      │ editor (step 6): inputs as  │
 │ services, @async: assistant turns, ACP, │      │ values, reads no document   │
 │   MCP server, terminal, task readers    │      └─────────────────────────────┘
 └─────────────────────────────────────────┘
```

- **The loop** does what it does today. In two places it can meet a code unit:
  in the drain of the inbox, and in an operation that runs the code tool. There
  it starts the unit, and it runs held frames until the unit ends.
- **The task of a code unit** runs on a default thread that is not the thread of
  the loop. While it runs, it owns the cells of the editor and the text state of
  the backend (A1).
- **The services** stay on thread 1 as `@async` tasks. They run during a unit,
  because a held frame waits for events and yields. They reach a document only
  through the door.
- **The formula task** of each editor computes formulas from their inputs as
  values (step 6). It reads no document, so it runs next to the loop and next to
  a unit.

### 5.2 Who owns what

| State | The loop task (thread 1) | The task of a unit | The services (thread 1) |
|---|---|---|---|
| The cells of the editor | owner, except during a unit | owner during the unit | never: they post |
| The fault store | writes, except during a unit | writes during the unit (P1) | never |
| The text state of the backend (font cache, TTF) | uses, except during a unit | uses during the unit (A1) | never |
| The windows, the renderer, the events, the pointer | always | never | never |
| The inbox, bounded (64) | drains, except during a unit | does not drain | post, and wait when it is full |
| The queue of the owner, no bound (I3) | posts and drains | posts | never |
| The record of the unit: description, start time | reads | — | — |
| The stop flag of the unit | sets | reads | — |
| The faults of the held frames | writes, and records them after the unit | — | — |

### 5.3 The states of the loop

```
            ┌───────────────────────── a frame ──────────────────────────┐
   wait ──> │ drain the feeds ──> read ──> evaluate ──> print, paint      │ ──> wait
            └───────┬──────────────────────────────┬─────────────────────┘
                    │ a posted function             │ the code tool, run by
                    │ in the inbox                  │ an operation
                    ▼                               ▼
            ┌────────────────────────────────────────────────────────┐
            │ held: the unit runs on its thread; the loop runs held  │
            │ frames                                                 │
            └───────┬────────────────────────────────┬───────────────┘
                    │ the unit ends                   │ a close after a stop that had
                    ▼                                 │ no effect, and the confirm (D4)
         back to the place where it waited            ▼
                                                     quit
```

### 5.4 One unit, from its start to its end

**What a unit is.**

- The drain of the inbox, when it holds a posted function: every tool call of a
  native turn, of MCP, and through MCP of every ACP agent. The unit applies the
  posted operations and functions of that drain in order, and the busy bar names
  the current one (A4).
- A run of the code tool from the loop task, which `SubmitJuliaOperation`,
  `ComposerEvaluateOperation` and `EvaluateSelectedFormOperation` make. A run of
  the code tool inside a unit is part of that unit.

**Where it runs.** The task of a unit is pinned to a default thread that is not
the thread of the loop. With no such thread, as with `-t 1`, or with
`run_editor!(...; wait = false)` and the default threads, the unit runs inline on
the loop task, as today, and no held frame shows.

**A tool call of MCP, from its start to its end:**

```
 MCP server task (thread 1)    loop task (thread 1)                    unit task
 ──────────────────────────    ────────────────────────────────────    ─────────────────────
 run_on_editor_task!(f)
   posts RunFunctionOperation ─> wakes; the next frame drains the inbox
   waits for the answer          run_code_unit!(editor, drain):
   (T3: 30 s until it starts)      prepare_held_frames!
                                   the owner becomes the unit task
                                   starts the pinned task ───────────> runs the drain: f(), ...
                                   repeats:                              reads and edits documents
                                     run_held_frame!                     posts go to the queue
                                     (a stop, a close?)                  of the owner (I3)
                                                                         sleep: stoppable (D6)
                                   until the unit task is done <──────── ends, and wakes the
                                   waits for the done task                backend
                                   the owner becomes the loop task
                                   records the faults of held frames
                                   end_held_frames!
 gets the answer <───────────────  the unit put it into the channel
                                   the frame goes on: read, evaluate,
                                   print, paint
```

**The order of memory.** The loop starts the task of the unit after it sets the
owner, and the start of a task makes every earlier write visible to the task.
At the end, the loop `wait`s on the task that is done, which makes every write of
the unit visible to the loop. No other lock is needed.

**One at a time.** The inbox is not drained while a unit runs, so a second call
waits in it until the first one ends.

### 5.5 A held frame

The loop, while it waits for a unit, runs held frames. A held frame:

- pumps the events of the window system, so the window answers the ping of the
  window manager;
- leaves the keys and the window events (resize, expose, focus) in the queue of
  the backend, in order, for the frames after the unit. Escape while the busy bar
  shows is the stop (D3), and the held frame takes it out;
- drops each pointer press, release and motion of the windows of its editor that
  starts during a held frame. A press that started before the held frame keeps
  its release (D2);
- on an expose or a resize, presents the retained picture again. After a resize,
  it draws the old picture at the top left and fills the rest;
- shows the hourglass pointer. `end_held_frames!` gives the pointer back the
  shape at the pointer;
- after 0.5 s, draws a busy bar with the description of the unit, its time and a
  stop control, from textures that `prepare_held_frames!` made before the unit
  started (A1);
- reads the stop (D3) and the close of a window (D4).

A held frame reads no cell, applies no operation, drains no feed, writes no fault
store and makes no text. It reads only plain values: the description, the start
time and the stop flag of the unit.

### 5.6 The stop

- **The stop flag** (`Threads.Atomic{Bool}`) belongs to each unit. On the stop
  gesture, the held frame calls `stop_code_unit!`: it sets the flag, and starts
  one task that runs the stop steps of the unit. Nothing that can block runs on
  thread 1.
- **Our own waits in a unit**, such as a verb with `wait = true` or a wait for a
  task group, find their unit through a scoped value, which a task that the code
  starts inherits. Each one attaches a stop step that closes what it waits on, or
  wakes it. This route has no race.
- **A `sleep` of model code** (D6). The scratch module of the code tool has its
  own `sleep`. It waits for its time or for the stop flag of its unit, both
  behind one lock, and on a stop it throws `InterruptException` in its own task.
  The code tool turns the interrupt into the answer of the call (L18-10 C). No
  task throws into another task, so this route has no race.
- **Any other wait of model code** (a channel, I/O, `Base.sleep` in a library),
  and code that computes without a wait, do not see the stop. If the stop has no
  effect after 3 s, the busy bar says so, and a close then offers to quit without
  a save (D4).
- **A stopped unit needs no repair.** A stop acts only at a `sleep` of model code,
  between two of its operations. That is the same as code that throws an error,
  which today needs no repair either.
- **A model stream and an ACP request are not part of a unit.** They run on the
  task of a turn. A stop of a unit that an assistant turn of this editor made also
  cancels that turn, as the Stop button of the assistant does (A2). For an
  external MCP client, only the call ends.

### 5.7 Who touches a document during a code unit

**Decided by the owner, 2026-10-13: the rules a, b, c and d below.**

While a code unit runs, it owns every document of its editor. Model code keeps
its API: the fields of a document, the search verbs, the edit verbs and
`evaluate_operation`. Nothing else touches a document:

- The loop on thread 1 runs held frames only (§5.5).
- The cells pass to the unit at its start and back at its end (§5.4).
- Units are serial (§5.4).

These tasks touch a document outside the door today. They are safe only because
they share thread 1 with the loop:

- a task that model code starts, with `@async` or `Threads.@spawn`, while the
  unit runs or after it ends. The edit verbs apply their operation on the task
  that calls them (`DocumentEdits.jl:82`, `PaneProgram.jl:570`);
- an MCP resource provider that reads a document (`McpServer.jl:334-362`);
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
  each running editor. A cell that no computation reads, such as a cell of a
  document that a service task builds before it posts it, is not checked. With
  no running loop, nothing is checked. The check compares the task that writes
  with the owners of the running editors (D7). A limit: a task that writes a cell
  of its own document while a loop runs, where a computation reads that cell and
  no editor shows the document, is reported too.

### 5.8 Faults

- A unit writes the fault store of its editor, while the loop runs held frames
  and writes none. So one task writes the store at a time, and the start and the
  end of the unit order the writes. The sealed docstring says "on the thread of
  the editor task", so it says "one task at a time: the task that owns the cells"
  (P1).
- A held frame keeps its own faults (a failed pump, a failed present) in a list,
  and the loop records them after the unit.

### 5.9 Deadlocks, races and livelocks

| Hazard | How the model prevents it |
|---|---|
| The loop waits for a unit with no bound | The loop runs held frames while it waits, and the stop and the close of D4 end the wait. |
| A unit runs on the thread of the loop | The task of a unit is pinned to a default thread that is not the loop's. With none, the unit runs inline, as today. |
| A unit waits for work that only the loop can do | `run_on_editor_task!` runs at once for the owner, and throws at once for a task of the running unit (rule b). |
| The owner posts into a full inbox (L21-5, L22-4) | The posts of the owner, the loop task or the running unit, go to the queue with no bound (POLICY-6-inbox I3, D5). |
| A late post after the end of the loop (L22-3) | The end closes both queues, and a later post throws (POLICY-6-inbox I5, D5). |
| A lock held across a wait | Rule: no lock is held across a `wait`, a `put!`, a callback or I/O. ACP calls `on_event` after it releases `turns_lock`. |
| A stop step that blocks | It runs on a task of its own, never on thread 1 (§5.6). |
| Two threads touch a cell | The start and the end of a unit hand the cells over. A held frame reads no cell. Rules a to d cover the other tasks (§5.7). |
| Two threads use the text state of the backend | A held frame makes no text; it draws textures that were made before the unit (A1). |
| Two threads write the fault store | A held frame writes none (§5.8). |
| An MCP resource provider on the server task (`McpServer.jl:334-362`) | One that reads a document goes through the door. One that reads none runs on the server task (T4). |

### 5.10 A slow frame

The loop measures each stage of a frame. A frame that takes longer than 1 s is
recorded once, with the stage and the work in it: the operation, the feed or the
part of the print. This shows whether a frame is slow in real use, and so whether
B is ever needed.

### 5.11 The new names and their files

| Name | What it is | File |
|---|---|---|
| `CodeUnit` | a unit: its description, its start time, its stop flag and its stop steps | `source/kernel/tool/CodeUnit.jl` (new) |
| `get_current_code_unit()` | the unit of the running task, through a scoped value, or `nothing` | same |
| `is_code_unit_stopped()` | whether the person stopped the current unit | same |
| `attach_code_unit_stop!(step)` | a step that a stop runs on a task of its own, such as the close of what a wait waits on | same |
| `stop_code_unit!(unit)` | sets the stop flag and starts the stop steps | same |
| `wait_in_code_unit(seconds)` | the stoppable wait that the `sleep` of the scratch module calls | same |
| `sleep` of the scratch module | the stoppable `sleep` of model code (D6) | `CodeExecution.jl` |
| `run_code_unit!(editor, function_; description)` | runs `function_` as a unit, and runs held frames until it ends | `source/kernel/editor/HeldFrames.jl` (new) |
| `prepare_held_frames!(backend, devices, description)` | backend protocol: makes what held frames draw, before the unit starts | `BackendInterface.jl`, `BackendDefaults.jl` |
| `run_held_frame!(backend, devices, seconds)` | backend protocol: one held frame; answers `:none`, `:stop` or `:close` | same |
| `end_held_frames!(backend, devices)` | backend protocol: gives the pointer back its shape and frees what held frames drew | same |
| `add_cell_writer!(task)`, `remove_cell_writer!(task)` | the owner tasks of rule d | `source/kernel/cell/CellWriterCheck.jl` (new) |
| `run_on_editor_task!(...; timeout, description)` | T3, and the description of a unit | `Inbox.jl` |
| `EditorCallTimeoutException` | the end of the wait of T3 | `Inbox.jl` |
| `Editor` fields `code_unit`, `owner_posts`, `loop_state`, `held_faults` | the running unit, the queue of I3, the state of I1, the faults of held frames | `Editor.jl` |
| `Tool(...; reads_documents)` | T4: a tool that reads no document runs on the calling task | `Tool.jl` |
| `acquire_document!(editor, document)`, `AcquireDocumentOperation` | the counterpart of `release_document!` (A3) | `DocumentRelease.jl` |
| formula fields `result` (stored), `result_key`, `draft` | the last value, the inputs that it came from, the code in edit mode | `FormulaDocument.jl` |
| `EditFormulaOperation`, `CommitFormulaOperation`, `CancelFormulaEditOperation`, `ReplaceFormulaResultOperation` | the edit mode and the value of a formula (step 6) | `source/domain/formula/FormulaComputation.jl` (new) |

The backend defaults make a backend with no held frames still work:
`run_held_frame!` waits one slice and answers `:none`, and the other two do
nothing.

## 6. Each circumstance

| Circumstance | Today | With the plan |
|---|---|---|
| `execute_julia_code` from a native turn, MCP or ACP | holds the window | a unit: held frames, the stop |
| An evaluation of the composer or the evaluator | holds the window | a unit |
| Any other tool call that reads a document | holds the window | a unit |
| A tool call that reads no document (T4) | holds the window | runs on the calling task |
| A formula in a print | holds the window | the print reads a stored value; the formula computes off the loop (step 6) |
| An operation, a feed drain, a print | fast (D1) | as today; §5.10 records a slow frame |
| A storm of faults | the frame reports them | as today |
| A second MCP request while a unit runs | waits with no bound | waits in the queue of the MCP server until the unit ends |
| A call that waits in the inbox while a unit runs, such as a tool call of a native turn | waits with no bound | the bound T3: 30 s until it starts, then an error result |
| An ACP permission request | waits for the person | the same: no unit runs while the agent waits for the answer, and the Stop of the assistant releases it |
| A model stream, an ACP agent, a terminal, a task group | starved while a frame runs | run during a unit, because thread 1 waits in held frames |
| The MCP start | waits up to 10 s on the loop | waits on a service task (T0) |
| The person closes a window while a unit runs | nothing happens | D4 |

## 7. What Julia can not give

- **Julia 1.13 has no API to cancel a task.** A loop that computes and never
  waits runs to its end. Only a separate process for code can stop it.
- **An interrupt of a task that waits has a small race.** `schedule(...; error =
  true)` takes the task out of the wait queue of a condition without the lock of
  that condition. A notify from another thread in the same microseconds can then
  break the queue. Julia's own Ctrl+C has the same race: it forwards the
  interrupt with `throwto`, and its comment calls the delivery "best-effort"
  (`base/task.jl:1199-1217`). So the plan throws into no task (D6).
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
- **D4. Decided by the owner, 2026-10-13: A.** During a held frame, the first
  close of a window acts as the stop. A second close, or a close after a stop that
  had no effect for 3 s, shows "Quit without saving?" with a confirm control on
  the busy bar, and the confirm quits the process. No save is possible during a
  unit, because the unit owns the documents. The other options were B, the close
  waits for the end of the unit, and C, the close quits at once.
- **D5. Decided by the owner, 2026-10-13: A.** POLICY-6-inbox A (I1 to I6) and
  T0, T3 and T4 of POLICY-6-time (`kernel-audit-fixes.md:2226-2272`) are part of
  this plan, with two changes for units:
  - I3: the queue with no bound takes the posts of the owner of the cells, which
    is the loop task or the running unit. The inbox is not drained during a unit,
    so a unit that posts into a full inbox would wait for the loop that waits for
    it.
  - T4: the description of the code tool says that the person can not edit while
    the code runs, so long work belongs in a task that posts its results.
  T0 moves the MCP start, which waits up to 10 s on the loop, to a service task.
  T1, T2, T5 and T6 stay in `kernel-audit-fixes.md`. The other options were B,
  only I3, I5 and T3, and C, nothing until the audit plan decides POLICY-6.
- **D6. Decided by the owner, 2026-10-13: C.** No interrupt. A stop ends our own
  waits and the `sleep` of the scratch module of the code tool, which waits for
  its time or for the stop flag behind one lock (§5.6). Any other wait of model
  code ends with the quit of D4. The other options were A, an interrupt with
  `schedule(...; error = true)`, which has the race of §7 and can crash the
  process, and B, no interrupt and no stoppable `sleep`. My recommendation was A
  at first. I changed it to C because the owner asked to avoid races at all
  costs, and a crash loses the unsaved changes of every window.
- **D7. Decided by the owner, 2026-10-13:** "there should be no document which
  two editor owns or reads or writes. If it's ever needed it will use a feed from
  one to the other, copying and synching stuff." So each editor has its own
  owner, and a unit holds only the document work of its own editor. The
  documents that two editors share today change in step 5 (L21-1).
- **D8. Decided by the owner, 2026-10-13: the model of step 6.** A formula
  computes at a commit, at a load, and at a new value of a formula that it names,
  as Excel does. A key starts no computation, and a formula in edit mode shows no
  value, because the stored value belongs to code that is no longer there. Each
  start is an operation of the formula domain. The options before were a feed
  that walks the documents, a new kind of cell that computes off the loop, a note
  from the print in the printer context, and a mark that the reader adds to each
  edit. The model needs none of them.

### 8.1 The points of the review of 2026-10-13

**Decided by the owner, 2026-10-13: option a of each point.**

- **A1. The text state of the backend.** A unit can call `write_image`, which
  starts SDL video and TTF on the thread of the unit, and any print-side
  computation of a unit measures text with the shared `_font_cache` (§3.4). A held
  frame that drew text would use the same cache and TTF on thread 1 at the same
  time. Decided: a held frame draws only textures that `prepare_held_frames!`
  made before the unit started, so the unit owns the text state as it owns the
  cells; and the offscreen render of `write_image` needs no SDL video, so it can
  run on the thread of a unit. The other options were b, a lock on the font cache
  and TTF, which can make thread 1 wait as long as the unit renders text, and c,
  backend calls of a unit that thread 1 runs in a held frame.
- **A2. A stop of a unit that an assistant turn made.** The stop ends the code,
  and the tool answers that it was interrupted. The turn then goes on, and the
  model can run the code again. Decided: a stop of a unit that an assistant turn
  of this editor made also cancels that turn, as the Stop button of the assistant
  does. For an external MCP client, only the call ends. The other option was b,
  only the unit stops.
- **A3. A document that enters the window.** A formula computes at the load of a
  document (D8), and no hook says when a document enters the window (§3.4).
  Decided: `acquire_document!(editor, document)` and
  `AcquireDocumentOperation`, the counterpart of `release_document!`, which the
  open of a document adds. The formula domain starts its computations there. This
  is a new mechanism. The other option was b, no start at load, so a sheet opens
  with no values.
- **A4. What a unit is.** Each streamed event of a turn and each line of output of
  a terminal is a posted function. If each posted function were a unit, each would
  cost a handoff to another thread and back, up to 64 in one drain. Decided: one
  unit for each drain of the inbox that holds a posted function, which applies
  the posted operations and functions of the drain in order (§5.4). The other
  options were b, each posted function a unit, and c, only posts that the caller
  marks as long.

## 9. The steps (after the decisions)

- [ ] **1. A probe**, in a throwaway program outside the repository: the SDL loop
  on thread 1, a unit pinned to a default thread, the start and the end of a
  unit, held frames from the retained picture, the hourglass and a busy bar from
  textures made before the unit. Units: `sleep(10)` with the stoppable `sleep`,
  a loop that computes for 10 s, once with and once without allocations, and a
  `write_image` (A1). Measure: the window moves, redraws, resizes and closes, and
  GNOME shows no "not responding"; a stop ends the stoppable `sleep` within
  100 ms; the delay from a key press to its picture does not grow in a frame with
  no unit; the keys of a held frame arrive in order after the unit; the effect of
  a collection and of a compile on the held frames.
- [ ] **2. Units in the kernel editor layer:** `CodeUnit`, `run_code_unit!`, the
  task pinned to a default thread that is not the loop's and the fallback inline,
  the start and the end of a unit, the held frames while the loop waits,
  `run_on_editor_task!` for the owner, the faults of the held frames, the
  sentence of P1 in `FaultStore.jl` and `fault.md`, POLICY-6-inbox with I3 for a
  unit (D5), the cell writers of rule d, and the record of a slow frame (§5.10).
- [ ] **3. The stop and the bounds:** the stop flag, `stop_code_unit!` and the
  stop steps of our own waits, the stoppable `sleep` of the scratch module (D6),
  T0 with the MCP start on a service task, T3, T4 (`Tool(...; reads_documents)`,
  and the budget in the description of the code tool), the rules a, b and c of
  §5.7, and A2.
- [ ] **4. The backends:** the three protocol functions of held frames and their
  defaults. SDL: the pump; the keys and the window events left in the queue; the
  pointer events of the windows of the editor dropped; the retained present; the
  resize; the pointer; the busy bar from textures; the stop control; the close;
  and the offscreen render of `write_image` with no SDL video (A1). The web
  backend: a busy message and the `wait` pointer. The console backend: a status
  line. The video backend: a unit runs on the thread of the loop, so the video
  time stays exact.
- [ ] **5. The doors:** a list of each task that touches a document outside the
  door (§5.7), with each one moved to the door; each MCP resource provider by
  `reads_documents`; no lock across a post in ACP; and each document that two
  editors share today (L21-1: the session fault log, and the stores of the log and
  statistics feeds) becomes one for each editor, or a copy that a feed keeps in
  sync (D7).
- [ ] **6. Formulas off the loop.** The owner, 2026-10-13: "the formula value
  should be stored in the document explicitly and updated by the projection on a
  task/thread out of the printer loop to avoid making the editor unresponsive".
  Today `result` is a cell whose computation runs the code of the formula, set by
  `wire_result!` (`FormulaDocument.jl:574`), so a print or any read runs it, and
  it computes again on each key that changes the code. The model, decided by the
  owner on 2026-10-13 (D8):
  - **The last value.** A formula holds the last value that was computed, in a
    field of the document, with the key of the code and the inputs that it came
    from. Its default is `nothing`. Only `ReplaceFormulaResultOperation`, which
    brings a computed value back through the door, writes it. A print reads only
    this field.
  - **Two modes.** In value mode, a formula shows its value. In edit mode, it
    shows its code and no value, and the keys edit a draft of the code. A commit
    (`CommitFormulaOperation`) writes the draft into the code as one operation and
    starts the computation. A cancel (`CancelFormulaEditOperation`) drops the
    draft. A key starts no computation. This is what Excel does: Enter or a move
    out of the cell commits, and Escape cancels.
  - **Three starts.** A computation starts at a commit, at the load of a document
    (A3), and at a new value of a formula that this formula names, as in the
    automatic mode of Excel. Each start is an operation of the formula domain,
    which runs on the loop outside every computation.
  - **Off the loop.** The formula task of the editor computes one formula at a
    time, in the order of their dependencies, in a scratch module of its editor.
    The scratch module of formulas is one for the process today
    (`FormulaDocument.jl:442`). A computation gets its inputs as values, as
    `evaluate_formula` already binds them in a `let`, so it reads no document. A
    value computed for code or inputs that are no longer current is dropped. Until
    the value arrives, the formula shows a mark that it computes.
  - **Undo** of a commit restores the old code and its value together, because the
    commit is one operation.
  - **Code that reads a value.** `get_formula_value` in a unit answers the value
    for the current code and inputs, and computes it on the task of the unit
    when the stored value is not current. So a script that adds a formula and
    reads its value at once still works. Its users in omnet-julia
    (`StudyCheck.jl`, `StudyVerbs.jl`, `StudyToWidget.jl`, `StudyFile.jl`,
    `IdePrecompile.jl`) follow.
  - **The gestures** that enter the edit mode, commit and cancel are designed in
    this step. Julia code can have more than one line, so Enter can not always
    commit. The commit of `FormulaInsertion` on Enter (`formula.md:94`) uses the
    same gestures.
- [ ] **7. The rules, the guides and the checks:** a new invariant for the units
  and the held frames, the limits in `editor.md`, `mcp.md`, `mcp-guide.md` and
  `assistant.md`, the tests of each layer, and a live check of each row of §6
  with the real application. The hourglass plan and the branch
  `plan-evaluation-off-editor` close.

## Not in this plan

Option B · the services off thread 1, which needs `-t 2` · code in a separate
process, which alone can stop a loop that never waits · the process-wide swap of
stdout in the code tool (L18-4) · editing of other documents while a code unit
runs.
