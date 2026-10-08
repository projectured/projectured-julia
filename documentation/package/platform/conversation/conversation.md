# Conversation

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [widget.md](../widget/widget.md), [natural.md](../natural/natural.md)

The conversation slice of `ProjecturedPlatform` holds a chat with a model as documents: turns of parts, the evaluation of a piece of code with its result, and the draft of the next message. It draws the history as widgets, edits the draft part by part, and evaluates Julia in the running editor. This document says how the parts, the composer and the evaluator work together, and where its documents differ from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Conversation example" src="../../../asset/image/example/conversation-widget.png">

## How it works

| Document | What it holds |
| --- | --- |
| `ConversationConversation` | `turns`, the history |
| `ConversationTurn` | `role`, which is `:user` or `:assistant`, then `parts`, `stop_reason` and `collapsed` |
| `ConversationPart` | `content`, a document of any domain, and `collapsed` |
| `ConversationThinking` | the reasoning of a model, with the `signature`, `redacted` and `data` that the provider needs back unchanged |
| `ConversationDraft` | `parts` of the message that a person composes, and `assistant`, the host of the draft or `nothing` |
| `EvaluatorForm` | `form` and `result`, two sections that fold on their own, and the metadata of the tool call that made them |
| `EvaluatorToplevel` | `elements`, a sequence of forms: a REPL in a tab |

Each list is a `CellVector`. A part that streams in is a `push!`: the computed cell of its turn prints the parts again, and the rest of the transcript stays as it is.

These documents differ from the shape of every domain. They have no `@domain` and no placeholder kit. They have no text form, no parser and no file type of their own. Their printers end in widgets, and not in a syntax tree.

### A part holds a document of another domain

A code part is a live document of its own domain, such as a `JuliaDocument` or a `JsonObject`. This slice names none of those domains. It calls the natural-format seam of the natural slice: `get_natural_format` gives the format of a document, and `has_natural_parser` and `parse_natural_text` read a text into a document of that format. So this slice has no dependency on the Julia, JSON or XML packages, and a domain that the session did not load has no parser there. `CODE_FORMATS`, which holds `:jl`, `:json` and `:xml`, selects the parts that get a panel.

### The transcript

`ConversationToWidget()` is a `TypeDispatchingProjection` of three projections. A conversation prints as a `VerticalLayout` of turns. A turn prints as a `WidgetCard` with a role header over a `VerticalLayout` of parts. A part prints as its content, or as a muted panel for code, a thinking block and an evaluation. [transcript.md](transcript.md) describes what each one draws, the folds, the object selection, the Alt+arrow walk and the paste rules.

The reference maps work one level at a time. Each level removes the steps that it printed and gives the rest to the IO map of the child that printed them: `turns[i]` is `children[i]`, and `parts[j]` is `content.children[j]`. A part is the lowest level, except for the `form` and the `result` of an evaluation. So a path of the widget layer never reaches the conversation document.

`_follow_selection!` makes the `selection` cell of each container a computed cell: the selection of the node, mapped forward, less the steps that lead to the container. The layout and the card draw their ring from that cell. So a selected message, part, form or result has a ring, and no printer runs again when the selection changes.

The transcript is read, not written. Its reader returns `nothing` for `ReplaceReferencedValueOperation`, `ReplaceStringRangeOperation` and `ReplaceNumberRangeOperation`, and passes every other operation on.

### The composer

`ConversationComposerToWidget` prints a draft as a `VerticalLayout` of one `WidgetCard` for each part, with no role header. The last part is the active part, and its content sets which keys the composer reads:

| Active content | Return | Other keys |
| --- | --- | --- |
| `PrimitiveString`, a line of text | submit the draft | Shift+Return: a new line. Tab or Insert: add a kind chooser. |
| `DocumentInsertion`, the kind chooser | make the named kind | Escape: back to a line of text. |
| the insertion of a Julia document | parse it into a `JuliaDocument` | Alt+Return: evaluate it into an `EvaluatorForm`. Shift+Return: a new line. Escape. |
| the insertion of another domain | parse it into a document of that domain | Shift+Return: a new line. Escape. |

After a code part or an evaluation, the composer appends a new line of text, so a draft always ends in one. The chooser reads its name with `resolve_insertion`, and `_composer_kind` keeps a type only when it is the insertion of a domain whose text has a parser. So `julia` makes a `JuliaInsertion`, and Return on a kind that the session can not parse does nothing.

The text keys belong to the text layer of the active part: typing, Backspace, Delete, the arrows and their Shift variants. Their edits come back through the reference maps of the composer as edits of `parts[n].content.value{s:e}`. The table of the composer holds only Return, Shift+Return, Alt+Return, Tab, Insert and Escape. It is a list of `GestureBinding`s, and `get_projection_gesture_bindings` returns the same list, so the gesture help shows the keys that the reader fires.

After each operation, `sync_draft_selection!` puts the complete selection of the editor on the caret of the active part, because a key goes where the complete selection points. When the focus is on another pane, the draft keeps the caret as a dormant selection instead. [transcript.md](transcript.md#the-draft-has-one-selection) describes the one selection of the draft.

### The operations hold the document

A composer operation holds the draft, and not a path into it. `is_self_contained_operation` is `true` for each of them, so no projection above changes or drops one. This is how a composer inside an assistant pane, or inside a page, reaches the editor.

The composer loads before any host, so it can not name the operation of a host. `make_submit_operation(host)` and `make_evaluate_operation(host)` are generic functions whose default returns `nothing`. `resolve_composer_host_operation(draft.assistant, operation)` replaces the submit and the evaluation of the composer with what the host returns. The assistant slice adds a method for `Assistant` by qualification, which is `PAR-QUALIFIED-EXTENSION`. A draft with no host keeps the operations of the composer: Return finalizes the draft, and Alt+Return keeps the form as a part.

### The evaluator

`EvaluatorForm` keeps `source`, the text of a call, and `input`, the whole input of a tool call, exactly as they arrived. The form is a projection of that text, and a projection is not reversible: a snippet that does not parse is a `PrimitiveString`, and a parsed one prints as the printer writes it. The assistant replays `source` and `input` to the model, not the printed form.

`ComposerEvaluateOperation` calls `execute_julia_code!(set, editor, text)`, and so does `EvaluateSelectedFormOperation` for a form that is still text. A form that is already a document runs as an `Expr`: `make_natural_expression(:jl, form)` through the natural seam, then `execute_julia_expression!(set, editor, expression)`, so an object pasted into the code is the object the code acts on. When the last value is a `Document`, from `get_last_evaluated_value`, the result is that document, so a plot or a table draws live in the transcript. Otherwise the result is a `TextBlock` of the printed output and the value, and both operations pass `describe_value = describe_value_for_person`, so a person reads the value as the Julia REPL shows it, not the trimmed form with a note that a model gets. The composer passes `editor.tools`, so its code keeps the API that the host declares. The evaluator is typed by a person, so it runs like a Julia REPL: the evaluators of one editor share one tool set with no declared API, kept for `editor.tools` in a weak table. Every name that `Projectured` exports is in scope there, and `using` loads what the environment declares. That tool set shares the observers of `editor.tools`, so a host still hears each evaluation, and it releases `editor` after each evaluation. A name that one form binds is defined in the next.

An `EvaluatorToplevel` opens in a tab when a person types `repl` or `evaluator`, or presses the Evaluator button of the toolbar. It starts with one empty form. Return evaluates the form that holds the caret, appends a new empty form, and moves the complete selection from the root to the new form, so the form that was evaluated shows no caret. Shift+Return puts a line break at the caret. Up and Down walk the history, as in the Julia REPL. The text layer moves the caret up or down a line where there is one, so the keys reach the toplevel only from the first or the last line of the code. In the bottom form, Up recalls the code of an older form and Down the code of a newer one, with `RecallEvaluatorFormOperation`, and the caret goes to the end of the code. The text before the caret, when the navigation starts, is a prefix that each entry must start with, and what the form held then comes back after the newest entry. A failed form is an entry, and an entry that is the text shown now is skipped. The position, the draft and the prefix are view state on the toplevel, and an evaluation resets them. In a form above, Up and Down move the caret to the neighbor form, so a recall never overwrites evaluated code. A neighbor that is a Julia document is selected whole, because a place in its code is a place in its projection, which a gesture of the toplevel does not see; Return on it evaluates it again. A row of options stands above the forms, and the forms stand in a `WidgetScrollPane` below it, in a `GridLayout` of one column whose rows are `Content` and `Fill`, so the row stays in place when the forms scroll. The pane follows the end through the `follow_end` field of the toplevel: a scroll away from the end turns it off, and an evaluation turns it on again, so the new form is in view. Its style keeps its viewport transparent, so the forms stand on the page of the tab. `EvaluateSelectedFormOperation` holds the toplevel and not a path, so it also travels up the chain unchanged. The rule of Return is an `override`, and `EvaluatorToplevelToWidgetComposite` offers a key that an inner layer already answered to the table of the toplevel as a claimed key, as the reader of `@projection_template` does, because the hole of a structured form answers Return itself. The rule answers only when the selection is in the code of a form, so a result that reads Return keeps it. A plain press that nothing inside a form answers, on its prompt or after its code, puts the caret at the end of that form's code, or selects the code whole when it is a document; one on the empty space of the evaluator puts the caret at the end of the bottom form, as a click on a terminal goes to its prompt. A press on an option leaves the caret where it is: a path into the row of options maps back to nothing, so the focus that a press on a control asks for does not move the selection. `EvaluatorFormToVerticalLayout` draws a form as a `>` row that holds the code and a `=` row that holds the result. The two prompts stand in a column of their own, so the code and the result start at one x. A form shows no `=` row until it has a result. The reference maps pass the rest of a `form` or `result` path through, because a bare form is edited and not only read. The transcript of the assistant does not use this layout: it draws a form as two sections.

After an evaluation, a form keeps its code as typed in `source`. When the `parse_evaluated_forms` field of the toplevel is on, which is the default, the code becomes a Julia document if that document prints back as the same tokens on the same lines as the code. The spaces between the tokens do not count, so `1+1` becomes Julia and shows as `1 + 1`, and a recall gives back `1 + 1`. A line break counts, and so does every character of a string and of a comment. Code with a comment, code that the print would change in another way, and code that does not parse keep their `PrimitiveString`. The tokens come from `Base.JuliaSyntax.tokenize`, the tokenizer of the parser that `Meta.parse` runs. The evaluation runs the typed code either way. A parsed form draws in the colors of the Julia notation. Code whose last token, apart from a comment, is `;` hides its value, as in the Julia REPL: the code runs, what it prints still shows, and so does an error, but the value is not drawn, and a form that printed nothing shows no `=` row.

**Structured forms.** The `type_structured_forms` field of the toplevel, off by default, makes each fresh form a hole of the Julia domain, the insertion that `resolve_insertion(Document, "julia")` names, so this slice still does not depend on that domain. A hole keeps its text in `value`, as a string form does, so the caret, Shift+Return and the history treat the two alike; Tab commits the hole as the Julia domain does, and Return commits it as part of its evaluation by the token rule above. A form that is a document takes a pasted object: select a node of the code whole, with Alt+click, and paste a copied or noted document with Ctrl+V. The Julia notation draws the object as its title in angle marks, and the evaluation uses the object itself, a noted live one too. A form that holds an object keeps an empty `source` and is no entry of the history, because the label of an object is no code. Ctrl+Shift+C copies the reference of a selected object as code that gives the object; see [clipboard.md](../clipboard/clipboard.md).

**The options.** The row above the forms holds two `WidgetCheckbox`es, "Parse evaluated forms" and "Structured forms", bound to the two fields by a cell function. Their per-instance bindings answer a plain press, Space and Return with `ToggleEvaluatorOptionOperation(toplevel, option)`, which the check box reader reads before its own toggle. Two rules without a key, "Parse evaluated forms" and "Type structured forms", reach the same operation from the command palette. Structured forms changes the bottom form at once and keeps its text and caret: a string becomes a hole, and a hole or a parsed form becomes a string; a form that holds an object stays as it is. Parse evaluated forms changes only the evaluations that come after it.

`is_selection_walk_stop(::EvaluatorForm)` is `false`, so the Alt+arrow walk passes from a part directly to its form or its result.

**The duplicate.** `has_document_duplicate` is `true` for every `EvaluatorDocument`, so the tab of the evaluator shows a `+` above its `x`. The duplicate copies the forms, their code, their folds, the caret and the history state; see [document.md](../../kernel/document.md#the-duplicate). `copy_document(::DuplicatePolicy, ::EvaluatorForm)` shares the result of each form. A result can be live, such as a list that computes or a widget that holds a function, and a copy of a live value is refused. An evaluation in the duplicate puts a new result in the form of the duplicate. The duplicate evaluates in the namespace of its window, as every evaluator of the window does, so a name that the original binds is defined in the duplicate. A tool call in the transcript of an assistant is an `EvaluatorForm` too, so the fork of an assistant has tool calls of its own and shares their results.

## How it fits

The conversation slice depends on the kernel and on the collection, domain, focus, natural, layout, primitive, projection, serialization, style, text and widget slices of `ProjecturedPlatform`. It uses the serialization slice for the file forms of `EvaluatorForm` and `ConversationPermissionRequest`. It calls `execute_julia_code!` of the `tool` layer of the kernel to evaluate a form.

The assistant slice holds a `ConversationConversation` and a `ConversationDraft`, and adds the two host methods; see [assistant.md](../assistant/assistant.md). The shell slice puts an Evaluator button on the toolbar; see [shell.md](../shell/shell.md).

The conversation slice registers two natural rows under `:evaluator`, one for `EvaluatorToplevel` and one for `EvaluatorForm`. Each chains its widget projection to `VerticalLayoutToGraphicsCanvas`, because a tab reads its content through `print_child` and needs graphics. It also registers the insertion aliases `repl` and `evaluator`. It registers no row for `ConversationConversation` or `ConversationDraft`: a host adds those two. `make_conversation_row(; measure)` and `make_conversation_draft_row(; measure)` give them: each draws its document as chat bubbles, and what a part of a bubble holds goes through the natural renderer, so a part shows a document of every domain that the session loaded. Put the draft row first, because a draft is a conversation document too.

## Design decisions

- **A turn is a list of parts, and a part draws as its content.** Only code, a thinking block and an evaluation get a panel, because the content of every other part shows what it is. The rejected alternative was a card with a kind heading around every part: `text` over the words "hi there" repeats what a person sees. See [plan/done/conversation-redesign.md](../../../../plan/done/conversation-redesign.md) and [plan/pending/conversation-flat-transcript.md](../../../../plan/pending/conversation-flat-transcript.md), stages 1 to 3.
- **The fold state is on the domain node.** A turn builds its part cards again when a part streams in, so a flag on a widget would reset while the model writes. See [plan/done/transcript-folds.md](../../../../plan/done/transcript-folds.md).
- **The composer grows by a typed insertion.** One `DocumentInsertion` chooser serves every domain that has a parser, instead of one code path for each domain. See [plan/done/conversation-redesign.md](../../../../plan/done/conversation-redesign.md), stage 3.
- **A form keeps its source and its input as they arrived.** A replay from the printed form sends a snippet that does not parse as `PrimitiveString("…")`, and a model copies that constructor into its next call. The tool headers of [plan/done/transcript-folds.md](../../../../plan/done/transcript-folds.md), stage D, read the `input` field.
- **An evaluated form is parsed only when its print is the same tokens on the same lines, and the switch is a field of the toplevel.** Parsing always would delete a comment the moment Return is pressed, and would turn code of several statements into an indented block. A comparison character by character kept `1+1` a string beside `1 + 1`, which owes nothing to what the code says. The parse replaces the content of the form, so it is an edit of the document, and a field of the document says whether it happens. The rejected alternative was a parameter of a projection that parses the string only to draw it: an edit in the drawn Julia tree could not be mapped back into the string. See [plan/done/evaluator-parses-forms.md](../../../../plan/done/evaluator-parses-forms.md) and [plan/done/evaluator-parse-ignores-spacing.md](../../../../plan/done/evaluator-parse-ignores-spacing.md).
- **A structured form reaches the Julia domain only through the natural seam.** Domains are independent, so the conversation slice names the Julia hole by `resolve_insertion` and runs a document through `make_natural_expression(:jl, …)`, a hook keyed by format as the parser is. The rejected alternative was a generic function declared in the kernel's tool module with a method in the Julia domain. See [plan/done/evaluator-structured-forms-and-paste.md](../../../../plan/done/evaluator-structured-forms-and-paste.md).
- **The check boxes are the evaluator's own, not `ObjectField`s.** An `ObjectField` has no row in the natural projection, and a plain write of the field could not change the bottom form with it.
- **A host gives the meaning of Return by a method.** A mutable hook holds one answer for the whole process, and a `Ref` that one package writes during the precompilation of another is lost when the image loads. The reason is in the docstrings of `make_evaluate_operation` and of the two methods in `source/platform/assistant/AssistantTurn.jl`.
- **The ring follows the selection through a cell.** Each container computes its own selection from the node, so no widget needs a `:selected` variant. Stage 6 of [plan/pending/conversation-flat-transcript.md](../../../../plan/pending/conversation-flat-transcript.md) proposes that variant, and it is not built. [plan/pending/select-a-widget-and-paste-it-into-a-tab.md](../../../../plan/pending/select-a-widget-and-paste-it-into-a-tab.md) holds the step that built the ring.

## Usage

```julia
conversation = ConversationConversation([
    ConversationTurn(:user, [ConversationPart("Can you write a factorial function?")]),
    ConversationTurn(:assistant, [
        make_conversation_thinking_part("A recursive one is the clearest."),
        ConversationPart(parse_julia("factorial(n) = n <= 1 ? 1 : n * factorial(n - 1)")),
        ConversationPart(EvaluatorForm(parse_julia("factorial(5)");
                                       source = "factorial(5)",
                                       result = make_evaluator_result_text("120"))),
    ]),
])
projection = make_conversation_widget_projection_example()   # the transcript
draft      = make_conversation_draft()                       # one empty line of text
composer   = make_conversation_editor_projection_example()   # the composer
```

The paths of a transcript name its objects, and the path of a draft names a place in the text of the active part:

```julia
@reference turns[2]                          # a message
@reference turns[2].parts[3]                 # a part of it
@reference turns[3].parts[1].content.result  # the result of an evaluation
@reference parts[1].content.value{4}         # the caret in the draft
```

- Examples: `conversation_widget_example` and `conversation_editor_example`, and the atomic examples `conversation`, `turn`, `part` and `draft`. The factories are in `example/platform/conversation/`.
- Tests: `test_conversation()` runs the layering guard, `test_conversation_editor()` and `test_conversation_transcript()`. In `test/projectured/editor/`, `test_evaluator_toplevel()` covers the evaluator in a tab, and `test_conversation_serialization()` and `test_parse_markdown_blocks()` cover what the assistant sends and receives.

## Limits

- A card does not light up under the pointer. The ring of a selected object works; the light of a card, from stage 6 of [plan/pending/conversation-flat-transcript.md](../../../../plan/pending/conversation-flat-transcript.md), is not done.
- The draft has no frame, no focus ring, no `+` button and no hint line. Stage 4 of the same plan puts them on the pane that holds the draft, and they are not done.
- The chooser makes an insertion that takes the whole source as text. A structural key, such as `[` for a JSON array, does not start a document.
- The arguments of a tool call print one `key: value` line each. A nested value prints as its Julia `string`.
- A noted object in a form is live only while the session lives: a saved evaluator writes it by value, and it comes back as a copy.
- An evaluated form with a comment stays a string, because the Julia domain has no comment. Code of several statements stays a string too, because the Julia notation prints a top-level block indented, with an empty first and last line. A form that stays a string draws in one color, so beside a parsed form it looks unhighlighted.
- The composer and the evaluator set `is_error` from the text of the output: an output that contains `ERROR` or `Error` marks the result as an error.
- A tab that holds a bare `ConversationConversation` shows its reflected fields unless the host adds the conversation rows.
- No test is marked `@test_broken`.
