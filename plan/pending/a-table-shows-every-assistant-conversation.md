# A table shows every assistant conversation

> **Status:** pending. Written 2026-10-09. No step is done.

## 1. The request

The owner asked (2026-10-09) for "an overview of the ongoing assistant
conversations which show me the current state, title, initial prompt, some
description, context size, start time, total duration, number of turns, whether
it's assistant turn or user turn, last prompt, etc. and where a user can also add
comment and set some user state (e.g. pending, complete, in progress,
abandoned)". And: "we could show a table of them and click for the details or
something and also see how some state about what they are doing on the fly".

The owner answered three questions (2026-10-09):

1. **Scope:** the assistant tabs of the running editor first. Claude Code
   sessions outside the editor, from their transcripts in `~/.claude/projects/`,
   are not in this plan.
2. **The comment and the user state live in the `Assistant` document**, not in
   the row of the list.
3. **The person edits the description.** The agent does not write it.

## 2. What exists

- **One assistant is one document in one tab.** The `Assistant` document
  ([AssistantDocument.jl:147](../../source/platform/assistant/AssistantDocument.jl#L147))
  holds `conversation`, `status` (`:idle`, `:streaming`, `:error`),
  `turn_control` (not `nothing` while a turn runs), `agent_title`,
  `agent_usage` (an `AgentUsageUpdate`: `used`, `size`, `cost`, `currency`),
  `agent_session_id`, `agent_session_directory`, `agent_session_turn_count`,
  `backend` and `model`. Each field is a cell, so a label that reads it draws
  again after a write.
- **Only the ACP agent sends a title and a usage.** The external agent writes
  `agent_title` and `agent_usage` on the editor task
  ([ExternalAgentTurn.jl](../../source/platform/assistant/ExternalAgentTurn.jl),
  `_handle_external_agent_event!`). The native backends give `input_tokens` in
  `LlmTurnEnd`, but the assistant does not keep it.
- **A turn records no time.** `ConversationTurn`
  ([ConversationDocument.jl:146](../../source/platform/conversation/ConversationDocument.jl#L146))
  holds `role`, `parts`, `stop_reason` and `collapsed`. The only clock is a
  local `turn_t0` for a log line
  ([AssistantTurn.jl:746](../../source/platform/assistant/AssistantTurn.jl#L746)).
- **The parts of a turn show the current activity.** A part holds a text block,
  a `ConversationThinking`, an `EvaluatorForm` for a tool call (its `tool_name`),
  or a `ConversationPermissionRequest`, whose `reply` is not `nothing` while it
  waits for the person.
- **A save keeps the settings, not the moment.** `pred_arguments` writes
  `backend`, `model`, `system`, `context` and `collapse_thinking`. An assistant
  with a kept ACP session also writes the conversation and the session fields.
  A native assistant loads with an empty conversation.
- **A duplicate is a fork.** `copy_document` copies the conversation and the
  values, and clears the session fields.
- **No list of the assistants exists.** When a tab closes, its assistant is gone
  from view.
- **The task slice has the pattern to copy.**
  [TaskGroupList.jl](../../source/platform/task/TaskGroupList.jl) is a list of
  the session, newest first. A group adds itself when it starts, on the task
  that writes the documents. A row stays after its pane closes, until the person
  closes the row. `TaskGroupListToWidgetPane`
  ([TaskGroupToWidget.jl:748](../../source/platform/task/TaskGroupToWidget.jl#L748))
  draws the rows in a `WidgetTable`, and its labels are closures that read
  cells. `TaskGroupDocumentToWidgetPane` puts the table above the detail of the
  `selected` task, in a split that the person can drag.
- **A key reaches a document in the detail.** The commits `09c7ff849` and
  `50ee4bb29` let a person edit the result document of a task where the detail
  shows it: a path from the root of the pane reaches it.
- **A command opens a tool pane.** The Settings slice puts "Show the settings"
  in the palette with `@gestures` and `show_document!`
  ([SettingsDocument.jl:67](../../source/platform/settingsmanaging/SettingsDocument.jl#L67)).
  `show_document!` on a `PaneTree`
  ([PaneTabsWrapper.jl:77](../../source/platform/pane/PaneTabsWrapper.jl#L77))
  finds the tab by its title. Many assistant tabs have the same title
  "Assistant", so this search can find the wrong tab.
- **Widgets that exist:** `WidgetTable`, `WidgetSplitPane`, `WidgetSelect`,
  `WidgetRadioGroup`, `WidgetTextarea`, `WidgetBadge`, `WidgetButton`.
- **A kernel `Clock` exists** with `start_wall_clock!`
  ([Clock.jl](../../source/kernel/clock/Clock.jl)). A computation that reads it
  computes again after each write.

## 3. The design

### 3.1 Three fields that the person writes

The `Assistant` document gets three fields:

- `description::PrimitiveString` — what the conversation is about. A
  `PrimitiveString`, as `input`, so the text-edit projections route keys to it.
- `comment::PrimitiveString` — the note of the person.
- `work_state::Symbol` — `:pending`, `:in_progress`, `:complete` or
  `:abandoned`. The default is `:pending`. Only the person changes it. The name
  is not `state`, because `status` is already the word for what a turn does now.

`pred_arguments` writes the three fields for every backend, because the person
wrote them and they describe the conversation, not a moment of it.

**Recommendation (mine):** a fork copies all three, as it copies the backend and
the model. The person changes them in the fork.

### 3.2 The time of a turn

`ConversationTurn` gets `start_time::Float64` and `finish_time::Float64`, in
seconds of `time()`. `0.0` means not known, for a turn of an old file or of a
test.

- The submit of a prompt writes both times of the user turn.
- The assistant turn writes `start_time` when it is pushed and `finish_time`
  when its `stop_reason` is set.

The overview computes from these times:

- the start time: the `start_time` of the first turn;
- the elapsed time: from the start time to now while a turn runs, else to the
  `finish_time` of the last turn;
- the busy time: the sum of the durations of the assistant turns;
- the last activity: the latest `finish_time`.

A saved conversation gets the two keywords for each turn. A file without them
loads with `0.0`.

### 3.3 The list of the session

`AssistantList` is a document in the assistant slice, a copy of the design of
`TaskGroupList`:

- `assistants::CellVector` — newest first.
- `selected::Int` — the row that the detail shows, `-1` for none.
- `get_session_assistant_list()` makes it at the first call.
- `add_assistant!(list, assistant)` and `remove_assistant!(list, assistant)`.

An assistant adds itself at its first submit, in the operation, on the editor
task. A document that a precompile or a test builds and never submits does not
enter the list. A row stays after its tab closes. Close takes the row out and
leaves the conversation as it is. The list holds each assistant until the
person closes its row, so the memory stays bounded by the person.

### 3.4 The values of a row

Functions in the assistant slice compute the values, so the pane, a verb and a
test read the same values:

- `get_assistant_overview_title(a)` — `agent_title`, else the first line of the
  first prompt, else "Assistant".
- `find_first_prompt(a)` and `find_last_prompt(a)` — the text of the first and
  the last user turn, or `nothing`.
- `get_prompt_count(a)` — the count of user turns. One turn of the overview is
  one prompt and its answer.
- `get_assistant_turn_side(a)` — `:assistant` while a turn runs, `:permission`
  while a permission request waits, `:error` after a failure, else `:person`.
- `describe_assistant_activity(a)` — for the turn that runs: "thinks",
  "writes", "runs <tool>", or "asks to run: <tool>". Empty between turns.
- `get_assistant_context_usage(a)` — `used` and `size` of `agent_usage`, or
  `nothing`.

### 3.5 The Assistants pane

`AssistantListToWidgetPane` draws the list. The heading says the count of
conversations and how many wait for the person. The table has one row for each
assistant:

| Column | Value |
| --- | --- |
| (button) | Show: focus the tab of the assistant, or open it again |
| Title | `get_assistant_overview_title` |
| Work | `work_state`, as a badge |
| Turn | `get_assistant_turn_side`, as a badge |
| Activity | `describe_assistant_activity` |
| Prompts | `get_prompt_count` |
| Context | `used / size`, and the cost when the agent gives it |
| Started | the start time |
| Elapsed | the elapsed time |
| (button) | Close the row |

A click on a row selects it. The detail below the table, in a split that the
person can drag, shows:

- the title, the backend and the model;
- the description and the comment, which the person edits there;
- the work state, which the person sets with a `WidgetSelect`;
- the first prompt and the last prompt;
- the start time, the elapsed time, the busy time and the last activity;
- the session id and the folder of an ACP agent.

The keys reach the description and the comment through a path from the root of
the pane, as in the detail of a task.

Show must find the tab whose content is the assistant, not the tab with the
same title. Step 5 changes or adds a method of `show_document!` for that.

### 3.6 How a person opens the pane

- A palette command "Show the assistants", with `@gestures`, as "Show the
  settings".
- A verb `show_assistant_list!()` for the REPL and for a model.

## 4. Steps

Each step gets a commit. Each step runs the narrowest test that covers it.

- [ ] **1. The three fields.** Add `description`, `comment` and `work_state` to
  `Assistant`. Write them in `pred_arguments`. Copy them in the fork. Test the
  save and the load in `ConversationSerializationTest.jl`, and the fork in
  `AssistantDuplicateTest.jl`.
- [ ] **2. The time of a turn.** Add `start_time` and `finish_time` to
  `ConversationTurn`. Write them in the submit and at the end of the native turn
  and of the ACP turn. Test with a `FakeLlm` that the times are in order, and
  that an old file loads with `0.0`.
- [ ] **3. The values of a row.** Add the functions of 3.4. Test each one on an
  assistant with a `ScriptedLlm`: before a turn, while a turn runs, while a
  permission request waits, and after a failure.
- [ ] **4. The list.** Add `AssistantList`, `get_session_assistant_list`,
  `add_assistant!` and `remove_assistant!`. Add the assistant at the first
  submit. Test that a submit adds it once, and that Close takes only the row.
- [ ] **5. The pane.** Add `AssistantListToWidgetPane` with the table, the
  palette command and `show_assistant_list!`. Make Show find the tab by its
  content. Test the rows in a real editor: a label changes when a turn starts
  and ends.
- [ ] **6. The detail.** Add the split and the detail. Test in a real editor that
  a key edits the description and the comment, and that the select sets
  `work_state`.
- [ ] **7. The guide.** Update
  [assistant.md](../../documentation/package/platform/assistant/assistant.md).
  Move this plan to `plan/done/`.

## 5. Open questions

1. **An assistant with no prompt.** Does a new tab with no prompt need a row?
   Recommendation (mine): no. The row comes at the first submit, as a task group
   comes at its start.
2. **A native assistant that loads.** Its conversation loads empty, but its
   description, comment and work state stay. Recommendation (mine): keep them.
   They are what the person wrote.
3. **The title of a native assistant tab.** Must the tab also take the first
   line of the first prompt as its title? Recommendation (mine): not in this
   plan. It changes the tab of every native assistant.
4. **The elapsed time while a turn runs.** A label of the elapsed time must draw
   again each second. The candidate is the kernel `Clock` with
   `start_wall_clock!`, which runs only while a turn runs. This step must not
   add a new mechanism without the word of the owner.
5. **The place of the palette command.** "Show the settings" lives on
   `SettingsDocument`. The command "Show the assistants" needs a document that
   every tab is inside. Step 5 finds it, or asks.
6. **The context of a native backend.** The native backends give `input_tokens`
   in `LlmTurnEnd`. A later step can keep it, so the Context column also shows a
   native assistant. Not in this plan.
