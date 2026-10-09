# A text block holds only lines

> **Kind:** plan · **Status:** pending, 2026-10-09. The owner decided the end
> state on 2026-10-09 (N5 of [a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md)),
> and that it is a plan of its own, and L1 on 2026-10-09. The other questions of
> §6 are open, and no step is started. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [text-domain-kit.md](text-domain-kit.md) (shape A of Phase 3),
> [a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md) (N5)

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
  [a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md) removes
  it; this plan keeps the paths that read it.
- The syntax, which gives lines already.

The two plans are independent. They share the producers of a free text
(`ReferenceToText`, the evaluator, the fault messages) and the guard. The plan
that lands second follows the other.

## 5. The version

`TextNewline` and `TextNewlineToString` are exported (`TextModule.jl`). Their
removal is a removed export, which takes a minor version step after 0.1.0 (R36 of
the release plan).

## 6. Open questions

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
- **L2 The height of an empty line** (N5a of the other plan). A `TextNewline`
  carries the font of an empty line today, and an empty `TextLine` takes the
  first font of its block, so an empty line after a heading has the height of the
  heading.
  - (a) An empty line holds one empty run in its style. This needs the fix of the
    caret in an empty `TextString`, which is not drawn (found in Phase 3 of
    `text-domain-kit.md`).
  - (b) `TextLine` gets a font.

  My proposal, not decided: (a), because a run is where a style is now, and the
  caret of an empty line then stands in that run.
- **L3 A place in a text of one line.** `PrimitiveToText` maps `value{s}` to a
  structural `.elements[1].content{s}` position and `value{s:e}` to a flat range.
  `ObjectToWidget`, `ObjectFieldToWidget`, `WidgetToGraphics` and
  `ConversationEditor` build or parse the structural path too. With lines, each
  gets the line step, or each uses the flat caret.

  My proposal, not decided: the flat caret where a place in the text is meant,
  and a structural path only where a run is meant (a style, an image). Step 0
  finds why `PrimitiveToText` gives a structural position for an empty range.
- **L4 The placeholder of a fold.** `TextFold.placeholder` is a `TextBlock` that
  `TextFolding` appends to the line of the fold as spans.
  - (a) It stays a block, and `TextFolding` appends the runs of its one line.
  - (b) It becomes a `TextLine`, because it is a part of a line.

  My proposal, not decided: (b).

## 7. Facts found

- 2026-10-09: no source makes a lazy list of spans, so the lazy span layout of
  `TextToGraphics` serves only 5 tests.
- 2026-10-09: the gutter marks (`_make_fold_mark`, `_make_numbered_line`) are
  blocks of one run, which the recursion prints to graphics beside the line.

## 8. Steps (tentative)

Each step is one commit, on a branch in a worktree, with its tests. Until step 5,
a block of spans still works, so the producers move one at a time.

0. **The baseline.** The text and projection suites of the platform, the
   conversation and widget suites, the example sweeps and the console, each part
   in a process of its own, at main before step 1. Find the reason for the
   structural position of `PrimitiveToText` (L3).
   **`make_text_block(content, style)`** is step 1 of
   [a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md). The
   plan that starts first makes it.
1. **The producers of many lines give lines**: `ReferenceInspectorToText`,
   `SelectionInspectorToText`, `ReferenceToText`, `make_evaluator_arguments_text`
   (one line for each argument), and the tooltip of the gallery. Their
   `WordWrapping` then wraps lines.
2. **The producers of one run give one line**, by `make_text_block` or
   `TextBlock(TextLine(run))` (L1), with their paths by L3:
   `PrimitiveToText`, `FaultToText`, `@insertion TextBlock`, the widgets
   (`ObjectToWidget`, `ObjectFieldToWidget`, `WidgetToGraphics`), the
   conversation and the assistant, Formula, the Julia tooltip, RST, `NaturalProjection`,
   the gutter marks, and the fold placeholder by L4. One commit for each package
   slice, with the tests that assert its paths.
3. **The examples**: the documents of the text examples give lines, and the two
   examples of `TextNewline` leave the catalog. `ExampleSweeps.jl` follows.
4. **The tests of the consumers** build lines: the blocks of spans and the soft
   `TextNewline`s in `WordWrappingTest`, `TextToGraphicsTest`, `TextLineModelTest`,
   `InlineImageCaretTest`, `TextDocumentTest` and the decorators. The 5 lazy lists
   of spans become lazy lists of lines.
5. **The consumers lose their span path**, after L2: the list of §3.2, and
   `_is_block_of_lines`. `WordWrapping` keeps only `soft_breaks`, and its maps are
   the identity.
6. **`TextNewline` and `TextNewlineToString` go**, with their exports, and every
   constructor of `TextBlock` takes lines (L1); the tests and the examples that
   still pass runs follow, about 130 sites. A guard test walks the printer output of every example
   and rejects an element of a block that is not a `TextLine`.
7. **A full sweep** against step 0.
8. **The other repositories**, after the landing: inet-julia's
   `PacketDiagramToText` gives a line for each row and loses its stale comment;
   omnet-julia's 7 blocks of one run give one line (L1). Both make their precompile statements again.
9. **The documents**: `text.md` (the shape, the paths, the flat caret), the
   guides that show a block of spans, and a note in `text-domain-kit.md` that
   shape A is reached.
