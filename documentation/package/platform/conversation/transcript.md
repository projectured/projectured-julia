# The transcript

> **Kind:** reference · **For:** developer · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [concepts.md](../../../design/concepts.md)

The transcript is the widget presentation of a `ConversationConversation`: the
chat a person reads in the assistant pane. It is printed by
[`ConversationToWidget.jl`](../../../../source/platform/conversation/ConversationToWidget.jl)
and it is read, not written. A click in the text of a text part names the place
in that text, and a drag a range of it; a click in any other part names the part.
An Alt+click names the object under the pointer, and the whole part in a text
part. An edit that reaches the transcript is declined. In
a window that wraps its content in a clipboard, `Ctrl+C` and `Ctrl+N` copy and
note the selected object, and a paste over the transcript is refused.

One exception: the live field of a part, a place where a person works inside
the transcript. A request part names it: the terminal of a
`ConversationSignInRequest`, and the form of a `ConversationQuestionRequest`. A
click in a live field keeps its place, as a caret, and an edit inside it goes
on, so a person types the code of a sign-in, or picks and types the answer to
a question of the agent, there. The rest of the part, and the rest of the transcript, stay read.

## What a turn draws

A turn is a `WidgetCard` that fills the width it is offered. The user's turn is
tinted and the model's is plain; a colored mark and the role word say who spoke.
The parts of a turn stack inside it at the `section_gap` of the widget theme, and
the same gap separates two turns, on top of the padding each turn card keeps.

## What a part draws

A part draws as its content, and takes a chrome only where the content can not
say what it is:

| Content | Chrome | Header |
| --- | --- | --- |
| plain text (`PrimitiveString`) | none | none |
| prose, markdown | none | none |
| code (`julia`, `json`, `xml`) | a muted panel | the language |
| a thinking block | a muted panel | `thinking` |
| an evaluation (`EvaluatorForm`) | a muted panel with two sections | see below |
| a picture (`ImageFile`) | a muted panel with the image, at most `picture_height` high | `picture` |

A part stores its text by the source of the text. A text that the person types,
a text of the editor such as an error, and a thinking text are plain text, a
`PrimitiveString`. The transcript draws it in `message_text` of the
`ConversationTheme`, with its line breaks as they were typed, and the composer
draws a typed text in the same style. An answer of a model is markdown, and draws
in the `MarkdownTheme`. A part that holds a plain text, a text block or prose is
a text part: it draws no chrome, and a place in its text can be selected.

## The header of an evaluation

`get_evaluation_title` names the form by the tool that produced it:

| Tool | Header |
| --- | --- |
| `execute_julia_code` | `eval` |
| `read_resource` | `resource · <uri>` |
| `list_resources` | `resources` |
| any other tool | `tool · <name> "<query>"`, the first string argument in quotes, cut at 60 characters |

The form keeps the tool's whole input, which is what the header reads and what
`build_messages` replays to the model.

## The two sections of an evaluation

Under its header, an evaluation shows two sections, each a bare card with a
small title and a fold of its own. `get_evaluation_section_labels` names them:
`code` over `result` for an evaluation, `arguments` over `result` for any other
tool, and `error` in the destructive color in place of `result` when the call
failed. The arguments of a tool draw one `key: value` line each.

A result draws through the projection of its own document. The answer of a
documentation tool is Markdown, so its result draws as a page of rendered
Markdown: headings, lists, code blocks, and tables as grids whose columns share
the width of the part. The prose of the model is a page in the same way. Any
other answer is text.

## Folds

Every card with a chrome folds: a turn, the work line of a finished turn, a
code part, a thinking part, an evaluation, and each section of an evaluation. A
card that folds is a `collapsible` `WidgetCard`: a chevron before its title
points down while it is open and right while it is folded, the chevron is the
fold target, and a folded card draws its header and nothing else.

The fold state lives on the domain node, never on the widget: `turn.collapsed`,
`turn.work_fold`, `part.fold`, and `form_collapsed` / `result_collapsed` on an
`EvaluatorForm`. The card's own `collapsed` cell is a computed cell that reads
the node's state. A turn's part cards are rebuilt whenever its part list changes,
which happens on every streamed part, so state on a widget would reset while
the model answers.

### A finished turn shows its message

A finished turn of the model shows its message, and the work before it folds
into one line, the work line:

```
▾ assistant
    ▸ Work: 9 tool calls · 3 thinking · 2 texts · 2 min 10 s
    I agree with the goal. My proposal …
```

The message is the parts after the last part of work. A part of work is a
thinking part, a tool call, and a permission request or a question that has its
answer. Every part before the last part of work goes into the work line, a text
too, because a text between two tools tells the progress of the work. Three
parts speak to the person and stay out of the work line: a note, a sign-in
request, and a request that waits for its answer. They show after the work line,
in their order.

Every model of the pane learns this rule from `ASSISTANT_ANSWER_INSTRUCTIONS`, so
it ends an answer with a text that stands alone.

The label of the work line counts the parts of each kind, and a part of another
kind counts as "other part". It gives the time of the turn when the turn has
both times and ran for 1 s or more. Open, the work line shows each part of the
work in its order.

These turns show no work line, and every part shows as it comes:

- a turn that runs, which is a turn with a start time and no finish time
  (`_is_turn_running`). A turn of a file that kept no times reads as finished;
- a turn of the person, because it is what the person said;
- a turn with no part of work;
- a turn with no message: only a note, a sign-in or a request that waits comes
  after its last part of work, or nothing does. Such a turn usually stopped
  before its end, by a stop, an error or the round limit, so its work is all that
  a person can read;
- every turn, when `finished_turn` of `ConversationSettings` is `:everything`.

`ConversationSettings(; finished_turn = :message)` is one setting for the whole
editor. `make_conversation_row(; settings)` gives its cell to
`ConversationToWidget(; finished_turn)`, so a change reaches every turn at once.
A transcript with no settings, as in a test or an example, uses `:message`.

### A fold is a default or a choice

`part.fold` and `turn.work_fold` hold one of three values. `:default` follows the
rule of the transcript, and `:open` and `:folded` are the choice of a person. A
producer makes each part with `:default`. A choice stays when the turn finishes,
when the setting changes and when the file loads again. A `.pred` file writes the
field only for a choice. A file that names the keyword `collapsed` of a part
loads, and the part follows the rule.

The rule for a node that has no choice:

| Node | Starts |
| --- | --- |
| a turn | open |
| the work line | folded |
| a part in the work line | folded |
| a part outside the work line: code, thinking, an evaluation, a request, a picture | open |
| an evaluation, its code and its result | open |
| the result of a failed evaluation | folded |
| the result of a call of an external agent that fails | folded when the update that says so comes; a later update keeps the fold |
| a resource read (`read_resource`, `list_resources`) | folded as a whole; its sections open |

The turn gives each part its rule through the property `:conversation_fold` of
the printer context, a function of no argument that says whether the rule closes
the part. A part that prints alone has none, and starts open. So nothing walks
the parts when a turn finishes: the card of a part reads its fold, the state of
its turn and the setting, and it follows a change of each.

A prose part has no chrome, so it has no header and does not fold. A folded
part shows only its header. A click on its chevron unfolds the part. A click on
its title does not fold, and it names the conversation, the same as a click
between two parts.

### A click on a chevron

A click on a chevron makes `ToggleCollapseOperation(card)` in the widget
renderer. The transcript reader walks its IO maps and says what that fold means:

| The card | The operation |
| --- | --- |
| a turn | `ToggleCollapseOperation(turn)` |
| the work line | `ReplaceConversationFoldOperation(turn, :work_fold, fold)` |
| a part | `ReplaceConversationFoldOperation(part, :fold, fold)` |
| a section of an evaluation | the `ToggleEvaluatorSectionOperation` that its part listed in `folds` |

`fold` is the opposite of what the card shows, `:open` or `:folded`. The inverse
of `ReplaceConversationFoldOperation` writes the old value back, so an undo gives
the default back. The operation answers `is_self_contained_operation`, so the
readers above the transcript pass it on, because the transcript declines a
generic write.

## Selecting an object

A transcript is read as objects, not as characters. The objects are:

| The person points at | The object | Path |
| --- | --- | --- |
| a message | the turn | `turns[i]` |
| a part: prose, code, thinking, an evaluation | the part | `turns[i].parts[j]` |
| the code of an evaluation | the form | `turns[i].parts[j].content.form` |
| the result of an evaluation: a table, a plot, a form | the result | `turns[i].parts[j].content.result` |

A plain click names at most a part: a click in a result selects the part that
holds it. An Alt+click names the innermost object, and an Alt+click on a
message's header names the message.

Alt and an arrow walk the objects. Up is the enclosing object, and the
conversation as a whole above a message; down is the first object inside; left
and right move between messages, between the parts of a message, and between
the form and the result of an evaluation. The first and the last object keep
the selection. The transcript answers these keys itself, whatever a widget
inside it said, because nothing in it is edited. Where the keys do not reach the
transcript, the generic walk answers with the same objects, because an evaluation says
`is_selection_walk_stop(::EvaluatorForm) = false` and the walk passes through
it.
The walk follows the parts of a turn and not the work line, so it can stop on a
part in a folded work line, where no ring draws.

The selected object is ringed. The transcript's containers follow the
selection: the conversation's layout rings a message, a message's body rings a
part, and a section card rings its form or result.

## The draft has one selection

A click in the draft selects a place in its value through the complete path from
the root, and every document on that path holds its part of the path. A key goes
where that path points: the assistant's split pane routes it to the draft, the
active part's card and body follow the draft's selection, and the body is a text
layer that answers the text keys — typing, `Backspace`, `Delete`, the arrows and
their `Shift` twins. The composer turns the text layer's edits into edits of the
draft's value. Its own table holds only `Return`, `Shift+Return`, `Alt+Return`,
`Tab`, `Insert` and `Escape`, and every composer operation moves the complete
selection to the caret of the active part (`sync_draft_selection!`). A key with
no selection in the draft does not reach it.

When the complete selection does not pass through the draft, as when a script
submits the draft while the focus is on another pane, the draft keeps the new
caret as a dormant selection. `sync_draft_selection!` writes the caret from the
root and at once writes the live selection back, and the kernel keeps the draft's
branch, because a draft answers `has_dormant_selection`. A dormant caret is not
drawn, and it is live again when the focus comes back to the assistant. The parts
that a submit moves into the transcript hold no selection.

## A paste is refused

The history of a conversation is a record, so
`accepts_pasted_document(::ConversationConversation)` answers `false`, and so
does the assistant as a whole. A clipboard pastes and cuts nothing there.
`accepts_pasted_text(::ConversationConversation)` answers `false` too, so no text
is pasted into the history; a copy only reads, and takes its text. The draft
takes pasted text: a caret or a range in its value is a text target of the
clipboard, and `Ctrl+V` puts the system clipboard's text there.

A whole conversation and a whole assistant are still copied, noted and pasted
somewhere else. A copy is their duplicate: a copy of an assistant is a fork,
with a draft of its own, that starts idle and shares no reply in progress. A
note is the assistant itself. A message, a part, a form and a result paste
anywhere a paste may write.

