# The transcript

> **Kind:** reference · **Status:** current · **Stands on:** [widget.md](../widget/widget.md), [editor-concepts.md](../../design/editor-concepts.md)

The transcript is the widget presentation of a `ConversationConversation`: the
chat a person reads in the assistant pane. It is printed by
[`ConversationToWidget.jl`](../../../source/conversation/ConversationToWidget.jl)
and it is read, not written. A click names the part it landed in, an Alt+click
names the object under the pointer, and an edit that reaches it is declined. In
a window that wraps its content in a clipboard, `Ctrl+C` and `Ctrl+N` copy and
note the selected object, and a paste over the transcript is refused.

## What a turn draws

A turn is a `WidgetCard` that fills the width it is offered. The user's turn is
tinted and the model's is plain; a colored mark and the role word say who spoke.
The parts of a turn stack inside it with a small gap, and a small gap separates
two turns on top of the padding each turn card keeps.

## What a part draws

A part draws as its content, and takes a chrome only where the content can not
say what it is:

| Content | Chrome | Header |
| --- | --- | --- |
| prose, markdown | none | none |
| code (`julia`, `json`, `xml`) | a muted panel | the language |
| a thinking block | a muted panel | `thinking` |
| an evaluation (`EvaluatorForm`) | a muted panel with two sections | see below |

A typed message becomes a markdown document when the composer commits it and the
markdown parser is loaded, so it draws with the same font and the same wrapping
as a reply.

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

## Folds

Every card with a chrome folds: a turn, a code part, a thinking part, an
evaluation, and each section of an evaluation. A card that folds is a
`collapsible` `WidgetCard`: a chevron before its title points down while it is
open and right while it is folded, the chevron is the fold target, and a folded
card draws its header and nothing else.

The fold state lives on the domain node, never on the widget: `turn.collapsed`,
`part.collapsed`, and `form_collapsed` / `result_collapsed` on an
`EvaluatorForm`. The card's own `collapsed` cell is a computed cell that reads
the node's flag. A turn's part cards are rebuilt whenever its part list changes,
which happens on every streamed part, so state on a widget would reset while
the model answers.

A click on a chevron makes `ToggleCollapseOperation(card)` in the widget
renderer. The transcript reader walks its IO maps and says what that fold means:
a card that is the output of an IO map folds the node that IO map printed, and a
section card means the `ToggleEvaluatorSectionOperation` its part listed in
`folds`.

| Node | Starts |
| --- | --- |
| a turn | open |
| a code part | open |
| a thinking part | folded |
| an evaluation, its code and its result | open |
| the result of a failed evaluation | folded |
| a resource read (`read_resource`, `list_resources`) | folded as a whole; its sections open |

A prose part has no chrome, so it has no header and does not fold. A folded
part shows only its header. A click on its chevron unfolds the part. A click on
its title does not fold, and it names the conversation, the same as a click
between two parts.

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
inside it said, because nothing in it is edited.

The selected object is ringed. The transcript's containers follow the
selection: the conversation's layout rings a message, a message's body rings a
part, and a section card rings its form or result.

## A paste is refused

The history of a conversation is a record, so
`accepts_pasted_document(::ConversationConversation)` answers `false`, and so
does the assistant as a whole. A clipboard pastes and cuts nothing there, and it
does not paste a whole conversation or a whole assistant elsewhere either: a
copy of an assistant would share its model session. A message, a part, a form
and a result paste anywhere a paste may write. The composer's own text paste is
not a pasted document, and it still works.

