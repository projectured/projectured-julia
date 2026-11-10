# A finished turn shows its message

> **Status (2026-11-10): PLANNED.** No step is done. The plan waits for approval.

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
- a plan of the agent;
- a permission request, a question or a sign-in request that has its answer, or
  that the end of the turn cancelled;
- a note that has no action;
- a text that comes before the last part of work.

A text, a prose document, a code block and a picture after the last part of work
are the message.

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

Two exceptions keep the fold that they have now: a resource read starts folded,
and the result of an error starts folded.

Because the rule computes the fold from the state of the turn and from the
setting, nothing walks the parts when a turn finishes. The card of a part reads
`fold`, the state of its turn and the cell of the setting, and it follows a
change of each.

## Proposed decisions

These details are proposals. They are approved with the plan.

1. **A part that needs the person stays outside the work line.** A note with an
   action, such as the "Go on" note of a turn that used its rounds, shows after
   the message. A request that waits for its answer belongs to a running turn,
   which has no work line.
2. **A turn with no work shows no work line.** A plain answer of a model looks as
   it does now. A turn with no message shows only its work line.
3. **The work line comes before the message**, because the work came first. It
   says how many parts of each kind the work holds, and how long the turn ran
   when both times are known: `Work: 9 tool calls · 3 thinking · 2 texts · 2 min
   10 s`.
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

1. ☐ **The fold of a part is a default or a choice.** Change `ConversationPart` to
   `fold`. Put the rule of the table in the part printer, with the state of the
   turn from `_is_turn_running`. Add `ReplaceConversationFoldOperation` and its
   inverse, and make the fold reader give it for a part. Change the producers in
   `AssistantTurn.jl` and `ExternalAgentTurn.jl`. Change the file form (proposed
   decision 5).
   Test: `test_conversation_transcript()`, `test_conversation_serialization()`,
   `test_conversation_tree()`, `test_assistant_overview()`.
2. ☐ **A finished turn folds its work into one line.** Add `work_fold` to
   `ConversationTurn`. Make the turn printer split the parts into the work and the
   message, and draw the work line with its label. Make the fold reader give the
   operation for the work line. Add tests that print one turn while it runs and
   after it finishes, and check where the message and the work line draw.
   Test: `test_conversation_transcript()`, `test_conversation()`.
3. ☐ **One setting for the whole editor.** Add `ConversationSettings`. Give its cell
   to the transcript through `make_conversation_row` and
   `make_application_content_projections`. Remove `collapse_thinking`.
   Test: `test_conversation()`, `test_assistant_duplicate()`, and a test that a
   change of the setting opens the work of a finished turn.
4. ☐ **Check by eye.** Render a seeded conversation with a running turn, a finished
   turn and a turn of an old file, with each value of the setting. Tune the label
   and the spacing of the work line.
5. ☐ **Documentation.** Update
   [transcript.md](../../documentation/package/platform/conversation/transcript.md),
   [conversation.md](../../documentation/package/platform/conversation/conversation.md)
   and [assistant.md](../../documentation/package/platform/assistant/assistant.md).
