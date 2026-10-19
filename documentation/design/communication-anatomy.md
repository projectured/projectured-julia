# The means of communication

> **Kind:** design · **Status:** current · **Stands on:** [system-anatomy.md](system-anatomy.md), [architecture-invariants.md](../rule/architecture-invariants.md), [editor.md](../package/kernel/editor.md)

This document names the parts of the editor that run at the same time, and the means by which they give data to each other. It is a map: each means has one section here, and the guide of its slice holds the detail. Read it before you add a part that runs on a task of its own, or that reads the disk, a process or the network.

## The parts that run at the same time

A part here is code that runs on a task of its own, or a process outside Julia. The table names each part, where it runs, and the guide that describes it.

| Part | Where it runs | How many | Guide |
| --- | --- | --- | --- |
| The loop of an editor | The task that calls `run_editor!`. With `wait = false`, a task pinned to an interactive thread, else to a default thread. | One for each editor | [editor.md](../package/kernel/editor.md#the-read-eval-print-loop) |
| The backend | The loop task. The web backend adds a receive task and a send task. The console backend adds a task that reads the terminal. | One for each editor | [devices-and-backends.md](../package/kernel/devices-and-backends.md) |
| A code unit | A task pinned to a free interactive thread. Without one, a task of the default pool. | One at a time for each editor | [editor.md](../package/kernel/editor.md#a-code-unit-and-its-held-frames) |
| Background work | A task of the default pool. Examples: the work of a background cell, the formula task, a turn of the assistant. | Any count | [editor.md](../package/kernel/editor.md#the-background-cell) |
| The producer of a feed | A task of its own: a watcher of a folder, the tasks of a task group, a sampler of `/proc`, the read of a reflected value. Any task that logs is a producer too. | One or more for each feed | [editor.md](../package/kernel/editor.md#the-feeds) |
| A server | The MCP server, on a task that the loop starts on its own thread. The HTTP server of the web backend. | One for each editor | [mcp.md](../package/adapter/mcp/mcp.md), [web.md](../package/backend/web/web.md) |
| An outside process | A process of the operating system: a terminal, a process of a task group, a clipboard tool, an agent that speaks the agent client protocol (ACP). | Any count | [terminal.md](../package/platform/terminal/terminal.md), [task.md](../package/platform/task/task.md), [acp.md](../package/adapter/acp/acp.md) |

`bin/projectured` starts Julia with `--threads=auto,2`: a default pool and two interactive threads. The loop takes the main thread or one interactive thread. A code unit takes the other interactive thread, so it never waits behind background work. Background work and the producers of feeds use the default pool.

## One owner task for each editor

The documents of an editor, and the cells that its projections derive from them, have one owner task (`PAR-SINGLE-WRITER`). The owner is the loop task. While a code unit runs, the owner is the task of the unit, and the loop runs held frames that read no cell. The engine takes no lock on a cell. Instead, `cell/CellWriterCheck.jl` records a `ForeignCellWriteException` fault when another task writes a cell that a computation reads.

So a cell is not a means of communication between tasks. A write of a cell, and the recompute of its readers, are calls on the owner task. Every means below moves data from another task to the owner task, or from the owner task to the outside.

```
 other tasks                                   the owner task: the loop, or a code unit
 ───────────                                   ─────────────────────────────────────────
 any task      ── wake_editor! ──────────────▶ wake_pending ──▶ the wait ends
 any task      ── post_operation! ───────────▶ inbox ─────┐
 any task      ── run_on_editor_task! ───────▶ inbox ─────┤
 a producer    ── store, then wake ──────────▶ feed ──────┴─▶ drain ─▶ evaluate ─▶ cells
 window system ── event queue ───────────────▶ take_from_devices! ─▶ read_intent ─▶ evaluate
                                                                    print ─▶ paint
 background work ◀── demands ──────────────── start_background_cell_work!, after the print
                 ── answers, by post_operation! ─▶ inbox
```

## The means between tasks

Each means has its own section below. This table gives them together.

| Means | Carries | From, to | The sender waits | Guide |
| --- | --- | --- | --- | --- |
| The wake | No data: "run a frame" | Any task, to the loop | Never | [editor.md](../package/kernel/editor.md#the-feeds) |
| The deadline | No data: a time | The loop, to itself | Not applicable | [editor.md](../package/kernel/editor.md#the-timer-and-the-display-event) |
| The event queue of the backend | A `WindowInput` | The window system, to the loop | Never | [devices-and-backends.md](../package/kernel/devices-and-backends.md) |
| The inbox | An `Operation` | Any task, to the owner | When the inbox is full | [editor.md](../package/kernel/editor.md#the-inbox) |
| The call | A function, and its answer | Any task, to the owner and back | With `wait = true`, until the answer | [editor.md](../package/kernel/editor.md#a-call-on-the-editor-task) |
| The feed | Data that the producer prepared | A producer, to a target document | Never | [editor.md](../package/kernel/editor.md#the-feeds) |
| The background cell | Inputs out, answers back | The owner, to background work and back | Never | [editor.md](../package/kernel/editor.md#the-background-cell) |
| The fault store | A fault record | The owner, to the fault log | Never | [fault.md](../package/kernel/fault.md) |
| The stop | A flag and stop steps | The owner, to running work | Never | [editor.md](../package/kernel/editor.md#a-code-unit-and-its-held-frames) |

### The wake

`wake_editor!(editor)` sets the atomic flag `wake_pending`. When the flag changes from `false` to `true`, it calls `wake_backend!`, which ends the wait of the backend. `wake_backend!` is the one function of the backend protocol that must be thread-safe. Many wakes before a frame give one frame, because the frame takes the flag with one atomic exchange. A store gets the wake as a callback when its feed is registered, so a store never names `Editor`.

### The deadline

The loop also wakes itself. `compute_wait_timeout` gives the earliest of three times:

- `FRAME_INTERVAL`, 1/30 s, while a cell reads the clock of the editor;
- the deadline of each feed, from `compute_wake_deadline`;
- the earliest timer. A reader sets a timer with `SetTimerOperation`, and the loop reads a `TimerExpire` at its time.

The loop uses no timer of the operating system: the timeout of the wait is the timer. A rest of the pointer works so, through `DwellRecognition`; see [gesture.md](../package/kernel/gesture.md).

### The event queue of the backend

The backend has no task of its own for the loop. `wait_for_input` waits on the loop task, and `take_from_devices!` gives one `WindowInput` or `nothing`. The backend never calls the editor. The queue is different for each backend:

| Backend | The queue | The wake |
| --- | --- | --- |
| SDL | The event queue of SDL | `SDL_PushEvent` of a user event, which SDL makes safe from any thread |
| Web | A `Channel` of 256 events, which the receive task of the WebSocket fills | A `Base.Event` gate |
| Console | The input that a task of the backend reads from the terminal | A `Base.Event` gate |
| Video | A timeline of scripted events | None: in video time the wait only lets the other tasks run |

A paint goes the other way. `run_print_stage!` calls `write_to_devices!` on the loop task. The web backend puts each frame into the outbox `Channel` of its connection, and a send task writes it to the socket.

### The inbox

`post_operation!(editor, operation)` is the door for an edit from another task. It puts the operation into `editor.inbox`, a `Channel` of 64 operations (`INBOX_CAPACITY`), and calls `wake_editor!`. A producer that is faster than the editor waits when the inbox is full. A post from the owner, or from a task that the running code unit started, goes to `owner_posts` instead. That queue has no bound, so the owner never waits for itself.

The drain applies `owner_posts` first and then the inbox, at the start of the frame, each operation in a fault barrier. After the loop ends, a post throws `InvalidStateException`, and each caller catches it.

### The call

`run_on_editor_task!(function_, editor; wait, timeout)` runs a function on the owner task. It posts a `RunFunctionOperation`, which holds the function and a `Channel` for the answer. A drain that holds a call runs as one code unit, so the window still answers while the function runs. With `wait = true`, the caller waits for the value, or for the exception, which it throws again.

- The call runs at once on the owner task, and when no loop runs.
- After `timeout`, 30 s by default, a call that did not start throws `EditorCallTimeoutException` and does not run. The start and the timeout each try one compare-and-swap on the state of the call, and only the first one succeeds.
- A call with `wait = true` from a task that the running unit started throws `CodeUnitWaitException`, because the two would wait for each other.

The users of the call are a tool call of the MCP server that reads documents, a turn of the assistant, a verb that the Julia REPL calls, the formula task, the text of a terminal, and a fault from another task.

### The feed

A feed is one registered inflow of the editor. Its producer writes a plain store under a lock and calls the wake that the store got at registration. Its drain, `drain_changes!(feed, editor)`, runs on the owner task once per frame, after the inbox. A drain moves only data that its producer prepared off the loop (`PAR-DRAIN-MOVES-PREPARED-DATA`). It does no I/O and calls no method of a type that a user defines.

| Feed | Producer | The editor gets a frame by | Target |
| --- | --- | --- | --- |
| `InboxFeed` | `post_operation!` and `run_on_editor_task!` | The wake | The edited document |
| `MessageLogFeed` | Any task that logs | The wake | The `MessageLog` of the editor |
| `McpLogFeed` | The MCP server, for each call | The wake | The `McpLog` of the editor |
| `FrameStatisticsFeed` | The loop itself | A deadline, never a wake | The table and the plot of the frames |
| `BackgroundWorkFeed` | The loop itself, at the start and at the end of each work of a background cell | A deadline while the log is due, never a wake | The log of the background work |
| `FileChangeFeed` | A watcher task for each watched folder | The wake | The file document, or the folder document |
| `TaskFeed` | The tasks of a task group | A deadline of 0.25 s while entries change | The rows of the task groups |
| `ReflectionFeed` | A read of a value on a task of the default pool | The wake and a deadline | The reflected tree of the value |
| `SystemProcessFeed` | A sampler of `/proc`, at most once a second | A deadline | The tree of processes |
| `AgentEventFeed` | The connection to an agent over ACP | The wake and a deadline | The transcript of the assistant |

The application gives most feeds when it makes the editor. The system process slice and the assistant add their feed to a running editor at the first use.

### The background cell

A background cell is a cell whose value background work computes. A read never waits:

1. A computation reads the cell. If the cell has no answer for its inputs, the read records a demand and calls `wake_editor!`. The read gives the last answer or the default, and the cell is provisional.
2. After the print, `start_background_cell_work!` starts one background work for each source. The work gets the inputs of all demands of that source.
3. The work posts one `WriteBackgroundAnswersOperation` to the inbox.
4. The owner writes each answer into its cell in a write phase. The readers become invalid, and the next print shows the answers.

The demand is a record in a collector outside the graph, so the computation stays pure (`PAR-PURE-THUNK`). An answer to an old demand is dropped by its demand number. Nothing cancels the work of a background cell: a new input makes a new demand. The folder listing of the file system slice uses a background cell; see [filesystem.md](../package/platform/filesystem/filesystem.md).

Two other forms bring the result of work off the loop back to the owner:

- `start_document_read!(editor, read, apply)` runs `read` on a task and waits 50 ms for it. If the read ends in that time, the owner evaluates `apply(answer)` at once. Else a task posts it when the read ends.
- The formula task is background work. For each formula, one call gets the inputs as values, the code runs off the loop, and a second call stores the result ([formula.md](../package/domain/formula/formula.md)).

### The fault store

The fault store of an editor has no lock, so only the owner task writes it. The barrier of each stage catches a fault in a frame. A task that is not the owner records a fault through `run_on_editor_task!(...; wait = false)`. `record_fault!` calls the fault wake, and `report_frame_faults!` reports the store at the top of the next frame. A task that has only `errormonitor` writes its exception to the log, not to the fault store. See [fault.md](../package/kernel/fault.md).

### The stop

A stop goes from the owner to work that runs on another task. Julia can not cancel a task. So a stop sets a flag and runs the stop steps of the work on a task of their own. A stop step ends a wait of the work.

| Work | The stop | What it does |
| --- | --- | --- |
| A code unit | `stop_code_unit!`, from Escape, the stop control or the first close of a window | Ends a wait of the editor in the unit, and the `sleep` of the scratch module of the code tool |
| Background work | `stop_background_work!` | Sets the flag and runs the stop steps |
| A task group | `stop_work_item!`, then `stop_task_execution!` | Sends `SIGINT` to the process group of each task |
| A search below a node | `stop_work_item!` | Keeps the result that it has, and reads no more |
| A terminal | `stop_terminal!` | Sends `SIGINT`, and `SIGKILL` at the second stop |

Code that computes and never waits ends only with the quit. A second close of the window asks whether to quit, and the confirm throws `QuitEditorException` while the unit still runs. The rule is `PAR-LOOP-RUNS-NO-USER-CODE`.

## Inside the owner task: calls, not messages

The core of the editor is one chain of calls on the owner task. No queue stands between its steps:

1. `run_read_stage!` gives a `WindowInput` to `read_intent`, wrapped in an `Intent`.
2. Each projection of the chain translates the `Intent` with the IO map of its last print, and an `Operation` comes out at the document end ([projection-system.md](../package/kernel/projection-system.md)).
3. `evaluate_operation` applies the operation to the document ([operation.md](../package/kernel/operation.md)).
4. Each write of a cell invalidates its readers. Nothing recomputes yet ([cell.md](../package/kernel/cell.md)).
5. `print_document` reads the cells again. Only invalid cells recompute, and the print gives a new IO map.
6. `write_to_devices!` paints the output.

An operation that code makes at a place, not a gesture, goes through the same readers with a route (`read_rooted_operation`). Undo records the inverse of each edit that passes its projection. A popup, a tooltip and a second window are windows of the same editor, which ordinary operations open and close. So none of them is a separate part that communicates.

## One frame: the order of the inflows

A frame takes each inflow at one fixed place. So the frame in which the data of a producer shows is known in advance:

1. The loop waits until an input, a wake or the timeout. A frame with a wake that is still pending does not wait, and sleeps 1 ms (`TASK_SHARE`) so that the other tasks of the thread run.
2. The frame takes the wake flag. A wake after this point belongs to the next frame.
3. The loop sets the clock of the editor.
4. `drain_feeds!` drains the feeds: the inbox first, then each registered feed.
5. `report_frame_faults!` reports the fault store.
6. The loop reads and evaluates up to 32 inputs (`MAX_OPERATIONS_PER_FRAME`).
7. The loop prints and paints.
8. `start_background_cell_work!` starts the work of the demands that the print recorded.

A post during a frame shows in the next frame. A demand that the print records starts its work after the paint of the same frame.

## Examples of paths

| What happens | The path |
| --- | --- |
| The person presses a key | The SDL queue, `take_from_devices!`, `read_intent`, `evaluate_operation`, the print, the paint |
| The pointer rests | A motion gives a deadline, the loop sets a timer, the wait ends at the timer, and `TimerExpire` becomes `MouseDwell` |
| A folder opens in the tree | `AcquireDocumentOperation` starts a watch. The print reads the listing cell, which records a demand. Background work reads the folder and posts the answer, and the next print shows the entries |
| A file changes on disk | The watcher task waits until the file settles, then hashes and parses it. It stores the result and wakes the editor. The drain calls `receive_file_change!`, which evaluates `ReloadFileOperation` |
| An MCP client calls a tool | The server task calls `run_on_editor_task!`. The drain runs the tool in a code unit, and the server task sends the answer. `McpLogFeed` copies the call into the MCP log |
| The assistant answers | A turn runs as background work and streams from the model. It posts each part with `run_on_editor_task!(...; wait = false)` |
| An agent over ACP answers | The connection task puts each event into an `AgentEventQueue` and wakes the editor. `AgentEventFeed` applies the events in order |
| A process of a task group writes a line | A reader task writes the execution under the lock of the runtime. A listener marks the entry in the store, and `TaskFeed` copies it at its next deadline |
| A terminal writes text | A reader task posts the text with `run_on_editor_task!(...; wait = false)` |
| A task logs a message | The logger writes the store of the log and wakes the editor. `MessageLogFeed` copies the new lines |
| The Julia REPL shows a value in a running editor | The display calls `run_on_editor_task!`, which runs the show on the owner task |

## The outside of the process

| Outside part | The means | The task that waits for it |
| --- | --- | --- |
| The window system | The event queue of SDL | The loop task, in `wait_for_input` |
| A browser | HTTP and a WebSocket | The receive task and the send task of the web backend |
| An MCP client | HTTP on `127.0.0.1:9876/mcp` by default | The task of the server |
| An agent over ACP | The pipes of a process, or streams in the same process | The task of the connection |
| A language model | HTTP streams of the adapter | Background work, in the turn of the assistant |
| A child process | Pipes, a process group of its own, and signals | The reader tasks of a terminal or of a task |
| The disk | The notification of a folder, or a poll of its files | The watcher task of the folder; background work for a read |
| `/proc` | A read of files | The sampler task |
| The clipboard | A clipboard tool that the editor starts | The owner task: a copy runs the tool in `evaluate_operation`, and a paste runs it in the reader. The frame waits for the tool |

## Two editors in one process

One process can run many editors (`PAR-PER-EDITOR-STATE`). Each editor has its own inbox, feeds, fault store and session documents (`get_session_document!`). No document is owned, read or written by two editors. When two editors show the same data, a feed copies it into a document of each editor.

Three producer stores are constants of the process: the store of the log, the store of the MCP log, and the store of the task feed. Each store keeps numbered entries, and each feed reads from its own cursor, so each editor gets its own copy. The store of the MCP log takes the calls of every MCP server of the process, so the MCP log of each editor shows all of them. The list of owner tasks that the cell writer check reads holds the owner tasks of all editors.

## Choose a means for a new part

| A new part must | Use |
| --- | --- |
| Give the editor an edit from another task | `post_operation!` |
| Read or write documents from another task, with or without an answer | `run_on_editor_task!` |
| Give a stream of data from a task of its own | A feed: a store that the producer fills, and a drain that only copies |
| Show a value that is slow to compute, or that comes from the disk | A background cell |
| Run code of a person or a model, of a length that is not known | A code unit, through a tool call, or background work |
| Wait for a time with no event | `SetTimerOperation` in a reader, or `compute_wake_deadline` in a feed |
| Read outside state for a document that a view shows | An acquire that starts the watch, and a background cell that reads ([filesystem.md](../package/platform/filesystem/filesystem.md)) |

Do not write a cell from another task. The cached values then mix old and new values, and the cell writer check records a fault. Do not read the disk in a computation (`PAR-PURE-THUNK`), and do no I/O in a drain (`PAR-DRAIN-MOVES-PREPARED-DATA`).

## The terms

| Term | Meaning |
| --- | --- |
| **owner task** | The task that writes and reads the cells of an editor: the loop task, or the task of the running code unit |
| **loop task** | The task that runs `run_editor!` |
| **frame** | One turn of the loop: drain, read, evaluate, print, paint |
| **held frame** | A frame that the loop runs while a code unit owns the cells. It reads no cell |
| **code unit** | Work of a length that is not known, which owns the cells while it runs on a thread of its own |
| **background work** | Work on a task of the default pool that no frame waits for |
| **background cell** | A cell whose value background work computes. A read never waits |
| **demand** | The record that a read of a background cell makes when the cell has no answer |
| **provisional** | A value that is not final yet, because an answer is still to come |
| **post** | A call of `post_operation!` |
| **inbox** | The bounded queue of posted operations of an editor |
| **call** | A call of `run_on_editor_task!` |
| **wake** | A call of `wake_editor!`, or of the callback that a store got |
| **deadline** | A time at which the loop runs a frame with no wake |
| **feed** | A registered inflow: a producer, a store and a drain |
| **drain** | The step of a feed that copies new data into a document, on the owner task |
| **stop step** | A function that a stop of a work runs, on a task of its own |
| **acquire**, **release** | The operations by which a view starts and ends its need for a document that shows outside state |
