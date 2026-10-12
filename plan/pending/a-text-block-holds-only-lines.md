# A text block holds only lines

> **Kind:** plan · **Status:** in progress, 2026-10-12, on the branch `text-lines`
> (worktree `projectured-julia-text-lines`). The owner decided the end
> state on 2026-10-09 (N5 of [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md)),
> and that it is a plan of its own, and L1 to L4 on 2026-10-09. The owner asked for
> the implementation on 2026-10-12 ("continue with plan 2"). No question is open. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [text-domain-kit.md](text-domain-kit.md) (shape A of Phase 3),
> [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md) (N5)

## 1. The goal

A text is a list of lines, and a line is a list of runs. The end state:

- A `TextBlock` holds only `TextLine`s, as a `CellVector` or as a lazy list.
- A `TextLine` holds runs: `TextString`, `TextSpacing` and `TextGraphics`. It
  holds no break.
- The only break is the break before a `TextLine`, and it counts one flat offset,
  as it does now.
- The types `TextNewline` and `TextNewlineToString` go.
- Each consumer of a text has one path. `_is_block_of_lines` goes.
- A structural path to a run is `.elements[i].elements[j].content{k}`. The flat
  caret, `TextRangeReferenceStep`, keeps its values.

This is shape A of `text-domain-kit.md`. Shape B, where a block holds spans or
lines, is the way there: the consumers read lines already, so the producers move
one at a time, and the span paths go when no producer is left.

## 2. Why

The owner decided it on 2026-10-09, on these reasons:

- **One edit model.** Enter splits a line, and Backspace at the start of a line
  joins it to the line before. Today Enter in a block of spans inserts an element.
- **One path in each consumer.** Today the layout, the decorators, the flat
  helpers and the console each keep a path for spans and a path for lines, and a
  rule of "spans or lines, never a mix" that nothing enforces.
- **The properties of a line for every text.** Indentation, the gutter, a fold,
  soft breaks and later the markers attach to a line. A block of spans has no
  place for them, so the inspector, a tooltip and the examples can have none.
- **No search for a line.** The lazy list of spans in `TextToGraphics` walks to
  the next `TextNewline` to find a paragraph. A lazy list of lines has the line
  as its unit.
- **Real editors keep lines**: a list of lines, or a buffer with an index of its
  lines. The line is their unit of layout, scroll, fold, gutter and diff.

Not taken: both forms for good, and `TextNewline` kept only as a spelling that a
constructor converts (N5 of the other plan says why).

## 3. What it touches

The inventory of 2026-10-09, at main `3d9187549`. Line numbers are of that
commit.

### 3.1 Producers of a block of spans

| where | sites | what |
|---|---|---|
| `inspector/ReferenceInspectorToText.jl` | 1 | spans with `TextNewline`s between the parts |
| `inspector/SelectionInspectorToText.jl` | 1 | wraps the spans of an inner block |
| `text/ReferenceToText.jl` | 4 | `_short_text`, `_long_text` (a `TextNewline` between the nodes) |
| `text/PrimitiveToText.jl` | 4 | one run for a bool, a number, an insertion and a string; its paths are `.elements[1].content{s:e}` |
| `text/FaultToText.jl` | 1 | one run |
| `text/TextDocument.jl` | 1 | `@insertion TextBlock`, `TextBlock([TextString("")])` |
| `text/TextFolding.jl`, `text/TextLineNumbering.jl` | 2 | the marks of the gutter, one run each |
| `syntax/SyntaxToText.jl` | 1 | `_make_node_fold`, the placeholder of a fold |
| `widget/ObjectToWidget.jl`, `widget/ObjectFieldToWidget.jl` | 2 | one run, with a caret path into it |
| `widget/WidgetToGraphics.jl` | 3 | `_make_plain_text_view` (one run, or one run per piece of code), `_print_tab_name_view` |
| `natural/NaturalProjection.jl` | 1 | `PhraseToGraphics` |
| `conversation/` (`ConversationDocument`, `ConversationEditor`, `ConversationToWidget`, `Evaluator`) | 13 | one run, or a few runs; `make_evaluator_arguments_text` joins its lines with `"\n"` in one run |
| `assistant/AssistantTurn.jl` | 3 | one run |
| `domain/formula/FormulaDocument.jl` | 1 | `make_formula_result_text` |
| `domain/julia/JuliaDocument.jl` | 1 | `_julia_tooltip_text` |
| `domain/rst/RstToLayout.jl` | 1 | `_title_block` |

About 40 sites in source. The decorators (`TextFiltering`, `TextHighlighting`,
`SelectionInverting`, `TextFirstLine`, `WordWrapping`, `TextLineNumbering`) give
a block of spans only when their input is one.

The examples have about 34 sites in 12 files. `TextNewline` is in 6 of them, and
the catalog has two examples of it (`make_text_newline_document_example`,
`make_text_newline_atom_document_example`). The other repositories:

- omnet-julia: 7 blocks of one run in 3 files (`OmnetWorkbenchToWidget.jl`,
  `Mm1kDocument.jl`, `LegacySimulationResultToWidget.jl`), no `TextNewline`, no
  structural path into a text.
- inet-julia: `PacketDiagramToText.jl` gives a `TextNewline` after each row of a
  packet diagram, and a comment there says `TextToGraphics` does not lay out a
  `TextLine` yet, which is no longer true.
- Both have generated precompile statements that name `TextNewline`.

### 3.2 Consumers with two paths

- `TextToGraphics.jl`: `_line_groups` (splits at a `TextNewline`), `_find_group_line`,
  `_element_font(::TextNewline)`, `_print_listnode`, and the lazy list of spans
  (`_find_list_span_place`, `_map_list_text_forward`, `_build_paragraph_node`,
  `_build_paragraph_node_prev`, `_layout_paragraph` and the rest, about lines
  1277 to 1716). No source makes a lazy list of spans: `SyntaxListToText` makes a
  lazy list of lines, and only 5 tests make one of spans.
- `TextDocument.jl`: the flat helpers (`_text_flat_total`, `_flat_chars`,
  `get_flat_length`, `get_flat_offsets`, `get_flat_base`, `_flat_to_span_nearest`),
  the span lookups (`_text_span_infos`, `_span_content`), the path helpers
  (`_parse_selection_range`, `_text_replace_path`, `_elements_prefix`), and
  `_find_style_span`, `_make_styled_run`.
- `WordWrapping.jl`: `_wrap` with `WrapSegment` and the soft `TextNewline`,
  `_make_wrap_runs`, `_parse_text_elem_range`. Its users on a block of spans: the
  two inspectors, `text_to_graphics` of `Application.jl` for a text and a
  primitive, the tooltip of the gallery, and three examples.
- `TextLineNumbering.jl`: the span path of `print_document` and
  `_output_to_input_map`.
- `TextFiltering.jl` (`_filter`), `TextFirstLine.jl` (`_first_line`),
  `TextHighlighting.jl` (`_highlight`), `SelectionInverting.jl` (`_invert`), each
  with the span branch of its maps and its reader.
- `TextToString.jl` (`TextNewlineToString`), `ConsoleBackend.jl`
  (`_render_span!(::TextNewline)`).
- `SyntaxToText.jl`: `_compute_output_lines` lets a span join the line before it
  and a `TextNewline` open a line.
- `TextFolding.jl`: `_make_fold_placeholder` reads the placeholder of a fold as
  spans.

### 3.3 Structural paths to a span at the top of a block, in source

`PrimitiveToText.jl` (5), `TextDocument.jl` (`@insertion`, and the path helpers,
which take a line step too), `WordWrapping.jl` (3), `SelectionInverting.jl`,
`TextHighlighting.jl` (their span branches), `TextToGraphics.jl` (the lazy list
of spans), `ObjectToWidget.jl` (`_end_cursor`), `ObjectFieldToWidget.jl`
(`_caret_in_content`), `WidgetToGraphics.jl` (`_map_plain_text_reference`), and
`ConversationEditor.jl` (`_body_range_selection`, `_parse_body_span_range`,
`_map_body_to_value`, `_body_selection`).

### 3.4 Tests

- 24 files build about 128 blocks of spans. Most are one run.
- About 20 files assert or build a path to a span at the top of a block, about
  100 sites. The most: `InlineImageCaretTest` (about 18), `PrimitiveToTextTest`
  (11), `SelectionInvertingTest` (13), `TextDocumentTest` (7),
  `WidgetTextEditTest` (7). `ExampleSweeps.jl` has the prefix
  `".elements[1].content{"` for the example "text".
- 14 files name `TextNewline`, 46 times. `WordWrappingTest` and
  `SizeRangeChildRuleTest` assert soft `TextNewline`s in the output of a wrap.
- `TextSpanReferenceStep` is a flat range in every test, so it does not change.

## 4. What it does not touch

- The flat caret space and its values.
- A `'\n'` inside a `TextString`. Step 7 of
  [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md) removes
  it; this plan keeps the paths that read it.
- The syntax, which gives lines already.

The two plans are independent. They share the producers of a free text
(`ReferenceToText`, the evaluator, the fault messages) and the guard. The plan
that lands second follows the other.

## 5. The version

`TextNewline` and `TextNewlineToString` are exported (`TextModule.jl`). Their
removal is a removed export, which takes a minor version step after 0.1.0 (R36 of
the release plan). The span path takes three more exports with it,
`WrapSegment`, `convert_flat_offset_to_element` and
`convert_element_to_flat_offset`, and the keyword `separator` of
`TextLineNumbering` and `LineNumbering`, which only the prefix spans of a block
of spans used. No caller in the three repositories passes or names them.

## 6. Questions

- **L1 The constructor of a block of spans. Decided, the owner, 2026-10-09: (b),
  the arguments of a `TextBlock` are always its lines**, in each constructor: the
  arguments, a vector, a thunk and the raw form. A producer of one run writes
  `TextBlock(TextLine(run))`, or calls `make_text_block(content, style)` when it
  turns a string in a style into text.
  - The elements of the raw form and of a thunk are a computation, which a
    constructor can not read when it runs, so these two take lines in every
    answer. Only the constructor of arguments and of a vector was open.
  - A block of zero lines stays valid, because a filter with no match gives one.
    The insertion of an empty text gives one empty line.
  - Not taken: (a) arguments that are runs give one line, which gives one name two
    meanings (`TextBlock(a, b)` is two lines or two runs by the types of `a` and
    `b`) and makes `TextBlock(spans...)` and `TextBlock(() -> spans)` disagree; a
    `TextLine` alone as a text at the top of a chain, which gives each consumer
    its second path back.
- **L2 The height of an empty line. Decided, the owner, 2026-10-09: (a), an empty
  line holds one empty run in its style**, and the layout sizes the line by the
  font of that run. Text typed into the line goes into the run and takes its font
  and its colour (the owner: "it also allows type-in in that style font/color").
  - Today a `TextNewline` carries the font of an empty line, and an empty
    `TextLine` takes the first font of its block (`_line_height_font`), also when
    it holds an empty run in another font. So an empty line after a heading has
    the height of the heading, and the caret in it the height of its run.
  - A caret in an empty run is drawn, one line high (the test "TextToGraphics
    draws a caret in an empty span, one line high"). The syntax gives an empty run
    already: it splits `"a\n\nb"` into three runs, and the middle one is `""` in
    the style of its span. `make_text_block` does the same.
  - A line with no run stays valid and takes the first font of its block. It has
    no style, so it is not a second form of an empty line.
  - Not taken: (b) a font on `TextLine`, which is a second place for the style of
    a typed text and a sixth positional field. A style of a line (alignment,
    spacing, its height) is a paragraph style, a design of its own when a domain
    needs one.
- **L3 A place in a text of one line. Decided, the owner, 2026-10-09: (b), the
  flat form.** The forward map of a producer of one line gives the flat caret and
  the flat range. Its backward map reads the flat forms, and the structural forms
  that an edit and an operation bring, through the readers of the text domain:
  `get_flat_caret(block, reference)` for a caret, and a new sibling
  `get_flat_range(block, reference)` for a range, which the owner approved with
  this answer. So no producer names the line step; only the text domain and the
  generic edit know the shape of a text.
  - The structural form stays, with the line step, because an operation names
    the string it changes: `ReplaceStringRangeOperation` (`PrimitiveDocument.jl`)
    splices a string at its path and leaves the caret at that path, until the
    next print makes it flat.
  - `PrimitiveToText` gives a structural caret and a flat range. The flat range
    came with the clipboard work (`773dd0f67`, 2026-09-17), which left the caret
    as it was; neither the commit nor its plan gives a reason for the structural
    caret.
  - The producers that build or parse the structural path today: `PrimitiveToText`,
    `ObjectToWidget._end_cursor`, `ObjectFieldToWidget._caret_in_content`,
    `WidgetToGraphics._map_plain_text_reference`, and `_body_range_selection`,
    `_parse_body_span_range`, `_map_body_to_value`, `_body_selection` of
    `ConversationEditor`.
  - Not taken: (a) each producer keeps the structural form with the line step,
    which makes each producer of one line follow every change of the shape of a
    text.
- **L4 The placeholder of a fold. Decided, the owner, 2026-10-09: nothing or a
  list of runs.** The owner: "nothing or a TextString is usually enough, but a
  list of runs is also fine". So `TextFold.placeholder` holds the runs that
  `TextFolding` appends to the first line of a closed region, as
  `TextLine.elements` does, or `nothing` for `…`. One run is a list of one run.
  - Today the field is `Union{Document, Nothing}`, and `_make_fold_placeholder`
    reads a `TextBlock` as spans, one span, or `nothing`. `SyntaxToText` gives the
    ellipsis and the closing spans of the node (`…}`), so it needs a list, and the
    folding example gives one run.
  - A single `TextString` is not kept as a second form, for the reason of L1.
  - Not taken: a `TextBlock` of one line, which only a check at run time keeps to
    one line; a `TextLine`, whose indentation, gutter, fold and soft breaks a
    placeholder must ignore.
  - The name `TextFold`, which step 1 of the fold plan chose without a question,
    is accepted (the owner, 2026-10-09: "the name is fine").

## 7. Facts found

- 2026-10-09: no source makes a lazy list of spans, so the lazy span layout of
  `TextToGraphics` serves only 5 tests.
- 2026-10-09: the gutter marks (`_make_fold_mark`, `_make_numbered_line`) are
  blocks of one run, which the recursion prints to graphics beside the line.
- 2026-10-12, the inventory again at main `8cd3db4e6`, after the first plan
  landed: about 40 producers of a block of spans in source and 20 in the
  examples; `TextNewline` on 70 lines of source, 14 of the examples and 48 of the
  tests (15 files); 21 call sites of `_is_block_of_lines`; about 117 blocks of
  spans in 32 test files. `ObjectToWidget` and `ObjectFieldToWidget` no longer
  build a block. omnet-julia has 7 blocks of one run; inet-julia's
  `PacketDiagramToText` gives a `TextNewline` after each row.
- 2026-10-12: a reader of a text that joins the runs at the top of a block reads
  nothing from a block of lines. Such readers were `_text_to_string` of the
  assistant (the text that a model gets), `_text_is_empty` of the conversation,
  and the result of a formula; they read the flat string now. A producer and its
  readers must change in one step.
- 2026-10-12: once a primitive is a block of lines, Enter there is a break of the
  text domain. The rule of the first plan for a field of one run (N10: it takes no
  break, and the key falls to the bindings around it) now applies to each producer
  of a value of one line: `PrimitiveToText` declines an edit that holds a `'\n'`,
  so Enter still makes the value of a type-in, and `_text_break` binds in every
  block. A paste of text with breaks into a primitive is declined too; on main the
  value took the breaks, which its one run then held.

## 8. Steps (tentative)

Each step is one commit, on a branch in a worktree, with its tests. Until step 5,
a block of spans still works, so the producers move one at a time.

0. **The baseline.** The text and projection suites of the platform, the
   conversation and widget suites, the example sweeps and the console, each part
   in a process of its own, at main before step 1.
   *Started (2026-10-12)* at main `8cd3db4e6`, in `/var/tmp/text-lines/baseline`:
   the sweep of the first plan, with `test_platform` at 12 GB (it peaks near 8 GB
   in one process), and the catalog, its coverage, the insertion, the assistant
   MVP and the tool views.
   **`make_text_block(content, style)`** is step 1 of
   [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md). The
   plan that starts first makes it.
1. **The producers of many lines give lines**: `ReferenceInspectorToText`,
   `SelectionInspectorToText`, `ReferenceToText`, `make_evaluator_arguments_text`
   (one line for each argument), and the tooltip of the gallery. Their
   `WordWrapping` then wraps lines.
   *Built (2026-10-12), `8f648b6fe`.* `make_evaluator_arguments_text` gave lines
   already, from the first plan. The tooltip of a Julia definition gave a run for
   each line, which a block of spans draws on one row; it gives lines too.
2. **The producers of one run give one line**, by `make_text_block` or
   `TextBlock(TextLine(run))` (L1). First `get_flat_range(block, reference)` in the
   text domain, with its tests; its name follows its sibling `get_flat_caret`.
   Then each producer maps forward to the flat form and backward through
   `get_flat_caret` and `get_flat_range` (L3):
   `PrimitiveToText`, `FaultToText`, `@insertion TextBlock`, the widgets
   (`ObjectToWidget`, `ObjectFieldToWidget`, `WidgetToGraphics`), the
   conversation and the assistant, Formula, the Julia tooltip, RST, `NaturalProjection`,
   the gutter marks, and the fold placeholder as a list of runs (L4). One commit for each package
   slice, with the tests that assert its paths.
   *Built (2026-10-12)*: the text slice with `get_flat_range` (`fa5a838b5`), the
   widgets (`76eb9bbe8`), the conversation and the assistant (`936f72fc6`), and
   formula, RST and natural (`879c8647c`).
   - `get_flat_range(block, reference)` is `_text_flat_selection` by a public
     name; a caret is the empty range.
   - `make_text_block(content)` gives lines in the font of a text with no style,
     as `TextString(content)` does; a part, a thinking, a committed paragraph, a
     streamed text and a formula result use it.
   - The view of a field of code gives a line for each line of its text, with a
     run for each piece, and a text widget maps a place of its view back through
     `get_flat_range` on the view, which the IO map of its content holds.
   - The body of a draft is one line; its caret is the flat range past the runs
     before the value, so the empty chooser needs no case of its own.
   - The placeholder of a fold is `Union{Vector{TextDocument}, Nothing}`; the
     syntax gives a `CellVector{TextDocument}` from its computed cell.
3. **The examples**: the documents of the text examples give lines, and the two
   examples of `TextNewline` leave the catalog. `ExampleSweeps.jl` follows.
   *Built (2026-10-12), `9f66afbe5`*, with their export, their precompile
   statements and their ids in the catalog tests.
4. **The tests of the consumers** build lines: the blocks of spans and the soft
   `TextNewline`s in `WordWrappingTest`, `TextToGraphicsTest`, `TextLineModelTest`,
   `InlineImageCaretTest`, `TextDocumentTest` and the decorators. The 5 lazy lists
   of spans become lazy lists of lines.
   *Built (2026-10-12), in `5bb137d54` with the decorators of step 5.* A wrap is
   the `soft_breaks` of a line, counted by hand from `_compute_soft_breaks`; the
   tests of the decorators read the line step and the flat base; the lazy test of
   spans in `TextToGraphicsTest` goes, as the test of a lazy list of lines covers
   its cases, and its laziness test now expects no read of `next` until the output
   asks for it. No test names `TextNewline`. To check when it runs: the numbers of
   the soft breaks, the laziness test, and the style of a run typed beside an image
   on a line with no text run.
5. **The consumers lose their span path**: the list of §3.2, and
   `_is_block_of_lines`. With them go the row that `TextToGraphics` draws for a
   `'\n'` in a run, the cut of `TextFirstLine` there, and the cut of a run in
   `SyntaxToText` (N11 of [a-text-span-holds-no-line-break.md](../done/a-text-span-holds-no-line-break.md)):
   step 2 has moved the producers of a free text, so no run holds a break, which
   the guard `test_text_runs_hold_no_break` checks. `_line_height_font` sizes an empty line by the font of its
   empty run (L2), with a test of an empty line after a heading. `WordWrapping` keeps only `soft_breaks`, and its maps are
   the identity.
   *Built (2026-10-12)*: the decorators and the flat helpers (`5bb137d54`),
   `TextToGraphics` (`6711e0b1f`, 380 lines fewer: a group is a line, a run is one
   piece for each row of its soft breaks, the lazy list of spans goes), the console
   (in `29be6b79b`), and the cut of a run in `SyntaxToText` (`31cd2fc3c`). The test
   of an empty line after a heading gives the heading its own metrics in a
   `FixedMeasure` (`75fbd38d2`).
   - `_text_break` binds in every block; a producer of a value of one line declines
     the break (§7).
   - `TextLineNumbering` puts the number in the gutter only, and `TextFirstLine`
     keeps the first line, the same object.
   - The decorators keep no branch for a lazy list of lines. Their span branch
     walked a lazy list too, and no chain gives them one.
6. **`TextNewline` and `TextNewlineToString` go**, with their exports, and every
   constructor of `TextBlock` takes lines (L1); the tests and the examples that
   still pass runs follow, about 130 sites. A guard test walks the printer output of every example
   and rejects an element of a block that is not a `TextLine`.
   *Built (2026-10-12), `29be6b79b`.* `test_text_blocks_hold_only_lines` shares
   the walk of `test_text_runs_hold_no_break` and runs after it in the umbrella
   suite. The constructors store what they get; their docstring says that the
   arguments are lines. The recorded precompile statements that name a removed type
   go; a statement of a removed private function is skipped when it is replayed.
7. **A full sweep** against step 0.
   *Done (2026-10-12)* at `75fbd38d2` against main `8cd3db4e6`, in
   `/var/tmp/text-lines/branch-5bb137d54` and `/var/tmp/text-lines/baseline`.
   - 25 of 34 parts give the counts of main; `test_printers` and
     `test_domain_examples` count more checks of the lines; the guard of lines
     passes 111 examples; the catalog keeps its two failures and loses the checks
     of the two removed examples of `TextNewline`.
   - `test_platform` had 4 failures and 4 errors more than main, in the tests that
     step 4 converted: a test called `get_flat_string` on a line, which now has
     that method; a test of the cut of a run, which goes with the cut; the text
     area of a plain string answers Return with a string edit, as on main; the
     identity map of the wrap keeps the node types; and a caret on a line that the
     filter drops goes to the next kept line, as on main, where the line path of
     the filter used the same map (`206eaf8ee`).
   - Two examples, "text" and "text_with_image", now walk the same carets left
     and right: their broken marks are tests (`26d978140`).
   - `test_assistant_mvp`: Return in the draft typed a break, since the body of a
     draft is a line. The composer owns Return (plain submits, Shift breaks the
     line), so it declines an edit of the text under a card that holds a break
     (`4576c2461`). It passes as on main.
   - At `4576c2461` the fixed tests, the invariants (391 pass, 6 broken), the
     conversation (the failing lines of main and no other), the conversation
     editor and `test_text_to_graphics` pass.
8. **The other repositories**, after the landing: inet-julia's
   `PacketDiagramToText` gives a line for each row and loses its stale comment;
   omnet-julia's 7 blocks of one run give one line (L1). Both make their precompile statements again.
   *Prepared (2026-10-12)* on the branches `text-lines` of inet-julia (`3db493c`:
   a `TextLine` for each row of the packet diagram, and its string needs no strip
   of a trailing break) and of omnet-julia (`c1b82b45`: the source view of the
   workbench is `make_text_block`, as a source has many lines, and the other six
   sites are one line), to land with this branch, as the first plan did.
   Checked (2026-10-12) in scratch environments against this branch: inet-julia's
   test of the packet diagram passes 128 of 128, the figure character for
   character; omnet-julia's legacy examples hold only lines and no run with a
   break (11 of 11), and its tests of the result views fail only where main does
   (`SimulationTest.jl` 248 and 307). The six tests of the workbench error on main
   too (`Projectured` is not defined in `OmnetPresentation`), so they do not check
   the source view.
9. **The documents**: `text.md` (the shape, the paths, the flat caret), the
   guides that show a block of spans, and a note in `text-domain-kit.md` that
   shape A is reached.
