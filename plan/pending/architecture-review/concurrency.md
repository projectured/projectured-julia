# Architecture review: tasks, timers, processes, watchers, and their way to the editor loop

Commit 3a9b4fae4. Reviewer area key: concurrency.

## Scope

The area is a cross-cut of `source/`. I found the sites with these searches: `@async`, `Threads.@spawn`, `schedule(`, `errormonitor`, `Channel(`, `Timer(`, `sleep(`, `timedwait(`, `ReentrantLock`, `Base.Event`, `FolderMonitor`, a start of a process (`run(`, `open(` of a command), `make_background_cell`, `start_background_work`, `start_document_read!`, `run_on_editor_task!`, `post_operation!`, `wake_editor!`, `drain_changes!`, `compute_wake_deadline`, `acquire_document!`.

Read in full, about 6100 lines:

- Documents: `documentation/design/communication-anatomy.md`, `concepts.md`, `architecture-decisions.md`; of `documentation/rule/architecture-invariants.md` the index and the rules PAR-PURE-THUNK, PAR-NO-WRITE-IN-THUNK, PAR-STORE-THEN-DRAIN, PAR-SINGLE-WRITER, PAR-PER-EDITOR-STATE, PAR-LOOP-RUNS-NO-USER-CODE, PAR-DRAIN-MOVES-PREPARED-DATA, PAR-PRODUCER-CARRIES-THE-PART, PAR-REPORT-NEVER-THROWS.
- Kernel: `source/kernel/editor/Inbox.jl`, `Feeds.jl`, `BackgroundCells.jl`, `EditorLoop.jl`; `source/kernel/tool/BackgroundWork.jl`, `CodeUnit.jl`; `source/kernel/feed/FeedInterface.jl`, `FeedDefaults.jl`.
- Platform and adapters: `filechange/FileChangeStore.jl`, `FileChangeFeed.jl`; `log/MessageLogStore.jl`, `MessageLogFeed.jl`, `MessageLogCapture.jl`; `mcplog/McpLogStore.jl`, `McpLogFeed.jl`; `task/TaskFeed.jl`, `TaskWorkItem.jl`; `reflection/ReflectionFeed.jl`; `backgroundwork/BackgroundWorkFeed.jl`; `statistics/FrameStatisticsFeed.jl`; `terminal/TerminalProcess.jl`, `TerminalDocument.jl`; `domain/DocumentRead.jl`; `assistant/AgentTerminal.jl`; `adapter/languageserver/LanguageServerConnection.jl`.
- Plans: `plan/done/a-value-that-a-task-reads-is-a-cell.md`, `plan/done/the-feeds-of-an-editor-are-its-own.md`.

Sampled, by the parts that the searches named: `kernel/editor/Editor.jl`, `HeldFrames.jl`, `DocumentEdits.jl`; `kernel/agent/AgentLoop.jl`, `AgentConnectionEvent.jl`; `kernel/tool/MeaningSearch.jl`; `platform/assistant/AgentEventFeed.jl`, `AssistantTurn.jl`, `ExternalAgentTurn.jl`, `AssistantWake.jl`, `AgentWorkDocument.jl`; `platform/task/TaskExecution.jl`, `TaskGroupDocument.jl`, `TaskDocument.jl`, `ProgramTask.jl`, `ImitatedProcess.jl`; `platform/systemprocess/SystemProcessSync.jl`, `SystemProcessDocument.jl`, `SystemProcessProgram.jl`; `platform/fileformat/DocumentFile.jl`; `platform/filesystem/FileSystemDocument.jl`, `WorkspaceFileList.jl`; `platform/style/Image.jl`; `platform/clipboard/Clipboard.jl`; `platform/conversation/Evaluator.jl`; `platform/display/EditorDisplay.jl`; `platform/domain/DocumentRelease.jl`; `domain/formula/FormulaComputation.jl`; `domain/git/GitRange.jl`, `GitRead.jl`; `domain/process/ProcessDebug.jl`; `adapter/mcp/McpServer.jl`; `adapter/acp/AcpUpdate.jl`; `adapter/languageserver/LanguageServerSession.jl`, `LanguageServerDocument.jl`; the wait and the wake of `backend/sdl/SdlBackend.jl`, `backend/web/WebBackend.jl`, `backend/console/ConsoleBackend.jl`, `backend/sdl/SystemColorQuery.jl`. Of the plans: the heads of the four plans that the task names, `plan/done/an-answer-streams-in-without-holding-the-window.md`, `plan/done/a-terminal-runs-a-program-in-the-editor.md`, decision D9 and D12 of `plan/done/the-editor-always-answers-the-person.md`, group 7 of `plan/pending/kernel-audit-fixes.md`, and the headings of `plan/pending/kernel-audit/20-agent.md`, `21-feed.md`, `22-editor.md`.

I ran no Julia. Each claim below comes from the text of the code.

## State

The receiving side is sound. One task owns the cells of an editor, and the engine takes no lock. A frame takes each inflow at one fixed place. The wake is one atomic flag. A code unit and background work share one stop. The background cell is the strongest part: seven slices use it in the same way, and it follows the first principle that a value is computed when a view needs it.

The sending side is the weakness. The documents name seven means, but the code that feeds them is written by hand at each site. About 40 lines start a task directly, and each one chooses its thread, its error report and its end. A stream has three doors to the loop, and one stream that uses two of them keeps its order by hand. A value that is read off the loop is built six ways, although a done plan started to move them all to the background cell. A value that is sampled at an interval has no general form, so three feeds drive the same sampler. A child process is run five ways. The feed layer of the kernel is a contract of 62 lines with no store, so each feed has its own lock, wake list and rate limit.

None of this breaks a rule of the single owner. It makes each new producer repeat four or five decisions, and it makes some parts work only in the places where a feed happens to drive them.

## Inventory

### Table 1. The means by which data reaches the owner task

The owner task is the task that reads and writes the cells of an editor: the loop, or a running code unit.

| # | Means | The function | Sites | Named in communication-anatomy.md |
| --- | --- | --- | --- | --- |
| M1 | A post of a typed operation | `post_operation!` ([Inbox.jl:32](../../../source/kernel/editor/Inbox.jl#L32)) | 12 direct call sites | yes |
| M2 | A call: a closure that runs on the owner | `run_on_editor_task!` ([Inbox.jl:201](../../../source/kernel/editor/Inbox.jl#L201)) | about 180 call sites outside the file that defines it (the check counted 182 lines, a few of them in docstrings): about 91 are verbs that pass their own name as `description`, 35 are their `make_change` twins, 29 pass `wait = false` | yes |
| M3 | A feed: a store, a wake and a drain | `drain_changes!` ([FeedInterface.jl:41](../../../source/kernel/feed/FeedInterface.jl#L41)) | 10 feeds, with 8 shapes of store (Table 3) | yes |
| M4 | A background cell | `make_background_cell` ([BackgroundCells.jl:227](../../../source/kernel/editor/BackgroundCells.jl#L227)) | 10 call sites in 7 files | yes |
| M5 | A read that an operation starts | `start_document_read!` ([DocumentRead.jl:33](../../../source/platform/domain/DocumentRead.jl#L33)) | 2 call sites | yes |
| M6 | The event queue of the backend, with a slot of the backend | `wake_backend!`; the system colours go this way ([SystemColorQuery.jl:52](../../../source/backend/sdl/SystemColorQuery.jl#L52)) | 1 | partly |
| M7 | The formula queue and two calls for each formula | `_FormulaComputer` ([FormulaComputation.jl:90](../../../source/domain/formula/FormulaComputation.jl#L90)) | 1 | yes, as a form of M4 |
| M8 | A slot under a lock that the next drain reads | `ReflectionFeed.read` ([ReflectionFeed.jl:52](../../../source/platform/reflection/ReflectionFeed.jl#L52)); `_SystemProcessSampler.result` ([SystemProcessDocument.jl:121](../../../source/platform/systemprocess/SystemProcessDocument.jl#L121)) | 2 | no: the document lists them as feeds |
| M9 | A timer of the operating system that makes a call | `_start_refresh_timer` ([EditorDisplay.jl:158](../../../source/platform/display/EditorDisplay.jl#L158)) | 1 | no |
| M10 | "No loop runs, so apply here": a branch at the site | `is_editor_loop_running` | 9 uses | no |

### Table 2. Each site that starts a task, a timer, a process or a watcher

"Door" is the way of the result to the owner task. "stderr" means `errormonitor`: Julia prints the failure to the error stream, and neither the fault store nor the message log gets it.

| Site | Slice | What it does | Door | Cancel | Error report | When the editor closes |
| --- | --- | --- | --- | --- | --- | --- |
| [EditorLoop.jl:491](../../../source/kernel/editor/EditorLoop.jl#L491) | kernel/editor | the loop task | it is the owner | `QuitEditorException` | stderr | it is the close |
| [HeldFrames.jl:74](../../../source/kernel/editor/HeldFrames.jl#L74) | kernel/editor | a code unit on its own thread | owns the cells; `fetch` | `stop_code_unit!`: flag and stop steps | thrown again at the caller | the unit runs on and keeps the cells |
| [BackgroundWork.jl:99](../../../source/kernel/tool/BackgroundWork.jl#L99) | kernel/tool | `start_background_work`: a task of the default pool, or a sticky task | M2 | `stop_background_work!` | kept in the task until a `fetch` | nothing stops it; no list holds it |
| [BackgroundCells.jl:328](../../../source/kernel/editor/BackgroundCells.jl#L328) | kernel/editor | the work of a `BackgroundSource` | M1, `WriteBackgroundAnswersOperation` | none; a new input makes a new demand | the failure is the answer of the cell | the post is dropped ([:344](../../../source/kernel/editor/BackgroundCells.jl#L344)) |
| [EditorLoop.jl:262](../../../source/kernel/editor/EditorLoop.jl#L262) | kernel/editor | the start of the MCP server | none | none | stderr | waits 10 s, then stops the server |
| [MeaningSearch.jl:213](../../../source/kernel/tool/MeaningSearch.jl#L213), [:296](../../../source/kernel/tool/MeaningSearch.jl#L296) | kernel/tool | the build of meaning vectors | a store of the process under a lock | none | kept in the store, or `@warn` | runs on (a value of the process) |
| [FileChangeStore.jl:304](../../../source/platform/filechange/FileChangeStore.jl#L304), [:307](../../../source/platform/filechange/FileChangeStore.jl#L307) | platform/filechange | a watcher of a folder: a monitor of the system, or a poll with `sleep` | M3, a set of changed paths | the close of the monitor | stderr | a stop step closes the store |
| [TaskGroup.jl:475](../../../source/platform/task/TaskGroup.jl#L475), [:702](../../../source/platform/task/TaskGroup.jl#L702); [TaskExecution.jl:512](../../../source/platform/task/TaskExecution.jl#L512)–[514](../../../source/platform/task/TaskExecution.jl#L514) | platform/task | the scheduler of a group; two readers of a process by line; a sampler of `/proc` with `sleep(0.25)` | M3: a native struct under a lock, a listener, a list of changed entries, a drain each 0.25 s | `SIGINT` to the process group | stderr, `@warn`, `@error` | the entries are dropped; the processes run on |
| [ProgramTask.jl:115](../../../source/platform/task/ProgramTask.jl#L115) | platform/task | a `Timer` for the time limit of a program | stops the execution | closed at the end | none | none |
| [TerminalProcess.jl:47](../../../source/platform/terminal/TerminalProcess.jl#L47)–[56](../../../source/platform/terminal/TerminalProcess.jl#L56) | platform/terminal | a process with standard input; two readers by chunk | M2 with `wait = false`, one for each chunk | `SIGINT`, then `SIGKILL`; at release `SIGTERM` and a `Timer` of 3 s ([:206](../../../source/platform/terminal/TerminalProcess.jl#L206)) | stderr | `atexit` of the process kills the groups of a set of the process ([:215](../../../source/platform/terminal/TerminalProcess.jl#L215)) |
| [ReflectionFeed.jl:87](../../../source/platform/reflection/ReflectionFeed.jl#L87) | platform/reflection | a read of a value along its open nodes | M8 and a wake | none | thrown in the next drain | nothing |
| [SystemProcessSync.jl:154](../../../source/platform/systemprocess/SystemProcessSync.jl#L154) | platform/systemprocess | a read of `/proc` | M8, no wake, a deadline | none | `@warn` | nothing |
| [DocumentRead.jl:38](../../../source/platform/domain/DocumentRead.jl#L38), [:43](../../../source/platform/domain/DocumentRead.jl#L43) | platform/domain | a read for an operation; the owner waits up to 50 ms | M5: evaluate at once, or M1 | none | the exception is the answer | the post is dropped |
| [Clipboard.jl:166](../../../source/platform/clipboard/Clipboard.jl#L166), [:29](../../../source/platform/clipboard/Clipboard.jl#L29) | platform/clipboard | a chain of write tasks of the process; a tool with a limit of 2 s | none | `kill` at the limit | dropped | nothing |
| [AssistantTurn.jl:343](../../../source/platform/assistant/AssistantTurn.jl#L343) | platform/assistant | a turn of the built-in assistant, as background work | M3 for events (a queue of the turn) and M2 for steps | `AssistantTurnControl`; the work is found in `_TURN_WORKS`, a table of the process ([:135](../../../source/platform/assistant/AssistantTurn.jl#L135)) | caught: a fault through M2, `@error`, a line in the chat | nothing stops it |
| [ExternalAgentTurn.jl:109](../../../source/platform/assistant/ExternalAgentTurn.jl#L109), [:483](../../../source/platform/assistant/ExternalAgentTurn.jl#L483), [:615](../../../source/platform/assistant/ExternalAgentTurn.jl#L615), [:649](../../../source/platform/assistant/ExternalAgentTurn.jl#L649), [:681](../../../source/platform/assistant/ExternalAgentTurn.jl#L681), [:727](../../../source/platform/assistant/ExternalAgentTurn.jl#L727) | platform/assistant | a request to an agent: cancel, steer, start, sign out, set an option, stop | M2 with `wait = false` | none | stderr, or `@warn` | a stop step waits up to 10 s for the stops |
| [AgentWorkDocument.jl:253](../../../source/platform/assistant/AgentWorkDocument.jl#L253), [AgentWorkToWidget.jl:172](../../../source/platform/assistant/AgentWorkToWidget.jl#L172) | platform/assistant | a stop or a cancel sent to an agent | M2 with `wait = false` | none | `@warn` | nothing |
| [AssistantWake.jl:46](../../../source/platform/assistant/AssistantWake.jl#L46), [TaskGroupDocument.jl:485](../../../source/platform/task/TaskGroupDocument.jl#L485), [AgentTerminal.jl:113](../../../source/platform/assistant/AgentTerminal.jl#L113) | assistant, task | a waiter for the end of a group or of a task | M2 with `wait = false`, M1, or a reply function | none | stderr | catches `InvalidStateException` |
| [AcpUpdate.jl:43](../../../source/adapter/acp/AcpUpdate.jl#L43), [AcpConnection.jl:208](../../../source/adapter/acp/AcpConnection.jl#L208) | adapter/acp | a task that gives the events of a prompt from a `Channel` with no bound; the agent in this process | M3 through `AgentEventQueue` | the close of the channel | `@warn` for each event; stderr | with the agent |
| [McpServer.jl:148](../../../source/adapter/mcp/McpServer.jl#L148), [:388](../../../source/adapter/mcp/McpServer.jl#L388) | adapter/mcp | the server task; a tool that reads no document on the default pool | M2 for a tool call; a store of the process for the log | the works of the calls in `mcp.running.works` | a fault through M2 | `stop_mcp!` at the end of the loop |
| [LanguageServerConnection.jl:182](../../../source/adapter/languageserver/LanguageServerConnection.jl#L182), [:195](../../../source/adapter/languageserver/LanguageServerConnection.jl#L195), [:258](../../../source/adapter/languageserver/LanguageServerConnection.jl#L258); [LanguageServerDocument.jl:220](../../../source/adapter/languageserver/LanguageServerDocument.jl#L220) | adapter/languageserver | a process; a reader of answers; a `Timer` for each request; the close of a file | a `Channel` for each request, inside the work of M4 | `shutdown`, then `kill` of the leader | stderr | a stop step stops the servers |
| [FormulaComputation.jl:111](../../../source/domain/formula/FormulaComputation.jl#L111) | domain/formula | the formula task: one formula after the other | M7 | none | `@warn`, and the task stops | a call throws, and the task stops |
| [Evaluator.jl:593](../../../source/platform/conversation/Evaluator.jl#L593) | platform/conversation | the evaluation of a form | M2 with `wait = false` | the work is found in `session.works` | the text of the result | nothing |
| [EditorDisplay.jl:158](../../../source/platform/display/EditorDisplay.jl#L158) | platform/display | a `Timer` with an interval that refreshes the shown values | M9 | the close of the session | none | the session closes it |
| [ProcessDebug.jl:98](../../../source/domain/process/ProcessDebug.jl#L98) | domain/process | the run of a model of a person | its trace, which a sync copies | a stop exception at a step | none | nothing |
| [WebBackend.jl:804](../../../source/backend/web/WebBackend.jl#L804), [ConsoleBackend.jl:55](../../../source/backend/console/ConsoleBackend.jl#L55), [SystemColorQuery.jl:42](../../../source/backend/sdl/SystemColorQuery.jl#L42) | backends | a send task; a reader of the terminal; a query of the system colours | M6 | the quit of the backend | none | the quit of the backend |

Counts over `source/`, without the builder tool: 40 lines start a task directly, outside the kernel functions that are the means themselves. 22 of them use `errormonitor`. 8 call sites use `start_background_work`. 5 sites catch `InvalidStateException` for a post after the end of the loop. 4 sites pass `is_sticky = !is_editor_loop_running(editor)`. 4 tables keep running works by hand.

### Table 3. The stores of the feeds

| Feed | Store | Shape | Lock | Wake | Rate limit | Sources at run time | Found by |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `InboxFeed` | two `Channel`s of the editor | queue, bound 64 | channel | `wake_editor!` | 64 for each drain | none | a field |
| `MessageLogFeed` | `MessageLogStore` ([MessageLogStore.jl:19](../../../source/platform/log/MessageLogStore.jl#L19)) | numbered ring, a cursor for each reader | yes | `IdDict` of wakes | none | none | a constant of the process |
| `McpLogFeed` | `McpLogStore` ([McpLogStore.jl:18](../../../source/platform/mcplog/McpLogStore.jl#L18)) | the same | yes | `IdDict` of wakes | none | none | a constant of the process |
| `FileChangeFeed` | `FileChangeStore` | two sets of changed paths | yes | `Vector` of wakes | none | `watch_document_file!`, `watch_folder!` | a search of `editor.feeds` by type ([FileChangeStore.jl:85](../../../source/platform/filechange/FileChangeStore.jl#L85)) |
| `TaskFeed` | `TaskFeedStore` | a list of changed entries | yes | none | `flush_interval`, `now`, `flushed_at` | `register_task_execution!` | a constant of the process, filtered by editor |
| `AgentEventFeed` | an `AgentEventQueue` for each source | queue with no bound | yes | `wake_editor!` at the site | 0.25 s while work runs | `_add_agent_event_source!` | a search by type ([AgentEventFeed.jl:672](../../../source/platform/assistant/AgentEventFeed.jl#L672)) |
| `ReflectionFeed` | fields of the feed | one slot | yes | a field | `interval`, `now`, `synced_at`, `is_sync_skipped` | fixed when the editor is made | none |
| `SystemProcessFeed` | a sampler in each tree | one slot | yes | none | `interval`, `started_at` | `push!` into `feed.trees` | a search by type ([SystemProcessProgram.jl:41](../../../source/platform/systemprocess/SystemProcessProgram.jl#L41)) |
| `FrameStatisticsFeed` | a ring of the editor | ring | none: owner only | none | `flush_interval`, `now`, two times | none | a field |
| `BackgroundWorkFeed` | a session document | records and a change count | none: owner only | none | `flush_interval`, `now`, `flushed_at` | none | `get_session_document!` |

### Table 4. A value that is read off the loop and comes back

| Mechanism | What starts it | The inputs | The task | The answer | An old answer | The mark while it runs | With no loop |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Background cell | a read by a computation | the `inputs` computation | `start_background_work`, one for each source and frame | an operation through the inbox | dropped by the demand number | the `working` cell, and the provisional state | `wait_for_cell!` computes on the calling task |
| `start_document_read!` | the evaluation of an operation | the caller | a raw `Threads.@spawn`; the owner waits up to 50 ms | evaluated at once, or posted | the check of the caller | a field of the caller | the read runs at once |
| Formula task | `ComputeFormulasOperation` | a call to the owner | `start_background_work`, one task, a queue | a call to the owner | dropped by `key` | `is_computing` | computed at once |
| `ReflectionFeed` | a drain, by an interval or a request | made in the drain | a raw spawn | a slot; the next drain writes it | one read at a time | `reading` | none |
| System process sampler | a drain while a view reads `roots` | made in the drain | a raw spawn | a slot; the next drain syncs it | one read at a time | `reading` | none |
| "A task, then a call", by hand | an operation or a press | the caller | `errormonitor(@async …)` or `start_background_work` | `run_on_editor_task!(…; wait = false)` | none | a field of the caller | `is_sticky` |

### Table 5. A child process

| Capability | Terminal ([TerminalProcess.jl](../../../source/platform/terminal/TerminalProcess.jl)) | Task ([TaskExecution.jl:477](../../../source/platform/task/TaskExecution.jl#L477)) | Language server ([LanguageServerConnection.jl:171](../../../source/adapter/languageserver/LanguageServerConnection.jl#L171)) | Clipboard tool ([Clipboard.jl:26](../../../source/platform/clipboard/Clipboard.jl#L26)) | Colour query ([SystemColorQuery.jl:204](../../../source/backend/sdl/SystemColorQuery.jl#L204)) | Git read ([GitRead.jl:27](../../../source/domain/git/GitRead.jl#L27)) |
| --- | --- | --- | --- | --- | --- | --- |
| A process group of its own | yes | yes | yes | no | no | no |
| Standard input | yes | no | yes | for a write | no | no |
| Output read | by chunk, both streams | by line, both streams | by message; the error stream is dropped | whole | whole | whole |
| Output kept in a file | no | yes | no | no | no | no |
| Way of the output to a document | a call for each chunk | a feed each 0.25 s | the answer of a background cell | the answer of `start_document_read!` | a slot of the backend | the answer of a background cell |
| Stop | `SIGINT`, then `SIGKILL` | `SIGINT` only | `shutdown`, then `kill` of the leader | `kill` at 2 s | `kill` at a limit | none |
| Time limit | no | a `Timer` | for each request | 2 s | yes | no |
| Ended at the exit of the process | yes, `atexit` | no | no | not needed | not needed | not needed |
| Ended at the end of the loop | no | no | yes, a stop step | not needed | not needed | not needed |
| A stand-in for a test | no | `ImitatedProcess` | streams in place of a process | a writer function | a function | no |
| Samples of processor and memory | no | yes | no | no | no | no |

### Table 6. The ways to wait

| Who waits | Way | Sites |
| --- | --- | --- |
| The loop | the wait of the backend with the timeout of `compute_wait_timeout` ([Feeds.jl:44](../../../source/kernel/editor/Feeds.jl#L44)) | 1 |
| The loop | the clock: 1/30 s while any cell reads it ([Feeds.jl:45](../../../source/kernel/editor/Feeds.jl#L45)) | readers in 3 assistant labels and in the widget animations |
| The loop | a named timer: `SetTimerOperation`, then `TimerExpire` | only the gesture recognitions |
| The loop | the deadline of a feed: `compute_wake_deadline` | 6 feeds, each with its own interval fields |
| The owner, inside an operation | `timedwait` for a read, 50 ms ([DocumentRead.jl:39](../../../source/platform/domain/DocumentRead.jl#L39)) | 1 |
| Another task | a `Timer` of the operating system | 8 in the editor packages |
| Another task | a loop with `sleep` | the poll of a folder, the sampler of a task, the settle of a file, `wait_for_cell!`, the build of vectors |
| Another task | `timedwait` | 10 in the editor packages |
| A backend | a `Base.Event` gate with a `Timer`: `_wait_for_gate`, the same function in [WebBackend.jl:917](../../../source/backend/web/WebBackend.jl#L917) and [ConsoleBackend.jl:130](../../../source/backend/console/ConsoleBackend.jl#L130); the default of the kernel sleeps 10 ms | 2 copies |

The three ways of the loop have different jobs. Only the feed deadline is repeated by hand.

## Findings

### CC-1 A stream has three doors to the loop, and one stream keeps its order by hand

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 3 (an edit is a typed operation, and there is one way to edit); PAR-STORE-THEN-DRAIN ("The inbox is the queue-shaped case of the same rule, for a payload that is an edit: ordered, applied exactly once, with backpressure"); 7 (generic before special).
- **Today:** A task that is not the owner has three doors for a write with no answer.
  - Door A: `post_operation!` puts a typed operation into the inbox. The drain applies it in place. 12 call sites use it.
  - Door B: `run_on_editor_task!(f, editor; wait = false)` puts a closure into the inbox, as a `RunFunctionOperation`. 29 call sites use it. One such operation makes the whole drain a code unit, which runs on another thread while the loop runs held frames ([Inbox.jl:102](../../../source/kernel/editor/Inbox.jl#L102)–[110](../../../source/kernel/editor/Inbox.jl#L110)).
  - Door C: a queue of the slice, a wake and a feed. `AgentEventQueue` is a lock and a vector ([AgentConnectionEvent.jl:495](../../../source/kernel/agent/AgentConnectionEvent.jl#L495)). `AgentEventFeed` keeps a list of such queues ([AgentEventFeed.jl:650](../../../source/platform/assistant/AgentEventFeed.jl#L650)).
  - A frame drains the inbox first and each feed after it ([Editor.jl:199](../../../source/kernel/editor/Editor.jl#L199), [Feeds.jl:244](../../../source/kernel/editor/Feeds.jl#L244)). So an event in door C that came before a closure in door B applies after it.
  - A turn of the assistant uses door C for its events and door B for its steps. To keep the order, five places drain the queue by hand inside a call: [AgentEventFeed.jl:158](../../../source/platform/assistant/AgentEventFeed.jl#L158), [:171](../../../source/platform/assistant/AgentEventFeed.jl#L171), [:190](../../../source/platform/assistant/AgentEventFeed.jl#L190), [:253](../../../source/platform/assistant/AgentEventFeed.jl#L253) and `_run_turn_call!` at [:284](../../../source/platform/assistant/AgentEventFeed.jl#L284), which [AssistantTurn.jl:952](../../../source/platform/assistant/AssistantTurn.jl#L952)–[995](../../../source/platform/assistant/AssistantTurn.jl#L995) calls five times.
  - The terminal uses door B for each chunk of output ([TerminalProcess.jl:45](../../../source/platform/terminal/TerminalProcess.jl#L45)–[48](../../../source/platform/terminal/TerminalProcess.jl#L48)). So do the result of a form ([Evaluator.jl:658](../../../source/platform/conversation/Evaluator.jl#L658)) and a fault from another task ([McpServer.jl:318](../../../source/adapter/mcp/McpServer.jl#L318), [AssistantTurn.jl:358](../../../source/platform/assistant/AssistantTurn.jl#L358)).
  - The cost of door B already moved one producer. The done plan `an-answer-streams-in-without-holding-the-window.md` measured a median frame of 47.92 ms with one code unit for each delta, and moved the turn to door C. The message of commit `d789a359d` gives the same reason for the typed operation that [Application.jl:618](../../../source/platform/application/Application.jl#L618) posts: "a RunFunctionOperation would run the whole first drain as a code unit".
  - The ACP adapter adds a fourth queue in front of door C: a `Channel` with no bound and a task that empties it ([AcpUpdate.jl:34](../../../source/adapter/acp/AcpUpdate.jl#L34)–[43](../../../source/adapter/acp/AcpUpdate.jl#L43)).
- **Example:**
  ```julia
  # Today: one stream, two doors, and a drain by hand.
  put_agent_event!(source.queue, event); wake_editor!(editor)           # door C
  run_on_editor_task!(editor) do                                         # door B
      _drain_agent_event_source!(editor, source)                         # keeps the order
      build_messages(a.conversation; until = turn)
  end
  run_on_editor_task!(() -> add_terminal_text!(terminal, :output, text), editor; wait = false)  # a code unit

  # After: one queue, in the order of the posts.
  post_operation!(editor, ApplyAgentEventOperation(assistant, turn, event))
  run_on_editor_task!(() -> build_messages(a.conversation; until = turn), editor)
  post_operation!(editor, AddTerminalTextOperation(terminal, :output, text))
  ```
- **Problem:** A producer must choose a door, and each door has another cost and another place in the frame. Doors B and C do not combine: a stream that needs both an ordered event and an answer must drain its own queue inside each call. The next stream, such as the output of a debugger or of a language server, must make the same choice and the same repair. A small write through door B pays a thread change and held frames.
- **Proposal:** The inbox is the one ordered door for a stream.
  1. A producer posts typed operations. The drain applies them in place, in the order of the posts.
  2. Only a call that waits for an answer runs as a code unit: a tool call, or a verb from another task. A post with no answer is an operation. Most of the 29 closures are writes of one to three lines.
  3. An operation type can say that two neighbours in one drain join, which is the job of `_join_stream_deltas` ([AgentEventFeed.jl:261](../../../source/platform/assistant/AgentEventFeed.jl#L261)).
  4. The agent layer of the kernel still names no editor: the open of a session and a prompt take the post function, as a store takes its wake.
  5. A feed stays for a state that is synced and has no order: the tasks, the marks of changed files, the statistics.
- **What goes away:** `AgentEventQueue` with its two functions; the queue in `_TurnEventSource`; the list `AgentEventFeed.sources` with its add, its remove and `_is_agent_event_source_open`; the five drains by hand and `_run_turn_call!`; the two "no loop" branches of `_post_agent_event!` and `_post_turn_event!`; one code unit for each chunk of a terminal. Roughly 200 lines, and one concept.
- **What stays:** The order of a stream. One append for the deltas of one frame. No held frame for an event. The stop of a turn. A test with no loop, if a post with no loop applies at once, as a call does today.
- **Risk and open questions:**
  - The inbox holds 64 operations, and a full inbox makes the producer wait. For a stream of a model this is the purpose of the bound. A reader of ACP that holds a lock must not wait, so its outbox may have to stay.
  - A posted operation that is slow holds the frame. The contract is the one of a drain: prepared data only (PAR-DRAIN-MOVES-PREPARED-DATA).
  - The change gives `wait = false` another meaning, so it is a change of a mechanism and needs the word of the owner. It revisits point 1 of the model of `an-answer-streams-in-without-holding-the-window.md` ("A turn is a producer of a feed").
  - A post when no loop runs is defined today (corrected by the check): it goes to the queue of the owner, which has no bound, and the first drain takes it (the docstring of `post_operation!`, [Inbox.jl:12](../../../source/kernel/editor/Inbox.jl#L12)–[31](../../../source/kernel/editor/Inbox.jl#L31)). Three sites rely on that: [Application.jl:618](../../../source/platform/application/Application.jl#L618), [Application.jl:911](../../../source/platform/application/Application.jl#L911) and [PaneTabsWrapper.jl:65](../../../source/platform/pane/PaneTabsWrapper.jl#L65). So "a post with no loop applies at once" is a change of that rule, and a post in a test with no loop is applied by no drain.
- **Related plans:** `plan/done/an-answer-streams-in-without-holding-the-window.md` (done; made the queue of a turn). `plan/done/the-assistant-shows-the-work-of-its-agent.md` (done; made `AgentEventQueue`). `plan/pending/guards-keep-the-frame-short-at-any-size.md` (in progress; it measures a burst of calls and the terminal, and changes no door).
- **Check:** weakened. Value after the check: medium. The facts hold. I counted 12 direct posts and 29 calls with `wait = false`, and I read `drain_operations!` (one `RunFunctionOperation` makes the whole drain a code unit), the order of `drain_feeds!` (the inbox first) and the five drains by hand. The prompt of an external agent has the same repair ([ExternalAgentTurn.jl:161](../../../source/platform/assistant/ExternalAgentTurn.jl#L161)–[199](../../../source/platform/assistant/ExternalAgentTurn.jl#L199)), so two streams keep their order by hand, not one. Four points weaken the proposal.
  - The feed is the documented door of a stream. `communication-anatomy.md`, "Choose a means for a new part", gives "a stream of data from a task of its own" to a feed. The owner approved the model "A turn is a producer of a feed" on 2026-10-21, with the rule "Add no event type, no payload and no channel". Point 3, the join of two neighbours in a drain, is a new mechanism of the inbox.
  - `AgentEventQueue` can not go away. The ACP adapter puts the events of a session between two prompts, and the events that waited for an open, into the queue under `turns_lock` ([AcpConnection.jl:309](../../../source/adapter/acp/AcpConnection.jl#L309)–[322](../../../source/adapter/acp/AcpConnection.jl#L322), [:866](../../../source/adapter/acp/AcpConnection.jl#L866)). That put must never wait, and a post waits when the inbox holds 64 operations. A queue with no bound and a task that empties it would take its place, so the count of queues stays the same.
  - A burst gets worse. A feed applies its whole queue in one frame, so the replay of a resumed session is one print. The inbox applies at most 64 operations for each frame, so 10 000 events are about 157 frames, each with a print.
  - The case of no loop: see the corrected risk above. The two "no loop" branches stay in some form, because a test with no loop must see each event at once.
  - What holds with none of these costs is point 2 alone: a post of platform code that waits for no answer is a typed operation and not a closure. Then the chunks of a terminal and the steps of a prompt make no code unit. It needs about 20 new operation types. The measured cost of today is small: the guards plan found the frames of a terminal flat on the headless backend ("Seen, not broken: the terminal").

### CC-2 A value that is read off the loop is built six ways

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** medium
- **Principle:** 1 (who needs a value computes it and stores it; only what is visible is computed); 7; the owner on 2026-10-18, quoted in `plan/done/a-value-that-a-task-reads-is-a-cell.md`: "this should be a kernel service".
- **Today:** Table 4 has six rows. The done plan listed six hand-made reads and said: "The other five reads of the table move one at a time after the pilot, each in a plan of its own." The listing of a folder moved. No pending plan names the others. (Corrected by the check: the six reads of the plan are not the six rows of Table 4. Two of them are in this repository: the listing of a folder, which moved, and the values of formulas, which did not. The other four are in the downstream simulator, whose files use `make_background_cell` now. The plan does not name `start_document_read!`, `ReflectionFeed`, the process sampler or the hand-made sites as reads to move.)
  - The formula task keeps a queue under a lock in a session document, and makes two calls to the owner for each formula ([FormulaComputation.jl:90](../../../source/domain/formula/FormulaComputation.jl#L90)–[151](../../../source/domain/formula/FormulaComputation.jl#L151)). Its parts are those of a background cell: inputs read on the owner, work off the loop, an operation with a key that drops an old answer ([:221](../../../source/domain/formula/FormulaComputation.jl#L221)), and a mark `is_computing`.
  - `start_document_read!` starts a raw task and makes the owner wait up to 50 ms in the evaluation of an operation ([DocumentRead.jl:38](../../../source/platform/domain/DocumentRead.jl#L38)–[43](../../../source/platform/domain/DocumentRead.jl#L43)). It has two callers: the check whether a sub-folder is empty ([FileSystemDocument.jl:691](../../../source/platform/filesystem/FileSystemDocument.jl#L691)) and the paste ([ClipboardSliceToAny.jl:226](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L226)). Its post after the end of the loop repeats the one of the background cell ([DocumentRead.jl:60](../../../source/platform/domain/DocumentRead.jl#L60), [BackgroundCells.jl:344](../../../source/kernel/editor/BackgroundCells.jl#L344)).
  - `ReflectionFeed` and the sampler of a process tree each keep a task, a lock and a slot for one answer ([ReflectionFeed.jl:50](../../../source/platform/reflection/ReflectionFeed.jl#L50)–[53](../../../source/platform/reflection/ReflectionFeed.jl#L53), [SystemProcessDocument.jl:121](../../../source/platform/systemprocess/SystemProcessDocument.jl#L121)–[128](../../../source/platform/systemprocess/SystemProcessDocument.jl#L128)).
  - At least eight sites write "start a task, call outside, then post or call with `wait = false`" by hand (the last row of Table 4 and its rows in Table 2), such as [ExternalAgentTurn.jl:649](../../../source/platform/assistant/ExternalAgentTurn.jl#L649)–[659](../../../source/platform/assistant/ExternalAgentTurn.jl#L659) and [AgentWorkDocument.jl:238](../../../source/platform/assistant/AgentWorkDocument.jl#L238)–[254](../../../source/platform/assistant/AgentWorkDocument.jl#L254).
- **Example:**
  ```julia
  # Today, the formula task:
  computer = get_session_document!(_FormulaComputer, editor, _FormulaComputer)   # lock, queue, task
  job = run_on_editor_task!(() -> _make_formula_job(formula, env), editor; timeout = Inf)
  value = _run_formula_job(computer.scratch, job)
  run_on_editor_task!(editor; timeout = Inf) do
      evaluate_operation(editor, ReplaceFormulaResultOperation(formula, env, value, job.key))
  end

  # After, the same parts from the kernel:
  make_background_cell(FORMULA_SOURCE, () -> make_formula_inputs(formula, env);
                       working = getfield(formula, :is_computing),
                       apply = (inputs, value) -> ReplaceFormulaResultOperation(formula, env, value))
  ```
- **Problem:** Each form has its own answer to the same questions: which task, what an old answer does, what the view shows meanwhile, what happens with no loop, and where a failure goes. Only the background cell shows its work in the log of the background work. The 50 ms wait of `start_document_read!` runs on the owner task, and the pending plan of the frame guards names it as a cause of long frames.
- **Proposal:** Two forms, both from the kernel.
  1. A value that a view reads is a background cell: the value of a formula, the emptiness of a sub-folder, the snapshot of a reflected value, the records of a process tree.
  2. A read that an operation starts, such as the paste, keeps `start_document_read!`. It is built on `start_background_work` and posts its operation, with the one helper that drops a post after the end of the loop. The hand-made "task, then a call" sites use it.
- **What goes away:** `_FormulaComputer`, `_queue_formulas!`, `_run_formula_task!` and the key check, about 70 lines. The slot, the lock and the task of `ReflectionFeed` and of `_SystemProcessSampler`. The raw spawn and the second post helper of `DocumentRead.jl`. The hand-made task blocks of the last row of Table 4.
- **What stays:** A formula keeps its stored value in the document, through `apply`. It still computes off the loop and one after the other, because one source runs one work for each frame. A paste still lands when the clipboard answers. A chevron of a reflected tree still opens its node.
- **Risk and open questions:**
  - The owner decided on 2026-10-13 (D8 of `the-editor-always-answers-the-person.md`) that a formula computes at a commit, at a load, or at a new value of a formula that it names, and never on a key. Each of the three is a change of an input, so a background cell keeps them. It adds one condition: a formula that no view reads is not computed. The owner must say whether that is wanted.
  - The order of formulas that name each other comes from provisional inputs: a cell whose inputs are provisional records no demand. A cycle needs a check.
  - The short wait of a paste: without it a paste shows one frame later.
- **Related plans:** `plan/done/a-value-that-a-task-reads-is-a-cell.md` (done; names the six reads and leaves five for later plans). `plan/pending/guards-keep-the-frame-short-at-any-size.md` (in progress; measures only).
- **Check:** weakened. Value after the check: medium. Each cited line holds. But the six rows are three jobs, and only the first is the job of a background cell.
  - A value that a view reads: the background cell.
  - A read or an action that an operation starts once: `start_document_read!` and the hand-made sites. The hand-made sites are requests to an agent (sign out, stop a task, cancel) with a note afterwards, and no reads of a value.
  - A poll at an interval: `ReflectionFeed` and the process sampler. The value changes with no change of an input cell, so a background cell can not replace them before it has the period of CC-3. CC-3 counts them too.
  - The formula. The done plan leaves it for "a plan of its own", so the direction is accepted. But D8 (the owner, 2026-10-13) lists "a new kind of cell that computes off the loop" among the options that the model does not need, and chose "each start is an operation of the formula domain", with the value stored in the document. Today every formula of a sheet computes at a load and at a commit, and `get_formula_result` and the table view read `formula.result` with no demand ([FormulaDocument.jl:828](../../../source/domain/formula/FormulaDocument.jl#L828), [FormulaToTable.jl:60](../../../source/domain/formula/FormulaToTable.jl#L60)). With a background cell, a formula that no view reads keeps an old value, so each such reader must wait for the cell. That changes the model of D8 and needs the owner, as the risk says.
  - The paste. The wait of 50 ms also keeps the order: a key that the frame reads after the paste applies after the pasted text when the clipboard tool answers in time. Without the wait the key applies first.
  - What holds: `start_document_read!` built on `start_background_work` with the one post helper; the emptiness of a sub-folder as a background cell (today that read waits up to 50 ms inside the drain of `FileChangeFeed`); one helper for "a task, then a post".

### CC-3 A value that is sampled at an interval has no general form

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 1 (only what is visible is computed); 6 (no central walker); 7 (a missing case gets its row in the generic mechanism).
- **Today:**
  - `drain_system_process_tree!` samples a tree of processes once a second while a view reads it ([SystemProcessSync.jl:128](../../../source/platform/systemprocess/SystemProcessSync.jl#L128)). A tree does not sample itself. Three feeds call the function: `SystemProcessFeed` for the trees in its list ([:206](../../../source/platform/systemprocess/SystemProcessSync.jl#L206)), `TaskFeed` for the tree of a task ([TaskFeed.jl:167](../../../source/platform/task/TaskFeed.jl#L167), [TaskDocument.jl:181](../../../source/platform/task/TaskDocument.jl#L181)), and `AgentEventFeed` for the tree of an agent ([AgentEventFeed.jl:791](../../../source/platform/assistant/AgentEventFeed.jl#L791)).
  - Only `show_system_process_tree!` puts a tree into the list ([SystemProcessProgram.jl:33](../../../source/platform/systemprocess/SystemProcessProgram.jl#L33)), and nothing takes one out. The tree "System processes" of the first content of the explorer is made at [ApplicationExplorer.jl:54](../../../source/platform/application/ApplicationExplorer.jl#L54), and a tree that a file loads is made at [SystemProcessDocument.jl:110](../../../source/platform/systemprocess/SystemProcessDocument.jl#L110). I found no code that puts either into the list, so by the code neither is sampled. I did not run it.
  - The tree of a task is sampled only because the sampler of the task marks the execution as changed four times a second; the docstring says so ([TaskFeed.jl:131](../../../source/platform/task/TaskFeed.jl#L131)–[133](../../../source/platform/task/TaskFeed.jl#L133)).
  - Four feeds repeat the same fields for "at most once in an interval": `TaskFeed` ([TaskFeed.jl:187](../../../source/platform/task/TaskFeed.jl#L187)), `BackgroundWorkFeed` ([BackgroundWorkFeed.jl:23](../../../source/platform/backgroundwork/BackgroundWorkFeed.jl#L23)), `FrameStatisticsFeed` ([FrameStatisticsFeed.jl:37](../../../source/platform/statistics/FrameStatisticsFeed.jl#L37)) and `ReflectionFeed` ([ReflectionFeed.jl:44](../../../source/platform/reflection/ReflectionFeed.jl#L44)). Three probe "does a view read this" with `has_dependent_cells` ([BackgroundWorkFeed.jl:35](../../../source/platform/backgroundwork/BackgroundWorkFeed.jl#L35), [FrameStatisticsFeed.jl:59](../../../source/platform/statistics/FrameStatisticsFeed.jl#L59), [SystemProcessSync.jl:129](../../../source/platform/systemprocess/SystemProcessSync.jl#L129)).
  - The display of a value from the REPL refreshes with a `Timer` of the operating system and a call ([EditorDisplay.jl:158](../../../source/platform/display/EditorDisplay.jl#L158)).
  - The clock has one rate. A label that shows seconds reads it, so the loop runs 30 frames a second while a turn runs ([AssistantListToWidget.jl:98](../../../source/platform/assistant/AssistantListToWidget.jl#L98), [Feeds.jl:45](../../../source/kernel/editor/Feeds.jl#L45)).
- **Example:**
  ```julia
  # Today: a tree follows its processes only where a feed drives it.
  tree = SystemProcessTree([process_id])
  push!(_get_system_process_feed(editor).trees, tree)      # only show_system_process_tree! does this
  # TaskFeed and AgentEventFeed each call drain_system_process_tree! for their own trees.

  # After: the tree asks for its own samples while a view reads it.
  records = make_background_cell(PROCESS_SOURCE, () -> (root_process_ids,); refresh_every = 1.0,
                                 apply = (inputs, records) -> SyncSystemProcessTreeOperation(tree, records))
  ```
- **Problem:** A part that shows sampled state works only where some feed knows it. A new owner of a process tree, such as a card of a dashboard, must find a feed or add one. Each feed that limits its rate writes the same fields and the same test.
- **Proposal:**
  1. A background cell takes a period. When the period of an answered cell has passed and a computation still reads the cell, the cell asks again. The loop takes the nearest such time in `compute_wait_timeout`, beside the timers. The demand is the test for "a view reads it", so no probe is needed.
  2. A feed says its interval once. `drain_feeds!` skips a feed that drained less than an interval ago, and the wait takes the rest of the interval.
  3. As an option, a read of the clock takes a period, so a label of seconds costs one frame a second.
- **What goes away:** `SystemProcessFeed`, its wrapper and its list; the two calls from `TaskFeed` and `AgentEventFeed` with their deadline code ([AgentEventFeed.jl:789](../../../source/platform/assistant/AgentEventFeed.jl#L789)–[809](../../../source/platform/assistant/AgentEventFeed.jl#L809)); `_SystemProcessSampler`; the interval fields of four feeds; three probes; the refresh timer of the display. About 150 lines.
- **What stays:** A tree is read once a second while a view shows it, and never else. The read stays off the loop. The task feed still syncs at most four times a second.
- **Risk and open questions:** A period on a background cell is a new input of a kernel function. The process tree keeps the processor ticks of the last sample in its sampler; they move into the inputs or the document. How a document reaches the clock of its editor is open, so point 3 is an option only.
- **Related plans:** `plan/done/the-feeds-of-an-editor-are-its-own.md` (done; fixed the list of feeds at the make of the editor, which is why a tree needs a list inside a feed). `plan/pending/guards-keep-the-frame-short-at-any-size.md` (in progress; names the four feeds that wake the loop each 0.25 s).
- **Check:** confirmed-with-corrections. Value after the check: medium. I read the three callers of `drain_system_process_tree!` and every use of `feed.trees`. Only `show_system_process_tree!` adds a tree. So by the code nothing samples the tree "System processes" of the explorer or a tree that a file loads; the test of the explorer checks only that the tree is there ([ExplorerTest.jl:1029](../../../test/platform/explorer/ExplorerTest.jl#L1029)). No plan names this gap. I ran nothing either. Corrections:
  - The three callers are a stated design, not an accident: `systemprocess.md`, "The owner drains. The owner of a tree has a feed in its window already. A central registry of trees would need an owner of its own" (written 2026-10-15, three days before the background cell existed). The proposal is no registry, so that reason does not speak against it. The gap shows that the design serves only a tree that has an owner with a feed.
  - "The demand is the test for 'a view reads it', so no probe is needed" does not hold as written. A reader whose value is cached does not read the cell again, so it records no demand when the period ends. The kernel must then look for readers of the cell, which is the same probe once in the kernel, or make the answer old so that a visible reader asks again.
  - Point 2 fits `TaskFeed` and `BackgroundWorkFeed` only. `FrameStatisticsFeed` keeps two flush times, one for the table and one for the plot ([FrameStatisticsFeed.jl:40](../../../source/platform/statistics/FrameStatisticsFeed.jl#L40)). `ReflectionFeed` must drain inside its interval for a request of a chevron and for a read that ended ([ReflectionFeed.jl:75](../../../source/platform/reflection/ReflectionFeed.jl#L75)–[81](../../../source/platform/reflection/ReflectionFeed.jl#L81)). So "the interval fields of four feeds" is the fields of two.
  - Point 1 is a new input of a kernel function and needs the word of the owner. Point 3 is a new feature, which the review does not ask for.

### CC-4 A child process is run five ways

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism; a missing case gets its row); 9 (outside state enters on a task).
- **Today:** Table 5. (Corrected by the check: the table has six columns, not five, and four more sites start a program with no stop and no time limit: `readchomp` of `xrandr` and of `xrdb` at [SdlBackend.jl:64](../../../source/backend/sdl/SdlBackend.jl#L64) and [:956](../../../source/backend/sdl/SdlBackend.jl#L956), and the postprocess of a build step at [BuildStep.jl:263](../../../source/platform/task/BuildStep.jl#L263) and [:304](../../../source/platform/task/BuildStep.jl#L304).) The terminal and the task both start a program in a process group of its own, with two reader tasks.
  - The terminal reads by chunk, has a standard input, stops with `SIGINT` and then `SIGKILL`, and ends its groups at the exit of the process through a set of the process ([TerminalProcess.jl:20](../../../source/platform/terminal/TerminalProcess.jl#L20)–[58](../../../source/platform/terminal/TerminalProcess.jl#L58), [:177](../../../source/platform/terminal/TerminalProcess.jl#L177)–[230](../../../source/platform/terminal/TerminalProcess.jl#L230)).
  - The task reads by line, has no standard input, stops with `SIGINT` only, has a time limit and a file for each stream, and nothing ends its process at the exit ([TaskExecution.jl:477](../../../source/platform/task/TaskExecution.jl#L477)–[560](../../../source/platform/task/TaskExecution.jl#L560), [:372](../../../source/platform/task/TaskExecution.jl#L372)–[396](../../../source/platform/task/TaskExecution.jl#L396)).
  - The plan of the terminal records the reason: the task slice "does not pipe the standard input" and reads "line by line", and "a process is the same kind of thing as a task".
  - The terminal of an agent over ACP is a task and not a terminal ([AgentTerminal.jl:49](../../../source/platform/assistant/AgentTerminal.jl#L49)–[60](../../../source/platform/assistant/AgentTerminal.jl#L60)), so it has no input. The only user of `TerminalDocument` in this repository is the sign-in of an agent ([ExternalAgentTurn.jl:548](../../../source/platform/assistant/ExternalAgentTurn.jl#L548)).
  - "Run a command, read its output, stop it at a time limit" exists twice: `_shell_read` ([Clipboard.jl:26](../../../source/platform/clipboard/Clipboard.jl#L26)) and `_read_command_output` ([SystemColorQuery.jl:204](../../../source/backend/sdl/SystemColorQuery.jl#L204)). The read of git has no limit ([GitRead.jl:27](../../../source/domain/git/GitRead.jl#L27)).
- **Example:**
  ```julia
  # Today: two starts with the same parts.
  process = open(pipeline(addenv(Cmd(command; detach = true), "TERM" => "dumb"); stderr = errors), "r+")   # terminal
  process = run(pipeline(Cmd(command; detach = true); stdout = output, stderr = error_output); wait = false) # task

  # After: one start, and the two views read it.
  process = start_child_process(command; input = true, on_output = (stream, text) -> ...)
  stop_child_process!(process)        # SIGINT, then SIGKILL, and at the end of its editor
  ```
- **Problem:** A capability that one runner has is missing in the other: the input and the chunks in a task, the kill at the exit and the second signal in a task, the time limit and the stand-in for a test in a terminal. The next part that runs a program, such as a debugger, copies one of them. The output of a terminal takes the costly door of CC-1.
- **Proposal:** One runtime for a child process in the platform, in the task slice or beside it: the start in a group, the optional input, readers by chunk that can cut lines, the stop with two signals, the time limit, the end with the editor, and the stand-in for a test. `TerminalDocument` is a view of such a process with an input line. `TaskExecution` uses it and adds the result, the files and the samples. One small function runs a command with a limit and answers its text.
- **What goes away:** The start, the readers, the signals and the set `_RUNNING_GROUPS` of `TerminalProcess.jl`, about 150 lines. One of the two "command with a limit" functions. The start and the `kill` of the language server, about 40 lines.
- **What stays:** A terminal shows a prompt with no line end and takes a line. A task keeps its lines, its files, its result and its group stop. The sign-in of an agent works as now.
- **Risk and open questions:** The SDL backend can not use a function of the platform, so the small function belongs to the kernel, or the backend keeps its copy. The ACP library starts its own process. Whether a task must end with its editor is a choice of the owner: a build can be meant to run on.
- **Related plans:** `plan/done/a-terminal-runs-a-program-in-the-editor.md` (done), `plan/done/the-assistant-starts-programs-as-tasks.md` (done). No pending plan.
- **Check:** confirmed-with-corrections. Value after the check: low. Each row of Table 5 that I opened holds: the terminal, the task, the language server, the clipboard tool, the colour query and the read of git. Corrections:
  - The count, corrected above.
  - Part of the difference has a reason. A task stops with `SIGINT` alone "so a program that catches it can still finish its work" ([TaskExecution.jl:368](../../../source/platform/task/TaskExecution.jl#L368)). The terminal reads by chunk for a prompt with no line end, and a task reads by line for its marks and its files. The language server reads framed messages from the raw streams, so readers by chunk do not serve it. A terminal of the ACP protocol has no input, so "it has no input" names no gap.
  - What is written twice is small: the start in a group, the read of the group id, and the signal to the group, about 40 to 60 lines. The review of the terminal plan already noted it ("`_signal_process_group!` repeats the signal helper of the task slice ... the reviewer passed it to the code quality steward"). The other lines of "what goes away" move into the shared runtime and stay.
  - The capabilities that one runner would get from the other (an input for a task, a second signal, the kill at the exit, a time limit for a terminal) are new features, which the review does not ask for. Whether a task ends with its editor is a choice of the owner, as the risk says.
  - The proposal loses no feature. Its gain is one helper for the group and its signals, which is a matter of code quality more than of architecture.

### CC-5 A task of an editor is started by hand at about 40 places, and no list holds the running work

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 6 (state belongs to an editor); 7; PAR-REPORT-NEVER-THROWS ("a barrier that catches must record").
- **Today:** Table 2 and its counts.
  - `start_background_work` binds the editor of the evaluation and a stop ([BackgroundWork.jl:89](../../../source/kernel/tool/BackgroundWork.jl#L89)). It keeps no list, reports no failure, and knows nothing of the end of the loop. 8 call sites use it. 40 lines start a task with `@async` or `Threads.@spawn`.
  - 22 of the 40 use `errormonitor`. Julia then prints the failure to the error stream. The fault store and the message log do not get it, because the capture of the message log is a logger ([MessageLogCapture.jl:40](../../../source/platform/log/MessageLogCapture.jl#L40)).
  - Four tables keep running works so that a stop can find them: `_TURN_WORKS`, a table of the process ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)); `session.works` ([Evaluator.jl:598](../../../source/platform/conversation/Evaluator.jl#L598)); `computer.task` ([FormulaComputation.jl:93](../../../source/domain/formula/FormulaComputation.jl#L93)); `mcp.running.works` ([McpServer.jl:421](../../../source/adapter/mcp/McpServer.jl#L421)).
  - Four sites pass `parent = nothing, is_sticky = !is_editor_loop_running(editor)` ([AssistantTurn.jl:340](../../../source/platform/assistant/AssistantTurn.jl#L340), [AgentWorkToWidget.jl:172](../../../source/platform/assistant/AgentWorkToWidget.jl#L172), [AgentWorkDocument.jl:253](../../../source/platform/assistant/AgentWorkDocument.jl#L253), [ExternalAgentTurn.jl:615](../../../source/platform/assistant/ExternalAgentTurn.jl#L615)), and the terminal makes the same choice by hand ([TerminalProcess.jl:56](../../../source/platform/terminal/TerminalProcess.jl#L56)).
  - Five sites catch `InvalidStateException` for a post after the end of the loop ([TaskGroupDocument.jl:494](../../../source/platform/task/TaskGroupDocument.jl#L494), [AssistantWake.jl:56](../../../source/platform/assistant/AssistantWake.jl#L56), [DocumentRead.jl:64](../../../source/platform/domain/DocumentRead.jl#L64), [BackgroundCells.jl:348](../../../source/kernel/editor/BackgroundCells.jl#L348), [ApplicationWorkload.jl:307](../../../source/platform/application/ApplicationWorkload.jl#L307)).
  - Six wrappers add a stop step of their own for the end of the loop: for the language servers, the agents, the watchers of files, the assistant list and the two logs (the lines with `stop_steps` in `source/`). Nothing stops a turn, a form, the formula task, a terminal or a task group.
- **Example:**
  ```julia
  # Today:
  errormonitor(@async begin
      try wait(scheduler) catch exception; exception isa TaskFailedException || rethrow() end
      try post_operation!(editor, operation) catch exception; exception isa InvalidStateException || rethrow() end
  end)
  start_background_work(stop; description = "the stop of a background task", editor,
                        parent = nothing, is_sticky = !is_editor_loop_running(editor))

  # After:
  start_background_work(editor; description = "the end of a group") do
      wait(scheduler)
      post_operation!(editor, operation)
  end
  ```
- **Problem:** Each site decides four things again: the thread, the error report, the case of no loop, and the end of the editor. The answers differ with no reason. A failure of a watcher or of a reader shows only in the terminal that started the program. With two editors in one process, the work of a closed editor runs on.
- **Proposal:** `start_background_work` is the one way to start a task for an editor.
  1. The editor keeps its running works in a session document.
  2. A work that fails records a fault through the door.
  3. The function chooses a sticky task when no loop runs, and `parent = nothing` is the default for work that an operation starts.
  4. The end of the loop stops every work of the editor, and a post after the end is dropped in one place.
  5. The log of the background work shows every work, not only the works of background cells.
- **What goes away:** Most of the 22 `errormonitor` lines; the four tables; the five catches; the four keyword pairs; the stop steps that only stop tasks.
- **What stays:** The stop of a turn, of a form and of a tool call. The rule that a code unit does not wait for work that it started.
- **Risk and open questions:** The owner noted in D9 of `the-editor-always-answers-the-person.md` that a visible list of all background work "is not part of it: each user shows its own work". That is a limit of that plan and no decision against a list, but the owner must confirm. A reader task that is waited for needs no record. A stop at the end of the loop can not end code that computes.
- **Related plans:** `plan/done/the-editor-shows-its-background-work.md` (done; says "Nothing keeps a work after its start"). `plan/pending/kernel-audit-fixes.md` L22-14 (pending; the detach of a wake at the end of an editor).
- **Check:** weakened. Value after the check: low. The counts hold: 44 lines start a task, 41 of them outside the three kernel means; 23 use `errormonitor`, 22 outside the kernel; 8 call sites of `start_background_work`; 5 catches; 4 `is_sticky` pairs. About 10 of the lines start no task of an editor: the tasks of the backends, the write chain of the clipboard, the meaning vectors, and the readers of a connection. The proposal keeps or loses more than it says:
  - The four tables are maps by a key: `_TURN_WORKS` by the control of a turn ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)), `session.works` by the form, and the set of one MCP server. A stop needs the work of that turn or that form. A list of all works of an editor does not answer that, so the tables stay unless the list takes a key, which the proposal does not say.
  - None of the six stop steps only stops tasks. They close a store, detach a wake, take a logger back, or stop the process of an agent or of a server. They stay.
  - `parent = nothing` as a default goes against D9b (the owner, 2026-10-14): work that a running unit starts keeps its link to that unit. The function can not tell work that an operation starts from work that model code starts. The signature of D9a was decided as written.
  - The "after" example drops the catch of `TaskFailedException`, so a group whose scheduler failed would post nothing ([TaskGroupDocument.jl:485](../../../source/platform/task/TaskGroupDocument.jl#L485)–[496](../../../source/platform/task/TaskGroupDocument.jl#L496)).
  - `start_background_work` is in the tool layer, below the editor layer, so a list in a session document needs a seam.
  - What holds: one helper for a task of an editor that records a failure as a fault and drops a post after the end of the loop, and the choice of a sticky task inside `start_background_work`. That is a small gain in consistency and removes few lines.

### CC-6 The feed layer gives a contract and no store

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 7; PAR-STORE-THEN-DRAIN.
- **Today:** `source/kernel/feed/` is the abstract type `Feed` and three functions. Each feed writes its store. Table 3 shows the result.
  - `MessageLogStore` and `McpLogStore` are the same type twice: the fields `first_index`, `lock`, `capacity`, `dropped` and `wakes`, and the functions record, read from a number, take, attach a wake and detach a wake ([MessageLogStore.jl:19](../../../source/platform/log/MessageLogStore.jl#L19)–[117](../../../source/platform/log/MessageLogStore.jl#L117), [McpLogStore.jl:18](../../../source/platform/mcplog/McpLogStore.jl#L18)–[112](../../../source/platform/mcplog/McpLogStore.jl#L112)).
  - A list of wakes has three forms: a vector ([FileChangeStore.jl:55](../../../source/platform/filechange/FileChangeStore.jl#L55)), an `IdDict` by reader ([MessageLogStore.jl:29](../../../source/platform/log/MessageLogStore.jl#L29)), and one field ([ReflectionFeed.jl:53](../../../source/platform/reflection/ReflectionFeed.jl#L53)). Only the `IdDict` form can detach.
  - Three slices find their feed with a search of `editor.feeds` by type ([FileChangeStore.jl:85](../../../source/platform/filechange/FileChangeStore.jl#L85), [AgentEventFeed.jl:672](../../../source/platform/assistant/AgentEventFeed.jl#L672), [SystemProcessProgram.jl:41](../../../source/platform/systemprocess/SystemProcessProgram.jl#L41)). Two of them throw when the editor was made with no wrapper. The editor also has `get_session_document!`, a table by type that makes its entry at the first ask ([Editor.jl:262](../../../source/kernel/editor/Editor.jl#L262)).
- **Example:**
  ```julia
  # Today, twice:
  mutable struct McpLogStore
      calls::Vector{NamedTuple}; first_index::Int; lock::ReentrantLock
      capacity::Int; dropped::Int; wakes::IdDict{Any,Any}
  end

  # After, once in the feed layer:
  const McpLogStore = NumberedStore{McpCall}
  record_entry!(store, call)                 # any task; wakes each reader
  entries, next, missed = read_entries(store, feed.next)
  ```
- **Problem:** A new log repeats 120 lines. A fix of one store, such as the detach of a wake, must be made in each. A slice that needs a place of its own in an editor has two ways to get it, and the feed way fails for an editor with no wrapper.
- **Proposal:** The feed layer gives two stores: a numbered store with a bound and a cursor for each reader, and a set of changed keys. Each holds the lock and the list of wakes with attach and detach. A feed that only keeps a list of sources for its editor keeps that list in a session document.
- **What goes away:** One of the two log stores and most of the second feed, about 150 lines. Two forms of the wake list. The three searches by type.
- **What stays:** Each editor gets every line from its own cursor. A full store drops its oldest entry and counts it.
- **Risk and open questions:** L21-1 of `kernel-audit-fixes.md` asks whether a store belongs to one editor; the owner chose "B for now, A later" (D12). A generic store fits both answers. The kernel keeps plain stores and no notion of a log, so the store must stay a plain container.
- **Related plans:** `plan/pending/kernel-audit-fixes.md` L21-1, L22-14, L22-15 (pending; who owns a store, and the detach). `plan/done/the-feeds-of-an-editor-are-its-own.md` (done).
- **Check:** confirmed-with-corrections. Value after the check: low. I compared the two files: `MessageLogStore` and `McpLogStore` have the same fields and the same record, read, take, attach and detach. One generic store is right and cheap. Corrections:
  - The list of wakes and the detach are the open question L22-14 of `kernel-audit-fixes.md` (recommended there: a detach pair in the feed contract). L21-1 with D12 "B for now, A later" gives each editor its own store. Then a store has one reader, and the cursor for each reader and the `IdDict` of wakes go by themselves. So that part is covered by the audit plan, and the generic store should come with L21-1 or after it, with the shape that A leaves.
  - The search of `editor.feeds` by type and the throw are the result of `plan/done/the-feeds-of-an-editor-are-its-own.md` (2026-10-26): "an error and not a fallback, because a fallback is the push that the plan removes". With the list in a session document, an editor with no feed takes a tree or a source in silence and never drains it. So the proposal loses that error.
  - What is left for this finding: one numbered store in place of two, about 100 lines.

### CC-7 A document of outside state repeats five parts

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 1; 7; 9 (outside state enters by an acquire on a task).
- **Today:** A document that shows a file, a folder or a repository builds the same five parts.
  1. A count of changes, `read_count`, as an input of its background cell.
  2. An operation that stores the answer and first compares the count: [FileSystemDocument.jl:561](../../../source/platform/filesystem/FileSystemDocument.jl#L561), [DocumentFile.jl:913](../../../source/platform/fileformat/DocumentFile.jl#L913), [Image.jl:179](../../../source/platform/style/Image.jl#L179), [GitRange.jl:161](../../../source/domain/git/GitRange.jl#L161).
  3. A watch at the acquire and its end at the release: [FileSystemDocument.jl:648](../../../source/platform/filesystem/FileSystemDocument.jl#L648)–[662](../../../source/platform/filesystem/FileSystemDocument.jl#L662), [GitRange.jl:209](../../../source/domain/git/GitRange.jl#L209)–[221](../../../source/domain/git/GitRange.jl#L221), [FileChangeStore.jl:255](../../../source/platform/filechange/FileChangeStore.jl#L255)–[268](../../../source/platform/filechange/FileChangeStore.jl#L268).
  4. A method that takes a change and adds one to the count: [FileSystemDocument.jl:684](../../../source/platform/filesystem/FileSystemDocument.jl#L684), [DocumentFile.jl:794](../../../source/platform/fileformat/DocumentFile.jl#L794), [GitRange.jl:226](../../../source/domain/git/GitRange.jl#L226), [Image.jl:257](../../../source/platform/style/Image.jl#L257).
  5. The background cell itself.
  - The kernel already numbers each demand and drops an older answer ([BackgroundCells.jl:387](../../../source/kernel/editor/BackgroundCells.jl#L387)). It still calls `apply` for an answer whose inputs are no longer the inputs of the cell, which is why each operation compares the count.
  - The store of the watches has two parallel sets of functions for one job: `watch_document_file!`, `unwatch_document_file!`, `is_document_file_watched` and `receive_file_change!` for a file, and `watch_folder!`, `unwatch_folder!`, `is_folder_watched` and `receive_folder_change!` for a folder, with two records and two sets of changed paths ([FileChangeStore.jl:11](../../../source/platform/filechange/FileChangeStore.jl#L11)–[24](../../../source/platform/filechange/FileChangeStore.jl#L24), [:113](../../../source/platform/filechange/FileChangeStore.jl#L113), [:198](../../../source/platform/filechange/FileChangeStore.jl#L198)). A file watch is a watch of its folder and a compare of a stamp.
- **Example:**
  ```julia
  # Today, in each such document:
  read_count = Cell(0)
  listing = make_background_cell(source, () -> (path[], read_count[]);
                                 apply = (inputs, answer) -> ApplyFolderListingOperation(folder, last(inputs), answer))
  evaluate_operation(editor, op::ApplyFolderListingOperation) =
      (op.read_count == op.folder.read_count || return nothing; ...)
  acquire_document!(editor, folder) = watch_folder!(folder.pathname; store, receiver = folder)
  receive_folder_change!(editor, folder, path) = (folder.read_count += 1; true)

  # After:
  listing = make_background_cell(source, () -> (path[],);
                                 apply = (inputs, answer) -> ApplyFolderListingOperation(folder, answer))
  acquire_document!(editor, folder) = watch_path!(store, folder.pathname; receiver = listing)   # a change asks again
  ```
- **Problem:** The sixth document of outside state copies the five parts, and a slip in the compare shows an old answer. Two watch interfaces mean two methods for a receiver that watches both.
- **Proposal:** The background cell owns the "ask again": one function makes a cell ask again, and `apply` runs only for an answer that belongs to the inputs of the cell now. The store has one watch for a path, and a change of a watched path can name a cell that asks again. The watch still starts at the acquire and ends at the release.
- **What goes away:** The field `read_count` and the compare in four documents; one of the two sets of watch functions; the receive method where it only adds one. About 100 lines, and four parts for each future document.
- **What stays:** The watcher reads nothing and knows nothing of editing; the receiver decides (the owner, "filechange reports a change"). A file document keeps its own receive method, because it also decides between a load and the band "changed on disk". No print reads the disk.
- **Risk and open questions:** A document that keeps the count for a second purpose, as `FileDiskState` does with `loaded_count`, keeps it. The compare of inputs in the kernel reads a cell in a write phase; that needs a look.
- **Related plans:** `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md` (in progress; step 2 built the text of a file with these five parts). `plan/pending/pending-edits-and-file-changes.md` (deferred).
- **Check:** confirmed-with-corrections. Value after the check: medium. Each cited line holds. `_write_background_answers!` calls `apply` for each answer that is not older than the answered one, also while a newer demand waits ([BackgroundCells.jl:385](../../../source/kernel/editor/BackgroundCells.jl#L385)–[399](../../../source/kernel/editor/BackgroundCells.jl#L399)), so each operation compares the count itself. Corrections:
  - `read_count` is in five holders, not four: `WorkspaceFileList` has it too, with no `apply` ([WorkspaceFileList.jl:45](../../../source/platform/filesystem/WorkspaceFileList.jl#L45)). Three use it only to ask again and to drop an old answer: the folder, the git range and the file list. Two keep it for a second purpose: `FileDiskState` with `loaded_count`, and `Image` with `decoded_count == read_count` ([Image.jl:136](../../../source/platform/style/Image.jl#L136)). So the field goes in three holders and the compare in two, about 50 lines and not 100.
  - "An answer that belongs to the inputs of the cell now" needs a read of the inputs in a write phase, as the risk says. The kernel can test `number == state.demand_count` with no read. Then an old answer still applies once when an input changed and no reader asked yet, which the compare of today prevents. This case needs a decision.
  - The area is in work: `a-tab-shows-the-file-that-a-program-rewrites.md` built the text of a file on these parts, and its steps 6 and 7 are the last commits on `main`. The change should wait for that plan.
  - A cell as the receiver of a watch keeps the rule of the owner: the watcher still only reports a change. The proposal loses no feature that I found.

### CC-8 Each verb repeats the door, and each verb with an edit repeats it twice

- **Kind:** repeated-by-hand · **Value:** low · **Effort:** medium · **Confidence:** medium
- **Principle:** 7; 10 (the surface of the assistant comes by reflection). Other area: the verbs of the assistant.
- **Today:** Rule (a) of PAR-LOOP-RUNS-NO-USER-CODE says that a verb reaches a document through `run_on_editor_task!`. About 91 verbs write that call by hand, with their own name as the description (corrected by the check from 83: 126 calls give a name as the description, and 35 of them give "make_change"). 35 more calls are the `make_change` twins of the verbs that edit, each with the description "make_change". Examples: [DocumentEdits.jl:226](../../../source/kernel/editor/DocumentEdits.jl#L226)–[237](../../../source/kernel/editor/DocumentEdits.jl#L237), [ArrangementProgram.jl:199](../../../source/platform/arrangement/ArrangementProgram.jl#L199)–[205](../../../source/platform/arrangement/ArrangementProgram.jl#L205), [ChartDocument.jl:1075](../../../source/domain/chart/ChartDocument.jl#L1075)–[1082](../../../source/domain/chart/ChartDocument.jl#L1082).
- **Example:**
  ```julia
  # Today:
  insert_elements!(collection, index, values; editor = get_evaluation_editor()) =
      run_on_editor_task!(editor; description = "insert_elements!") do
          _replace_elements!(editor, collection, make_change(insert_elements!, collection, index, values; editor))
      end
  make_change(::typeof(insert_elements!), collection, index, values; editor = get_evaluation_editor()) =
      run_on_editor_task!(editor; description = "make_change") do
          _make_replace_elements(editor, collection, index - 1, index - 1, values, "Insert ...")
      end

  # After: the change is written once, and the declaration makes the verb and both doors.
  @edit_verb insert_elements!(collection, index, values) =
      _make_replace_elements(editor, collection, index - 1, index - 1, values, "Insert ...")
  ```
- **Problem:** Each domain that adds a verb repeats the two wrappers. A verb that forgets the door works in a tool call, which owns the documents, and fails from background work.
- **Proposal:** One declaration for a verb that edits: it takes the body that makes the change, and makes the verb as "apply the change that `make_change` gives", both behind the door, with the name of the verb as the description.
- **What goes away:** About 120 wrapper lines over the kernel, the platform and the domains.
- **What stays:** Rule (a). The names, the signatures and the docstrings that the reflection reads.
- **Risk and open questions:** A macro hides the control flow, and the reflection of the surface must still find the generic function and its docstring. A verb that reads and makes no change needs its own form.
- **Related plans:** `plan/done/a-verb-gets-the-editor-of-the-evaluation.md` (done), `plan/done/the-assistant-finds-its-names-by-reflection.md` (done). No pending plan.
- **Check:** confirmed-with-corrections. Value after the check: low. I opened the three examples and counted the descriptions; the count of the verbs is corrected above. The verbs do not have one shape: after the apply each answers its own value. `insert_elements!` answers a `ReferencedDocument`, `filter_collection!` a description of the collection, and `move_series!` the chart. So one declaration needs a second body for the answer, and it saves about three lines for each of the 35 verbs that edit. The proposal loses no feature. The docstring stays on `function f end`, which the reflection reads. No pending plan covers it.

## Covered by plans

- The barrier of a tool call exists twice, in the loop of the agent and in the MCP server: `plan/pending/kernel-audit/20-agent.md`, L20-6, proposes one function.
- A store of a feed is a constant of the process (the message log, the MCP log, the task feed): `plan/pending/kernel-audit-fixes.md`, L21-1, with the decision D12 "B for now, A later".
- An ended editor leaves its wake in a shared store: `kernel-audit-fixes.md`, L22-14.
- Each editor writes to the one logger of the process: `kernel-audit-fixes.md`, L22-15.
- The bounds and the measures of a frame for the inbox, the feeds, the terminal and a burst of calls: `plan/pending/guards-keep-the-frame-short-at-any-size.md`.
- The wait of the SDL present where the display has no vertical blank: `plan/pending/a-present-that-is-a-timeout.md`.
- The process-global values of the SDL backend: `plan/pending/sdl-per-editor-state.md`.
- A card that acquires its file, and the one file document of a path: `plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md`, steps 6 and 7.
- Pending edits on top of a changed file: `plan/pending/pending-edits-and-file-changes.md`, deferred by the owner.

## Examined and sound

- One owner task and no lock on a cell, with the check of a foreign write: one rule, and the engine relies on it twice.
- The wake: one atomic flag and one kick of the backend; many wakes give one frame; a store gets the wake as a callback and never names the editor.
- The loop uses no timer of the operating system; the timeout of the wait is the timer.
- `SetTimerOperation` beside the feed deadline: a reader is pure and can not wait, so it answers an operation; the two have different callers.
- The code unit and the held frames: one mechanism for code of unknown length; the unit and background work share one stop (`_stop_scope!`).
- The queue of the owner with no bound beside the bounded inbox: the owner must never wait for itself.
- `run_on_editor_task!` runs at once for the owner and when no loop runs: one rule that lets a test drive a turn with no loop.
- The background cell: the demand is a record outside the graph, one work for each source and frame, an old answer is dropped; seven slices use it the same way.
- Acquire and release with a count of holders: one mechanism for the lifetime of a watch, a server and an agent.
- The task feed keeps the editor of each execution, as PAR-PRODUCER-CARRIES-THE-PART says.
- A watcher of a folder reads nothing and marks a stamp; the receiver decides what a change means.
- `wait_for_cell!` polls through the door with a sleep of 0.05 s from another task: a cell has no wait, and the call has a time limit.
- The event queue differs for each backend behind one protocol of three functions.
- The store of the meaning vectors is a value of the process: the accepted carve-out of PAR-PER-EDITOR-STATE.
- The run of a process model waits on a `Channel` at a breakpoint: that is the meaning of a breakpoint.
- `_wait_for_gate` is the same function in the web and the console backend, and the default of the kernel polls each 10 ms: a small copy in the area of the backends, and no finding here.

## Check of the report

A second reviewer checked each finding against the code at commit 3a9b4fae4, the guides and the plans. It ran no Julia. Each correction of a fact or a count stands in the finding, marked "corrected by the check".

| Id | Verdict | Value before | Value after | The main reason |
| --- | --- | --- | --- | --- |
| CC-1 | weakened | high | medium | The feed is the documented door of a stream. `AgentEventQueue` must stay for a put under a lock. A burst and the case of no loop get worse. Only "a post with no answer is a typed operation" holds with no cost |
| CC-2 | weakened | high | medium | The six rows are three jobs. The two polls need the period of CC-3 first. The formula as a background cell changes the model of D8 |
| CC-3 | confirmed-with-corrections | medium | medium | The tree of the explorer has no feed that samples it. The period is a new input of the kernel, and the kernel still needs the probe for readers |
| CC-4 | confirmed-with-corrections | medium | low | The part that is written twice is the group and its signals, 40 to 60 lines. The other differences have a reason or are new features |
| CC-5 | weakened | medium | low | The four tables are maps by a key and stay. The stop steps stay. `parent = nothing` as a default goes against D9b |
| CC-6 | confirmed-with-corrections | medium | low | The two log stores are one type. The wake list is the open question L22-14, and L21-1 changes the shape of the store |
| CC-7 | confirmed-with-corrections | medium | medium | The count goes in three holders and stays in two. The plan of the file tab works in this area now |
| CC-8 | confirmed-with-corrections | low | low | About 91 verbs, 35 with a twin. Each verb answers its own value, so the declaration saves about three lines for each |
