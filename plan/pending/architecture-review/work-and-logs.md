# Architecture review: running work and logs

Commit 3a9b4fae4. Reviewer area key: work-and-logs.

## Scope

Paths: `source/platform/{task,systemprocess,backgroundwork,terminal,workplan,log,mcplog,gesturelog,statistics}`, `source/domain/{process,workflow}`, `source/kernel/feed`, and the stores of background work in `source/kernel/editor` and `source/kernel/tool`. The area holds about 17,800 source lines.

Read in full, about 6,200 source lines:

- kernel: `feed/*` (103), `editor/Feeds.jl` (343), `editor/BackgroundCells.jl` (498), `tool/BackgroundWork.jl` (150);
- `log` (all but the theme), `mcplog` (all but the theme), `backgroundwork` (all);
- `statistics`: the feed and the document; `gesturelog`: the document and the recording;
- `terminal`: the document and the process;
- `task`: `TaskModule`, `TaskExecution`, `TaskFeed`, `TaskWorkItem`, `TaskStream`, `TaskDocument`;
- `workplan/WorkPlanDocument.jl`; `process/ProcessRuntime.jl` and `ProcessDebugSession.jl`.

Read in full, about 2,300 lines of documents: `concepts.md`, `architecture-decisions.md`, the package documents of task, systemprocess, backgroundwork, terminal, workplan, log, mcplog, gesturelog, statistics, workflow, process and roster, and the invariants `PAR-STORE-THEN-DRAIN` and `PAR-PER-EDITOR-STATE` to `PAR-REPORT-NEVER-THROWS`.

Sampled by outline and by search: `TaskGroup.jl`, `TaskGroupDocument.jl`, `TaskGroupToWidget.jl`, `TaskGroupList.jl` (270 of 378 lines), `TaskPagesToWidget.jl` (the stream parts), `TaskVerbs.jl`, `BuildStep.jl`, `ProgramTask.jl`, `FrameStatisticsToWidget.jl`, `TerminalToWidget.jl`, `SystemProcessSync.jl` (the drain and the feed), the workflow sources, `ProcessDebug.jl`, and the places outside the area that a finding names (`RecordTableToWidget.jl`, `McpServer.jl`, `Evaluator.jl`, `AssistantTurn.jl`).

Not read: the themes, `GestureLogOverlay.jl`, the body of `TaskGroup.jl` (the scheduler and the tally), `ProcessToSyntax.jl`, `ProcessToJuliaCode.jl`, `ProcessDiagramToGraph.jl`, `WorkflowEdits.jl`, `WorkflowToWidget.jl`.

I ran no Julia and no test. Each claim below rests on a read of the cited lines.

## State

The inflow of outside state is sound in its model. A producer writes a plain store, and a feed (a registered inflow of an editor, `Feed` in `source/kernel/feed/`) copies what is new into a document on the task of the editor. The task slice is the strongest part: a kind of task adds a few methods, and the table of a group, the Tasks pane and the list of the open workflows already reuse the roster (the generic table of items with fields) and the arrangement (the generic filter, sort and find of a collection). The assistant reuses the task documents for the background tasks of an agent.

The main weakness is on the view side of a log. Ten views show a list of records that grows. Seven of them are made by hand, each with its own bound, its own filter or none, and its own way to follow the end. Only the log of the background work uses the generic table. Four of the stores are already sources of a roster, so the generic view reaches them, but the tab of each log shows the hand-made view.

The second weakness is that a program that runs has two implementations (the execution of a task and the terminal), and a piece of background work has no single record: the kernel records it only for background cells, and four callers keep private tables.

The third weakness is repetition in the feeds. Two stores are the same code line by line, three feeds repeat the same pacing and three the same gate, and eleven session documents repeat the same methods.

One place breaks a first principle: the page of a stream of a task reads the disk inside the computations of its printer.

Eleven status vocabularies are stored in the area. One shared vocabulary exists for display (`DocumentCondition`), and each kind maps its status to it by hand.

## Inventory

### A. Documents that model a thing that runs and reports

| Thing | Type | Stored status | Start and end | Output | Result or error | Stop | Listed where | How its state comes in |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Execution of a task | `TaskExecution` [TaskExecution.jl:224](../../../source/platform/task/TaskExecution.jl#L224) | 7 symbols, `:pending` to `:skipped` [:194](../../../source/platform/task/TaskExecution.jl#L194) | `start_time`, `end_time` | two `TaskOutput` (first 100 and last 1000 lines) and a file for each stream [:24](../../../source/platform/task/TaskExecution.jl#L24) | `TaskResult` with a code string, 9 codes in 3 families [TaskResult.jl:49](../../../source/platform/task/TaskResult.jl#L49) | `stop_task_execution!`, SIGINT to the group | row of a group, or row of the Tasks pane for a task alone | native layout under a lock, then `TaskFeedStore`, then `TaskFeed` each 0.25 s, then a shadow by `sync_document!` [:322](../../../source/platform/task/TaskExecution.jl#L322) |
| Group of tasks | `TaskGroup`, `TaskGroupDocument` | 4 symbols [TaskGroupDocument.jl:34](../../../source/platform/task/TaskGroupDocument.jl#L34) | in the summary | of each task | `TaskGroupResult` | `stop_task_group!` | Tasks pane | the same feed |
| Program task, build step | `ProgramTask`, `BuildCommandTask` | kinds of task: they reuse the two rows above | | | `ProgramResult`, `BuildStepResult` | | | |
| Background task of an agent | `AgentBackgroundTask <: AbstractTask` [AgentWorkDocument.jl:169](../../../source/platform/assistant/AgentWorkDocument.jl#L169) | reuses the task rows | | | | | work page of the assistant | the task feed |
| Terminal | `TerminalDocument` [TerminalDocument.jl:53](../../../source/platform/terminal/TerminalDocument.jl#L53) | `:new`, `:running`, an `Int`, `:failed` | none | `lines`, a plain vector of at most 2000 | the exit status, in `status` | `stop_terminal!`, SIGINT then SIGKILL | its own tab or card only | reader tasks post each chunk to the inbox [TerminalProcess.jl:45](../../../source/platform/terminal/TerminalProcess.jl#L45) |
| System process | `SystemProcess` | 7 states of the system [SystemProcessDocument.jl:17](../../../source/platform/systemprocess/SystemProcessDocument.jl#L17) | `start_time` | none | none | Interrupt, Stop | a tree, a roster source | a sampler off the loop, then `SystemProcessFeed` each second |
| Background work | `BackgroundWork` [BackgroundWork.jl:24](../../../source/kernel/tool/BackgroundWork.jl#L24) | none; `show` derives "runs", "failed", "done" | none | none | `fetch` | `stop_background_work!` | nowhere | none |
| Work of background cells | `BackgroundWorkRecord` [BackgroundCells.jl:89](../../../source/kernel/editor/BackgroundCells.jl#L89), `BackgroundWorkRow` | 3 strings [BackgroundWorkDocument.jl:156](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L156) | `started`, `finished` | none | count of failures, first failure | none | Background work log | store of the editor, then `BackgroundWorkFeed` |
| Search of an explorer | `ExplorerSearch` | a `stopped` flag and a provisional cell [ExplorerSearch.jl:180](../../../source/platform/explorer/ExplorerSearch.jl#L180) | | matches | | `stop_work_item!` | Tasks pane | a background cell |
| Step of a work plan | `WorkPlanStep` | 5 symbols, and "blocked" as a relation [WorkPlanDocument.jl:13](../../../source/platform/workplan/WorkPlanDocument.jl#L13) | none | none | `reason` | none (read only) | tree of the plan | an agent event writes the fields |
| Node of a workflow | `WorkflowStep`, `WorkflowOption` | 4 and 4 symbols [WorkflowDocument.jl:209](../../../source/domain/workflow/WorkflowDocument.jl#L209) | times of journal entries | the journal | `reason` | not applicable | list of the open workflows | edits |
| Run of a process model | `ProcessTrace`, `ProcessDebugSession` | 5 symbols [ProcessDebugSession.jl:17](../../../source/domain/process/ProcessDebugSession.jl#L17) | none | `locals` | none | `stop_process!` | nowhere | `sync_process_debug!`, called by hand |
| Work of an agent | `AgentWork` | `:running`, `:idle`, `:requires_action` [AgentWorkDocument.jl:31](../../../source/platform/assistant/AgentWorkDocument.jl#L31) | | | | cancel | work page of the assistant | `AgentEventFeed` |

Count of stored status vocabularies: eleven (execution status, result codes, group status, terminal status, state of a background work row, work plan step, workflow step, workflow option, agent work, process debug session, system process state). One vocabulary is shared for display: the names of `DocumentCondition` (`:running`, `:failed`, `:waiting`, `:done`, `:stopped`, `:pending`, `:unexpected`) in [DocumentDecoration.jl:23](../../../source/platform/domain/DocumentDecoration.jl#L23).

Four ways bring the state of a running thing into a document: a feed with a store (task, background work, system process), a post of a closure to the inbox for each chunk (terminal), a write in a reader (gesture log), and a sync that the caller must call (process debug).

### B. Views that are like a log

"n.c." means not checked.

| View | Data model | Bound | View | Filter | Find | Builds only the visible rows | Follows the end | Clear |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Message log | `MessageLog.entries`, a `CellVector` of `MessageLogEntry` documents | 200, and a ring of 1000 | `MessageLogToSyntax`: one text line for each entry, newest first | no | no | no: every line is made again at each append [MessageLogToSyntax.jl:57](../../../source/platform/log/MessageLogToSyntax.jl#L57) | newest first | a function with no caller in `source` [MessageLogDocument.jl:84](../../../source/platform/log/MessageLogDocument.jl#L84) |
| MCP log | `McpLog.entries`, a `CellVector` of `McpCallEntry` documents | 500, and a ring of 1000 | `McpLogToWidget`: one block of widgets for each call | its own choice of three [McpLogToWidget.jl:42](../../../source/platform/mcplog/McpLogToWidget.jl#L42) | no | no: every shown block is made again at each change [:94](../../../source/platform/mcplog/McpLogToWidget.jl#L94) | yes [:102](../../../source/platform/mcplog/McpLogToWidget.jl#L102) | a gesture [McpLogDocument.jl:122](../../../source/platform/mcplog/McpLogDocument.jl#L122) |
| Gesture log | `GestureLog.entries`, a `CellVector` of plain structs [GestureLogDocument.jl:5](../../../source/platform/gesturelog/GestureLogDocument.jl#L5) | 20 | `GestureLogToSyntax`, and a panel over the window | only at the recording | no | no | newest first | a function with no caller in `source` |
| Fault log (fault slice) | `FaultLog.entries`, a `CellVector` of plain structs; a fault that comes again takes its own line back by its key | 50 | `FaultLogToSyntax` | no | no | no | newest first | a function with no caller in `source` [FaultDocument.jl:124](../../../source/platform/fault/FaultDocument.jl#L124) |
| Background work log | `BackgroundWorkLog.rows`, a `CellVector` of `BackgroundWorkRow` documents | 100 in the store | a line and a held table: an arrangement of a roster [BackgroundWorkDocument.jl:55](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L55) | yes, the arrangement | yes, the arrangement | yes, in a tab | newest first | no |
| Frame statistics | rows, and `frames` and `columns` as plain vectors | ring of 1000 | three hand-made `WidgetTable`s, the frames by `make_index_list` [FrameStatisticsToWidget.jl:547](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L547) | a choice of the measure | no | yes | newest first, and Pause | no |
| Stream page of a task | the file of the stream and an index of its lines, `_TaskStreamIndex` [TaskStream.jl:11](../../../source/platform/task/TaskStream.jl#L11) | the file has none | a hand-made `WidgetTable` of the visible lines and its own scroll bar [TaskPagesToWidget.jl:398](../../../source/platform/task/TaskPagesToWidget.jl#L398) | its own `filter_text` | its own `find_text` | yes, by its own window | its own `follow` | no |
| Stream box in the detail of a task, and stream preview on the task page | the kept lines of `TaskOutput` | 1100 | a text area of the joined lines in a scroll pane [TaskGroupToWidget.jl:868](../../../source/platform/task/TaskGroupToWidget.jl#L868); the last 8 lines as labels [TaskPagesToWidget.jl:79](../../../source/platform/task/TaskPagesToWidget.jl#L79) | no | no | no | yes | no |
| Lines of a terminal | `Vector{TerminalLine}` in one cell | 2000 | a label for each line in a scroll pane, all made again at each chunk [TerminalToWidget.jl:69](../../../source/platform/terminal/TerminalToWidget.jl#L69) | no | no | no | yes | no |
| Journal of a workflow | the entries of the tree | none | a timeline of outline rows | its own choice of the kind | no | n.c. | newest first | not applicable |

Copy: the stream page copies no line ([task.md:636](../../../documentation/package/platform/task/task.md#L636)). I did not check copy in the other views.

Four stores are also sources of a roster: `:log` [MessageLogToSyntax.jl:102](../../../source/platform/log/MessageLogToSyntax.jl#L102), `:mcp_log` [McpLogToWidget.jl:121](../../../source/platform/mcplog/McpLogToWidget.jl#L121), `:faults` [FaultLogToSyntax.jl:99](../../../source/platform/fault/FaultLogToSyntax.jl#L99), `:frames` [FrameStatisticsModule.jl:73](../../../source/platform/statistics/FrameStatisticsModule.jl#L73). So the generic table can show them with a filter, a sort and a find, but the tab of each log shows the hand-made view.

### C. Feeds

| Feed | Store | Where the store lives | Pacing | Gate | Wake | Shape of the drain |
| --- | --- | --- | --- | --- | --- | --- |
| `InboxFeed` | the inbox | editor | each frame | none | `wake_editor!` | applies operations |
| `MessageLogFeed` | `MessageLogStore`: ring of 1000, a cursor for each reader | process constant [MessageLogStore.jl:119](../../../source/platform/log/MessageLogStore.jl#L119) | each frame | none | a callback for each reader | appends entries; warns of missed lines |
| `McpLogFeed` | `McpLogStore`: the same fields | process constant [McpLogStore.jl:114](../../../source/platform/mcplog/McpLogStore.jl#L114) | each frame | none | a callback for each reader | appends entries; no count of missed calls |
| `TaskFeed` | `TaskFeedStore`: entries and changed entries | process constant, each entry names its editor [TaskFeed.jl:47](../../../source/platform/task/TaskFeed.jl#L47) | 0.25 s | an entry of this editor exists | deadline | shadow sync, then a call to the owner |
| `BackgroundWorkFeed` | `BackgroundWorkStore`: records and a change count | session document of the editor | 0.25 s | `has_dependent_cells` and a new count [BackgroundWorkFeed.jl:34](../../../source/platform/backgroundwork/BackgroundWorkFeed.jl#L34) | deadline | sync of rows by key, changed fields only |
| `FrameStatisticsFeed` | `FrameMeasurementStore`: ring of 1000 | field of the editor | 0.25 s for each document | `has_dependent_cells`, a new count, not paused [FrameStatisticsFeed.jl:56](../../../source/platform/statistics/FrameStatisticsFeed.jl#L56) | deadline | changed fields; whole columns |
| `SystemProcessFeed` | a sampler in each tree | the feed holds the trees | 1 s | `has_dependent_cells` [SystemProcessSync.jl:129](../../../source/platform/systemprocess/SystemProcessSync.jl#L129) | deadline | sync by process id and start ticks |
| `ReflectionFeed`, `FileChangeFeed`, `AgentEventFeed` | other areas; only their fields were sampled | | | | | |

What each feed repeats:

- the store with a lock, a ring, a count of dropped items and the wakes of the readers (2 copies, the same line by line);
- `flush_interval`, `now`, `flushed_at`, the test "at most once in each interval" and a deadline that answers the interval while the feed is due (3 copies with the same field names: task, background work, statistics; the reflection feed holds `interval` and `now`, and the system process feed has the interval inside each tree);
- the gate "a view reads the target", `has_dependent_cells` on one cell of the target (3 copies);
- the default target `something(feed.log, get_session_x(; editor))` (4 copies);
- a write of a field only when its value changed (4 copies: `_write_changed_field!` in the statistics, a loop in the background work log, `_SHADOW_FIELDS` in the execution, the sync of a process tree);
- a wrapper of `build_editor` that pushes one feed, and a line for its layer (6 copies in the area).

## Findings

### WL-1 A list of records that grows has seven hand-made views; only one log uses the generic table

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 8 (reuse an existing view: a list of items with fields goes to the roster) and 7 (one mechanism for every list).
- **Today:** Table B lists ten views. `MessageLogToSyntax`, `GestureLogToSyntax` and `FaultLogToSyntax` are three copies of one printer: a computed list of text lines, newest first, a text for an empty log, and the same cells for the paths ([MessageLogToSyntax.jl:56](../../../source/platform/log/MessageLogToSyntax.jl#L56), [GestureLogToSyntax.jl:60](../../../source/platform/gesturelog/GestureLogToSyntax.jl#L60), [FaultLogToSyntax.jl:57](../../../source/platform/fault/FaultLogToSyntax.jl#L57)). They differ only in the columns of a line. `McpLogToWidget` makes a block of widgets for each of up to 500 calls, makes all of them again at each new call, and has its own filter ([McpLogToWidget.jl:93](../../../source/platform/mcplog/McpLogToWidget.jl#L93)). `TerminalToWidget` makes a label for each of up to 2000 lines at each chunk ([TerminalToWidget.jl:69](../../../source/platform/terminal/TerminalToWidget.jl#L69)). Four documents repeat "append one entry and drop the oldest above the capacity" ([MessageLogDocument.jl:68](../../../source/platform/log/MessageLogDocument.jl#L68), [McpLogDocument.jl:77](../../../source/platform/mcplog/McpLogDocument.jl#L77), [GestureLogDocument.jl:88](../../../source/platform/gesturelog/GestureLogDocument.jl#L88), [FaultDocument.jl:91](../../../source/platform/fault/FaultDocument.jl#L91)), with the capacities 200, 500, 20 and 50. (Corrected at the check: two of the four are not plain appends. The fault log has no `count`, and a fault that comes again is written back into its own line by its key; the gesture log folds a run of typed characters into its newest entry, [GestureLogDocument.jl:60](../../../source/platform/gesturelog/GestureLogDocument.jl#L60).) The background work log is the one that holds `table`, an arrangement of a roster of its rows, so it has the filter, the sort, the find and the rows on demand with no code of its own ([BackgroundWorkDocument.jl:55](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L55)).
- **Example:**

  ```julia
  # Today: a new log writes a document, a record function, a printer and a row of the renderer.
  @document struct MessageLog
      entries::CellVector = CellVector(); capacity::Int = 200; count::Int = 0
  end
  record_message!(log, level, message)       # push, count, drop the oldest
  @projection UntrackedCell struct MessageLogToSyntax ... end     # 100 lines, a copy of two others

  # After: a log is a bounded list of record documents, and the generic views show it.
  log = RecordLog(MessageLogEntry; title = "Log", columns = ["level", "message"], capacity = 200)
  record!(log, MessageLogEntry("Warn", "the file changed"))       # one function for every log
  # the tab: the held table (filter, sort, find, rows on demand, newest first as a sort)
  # the text and the panel: one notation that prints the columns of each record as a line
  ```

- **Problem:** A feature of one view does not reach the others. The MCP log has a filter of three fixed choices, the message log has none, and neither has a find. A clear exists as a gesture for the MCP log and as a function that nothing in `source` calls for the message log and the gesture log. The message log and the terminal make every row again at each new record. The plan [guards-keep-the-frame-short-at-any-size.md](../../../plan/pending/guards-keep-the-frame-short-at-any-size.md) measured the cost of some of these views and marks the message log as broken. The next log (a log of the language server, of the file watcher, of an agent) must write a document, a bound, a printer and a renderer row again.
- **Proposal:** One kind of document for a log: a bounded `CellVector` of record documents, with `count`, the capacity and a clear, and with `table`, the arrangement of a roster of its records. One page shows it (WL-6). A log names its columns and its facets (for example the role of a level), and the page of one record shows the long parts (the code and the answer of an MCP call). One generic notation prints the same columns as text lines, for `print_natural_text`, for the panel of the gesture log and for the panel of the fault log; it replaces the three copies.
- **What goes away:** `MessageLogToSyntax`, `GestureLogToSyntax` and `FaultLogToSyntax` as three projections for one generic notation (corrected at the check: the three files hold 307 lines with their comments, style fields and registrations; the part that is the same is the body of `print_document`, about 20 lines in each, so the saving is below 100 lines); the body of `McpLogToWidget` (about 80 lines) for a page of one call; two of the four record functions (corrected: the fault log and the gesture log keep theirs) and the three clear functions; the `shown` field of the MCP log.
- **What stays:** Each log, its tab, its insertion alias, its roster source, its decoration and its capacity. The panel over the window and the text for the assistant keep a line for each record, from the generic notation. "Newest first" is a sort of the arrangement. The choice "tools only" and "faults only" is a filter of the arrangement.
- **Risk and open questions:** The MCP log shows the code of a call as Julia text and a folded answer under each call. In a table this is a tall cell or the page of the call; the look changes. A table row costs more than a text line (the roster document gives about 44 computations for a row); a log that gets 1000 lines in a burst needs the rows on demand to hold. The owner has settled that the memory of every list gets one generic solution and that it is not decided yet: the capacity of a log is such a bound, so this finding moves six bounds into one place and does not decide the general question. The terminal and the stream of a task are text and not records with fields; they are in WL-2 and WL-3.
- **Related plans:** [filter-sort-and-find-any-table.md](../../../plan/pending/filter-sort-and-find-any-table.md) (pending; gives every table the filter and the find, and names no log); [guards-keep-the-frame-short-at-any-size.md](../../../plan/pending/guards-keep-the-frame-short-at-any-size.md) (in progress; measures these views); [logging.md](../../../plan/tentative/logging.md) (tentative, a brainstorm that predates the message log; stale); [the-editor-shows-its-background-work.md](../../../plan/done/the-editor-shows-its-background-work.md) (done; the model to follow).
- **Check:** confirmed-with-corrections. Value medium (was high). I opened the three text printers, `McpLogToWidget.jl`, `TerminalToWidget.jl:55-90`, the four log documents and `BackgroundWorkDocument.jl`. The three printers are copies: the body of `print_document` is the same line by line, and only `_line`, the styles and the text of an empty log differ. The four roster sources exist. [cross-cutting-views.md](../../../plan/done/cross-cutting-views.md) made them and left the views of the tabs; no plan replaces those views, and no document gives a reason for a text view. The finding follows principle 8. Corrections:
  1. The title counts seven hand-made views, and the proposal changes four of them. The terminal and the two views of a stream are text, not records with fields.
  2. One `record!` replaces two record functions, not four. `append_fault!` is a seam of the kernel, writes a fault that comes again back into its line by its key, and has no `count`. `record_gesture!` folds a run of typed characters into the newest entry. The entries of these two logs are plain structs, not documents.
  3. The saving in the three printers is below 100 lines, not 300 (corrected above).
  4. The filter, the sort and the find already reach the four stores through the roster sources (`show_roster!` of `:log` and the others). So the gain is the view that the tab shows first and one way to write a log, not a new ability.
  
  What the proposal would lose: the MCP log as a transcript. A person reads there the code of each call as Julia and the answer under it, in one scroll ([mcplog.md](../../../documentation/package/platform/mcplog/mcplog.md): "A person reads in it what an agent did"). In a table each call is one row that is cut at its width, and the code and the answer need an open of the row. A long message of the message log is cut in its column in the same way. The part that is safe and small: one shared printer of lines for the three text logs, and the held table as the tab of the message log. The MCP log needs a decision of the owner.

### WL-2 The page of a stream of a task reads the disk in its printer, and has its own window, find, filter and follow

- **Kind:** special-case · **Value:** high · **Effort:** medium · **Confidence:** high for the facts, medium for the proposal
- **Principle:** 9 (a printer reads no disk; outside state enters by an acquire on a task) and 7 (one mechanism for every list).
- **Today:** `TaskStreamLines` is the document of the lines of one stream of an execution. Its printer, `TaskStreamLinesToWidget`, makes computed cells that call `collect_task_stream_rows` and `_read_stream_lines` ([TaskPagesToWidget.jl:398](../../../source/platform/task/TaskPagesToWidget.jl#L398)). These call `isfile`, `filesize`, `open` and `read` on the file of the stream ([TaskStream.jl:24](../../../source/platform/task/TaskStream.jl#L24), [:41](../../../source/platform/task/TaskStream.jl#L41)), and a search reads every new line of the file ([:56](../../../source/platform/task/TaskStream.jl#L56)). All of this runs on the task of the editor, in a frame. (Added at the check: the reader side reads the disk too. A button of the bar makes its operation with `find_task_stream_matches` and `_get_top_row_for`, which search and index the file, [TaskStream.jl:211](../../../source/platform/task/TaskStream.jl#L211), [:234](../../../source/platform/task/TaskStream.jl#L234).) The page keeps its own window (`top_row`, a count of visible rows, a scroll bar that it builds with 13 positional arguments, its own wheel step) and its own reader that looks for a write of the scroll bar inside the answer ([TaskPagesToWidget.jl:439](../../../source/platform/task/TaskPagesToWidget.jl#L439)). It has its own find (`find_text`, `found_line`), its own filter (`filter_text`) and its own follow. The document of the slice names the limits: a long line is cut, no key moves the lines, the page copies no line, and a search of a large stream holds the editor ([task.md:636](../../../documentation/package/platform/task/task.md#L636)). The same stream has two more views: a box of the kept lines in the detail of a task and the last 8 lines on the page of a task.
- **Example:**

  ```julia
  # Today, inside a computation of the printer:
  rows = Cell(@computation collect_task_stream_rows(lines))      # isfile, filesize, open, read
  texts = _read_stream_lines(lines.index, numbers)               # open and seek, in the frame

  # After: the read is the work of a background source, as for a folder, a picture and a git file.
  source = BackgroundSource(inputs -> [read_stream_window(input...) for input in inputs];
                            description = "the lines of a stream")
  window = make_background_cell(source, () -> (output.path, output.count, head, visible, filter_text);
                                default = EMPTY_STREAM_WINDOW)
  rows = make_index_list(window[].count, head, k -> make_stream_row(window, k))   # the one lazy list
  ```

- **Problem:** Every other reader of the disk in the platform goes through a background cell, a cell whose value a task computes off the loop (`make_background_cell`: pictures, folders, the text of a file, git, the workspace files). This page is the exception, so a large stream on a slow disk makes a slow frame. The window, the find and the filter exist only here, so they do not have the keys, the selection and the copy that the generic views have, and the work on the find of every table will not reach them.
- **Proposal:** Two steps. First, the index of the lines, the window of texts and the matches of a search become answers of a `BackgroundSource`, with the path, the count of lines, the head, the height and the two texts as inputs. The printer reads only cells. Second, the rows become the generic lazy list (`make_index_list`, which the roster, the frame statistics and the data frame view use), with the head as the anchor that the document owns, so the rows on demand and the wheel come from the table as they do for the frames. (Corrected at the check: the scroll bar and the jump do not come from the table. The page of the frames builds its own scroll bar and converts five writes in its reader, [FrameStatisticsToWidget.jl:556](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L556) to :600 and :652, and the data frame view does the same.) The marks of a line (error, warning) stay a function of the kind of task. A further step, which needs a decision: show the file through the view of a text file, which the button "Open as a file" already opens, and keep only the marks and the follow as additions.
- **What goes away:** the disk reads in `TaskStream.jl` from the frame; the hand-made window and scroll bar in `TaskStreamLinesToWidget` and its reader (about 80 lines); the limit "a search holds the editor task".
- **What stays:** every line of a stream in its file; the page with its bar; Find with its count of matches; the filter; the follow of the end; First error; the colours of the marks; a stream of a million lines that costs the lines on the screen.
- **Risk and open questions:** The answer of a background cell comes a frame later, so the page shows its last window for one frame; the follow of the end must stay smooth. Whether the view of a text file can show a file that grows to a million lines is not checked here; that is why the proposal keeps the page.
- **Related plans:** [a-tab-shows-the-file-that-a-program-rewrites.md](../../../plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md) (in progress; goal 7 says "no print reads the disk" for a file in a tab; it does not name the stream page); [guards-keep-the-frame-short-at-any-size.md](../../../plan/pending/guards-keep-the-frame-short-at-any-size.md) (in progress); [a-highlighted-text-marks-given-ranges.md](../../../plan/pending/a-highlighted-text-marks-given-ranges.md) and [a-text-has-a-gutter-beside-its-lines.md](../../../plan/pending/a-text-has-a-gutter-beside-its-lines.md) (pending; they would give a text view the marks and the line numbers).
- **Check:** confirmed-with-corrections. Value high. I opened all of `TaskStream.jl` and `TaskPagesToWidget.jl:343-472`. The facts hold: `collect_task_stream_rows`, `_read_stream_lines` and `_search_stream_lines` call `isfile`, `filesize`, `open` and `read` inside computed cells of the printer, and the scroll bar has 13 positional arguments. The reader side reads the disk too (added above), so the page breaks principle 9 on both sides. The pending plan of the file in a tab writes "A printer must read no disk" as a decision ([a-tab-shows-the-file-that-a-program-rewrites.md:254](../../../plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md)) and does not name this page; no plan covers it, and no document gives a reason for the read in the print. Step 1 of the proposal holds and uses the mechanism that folders, pictures and git use. Corrections:
  1. Step 2 removes less than it says. `make_index_list` gives the rows on demand and the wheel. The scroll bar and the jump stay code of the page: the page of the frames, which the proposal names as the model, builds its own bar and converts five writes in its reader, and the data frame view does the same (corrected above). So the "about 80 lines" of the window and the reader do not all go away.
  2. The box of the kept lines is a text area, not labels (corrected in Table B).
  3. I did not check the claim that every other reader of the disk in the platform goes through a background cell.
  
  One fact for the design: the reader task of the execution writes each line into the file and knows where the line starts and which mark it has ([TaskExecution.jl:540](../../../source/platform/task/TaskExecution.jl#L540)). The page reads the file again to find the line starts, and computes the mark of each shown line again ([TaskPagesToWidget.jl:414](../../../source/platform/task/TaskPagesToWidget.jl#L414)). If the output carries these two facts, the index needs no read at all, and only the texts of the visible lines and a search need the background source. What the proposal makes a little worse: the window comes one frame and one task switch after each step of the wheel, and the follow of the end starts a work at each sync of the stream.

### WL-3 A program that runs has two implementations: the execution of a task and the terminal

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 7 (one mechanism; a missing case gets its row), and `PAR-STORE-THEN-DRAIN`.
- **Today:** `start_process_task!` starts a command for a `TaskExecution`: pipes for the two outputs, a process group of its own, two reader tasks, a file for each stream, a sampler of the load, and a result ([TaskExecution.jl:477](../../../source/platform/task/TaskExecution.jl#L477)). `start_terminal!` starts a command for a `TerminalDocument`: pipes for the input and the two outputs, a process group of its own, two reader tasks, and an exit status ([TerminalProcess.jl:20](../../../source/platform/terminal/TerminalProcess.jl#L20)). Each has its own signal helper ([TaskExecution.jl:384](../../../source/platform/task/TaskExecution.jl#L384), [TerminalProcess.jl:188](../../../source/platform/terminal/TerminalProcess.jl#L188)); the plan of the terminal notes this copy and leaves it.

  | Capability | Execution of a task | Terminal |
  | --- | --- | --- |
  | standard input | no | yes |
  | text with no line end (a prompt), carriage return | no, whole lines | yes |
  | how output reaches the documents | store, then a drain at most 4 times a second | one posted closure for each chunk [TerminalProcess.jl:45](../../../source/platform/terminal/TerminalProcess.jl#L45) |
  | memory of the output | first 100 and last 1000 lines, all lines in a file | last 2000 lines, the vector copied at each chunk [TerminalDocument.jl:110](../../../source/platform/terminal/TerminalDocument.jl#L110) |
  | row in the Tasks pane, who started it | yes | no |
  | verbs for the assistant (`get_task_output`, `stop_tasks!`, `wait_for_tasks!`) | yes | no |
  | tree of its processes, load, memory | yes | no |
  | time limit | yes (`ProgramTask`) | no |
  | a function imitates the program (compile workload) | yes | no |
  | the program ends when the editor process ends | no | yes [TerminalProcess.jl:215](../../../source/platform/terminal/TerminalProcess.jl#L215) |
  | second stop sends SIGKILL; a child left in the group is ended | no | yes |
  | status | 7 symbols and a result code | `:new`, `:running`, an `Int`, `:failed` |

- **Example:**

  ```julia
  # Today: two documents, two starts, two stops.
  run_tasks!(ProgramTask(`make test`; working_directory = folder))     # a row, a result, a stream page
  terminal = TerminalDocument(`claude auth login`); start_terminal!(editor, terminal)   # no row, no verbs

  # After: one execution; the terminal is a view of a task that takes input.
  task = ProgramTask(`claude auth login`; takes_input = true)
  document = run_tasks!(task)                    # a row in the Tasks pane, the verbs, the process tree
  send_task_input!(document, "the code")         # the line that the terminal view sends on Return
  ```

- **Problem:** A feature of one side does not reach the other. A program of a terminal is not in the Tasks pane, the assistant can not read or stop it with the verbs of tasks, and it has no process tree. A program task can not answer a prompt. The two differ in what happens at the exit of the editor, which looks like an accident of two implementations and not a decision. The reason for the split was true when the terminal was built (2026-10-09): the task documents then modelled only work in groups. Since 2026-11-06 a `ProgramTask` is "one program that a person or a model starts" and runs as a task alone, so the reason is gone.
- **Proposal:** One execution of a process. `start_process_task!` gets an optional input pipe and a reader that hands on text as it comes, with the open last line. The terminal becomes a kind of task with input, and `TerminalToWidget` becomes a view of that task: the transcript, the input line and the status. The rules for the end of a group (SIGKILL at a second stop, the children, the exit of the editor) are decided once, for both.
- **What goes away:** the start, the readers, the stop and the group table of `TerminalProcess.jl` (about 180 lines), `TerminalControl`, the status vocabulary of the terminal, one of the two signal helpers.
- **What stays:** the terminal view with its input line, the prompt with no line end, the carriage return, the removal of escape sequences, `on_exit`, the sign-in card of an agent that holds the terminal, the undo of a sent line.
- **Risk and open questions:** A terminal shows one merged transcript of four kinds of line; an execution keeps two streams. The execution must then keep the order of the chunks. A sign-in terminal inside a card of a conversation must not show as noise in the Tasks pane; a starter or a flag can hide it. The terminal posts its text with no delay; the task feed drains each 0.25 s, which a person who types into a prompt may feel.
- **Related plans:** [a-terminal-runs-a-program-in-the-editor.md](../../../plan/done/a-terminal-runs-a-program-in-the-editor.md) (done; names the copied signal helper), [the-assistant-starts-programs-as-tasks.md](../../../plan/done/the-assistant-starts-programs-as-tasks.md) (done), [any-acp-agent-gets-the-instructions-and-a-sign-in.md](../../../plan/pending/any-acp-agent-gets-the-instructions-and-a-sign-in.md) (pending; uses the terminal for a sign-in).
- **Check:** weakened. Value low (was medium). I opened all of `TerminalProcess.jl`, `TerminalDocument.jl:96-135`, `TaskExecution.jl:372-560`, `ProgramTask.jl` and the two done plans. Each row of the table holds. No plan weighed a join of the two. The post of a closure for each chunk breaks no rule: `PAR-STORE-THEN-DRAIN` names the inbox as the case of the rule for a payload that is an edit. The terminal has one user, the sign-in card of an agent (`ExternalAgentTurn.jl`), and the owner asked for it with the words "don't overdo it" ([a-terminal-runs-a-program-in-the-editor.md](../../../plan/done/a-terminal-runs-a-program-in-the-editor.md)). The proposal as written adds features more than it joins code: input for a task, and a terminal in the Tasks pane with the verbs. It would lose these, or keep a second path for each:
  1. A prompt shows with no delay today. The task feed drains each 0.25 s.
  2. `TaskOutput`, the file of a stream, the marks and `read_line` all work on whole lines. An open last line that a carriage return writes over has no place in them.
  3. One transcript in the order of the chunks of both streams, with the lines of the input and of the status between them.
  4. The program ends when its tab closes (`release_document!`); a task goes on when its tab closes.
  5. `on_exit` runs on the editor task with the editor.
  6. A sign-in must not show in the Tasks pane, so a flag hides it, which is a special case.
  
  What holds, at a small effort: the start of a command in a group of its own, the signal to the group, the end of the children that the program left, and the end at the exit of the editor are written twice, with different rules and no stated reason (a task gets SIGINT only, and its group is not ended at the exit of the editor). One helper for a process group, in a slice that both use (the task slice already depends on `systemprocess`), settles these rules once. The plan of the terminal already passed this copy on as a code quality item.

### WL-4 The editor records a running background work only for background cells; four other callers keep private tables

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 6 (state belongs to an editor, no global state) and 7 (one mechanism).
- **Today:** `start_background_work` runs a function on a task off the loop and answers a `BackgroundWork`: a description, a stop flag and a task. It keeps no list ([BackgroundWork.jl:89](../../../source/kernel/tool/BackgroundWork.jl#L89)). The work of the background cells is one caller. It adds a `BackgroundWorkRecord` to the `BackgroundWorkStore` of the editor by hand, before it calls `start_background_work` ([BackgroundCells.jl:326](../../../source/kernel/editor/BackgroundCells.jl#L326)), and `wait_for_cell!` adds and ends a record by hand a second time ([BackgroundCells.jl:474](../../../source/kernel/editor/BackgroundCells.jl#L474)). `source` has seven other call sites of `start_background_work`. Three of them keep the work, and the MCP server keeps the work that a fourth, the code tool, answers ([DefaultTools.jl:209](../../../source/kernel/tool/DefaultTools.jl#L209)); each keeps it in another shape and for another use (corrected at the check: they are not four tables of one kind; the evaluator and the turn keep a map from an owner to its work for a stop, the MCP server keeps a set to stop all at a cancel, and the formula domain keeps one work in a session store of the editor as the flag "the formula task runs"): the evaluator of a form keeps `session.works` and `is_running` ([Evaluator.jl:531](../../../source/platform/conversation/Evaluator.jl#L531), [:593](../../../source/platform/conversation/Evaluator.jl#L593)); the turn of the assistant keeps `_TURN_WORKS`, a constant of the process ([AssistantTurn.jl:135](../../../source/platform/assistant/AssistantTurn.jl#L135)); the MCP server keeps `running.works` ([McpServer.jl:46](../../../source/adapter/mcp/McpServer.jl#L46)); the formula domain keeps `computer.task` ([FormulaComputation.jl:110](../../../source/domain/formula/FormulaComputation.jl#L110)). The document of the slice lists the gap as a limit: the works that no background cell starts are not in the log ([backgroundwork.md](../../../documentation/package/platform/backgroundwork/backgroundwork.md)).
- **Example:**

  ```julia
  # Today: the caller keeps the work itself, to stop it later.
  work = start_background_work(; description = "Evaluate a form", editor) do ... end
  lock(() -> (session.works[element] = work), session.lock)
  ...
  work = lock(() -> get(session.works, form, nothing), session.lock); stop_background_work!(work)

  # After: the start records the work in the store of its editor, and the end closes the record.
  work = start_background_work(; description = "Evaluate a form", editor) do ... end
  # every work has a record: description, who started it, start, end, failure, and its stop
  ```

- **Problem:** "Which background work runs in this editor" has no single answer. The background work log shows one kind of work. The stop of a work is wired four times. One of the private tables is a constant of the process, which the rule of state for each editor forbids. A new caller must again keep a table to stop its work.
- **Proposal:** `start_background_work` adds a record to a plain store of the editor that it is given, and the end of the task closes the record, with the failure when it threw. The record holds the description, the starter of the evaluation, the times and the stop. The work of background cells adds its count of values and its inputs as detail. The background work log then lists every work, and a row can stop its work. A caller that needs its work later keeps the `BackgroundWork` in a field of its own document, and needs no table.
- **What goes away:** the two hand-made record sites in `BackgroundCells.jl`; `_TURN_WORKS` and its lock; the `works` tables of the evaluator and of the MCP server, where a field can hold the work; the limit in the document of the slice.
- **What stays:** `BackgroundWork`, its `fetch`, its stop and its link to a code unit; the store as a plain value with no cell (the kernel has no notion of a view); the feed that copies it only while a view reads it; the capacity of the store.
- **Risk and open questions:** `start_background_work` is in the tool layer of the kernel, below the editor layer that holds `get_session_document!`. Either the store type moves down to the tool layer and the editor holds it, or the editor layer wraps the start. A work that starts with no editor has no store and no record, as today. This finding sits near two kernel layers; the kernel audit has no finding on it (I searched its files for `BackgroundWork`).
- **Related plans:** [the-editor-shows-its-background-work.md](../../../plan/done/the-editor-shows-its-background-work.md) (done; it says "nothing keeps a work after its start" and leaves the other works out of its scope, with no reason against them).
- **Check:** weakened. Value low (was medium). I opened `BackgroundWork.jl`, `BackgroundCells.jl:80-130`, `:300-345` and `:455-498`, the four keepers and the plan. The facts hold: the start keeps no list, the two record sites are made by hand, and the document of the slice lists the gap as a limit. Both kernel files are not sealed. What does not hold in the proposal:
  1. "A caller keeps the `BackgroundWork` in a field of its own document, and needs no table." The source gives the reason against it at [AssistantTurn.jl:131](../../../source/platform/assistant/AssistantTurn.jl#L131): the work holds the editor, and no document holds an editor, which is a decision of the owner. So the two maps from an owner to its work (a form, a turn) do not go away. They can move into a store of the editor, with the owner as the key.
  2. The four keepers are not one kind of table (corrected above). The field of the formula domain is already in a session store of its editor and is a flag, and the set of the MCP server is a field of the server. Only `_TURN_WORKS` is a constant of the process.
  3. A record that holds the stop of its work holds the task and, through it, the editor and the documents. The plan says that a record keeps no document alive, so a record must let its work go at the end.
  4. The plan put "the works that no background cell starts" and "a stop of one work from the page" under "Not in this plan" on purpose. The Tasks pane is already the list of the work that a person watches and stops (the work items, `stop_work_item!`). A second list with a Stop needs a decision on which list shows a turn or an evaluation.
  
  What holds: `_TURN_WORKS` is a table of the process, against the rule that state belongs to an editor, and it can become a store of its editor. A complete log is a feature that the plan left out, not a repair.

### WL-5 Each feed builds its store, its pacing and its gate again

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (generic before special) and `PAR-STORE-THEN-DRAIN`.
- **Today:** Table C. `MessageLogStore` and `McpLogStore` have the same six fields and the same functions: record, read from a cursor, take, attach a wake, detach a wake, and a constant for the session ([MessageLogStore.jl:19](../../../source/platform/log/MessageLogStore.jl#L19), [McpLogStore.jl:18](../../../source/platform/mcplog/McpLogStore.jl#L18)). They have drifted in one place: the read of the message store answers how many lines were missed and its feed writes a warning ([MessageLogFeed.jl:36](../../../source/platform/log/MessageLogFeed.jl#L36)); the read of the MCP store does not, so missed calls are silent ([McpLogStore.jl:71](../../../source/platform/mcplog/McpLogStore.jl#L71)). The `take` function of each store and its `dropped` count are used only by tests. Three feeds hold `flush_interval`, `now` and `flushed_at` and repeat the test and the deadline ([TaskFeed.jl:185](../../../source/platform/task/TaskFeed.jl#L185), [BackgroundWorkFeed.jl:21](../../../source/platform/backgroundwork/BackgroundWorkFeed.jl#L21), [FrameStatisticsFeed.jl:34](../../../source/platform/statistics/FrameStatisticsFeed.jl#L34)); the reflection feed, in another area, holds `interval` and `now` for the same job ([ReflectionFeed.jl:44](../../../source/platform/reflection/ReflectionFeed.jl#L44)). Three repeat the gate on `has_dependent_cells`.
- **Example:**

  ```julia
  # Today: 120 lines of store and 45 lines of feed for each log.
  mutable struct McpLogStore; calls; first_index; lock; capacity; dropped; wakes; end
  mutable struct McpLogFeed <: Feed; store; log; next; end
  drain_changes!(feed::McpLogFeed, editor) = ...

  # After: the two shapes exist once.
  const MCP_CALLS = RecordStore{McpCall}(; capacity = 1000)
  McpLogFeed() = RecordFeed(MCP_CALLS; target = editor -> get_session_mcp_log(; editor), record = record_mcp_call!)
  BackgroundWorkFeed() = SampledFeed(; interval = 0.25,
      is_due = editor -> ..., is_watched = editor -> ..., flush = editor -> ...)
  ```

- **Problem:** The next feed copies 100 to 160 lines and can drift, as the missed count shows. A change of the contract (the kernel audit lists five corrections to it) must be made in each copy.
- **Proposal:** Two building blocks beside the feed contract. A record store (a ring with a cursor for each reader and the wakes) with a feed that appends what is new to a target and reports what was missed. A sampled feed that holds the interval, the clock, the gate and the deadline, and calls one flush function. The four copies of "write a field only when it changed" become one helper.
- **What goes away:** one of the two stores and both hand-made feeds of the logs (about 200 lines); the pacing fields and tests of three feeds (about 50 lines); the `take` functions.
- **What stays:** each feed, its wrapper, its interval, its gate and its target; the rule that an idle feed writes no cell.
- **Risk and open questions:** The record store is a plain mechanism with no document, so it could sit in the kernel beside the contract; the sampled feed needs `has_dependent_cells`, which the kernel has. Whether both belong in the kernel or in a platform slice is open.
- **Related plans:** [kernel-audit/21-feed.md](../../../plan/pending/kernel-audit/21-feed.md) (pending; findings on the contract, not on this repetition); [the-feeds-of-an-editor-are-its-own.md](../../../plan/done/the-feeds-of-an-editor-are-its-own.md) (done).
- **Check:** confirmed-with-corrections. Value medium. I compared the two stores with the names made equal: the fields and the functions are the same, and the differences are the type of a record and the `missed` count of the read. The two feeds are the same but for the warning. `take_message_lines!` and `take_mcp_calls!` have callers only in the tests. The three feeds hold the same three pacing fields. The kernel audit of the feed layer has no finding on this. Corrections:
  1. The part that holds is the record store and its feed: two copies of about 120 and 45 lines, with a drift that hides missed MCP calls. With WL-1 this is one proposal: a log is a store, a feed, a document and a view, each written once.
  2. The sampled feed is weak. The pacing is three fields, one test and one line for the deadline in each feed, about 8 lines. The statistics feed paces two documents with two times, and the gate of the task feed is another one (an entry of this editor exists, no `has_dependent_cells`). A feed made of four closures is not simpler than these lines. One small function for "the interval has passed" is enough, so the "about 50 lines" are nearer to 20.
  3. The two stores stay constants of the process until D12 A; a generic store does not change that.
  
  The proposal loses no feature.

### WL-6 The page "a line of counts over a held table" is written six times

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** 7 (one mechanism) and 8 (reuse an existing view).
- **Today:** Seven documents hold a field `table`, an `ArrangementDocument` around a `Roster` of their own collection: the background work log, the task list, a task group, the open files, a record table, a git range, the list of workflows. Six printers draw "a line, and the table under it" and repeat the same three parts: the grid of two rows, the two maps between `table.<rest>` and the second child of the grid, and a reader that patches the answer with `keep_held_arrangement` and `retarget_held_row_open` ([BackgroundWorkLogToWidget.jl:37](../../../source/platform/backgroundwork/BackgroundWorkLogToWidget.jl#L37), [RecordTableToWidget.jl:31](../../../source/platform/roster/RecordTableToWidget.jl#L31), [OpenFileListToWidget.jl:33](../../../source/platform/fileformat/OpenFileListToWidget.jl#L33), [TaskGroupToWidget.jl:1525](../../../source/platform/task/TaskGroupToWidget.jl#L1525), [GitToWidget.jl:500](../../../source/domain/git/GitToWidget.jl#L500), [WorkflowListToWidget.jl:35](../../../source/domain/workflow/WorkflowListToWidget.jl#L35)). The copies have drifted: the page of the workflows does not call `keep_held_arrangement`, and its document lists the effect as a limit (the table does not keep its arrangement when its last entry goes, [workflow.md](../../../documentation/package/domain/workflow/workflow.md)).
- **Example:**

  ```julia
  # Today, in each of six pages (about 60 lines each):
  function read_intent(p::BackgroundWorkLogToWidget, recursion, change::Intent, iomap::SimpleIoMap)
      answer = invoke(read_intent, Tuple{Projection, Any, Intent, Any}, p, recursion, change, iomap)
      operation = keep_held_arrangement(answer.operation, getfield(log, :table)[], _TABLE_STEP)
      operation = retarget_held_row_open(operation, log, _TABLE_STEP)
      ...
  end

  # After: one projection for a document that holds a table.
  make_graphics_projection(::Type{<:BackgroundWorkLog}; measure, appearance) =
      make_held_table_page(; line = _format_log_line, table = "table")
  ```

- **Problem:** A page that forgets one of the two patches loses a behaviour, as the workflow list shows. Each new list of a session (and each log of WL-1) repeats 60 lines of maps.
- **Proposal:** One projection that takes the function of the line and the name of the table field, and holds the maps and the two patches. A better form removes the patches: an arrangement that a document holds keeps itself with no entry, and a roster whose link is its holder opens a row at the place of the item, so no page has to correct the answer.
- **What goes away:** about 300 lines in six files, and the limit of the workflow list.
- **What stays:** each page, its line of counts, its buttons where it has some (the Tasks pane has a line of buttons, so the generic page needs a slot for them).
- **Risk and open questions:** The page of a task group is larger than a line and a table; it would use the generic part for its table only.
- **Related plans:** [the-header-of-a-table-filters-and-sorts-its-arrangement.md](../../../plan/pending/the-header-of-a-table-filters-and-sorts-its-arrangement.md) and [filter-sort-and-find-any-table.md](../../../plan/pending/filter-sort-and-find-any-table.md) (pending; they change the table, not the page around it).
- **Check:** confirmed. Value medium. I opened the six pages and counted with grep. Seven documents make `ArrangementDocument(roster, …)` into a field `table`. Six pages draw a line and the table with the same grid, the same two maps and the same reader. The two patches are called at six sites in five files (`TaskGroupToWidget.jl` has two: the page of a group at :1357 and the Tasks pane at :1525), and the page of the workflows calls none; [workflow.md:128](../../../documentation/package/domain/workflow/workflow.md#L128) lists the effect as a limit. The copies also differ in how they write the same maps (a helper that finds the path below some steps in two, a test of the steps in four). No shared helper exists. The pending plans use the pattern and do not join it: [the-assistant-fills-a-live-table.md](../../../plan/pending/the-assistant-fills-a-live-table.md) wrote it once more for the record table. The helper holds a function and the name of a field, and no projection, so it keeps the rule that only the algebra projections hold projections. The Tasks pane adds a row of buttons and a third correction of the answer (`_select_pressed_list_row`), so the helper needs a slot for more parts and for one more correction. The proposal loses no feature.

### WL-7 Each kind of running thing maps its status to an icon and a condition by hand, and the Tasks pane reads the state back from the decoration

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** small · **Confidence:** medium
- **Principle:** 7 (one mechanism; verbs combine with no special case).
- **Today:** A document says how it looks where it is named through `get_document_decoration`, which answers an icon, conditions and counts. Six kinds turn their own status into an icon and a condition with a chain of `? :` of their own: a task ([TaskDocument.jl:311](../../../source/platform/task/TaskDocument.jl#L311)), a step of a work plan ([WorkPlanDocument.jl:183](../../../source/platform/workplan/WorkPlanDocument.jl#L183)), a row of the background work ([BackgroundWorkDocument.jl:27](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L27)), the work of an agent ([AgentWorkDocument.jl:111](../../../source/platform/assistant/AgentWorkDocument.jl#L111)), a search ([ExplorerSearch.jl:180](../../../source/platform/explorer/ExplorerSearch.jl#L180)) and a group ([TaskGroupToWidget.jl:956](../../../source/platform/task/TaskGroupToWidget.jl#L956)). The same glyph for "runs" (`:loader`) and "done" (`:circle_check`) is written in four of the six (corrected at the check: a search always shows `:search`, and a row of the background work has no icon). A work item is a row of the Tasks pane; it answers four generics ([TaskWorkItem.jl:126](../../../source/platform/task/TaskWorkItem.jl#L126)). Its state is not one of them: `_is_work_item_running` reads the conditions of the decoration, with a second method for a group ([TaskWorkItem.jl:199](../../../source/platform/task/TaskWorkItem.jl#L199)), `_get_work_item_state` reads the first condition ([TaskGroupToWidget.jl:1416](../../../source/platform/task/TaskGroupToWidget.jl#L1416)), and a cell of the table asks `hasmethod(get_work_item_identifier, …)` to know whether an item is a work item ([TaskGroupToWidget.jl:442](../../../source/platform/task/TaskGroupToWidget.jl#L442)). The flag `work_item = true` of a decoration means another thing: "the icon states the state". A row of the background work and a step of a work plan set it and are no rows of the Tasks pane.
- **Example:**

  ```julia
  # Today, in each kind:
  icon = status in (:running, :cancelling) ? :loader : status === :done ? :circle_check : ...
  condition = status === :in_progress ? DocumentCondition(:running) : ...
  _is_work_item_running(item) = any(c -> c.name === :running, get_document_decoration(item).conditions)

  # After: a kind answers one small value, and the look and the tests derive from it.
  get_work_state(document::TaskDocument) = WorkState(:running)          # one of six names
  get_work_state(step::WorkPlanStep) = WorkState(is_blocked(step) ? :waiting : ...)
  is_work_running(item) = get_work_state(item).name === :running
  ```

- **Problem:** Logic reads a value that is made for display, so a change of the look of a state can change what the Stop button does. The eleven status vocabularies of Table A stay (they come from different sources), but each needs its map written with care, and the maps already differ: a skipped step of a plan and a blocked step both show `:stopped`.
- **Proposal:** One small value for the state of work (pending, running, stopping, done, failed, stopped), which a kind answers by one method. The icon, the condition, the word in a "state" column and the test "does it run" derive from it once. The work item interface gets this method, so the Tasks pane asks the item and not its decoration, and needs no `hasmethod`.
- **What goes away:** six chains of status to icon and condition; `_is_work_item_running` with its special method; the `hasmethod` test.
- **What stays:** every stored status as it is, the result codes and their roles, the counts and the detail of each decoration.
- **Risk and open questions:** The codes of a result add a role that the six names do not carry (an unexpected FAIL is a warning, an ERROR is red); the decoration of a task keeps that part. This is near the domain slice (decoration), another area.
- **Related plans:** [an-assistant-shows-its-turns-in-the-tree.md](../../../plan/pending/an-assistant-shows-its-turns-in-the-tree.md) (pending; adds more kinds with a `:running` condition, each by hand).
- **Check:** weakened. Value low (was medium). I opened the six maps, `DocumentDecoration.jl:1-230`, `TaskWorkItem.jl` and `TaskGroupToWidget.jl:432-448` and `:1408-1422`. The six maps exist. The main claim does not hold: the conditions of a decoration are not the look. [DocumentDecoration.jl:1](../../../source/platform/domain/DocumentDecoration.jl#L1) says that a kind names its state as conditions from one list, and that the look of each condition is defined once, in `get_condition_look`. [TaskWorkItem.jl:1](../../../source/platform/task/TaskWorkItem.jl#L1) and [task.md:462](../../../documentation/package/platform/task/task.md#L462) say that the state of a work item comes from its decoration. So `_is_work_item_running` reads the shared vocabulary of states by design, and a change of a look can not change what the Stop button does. The proposal goes the wrong way: `WorkState` with six names would be a second vocabulary of states beside `DocumentCondition`, which already has `:pending`, `:running`, `:done`, `:failed` and `:stopped`. The chains of icons would stay in part, because the kinds have states outside the six names with an icon of their own (skipped, deferred, blocked, requires action, not as expected). What holds, all small:
  1. The icon of a work item for the shared states (`:loader`, `:circle_check`) is written in four kinds, and could come once from the condition, inside the mechanism that exists.
  2. `hasmethod(get_work_item_identifier, …)` at `TaskGroupToWidget.jl:442` and `applicable(start_task, …)` at `:1491` ask the method table where a declared answer would do.
  3. The flag `work_item` of a decoration ("the icon states the state") and the work item of the Tasks pane share a name and mean two things.

### WL-8 Eleven session documents repeat the same four methods

- **Kind:** repeated-by-hand · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 7 (generic before special) and 6 (state belongs to an editor).
- **Today:** A session document is a document that an editor keeps once, such as its message log. Each kind writes a getter `get_session_x(; editor) = editor isa Editor ? get_session_document!(X, editor, X) : X()`, a `make_insertion_document` and a `make_pred_document` that call it, and a `pred_arguments` that writes no field. Eleven kinds do so, for example [MessageLogDocument.jl:120](../../../source/platform/log/MessageLogDocument.jl#L120), [McpLogDocument.jl:97](../../../source/platform/mcplog/McpLogDocument.jl#L97), [GestureLogDocument.jl:208](../../../source/platform/gesturelog/GestureLogDocument.jl#L208), [FrameStatisticsDocument.jl:125](../../../source/platform/statistics/FrameStatisticsDocument.jl#L125), [BackgroundWorkDocument.jl:69](../../../source/platform/backgroundwork/BackgroundWorkDocument.jl#L69), [TaskGroupList.jl:109](../../../source/platform/task/TaskGroupList.jl#L109). A trait for one part exists: `is_session_explorer_entry_type` puts the session document of a type in the explorer ([TreeInterface.jl:105](../../../source/platform/tree/TreeInterface.jl#L105)).
- **Example:**

  ```julia
  # Today, for each kind:
  pred_arguments(::McpLog) = (), Pair{Symbol,Any}[]
  get_session_mcp_log(; editor = find_evaluation_editor()) =
      editor isa Editor ? get_session_document!(McpLog, editor, McpLog) : McpLog()
  make_insertion_document(::Type{McpLog}) = get_session_mcp_log()
  make_pred_document(::Type{<:McpLog}, positional, keywords) = get_session_mcp_log()

  # After: one declaration, and the defaults follow.
  is_session_document(::Type{McpLog}) = true
  get_session_document(McpLog)                 # the one getter, with the editor of the evaluation
  ```

- **Problem:** A kind that forgets `make_pred_document` loads as a new empty document from a window file, which nothing fills. Each new log repeats the five lines.
- **Proposal:** One trait, `is_session_document(type)`, with defaults for the three methods and one generic getter. The named getters that carry a docstring for the assistant stay as one-line calls.
- **What goes away:** about 50 lines in eleven files.
- **What stays:** one document for each editor, the insertion aliases, the load from a window file.
- **Risk and open questions:** Three kinds make their document with a function that first looks into the window (the task list, the explorer, the assistant list); the trait needs a maker method for them.
- **Related plans:** none found.
- **Check:** confirmed. Value low. I counted with grep: eleven `make_pred_document` methods answer a session getter, and eleven `make_insertion_document` methods do (ten of the same kinds and the explorer; the open file list has none). Four methods repeat, not five (the title is corrected). More kinds than three need a maker: the background work log and the open file list build their table (`_make_background_work_log`, `_make_open_file_list`), and the workflow list runs its constructor with the editor of the evaluation. The named getters carry the docstrings for the assistant and stay, so the saving is about three lines for each kind, near 35 lines and not 50. The generic getter exists in part: `ApplicationExplorer.jl:42` already calls `get_session_document!` for each type of `is_session_explorer_entry_type`. The proposal loses no feature and keeps the rule that a session document belongs to its editor.

### WL-9 The debugger of a process model brings its state in outside the feed mechanism

- **Kind:** partial-feature · **Value:** low · **Effort:** small · **Confidence:** medium
- **Principle:** `PAR-STORE-THEN-DRAIN`, and 7 (one mechanism). Other area: the process domain.
- **Today:** A realized process model writes a `ProcessTrace`, a plain value, from its own task. `sync_process_debug!` copies the trace into a `ProcessDebugSession` document and sends the commands of the session down ([ProcessDebugSession.jl:137](../../../source/domain/process/ProcessDebugSession.jl#L137)). The source and the document say to call it "from the refresh hook of the editor" ([ProcessDebugSession.jl:49](../../../source/domain/process/ProcessDebugSession.jl#L49)). The kernel has no such hook; I found the words only in the process domain and its document. Only tests call the sync. `start_process`, which is offered to the assistant, starts the model with `Threads.@spawn` ([ProcessDebug.jl:98](../../../source/domain/process/ProcessDebug.jl#L98)) and not with `start_background_work`, so the run has no editor, no stop scope and no record.
- **Example:**

  ```julia
  # Today: the caller must sync by hand, from a place that the editor does not offer.
  run = start_process(model, 1; mode = :step, session)
  sync_process_debug!(session, run.trace, model)        # who calls this in a running editor?

  # After: the trace is a store and a feed drains it, as for a task.
  run = start_process(model, 1; mode = :step, session)  # registers (session, trace, model) with its editor
  # the feed of the editor calls the sync while a view reads the session
  ```

- **Problem:** In a running editor nothing moves the position of a run into the session, so the two views that read the session show nothing, and a command that a person writes into the session reaches no run. The document of the domain lists as a limit that no gesture writes the command or a breakpoint (corrected at the check: it does not say that nothing calls the bridge in a running editor; it tells the caller to call it "from the refresh hook", [process.md:123](../../../documentation/package/domain/process/process.md#L123)).
- **Proposal:** A feed that holds the runs of its editor and calls the sync for each run whose session a view reads; `start_process` registers the run with the editor of the evaluation and starts it as background work. The trace, the probe protocol and the session stay as they are.
- **What goes away:** the words "refresh hook", and the duty of an embedder to call the sync.
- **What stays:** the plain trace with no cell, realized code that runs outside the editor, breakpoints as nodes, the staleness stamp.
- **Risk and open questions:** The state machine domain says that an embedder supplies its runtime; I did not check whether the same gap exists there.
- **Related plans:** [process-domain.md](../../../plan/done/process-domain.md) (done; defers the gestures of the debugger).
- **Check:** confirmed-with-corrections. Value low. `sync_process_debug!` has callers only in `test/domain/process/projection/ProcessDebugTest.jl`. The words "refresh hook" name nothing in `source/kernel`; they stand in the process domain, its document and decision D12 of its plan, which is older than the feed contract. `start_process` starts its task with `Threads.@spawn` at `ProcessDebug.jl:98` and carries the mark for the assistant. Corrections: the document of the domain does not list the missing call of the bridge as a limit (corrected above). The plan defers the gestures of the debugger "to the work on the editor surface", so the debugger in a running editor is work that is not finished, and this finding is advice for that work: use a feed, and start the run as background work of its editor. It is no fault of a feature that runs today. No domain defines a feed today; this one would be the first. The proposal loses no feature.

## Covered by plans

- The stores of the feeds that are constants of the process (`SESSION_TASK_FEED_STORE`, `_SESSION_MCP_LOG_STORE`, `_SESSION_MESSAGE_LOG_STORE`): decision D12 of [the-editor-always-answers-the-person.md](../../../plan/done/the-editor-always-answers-the-person.md) is "B for now, A later", where A gives each editor its own stores; it stays with finding L21-1 of [kernel-audit/21-feed.md](../../../plan/pending/kernel-audit/21-feed.md). One fact for that work: the task feed and the MCP server already know their editor when they write ([TaskFeed.jl:67](../../../source/platform/task/TaskFeed.jl#L67), [McpServer.jl:53](../../../source/adapter/mcp/McpServer.jl#L53)), so only the message log needs a logger for each editor.
- The cost of a burst in the message log, of a flush of the background work log and of a chunk in a terminal: [guards-keep-the-frame-short-at-any-size.md](../../../plan/pending/guards-keep-the-frame-short-at-any-size.md) measures and guards them.
- The contract of a feed (a drain that throws, a deadline that throws, the bound of the inbox): [kernel-audit/21-feed.md](../../../plan/pending/kernel-audit/21-feed.md).
- A file in a tab that a program rewrites, with no read of the disk in a print: [a-tab-shows-the-file-that-a-program-rewrites.md](../../../plan/pending/a-tab-shows-the-file-that-a-program-rewrites.md).
- The filter, the sort and the find of every table: [filter-sort-and-find-any-table.md](../../../plan/pending/filter-sort-and-find-any-table.md).

## Examined and sound

- The feed contract of the kernel (`Feed`, `drain_changes!`, `compute_wake_deadline`, `attach_wake_callback!`): three generics, no state, one inflow model for every producer.
- The background cell (`make_background_cell`, `BackgroundSource`): one acquire mechanism, used by pictures, folders, file text, git, the workspace files and the language server; the search of an explorer is a provisional cell and needs no feed.
- The task slice as an extension point: a kind of task adds methods (`get_task_columns`, `make_task_kind_document`, `find_task_output_mark`), and nothing in the slice knows the work. The background task of an agent is a kind of task and reuses the documents, the feed and the pages.
- The live state of an execution and of a group (`@document [M, C]`, a native layout under a lock and a shadow that `sync_document!` brings up to date): one kernel mechanism, used for both.
- The table of a task group and the Tasks pane: an arrangement of a roster, with the quick choice of rows as a collection in front of it. They reuse the generic table.
- The log of the background work: a plain store in the kernel, a feed that copies only while a view reads, and the generic table. It is the model for WL-1.
- The tree of system processes: the owner of a tree drains it and no registry of trees exists; the read runs off the loop; a tree that no view reads costs no read.
- `WorkPlan` (the plan of an agent, read only, replaced at each update) and `WorkflowStep` (a record that a person edits and a file keeps) are two models on purpose; both show through generic views (the tree slice, the outline kit, the roster). The workflow document states the reason.
- The process domain as a model of an algorithm: it is no "running work" in the sense of a task, and its statuses belong to a debugger.
- The store of the message log as a constant of the process: the Julia logger is one for the process (until D12 A).
- The gesture log writes its document in the reader of a decorator: the reader runs on the task of the editor, and the log is no part of the edited document; the plan of the gesture log records why it is no operation.
- The result codes as strings in three families: they follow `opp_repl` on purpose, and the role of a code gives the colour once.

## Check of the report

A second reviewer checked each finding at commit 3a9b4fae4: it opened the cited lines, counted again with grep, looked for a shared helper and for a stated reason in the documents and the plans, and tried to name what each proposal would lose. It ran no Julia and no test. The item **Check** under each finding holds the detail, and wrong facts are corrected where they stand.

| Id | Verdict | Value after the check | In one line |
| --- | --- | --- | --- |
| WL-1 | confirmed-with-corrections | medium (was high) | The three text printers are copies and the roster reaches the stores. The proposal changes four views, not seven; two logs are not plain appends; the MCP log would lose its transcript look. |
| WL-2 | confirmed-with-corrections | high | The printer and the reader of the stream page read the disk; no plan covers it. Step 2 removes less than it says: the scroll bar and the jump stay code of the page. |
| WL-3 | weakened | low (was medium) | The facts hold. The join as written adds features and loses six behaviours of the terminal. What holds is one helper for a process group and one rule for its end. |
| WL-4 | weakened | low (was medium) | The facts hold. A document can not hold the work, because the work holds the editor, so the maps stay. What holds is that `_TURN_WORKS` moves into a store of its editor. |
| WL-5 | confirmed-with-corrections | medium | The record store and its feed are two copies with a drift. The sampled feed saves about 8 lines for each feed and is not simpler. |
| WL-6 | confirmed | medium | Six pages repeat the grid, the two maps and the reader; one page misses the patches and has the limit. |
| WL-7 | weakened | low (was medium) | The conditions of a decoration are the shared vocabulary of states by design, so a second state value would be a second vocabulary. Three small points stay. |
| WL-8 | confirmed | low | Eleven kinds repeat four methods; the saving is about three lines for each kind. |
| WL-9 | confirmed-with-corrections | low | Only tests call the bridge and no refresh hook exists. The debugger in the editor is deferred work, so this is advice for that work. |

Seen during the check and not in the report:

- A table of a lazy list with a scroll bar that jumps is wired by hand in each page that has one: the page of the frames ([FrameStatisticsToWidget.jl:556](../../../source/platform/statistics/FrameStatisticsToWidget.jl#L556) to :600 and :652), the data frame view (`DataFrameViewToWidget.jl:439`, `:753`, `:878`) and the stream page ([TaskPagesToWidget.jl:416](../../../source/platform/task/TaskPagesToWidget.jl#L416) to :460). Each builds the bar and converts the same writes into a write of its anchor. Check it against the decision that a lazy list counts from its head before a proposal.
- The stream page finds again what the producer knew: it reads the file to find the start of each line ([TaskStream.jl:24](../../../source/platform/task/TaskStream.jl#L24)) and computes the mark of each shown line again ([TaskPagesToWidget.jl:414](../../../source/platform/task/TaskPagesToWidget.jl#L414)), while the reader task of the execution wrote each line and computed its mark ([TaskExecution.jl:540](../../../source/platform/task/TaskExecution.jl#L540)).
