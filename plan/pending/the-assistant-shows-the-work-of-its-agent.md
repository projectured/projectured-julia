# The assistant shows the work of its agent

> **Kind:** plan · **Status:** pending; written 2026-10-15; the owner answered the questions of section 8 on 2026-10-15; steps 1 to 8 are done. · **Stands on:** [acp.md](../../documentation/package/adapter/acp/acp.md), [agent.md](../../documentation/package/kernel/agent.md), [assistant.md](../../documentation/package/platform/assistant/assistant.md), [roster.md](../../documentation/package/platform/roster/roster.md), [navigator.md](../../documentation/package/platform/navigator/navigator.md), [task.md](../../documentation/package/platform/task/task.md), [cross-cutting-views.md](../done/cross-cutting-views.md)

## 1. The request

The owner, 2026-10-15: "My goal would be to allow the user to better understand
what an agent is doing, where it stands in the process, what was done, was is
going to be done, what is the job at hand, get some overview and understanding
of the process and it's state." The examples of the owner: the processes that
the agent started and watches, a tree of the subagents, and the plan of each
assistant with its progress: the completed, the deferred, the skipped and the
remaining steps.

The first answer of the assistant recommended this direction. Map the data of
Claude Code onto the unstable types of ACP that the schema already has. Add one
extension of ACP for background tasks, because ACP has no type for them. The
owner answered "yes, good for a plan", and added:

- "take care of making what is generic in projectured a generic layer. for
  example, a process tree of the claude process and what it's doing can be
  made in a generic document/projection layer"
- "if the presentation displays a table, clicking a row can display the
  details, you may want to use the navigator"
- "also, tree widget for a process or agent tree, step tree in a plan, etc."
- "be clever and make parts of it reusable if possible"

## 2. Words

Claude Code uses the word "task" for two different things, and the task slice
uses it for a third. This plan uses these words:

| Word | What it is | Claude Code | ACP |
| --- | --- | --- | --- |
| **plan step** | one entry of the plan of an agent | a task of `TaskCreate`, `TaskUpdate`, `TodoWrite` | a plan entry |
| **subagent** | an agent that the agent starts for a part of the work | the tool `Agent`; a task of the type `local_agent` | a child session (unstable) |
| **background task** | work that the agent starts and that runs after the call that started it: a shell command with `run_in_background`, a monitor, a workflow | a task of the type `local_bash`, `monitor_*`, `local_workflow`, … | none |
| **task** | a task of the task slice: `AbstractTask`, `TaskDocument` | — | — |
| **system process** | a process of the operating system | — | — |

## 3. What exists

### 3.1 The data

- **ACP version 1, stable.** The protocol has text, thinking, tool calls,
  one flat plan, options, commands, usage and the title of a session. A plan
  entry has `content`, `priority`, and a `status` of `pending`, `in_progress`
  or `completed`.
- **ACP, unstable.** These types are in the generated schema of
  `AgentClientProtocol` 0.1.0 (`src/types.jl`):
  - `subagent_update`: a child session, announced on its parent, with a
    title, a description, a `state` (`running`, `idle`, `requires_action`,
    `unknown`) and a `cancel` capability. The events of the child come on the
    same connection, with the session id of the child.
  - `plan_update` and `plan_removed`: many plans in one session, each with a
    `plan_id`. The content of a plan is `items`, `markdown` or `file`.
  - `notice` and `compaction_update`.
  - The client capabilities `subagents`, `plan`, `session.notices` and
    `session.compaction` turn them on.
- **ClaudeCodeACP drops most of what Claude Code says.**
  - It reads only `system/init`, the stream deltas, the tool uses and the
    tool results ([agent.jl:613](../../../claude-code-acp/src/agent.jl#L613)).
  - It drops every event of a subagent
    ([translation.jl:31](../../../claude-code-acp/src/translation.jl#L31)).
  - Of a plan step, it keeps only the subject and the status
    ([translation.jl:241](../../../claude-code-acp/src/translation.jl#L241)).
- **What Claude Code can say.** The binary of `claude` 2.1.286 has code that
  writes the events below. A recorded stream of `claude -p` holds none of them
  yet, so step 1 checks which events `claude -p` writes.

  | Event | Fields |
  | --- | --- |
  | `system/task_started` | `task_id`, `task_type`, `description`, `subagent_type`, `spawn_depth`, `is_backgrounded`, `prompt`, `tool_use_id` |
  | `system/task_progress` | `usage` (tokens, tool uses, duration), `last_tool_name`, `summary` |
  | `system/task_updated` | a patch: `status`, `end_time`, `error`, … |
  | `system/task_notification` | the last `status`, `summary`, `output_file`, `usage` |
  | `system/background_tasks_changed` | the background tasks that run: `task_id`, `task_type`, `description` |
  | the messages with `parent_tool_use_id` | the transcript of a subagent |
  | `system/compact_boundary`, `system/api_retry`, `system/model_fallback` | the health of the session |
  | the control request `stop_task` | stops one background task |

- **A plan step of Claude Code** has `id`, `subject`, `description`,
  `activeForm`, `owner`, `blocks`, `blockedBy` and a free `metadata` map. Its
  status is `pending`, `in_progress` or `completed`. Neither Claude Code nor
  ACP has a status "skipped" or "deferred".

### 3.2 The generic parts of the editor

- **The roster** shows the items of any source as a table, with facets and an
  arrangement ([roster.md](../../documentation/package/platform/roster/roster.md)).
  `ItemsWithin(source, type)` finds the documents of a type inside the items of
  a source. A press on a row selects its item. A row shows no details.
- **`WidgetTree`** has `roots`, lazy children and node gestures
  ([WidgetDocument.jl:3037](../../source/platform/widget/WidgetDocument.jl#L3037)).
  `expanded` holds the open nodes as paths of indices. When a node comes or
  goes before another one, the paths name other nodes. No projection shows a
  document of any type as a tree: each user builds its own, as
  `FileSystemToWidgetTree` does.
- **The navigator** shows one part of a document as a page, with Back,
  Forward and Parent. A link answers `OpenPageOperation`, and the nearest
  navigator takes it. With no navigator, the editor opens a new tab with a
  navigator. A page shows with the view of its type
  ([navigator.md](../../documentation/package/platform/navigator/navigator.md)).
- **The task slice** has `TaskDocument`, `TaskExecution`, the detail of a
  task, and the facets `name` and `status`
  ([task.md](../../documentation/package/platform/task/task.md)).
  `_read_process_usage` reads the processor time and the memory of one
  process from `/proc`
  ([TaskExecution.jl:421](../../source/platform/task/TaskExecution.jl#L421)).
- **A feed** carries data from another task into the documents: the producer
  writes a store with a lock, and the editor drains it (`PAR-STORE-THEN-DRAIN`;
  `TaskFeed`, [TaskFeed.jl](../../source/platform/task/TaskFeed.jl)).
- **The assistant list** shows the assistants of a window as a table, with
  `describe_assistant_activity` ([AssistantOverview.jl:69](../../source/platform/assistant/AssistantOverview.jl#L69)).
- **The workflow domain** keeps a record of human work as a tree of steps. It
  is a domain package, so the platform can not name it.

### 3.3 What is missing

1. No view shows a document of any type as a tree.
2. A row of a roster shows no details. The roster slice can not name
   `OpenPageOperation`: the operation is in the slice `navigator`, which uses
   `pane`, which uses `roster`
   ([PlatformSuite.jl:61](../../test/platform/PlatformSuite.jl#L61)).
3. No view shows the system processes. `/proc` is read only for the process of
   one task.
4. No document holds a plan with more states than "done" and "not done". The
   assistant shows the plan of its agent as a Markdown checklist in the
   transcript ([ExternalAgentTurn.jl:690](../../source/platform/assistant/ExternalAgentTurn.jl#L690)).
5. The kernel has no event for a subagent, a background task, a notice or a
   compaction. Between two prompts, the connection keeps only the last update
   of four kinds of the session, and gives them to the next prompt. A
   background task that ends between two prompts reaches nobody. The
   connection keeps no `on_event` of a session, and it can not keep one that
   holds the editor, because the assistant document holds the connection
   (`PAR-NO-EDITOR-IN-DOCUMENT`).
6. ProjecturedACP advertises none of the unstable capabilities. ClaudeCodeACP
   sends none of this data.

## 4. The design

### 4.1 Three layers

```
generic, in the platform           any ACP agent                    Claude Code only
────────────────────────           ─────────────                    ────────────────
tree:          DocumentTree    ┐   kernel agent layer:              ClaudeCodeACP:
navigator:     open a page     │     events of the work,              the stream of claude
roster:        (exists)        ├─▶   the queue outside a prompt  ◀──  as ACP updates, and
systemprocess: SystemProcess   │   ProjecturedACP: translation        _session/background_task
workplan:      WorkPlan        │   assistant: AgentWork,
task:          (exists)        ┘     the work page
```

A part of the left column names no agent. A part of the middle column names no
agent program. Only the right column knows Claude Code.

### 4.2 The tree slice: a tree of documents of any type

A new slice `tree`, module `TreeModule`, after `widget` and `natural`.

- **`DocumentTree(root; title)`** is a document that shows `root` as a tree,
  as a `Roster` shows a source as a table. It holds `root`, `title`, and
  `expanded`: the open nodes, kept by the identity of their documents and not
  by their indices. `expanded` is view state, so a save keeps the root and the
  title and no open node. The address of a navigator is data for the same
  reason (decision of 2026-10-06 in navigator.md).
- **Three generics** say how a document is a node. Each has a default, so any
  document is a leaf with a label:
  - `get_tree_children_steps(document)`: the steps from a node to each
    collection of its children, in order. A process has one,
    `[:children]`. The work of an agent has two: its subagents and its
    background tasks. The default is none.
  - `format_tree_node_label(document)`: the text of the node. The default is
    `get_document_title`.
  - `get_tree_node_icon(document)`: a Lucide glyph, or `nothing`.
- **`DocumentTreeToWidgetTree`** prints a `WidgetTree`. A node reads its
  children only when the node is open, as `FileSystemToWidgetTree` does. A
  label reads only the cells of its own document, so a change in one process
  draws one label again.
- **The maps follow the steps.** The path of a node is the path of its parent,
  the steps of its collection, and its index. So the selection maps both ways
  with no code for each type of node.
- **`show_document_tree!(root; title, editor)`** shows a tree in a tab and
  answers a `ReferencedDocument`, as `show_roster!` does.

### 4.3 A row or a node opens a page

The navigator is the way from a table or a tree to the details of one item.

- `OpenPageOperation` moves from the slice `navigator` to the lowest slice that
  it needs, below `roster` and `tree`. Its evaluation and the visit stay in the
  navigator. No other code changes.
- A double click on a node of a `DocumentTree`, or Return on a node, answers
  `OpenPageOperation(nothing, <path of the node>)`.
- A double click on a row of a roster answers `OpenPageOperation(nothing,
  <path of the item of the row>)`.
- Inside a navigator, the item opens as a page and Back returns to the table
  or the tree. With no navigator, the editor opens a new tab with a navigator,
  as it does now for any link. The menu items "Open as a page" and "Open in a
  new tab" of the navigator already work on a selected item.
- A slice gives an item type a page view only where the page must look
  different from the row. The steps below give a page view to a system
  process, a plan step and the work of an agent. A background task uses the
  detail of a task.

### 4.4 The system processes slice

A new slice `systemprocess`, module `SystemProcessModule`, before `task`. The
domain `process` holds flowcharts, so the slice does not take the name
`process`.

- **`SystemProcess`** is one process: `process_id`, `parent_process_id`,
  `command` (the command line), `folder` (the working folder), `state`
  (running, sleeping, waiting for the disk, stopped, zombie), `start_time`,
  `processor_load`, `memory`, `thread_count` and `children`.
- **`SystemProcessTree(root_process_ids; title)`** holds the processes below a
  set of roots. The tree slice shows it: `get_tree_children_steps` is `[:roots]`
  for the tree and `[:children]` for a process. The label says the process id,
  the command, the load and the memory.
- **The sample.** A task off the editor task reads `/proc` once in an interval
  (1 s), only while a view reads the tree (`has_dependent_cells`, as the clock
  does). It writes a snapshot into a store with a lock, and a feed syncs the
  snapshot into the documents on the editor task. The sync keeps a document
  by its process id and its start time, so a process id that the system gives
  again is a new document. A process that ended leaves the tree.
- **The reader takes the root folder**, `/proc` by default, so a test reads a
  folder of fixed files.
- **A roster source**, `SystemProcesses(root_process_ids)`, gives the same
  documents as a flat table. `load` and `elapsed` are facets; the other
  columns are fields.
- **The page of a process** shows its facts and two buttons: Interrupt
  (`SIGINT`) and Stop (`SIGTERM`).
- **The task slice uses the slice.** `_read_process_usage` moves to
  `read_system_process_usage`, and the detail of a running task shows the tree
  of the processes below its process. So a build or a simulation run shows
  its compilers or its workers with no new code in their domains.
- **Limit.** Only Linux has `/proc`. On another system the tree is empty and
  says why.

### 4.5 The work plan slice

A new slice `workplan`, module `WorkPlanModule`, after `tree`. The name `Plan`
is not used: the umbrella exports the names of the platform, and so short and
general a name can collide with a name of another package in the code of a
person.

- **`WorkPlanStep`**: `id`, `title`, `active_title` (what the view shows while
  the step runs, Claude's `activeForm`), `description`, `status`, `priority`,
  `reason`, `blocked_by` (the ids of other steps) and `children`.
- **The statuses** are `:pending`, `:in_progress`, `:completed`, `:skipped`
  and `:deferred`. A pending step whose blocker is not completed shows as
  blocked (`is_work_plan_step_blocked`); "blocked" is not a status. No agent
  gives `:skipped` or `:deferred` in this plan (answer 2 of section 8). The
  Markdown plans hold that information now, and a later reader of them fills
  the two statuses.
- **`WorkPlan`**: `id`, `title`, and one of three contents, as the content of
  an ACP plan: `steps`, a Markdown `text`, or the `uri` of a file.
- **`compute_work_plan_progress(plan)`** counts the steps of each status, at
  every depth. `describe_work_plan_progress(plan)` writes it, for example
  `3 of 7 completed, 1 in progress, 1 skipped, 1 deferred`.
- **The view** `WorkPlanToWidget` shows the progress as a line and a bar, and
  the steps as a `DocumentTree`: the step tree. A plan with a text shows it as
  the transcript shows prose. A plan with a file shows a link that opens the
  file.
- **The page of a step** shows its title, its status, its description, its
  reason and its blockers.
- **Facets** for a roster: `status`, `title`, `blocked`.
- A person does not edit a plan of an agent: the next update of the agent
  replaces it.

### 4.6 The kernel: the work of an agent

The agent layer of the kernel gets the events below. They name no agent
program. A field that is `nothing` in an update keeps its last value, as for
`AgentToolCallUpdate`.

| Event | What changes |
| --- | --- |
| `AgentPlanEntry` | new fields `id`, `description`, `active_title`, `blocked_by` |
| `AgentPlanUpdate` | new fields `id` (empty for the one plan of ACP version 1), `markdown`, `uri`, `is_removed` |
| `AgentSubagentUpdate` | new: `id`, `title`, `description`, `state`, `stop_reason`, `usage`, `can_cancel`, and `event`: one event of the subagent, such as its text or a tool call. A subagent of a subagent comes as an update inside an update. |
| `AgentBackgroundTaskUpdate` | new: `id`, `kind`, `title`, `status`, `tool_call_id`, `subagent_id`, `output_uri`, `summary`, `usage`, `start_time`, `end_time`, `can_stop` |
| `AgentNoticeUpdate` | new: `severity`, `title`, `description` |
| `AgentCompactionUpdate` | new: `id`, `status`, `summary` |
| `AgentSessionInfoUpdate` | new field `process_id`: the system process of the session |

Two generics act on the work: `cancel_agent_subagent!(connection, session_id,
subagent_id)` and `stop_agent_background_task!(connection, session_id,
task_id)`.

**The events outside a prompt.** A connection puts each event that comes
between two prompts into an `AgentEventQueue` of the session, a list with a
lock that holds no editor. `open_agent_session!` takes the queue. The assistant
gives the window a feed that drains the queues of the assistants that the
window shows, as the task feed drains the executions (`PAR-STORE-THEN-DRAIN`).
The four kinds of the session that wait for the next prompt now go through the
queue too, so there is one path for an event outside a prompt.

`ScriptedAgentConnection` of `ProjecturedKernelExample` can script each new
event, so a test of the assistant needs no agent.

### 4.7 ProjecturedACP: the translation

- `initialize` advertises `subagents`, `plan`, `session.notices` and
  `session.compaction`, and `_meta.backgroundTasks` for the extension.
- A `subagent_update` becomes an `AgentSubagentUpdate`. The connection keeps
  the parent of each child. A `session/update` of a child becomes an
  `AgentSubagentUpdate` with the event of the child, one level for each parent,
  and the child keeps its own frame of text blocks (`AcpTurn`).
- A `plan_update` becomes an `AgentPlanUpdate` with its id, and a
  `plan_removed` becomes one with `is_removed`. A `plan` of version 1 becomes
  one with an empty id. The package reads the keys `taskId`, `description`,
  `activeForm` and `blockedBy` of `_meta.claudeCode` of an entry, and no other
  key. acp.md lists them, as it lists `toolName` now.
- The notification `_session/background_task` becomes an
  `AgentBackgroundTaskUpdate`. `stop_agent_background_task!` sends the request
  `_session/stop_background_task`. `cancel_agent_subagent!` sends
  `session/cancel` with the session id of the child, when the child has the
  capability.
- `session_info_update._meta.processId` gives the `process_id`. An agent in a
  child process that does not send it gets the process id of that child.
- Every event that comes outside a prompt goes into the queue. The field
  `waiting_session_events` goes away.

### 4.8 The assistant: the work of its agent

**The documents.**

- **`AgentWork`** is the work of one agent session: `id`, `title`,
  `description`, `state`, `stop_reason`, `usage`, `conversation`, `plans`
  (`WorkPlan`s by id), `background_tasks` (`TaskDocument`s), `subagents`
  (`AgentWork`s), `notices` and `processes` (a `SystemProcessTree`).
- **`Assistant` gets the field `agent_work`**, the work of its own session. The
  title, the state, the usage and the transcript of that session stay in the
  fields of the assistant that hold them now. A subagent has its own in its
  `AgentWork`.
- **A subagent has a transcript.** Its `conversation` is filled by the
  handlers that fill the transcript of the assistant. So a subagent shows its
  prompt, its text, its tool calls and its plan as the assistant does.
- **A background task is a task.** `AgentBackgroundTask <: AbstractTask` is a
  kind of task that the agent runs and the editor only watches. Its
  `TaskExecution` has no process. The events write its status, its times and
  its result. Its columns, its facts, and a Stop button come from the task
  slice. Stop calls `stop_agent_background_task!`. The output file is a link
  that opens the file.
- **One function applies an event**, `apply_agent_work_event!`, for an event
  of a prompt and for an event of the feed.
- **A file keeps no agent work.** It is the live state of a session.

**The work page.**

- **`AssistantWork(assistant)`** is a document that holds an assistant and
  shows its work, as `WorkflowJournal` holds a workflow and shows its journal.
  It opens in a navigator:
  - **the job**: the title, the first prompt, and the plan of the plan mode
    when the agent has one;
  - **now**: the activity (`describe_assistant_activity`), the step in
    progress with its `active_title`, the elapsed time, and the use of the
    context;
  - **the plans**, each with `WorkPlanToWidget`;
  - **the work tree**: a `DocumentTree` of the session, its subagents and
    its background tasks, at every depth;
  - **the processes**: a `DocumentTree` of `agent_work.processes`;
  - **the notices** and the compactions, the newest first.
- **The pages.** A press on a node or a row opens its item in the navigator:
  - a subagent shows its own work page: its job, its plan, its transcript and
    its background tasks;
  - a background task shows the detail of a task;
  - a process and a plan step show the pages of their slices.
- **The way in.** A Work button in the tab of an assistant, and in each row of
  the assistant list. The verb `show_assistant_work!(assistant; editor)` does
  the same for code and for the assistant.
- **The assistant list gets three columns**, which are also facets of
  `Assistant`:
  - `plan`: for example `3/7`;
  - `subagents`: how many run;
  - `background tasks`: how many run.

### 4.9 ClaudeCodeACP

The agent sends the new updates only to a client that advertises them.

- **Subagents.**
  - A `task_started` of the type `local_agent` announces a child session with
    `subagent_update`. Its id is the `task_id`, and its title is the
    `description`.
  - `task_progress` and `task_updated` change the state and the usage. The
    `summary` and the last tool go in `_meta`.
  - `task_notification` makes the child idle, with its stop reason.
  - A message with `parent_tool_use_id` goes to the child of that tool call,
    through the same translation as a message of the session. Each child has
    its own `TurnState`.
- **Background tasks.**
  - The other types of task send `_session/background_task`.
  - `_session/stop_background_task` sends the control request `stop_task`.
- **Plans.**
  - The plan steps of `TaskCreate`, `TaskUpdate` and `TodoWrite` go as a
    `plan_update` of the type `items`, with the id `tasks`.
  - The id, the description, the `activeForm` and the blockers of a step go
    in `_meta.claudeCode`.
  - The input of `ExitPlanMode` goes as a `plan_update` of the type
    `markdown`, with the id `plan-mode`.
- **Health.**
  - `compact_boundary` sends a `compaction_update`.
  - `api_retry` and `model_fallback` send a `notice`.
- **The process.** `session_info_update._meta.processId` gives the process id
  of the `claude` of the session, also after a restart for a new option.

### 4.10 What reuses what

| Need of the request | Generic part | Also used by |
| --- | --- | --- |
| the process tree of the agent | `systemprocess` and `tree` | the detail of every running task: builds, simulation runs |
| the tree of the subagents and the background tasks | `tree` | the step tree of a plan, the process tree |
| the plan, its progress, and the skipped and the deferred steps | `workplan` and `tree` | any plan that a slice makes later |
| a background task | the task slice: `TaskDocument`, its facets, its detail | every roster of tasks |
| a click on a row or a node shows the details | the navigator and `OpenPageOperation` | every roster and every tree |
| the transcript of a subagent | the transcript of the assistant | — |
| lists across the session | `ItemsWithin` of the roster | all the background tasks of all the assistants, all the subagents, all the processes of the agents, with no new code |

For example, `show_roster!(ItemsWithin(TabDocuments(Assistant), TaskDocument);
columns = ["name", "status", "within.title"])` lists the background tasks of
every assistant of a window.

## 5. New mechanisms that need the word of the owner

1. The slices `tree`, `systemprocess` and `workplan`, with the documents
   `DocumentTree`, `SystemProcess`, `SystemProcessTree`, `WorkPlan` and
   `WorkPlanStep`, and the generics of section 4.2.
2. `OpenPageOperation` in a lower slice. The answer of a node and of a row to
   a double click is that existing operation. No new event and no new payload.
3. The events and the two generics of section 4.6, and `AgentEventQueue` with
   its feed in place of `waiting_session_events`.
4. The ACP extension: the notification `_session/background_task`, the request
   `_session/stop_background_task`, and `_meta.backgroundTasks`. The keys of
   `_meta.claudeCode` that section 4.7 lists.
5. `AgentWork`, `AgentBackgroundTask`, `AssistantWork`, the field
   `Assistant.agent_work`, and the three columns of the assistant list.

## 6. Steps

Do the work of projectured-julia in a worktree, on the branch `agent-work`, off
`main`. Do the work of ClaudeCodeACP in a worktree of its repository, on a
branch of the same name. Make one commit for each step. Mark each step done
here, and write here what the step finds. A branch lands on `main` only with
the word of the owner.

For each step, run the narrowest test: the test files of the step. Do not run
`test_all()`.

- [x] **1. Record what `claude -p` says.** In ClaudeCodeACP. This step runs
  `claude` on the subscription of the owner, which the owner allowed on
  2026-10-15. Done 2026-10-15, ClaudeCodeACP `b720da0`.
  - Record four turns with the model `haiku` in an empty folder, and clean
    them as `test/recorded/README.md` says:
    - a subagent;
    - a background shell command, and a stop of a second one;
    - a plan of three steps, one of them blocked by another;
    - the plan mode, up to `ExitPlanMode`.
  - Write here which events of section 3.1 come, and their fields. If an
    event does not come, the steps below use what comes, and say so here.
  - **What the step found** (`claude -p` 2.1.286, `haiku`; the files are
    `subagent.jsonl`, `background-task.jsonl`, `plan-steps.jsonl` and
    `plan-mode.jsonl` in `test/recorded/` of ClaudeCodeACP):
    - The task events come. Each system event also has `uuid` and
      `session_id`.
      - `task_started`: `task_id`, `tool_use_id`, `description`, `task_type`
        and `is_backgrounded`. A subagent also has `subagent_type`,
        `spawn_depth` and `prompt`.
      - `task_progress`, for a subagent only: `usage` (`total_tokens`,
        `tool_uses`, `duration_ms`), `last_tool_name` and `description`.
      - `task_updated`: `task_id` and a `patch` of `status` (`completed`,
        `killed`) and `end_time`.
      - `task_notification`: `status` (`completed`, `stopped`),
        `output_file` and `summary`. A subagent also has `usage`.
      - `background_tasks_changed`: the whole list of the background tasks
        that run, each with `task_id`, `task_type` (`local_agent`,
        `local_bash`) and `description`.
    - `compact_boundary` and `api_retry` did not come: a turn this small does
      not cause them. Step 9 takes their shapes from the binary, and no
      recording tests them.
    - **A subagent sends no stream events.** Its `assistant` and `user`
      messages carry `parent_tool_use_id`, the id of the `Agent` call, and its
      `stream_event`s have none. So the text of a subagent comes as whole
      messages, not as deltas. The `task_id` of a subagent is its agent id,
      and its `tool_use_id` is the id of the `Agent` call.
    - **`claude` starts a turn by itself** when a background subagent or a
      background command ends after the `result` of a turn. A second `result`
      follows with no message on the input. ClaudeCodeACP reads the events of
      `claude` only while a prompt runs, so the events of that turn wait until
      the next prompt and go to it. Step 9 adds a reader that runs between two
      prompts and sends those events as updates outside a prompt, which step 6
      puts into the queue.
    - A background command starts with `Bash` and `run_in_background: true`.
      Its result has `backgroundTaskId`. The stop is `TaskStop` with
      `{task_id}`, which `claude` loads with `ToolSearch`. A stop gives
      `background_tasks_changed`, `task_updated` (`killed`) and
      `task_notification` (`stopped`).
    - **`TaskCreate` comes only with `CLAUDE_CODE_ENABLE_TASKS=1`.** Without
      the variable, `claude -p` has `TodoWrite` (its result has `oldTodos` and
      `newTodos`) and no `TaskCreate`. ClaudeCodeACP does not set the variable
      and translates only `TaskCreate` and `TaskUpdate`, so the plan of the
      real agent can stay empty now. Step 9 translates `TodoWrite` too and
      sets no variable: the agent runs `claude` as the person configured it.
      `TaskUpdate` with a blocker has the input `{taskId, addBlockedBy}`.
    - **`ExitPlanMode` needs a permission tool.** With
      `--permission-prompt-tool`, as the agent runs `claude`, the plan mode
      asks for `ExitPlanMode` with the input `{plan}` (Markdown) and
      `planFilePath`. Without it, the plan mode writes a file under
      `~/.claude/plans/` with `Write`.
    - The `Agent` tool is named `Task` in the list of tools of `init`.

- [x] **2. The tree slice, and a page from a row or a node.** Done 2026-10-15.
  - `OpenPageOperation` moves below `roster` and `tree`.
  - `DocumentTree`, `DocumentTreeToWidgetTree`, the three generics,
    `expanded` by identity, `show_document_tree!`.
  - A double click on a node or a row answers `OpenPageOperation`.
  - Tests in `test/platform/tree/`:
    - a tree of plain test documents;
    - the selection both ways;
    - an open node stays open when a node comes before it;
    - a label draws again alone when its document changes;
    - in a real `Editor`, a double click on a node and on a row of a roster
      opens a page in a navigator, and Back returns.
  - **What the step found and decided:**
    - `OpenPageOperation` is a fragment of `WidgetModule`,
      `source/platform/widget/OpenPageOperation.jl`, beside
      `ContextMenuOperation.jl`, with its constructor and its four methods.
      `NavigatorModule` uses it and no longer exports it. Its docstring no
      longer names the navigator, because a lower slice does not describe its
      consumers (`PAR-NO-CONSUMER-DOCS`). What the navigator does with an open
      that no navigator takes is now the comment of its `evaluate_operation`,
      in `NavigatorPageOpen.jl`, with `find_navigator_target` and
      `_find_opened_content`. Markdown, rst and the data frame adapter reach
      the name through `PlatformModule`, and need no change.
    - A binding of a `WidgetTreeNode` answers in the frame of the
      `WidgetTree`: the reader of the tree returns the answer of the node as it
      is, and does not put the path of the node before it. So
      `OpenPageOperation(nothing, EmptyReference())` from a node would name
      the widget, not the node. The binding of a node answers
      `OpenPageOperation(nothing, roots[1].children[k]…)`, the path of its own
      node, and `DocumentTreeToWidgetTree` maps it to `root.<steps>[i]…`. The
      widget slice does not change. A node knows its path because each node is
      made again when the collections of its parent change.
    - Each node is two lazy lists of its children. The entries give the
      document of each child and its index path, and read only the collections
      of the parent. The widget nodes read the text and the icon of the
      document, and take their children from the entry. So a change of the
      text of one document computes its own `WidgetTreeNode` again, and its
      children are the same list.
    - `expanded` is an `IdDict{Any,Nothing}` whose keys are the open
      documents. A walk of the documents enters a dict by its values, so
      `search_documents` does not find the open documents a second time. A
      `Base.IdSet` keeps its keys in a `Memory` field, which the walk enters.
    - A chevron answers `ReplaceViewStateOperation(ReplaceReferencedValueOperation(widget,
      "expanded", paths))`, a write that carries the widget as its root. The
      reader of `DocumentTreeToWidgetTree` turns it into the same write of
      `expanded` of the `DocumentTree`, with the documents at those paths.
    - The open paths of the widget walk the open nodes only. So a node under a
      closed node leaves `expanded` at the next write, and a node that opens
      again shows its children closed. The widget alone keeps the paths of the
      nodes under a closed node.
    - A document that is again on the path to its own node stays closed there,
      so a cycle of documents does not open without end.
    - The row of the natural renderer is
      `ChainingProjection(DocumentTreeToWidgetTree(), RecursiveProjection(FaultCatchingProjection(WidgetToGraphics(…))))`,
      as the row of the workspace draws the tree of the files.
    - The default title of a `DocumentTree` and of `show_document_tree!` is the
      label of the root. `show_document_tree!` is declared to the assistant as
      `show_roster!` is: `TreeModule => (:DocumentTree, :show_document_tree!)`
      in `make_application_api`, and one sentence in `APPLICATION_SYSTEM`.
    - A double click on a row of a roster is a `read_intent` of
      `RosterRowsToWidget` of its own, below `_is_index_step`, away from the
      lines that the branch `roster-scroll` changes. It adds
      `OpenPageOperation(nothing, [r].item)` when the answer of a plain double
      click selects the item of a row, as the view of a data frame does.
    - The entry of the test is `test_document_tree()`, not `test_tree()`:
      `ProjecturedTest` defines and exports `test_tree()`, the guard of the
      repository tree, and it uses `ProjecturedPlatformTest`.

- [x] **3. The system processes slice.** Done 2026-10-15.
  - `SystemProcess`, `SystemProcessTree`, the sample, the store and the feed,
    the roster source, the facets, and the page of a process.
  - The task slice reads `/proc` through the slice. The detail of a running
    task shows its process tree.
  - Tests:
    - a fixed `/proc` folder gives a known tree;
    - a reused process id is a new document;
    - no view, no sample;
    - a real child process tree of `sleep` shows and leaves;
    - the detail of a running task shows its process.
  - **What the step found and decided:**
    - **The schedule refines section 4.4.** Section 4.4 said "a feed syncs the
      snapshot" and named no feed. The read of `/proc` runs off the editor
      task, on a task of `Threads.@spawn`, and writes only into the sampler of
      its tree, under its lock. The sync runs on the editor task. There is no
      registry of trees: each owner drains its own trees from a feed that its
      window already has. `show_system_process_tree!` adds one
      `SystemProcessFeed` to `editor.feeds` (the first tree adds it, the next
      ones reuse it) and puts the tree in it. The tree of a task is drained by
      the feed of the tasks, `drain_task_feed!`, which finds it through the
      owner of each execution. `drain_system_process_tree!` syncs a read that
      ended and starts the next one once in the interval, only while
      `has_dependent_cells` holds for the cell `roots`. A read is synced at the
      first drain after it ends, so a view shows a sample at most one interval
      old. The read does not wake the editor; `compute_wake_deadline` answers
      the time to the next sample.
    - The slice is `source/platform/systemprocess/`, eight fragments:
      `SystemProcessRead.jl` (`SystemProcessRecord`, `read_system_processes`,
      `read_system_process_usage`, `get_clock_ticks_per_second`),
      `SystemProcessDocument.jl` (the two documents, the sampler, the tree
      generics, the facets, `format_memory_size`), `SystemProcessSignal.jl`,
      `SystemProcessSync.jl` (the sync, the drain, the deadline,
      `SystemProcessFeed`), `SystemProcessTreeToDocumentTree.jl`,
      `SystemProcessToWidget.jl`, `SystemProcessRoster.jl`
      (`SystemProcesses`) and `SystemProcessProgram.jl` (the two verbs).
    - The read takes the children from `task/<tid>/children` of every thread.
      It needs `btime` in `<root>/stat` for the start time, so a folder with no
      `stat` answers no records, as a missing folder does. A process whose
      `stat`, `statm` or `cmdline` can not be read is gone and left out, and so
      are the children that only it named. A `cwd` that can not be read is an
      empty `folder`.
    - **The start ticks are a field**, `SystemProcess.start_ticks`: with the
      process id it is the key of a document in the sync, of the processor ticks
      in the sampler, and of the guard of a signal.
    - **The elapsed time reads one shared cell.** The field `sampled_at` of each
      process is the cell `sampled_at` of its tree itself, so the page and the
      facet `elapsed` read the time of the sample with no clock, and one write in
      a sync moves the elapsed time of every process. A sync writes the time at
      which the read began, not the time of the drain, so the load and the
      elapsed time are those of the read. A sync with no change writes only
      `sampled_at`, and a sync at the same time writes no cell.
    - A list of children, and `roots`, is replaced by a new `CellVector` only
      when its members are not the same documents in the same order.
    - `root_process_ids` reads back as a `CellVector`, because `@document` wraps
      a vector field; the drain collects it before the read.
    - The sampler is the private `_SystemProcessSampler`, marked
      `is_walk_opaque`, so `search_documents` does not enter its task or its
      lock. A tree is one document with its sampler in a field, so the way of
      `TaskExecution`, a runtime in the native layout only, does not apply.
    - The feed holds its trees strongly. A tree is an immutable struct (the cell
      layout), and a `WeakRef` to it does not hold its identity. A tree that no
      view reads costs one check in each drain.
    - `_read_process_usage` moved as `read_system_process_usage`, and the
      behaviour of `sample_task_usage!` is the same. `get_clock_ticks_per_second`
      is public, because the load of a task and the load of a process both
      divide by it. `format_memory_size` moved from the task slice to this one,
      which the label of a process needs and which loads first;
      `ProjecturedPlatform` still exports it.
    - **The tree slice draws through the seam.** `DocumentTree` now gives
      `make_graphics_projection` in place of `register_natural_graphics!(:tree,
      …)`. The pane of a group draws a card with a widget renderer that reads
      only that seam, and the natural renderer reads it too, so the tree draws
      in both. `SystemProcessTree` and `SystemProcess` draw through the seam as
      well.
    - A `SystemProcessTree` shown alone prints, through
      `SystemProcessTreeToDocumentTree`, a `DocumentTree` of itself, whose paths
      are its own below `root`. Its open nodes live as long as that print.
    - The page of a process is `SystemProcessToWidget`. Interrupt and Stop are
      `WidgetButton`s whose action calls `interrupt_system_process!` and
      `stop_system_process!`, as `_make_task_action_button` calls an action of a
      kind. Each signal reads the start ticks of the process id from `root`
      (`/proc` by default) and sends nothing when they changed; the keyword is
      what the test of the guard sets to a fixture folder.
    - The icon table has no `:cpu`. A process node uses `:terminal`
      (square-terminal).
    - `SystemProcesses(tree)` has one part, the tree. A root has `within =
      nothing`.
    - **The tree of a task is a computed field of `TaskDocument`**,
      `process_tree`, as `result_document` is: the `SystemProcessTree` of the
      process of the current execution while it has a process and no result,
      made when a view first reads it, and `nothing` after. `drain_task_feed!`
      calls the private `_drain_task_process_tree!(owner, now)` for each entry at
      each drain: a `TaskDocument` and the slot of a group drain the tree when
      its cell is valid, so a task that no view looked at makes no tree. The
      detail of a task shows it in an embedded card after the buttons and before
      the card of the result. The maps of the pane find both cards by their
      places, from `_CARD_FIELDS`; a task that ended has no tree, so the card of
      the result stays the seventh part.
    - The two verbs are declared to the assistant as `show_document_tree!` is:
      `SystemProcessModule => (:show_system_process_tree!,
      :describe_system_process_tree)` and one sentence in `APPLICATION_SYSTEM`.
      Their docstrings do not say "find" or "pane".
    - **An empty tree says why in the text of its root node.** The tree keeps
      the folder that it reads, `/proc` by default, in its sampler
      (`SystemProcessTree(ids; root)`). When that folder is not there,
      `format_tree_node_label` of the tree answers "No /proc on this system:
      the processes can not be read." in place of the title, and
      `describe_system_process_tree` says the same in its text. The node text
      keeps the tree generic: a leaf under the root would need a child that is
      no process, in `roots` or in a second collection of children.
    - The entry of the test is `test_system_process()`, which no other test
      package defines. It ran 72 tests (78 with the empty tree); `test_document_tree` 66,
      `test_task_execution` 43, `test_task_document` 83, `test_task_views` 36,
      `test_task_group_verbs` 23, the layering 21 and the edges 1, all passing.

- [x] **4. The work plan slice.** Done 2026-10-15.
  - `WorkPlan`, `WorkPlanStep`, the statuses, the progress, the blocked
    steps, `WorkPlanToWidget`, the page of a step, and the facets.
  - Tests:
    - the progress at every depth;
    - a blocked step;
    - the three contents of a plan;
    - the step tree in a real `Editor`.
  - **What the step found and decided:**
    - **A step holds a link to its plan.** Blocked is a relation between the
      steps of one plan, and the label, the icon and the facet of a step, and
      its page, get only the step (`format_tree_node_label(step)`,
      `compute_item_facet(step, …)`, the page of a navigator). In general a
      document does not know its parent, because a document can sit in two
      places. So a plan gives its own steps a link that a walk does not
      follow, and only the plan sets it. `WorkPlanStep.plan` holds the private
      `_WorkPlanLink(plan, step_tree)` of its plan, or `nothing`; the plan keeps
      the same holder in its field `link`, and `is_walk_opaque` holds for it.
      `WorkPlan(id; steps)` and `set_work_plan_steps!(plan, steps)` link every
      step at every depth. Step 7 writes the steps of a plan of an agent only
      through `set_work_plan_steps!`. A step with no plan is never blocked, and
      its page shows the ids that it waits for with no link. The label, the
      icon, the facet and the page call `is_work_plan_step_blocked(plan, step)`
      when they read, so a view follows a status of a blocker.
    - **The tree of the steps lives in the link.** `step_tree` of
      `_WorkPlanLink` is the `DocumentTree` of the plan, titled "Steps", which
      the first view of the plan makes. So its open nodes stay when a view
      draws the plan again, and a walk does not find the plan again below it.
    - A file keeps the id, the title and the content (`pred_arguments` leaves
      out `link` and `plan`), and the constructors make the links again when
      the file is read. A copy of a plan has a link of its own, and its copied
      steps link to the copy; a step copied alone has no plan. A copy of
      another kind of cell (`copy_document(K, plan)`) keeps the link of the
      original: not handled, and no test.
    - **`OpenFileOperation` moved to the widget slice** (`36794425b`), as step
      2 moved `OpenPageOperation`: the slices `workplan` and `assistant` load
      before `filesystem`, and both show a link to a file (the file of a plan,
      and in step 8 the output file of a background task). The evaluation stays
      in `FileSystemDocument.jl`. The docstring of the operation still says "a
      tab, a pane or a page": `search_api` ranks "find pane" by a margin of
      0.008 (`find_pane` 1.758, `find_pane_reference` 1.750), and without the
      word the order turns and `test_referenced_document_editor` fails.
    - **The prose of a text** goes through `make_prose_document(text)`, a new
      public function of the natural slice (`NaturalNotation.jl`): the Markdown
      parser of the seam when one is registered for `:md`, else a text block.
      The conversation (`finalize_draft!`) and the assistant (`_prose_part`
      and the plan part of an external agent) call it in place of their own
      copies.
    - The slice is `source/platform/workplan/`, four fragments:
      `WorkPlanDocument.jl` (the documents, the link, the tree generics, the
      facet), `WorkPlanProgress.jl`, `WorkPlanToWidget.jl` and
      `WorkPlanStepToWidget.jl`. It loads after `systemprocess` and before
      `assistant`, and uses collection, layout, natural, projection, roster,
      serialization, style, tree and widget.
    - **The content of a plan** is its steps, else its text, else its file; a
      plan with none shows its steps, which say "no steps". A `file://` prefix
      of the `uri` is dropped, and nothing else of a URI is read.
    - **The progress.** `WorkPlanProgress(total, pending, in_progress,
      completed, skipped, deferred, blocked)`; `pending` counts the blocked
      steps too, and the words say "pending" for the pending steps that are not
      blocked, so the parts add up to the total. The bar shows the share of the
      completed steps.
    - **The label of a step** is its active title while it is in progress and
      has one, else its title, then " · " and its status or "blocked by step
      2, 3", the blockers that are not completed. The icons: pending `:circle`,
      in progress `:loader`, completed `:circle_check`, skipped
      `:skip_forward`, deferred `:circle_pause`, blocked `:stop`, and the plan
      `:list`. The label of a plan is its title (else "Plan"), " · " and its
      progress.
    - **The views draw through the seam**, each chained to
      `VerticalLayoutToGraphicsCanvas()`, so the parts come back through the
      recursion of the renderer, which draws the tree of the steps and the prose
      with their own rows. A path `steps[i]…` of the plan is the path
      `children[3].child.root.steps[i]…` of the view. The parts that a view
      builds after the print take their paths from the layout; the tree
      document takes its part and no more, because its root is the plan.
    - **A blocker link** on the page of a step is a button that answers
      `OpenPageOperation(plan, steps[i]…)`. A navigator whose content is the
      plan, or which has the plan on the address of its page, opens it as a
      visit, and Back returns.
    - **Facets.** `status` and `title` are fields of `WorkPlanStep`, and a facet
      with the name of a field of its own type is an `ArgumentError`, so the
      only facet is `blocked`.
    - The entry of the test is `test_work_plan()`, which no other test package
      defines. It ran 82 tests; `test_document_tree` 66, the layering 21, the
      edges 1, `test_external_agent_turn` 269, `test_conversation_editor` 40,
      and the guards of the names, the exports and the arguments, all passing;
      `test_parse_markdown_blocks` passes 12 of 13, and its failure is item 5 of
      `the-suites-of-main-pass-again.md`. For the move:
      `test_open_page_operation` 61, `test_filesystem` 84, `test_file_dialog`
      14, `test_markdown_link_target` 11, `test_workflow_catalog_to_widget` 13,
      `test_tool_views` 19 and `test_referenced_document_editor` 110 pass;
      `test_application` has 2 failures and 2 errors, which are item 8 of
      `the-suites-of-main-pass-again.md`.

- [x] **5. The kernel: the events of the work.** Done 2026-10-15.
  - The events and the generics of section 4.6, and `AgentEventQueue`.
  - `ScriptedAgentConnection` scripts them.
  - Tests in the agent tests of `ProjecturedKernelTest`. An old
    `AgentPlanEntry(content, priority, status)` still builds.
  - **What the step found and decided:**
    - **The fields.** `AgentSubagentUpdate(id; title, description, state,
      stop_reason, token_count, tool_call_count, duration, last_tool, summary,
      can_cancel, event)` and `AgentBackgroundTaskUpdate(id; kind, title,
      status, tool_call_id, subagent_id, output_uri, summary, start_time,
      end_time, can_stop)` replace the one `usage` of section 4.6 by the counts
      that a view shows. `duration` is in seconds; `start_time` and `end_time`
      are seconds since 1970, as `time()`. A background task has no usage.
    - **The prompt of a subagent is an `LlmMessage(:user, …)`** in the `event`
      of an `AgentSubagentUpdate`. No event of the kernel says "a prompt": the
      text events are an answer, and `description` is the role of the
      subagent. `LlmMessage` is the type of the kernel for a message of a role,
      and no new type was needed. So `event` is
      `Union{Nothing,AgentEvent,LlmEvent,LlmMessage}`.
    - `AgentNoticeUpdate(severity, title, description)` has a `String`
      description, empty when the agent gives none: a notice is no patch.
      `AgentCompactionUpdate(id, status, summary)` is a patch: `nothing` keeps
      the summary, an empty one clears it.
    - `AgentPlanEntry` holds a vector of blockers, so it defines `==` and
      `hash` by its fields; a test that compares entries compares their values.
      `AgentPlanUpdate(entries; id, markdown, uri, is_removed)` takes its
      entries positionally, also when they are empty, because a definition
      takes no optional positional argument beside keywords.
    - **The queue lives in `AgentConnectionEvent.jl`**, beside the events that
      it holds: `AgentEventQueue` (a lock and a `Vector{Any}`),
      `put_agent_event!` and `take_agent_events!`. A new fragment would need a
      place in the audit inventory of `SEALING.md` for three short names.
    - The defaults: `cancel_agent_subagent!` does nothing and answers
      `nothing`; `stop_agent_background_task!` answers `false`.
    - **`ScriptedAgentConnection`** keeps the queue of each open in
      `sessions[k].events`, and a test puts an event between two prompts with
      `put_agent_event!(connection.sessions[k].events, event)`, so it needs no
      new name. `subagent_cancels` and `background_task_stops` record each call
      as `session_id => id`; a stop answers `true`.
    - `agent.md` still says that the session kinds wait for the next prompt;
      step 10 changes it with the other documents.
    - Tests: `test_agent_connection_event()` and
      `test_scripted_agent_connection()` are new in `test/kernel/agent/`, and
      `test_agent_defaults()` checks the two defaults. With
      `test_kernel_layering()` and `test_agent_loop()` they ran 127 tests, all
      passing; `test_external_agent_turn()` ran 269, all passing, with the old
      constructors.

- [x] **6. ProjecturedACP: the translation.** Done 2026-10-15.
  - The capabilities and the translation of section 4.7. The queue replaces
    `waiting_session_events`.
  - Tests with `FakeAcpAgent`:
    - a child and a child of a child;
    - two plans and a removal;
    - the keys of `_meta.claudeCode`;
    - a background task that ends between two prompts;
    - a stop and a cancel.
  - Run `test_acp()`.
  - **What the step found and decided:**
    - **One path for every update.** `receive_notification` finds, under the
      lock, the `AcpTurn` that takes the updates of a session
      (`_find_session_turn!`): the prompt that runs; else, for a child, its
      own frame, whose `on_event` wraps each event in an
      `AgentSubagentUpdate` of the child and gives it to the turn of its
      parent; else, for a session with a queue, a frame whose `on_event` puts
      into the queue. The frames live in `session_frames`. The four kinds of
      the session go the same way and need no frame. The start of a prompt
      closes the frame of its session between two prompts, so the last stop
      of that text goes to the queue.
    - **An update before the answer of an open.** `claude-agent-acp` sends its
      commands just after its answer to `session/new`, and the reader can give
      them before the open has the id. While an open waits
      (`opening_count`), an update of a session with no queue and no parent
      waits in `opening_events`; the open puts it into the queue of its
      session, and the end of the last open drops the rest. So the buffer is
      bounded by the time of an open. `waiting_session_events` used to keep
      them for the next prompt.
    - **The idle state of a child closes its open block**, as the end of a
      prompt closes the block of a prompt; a child's text arrives as whole
      messages, so its last block has no other end.
    - **The prompt of a subagent** is `LlmMessage(:user, [LlmText(text)])`,
      one for each `user_message_chunk` of a child session, which closes the
      open block of the child first. A chunk of a session of the client still
      gives no event.
    - `plan_update`, `plan_removed` and `plan` close the open block, as `plan`
      did; `notice`, `compaction_update` and `subagent_update` do not.
      `compaction_summary_chunk` gives no event. A notice of an unknown
      severity is `:info`; a subagent state that the client does not know is
      `:unknown`. The token count of a subagent comes from
      `_meta.claudeCode.usage.totalTokens`, else from the `usage` of its idle
      state.
    - `_session/background_task` comes through the method of
      `ACP.receive_notification` for a method that the protocol does not name,
      and goes where an update of its session goes, also through the parents
      when its session is a child.
    - `cancel_agent_subagent!` sends `session/cancel` with the id of the child
      and does not check `can_cancel`: the caller shows the button only when
      the subagent can be cancelled. `stop_agent_background_task!` waits 30 s;
      a timeout throws, as for the other requests.
    - The process id of a child agent is the `process_id` that the transport
      of `AgentClientProtocol` keeps; the queue gets it first, before the
      waiting events. The transport test gives a child agent an answer to
      `session/new` and checks it.
    - `close_agent_session!` forgets the queue, the frames and the children of
      the session (`_forget_session!`).
    - **Until step 7**, the assistant gets the new events during a prompt and
      does not apply them: each one closes its open text block, and a plan of
      Markdown or a removal replaces the checklist of the plan with an empty
      one, because ClaudeCodeACP now sends `plan_update` to this client.
    - `acp.md` has the new rows of the translation table, the sections "Where
      an event goes", "The work of an agent" and "The keys of
      `_meta.claudeCode`", the capabilities, and two new limits: a
      permission request of a child session is cancelled, and a summary chunk
      of a compaction gives no event.
    - Tests: `test_acp()` ran 248 tests, all passing, with the layering guard;
      the naming, export, argument and documentation guards pass.
    - **What the review changed** (`16b1a9b07`; `test_acp()` 301 tests pass):
      - `stop_agent_connection!` forgets every session of the agent that
        ended. Before a frame goes (at a stop, at a second open of the same
        id, at `close_agent_session!`), the event that closes its open block
        goes into its queue, and its waiting requests are answered as
        cancelled.
      - A child that becomes idle keeps only its parent, in a record of at
        most 256 finished children for each root session, which the close of
        the root clears. A late `_meta`-only update still reaches the root and
        adds no entry. A finished child that gets `running` again is a child
        again, because ACP lets an agent use an idle child again.
      - A `session_message` or a `session_message_chunk` to a child is its
        prompt. A permission request or a form of a child goes to its root,
        wrapped in one `AgentSubagentUpdate` for each level. A request of a
        root session between two prompts goes into its queue and is no longer
        cancelled. The two limits of acp.md about them are gone.
      - `compaction_summary_chunk` adds its text to the summary.
      - One frame for each id while an open waits, given to the registration.
      - A `null` title or description of a subagent clears it, and a `null`
        state gives `:unknown`. The text keys of a background task clear the
        same way.
      - A `subagent_update` that names its own session or one of its parents
        as the child is ignored, with a warning.
      - The reviewer also found that the two paths, the queue before a prompt
        and `on_event` during it, have no order between them. Step 7 puts both
        into the same queue.

- [x] **7. The assistant: the documents of the work.** Done 2026-10-15.
  - `AgentWork`, `Assistant.agent_work`, `AgentBackgroundTask`,
    `apply_agent_event!`, the transcript of a subagent, and the facets.
  - The feed of the window drains the queues.
  - Tests with `ScriptedAgentConnection`:
    - a subagent and its transcript;
    - a background task that ends after the prompt;
    - a plan with a blocked step and a step in progress;
    - the process id of a session.
  - **What the step found and decided:**
    - **The assistant slice loads after the task slice.** It loaded before
      `pane`, and the task slice uses `pane`, so `AgentBackgroundTask <:
      AbstractTask` could not be written. The include of `assistant` moved to
      just after `task`, and `task` to just before `shell`, the first slice that
      uses the assistant; no slice between them uses either. The table of the
      edges gives `assistant` the edges `systemprocess`, `task` and `workplan`.
    - Two new fragments: `AgentWorkDocument.jl` (`AgentNotice`, `AgentWork`,
      `AgentBackgroundTask`, `AgentBackgroundTaskResult`, what the task slice
      asks of a background task, the facets), included first because
      `Assistant` declares a field of `AgentWork`; and `AgentEventFeed.jl`
      (`apply_agent_event!`, the turns, the prompt, the work, `AgentEventFeed`).
    - **The name is `apply_agent_event!(editor, assistant, event)`.** It applies
      every event of a session, its text too, not only the work, so "work" left
      the name. It takes the editor first, as the other functions of the turn do:
      the forms of a tool call take their live results from `editor.tools`, and a
      failed event is a fault of `editor`. No state that a document reaches holds
      the tool set, which binds the editor in its scratch module.
    - **One path, one order** (an addition of the review of steps 5 and 6). The
      `on_event` of a prompt puts each event into the queue of its session and
      calls `wake_editor!`; the feed applies the queue in the next frame. An
      editor whose loop does not run on another task, as in a test, applies the
      queue at once on the task of the turn. The start of a prompt, on the
      editor task, applies the events that wait, ends a turn that the agent
      started by itself, and makes the state of the prompt the one that takes the
      events; the end of a prompt applies the events that wait before it cancels
      the questions and lets the state go. The stop reason and the split of a
      steered turn stay with the turn.
    - **The states of the turns live in `ExternalAgentSession`**, which is no
      data: `events` (the queue), `prompt_turn`, `agent_turn`,
      `waiting_requests`, `subagent_turns` (by the `AgentWork` of each
      subagent) and `prompt_end_time`. The session is now opaque to the walk of
      the documents (`is_walk_opaque`), so a search does not find a part a
      second time through a state.
    - **A turn that the agent starts by itself** (addition 2): a text, a
      reasoning, a tool call, a plan or a question between two prompts begins a
      new assistant turn; an `AgentUsageUpdate` between two prompts, or the next
      prompt, ends it and closes its open blocks. An event that only ends a block
      begins no turn.
    - **The questions** (addition 3): a question of the session between two
      prompts is a card in the turn that the agent started by itself; it stays
      open after that turn ends (`waiting_requests`), and the end of the next
      prompt cancels it when nobody answered. A question of a subagent is **one
      request in two parts**: a part of the transcript of the subagent, whose end
      cancels it, and a part of the turn of the session that runs, where the
      person looks. An answer in either is the answer of both, and the reply goes
      to the `reply` of the event once. Its title names the subagent:
      `The subagent “Explore” asks to run: …`.
    - **The plan parts of the transcript** are one part for each plan id, so a
      Markdown plan is a prose part "Plan" with its text, beside the checklist,
      and a removal or a plan in a file changes no part. An event of the work (a
      subagent, a background task, a notice, a compaction) no longer closes the
      open text block of the session, which step 6 left so.
    - **A plan of the work.** The plan with an empty id has the title "Plan";
      another plan has its id as its title. A step keeps its document from one
      update to the next by its id, and only its changed fields are written, so
      a view keeps its open steps; an entry with no id is named by its place
      (`"1"`, `"2"`, …). The steps are written through `set_work_plan_steps!`,
      and only when the list of the documents changed.
    - **`AgentBackgroundTask` holds `summary` and `can_stop` too**: the task is
      the facts of the agent about it, a plain immutable value. An update that
      changes one writes a new value into the cell `task` of the `TaskDocument`,
      so the views follow; a task that ended can not be stopped. Its execution
      starts at its first status (`update_task_execution!`, then the shadow,
      `add_task_execution!` and `register_task_execution!` with the store of the
      session) and ends at `completed`, `failed` or `stopped` with
      `finish_task_execution!` and `AgentBackgroundTaskResult` (DONE, ERROR,
      CANCEL), with the end time of the agent. A summary that comes after the end
      is in the task, not in the result.
    - **The window gets a `TaskFeed` with its first session** when it has none:
      the window of ProjecturEd has none, and without it the shadow of a
      background task would never sync.
    - The output file is a fact line (`output: <path>`) and a button "Open the
      output" of `get_task_actions`, which evaluates `OpenFileOperation`; Stop is
      a button while `can_stop`. Stop finds the assistant of the session in
      `get_session_assistant_list().assistants`; a refusal of the agent is a
      notice "The agent did not stop …".
    - A compaction is a notice whose title says its status, such as "The context
      was compacted", with its summary as the description.
    - A reset of the conversation starts an empty `AgentWork` too.
    - **The end of a connection ends its work** (a review of the step). The ends
      are `stop_external_agent!` (also the close of a tab and a reset), a turn
      whose connection failed or stopped, and a start of the agent that failed;
      the next start of the agent comes after one of them. The work of the
      session then ends at once on the editor task, because the agent may send
      nothing more, as when its process died: each background task that runs
      ends as `CANCEL` with the reason "The agent ended.", each subagent that
      runs or waits for a person becomes idle with `:cancelled` and its turn
      ends, every question that waits is cancelled, and a turn that the agent
      started by itself ends. After a failed prompt, the end comes after the
      events of the prompt that still wait. The feed asks for no frame for a
      session that closed, and lets its queue go at the next drain.
    - The new lines keep to 90 characters, in the style of their neighbours.
    - Tests: `test_agent_work()` is new, in
      `test/platform/conversation/AgentWorkTest.jl`; it ran 151 tests: the
      eight cases of the brief, the order of a queued event and an event of a
      prompt, a turn that the agent starts by itself, a question of a subagent
      that the person answers, a question between two prompts, the end of the
      work at a stop and at a failed connection, and a live loop. The live loop
      is `run_editor!` on a `HeadlessBackend`, whose default wait sleeps 10 ms;
      a step of the script reads the work just after it sent a notice, and the
      notice is not applied yet, because the feed of the loop applies it in a
      frame. `test_external_agent_turn()` ran 269, `test_assistant_overview()`
      63, `test_assistant_list()` 49, the layering 21, the edges 1,
      `test_acp()` 301, `test_assistant_mvp()` 186 with its 4 known broken,
      `test_assistant_composer_panel()` 84, all passing; `test_application()`
      has 368 passing, 2 broken, and the 2 failures and 2 errors of item 8 of
      `the-suites-of-main-pass-again.md`. The naming, export and argument
      guards pass, and the style guard has only its known failure at
      `TextDocument.jl:438`.
    - Not checked: a real agent, and the views of step 8.

- [x] **8. The assistant: the work page.** Done 2026-10-15.
  - `AssistantWork` and its view, the page of a subagent, the Work button, the
    three columns of the assistant list, and `show_assistant_work!`.
  - Tests in a real `Editor`:
    - the work page shows the job, the plan and the work tree;
    - a press on a subagent opens its page, and Back returns;
    - a row of a background task opens its detail;
    - the column `plan` of the assistant list follows a plan update.
  - **What the step found and decided:**
    - **The navigator slice loads before the assistant slice**, just after
      `task`: `show_assistant_work!` makes a `Navigator`. The assistant gets the
      edges `navigator`, `pane` and `tree`, and the task slice the edge `tree`.
    - **`AssistantWork(assistant)`** holds the assistant, the computed fields
      `subagents`, `background_tasks`, `plans` and `processes`, which follow the
      `agent_work` of a new session, and two trees: `work_tree`, a
      `DocumentTree` whose root is the page itself, labelled "This session", and
      `process_tree`, a `DocumentTree` of `processes` computed while the agent
      names a process. An address names a part of the work through the computed
      fields, such as `subagents[1]` or `subagents[1].background_tasks[2]`, so no
      container and no root work stands on it: Parent from a top-level subagent
      returns to the page, and `is_navigator_stop` needs no method.
    - **The walk.** `AssistantWork` is opaque to the walk, as `AssistantList`
      and `Roster` are: a walk reaches the work once, through the tab of the
      assistant. A file keeps only the assistant of the page
      (`pred_arguments`); the page draws the work again.
    - **The view** `AssistantWorkToWidget` is the natural row
      `ChainingProjection(AssistantWorkToWidget, VerticalLayoutToGraphicsCanvas())`:
      a column of cards in a scroll pane of its own, which fills the page: The
      job, the plan of the plan mode, Now, each other plan, Work, Processes (or
      "The agent gives no process."), and Notices, the newest first. A plan and a
      tree stand in `make_embed_card`. The card of a plan follows its plan, which
      holds its own paths; a tree takes its paths from its card, as the step tree
      of `WorkPlanToWidget` does, because the page made it. The maps lead
      `subagents…` and `background_tasks…` to `content.root…` of the card of the
      work tree, `processes…` to `content.root…` of the card of the processes,
      and `plans[j]…` to `content…` of the card of the plan. The elapsed time of
      Now reads the clock only while a turn runs.
    - **A double click inside a scroll pane opened nothing.** The reader of a
      scroll pane (`_retarget_op` in `WidgetToGraphics.jl`) re-rooted only a list
      of operation types and passed any other on unchanged, so an
      `OpenPageOperation` lost the step `content`, while a selection kept it. Its
      fallback now maps any operation that names a place through
      `operation_reference` and `retarget_operation`, as `reroot_operation` of
      the kernel does. This also re-roots `OpenTooltipOperation` and
      `ArrangeCollectionOperation` from inside a scroll pane; the suites of the
      navigator, the tree, the work plan, the tooltip, the scroll pane, the
      routed gestures and the arrangement pass.
    - **The page of a subagent** is the natural row of `AgentWork`,
      `AgentWorkToWidget`: a header with its title, its type (`description`), its
      state, its tokens, tool calls and duration, its last tool and its summary,
      and Cancel while it runs and `can_cancel`; its plans; its transcript, the
      card of its `conversation`, which the renderer draws as a transcript; and
      a link to each of its subagents and its background tasks, a button that
      answers `OpenPageOperation(work, subagents[i])`. Cancel finds, at the
      press, the assistant of the list of the assistants whose work holds the
      subagent, and calls `cancel_agent_subagent!` on a task of its own.
    - **A lone `TaskDocument`** has a natural row of the task slice,
      `TaskDocumentToWidgetPane`, which shows the detail of the task with the
      builder that the pane of a group uses (`_build_task_detail_parts`): its
      name and state, its facts, its process and its elapsed time, its result,
      its earlier executions, its buttons and its two streams. Stop shows while
      the execution has a process; a lone task has no Run again and no cards.
      The node of a task in a tree is a leaf: "name · status · elapsed", with an
      icon of its status.
    - **The nodes of the work.** The children of a work are its subagents, then
      its background tasks. A subagent says its title, its state, its last tool
      while it runs and its tokens, with an icon of its state.
    - **`show_assistant_work!(assistant; editor)`** shows the page of the
      assistant that a tab of the window shows already, which it reads with
      `collect_pane_tab_contents` over each `PaneTree` of the window, else opens
      `Navigator(AssistantWork(assistant))` titled "Work · " and the title of the
      assistant, and answers the `AssistantWork` in its window.
      `find_pane_tab_layer` is not exported, and a qualified use of it breaks
      `PAR-MODULE-BOUNDARY-IS-API`. The verb is declared to the assistant
      (`AssistantModule => (:show_assistant_work!,)` and one sentence in
      `APPLICATION_SYSTEM`); its docstring says neither "find" nor "pane".
    - The tab of an assistant with an external agent has a Work button (the icon
      `:list`) after the picture button, and each row of the Assistants pane a
      Work button after Show, and the columns `plan`, `subagents` and
      `background tasks`.
    - Tests: `test_assistant_work()` is new, in
      `test/platform/conversation/AssistantWorkTest.jl`, in a real editor; it
      ran 78 tests. `test_agent_work()` ran 151, `test_external_agent_turn()`
      269, `test_assistant_overview()` 63, `test_assistant_list()` 49, the
      layering 21, the edges 1, `test_assistant_composer_panel()` 84 and
      `test_referenced_document_editor()` 110, all passing. For the scroll pane
      and the task detail: the navigator suites (326), `test_document_tree` 66,
      `test_work_plan` 82, `test_system_process` 78, `test_task_views` 36,
      `test_task_document` 83, `test_task_group` 76, and the tooltip, scroll
      pane, routed gesture, widget forward, mouse target and arrangement tests
      pass. The naming, export and argument guards pass; the style guard has
      only its known failure.
    - Not checked: a real agent, the page in a live window, the Cancel of a
      nested subagent, and a tooltip inside a scroll pane in a live window.

- [ ] **9. ClaudeCodeACP: the new updates.** This step can start after step 1.
  - The translation of section 4.9, from the recordings of step 1.
  - Tests with the fake `claude` of the package, on the new recordings.
  - Prepare a new version of the package and its entry in the registry. The
    owner publishes it. Then the compat bound of ProjecturedACP follows.
  - **The code is done** (ClaudeCodeACP `976708f`, `51cc8fc`, `f839b94` and
    `4dfddf6`; 319 tests pass). The version and the entry in the registry are
    not prepared yet. The bullets below are the state after the review; where
    a later bullet says otherwise, the later one holds.
    What the code found and decided:
    - **One reader for each `claude` process** (`_follow_claude!`) replaces
      `_follow_turn!`. While a prompt runs, it gives the events to the prompt,
      and the prompt waits on `session.prompt_end`. Between two prompts, it
      sends each event as an update at once. So the turn that `claude` starts
      by itself reaches the editor at once.
    - The messages:
      - `_session/background_task` has the params `{sessionId, taskId, kind,
        title, status, startTime, canStop, toolCallId?, subagentId?,
        outputUri?, summary?, endTime?}`. Each notification holds the whole
        state of the task. The times are epoch milliseconds. `claude` gives no
        start time, so `startTime` is the time at which the agent reads
        `task_started`. `killed` becomes `stopped`. `canStop` is true only
        while the task runs. `subagentId` names the subagent whose `Bash` call
        started the task, when the agent finds it.
      - `_session/stop_background_task {sessionId, taskId}` answers `{}`, or
        `INVALID_PARAMS` for a task that is unknown or does not run. It sends
        the control request `stop_task` to `claude`.
      - `_meta.claudeCode` of a plan entry is `{taskId?, description?,
        activeForm?, blockedBy?}`.
      - `_meta.claudeCode` of a subagent update is `{usage?: {totalTokens,
        toolUses, durationMs}, lastToolName?, summary?}`. It grows, and each
        update sends all of it. The idle state goes once.
      - `session_info_update` with `_meta: {"processId": <int>}` and no title.
        It goes in the first prompt after each start of `claude`, because at
        `session/new` the client does not know the id of the session yet. It
        needs no capability.
      - A cancel of a child session sends `stop_task` for that subagent.
    - **The plan of the plan mode comes from the permission request.** The
      `tool_use` of `ExitPlanMode` has the input `{}` in the stream; the plan
      is only in the question for the permission. So the agent sends the
      `PlanMarkdown` when it asks the editor. A `plan` in the input of the tool
      is read too, and not sent twice.
    - **The end of `claude` ends its work.** When `claude` ends or starts
      again, each subagent that runs becomes idle with `cancelled`, and each
      background task that runs gets a last notification: `stopped` when the
      agent closed or interrupted `claude`, `failed` when `claude` ended by
      itself. Events of a process that the session no longer holds are
      dropped.
    - A client with no `plan` capability now gets the old `plan` update from
      `TodoWrite` too; it got nothing before.
    - Not checked against a real `claude`: whether `claude -p` takes
      `stop_task` on its input, the health events (their shapes come from the
      binary), and a subagent of a subagent (a unit test covers it).
    - **What the review of the code changed** (`f839b94`, `4dfddf6`):
      - **Which `result` ends a prompt.** A `result` ends a prompt when the
        prompt is cancelled, when every message of the prompt was taken, or
        when it is past the results of the turns that ran when the prompt sent
        its message. So the error `result` of a turn that `claude` started by
        itself does not end a prompt that `claude` has not taken yet, and a
        prompt whose turn fails before the echo still ends. A turn starts with
        `system/init`, or an `assistant`, `user` or `stream_event` with no
        `parent_tool_use_id`. Limit: an event that is still in the pipe at the
        send is not counted.
      - A prompt that failed at its `result` no longer starts `claude` again,
        so the background work of `claude` lives on.
      - **A later `_session/background_task` carries only the keys that
        changed**, with `sessionId` and `taskId`. The first one carries the
        whole state. Step 6 merges them.
      - The `_meta` of a subagent: a finished subagent is dropped, with its
        state. Its parent stays known, because `claude` sends the `summary`
        and the last `usage` in the `task_notification` after the
        `task_updated` that made it idle. That late event sends one
        `SubagentUpdate` with only `_meta`.
      - `_session/stop_background_task` waits up to 10 s for the
        `control_response` of `claude`, and answers its error.
      - `_meta.processId` goes only to a client that advertises
        `_meta.backgroundTasks`, so a client of version 1 sees the old updates.
      - The plan of the plan mode of a subagent goes in the child session of
        that subagent, and only when the editor is asked for the permission.
      - The maps of finished subagents, finished background tasks and tool
        calls are emptied, so a long session does not grow them.
      - One lock covers the sends of the reader, the end of the work and a
        restart. Work of a `claude` that crashed is `failed`.

- [ ] **10. The live check and the documentation.**
  - Run the editor with a signed-in Claude Code, as the owner allowed on
    2026-10-15:
    - give a prompt that starts a subagent and a background command;
    - drive the work page by pushed SDL events;
    - write here what showed.
  - New design documents: `tree.md`, `systemprocess.md` and `workplan.md`.
  - Changes to `acp.md`, `agent.md`, `assistant.md`, `roster.md`,
    `navigator.md` and `task.md`, and the index of the package documents.
  - `test_documentation()` passes.

## 7. Not in this plan

- A Markdown file of a plan, such as a file of `plan/pending/`, read as a
  `WorkPlan`.
- A formal way for an agent to say that it skipped or deferred a plan step
  (answer 2 of section 8).
- A link from a background task to its system process: no key joins them
  exactly, and a match by the text of a command is a guess.
- A tree with columns.
- The files of Claude Code under `~/.claude` as a source: the transcripts and
  the plan steps of a past session.
- The commits that a session made.
- Another ACP agent, such as `claude-agent-acp`. It gets the generic parts when
  it sends the unstable updates.
- `post_turn_summary` and `session_state_changed` of Claude Code: one looks
  internal, and the other needs an environment variable.
- The system processes on macOS and Windows.

## 8. The answers of the owner (2026-10-15)

1. **Steps 1 and 10 run `claude` on the subscription of the owner.** "agreed".
2. **A line in the system text of ClaudeCodeACP, to ask Claude to write
   `metadata.outcome` for a skipped or a deferred plan step.** "not necessary
   for now, the markdown plans do have that information now, we can make the
   formal later". So the line is not in this plan. `WorkPlanStep` keeps the
   statuses `:skipped` and `:deferred` for a later reader of the Markdown
   plans, and the kernel and ACP carry no such status.
3. **The page of a process has Interrupt and Stop.** "yes, I want".
