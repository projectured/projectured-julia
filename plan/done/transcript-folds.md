# Transcript folds: a visible fold on every collapsible part

> **Status (2026-09-15): IMPLEMENTED on the branch `transcript-folds`** in the
> sibling worktree `projectured-julia-folds`. Every stage below is done; the
> notes under each stage say what the implementation found. The user
> fast-forwards `main`.

## What the user asked for

1. A widget that folds properly and **shows its fold state** on every user part
   and every assistant part. Today nothing on screen says whether a part is
   collapsed or expanded.
2. An evaluation node folds in **two**: the code and the result, each on its
   own. When the result is an exception text, the result starts collapsed.
3. A thinking node starts collapsed. A collapsed node can show **only a
   header**. It does not need to show a clipped first line.
4. The header of an MCP tool call or a resource read **names the tool or the
   resource**.
5. The result must look good. Check it by eye with `run_example` on the
   assistant example, and tune the spacing, the font sizes and the colors until
   it does. A fake conversation is fine for the check.

## What the code does now

The transcript is
[`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl).
A turn is a `WidgetCard` (tinted for the user, plain for the model). A part is
bare content, except three kinds that keep a `:muted` card with a one-word tag:
code (`julia`), a thinking block (`thinking`) and an evaluation (`eval`,
`resource` or `tool`).

**How a fold works.** A click on a card header makes
`ToggleCollapseOperation(card)` in
[`WidgetToGraphics.jl`](../../source/widget/WidgetToGraphics.jl) (the card
reader). The conversation reader walks its IO maps by identity
(`_find_collapse_target`) and re-targets the operation to the domain node, so
the kernel handler flips `part.collapsed` or `turn.collapsed`. The printer reads
the domain flag and wraps the body in `_maybe_clip`, a 30 px viewport. The
card's own `collapsed` cell is never written.

**What the baseline render shows** (`write_example_image("conversation_widget")`
at 1200 × 900, on main `e5f368ca`):

- The collapsed thinking part shows one clipped line inside a white band. There
  is no chevron and no other mark. It reads as a rendering fault, not as a fold.
- A tag (`thinking`, `julia`, `eval`) is a 14 px bold word. Nothing says that the
  word is a button.
- The evaluation card holds the code over the result with one fold for both.
- `assistant_example` starts with an empty conversation, so the transcript pane
  is blank. A visual check needs a seeded conversation.

**What the live pane shows** (the split pane of `make_assistant_projection_example`
at 1400 × 700, seeded with a typed message, a reply from `parse_markdown_blocks`
and a second typed message; measured with a script that finds the first ink
pixel of every row):

- The left edge of the user text, the model text and both role lines is the
  same, 22 px in the pane and 17 px in the standalone render. The two roles are
  aligned on the left.
- A typed message is a `TextBlock` and draws in the monospace body font. A reply
  is a `MarkdownRoot` and draws as rendered markdown in the proportional font.
  The two kinds of prose look different in weight and in width. This is the
  difference a reader sees between the two roles, and Stage B removes it.
- The distance between two turns is large. From the edge of a user band to the
  next role line is 44 px (`_TURN_GAP` 28 plus the card's 16 px padding). From
  the last line of a model turn to the next user band is 44 px, and to its role
  line 60 px, because the plain card keeps its padding without a panel.

**Why the header can not name a resource today.** `EvaluatorForm` in
[`Evaluator.jl`](../../source/conversation/Evaluator.jl) keeps `tool_name` and
`source`, and not the tool's input. The agent loop in
[`AssistantTurn.jl`](../../source/assistant/AssistantTurn.jl) reads
`get(call.input, "code", "")`, so a `read_resource` call keeps an empty form and
loses its `uri`. `build_messages` has the same gap and says so in a comment: it
replays every call as `execute_julia_code`.

**What exists to build on.**

- `WidgetCard` already draws only its header when `collapsed` is true
  (`_card_build`). The transcript does not use that path.
- `WidgetTree` and `WidgetAccordion` draw a vector chevron with
  `_push_chevron!`. The flat-transcript plan found that a text glyph is unsafe:
  the chrome font lacks some glyphs and draws others as thin outlines. The
  vector chevron has no such problem.
- `ObjectToWidget._collapsible_card` builds a reactive title with text markers
  `▾` / `▸`. It is the pattern for a title that reads the fold state.
- The pending plan
  [`conversation-flat-transcript.md`](conversation-flat-transcript.md) already
  proposes a `padding` field on `WidgetCard` (its Stage 6). This plan adds it.

## The design

| Question | Decision |
| --- | --- |
| Where does the fold mark live | In `WidgetCard`. A card with `collapsible = true` draws a chevron in its header. The producer does not draw it. |
| Which chevron | The vector chevron of `_push_chevron!`, in the theme's muted foreground. Not a text glyph. |
| What a collapsed card shows | Its header row only. The 30 px clipped viewport goes. |
| Where the fold state lives | On the domain node, as today: `ConversationTurn.collapsed`, `ConversationPart.collapsed`, and two new flags on `EvaluatorForm`. The card's `collapsed` cell is a computed cell that reads the domain flag. |
| Why not on the widget | A turn's part cards are rebuilt when its part list changes, which happens on every streamed part. State on a widget would reset while the model answers. |
| The evaluation | One outer card with the kind and the name in its header. Inside, two sections, `code` and `result`, each a collapsible card of its own. The outer fold stays. |
| The evaluation's default state | Without an error, the outer card and both sections start open. With an error, the result section starts collapsed and is titled `error` in the destructive color; the outer card and the code section stay open. |
| A resource read's default state | The outer card starts collapsed, as `_collapse_tool_default` says today. Both sections inside start open. The user's decision above names the evaluation; this row keeps an earlier decision and the user can overrule it. |
| The prose of a typed message | The composer commits a typed prose part as a markdown document when the markdown parser is loaded, so it draws in the same font and with the same wrapping as a reply. |
| The distance between turns | Smaller. `_TURN_GAP` starts at 8 and the visual pass settles it with the user. |
| A tool that is not `execute_julia_code` | The first section is titled `arguments` and lists the input, one `key: value` line each. |
| The header of a tool call | `tool · <name>` plus the first string argument in quotes, cut at 60 characters. A `read_resource` call reads `resource · <uri>`. A `list_resources` call reads `resources`. An evaluation reads `eval`. |
| The thinking header | The bare word `thinking`. No preview line. |
| The tool input | `EvaluatorForm` keeps it in a new `input` field, and `build_messages` replays the real tool name and input. The known gap closes. |
| Hover feedback | Out of scope. It needs a `hovered` cell on the card and hover tracking in the assistant chain, which is Stage 6 of the flat-transcript plan. |

## Stage A — `WidgetCard` shows its fold state ✅ DONE

Files: [`WidgetDocument.jl`](../../source/widget/WidgetDocument.jl),
[`WidgetToGraphics.jl`](../../source/widget/WidgetToGraphics.jl),
[`widget.md`](../../documentation/package/widget/widget.md),
[`SubstrateExamples.jl`](../../example/substrate/SubstrateExamples.jl) and the
widget card example factory.

1. Add two fields to `WidgetCard`, both with keyword defaults:
   - `collapsible::Bool = false` — the card draws a chevron before its title and
     the whole header row is the fold target.
   - `padding::Int = -1` — the card's own padding in pixels; a negative value
     means the theme's. A `:plain` card with `padding = 0` draws nothing and
     occupies nothing beyond its content.

   Before you add a field, grep for a positional call: `WidgetCard(Cell(`. Today
   only the keyword constructor uses that form. A new field changes the arity of
   the generated positional constructor, and a keyword default does not protect
   a positional caller.
2. Give `WidgetCardToGraphicsCanvas` two more fields: `chevron::StyleStroke`
   (color `theme.muted_foreground`, width `theme.stroke`) and
   `chevron_size::Int` (`theme.chevron`). Wire them in the theme builder next to
   the card entry.
3. In `_card_build`:
   - Read `w.padding` and use it in place of `p.padding` when it is not
     negative. Do the same for the inner width in `print_document`.
   - When `w.collapsible` is true, reserve a chevron column of
     `2 * chevron_size + title_gap` at the left of the header row, place the
     title after it, and push the chevron centered on the title row: `:down`
     when expanded, `:right` when collapsed. The build cell already reads
     `w.collapsed`, so the chevron flips without a re-print.
   - The recorded title placement (`child_iomaps` entry) carries the shifted x,
     so the forward map and the click router see the offset with no change.
4. In the `MousePress` reader, when the card is collapsible, the fold hit box is
   the header band across the full card width, not the title canvas alone. A
   click on the chevron must fold.
5. Extend the widget card example with one collapsible card, and regenerate its
   screenshot with `generate_example_screenshots(filter = r"^widget_card$")`.
6. Document `collapsible` and `padding` in the card row of `widget.md`, and in
   the `WidgetCard` docstring.

**Test.** `test_object_to_widget()`, `test_widget_button_behavior()` and
`test_substrate()` stay green. Add a testset (next to the widget tests) that
renders one collapsible card: expanded it draws two `GraphicsLine`s in a `:down`
shape, collapsed a `:right` shape and no body; a `MousePress` on the chevron
column yields `ToggleCollapseOperation(card)`; a `:plain` card with
`padding = 0` measures exactly its content.

**A struct changed, so start a fresh Julia process.** Revise can not redefine a
struct, and the widget dispatch table is built once.

**What the implementation found.**

- `padding` takes a number for every side or an `Inset` per side. A section
  inside an evaluation needs an indent and nothing else, and one number for
  four sides can not say that.
- A card added its section gap after its content even with no footer, so every
  card ended ten pixels below its last line and a nested card twice that. The
  gap now separates the content from a footer only; a card with no footer ends
  at its padding.
- The renderer draws the chevron from `_push_chevron!` with the theme's chevron
  half-size (4) in the muted foreground; the header moves right by two
  half-sizes plus the title gap, 12 pixels.
- New example `widget_collapsible_card_example`, an open card over a folded one.
  The test is `test_widget_card_fold()`, in the substrate suite: the chevron's
  direction in both states, the body absent when folded, the fold on the
  chevron column and on the title, no chevron on a card that does not fold,
  and the two padding forms.

## Stage B — the transcript folds to a header ✅ DONE

File: [`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl).

1. Every card that can fold — the turn card, the code card, the thinking card,
   the evaluation card — gets `collapsible = true`, and its `collapsed` cell
   follows the domain flag:

   ```julia
   set_cell_function!(getfield(card, :collapsed), () -> node.collapsed === true)
   ```

   `Cell` is `ReactiveCell{Any}`, and `set_cell_function!` turns a value cell
   into a computed one. The toggle reader re-targets every fold to the domain
   node, so the widget cell keeps its function.
2. Delete `_maybe_clip`, `_COLLAPSED_H` and `_CARD_PADDING`. The renderer draws
   only the header of a collapsed card.
3. The role header does not change. The chevron comes from the card, so
   `_role_header` stays a glyph and a word.
4. A thinking part starts collapsed (it already does) and shows only the word
   `thinking` until a click expands it.
5. Lower `_TURN_GAP` from 28 to 8. The visual pass in Stage E settles the final
   value with the user.
6. A typed message draws like a reply. In
   [`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl),
   `finalize_draft!` turns a committed `PrimitiveString` into a `TextBlock`.
   Change it to `parse_natural_text(:md, value)` when `has_natural_parser(:md)`
   is true, and keep the `TextBlock` when it is not. The conversation package
   names no domain, and the natural seam is how it already asks for a parser.
   `build_messages` serializes a markdown part through `_block_text`, the same
   as a reply, so the model sees the same text as before.

**Test.** `test_conversation()` (63 today) and `test_assistant_mvp()` (78 today)
stay green. In `AssistantMvpTest.jl`, the scenes test asserts the typed text
with `_text_to_string`, which reads a markdown part as well; check that
`_mvp_test_scenes` and `_mvp_test_tool_use_roundtrip` still pass, and change an
`isa TextBlock` assertion, if one exists, to `isa MarkdownDocument`.

**What the implementation found.**

- `_mvp_test_collapse_containment` asserted that the folded render is exactly
  as wide as the open one. A folded card is its header alone, so it can be
  narrower; the assertion is now `<=`, which is the no-widening property the
  test was written for.
- The click scan in `ConversationTranscriptTest.jl` could no longer name the
  thinking part: a folded part shows only its header, and the header is the
  fold. The test unfolds it first. This is the trade the design makes: a person
  unfolds a part before selecting it.
- `_prose_document` in the composer commits typed prose through
  `parse_natural_text(:md, …)`; the composer test accepts either form and reads
  the words back through `print_natural_text`. `_mvp_test_collapse_click` scans x from 16 to 200, which covers the
chevron column. `_mvp_test_collapse_containment` keeps its no-balloon check. Add
one assertion: the render of the example draws no `GraphicsText` of the
thinking body while the part is collapsed, and draws it after
`evaluate_operation` flips the flag.

## Stage C — the evaluation folds in two ✅ DONE

Files: [`Evaluator.jl`](../../source/conversation/Evaluator.jl),
[`ConversationModule.jl`](../../source/conversation/ConversationModule.jl),
[`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl),
[`ConversationEditor.jl`](../../source/conversation/ConversationEditor.jl).

1. `EvaluatorForm` gains `form_collapsed::Bool` and `result_collapsed::Bool`.
   They are view state, the same as `ConversationPart.collapsed`. The keyword
   constructor defaults `form_collapsed = false` and
   `result_collapsed = is_error`: without an error every fold of an evaluation
   starts open, and with an error only the result starts closed. Every
   construction site — the agent loop,
   `SubmitJuliaOperation`, the composer's ALT+ENTER at
   [`ConversationEditor.jl:282`](../../source/conversation/ConversationEditor.jl#L282),
   the examples and the tests — gets the default with no change.
2. Add `ToggleEvaluatorSectionOperation(form::EvaluatorForm, section::Symbol)`
   to `Evaluator.jl`, with `section` in `(:form, :result)`, and an
   `evaluate_operation` method that flips the named flag. Export it. The kernel's
   `ToggleCollapseOperation` flips one `collapsed` field per target and can not
   name a section; an operation whose vocabulary belongs to one domain lives
   with that domain's document. If the gesture log has no fallback
   `describe_operation`, add one for it.
3. Printer. `_eval_card` becomes an outer `:muted` collapsible card whose title
   is the evaluation title (Stage D) and whose content is a `VerticalLayout` of
   two section cards. A section card is `:plain`, `padding = 0`,
   `collapsible = true`, titled `code` / `result` (or `arguments` / `error`,
   see Stage D), and its `collapsed` cell follows `ef.form_collapsed` or
   `ef.result_collapsed`. Put the body builder in one helper, so the composer
   draws a committed evaluation the same way.
4. Reader. The part printer returns a `ConversationPartToWidgetIoMap`
   (`@iomap struct` with `projection`, `input`, `output`, `folds`), where
   `folds` lists each section card with the domain operation its fold means.
   `_find_collapse_target` becomes `_find_fold_operation(iomap, card)`: an IO
   map whose `folds` names the card answers that operation; an IO map whose
   `output === card` answers `ToggleCollapseOperation(iomap.input)`; a
   `ChildrenIoMap` recurses. The conversation reader for
   `ToggleCollapseOperation` calls it.
5. The composer. Check what a header click on a section does in the composer.
   If its reader lets the raw `ToggleCollapseOperation` through to the kernel,
   the widget cell flips and the fold works until the draft is re-printed. That
   is acceptable for a draft. If the click misbehaves, the composer passes
   `collapsible = false` on its sections.

**Test.** Add a testset to
[`ConversationTranscriptTest.jl`](../../test/conversation/projection/ConversationTranscriptTest.jl):
a click on the `result` section header of the example's evaluation yields
`ToggleEvaluatorSectionOperation(form, :result)`; `evaluate_operation` flips
`result_collapsed`; a form built with `is_error = true` starts with
`result_collapsed == true`; its render draws the code text and not the result
text. `test_conversation()`, `test_assistant_mvp()` and
`test_conversation_serialization()` stay green.

**What the implementation found.** The composer draws a draft's evaluation
through the same `_eval_sections` helper with `folds = nothing`, so its
sections do not fold: a draft is re-printed on submit and a fold there would
not survive it. The section cards are indented by `_SECTION_INDENT = 12`, the
chevron column of the card around them, so a section's chevron starts where
the header's word starts. The gesture log needs no method: `describe_operation`
falls back to the type name.

## Stage D — the header names the tool or the resource ✅ DONE

Files: [`Evaluator.jl`](../../source/conversation/Evaluator.jl),
[`AssistantTurn.jl`](../../source/assistant/AssistantTurn.jl),
[`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl),
[`ConversationSerializationTest.jl`](../../test/projectured/editor/ConversationSerializationTest.jl),
[`AssistantMvpTest.jl`](../../test/workbench/editor/AssistantMvpTest.jl).

1. `EvaluatorForm` gains `input::Dict{String,Any}` with an empty default. The
   agent loop passes `input = call.input`. The other construction sites pass
   nothing; an empty input means "the form is the input", which is what every
   older transcript holds.
2. Add `get_evaluation_title(ef) -> String` to `Evaluator.jl`, by the rule in
   the design table. `_kind_label(::EvaluatorForm)` returns it.
   `get_evaluation_kind_label` stays; `_collapse_tool_default` still keys off it.
3. The first section of a call that is not `execute_julia_code` shows the
   arguments: a `TextBlock` with one `key: value` line per input entry, in key
   order. Build it where the agent loop builds the form (`_eval_form_doc` gets
   the call, not only its code). The section title is `arguments`.
4. `build_messages` replays `LlmToolUse(ef.tool_use_id, ef.tool_name, input)`
   with `input = isempty(ef.input) ? Dict("code" => _eval_code(ef)) : ef.input`.
   Delete the "KNOWN GAP" comment. This is a behavior change on the model-facing
   replay, and it is the reason the gap was left open: the form did not keep the
   input.
5. `format_conversation` and `write_conversation` print the title before a call
   that is not an evaluation.

**Test.** In `ConversationSerializationTest.jl`, a `read_resource` form with
`input = Dict("uri" => "resource://guide/orientation")` replays as a
`LlmToolUse` named `read_resource` with that `uri`; the testset "a call replays
as the text it was made with" stays green through the fallback. In
`AssistantMvpTest.jl`, extend `_mvp_test_resource_collapse`: the part's form
keeps the `uri`, and a render of the turn draws a `GraphicsText` that contains
it. `test_assistant_mvp()` and `test_conversation_serialization()` green.

**What the implementation found.** `test_assistant_mvp()` reports 2 failures on
this branch and the same 2 on `main` at `e5f368ca`: the two `_eval_code`
assertions compare the kept source with the printer's rendering of it, which
differ in spacing. They are not this plan's. The middle dot in a header draws
in the chrome font, checked in the render.

## Stage E — the fake conversation and the visual pass ✅ DONE

Files: [`ConversationDocumentExample.jl`](../../example/conversation/ConversationDocumentExample.jl),
[`AssistantDocumentExample.jl`](../../example/workbench/AssistantDocumentExample.jl),
[`DomainExamples.jl`](../../example/projectured/DomainExamples.jl),
[`ConversationToWidget.jl`](../../source/conversation/ConversationToWidget.jl).

1. Add `make_assistant_conversation_document_example()` to the conversation
   examples and export it. It holds every kind of part the transcript can draw:
   - a user turn: one prose part, "Can you write a factorial function in Julia
     and check that it works?";
   - an assistant turn: a thinking part (collapsed); a prose part; a `julia`
     code part; an evaluation of `factorial(5)` with the result `120`; a
     `read_resource` call with `uri = "resource://guide/orientation"` and a
     three-line result; a `search_api` call with `query = "make_child_context"`
     and a short result; an evaluation of `sqrt(-1)` whose result is the
     `DomainError` text with `is_error = true`; a markdown part with a list;
   - a user turn: an evaluation of `factorial(6)` with the result `720`.

   `make_assistant_document_example()` seeds `Assistant(; llm = FakeLlm(),
   conversation = make_assistant_conversation_document_example())`. The small
   `make_conversation_document_example()` does not change: the tests index into
   its turns and parts.
2. Raise `render_height` of `assistant_example` from 283 to 1000 in
   `DomainExamples.jl`. Check whether a guide embeds `asset/image/example/assistant.png`;
   if it does, regenerate it with `generate_example_screenshots(filter = r"^assistant$")`
   and run `update_guide_screenshots()`.
3. The visual pass. Render, look, tune, repeat. Use a script in the scratchpad:

   ```julia
   using ProjecturedRepl
   write_example_image("assistant", "assistant.png"; width = 1400, height = 1000)
   write_example_image("conversation_widget", "conversation_widget.png"; width = 1200, height = 900)
   ```

   Render three states of the showcase: the defaults, every fold expanded, and
   every fold collapsed (flip the flags on the document before the write). Open
   each PNG and check this list:

   - every foldable header carries a chevron, and its direction matches the flag;
   - a collapsed card is one header row, with no clipped text and no white band;
   - the thinking part starts collapsed; the error result starts collapsed, and
     its label is red;
   - the tool header names `search_api` and its query; the resource header names
     the `uri`;
   - a section header is smaller than the kind header, and the kind header is
     smaller than the role line;
   - the gaps rank: turn gap > part gap > section gap;
   - no text leaves its card; the headers of one turn align on one x; the
     chevron does not touch the glyph beside it;
   - a typed message and a reply draw in the same font, and their left edges
     measure the same with the row script;
   - the distance between two turns is clearly larger than the distance between
     two parts, and no larger than that.

   Then run `run_example(assistant_example)` on the SDL window and click each
   header: the chevron flips and the body vanishes or returns.
4. Record the final numbers here: the role font, the kind style, the section
   style, `_GAP`, `_TURN_GAP`, the section gap, the section padding, the chevron
   size, and the error color. Starting values: role `font_ubuntu_bold_18`, kind
   `font_ubuntu_bold_14` in `color_slate_600`, section `font_ubuntu_regular_14`
   in `color_slate_500`, error `color_destructive`, `_GAP = 8`,
   `_TURN_GAP = 8`, section gap 4, section padding 0. The turn gap is the
   user's call: they found the distance on main too large.

**Test.** `test_example(assistant_example)` and
`test_printer(conversation_widget_example)` green. `assistant_example` is in the
`examples` registry, so the enumeration suites walk the seeded conversation;
the transcript holds no caret, so the type-in sweep has nothing more to type.

**What the visual pass settled.** The showcase is
`make_assistant_conversation_document_example()` in
[`ConversationDocumentExample.jl`](../../example/conversation/ConversationDocumentExample.jl),
and `make_assistant_document_example()` seeds the assistant with it, so
`run_example(assistant_example)` opens on the full transcript. Renders at
1200 × 1500 (the transcript alone) and 1400 × 1100 (the assistant pane) checked
every item of the list above. The final values:

| Constant | Value |
| --- | --- |
| `_ROLE_FONT` | `font_ubuntu_bold_18`, in the role's color |
| `_KIND_STYLE` | `font_ubuntu_bold_14`, `color_slate_600` |
| `_SECTION_STYLE` | `font_ubuntu_regular_14`, `color_slate_500` |
| `_ERROR_STYLE` | `font_ubuntu_bold_14`, `color_destructive` |
| `_GAP` (between parts) | 8 |
| `_TURN_GAP` (between turns) | 8 |
| `_SECTION_GAP` (between the two sections) | 10 |
| `_SECTION_INDENT` | 12 |
| chevron | the theme's half-size 4, muted foreground |

Two things the render showed that this plan does not fix:

- The last line of a markdown list at the end of a turn is clipped at its
  descenders. A render of the same reply on `main` clips it the same way, so
  the markdown text reports a height smaller than it draws. That is the wrap
  measure's, not the transcript's.
- A fold on a section card is as wide as the section's content, because the
  bare card takes its content's width. The header band is still the target,
  and a click on the chevron or the word folds.

## Stage F — documentation and bookkeeping ✅ DONE

1. Add [`documentation/package/conversation/transcript.md`](../../documentation/package/conversation/transcript.md):
   which parts draw a chrome, which of them fold, what each header says, and
   which start collapsed. Link it where the per-slice guides are indexed.
2. In [`conversation-flat-transcript.md`](conversation-flat-transcript.md),
   note under Stage 6 that the `padding` field now exists.
3. Move this plan to `plan/done/`.

**Done.** The guide exists and `CLAUDE.md` lists it with the per-domain
guides. The card row of `widget.md` names `variant`, `collapsible` and
`padding`. The screenshots `assistant.png`, `widget-card.png` and the new
`widget-collapsible-card.png` are regenerated.

## Sequence and cost

| Stage | Depends on | Size |
| --- | --- | --- |
| A — the card | nothing | medium: two fields, the renderer, one test |
| B — the transcript | A | small: one file |
| C — two sections | A, B | medium: two flags, one operation, one IO map, one test |
| D — the header | C | medium: one field, one title rule, the replay, two tests |
| E — the showcase and the look | A to D | medium: one factory, then render and tune |
| F — the docs | E | small |

Work in a sibling worktree, `workspace/projectured-julia-folds`, on a branch
`transcript-folds`; the `[sources]` entries of `environment/all` are relative
paths, so the worktree's own environment resolves to the worktree. Run every
Julia process with a 20 GB memory cap and a 10 minute timeout, and log to a file.
When every stage is green, the user fast-forwards `main`.

## Risks

- **A field on a `@document` struct changes the positional constructor.** Grep
  for positional callers of `WidgetCard` and `EvaluatorForm` before each field.
- **A fold the reader does not recognize flips the widget cell.** The kernel
  handler then replaces the computed `collapsed` cell with a value, and the
  card stops following its node. The reader must recognize every card the
  printer builds. Add one sweep to the transcript test: every header click on
  the showcase yields a domain operation, never one whose target is a widget.
- **Three stacked chevrons on an evaluation.** The user decided that the outer
  fold stays. The visual pass tunes the section header size and indent so the
  three read as one block, and does not remove a fold.
- **Streamed parts rebuild the cards.** Fold state on a widget would reset on
  every streamed part; the design keeps it on the domain node for that reason.
- **The chrome font lacks glyphs.** Use the vector chevron. Do not add a text
  glyph without a render check at the drawn size.
- **The replay change is model-facing.** A `read_resource` call now replays
  under its own name and input. The provider adapters take an `LlmToolUse` of
  any name, and the serialization test covers the old fallback.

## Open question

The user reported that the user parts and the assistant parts are not aligned
horizontally. The two renders on main measure the same left edge for both
roles, so this plan assumes the report is about the font difference between a
typed message and a reply, which Stage B item 6 removes. If the user saw a
different fault, a screenshot of their window names it, and this plan gets a
step for it.

## Out of scope

- Hover feedback on a header, and the selected-part outline: Stage 6 of the
  flat-transcript plan.
- The composer's input frame and hint line: Stage 4 of the flat-transcript plan.
- `ObjectToWidget._collapsible_card` still draws text markers. It can switch to
  `collapsible = true` later, in its own change with its own test.
- A preview line on a collapsed thinking part.

## Where this stands

| Stage | State |
| --- | --- |
| A — `WidgetCard` shows its fold state | ✅ |
| B — the transcript folds to a header | ✅ |
| C — the evaluation folds in two | ✅ |
| D — the header names the tool or the resource | ✅ |
| E — the fake conversation and the visual pass | ✅ |
| F — documentation and bookkeeping | ✅ |

**Tests on the branch.** `test_substrate()` widget suites, `test_widget_card_fold()`,
`test_conversation()` 96 of 96, `test_conversation_serialization()`, and
`test_assistant_mvp()` 76 of 78 with the same two failures as `main`.
