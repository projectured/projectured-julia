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

### 3.3 The registry of the session

`AssistantList` is the one registry of the open assistants of the session, a
document in the assistant slice. The owner asked for it (2026-10-09): "perhaps
we need a central registry which assistants could be added by some means and
removed". It holds:

- `assistants` — the open assistants, computed from the sources below. The
  order is the order in which the registry first saw each assistant, newest
  first.
- `added::CellVector` — the assistants that a caller added with
  `add_assistant!` and did not take out with `remove_assistant!`.
- `selected` — the assistant that the detail shows, or `nothing`. It is an
  assistant, not an index, so a row that comes or goes does not move the
  detail to another assistant.
- `get_session_assistant_list()` makes it at the first call.

The registry gets the open assistants from three sources:

1. **Stage 1: the tabs of each window.** The application builds the pane tree,
   so the application links the registry to the tree once. The link is no
   document field, because the tree holds the Assistants pane, and a field
   would make a cycle. The application sets it, as a window sets the `opener`
   of `TaskGroupList`. The registry reads `PaneTree.root`, then
   `PaneSplit.elements`, then `PaneGroup.tabs`, then `PaneTab.content`. All
   of them are cells, so the read runs again only when a tab opens, closes or
   moves, and never after an edit inside a tab. Every path that puts a document
   into a tab is covered with no hook: the start of the application,
   `open_pane!`, the load of a pane file, the insertion into an empty tab, a
   paste, the duplicate of a tab, and the undo of a close. An empty assistant
   tab gets a row.
2. **Stage 2: an assistant inside a tab**, for example in a layout or in a card.
   See 3.7.
3. **`add_assistant!` and `remove_assistant!`**, for a source that is no tab,
   for example an assistant that an MCP client starts.

A row leaves the table when its assistant is no longer open. The undo of the
close of a tab brings the row back. The description, the comment and the work
state stay in the `Assistant` document, so nothing that the person wrote is
lost. A precompile and a test that build an assistant and show it in no window
add no row.

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

### 3.7 Stage 2: an assistant inside a tab

The owner asked for every open assistant (2026-10-09): "ultimately, I would like
to have all assistants which are open", and then: "you can do both stage 1 and
stage 2". An assistant inside a layout of a tab is open, but it is not the
content of a tab, so stage 1 does not find it.

The facts:

- A `PaneGroup` prints the content of each of its tabs, also of a tab that is
  not active
  ([PaneToWidget.jl:342](../../source/platform/pane/PaneToWidget.jl#L342)).
  So each open assistant has an IO map in the print tree of the window.
- No IO map is released. The reconciler
  ([IoMapReconcile.jl](../../source/kernel/iomap/IoMapReconcile.jl)) drops the
  IO map of a child that is gone, and the garbage collector frees it. No hook
  runs.
- `get_child_iomaps`
  ([ProjectionInterface.jl:410](../../source/kernel/projection/ProjectionInterface.jl#L410))
  gives the child IO maps of a container. About 25 methods exist. Each other IO
  map answers `nothing`, so a walk of the print tree stops there.
- `search_documents` walks every document from a root.

Three ways:

- **2A. Walk the print tree.** On the editor task, the registry walks the IO
  maps of the window with `get_child_iomaps` and takes each IO map whose input
  is an `Assistant`. The cost grows with the printed nodes, not with the data.
  The walk misses a part under an IO map that holds children but has no method
  of `get_child_iomaps`. So each such IO map needs a method. The readers use
  the same methods ([`read_routed_child`](../../source/kernel/projection/ProjectionInterface.jl)),
  so the methods help them too.
- **2B. Walk the documents.** `search_documents(root, x -> x isa Assistant)`.
  A reactive walk depends on every cell and runs again after each key press.
  A walk that is not reactive needs a signal to run. The cost grows with the
  data, and a large data frame makes it slow.
- **2C. Release an IO map.** The reconciler and each projection that drops a
  child IO map call a release function, and the IO map of an assistant takes
  the assistant out of the registry. It is exact and cheap at each change, but
  it is a new mechanism of the kernel, and each projection that drops an IO map
  without the reconciler must call it. One missed call leaves a row of a closed
  assistant.

Recommendation (mine): 2A. Open means that the window shows it, and the print
tree is the record of what the window shows. Step 7 first counts the IO maps
that hold children without a method of `get_child_iomaps`, and measures the walk
on the largest example. **The owner chooses the way after step 7, before step
8.** A new mechanism needs the word of the owner. Each of the three ways adds
one: a walk of the print tree that the registry runs, a walk of the documents
with its signal, or a release.

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
- [ ] **4. The registry, stage 1.** Add `AssistantList`,
  `get_session_assistant_list`, `add_assistant!` and `remove_assistant!`, and
  the link from the application to the pane tree. Test in a real editor that an
  empty assistant tab gets a row, that each path of 3.3 adds the row, that a
  close takes it out, and that the undo of the close brings it back. Test that
  an edit inside a tab does not run the read again.
- [ ] **5. The pane.** Add `AssistantListToWidgetPane` with the table, the
  palette command and `show_assistant_list!`. Make Show find the tab by its
  content. Test the rows in a real editor: a label changes when a turn starts
  and ends.
- [ ] **6. The detail.** Add the split and the detail. Test in a real editor that
  a key edits the description and the comment, and that the select sets
  `work_state`.
- [ ] **7. Stage 2, the facts.** Count the IO maps that hold children and have
  no method of `get_child_iomaps`. Measure the walk of 2A on the largest
  example. Write the numbers in 3.7, and ask the owner to choose 2A, 2B or 2C.
- [ ] **8. Stage 2, the way that the owner chose.** Test in a real editor that
  an assistant inside a layout of a tab gets a row, and that the row goes when
  the layout loses the assistant.
- [ ] **9. The guide.** Update
  [assistant.md](../../documentation/package/platform/assistant/assistant.md).
  Move this plan to `plan/done/`.

## 5. The answers of the owner

The owner answered the six questions on 2026-10-09.

1. **An assistant with no prompt.** It gets a row. The owner first agreed that
   the row comes at the first submit, then changed the answer (2026-10-09): "an
   empty assistant tab should also show up in the table, otherwise it could be
   surprising". Then: "ultimately, I would like to have all assistants which are
   open, but we can defer this if this is difficult or expensive", and "perhaps
   we need a central registry which assistants could be added by some means and
   removed". When I proposed the tabs as stage 1 and an assistant inside a tab
   as stage 2: "you can do both stage 1 and stage 2". The design is in 3.3 and
   3.7.
2. **A native assistant that loads.** Keep the description, the comment and the
   work state. The owner: "yes, eventually the conversation should also load".
   The load of the conversation of a native assistant is a later plan.
3. **The title of a native assistant tab.** No change. The owner: "not needed".
4. **The elapsed time while a turn runs.** Use the kernel `Clock` with
   `start_wall_clock!`. The owner: "yes".
5. **The place of the palette command.** Step 5 finds the document that every
   tab is inside, or asks. The owner: "yes, we need assistant settings anyway
   for at least what part of the conversation starts expanded/collapsed, there
   are many parts".
   - The facts now: no `AssistantSettings` group exists. The groups are
     `HistorySettings`, `FaultSettings`, `PointerSettings`, `RenderSettings` and
     `StartSettings`, each declared with `@settings` in its own slice.
     `StartSettings` holds the backend, the model and the agent command of the
     assistant, and the application reads them only at its start.
   - Which part starts collapsed is now decided in code: `collapse_thinking` on
     each `Assistant`, and `_collapse_tool_default`
     ([AssistantTurn.jl:675](../../source/platform/assistant/AssistantTurn.jl#L675)),
     which collapses a tool call that reads a resource.
   - `AssistantModule` does not use `SettingsModule` now. An `AssistantSettings`
     group in the assistant slice adds that dependency. Check it against the
     package rules first.
   - A settings group is not on the path from the root to a tab, so a gesture of
     the group does not work from every tab. "Show the settings" works from
     every tab because `SettingsDocument` wraps the content.
   - **The owner (2026-10-09): `AssistantSettings` and the defaults of which
     parts start collapsed are a separate plan.** This plan does not add the
     group. Step 5 puts the command on a document that every tab is inside, so
     that the separate plan can move it to the group later. If step 5 finds no
     such document, it asks.
6. **The context of a native backend.** A later plan keeps `input_tokens`. The
   owner: "agreed".

## 6. Open questions

1. **A row leaves when its assistant closes.** The design in 3.3 takes the row
   out when the assistant is no longer open, because the owner asked for the
   open assistants. The table has no Close button for that reason. The owner
   did not answer this point. Recommendation (mine): keep it so.
2. **The way of stage 2.** The owner chooses 2A, 2B or 2C after step 7 (3.7).
   Recommendation (mine): 2A.

Step 5 asks again if it finds no document that every tab is inside.
