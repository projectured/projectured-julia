# An assistant carries a long study to its end, and a person follows every stage

> **Kind:** plan · **Status:** pending, written 2026-10-24 from a survey of
> `main` at `4c83985`. Every decision of §5 waits for the owner. · **Sibling
> plan:** omnet-julia
> `plan/pending/the-assistant-carries-out-an-aloha-study-on-the-legacy-simulator.md`,
> which holds the arc, the study and the simulation half. · **Stands on:**
> [agent.md](../../documentation/package/kernel/agent.md),
> [assistant.md](../../documentation/package/platform/assistant/assistant.md),
> [task.md](../../documentation/package/platform/task/task.md),
> [chart.md](../../documentation/package/domain/chart/chart.md),
> [research.md](../../documentation/package/domain/research/research.md),
> [workflow.md](../../documentation/package/domain/workflow/workflow.md),
> [a-study-records-questions-evidence-and-decisions.md](../done/a-study-records-questions-evidence-and-decisions.md),
> [a-study-and-a-workflow-read-as-one-quiet-outline.md](../done/a-study-and-a-workflow-read-as-one-quiet-outline.md)

A study of a simulation is long work: tens of turns, runs that take minutes,
and a record that grows the whole time. The sibling plan carries one out in
the window of `omnet_ide`. This plan builds the parts of it that belong to the
platform and that any long work of an assistant uses:

1. a turn whose budget of rounds fits the work, and that says when it ran out;
2. a turn that waits for a task group, and an assistant that resumes by itself
   when a group it started ends;
3. a verb that makes a plan of work, so a person sees the stages ahead;
4. intervals on the points of a chart;
5. a check of a prediction that holds the result it read;
6. a conversation kept with the study, with the model that wrote each turn.

## 1. What exists today

Every row was checked in the code on 2026-10-24.

| thing | where | state |
| --- | --- | --- |
| the rounds of a turn | `Agent(llm, tools; system, max_rounds = 8, thinking)` in `source/kernel/agent/Agent.jl`; the loop in `AgentLoop.jl` | the assistant builds `Agent(llm, set; system, thinking = true)` in `AssistantTurn.jl`, so every turn has eight rounds; at the cap the loop logs a warning and ends, and the turn's `stop_reason` is that of the last round |
| what a turn holds | `ConversationTurn(role, parts, stop_reason, collapsed, start_time, finish_time)` | no backend and no model |
| how a turn starts | `SubmitProseOperation`, `SubmitDraftTurnOperation`, `_send_user_turn!`, `_launch_agent_turn!`; a message typed during a turn waits (`_has_waiting_message`) | only a person starts a turn |
| a group of tasks | `TaskGroup` with `runtime.finish`, called with the group when its last task ends; `TaskGroupDocument`; `wait_for_task_group!(editor, group)` | the wait has no deadline; a group does not know who started it |
| the code a model runs | `execute_julia_code` runs in a code unit; `get_current_code_unit()`; `wait_in_code_unit` | a stop of the unit ends a wait |
| a workflow | `WorkflowStep` (the root is a step), `add_workflow_step!`, `change_workflow_state!`, `add_element!`, `record_workflow_decision!`, `add_workflow_entry!` | no verb makes a workflow and opens it; `start_study!` does so for a study |
| the plan of an agent | `WorkPlan`, `WorkPlanStep` of the work plan slice; `apply_agent_event!` writes each `AgentPlanUpdate` of an external agent into the `plans` of its `AgentWork` | read only, owned by the agent, replaced at each update, not in a study folder; the built-in backends give none |
| a series of a chart | `ChartLineSeries(label, x, y; …)`, `ChartScatterSeries`, `ChartBarSeries`, … | a point has no interval |
| a check of a prediction | `check_predictions!(study, read)`; `ResearchExpectation(result_selection, lower, upper, reference, tolerance)`; `_make_check_evidence` | `read(selection)` answers numbers and every number must lie in the bounds; the evidence has no basis; its statement gives the mean only |
| a study folder | `save_study_folder!(study, directory)`, `load_study_folder(directory)` | the conversation is not written |
| a conversation as text | `format_conversation`, `write_conversation(assistant, path)` | writes the turns, not the model |
| following the work | the quiet outline shows an item a verb adds and scrolls to it | done in the outline plan |

## 2. What is missing

1. **Eight rounds is a small turn.** One stage of a study — write a file, read
   it back, start a run, add an item, add a section — takes five to ten rounds.
   And a turn that runs out says nothing to the person.
2. **A turn can not span a run.** A model that starts a run either holds the
   turn in a wait with no deadline, which an MCP client may cut off, or ends it
   and waits for a person to type.
3. **No plan of work.** A person sees the conversation and the record, not the
   stages ahead or the one that runs.
4. **No interval on a point.** A mean without its interval is not a result.
5. **A check does not say what it read.** Its evidence has no basis, and it
   tests every value against the bounds, so it can only bound raw values.
6. **The folder does not keep the conversation**, nor which model wrote it.

## 3. Design

### 3.1 The round budget

`Assistant` gains `max_rounds::Int = 8`, a setting like `context`, which
`_launch_agent_turn!` hands to the `Agent`. A window that serves long work sets
it; the sibling plan's window sets it for a study (D2).

At the cap, the loop of the kernel ends the turn with the stop reason
`:round_limit`, and the transcript ends the turn with a quiet row: *"The turn
reached its 40 rounds."* and a **Go on** action that sends "Go on." as the
person. A person who types instead starts a turn as always.

### 3.2 A wait with a deadline

```julia
wait_for_task_group!(editor, group; timeout = nothing) -> group
```

With a `timeout` in seconds, the wait ends when the group ends or the deadline
passes, whichever is first; the group goes on. The verbs of a domain that wait
on its own groups (the sibling plan's `wait_for_run_card!`) are built on it and
answer one line of state.

### 3.3 The wake

A task group started inside a code unit of a turn **belongs to the assistant
of that turn**: the start records the assistant on the group's runtime. When
such a group ends:

- while a turn of that assistant runs, a note waits, as a message typed during
  a turn waits, and the next round reads it;
- while no turn runs, and the assistant's `wake` is on, the assistant starts a
  turn whose first part is a **note**: *"The task group "Load sweep" ended:
  330 of 330 done, 0 failed, in 3 min 12 s."* The transcript draws a note as a
  quiet row with its own glyph, so the person sees why the assistant spoke;
- an external agent over ACP gets the note as the prompt of a turn.

Three rules keep the person in charge (D1):

- a stop of a turn by the person turns the wake off until the person's next
  turn;
- one person's turn allows a bounded number of wakes (three by default), so a
  model that starts a run at each wake can not go on for ever;
- a wake never starts while the person types: the note waits for the draft to
  be sent or cleared.

`Assistant` gains `wake::Bool = false`. The note is a `ConversationNote` part,
written to the conversation file as a quoted line.

### 3.4 The plan of work

```julia
start_workflow!(title; steps = String[], editor) -> the root step
```

makes a workflow whose root is a step with `title` and one open child step for
each entry of `steps`, adds it to the explorer and opens it in a tab, as
`start_study!` does for a study. It joins `WORKFLOW_ASSISTANT_API`. The
docstring says when to call it: at the start of work of several stages, before
the first of them. `change_workflow_state!` marks a step `:active` and `:done`;
`add_element!` hangs on a step the documents and the items it made.

**A workflow and not a work plan (D5).** An external agent shows its own plan as
a `WorkPlan` already, and that plan is the agent's: it changes at each update,
no person edits it, and no folder keeps it. The plan of work of a study is a
record: a person reads it after the work, edits it during the work, and its
steps hold the items and the documents each stage made. So it is a workflow,
and the agent's own plan stays the agent's list of the moment. The guide says
to keep the workflow at the level of the stages and leave the small steps to
the agent's own plan.

### 3.5 An interval on a point

`ChartLineSeries` and `ChartScatterSeries` gain:

```julia
lower::Any = nothing     # a column as long as `y`, or nothing
upper::Any = nothing
interval_style::Symbol = :whisker   # :whisker or :band
```

- `ChartToChartPlot` draws a whisker with caps at each point, or a band under
  a line; the y range of the plot holds the intervals.
- The tooltip of a point names its interval.
- The legend draws the series as before; a band takes the series colour,
  lighter.
- The `.pred` file writes the three fields when they are set.

### 3.6 A check that holds what it read

- `result_selection` of a `ResearchExpectation` may be a result of the study,
  or its id. The check then reads `read(result.content)`, and the evidence it
  adds holds the result in its `basis`.
- `read` may answer labelled values, `label => value`; the statement of the
  evidence then names each value outside the bounds by its label, such as
  *"G = 2: 0.031 is outside [0.045, 0.06]"*.
- The check is unchanged otherwise: every value must lie in the bounds, and a
  reader that reduces (a peak, a mean) answers one value.

### 3.7 The conversation kept with the study

- `ConversationTurn` gains `backend::Symbol` and `model::String`, which
  `_launch_agent_turn!` writes from the assistant and the stream's own answer
  of the model id; a person's turn leaves them empty.
- `format_conversation` writes them in the heading of each assistant turn, and
  the reader of the conversation file reads them back.
- `save_study_folder!(study, directory; conversation = nothing)` writes
  `conversation.md` beside the study when a conversation is given.

## 4. Steps

Each step names its narrowest test.

- [ ] **1. The round budget.** `Assistant.max_rounds`; the loop's
      `:round_limit`; the quiet row and **Go on**. Test: a stub model that
      always calls a tool ends at the budget with `:round_limit`; the row shows
      and **Go on** starts a turn. `test_agent_loop()`, and a new
      `test_assistant_rounds()` beside `test_assistant_work()`.
- [ ] **2. The wait with a deadline.** `wait_for_task_group!(…; timeout)`.
      Test: a group of one sleeping task; the wait ends at the deadline with
      the group running, and at the end with the group done.
      `test_task_group_verbs()`.
- [ ] **3. The wake.** The owner of a group, the note part and its row, the
      three rules, ACP's prompt. Test: a scripted turn starts a group and ends;
      the end starts a turn whose first part is the note; a stop by the person
      turns the wake off; the fourth wake does not start. A new
      `test_assistant_wake()`; `test_scripted_agent_connection()` for the
      prompt of an external agent.
- [ ] **4. The interval.** The three fields, the whisker and the band, the
      tooltip, the file. Test: a chart of three points with intervals draws
      three whiskers in a picture; the y range holds the upper bound; the file
      round trip. `test_chart()`.
- [ ] **5. The plan of work.** `start_workflow!`, its docstring and its place
      in the list. Test: the verb makes the root with its steps, opens the tab
      and adds the explorer entry; undo removes it. `test_workflow()`.
- [ ] **6. The check holds what it read.** A result as the selection, labelled
      values, the basis. Test: a study with a result whose content a stub
      `read` answers as labelled values; the evidence holds the result and
      names the value outside the bounds. `test_research()`.
- [ ] **7. The conversation kept.** The two fields, the file, the folder.
      Test: a conversation with a turn of each backend writes and reads back
      with its models; `save_study_folder!` writes `conversation.md`.
      `test_conversation()`, `test_research()`.
- [ ] **8. The documents.** `agent.md` and `assistant.md` (the budget, the
      wake and its rules, the note), `task.md` (the owner of a group, the
      deadline), `chart.md` (intervals), `workflow.md` (`start_workflow!`),
      `research.md` (what a check holds), and the guide of the assistant's
      verbs.

Steps 1 to 3, 5 and 7 serve the sibling plan's Step 6; Step 4 its Step 4;
Step 6 its Step 5.

## 5. Decisions

- **D1. Whether an assistant wakes by itself.** (a) Off by default, on for a
  window that asks for it, with the three rules of §3.3. (b) Always, when a
  group it started ends. (c) Never: the person types "go on".
  *Recommendation: (a).* A long study is not followable when it stalls at each
  run, and a person who did not ask for a turn must see why it came.
- **D2. The budget of rounds.** (a) A setting of the assistant, eight by
  default, that a window raises, with a visible end. (b) A higher default for
  every assistant. (c) No cap.
  *Recommendation: (a).* The cap is what stops a model that loops; the window
  that knows the work sizes it.
- **D3. How an interval draws.** (a) Whiskers for points, a band for a line,
  chosen by `interval_style`. (b) Whiskers only.
  *Recommendation: (a).* A summary against a dense x reads better as a band.
- **D4. The conversation in the folder.** (a) Written when the study is saved
  from a window with an assistant. (b) Only on request. (c) Never; the history
  stays in the editor.
  *Recommendation: (a).* A study that does not say who wrote it and with which
  model can not be reproduced or judged.
- **D5. What the plan of work is.** (a) A workflow, made by `start_workflow!`,
  kept with the study (§3.4). (b) A `WorkPlan`, with a verb that lets a
  built-in backend write one as an external agent does. (c) Both, the work
  plan mirrored into the workflow.
  *Recommendation: (a).* A plan of record must take edits, hold the documents
  of its stages and live in the folder; a `WorkPlan` does none of the three,
  and a mirror makes two owners of one list.

## 6. Not in this plan

- An assistant that plans and runs several studies at once.
- A scheduler that wakes an assistant at a time rather than at the end of a
  group.
- A model that runs offline over a whole study; the local model stays in
  omnet-julia's `plan/pending/assistant-study-remainder.md`.
