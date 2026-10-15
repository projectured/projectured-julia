# The assistant shows the work of its agent

> **Kind:** plan · **Status:** pending; written 2026-10-15; the owner answered the questions of section 8 on 2026-10-15; no step is started. · **Stands on:** [acp.md](../../documentation/package/adapter/acp/acp.md), [agent.md](../../documentation/package/kernel/agent.md), [assistant.md](../../documentation/package/platform/assistant/assistant.md), [roster.md](../../documentation/package/platform/roster/roster.md), [navigator.md](../../documentation/package/platform/navigator/navigator.md), [task.md](../../documentation/package/platform/task/task.md), [cross-cutting-views.md](../done/cross-cutting-views.md)

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

- [ ] **1. Record what `claude -p` says.** In ClaudeCodeACP. This step runs
  `claude` on the subscription of the owner, which the owner allowed on
  2026-10-15.
  - Record four turns with the model `haiku` in an empty folder, and clean
    them as `test/recorded/README.md` says:
    - a subagent;
    - a background shell command, and a stop of a second one;
    - a plan of three steps, one of them blocked by another;
    - the plan mode, up to `ExitPlanMode`.
  - Write here which events of section 3.1 come, and their fields. If an
    event does not come, the steps below use what comes, and say so here.

- [ ] **2. The tree slice, and a page from a row or a node.**
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

- [ ] **3. The system processes slice.**
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

- [ ] **4. The work plan slice.**
  - `WorkPlan`, `WorkPlanStep`, the statuses, the progress, the blocked
    steps, `WorkPlanToWidget`, the page of a step, and the facets.
  - Tests:
    - the progress at every depth;
    - a blocked step;
    - the three contents of a plan;
    - the step tree in a real `Editor`.

- [ ] **5. The kernel: the events of the work.**
  - The events and the generics of section 4.6, and `AgentEventQueue`.
  - `ScriptedAgentConnection` scripts them.
  - Tests in the agent tests of `ProjecturedKernelTest`. An old
    `AgentPlanEntry(content, priority, status)` still builds.

- [ ] **6. ProjecturedACP: the translation.**
  - The capabilities and the translation of section 4.7. The queue replaces
    `waiting_session_events`.
  - Tests with `FakeAcpAgent`:
    - a child and a child of a child;
    - two plans and a removal;
    - the keys of `_meta.claudeCode`;
    - a background task that ends between two prompts;
    - a stop and a cancel.
  - Run `test_acp()`.

- [ ] **7. The assistant: the documents of the work.**
  - `AgentWork`, `Assistant.agent_work`, `AgentBackgroundTask`,
    `apply_agent_work_event!`, the transcript of a subagent, and the facets.
  - The feed of the window drains the queues.
  - Tests with `ScriptedAgentConnection`:
    - a subagent and its transcript;
    - a background task that ends after the prompt;
    - a plan with a blocked step and a step in progress;
    - the process id of a session.

- [ ] **8. The assistant: the work page.**
  - `AssistantWork` and its view, the page of a subagent, the Work button, the
    three columns of the assistant list, and `show_assistant_work!`.
  - Tests in a real `Editor`:
    - the work page shows the job, the plan and the work tree;
    - a press on a subagent opens its page, and Back returns;
    - a row of a background task opens its detail;
    - the column `plan` of the assistant list follows a plan update.

- [ ] **9. ClaudeCodeACP: the new updates.** This step can start after step 1.
  - The translation of section 4.9, from the recordings of step 1.
  - Tests with the fake `claude` of the package, on the new recordings.
  - Prepare a new version of the package and its entry in the registry. The
    owner publishes it. Then the compat bound of ProjecturedACP follows.

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
