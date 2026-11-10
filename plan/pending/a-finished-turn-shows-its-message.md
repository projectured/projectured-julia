# A finished turn shows its message

> **Status (2026-11-10): IN PROGRESS** on the branch `finished-turn` in the
> worktree `projectured-julia-finished-turn`. The owner approved the plan on
> 2026-11-10.

## What the user asked for

While a turn of the assistant runs, the person follows it: the thinking, the
tools and the commands. When the turn finishes, the person wants to see only what
the assistant said, and what the person said. The details of the work fold away,
also in the history, and stay available: a click opens them.

The goal is less noise on the screen, with the details one click away.

## Decisions of the owner

1. **The message of a finished turn is its last text.** The texts between the
   tools are progress updates, so they go into the work, with the tools and the
   thinking.
2. **While a turn runs, a tool call stays open until the turn ends.** A tool call
   that folds when the next step starts goes away before the person can read it,
   because the next tool comes fast.
3. **One setting for the whole editor**, in a new settings group, applies to
   every conversation. It is not a field of each assistant.
4. **A turn with no message folds nothing** (2026-11-10, after the measurement
   below). When no text comes after the last part of work, the turn shows every
   part, as while it runs. Such a turn usually stopped before its end, by a stop,
   an error or the round limit, so its work is all that a person can read.
5. **The agent knows that only its last text shows** (2026-11-10). Every model of
   the pane learns that after its answer only its last text shows, so its last
   text must stand alone.

## What the code does now

- A part has one flag, `collapsed::Bool`
  ([ConversationDocument.jl:20](../../source/platform/conversation/ConversationDocument.jl#L20)).
  The producer of the part writes it once, when it makes the part. Nothing
  changes it when the turn finishes.
- A thinking part starts folded. The field `collapse_thinking` of `Assistant` sets
  this, and it is `true` by default
  ([AssistantTurn.jl:1207](../../source/platform/assistant/AssistantTurn.jl#L1207)).
- A tool call starts open. A resource read starts folded
  ([AssistantTurn.jl:833](../../source/platform/assistant/AssistantTurn.jl#L833),
  [ExternalAgentTurn.jl:780](../../source/platform/assistant/ExternalAgentTurn.jl#L780)).
- The result of an error starts folded. This is the flag `result_collapsed` of
  `EvaluatorForm`, which this plan does not change.
- A click on a chevron gives the kernel `ToggleCollapseOperation`, which flips
  `collapsed` of the part or the turn
  ([ConversationToWidget.jl:909](../../source/platform/conversation/ConversationToWidget.jl#L909),
  [Operations.jl:773](../../source/kernel/operation/Operations.jl#L773)).
- A turn runs while it has a start time and no finish time:
  `_is_turn_running` in
  [ConversationTree.jl:61](../../source/platform/conversation/ConversationTree.jl#L61).
  A turn of a file that kept no times reads as finished.
- A saved conversation keeps the `collapsed` flag of each part. A loaded
  conversation therefore shows each part as the producer made it.
- A setting reaches the code that uses it as a cell: `get_setting_cell(group,
  :field)`, as `make_history_wrap` gives an undo buffer its capacity
  ([HistorySettings.jl:28](../../source/platform/undo/HistorySettings.jl#L28)).
  The settings slice loads before the conversation slice.
- The application builds the transcript in `make_conversation_row`
  ([ConversationRows.jl:14](../../source/platform/conversation/ConversationRows.jl#L14)),
  which `make_application_content_projections` calls
  ([Application.jl:180](../../source/platform/application/Application.jl#L180)).

## Design

### The levels of a turn

A turn shows four levels. Each level opens one click deeper.

1. The turn folded: its header only. This is `turn.collapsed`, which does not
   change.
2. The turn open: the work line, then the message.
3. The work open: every part of the work in its order, each on its own line.
4. A part open: its body.

A running turn, a finished turn and a turn of the history, with the setting at
its default:

```
▾ assistant                              (running: every part open)
    I will first look at the fold code.
    ▾ thinking
        The user wants …
    ▾ tool  Bash: grep -rn collapsed …
    ▸ tool  Read: Foo.jl                 (error: folded)
    Now I check the agent turn.
    ▾ thinking …

▾ assistant                              (finished, or from the history)
    ▸ Work: 9 tool calls · 3 thinking · 2 texts · 2 min 10 s
    I agree with the goal. My proposal …

▾ assistant                              (finished, the work open)
    ▾ Work: 9 tool calls · 3 thinking · 2 texts · 2 min 10 s
        I will first look at the fold code.
        ▸ thinking
        ▸ tool  Bash: grep -rn collapsed …
        …
    I agree with the goal. My proposal …
```

### The message and the work

The message of a finished turn is the parts that come after its last part of
work. Every part before that is work.

A part of work is one of these:

- a thinking part;
- a tool call (an `EvaluatorForm`);
- a permission request or a question that has its answer, or that the end of the
  turn cancelled;
- a text that comes before the last part of work.

A text, a prose document, a code block and a picture after the last part of work
are the message.

These parts are never work: a note, because every note is the editor that speaks
to the person (a wake, the rounds of a turn, a new session); a sign-in request;
and a permission request or a question that waits for its answer. A turn of the
person has no work at all, because it is what the person said.

A plan of the agent is a prose document, as a text is, so the transcript can not
tell the two apart. A plan counts as a text: before the last part of work it is
work, and after it, it is the message.

### The fold of a part is a default or a choice

A part has `fold::Symbol` in place of `collapsed::Bool`, with three values:

- `:default`: the part follows the rule below. A producer makes every part with
  this value.
- `:open` and `:folded`: the choice of the person. A choice does not change when
  the turn finishes, when the setting changes or when the file loads again.

A turn has `work_fold::Symbol` with the same three values, for its work line.

The rule for a part that has `:default`:

| Turn | Setting `finished_turn` | Work line | Part of work | Part of the message |
| --- | --- | --- | --- | --- |
| runs | any | none | open | open |
| finished | `:message` | folded | folded | open |
| finished | `:everything` | none | open | open |
| finished, no message | any | none | open | — |

Two exceptions keep the fold that they have now: a resource read starts folded,
and the result of an error starts folded.

Because the rule computes the fold from the state of the turn and from the
setting, nothing walks the parts when a turn finishes. The card of a part reads
`fold`, the state of its turn and the cell of the setting, and it follows a
change of each.

## Proposed decisions

These details are proposals. They are approved with the plan.

1. **A part that needs the person stays outside the work line.** A note, such
   as the "Go on" note of a turn that used its rounds, shows after the work line
   in its order. A request that waits for its answer shows the same way.
2. **A turn with no work shows no work line.** A plain answer of a model looks as
   it does now. A turn with no message shows no work line either (decision 4 of
   the owner).
3. **The work line comes before the message**, because the work came first. It
   says how many parts of each kind the work holds, and how long the turn ran
   when both times are known and the turn ran for 1 s or more: `Work: 9 tool
   calls · 3 thinking · 2 texts · 2 min 10 s`. A part of another kind, such as a
   code block or an answered question, counts as "other part".
4. **A click writes a choice.** A click on a chevron of a part or of the work line
   writes the opposite of what shows, `:open` or `:folded`. A new operation of the
   conversation slice does it, `ReplaceConversationFoldOperation(node, field,
   fold)`, and its inverse writes the old value back, so an undo gives back the
   default. The kernel `ToggleCollapseOperation` stays for `turn.collapsed`, and
   no kernel file changes.
5. **A file keeps only a choice.** A part writes `fold` only when it is not
   `:default`, and a turn writes `work_fold` the same way. A file of a part that
   has the old keyword `collapsed` loads, and the reader ignores the keyword, so a
   conversation of an old file folds by the new rule.
6. **The setting.** `ConversationSettings` in the conversation slice has one field:
   `finished_turn::Symbol = :message in (:message, :everything)`, with the text
   "Finished turn: what a finished turn shows, its message only or everything."
   `make_conversation_row` gets a `settings` keyword and gives the transcript
   projection the cell of the setting. A transcript with no settings, as in a
   test or an example, uses `:message`.
7. **`collapse_thinking` goes away.** The setting replaces it. The field of
   `Assistant` goes, and an assistant file that names it loads and ignores it.
   `make_conversation_thinking_part` loses its keyword `collapsed`.
8. **The folds of an evaluation do not change.** The two sections of an
   `EvaluatorForm`, its form and its result, keep their own flags. When the work is
   open, a tool call shows its header line only, so its sections show only when the
   person opens it.

## Steps

Do the work in a worktree on a branch. Make one commit for each step.

1. ✅ **The fold of a part is a default or a choice.** Change `ConversationPart` to
   `fold`. Put the rule of the table in the part printer, with the state of the
   turn from `_is_turn_running`. Add `ReplaceConversationFoldOperation` and its
   inverse, and make the fold reader give it for a part. Change the producers in
   `AssistantTurn.jl` and `ExternalAgentTurn.jl`. Change the file form (proposed
   decision 5).
   Test: `test_conversation_transcript()`, `test_conversation_serialization()`,
   `test_conversation_tree()`, `test_assistant_overview()`.
2. ✅ **A finished turn folds its work into one line.** Add `work_fold` to
   `ConversationTurn`. Make the turn printer split the parts into the work and the
   message, and draw the work line with its label. Make the fold reader give the
   operation for the work line. Add tests that print one turn while it runs and
   after it finishes, and check where the message and the work line draw.
   Test: `test_conversation_transcript()`, `test_conversation()`.
3. ✅ **One setting for the whole editor.** Add `ConversationSettings`. Give its cell
   to the transcript through `make_conversation_row` and
   `make_application_content_projections`. Remove `collapse_thinking`.
   Test: `test_conversation()`, `test_assistant_duplicate()`, and a test that a
   change of the setting opens the work of a finished turn.
4. ☐ **A turn with no message folds nothing.** Make `_find_work_indices` give no
   work line when only parts that stay out of the work come after the last part
   of work. Test: `test_conversation_transcript()`.
5. ☐ **The agent knows that only its last text shows.** Give the built-in loop and
   an external agent one sentence that says so, outside the `system` text of a
   window, because a window can replace that text. Test:
   `test_external_agent_turn()`, `test_assistant_mvp()`.
6. ☐ **Check by eye.** Render a seeded conversation with a running turn, a finished
   turn and a turn of an old file, with each value of the setting. Tune the label
   and the spacing of the work line.
7. ☐ **Documentation.** Update
   [transcript.md](../../documentation/package/platform/conversation/transcript.md),
   [conversation.md](../../documentation/package/platform/conversation/conversation.md)
   and [assistant.md](../../documentation/package/platform/assistant/assistant.md).

## Notes from the implementation

### Step 1

- **The generic write can not carry a fold.** `ReplaceReferencedValueOperation`
  writes one field and has an undo, but the readers of the transcript decline it
  by its type, because a transcript is read-only. So the fold has its own
  operation, `ReplaceConversationFoldOperation`, as proposed decision 4 says. It
  answers `is_self_contained_operation`, so the readers above the transcript
  pass it on. `ToggleEvaluatorSectionOperation` answers no such method; this plan
  does not change it.
- **The kernel view state is not used.** `get_view_state_fields` marks a field
  that a file leaves out and a history does not record. A fold that a person
  chose stays after a reload (the rule of the owner), so `fold` is a plain field.
- **The rule reaches a part through the context.** The turn gives each part the
  property `:conversation_fold` with `with_property`, a function of no argument
  that says whether the rule closes it. A part that prints alone has none, and
  starts open.
- **The resource read is the rule of the transcript.** The producers
  (`AssistantTurn.jl`, `ExternalAgentTurn.jl`) make every part with `:default`.
  `_collapse_tool_default` is gone, and `_is_resource_read` in the transcript
  folds a resource read by default.
- **The card makers lose the part.** `_part_card` makes the card, and the part
  printer sets its fold in one place.
- **Three recorded precompile lines named the gone keyword** `collapsed` of
  `make_conversation_thinking_part`, in the lists of `ProjecturedPlatform` and
  `ProjecturedBuild`. They are removed; a list allows 10 % of lines that do not
  resolve, but a line for a call that can not exist has no use.
- **The Alt+arrow walk of the transcript walks the domain.** It can stop on a part
  inside a folded work line. Step 2 checks what it does there.
- **A test that makes a resource read part by hand sees it folded.** The table
  test of `AssistantMvpTest.jl` reads the page inside a resource read, so it
  opens the part with `fold = :open`, as a person opens it.
- **Results:** `test_assistant_overview` passes with a new test of the file
  form; `test_conversation_tree` 43/43; `test_external_agent_turn` 321/321;
  `test_conversation_transcript` passes with a new test of the rule;
  `test_assistant_mvp` 193 pass, 4 broken, the markers of main.

### Step 2

- **The turn has an IO map of its own**, `ConversationTurnToWidgetIoMap`, with
  the IO maps of the parts, the indices of the work (`work`) and the card of the
  work line (`work_card`), each a computed cell. It adds a method of
  `get_child_iomaps`, so the generic walks still find the parts. The fold reader
  finds the work line there and writes `work_fold`.
- **The reference maps of the turn follow the work line.** `_find_part_place` and
  `_find_drawn_part` place part `j` in the work line or after it. A path to the
  header of the work line names the turn.
- **The work card follows the selection of the turn**, so a selection in a part of
  the work draws its ring. The cell of the card computes at its first read, after
  the IO map exists, so the card can follow it.
- **A turn reads as running only with a start time and no finish time**
  (`_is_turn_running`). A turn of a file or a test that has no times reads as
  finished, so the example conversation shows its thinking in a folded work line.
  Tests that read inside the work of such a turn open it with `work_fold = :open`,
  as a person does: `ConversationTranscriptTest.jl`, `AssistantMvpTest.jl` and
  `TextInkTest.jl`.
- **A time under 1 s is left out of the label.** A test turn gave `Work: 1 tool
  call · 0 s`, and `0 s` says nothing.
- **Open point: the Alt+arrow walk walks the domain**, so it can stop on a part
  inside a folded work line, where no ring draws. The walk test passes, because
  it checks paths. This plan does not change the walk; the owner decides.
- **`test_conversation` is measured alone.** In a process that loaded the
  umbrella `ProjecturedTest` first, it gives 78 fail and 53 errors, as main does
  (a known failure of main with the umbrella, from `ProjecturedMCP`).
- **Results:** `test_conversation_transcript` passes with two new tests;
  `test_assistant_mvp` 193 pass, 4 broken; `test_text_ink_inside_viewports`
  10/10; `test_assistant_stream` 20/20; `test_assistant_composer_panel` 90/90;
  `test_text_range_selection` 41/41; `test_conversation` alone 928/928.

### Step 3

- **The setting is `ConversationSettings`** in
  [ConversationSettings.jl](../../source/platform/conversation/ConversationSettings.jl),
  one field `finished_turn`, with the label "Finished turn: what a finished answer
  shows, its message with the work folded into one line, or everything."
- **The transcript projection holds the cell of the setting** in its field
  `finished_turn`. `make_conversation_row(; settings)` gives it
  `get_setting_cell(get_settings_group!(settings, ConversationSettings),
  :finished_turn)`, and `_find_work_indices` reads it, so a change reaches every
  turn at once. With no settings the field is `:message`.
- **The application passes its settings on.** `make_application_projection` and
  `make_application_content_projections` take `settings`, and the main window
  gives its own.
- **`collapse_thinking` is removed.** `make_pred_document(::Type{<:Assistant}, …)`
  drops the keyword, so a file that names it loads.
- **Results:** `test_assistant_overview` 69/69, `test_settings` 107/107,
  `test_settings_tab` 55/55, `test_settings_wrapper` 39/39,
  `test_conversation_theme` 58/58, `test_conversation` alone 930/930. The umbrella
  tests (`test_conversation_transcript`, `test_assistant_mvp`,
  `test_assistant_duplicate`, `test_application`) waited for memory, and I stopped
  their job to add steps 4 and 5. They run with step 4.

### The measurement behind decisions 4 and 5

The owner asked how often an important text of an answer goes into the work
line. I applied the rule to the 153 saved Claude Code sessions with the owner,
6,173 answers with a tool call or thinking:

- 34 % of all text goes into the work line.
- 8.6 % of the answers hide a text that looks important: 400 characters or more,
  a list, a table, a heading, or a question.
- 3.3 % hide such a text, and the last text repeats less than a quarter of its
  words.
- 0.9 % hide a question to the person.
- 2.4 % have text but no text after their last tool call.

In these sessions the agent was told that every text stays on the screen, and not
to repeat itself at the end. So the numbers show what happens when the agent of
the pane writes in the same way. Decision 5 removes that cause, and decision 4
removes the case of 2.4 %.
