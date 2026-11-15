# Architecture review: Text, syntax tree, natural notation, text entry

Commit 3a9b4fae4. Reviewer area key: text-syntax.

## Scope

Paths: `source/platform/text` (24 files, 7875 lines), `source/platform/syntax` (12 files, 4888 lines), `source/platform/natural` (8 files, 1579 lines), the text parts of `source/platform/widget` (`DrawnTextLine.jl`, `LetterMatch.jl`, and the text field code in `WidgetDocument.jl` and `WidgetToGraphics.jl`), and for comparison `source/domain/json`, `source/domain/yaml`.

Read in full: `TextModule.jl`, `SyntaxModule.jl`, `NaturalModule.jl`, `NaturalNotation.jl`, `NaturalRegistry.jl`, `TextView.jl`, `MarkedTextToText.jl`, `PrimitiveToText.jl`, `DrawnTextLine.jl`, `LetterMatch.jl`, `JsonToSyntax.jl`, and the three package documents `text.md`, `syntax.md`, `natural.md`, with `concepts.md` and `architecture-decisions.md`.

Read in large ranges: `TextDocument.jl` (lines 1 to 1500 and 1856 to 2165 of 2283), `SyntaxDocument.jl` (1 to 330), `SyntaxToText.jl` (255 to 352, 1412 to 1557, 1676 to 1735, and the list of its functions), `WordWrapping.jl` (60 to 166), `TextToGraphics.jl` (the list of its functions, 349 to 510, 654 to 662, 1420 to 1500), `NaturalProjection.jl` (1 to 251), `SyntaxNatural.jl` (60 to 157), `WidgetToGraphics.jl` (1270 to 1380, 2237 to 2560, 2640 to 2830, 6085 to 6200, 6745 to 6800, 14215 to 14300), `WidgetDocument.jl` (100 to 345, 2200 to 2262, 3764 to 3842), `ProjectionDefaults.jl` of the kernel (95 to 250), `PrimitiveDocument.jl` (96 to 215).

Sampled by search and short ranges: the other text decorators (their reader methods), `PrimitiveToSyntax.jl`, `ConversationEditor.jl`, `TerminalToWidget.jl`, `TaskPagesToWidget.jl`, `TaskGroupToWidget.jl`, `McpLogToWidget.jl`, `GitToWidget.jl`, `JuliaModule.jl`, `LanguageServerDocument.jl`, `YamlToSyntax.jl`, the three parsers, the arrangement slice (`Picking.jl`, `Finding.jl`), the clipboard slice. I ran no code. Every claim below comes from reading.

About 7,300 source lines were read line by line.

## State

The core of the area is sound. A text is one model: a block (`TextBlock`) of lines (`TextLine`) of runs (`TextString`, an image, a gap). The caret has one canonical form, a flat character offset. One table of keys (`@gestures TextBlock`, [TextDocument.jl:874](../../../source/platform/text/TextDocument.jl#L874)) serves a text file, a syntax view, a text field, a tab name, the draft of the chat and the console. One splice printer (`SyntaxCompoundToText`) prints every compound of the syntax tree, one level at a time. One measure (`TextMeasure`) serves the text layout, the wrap and the widgets.

The main weakness is the seam around the text domain, not the domain. A text edit travels back through the chain in two forms, and a caret in three, so each stage writes readers for each form by hand. Each place that shows a plain string as a text (a primitive value, a text field, a tab name, the draft, a marked text) builds its own lines and its own map between the string and the text. Outside the text slice, several views do not use the text domain for a read-only text of many lines, and draw one label for each line. The view of code (numbers, folds, gutter) is a chain that three packages assemble by hand, so the other domains have none. The natural notation keeps eight tables that are global to the process, beside a newer seam that the owner chose to replace them.

The syntax tree itself has two overlapping models (one combined node, six small wrappers), but a plan decided that on purpose, so it is no finding here.

## Inventory

### I1. Every way that a text reaches the screen

| Way | Where | Measure | Wrap | Cut | Caret and range | Colours of ranges | Lazy lines |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Text domain, lines in a `CellVector` | `TextToGraphics` ([TextToGraphics.jl:654](../../../source/platform/text/TextToGraphics.jl#L654)) | `TextMeasure` | `WordWrapping` sets soft breaks ([WordWrapping.jl:107](../../../source/platform/text/WordWrapping.jl#L107)) | by the container | yes, caret and band of the `TextTheme` ([TextToGraphics.jl:1224](../../../source/platform/text/TextToGraphics.jl#L1224)) | `HighlightedText`, `MarkedText`, `SelectionInverting` | no |
| Text domain, lines in a lazy `ListNode` | `_print_listnode` ([TextToGraphics.jl:1427](../../../source/platform/text/TextToGraphics.jl#L1427)) | same | honours soft breaks; `WordWrapping` is not lazy | no | no: no key ([TextToGraphics.jl:506](../../../source/platform/text/TextToGraphics.jl#L506), [TextDocument.jl:2115](../../../source/platform/text/TextDocument.jl#L2115)), and no caret at a point (`text.md`) | no | yes |
| Text with a gutter | `TextBlockToScrollLayout` | same | yes | scroll pane | yes | yes | no |
| A string that a widget draws | `_push_text_block!` ([WidgetToGraphics.jl:1327](../../../source/platform/widget/WidgetToGraphics.jl#L1327)), about 40 call sites | `TextMeasure` | its own greedy wrap, `_text_lines` ([WidgetToGraphics.jl:1293](../../../source/platform/widget/WidgetToGraphics.jl#L1293)) | "…" after `max_lines` ([WidgetToGraphics.jl:1353](../../../source/platform/widget/WidgetToGraphics.jl#L1353)) | read-only, written once in `DrawnTextLine.jl`; its own band and a caret 2 pixels wide ([DrawnTextLine.jl:377](../../../source/platform/widget/DrawnTextLine.jl#L377)) | no | no |
| A string in a text field | `TextView` of a block ([WidgetToGraphics.jl:2309](../../../source/platform/widget/WidgetToGraphics.jl#L2309)) | text domain | `wrap` of the field | box cut, scroll to the caret | text domain | `language` pieces | no |
| One label for each line | terminal, task facts, agent summary (see TS-3) | widget | per label | no | per label only | one colour for a line | no |
| Console | `render_console` of a `TextBlock` | characters | no | no | `SelectionInverting` | run colours | no |
| Plain string | `TextToString` | none | none | none | none | none | no |
| `GraphicsText` made directly | charts (27 sites in two chart files) | measure | no | no | no | no | no |

### I2. Every place where a person types characters

All of these end in the one key table of the text domain. The table shows what differs: the glue.

| Place | Text comes from | Map between the string and the text | Form of the edit at the owner | Many lines |
| --- | --- | --- | --- | --- |
| Text file, `TextBlock` document | the document | none | `ReplaceTextRangeOperation`, or lowered to one run | yes |
| Syntax view (JSON, SQL, Julia) | `SyntaxToText` | four reader methods in `SyntaxToText.jl` (267, 309, 1423, 1499) | `ReplaceStringRangeOperation` at `.value{s:e}` of a leaf | only where a leaf holds lines |
| `WidgetText`, `WidgetTextarea` over a plain string (16 construction sites: find and filter fields, file dialog, titles, settings) | `_make_plain_text_view` ([WidgetToGraphics.jl:2309](../../../source/platform/widget/WidgetToGraphics.jl#L2309)) | `_get_plain_text_caret`, `_map_plain_text_reference` (2362, 2394) | `ReplaceStringRangeOperation` at `content{s:e}` | field no, area yes |
| `WidgetText` over a document that gives a value (`ObjectField`) | same view | `_get_value_text_caret` (2328) | the whole new string, stored through the slot (`_make_value_text_store`, 2759) | no |
| Tab name | `_print_tab_name_view` ([WidgetToGraphics.jl:6122](../../../source/platform/widget/WidgetToGraphics.jl#L6122)), only while the name holds the caret | `_find_tab_name_range`, `_map_tab_name_operation`, `_map_tab_name_reference` (6097, 6761, 6781) | `ReplaceStringRangeOperation` at `…selector.text{s:e}` | no |
| Draft of the chat | `_editable_body` ([ConversationEditor.jl:563](../../../source/platform/conversation/ConversationEditor.jl#L563)) | `_map_body_to_value` (784) | edit of `value` | yes |
| Primitive value in a tab, a table cell, the terminal input | `PrimitiveToText` | `_forward_value`, four `_backward_…` functions ([PrimitiveToText.jl:15](../../../source/platform/text/PrimitiveToText.jl#L15)) | `ReplaceStringRangeOperation` at `value{s:e}`, or a type-in | string yes |
| Marked text (source file of a language server) | `MarkedTextToText` | `_forward_marked_text`, `_backward_marked_text` ([MarkedTextToText.jl:50](../../../source/platform/text/MarkedTextToText.jl#L50)) | `ReplaceStringRangeOperation` at `text{s:e}` | yes |
| Insertion buffer, navigator address | a syntax leaf of `InsertionToSyntaxLeaf` | the leaf | edit of `value` | no |
| Label, button, badge (read only) | drawn string, `DrawnTextLine` | `map_drawn_caret_forward`, `map_drawn_place_backward` | none; keys go to a short-lived block ([DrawnTextLine.jl:274](../../../source/platform/widget/DrawnTextLine.jl#L274)) | wrap of the label |

Caret move, word move, range selection and Unicode handling are the same in every row, because one table answers. Undo is the same, because every edit is an operation. I did not check copy and paste in each row; the clipboard reads a selection that ends in a range of a text field ([Clipboard.jl:426](../../../source/platform/clipboard/Clipboard.jl#L426)).

### I3. Builders of "the lines of a string"

| Builder | Where | Keeps unchanged lines | Placeholder | Colours |
| --- | --- | --- | --- | --- |
| `make_text_block(thunk, style; placeholder, empty_thunk)` | [TextDocument.jl:457](../../../source/platform/text/TextDocument.jl#L457) | yes, common head and tail | yes | no |
| `PrimitiveStringToTextBlock` | [PrimitiveToText.jl:259](../../../source/platform/text/PrimitiveToText.jl#L259) | yes, own head and last line cells | yes | no |
| `_editable_body` of the composer | [ConversationEditor.jl:563](../../../source/platform/conversation/ConversationEditor.jl#L563) | no | yes | no |
| `_make_code_lines` of a code field | [WidgetToGraphics.jl:2279](../../../source/platform/widget/WidgetToGraphics.jl#L2279) | no | no | pieces `(count, colour)` |
| `make_marked_text_lines` | [MarkedTextToText.jl:107](../../../source/platform/text/MarkedTextToText.jl#L107) | yes, by line and pieces | no | pieces `(count, colour)` from marks |
| `_read_text_table_key` | [DrawnTextLine.jl:274](../../../source/platform/widget/DrawnTextLine.jl#L274) | a new block for each key | no | no |
| one-line blocks: bool, number, type-in, tab name | `PrimitiveToText.jl` (83, 122, 197), `WidgetToGraphics.jl:6122` | n/a | type-in only | no |

### I4. Forms of a place in a text, and of an edit

| Thing | Forms | Where both are accepted |
| --- | --- | --- |
| Caret | flat `TextRangeReferenceStep{k}`; kernel `RangeReferenceStep{k}` right on the block; structural `.elements[i].elements[j].content{k}` | `_text_flat_selection` ([TextDocument.jl:982](../../../source/platform/text/TextDocument.jl#L982)), `get_flat_caret` (1041), `_parse_selection_range` (1466) |
| Edit of characters | flat `ReplaceTextRangeOperation`; lowered `ReplaceStringRangeOperation` on one run; `ReplaceStringRangeOperation` on a field that holds a `TextBlock` (`splice_value!`, [TextDocument.jl:810](../../../source/platform/text/TextDocument.jl#L810)) | `_lower_unless_line_edit` (2123) chooses |
| Where the flat edit is lowered | `TextToGraphics` in a window ([TextToGraphics.jl:372](../../../source/platform/text/TextToGraphics.jl#L372)); `SyntaxCompoundToText` in the console ([SyntaxToText.jl:1499](../../../source/platform/syntax/SyntaxToText.jl#L1499)); never for an edit of a break | |

Reader methods of the seven text-to-text stages (`WordWrapping`, `HighlightedTextToText`, `FilteredTextToText`, `TextFirstLine`, `SelectionInverting`, `TextFolding`, `TextLineNumbering`): 33 methods of `read_intent`. Five stages have a method for `ReplaceStringRangeOperation`; none has one for `ReplaceTextRangeOperation`.

### I5. Ways to colour ranges of a text

| Way | Input | Shape of a range | Sets | Where |
| --- | --- | --- | --- | --- |
| `HighlightedText` | any text document | a pattern, matched in each run | background | [HighlightedTextToText.jl](../../../source/platform/text/HighlightedTextToText.jl) |
| `MarkedText` | a string | `TextMark(start, stop; text)` | glyph colour | [TextDocument.jl:660](../../../source/platform/text/TextDocument.jl#L660) |
| `WidgetText.language` | a string | `compute_code_pieces` gives `(count, colour)` | glyph colour | [WidgetDocument.jl:294](../../../source/platform/widget/WidgetDocument.jl#L294) |
| `SelectionInverting` | a text block | the selection | inverse colours | console only |
| a domain projection to syntax | a document | one leaf, one style | glyph colour | every `…ToSyntax` |

### I6. Kinds of syntax node and their use

Counts are construction sites outside `SyntaxDocument.jl`, in `source/`.

| Type | Sites | Note |
| --- | --- | --- |
| `SyntaxLeaf` | 475 | fields `indentation` and `collapsed` are read by no printer |
| `SyntaxNode` (delimiters, separator, indentation, collapse in one) | about 350 | the combined form |
| `SyntaxConcatenation` | 86 | |
| `SyntaxDelimitation` | 6 | |
| `SyntaxSeparation` | 3 | |
| `SyntaxNavigation` | 1 | |
| `SyntaxIndentation` | 0 | tests only |
| `SyntaxCollapsible` | 0 | tests only |
| `SyntaxInsertion` | 0 | declared, never made or printed |

What a domain projection to syntax repeats (JSON, YAML, XML compared): the two rows `XNothing => InsertionNothingToSyntaxLeaf(…)` and `XInsertion => DomainInsertionToSyntaxLeaf(XDocument; …)` (8 domains); a scalar leaf `SyntaxLeaf(bound(:value, T, make_hinted_text(…; placeholder = "enter x …")))` (JSON and YAML have the same three); an entry node made with the raw constructor and empty delimiters ([JsonToSyntax.jl:119](../../../source/domain/json/JsonToSyntax.jl#L119), [YamlToSyntax.jl:105](../../../source/domain/yaml/YamlToSyntax.jl#L105)).

### I7. Ways a type says how it shows (natural notation)

| Way | Count of uses in `source/` | Storage |
| --- | --- | --- |
| `register_natural_domain!` / `register_natural_notation!` (rung table) | 11 | `_NOTATIONS`, `_FORMATS`, `_PARSERS`, `_EXPRESSIONS` ([NaturalNotation.jl:9](../../../source/platform/natural/NaturalNotation.jl#L9)) |
| `register_natural_rung!` (ladder step) | 1, plus 2 in the platform | `_LADDER` |
| `register_natural_syntax!`, `register_natural_graphics!`, `register_natural_fallback!` (factory lists) | 6, 24, 1 | three more constants ([NaturalRegistry.jl:38](../../../source/platform/natural/NaturalRegistry.jl#L38)) |
| method of `make_graphics_projection(::Type{T}; measure, appearance)` (seam) | 35 methods | the method table, read by `collect_graphics_projection_types` ([DocumentComposition.jl:37](../../../source/platform/widget/DocumentComposition.jl#L37)) |
| `extra` rows of a caller, and row makers (`make_natural_primitive_row`, `make_conversation_row`, …) | per caller | none |

The natural notation does not overlap with the syntax pipeline: it only chains it. It overlaps with the reflection view in one point, which `reflection.md` states on purpose: a value of no domain can show as reflected syntax (`ObjectToSyntax`), as a form (`ObjectToWidget`), or as a bounded tree (`ReflectionToWidget`).

## Findings

### TS-1 A text edit and a caret travel back in more than one form

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 3 (one way to edit), 7 (generic before special), PAR-PREFER-REFERENCE-RETARGET, PAR-MAPPERS-ARE-INVERSES.
- **Today:** A key in a text makes a flat edit, `ReplaceTextRangeOperation` (replace the flat range `{s:e}` of a block). `_lower_unless_line_edit` ([TextDocument.jl:2123](../../../source/platform/text/TextDocument.jl#L2123)) then turns it into the older form, a `ReplaceStringRangeOperation` on one run at `.elements[i].elements[j].content[s:e]`, unless the edit holds a break or changes the indentation. The comment says why: "so the existing per-stage `ReplaceStringRangeOperation` readers carry it the rest of the way up the chain" ([TextDocument.jl:2013](../../../source/platform/text/TextDocument.jl#L2013)). So both forms are alive. `SyntaxToText.jl` has four edit readers, two for each form (lines 267, 309, 1423, 1499). Five text decorators have a hand-written reader for the lowered form only, for example [FilteredTextToText.jl:136](../../../source/platform/text/FilteredTextToText.jl#L136), and pass the flat form on unchanged through `read_intent(…, op::Operation) = op` ([FilteredTextToText.jl:151](../../../source/platform/text/FilteredTextToText.jl#L151), [HighlightedTextToText.jl:277](../../../source/platform/text/HighlightedTextToText.jl#L277)). The caret has the same split: three accepted forms, read by `_text_flat_selection` ([TextDocument.jl:982](../../../source/platform/text/TextDocument.jl#L982)). The place of the lowering depends on the backend: `TextToGraphics` in a window, `SyntaxCompoundToText` in the console ([SyntaxToText.jl:1493](../../../source/platform/syntax/SyntaxToText.jl#L1493)).
- **Example:**

  ```julia
  # Today: each text stage writes the readers of both forms by hand.
  read_intent(p::FilteredTextToText, iomap, op::ReplacePathOperation)        = ...  # caret
  read_intent(p::FilteredTextToText, iomap, op::ReplaceStringRangeOperation) = ...  # lowered edit, remaps the line
  read_intent(::FilteredTextToText, iomap, op::Operation) = op                      # flat edit: passed on as it is
  read_intent(::FilteredTextToText, iomap, evt::Union{KeyPress, KeyDown})    = ...  # read the key against the input
  read_intent(::FilteredTextToText, iomap, op::Union{ReplaceReferencedValueOperation, CompoundOperation}) = ...

  # After: a stage states its two maps. The default reader of the kernel moves a caret,
  # a range and an edit of a range through them.
  map_reference_forward(p::FilteredTextToText, iomap, reference)  = ...
  map_reference_backward(p::FilteredTextToText, iomap, reference) = ...
  ```
- **Problem:** The lowered form can not name a range across two runs, so `_lower_text_range` answers `nothing` there ([TextDocument.jl:2154](../../../source/platform/text/TextDocument.jl#L2154)); `text.md` lists the result as a limit: Ctrl+Backspace over a word that two runs hold does nothing. A stage that drops lines, such as the filter, remaps the lowered form but not the flat form, so by my reading an Enter in a filtered text is applied at the offset of the output (not run, read only). The check found the same in a product view: `TextFolding`, which the Julia file view uses, returns a flat edit unchanged through its last method ([TextFolding.jl:336](../../../source/platform/text/TextFolding.jl#L336)), though a closed fold above the caret moves the offsets. Every new text stage must write five reader methods and decide for each form. `MarkedTextToText` shows the simple shape already: one reader for every range edit, through `get_flat_range` ([MarkedTextToText.jl:223](../../../source/platform/text/MarkedTextToText.jl#L223)).
- **Proposal:** Keep one form on the way back: the flat range. No stage lowers. Each stage maps the range with `map_reference_backward`, and the default reader of the kernel ([ProjectionDefaults.jl:139](../../../source/kernel/projection/ProjectionDefaults.jl#L139)) retargets the operation, as it does today for an edit of a break through `retarget_operation` ([TextDocument.jl:2006](../../../source/platform/text/TextDocument.jl#L2006)). The stage whose input holds the string turns the range into `field{s:e}`. `ReplaceStringRangeOperation` on a field that holds a `TextBlock` already edits a flat range of it (`splice_value!`, [TextDocument.jl:810](../../../source/platform/text/TextDocument.jl#L810)), so the two operation types can become one whose reference says what it edits. The canonical caret stays the flat offset; the structural form stays only for a reference to a run as an object.
- **What goes away:** `_lower_text_range`, `_lower_unless_line_edit`, `_flat_span_range_start`, `_flat_span_range_end`, `_flat_to_span_nearest`, `_find_text_run_line`, `_text_replace_path` (about 150 lines of `TextDocument.jl`); the `ReplaceStringRangeOperation` readers of five decorators and two of the four edit readers of `SyntaxToText.jl` (about 150 lines); about 19 of the 33 reader methods of the decorators (the 5 readers of the lowered form, the 6 path readers and the 8 pass-on methods), and the 6 key readers and the 7 declines of an element write become one each; the structural caret form in `get_flat_caret` and `_parse_selection_range` (the kernel range right on a block stays: a holder of a block hands a caret down so, [TextDocument.jl:987](../../../source/platform/text/TextDocument.jl#L987)); the limit on an edit across two runs of a text block.
- **What stays:** Every key and every edit. The rule that a value wins over its delimiter at a seam stays, in the backward map of `SyntaxLeafToText`, where the caret map has it already. A producer of one line still declines an edit of the lines (`changes_lines`). The number edit (`ReplaceNumberRangeOperation`) stays.
- **Risk and open questions:** The backward map of `SyntaxToText` maps a flat range only when one leaf value holds it; an insert at a seam now uses the selection of the input to choose the field ([SyntaxToText.jl:1447](../../../source/platform/syntax/SyntaxToText.jl#L1447)), and that rule must move into the map. An edit inside one run must still keep the run object, or a line is laid out again for each key. Domains that read `ReplaceStringRangeOperation` at `.value{s:e}` do not change. I did not count the domain readers that read the structural run path.
- **Related plans:** `plan/done/text-range-reference-flat-cursor.md` (done; its design lowered "at the syntax seam", the code lowers in `TextToGraphics`). `plan/done/a-text-span-holds-no-line-break.md` (done; decision N10 keeps an edit of a break flat). `plan/pending/simplest-syntax-document.md` (in progress; its note of 2026-08-12 says the dual accept of the caret "drops" once three sites go flat). No pending plan removes the lowering.
- **Check:** confirmed-with-corrections. Value stays high. I opened every cited place. The counts hold: 33 reader methods in the seven stages, 5 readers of the lowered form, none of the flat form, 4 edit readers in `SyntaxToText.jl`. The lowering has no design reason: the plan `text-range-reference-flat-cursor.md` designed a flat method in each text stage and the lowering at the syntax seam, and built the lowering in `TextToGraphics` as a first version "so the whole existing edit chain carries it up unchanged". N10 and `text.md` say that each stage maps its flat offsets, but `TextFolding`, `FilteredTextToText`, `HighlightedTextToText` and `TextFirstLine` return a flat edit unchanged. Each of them has a backward map, and the default reader of the kernel retargets a flat edit through it, so the change can go stage by stage. Four corrections to the proposal:
  1. **The cost of a key.** The lowering is also the place where the line index of the printer (`iomap.places`) turns a flat offset into the address of a run in log2 of the line count (step 3 of `plan/done/a-gesture-in-a-text-costs-only-the-lines-it-touches.md`). The flat `evaluate_operation` reads every line (`get_flat_offsets`, [TextDocument.jl:1976](../../../source/platform/text/TextDocument.jl#L1976)). With "no stage lowers", a typed character in a large text file would cost every line. The proposal must keep the bound: the stage whose input is the document names the run with its index, or the block keeps an index.
  2. **Two rules live only in the lowered reader of the compound** ([SyntaxToText.jl:1442](../../../source/platform/syntax/SyntaxToText.jl#L1442) to 1489): an insert at a seam reads the selection of the input, and an edit of a separator of a standalone syntax tree writes the one `separator` field. The default reader would decline the separator, because its backward map names an introduced part. Both must move to the flat reader, so `SyntaxToText` keeps hand-written edit readers.
  3. **The caret.** Only the structural form goes. `simplest-syntax-document.md` (note of 2026-08-12) already names that part.
  4. **One operation type in place of two is not needed** for the gain. The done plan chose two types on purpose, and `ReplaceTextRangeOperation` holds `changes_indentation`.

### TS-2 A plain string shown as an editable text is built again in each place

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism), 8 (reuse an existing view: a text goes to the text domain).
- **Today:** Seven places make the lines of a string (inventory I3), and seven write the map between `field{s:e}` of the string and the flat range of the text (inventory I2). `PrimitiveToText.jl` holds four copies of the backward map that differ only in a type name (`_backward_bool`, `_backward_number`, `_backward_string`, `_backward_insertion`, lines 36 to 62 and 182). The tab bar repeats what the text field does: `_print_tab_name_view`, `_find_tab_name_range`, `_map_tab_name_operation` and `_map_tab_name_reference` ([WidgetToGraphics.jl:6122](../../../source/platform/widget/WidgetToGraphics.jl#L6122), 6097, 6759 to 6790). The composer of the chat builds lines with a placeholder by hand ([ConversationEditor.jl:563](../../../source/platform/conversation/ConversationEditor.jl#L563)), though `make_text_block(thunk, style; placeholder, empty_thunk)` does that and keeps unchanged lines. `_make_code_lines` in the widget slice and `_make_marked_line` in the text slice both cut a line into runs from pieces `(count, colour)` ([WidgetToGraphics.jl:2279](../../../source/platform/widget/WidgetToGraphics.jl#L2279), [MarkedTextToText.jl:199](../../../source/platform/text/MarkedTextToText.jl#L199)).
- **Example:**

  ```julia
  # Today, the name of a tab (the text field, the composer and the primitives each have their own copy):
  view = TextBlock(TextLine(TextString(() -> name_of_tab(), style)))
  set_cell_computation!(getfield(view, :selection),
                        () -> make_flat_range_reference(found.start, found.stop; direction = found.direction))
  # ... and back: _map_tab_name_operation (5 methods) and _map_tab_name_reference.

  # After (names are tentative): one projection of the text slice, a row for each holder of a string.
  PrimitiveString => StringFieldToText(:value; theme)
  MarkedText      => StringFieldToText(:text; marks = :marks, theme)
  # A widget prints its own string field through the same code:
  print_string_field(recursion, pane, name_place, ctx; lines = false)
  ```
- **Problem:** A widget that edits a string of its own in place, as the tab bar edits a name, must copy the view, the caret map and the operation map again. A widget that holds a `WidgetText` as a part copies nothing, and the 16 construction sites of inventory I2 do that (the filter field of a column header, the field of the arrangement bar and the text of an outline row are of this kind). The copies differ in small ways: only three of the seven builders keep the object of an unchanged line. The field over an `ObjectField` stores the whole string for each key ([WidgetToGraphics.jl:2759](../../../source/platform/widget/WidgetToGraphics.jl#L2759)) while the field over a plain string edits a range; this difference has a reason, because the value of the slot need not be a string and the slot stores what it parses. The owner said on 2026-11-13, about the read-only text of a label: "we should not reinvent the text domain everywhere".
- **Proposal:** One general projection in the text slice for "the string at this field of the input is a text": it makes the lines (through `make_text_block`, with optional pieces and a placeholder), maps `field{s:e}` to the flat range and back, turns every range edit into an edit of the field (as `MarkedTextToText` does in one method), and declines an edit of the lines when it shows one line. The primitives, the marked text, the text field, the tab name and the composer are rows or calls of it. With TS-1 it needs no reader of its own.
- **What goes away:** the four `_backward_…` functions and the four path readers in `PrimitiveToText.jl` (about 60 lines; the edit readers of the number and of the type-in already call the default reader of the kernel and add the type-in, so they stay); `_get_plain_text_caret`, `_map_plain_text_reference`, `_strip_text_view_step` and the tab name functions in `WidgetToGraphics.jl` (about 130 lines); the plain `_editable_body` of the composer (9 lines; `_map_body_to_value` also serves the body of a kind chooser, whose value is one run before a hint, so it stays); `_make_code_lines`; the hand-written `PrimitiveToSyntax.jl` readers can follow the same shape through the `bound` marker that JSON uses.
- **What stays:** Every field, the placeholder, the colours of a code field, the type-in of a number, the one-line rule, and the read-only text of a label (`DrawnTextLine`), which the owner decided is no text view.
- **Risk and open questions:** The projection needs a per-print style from the context (`:text_style` exists for this) and must not be built per print (settled decision). A string that is no document needs a way to name its holder; the widget passes its own field today, and `ObjectField` is the existing document for "one field of one object".
- **Related plans:** `plan/done/the-window-has-one-system-for-space.md` (done; introduced `TextView`). `plan/pending/views-compose-as-content-composes.md` (later; moves the caret into the view, does not unify these maps). `plan/tentative/search-input-widget.md` (tentative; it is about the later stages of `ProjectionConfiguringProjection` and adds no copy).
- **Check:** confirmed-with-corrections. Value lowered from high to medium. I read `PrimitiveToText.jl` in full, the text field and tab name code of `WidgetToGraphics.jl`, the composer body and `MarkedTextToText.jl`. The repeat is real: `_backward_bool`, `_backward_number` and `_backward_string` differ only in a type name; the tab name repeats the caret map and the operation map of the text field; two functions cut a line into runs from pieces `(count, colour)`. Parts are shared already: `make_text_block`, `get_flat_range`, `make_flat_range_reference`, and the text field makes its lines with `make_text_block`. No plan covers the rest. Corrections, made in the text above: the count of lines that go (about 60 in `PrimitiveToText.jl`, not 120); the next widget copies nothing when it holds a `WidgetText`; the whole-string store of an `ObjectField` has a reason; `_map_body_to_value` stays; the sentence of the owner was about labels; the tentative plan adds no copy. One thing the proposal must keep: `PrimitiveStringToTextBlock` reads the value as a head and a last line in two cells, so an answer that streams changes one run and not the list of lines; `make_text_block` with a function splits the whole string at each change. The shared builder must take the first way. The proposal goes against no settled decision: the projection is a leaf, and its style comes from the context.

### TS-3 A read-only text of many lines reaches the screen in four ways beside the text domain

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 8 (a text goes to the text domain), 7.
- **Today:** Program output, a log and shown code are drawn (a) as one `WidgetLabel` for each line in a column: the terminal ([TerminalToWidget.jl:71](../../../source/platform/terminal/TerminalToWidget.jl#L71)), the summary of an agent ([AgentWorkToWidget.jl:108](../../../source/platform/assistant/AgentWorkToWidget.jl#L108)) (the facts of a task, [TaskPagesToWidget.jl:268](../../../source/platform/task/TaskPagesToWidget.jl#L268), are also one label for each line, but they are facts with a name and a value and no text: they belong to `WidgetFactGroup`, not to this finding); (b) as a `WidgetTextarea`, an editable widget, with a computed content: the output of a task ([TaskGroupToWidget.jl:869](../../../source/platform/task/TaskGroupToWidget.jl#L869)), the answer of an MCP call ([McpLogToWidget.jl:80](../../../source/platform/mcplog/McpLogToWidget.jl#L80)); (c) as one editable `WidgetText` for each line of code ([McpLogToWidget.jl:74](../../../source/platform/mcplog/McpLogToWidget.jl#L74)); (d) as a `WidgetTable` of a number label and a text label for each row, with its own window of rows and its own scroll bar ([TaskPagesToWidget.jl:405](../../../source/platform/task/TaskPagesToWidget.jl#L405)). The git domain shows the way of the text domain: a `TextBlock` with `TextLineNumbering` in a scroll pane ([GitToWidget.jl:555](../../../source/domain/git/GitToWidget.jl#L555)), after the owner asked for it.
- **Example:**

  ```julia
  # Today (terminal): a label for each line.
  Cell[Cell(WidgetLabel(line.text; text_style = style_of(line.kind))) for line in terminal.lines]

  # After: one text of lines; a line in the colour of its kind; the scroll pane follows the end.
  TextBlock(() -> TextDocument[TextLine(TextString(line.text, style_of(line.kind))) for line in terminal.lines])
  ```
- **Problem:** With labels, a range can not cross two lines, a copy takes one line, and there is no line number, no fold and no find. With a text area, a view that only shows is an edit widget. Each way lays out every line as a widget. The stream table repeats line numbers and lazy rows, which `TextLineNumbering` and a lazy list of lines exist for.
- **Proposal:** One read-only text view of lines from the text slice: a `TextBlock` (made by `make_text_block`, grown by `append_text!`), shown by the text chain, with numbers when asked (see TS-4). "Read only" is a look of one showing, so it can be a field of `TextView`, beside `wrap` and `line_spacing`, and the view declines edits in one place.
- **What goes away:** the label lists, the computed text areas, the text field for each code line, and the stream table with its own scroll bar (about 150 lines in four slices).
- **What stays:** the colour of a line by its kind, the follow of the end, the mark of the found line, and lazy reading of a long stream (this needs the lazy list path, see TS-8).
- **Risk and open questions:** The stream of a task can be very long; today only `TextToGraphics` is lazy over a `ListNode`, and numbering is not. Whether `TextView` is the right holder of "read only" is the owner's call.
- **Related plans:** none found. Other areas: terminal, task, mcplog, assistant.
- **Check:** confirmed-with-corrections. Value stays medium. I opened the eight cited places; each shows what the finding says, and no design document gives a reason for a label for each line (`terminal.md` and `task.md` only describe it). No plan covers it. Principle 8 names the case. Three corrections:
  1. **The facts of a task are no text** (corrected above). Four places remain: the terminal, the summary of an agent, the MCP log and the output box of a task.
  2. **"Read only" needs no new field of `TextView`.** The git view shows the existing way: its stage from the document to the text declines every range edit (`read_intent(::GitTextToText, ::SimpleIoMap, ::ReplaceRangeOperation) = nothing`, [GitToWidget.jl:203](../../../source/domain/git/GitToWidget.jl#L203)). A text widget with `enabled = false` is no answer, because it takes no press and no key, so it gives no selection and no copy.
  3. **The stream table can not move yet.** It reads a file of up to a million lines, shows only the rows that fit, filters its rows (`filter_text`) and marks the found line. A text of a `CellVector` of lines would hold every line, and a text of a lazy list has no caret, no number and no filter (TS-8). So the stream table stays until the lazy list of lines is decided; the proposal would lose its cost bound.

### TS-4 The view of code is a chain that each package assembles by hand

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 2 (a general step works for every domain), 7.
- **Today:** Three packages build the same tail: `TextLineNumbering`, optionally `TextFolding`, `TextBlockToScrollLayout`, then a recursion with rows for `UndoBuffer`, `TextGutter`, `TextBlock` and `GraphicsCanvas`: [JuliaModule.jl:93](../../../source/domain/julia/JuliaModule.jl#L93), [LanguageServerDocument.jl:238](../../../source/adapter/languageserver/LanguageServerDocument.jl#L238), [GitToWidget.jl:555](../../../source/domain/git/GitToWidget.jl#L555). A search for `TextLineNumbering`, `TextFolding` and `TextBlockToScrollLayout` outside the text slice finds only these three. Every other domain with a syntax form (JSON, XML, YAML, SQL, Markdown source, a plain text file) shows through the fallback fabric, `SyntaxToText` then `TextToGraphics` ([SyntaxNatural.jl:116](../../../source/platform/syntax/SyntaxNatural.jl#L116)), with no number, no text fold and no gutter.
- **Example:**

  ```julia
  # Today, in each package (15 lines):
  code = ChainingProjection(RecursiveProjection(JuliaToSyntax(…)), RecursiveProjection(SyntaxToText(; text_folds = true)),
                            TextLineNumbering(; theme), TextFolding(; theme), TextBlockToScrollLayout(; measure, theme, line_spacing))
  RecursiveProjection(TypeDispatchingProjection(UndoBuffer => UndoBufferToAnyProjection(), JuliaDocument => code,
      TextGutter => TextGutterToGraphics(), TextBlock => TextToGraphics(; measure, theme), GraphicsCanvas => GraphicsToGraphics()))

  # After: the text slice gives the tail once (name tentative).
  make_code_view_projection(JuliaToSyntax(…); measure, appearance, folds = true)
  ```
- **Problem:** Numbers, folds and the gutter are general steps, but a domain gets them only when its package copies the chain. A change of the chain (a new lane, a new row) must be made three times.
- **Proposal:** The text slice gives one builder of the code view from the stages before the text. The fabric of the natural renderer uses it for a code file of any domain whose rung is `:syntax`, so a file tab of JSON or SQL shows as a Julia file does.
- **What goes away:** the three hand-made chains (about 45 lines), and the difference between domains.
- **What stays:** the Julia, source file and git views as they are; a domain still gives its own first stages and its own gutter labels.
- **Risk and open questions:** Text folds need `text_folds = true` in `SyntaxToText` and a collapsible compound; JSON and XML pass no `collapsed` yet (`collapse-expand-syntax-nodes.md`). Whether every code tab should show numbers is a product choice.
- **Related plans:** `plan/pending/a-text-has-a-gutter-beside-its-lines.md` (in progress; its step 6 covers the Julia view only). `plan/pending/collapse-expand-syntax-nodes.md` (pending).
- **Check:** confirmed-with-corrections. Value lowered from medium to low. The three chains are as cited, and a search finds `TextLineNumbering(`, `TextFolding(` and `TextBlockToScrollLayout(` outside the text slice only in these three files; `omnet-julia` and `inet-julia` hold no copy. The finding has two parts of different weight:
  1. **One builder for the tail.** It holds and loses nothing, but it is small: the chains differ in their first stages and in their options (Julia has folds; git numbers only a file text, and has no row for a history), so the builder saves about 30 lines and gives one place for a new lane.
  2. **Numbers and a gutter for the file tab of every syntax domain.** This is a new feature and a product choice, which the review does not ask for. The owner decided the reach of the Julia view on 2026-10-08 (step 6 of the gutter plan: only the code of a Julia file in its tab, because numbers on a snippet say nothing); no decision gives numbers to a JSON or SQL tab. A file reaches its code view through a method of `make_graphics_projection` for its file type (`JuliaFile`, `SourceFile`); the other domains have a file type too (`JsonFile`, `XmlFile`, `YamlFile`, `SqlFile`) and draw through the general row `FileDocument => FileToContent()`, so the change for them is small once the builder exists, but it stays a choice of the owner.

### TS-5 Coloured ranges of a text have three shapes and two splitters

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7, 5 (the widget slice should not own a rule of a language).
- **Today:** `HighlightedText` colours the background of each match of a pattern in any text. `MarkedText`, added on 2026-10-21, colours the glyphs of given ranges (`TextMark`) of a string. A code field colours its string by `compute_code_pieces(Val(language), text, appearance)`, a function of the widget slice that the Julia domain extends ([WidgetDocument.jl:294](../../../source/platform/widget/WidgetDocument.jl#L294), [JuliaCodePieces.jl:39](../../../source/domain/julia/JuliaCodePieces.jl#L39)). Marks and pieces end in the same value, `(count, colour)` for each line, cut into runs by two functions (see TS-2). A pattern can not be given to a `MarkedText`, and marks can not be given to a `TextBlock`.
- **Example:**

  ```julia
  # Today: three shapes.
  HighlightedText(text = block, pattern = "dolor")                               # background of a match
  MarkedText(text = source, marks = [TextMark(4, 8; text = ColorRole(:function_name))])
  compute_code_pieces(::Val{:julia}, text, appearance) = [(3, keyword_color), (1, nothing)]

  # After: one list of marks on a text, whoever computes them.
  TextMark(start, stop; text, surface, underline)       # as D1 of the pending plan
  compute_code_marks(::Val{:julia}, text)               # a language gives marks, in the text slice
  ```
- **Problem:** A domain that wants an error mark in a text that a person edits has to choose a document type by where its ranges come from. A match of a find over a marked text needs a wrapper around a wrapper.
- **Proposal:** One range type (`TextMark` with a glyph colour, a surface and an underline) and one split, as `a-highlighted-text-marks-given-ranges.md` designs. A pattern gives marks with a surface; a language gives marks; a server gives marks. The marks belong to the view of the text, so they work on a string and on a block.
- **What goes away:** `compute_code_pieces` and `_make_code_lines` in the widget slice, the second splitter of a line into coloured runs, and one of `HighlightedText` and `MarkedText` as a separate concept.
- **What stays:** find highlight, marks of a language server with `compute_moved_text_marks`, the colours of a code field, editing through the split.
- **Risk and open questions:** A pattern is matched in one run today; marks count flat offsets. The plan is deferred by the owner ("not needed right now").
- **Related plans:** `plan/pending/a-highlighted-text-marks-given-ranges.md` (deferred 2026-10-11; its fact 1 says a caller can not give a range, and `MarkedText` came ten days later as a second document, not as the `marks` field the plan decided). `plan/done/a-source-file-takes-its-colours-from-a-language-server.md` did this knowingly: its fact 13 names the deferred plan and says "This plan does not use it: here the projection makes the runs from the string", the owner proposed the shape of `MarkedText` on 2026-10-21, and its section 7 says "A change of `HighlightedText`; the deferred plan stays deferred".
- **Check:** covered-by-plan. Value lowered from medium to low. The facts hold: three shapes (`HighlightedText` with a pattern, `MarkedText` with `TextMark`s, `compute_code_pieces` with pieces) and two functions that cut pieces into runs. But the proposal is the design of `plan/pending/a-highlighted-text-marks-given-ranges.md` (D1 one range type `TextMark(start, stop; text, surface, underline)`, D2 one split for a pattern and for marks), which the owner deferred on 2026-10-11 with "not needed right now". The second document `MarkedText` is no oversight: the owner chose it on 2026-10-21 and left the deferred plan deferred, with the reason that a source file is a string and the projection makes the runs from it. The cited principle 5 does not apply: the widget slice only declares the function `compute_code_pieces`, and the Julia domain owns the rule of its language. What the finding adds to the plan is one note: when the owner takes the plan up, it should also name `MarkedText` and the pieces of a code field, which came after it.

### TS-6 The natural notation keeps eight process-global tables beside the seam that replaces them

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 6 (no global state), settled decision "no process-global registry"; decisions C1 and C7 of `packages-compose-by-seams.md`.
- **Today:** A type says how it shows in two ways. The older way is a registration at load time into module constants: five in [NaturalNotation.jl:9](../../../source/platform/natural/NaturalNotation.jl#L9) and three in [NaturalRegistry.jl:38](../../../source/platform/natural/NaturalRegistry.jl#L38), filled by 45 calls of nine `register_natural_…!` functions (`register_natural_domain!` calls four of the others). The newer way is a method of `make_graphics_projection(::Type{T}; measure, appearance)`, with 35 methods; `NaturalToGraphics` reads the method table and puts these rows before the registered ones ([NaturalProjection.jl:184](../../../source/platform/natural/NaturalProjection.jl#L184)).
- **Example:**

  ```julia
  # Today: a registration in __init__ (JSON), and a seam method (git) for the same question.
  register_natural_domain!(JsonDocument; rung = :syntax, make = (; appearance) -> JsonToSyntax(),
                           format = :json, extension = ".json", parse = parse_json)
  make_graphics_projection(::Type{<:GitCommit}; measure, appearance) = …

  # After (names tentative): methods only.
  make_syntax_projection(::Type{<:JsonDocument}; appearance) = JsonToSyntax(…)
  get_natural_format(::Type{<:JsonDocument}) = (:json, ".json")
  parse_natural_text(::Val{:json}, text) = parse_json(text)
  ```
- **Problem:** Two precedence rules live in one table build: seam rows, then factory rows, then rung rows. A test that registers a type must put the tables back by hand (`natural.md`, Tests). The tables hold factories and not projections, so two editors do not share state through them, but they are still the registry form that the owner ruled out.
- **Proposal:** Finish decision C7: each of the register functions becomes a seam, a generic function that the owner of the type adds a method to. The ladder (`:syntax → :text → :graphics`, `:string`) stays as code of the natural slice that calls the seams.
- **What goes away:** the eight constants, the nine register functions and their idempotence keys, the registration calls in 34 files, and the order rule between seam rows and registered rows.
- **What stays:** `make_natural_projection`, `print_natural_text`, `parse_natural_text`, `NaturalToGraphics` with `extra`, and "what is not loaded is not supported".
- **Risk and open questions:** A parser keyed by a format with no type (`:yml`) and a fallback that covers `Any` need a seam shape of their own. A method added by a package can overwrite one of a lower package (seen once with a platform type, by the notes of the project).
- **Related plans:** `plan/pending/packages-compose-by-seams.md` (design; C7 says "a later plan moves the other eight natural register functions to seams"; I found no such plan).
- **Check:** covered-by-plan. Value lowered from medium to low, because the owner decided this already. The facts hold: eight constants (five in `NaturalNotation.jl`, three in `NaturalRegistry.jl`), nine register functions, 45 call lines in 34 files outside the two defining files, 35 methods of `make_graphics_projection(::Type…)`, and the seam rows before the registered rows in the table build ([NaturalProjection.jl:184](../../../source/platform/natural/NaturalProjection.jl#L184)). The proposal is decision C1 ("Seams only. No registry table, no `__init__` registration") with C7 ("The natural tables stay for now … A later plan moves the other eight natural register functions to seams") of `plan/pending/packages-compose-by-seams.md`, both by the owner on 2026-09-30. So there is nothing new to decide; what is open is only that the later plan is not written. The finding is useful as the inventory for that plan, and its two open points are right: a parser keyed by a format with no type, and a fallback for `Any`, need a seam shape of their own.

### TS-7 Find and filter of a text are a second mechanism, and no product view of this repository uses it

- **Kind:** redundant · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 7; the owner's sentence in `filter-sort-and-find-any-table.md`: "A filter is a filter, any collection can be filtered".
- **Today:** The text slice has `FilteredText` (keep the lines that match a pattern), `HighlightedText` (mark the matches) and `make_text_pattern`; the widget slice has `FindBarView` with its Ctrl+F rule ([FindBarViewGestures.jl:96](../../../source/platform/widget/FindBarViewGestures.jl#L96)). In `source/` of this repository, nothing constructs `FindBarView`, `FilteredText` or `HighlightedText`; only examples, tests and one docstring do. Outside it, `omnet-julia` uses `FindBarView` in a product view: `LegacyResultTableViewToFindBarView` puts the filter bar of a result table above the table (`omnet-julia/source/legacy/result/presentation/LegacyResultViewToDocument.jl:114`). `FindBarView` holds any `content` and a `bar` that the caller builds, so it is no part of the text find. The application binds Ctrl+F to the general arrangement, "Find in the collection that holds the selection" ([PaneGestures.jl:194](../../../source/platform/pane/PaneGestures.jl#L194)). The arrangement has its own filter language ([FilterLanguage.jl](../../../source/platform/arrangement/FilterLanguage.jl)) and a general stage that picks items of a collection by index, `PickingProjection` ([Picking.jl:25](../../../source/platform/arrangement/Picking.jl#L25)). The lines of a `TextBlock` are a collection.
- **Example:**

  ```julia
  # Today (only in example/ and test/): a document type for each of grep and highlight, and a bar view.
  FindBarView(; bar, content = FilteredText(text = HighlightedText(text = block, pattern = "dolor"), pattern = "dolor"))

  # After: the lines of a text are a collection that the arrangement filters; the matches are marks (TS-5).
  filter_collection!(@reference(elements), "dolor")     # the same verb as for a table
  ```
- **Problem:** Two pattern languages, two bars, two sets of fields (`pattern`, `regex`, `case_insensitive`, `invert` against the conditions of the arrangement). A person gets the text find only where an example wires it.
- **Proposal:** A text is one more collection for the arrangement. The text slice adds what is its own: the map of flat offsets over dropped lines (it has the helper, `_make_flat_runs`), and marks for the matches. The special documents and the special bar go.
- **What goes away:** `FilteredText`, `FilteredTextToText`, `HighlightedText` as a document of its own, `FindBarView`, `FindBarViewToWidget`, `FindBarViewGestures` (about 700 lines), and `make_text_pattern` if the filter language takes regular expressions.
- **What stays:** grep of lines, highlight of all matches, a caret that maps through a filtered text, Ctrl+F and Escape.
- **Risk and open questions:** I did not check whether the arrangement finds the `elements` of a `TextBlock` as a collection today, nor whether its find can mark matches inside an item. This finding reaches into the arrangement and widget areas.
- **Related plans:** `plan/pending/filter-sort-and-find-any-table.md` (pending), `plan/pending/fix-text-configuring-run-example.md` (pending; about the example switches of the text filter).
- **Check:** weakened. Value lowered from medium to low. What holds: in this repository only examples and tests construct `FilteredText` and `HighlightedText`, the application binds Ctrl+F to the arrangement, and the text filter has its own fields beside the filter language of the arrangement. What does not hold:
  1. **A product view uses `FindBarView`** (corrected above). The proposal would remove a view that `omnet-julia` shows, and that works on any content, so `FindBarView`, `FindBarViewToWidget` and `FindBarViewGestures` (267 of the 764 lines) must stay.
  2. **The text code does not go, it moves.** The map of flat offsets over dropped lines (the body of `FilteredTextToText`) and the split of a run at a match (the body of `HighlightedTextToText`) stay in the text slice under any design. What can go is the two document types with their four fields, about 100 lines.
  3. **The base of the proposal is not checked.** The finding says so itself. I looked: the arrangement slice names no `TextBlock` and no `TextLine`, and its find moves the selection to the next item; it marks nothing inside an item. So "a text is one more collection" needs new code in the arrangement and a text printer for picked lines.
  The direction is the owner's: section 3 of `plan/pending/filter-sort-and-find-any-table.md` (decided 2026-10-07) lists "the lines of a text" as a kind of collection, "as `TextFiltering` does". That plan has no step for a text. So what is left of the finding is one line for that plan: add a step for the lines of a text, and retire the two document types when it lands.

### TS-8 A text whose lines are a lazy list is a second, weaker path

- **Kind:** partial-feature · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** 1 (lazy and incremental), 7. Touches the settled decision on lazy lists (one generic solution, counted from the head), which is still open in its design.
- **Today:** `TextBlock.elements` is a `CellVector` or a lazy `ListNode`. `TextToGraphics` has a separate printer for the list ([TextToGraphics.jl:1427](../../../source/platform/text/TextToGraphics.jl#L1427)) whose IO map holds no segments. On a list: no key is read ([TextDocument.jl:2115](../../../source/platform/text/TextDocument.jl#L2115)), no key moves along the lines ([TextToGraphics.jl:506](../../../source/platform/text/TextToGraphics.jl#L506)), the list path puts no caret at a point (`text.md`, Layout), Ctrl+A, Tab and Shift+Tab decline ([TextDocument.jl:1290](../../../source/platform/text/TextDocument.jl#L1290)), and there is no gutter (`text.md`, Limits). The decorators (`WordWrapping`, `TextLineNumbering`, `TextFolding`, the filter, the highlight) iterate `text.elements` and build a `CellVector`; none names `ListNode`.
- **Example:**

  ```julia
  # Today: the same text gives a different set of features by the type of its list.
  TextBlock(CellVector(lines))   # caret, range, keys, numbers, folds, gutter
  TextBlock(list_node_of_lines)  # drawn only

  # After: every text stage reads the lines through one interface of a collection of lines
  # (count from the head, item at an index, sums of aligned blocks), so a stage is lazy by default.
  ```
- **Problem:** A long text (a stream of output, a log, a reflected value) is exactly where a lazy list is needed and exactly where a person wants a caret, a range to copy and line numbers. A view that needs both has to leave the text domain (see the stream table in TS-3).
- **Proposal:** One access interface for the lines of a text that both list types answer, and the text stages written against it. The places of lines are already sums of aligned blocks (`PlaceBlocks`) on the `CellVector` path; the lazy path needs the same sums counted from its head.
- **What goes away:** the second printer and the second forward map in `TextToGraphics.jl` (about 170 lines), and the `isa ListNode` branches.
- **What stays:** lazy drawing of an endless list; a caret in a list counts from the head.
- **Risk and open questions:** A flat offset over an endless list has no total; Ctrl+End and Ctrl+A need a rule. The owner has not chosen the generic memory solution for lists.
- **Related plans:** `plan/tentative/the-text-of-a-syntax-tree-costs-its-lines-not-its-depth.md` (tentative; about memory, not about this path). `plan/pending/syntax-tree-selection.md`, section 2 (open): the list path draws no caret and no band, and needs the same layer as the other path. `plan/pending/text-domain-kit.md`, Q3 (decided by the owner and built, 2026-10-08): a lazy text is a lazy list of lines, counted from the head; its gutter is named there as a later step.
- **Check:** weakened. Value lowered from medium to low. The facts hold: five `isa ListNode` returns in the text slice (TextDocument.jl:1290, 1321, 1346, 2115; TextToGraphics.jl:506), a printer of its own for the list, and no decorator that names `ListNode`. But the difference has a stated reason, and the proposal waits for a decision that is not made:
  1. **The reason.** The canonical caret is a flat offset over the whole block (decided, `text-range-reference-flat-cursor.md`). The source says why a list reads no key: "the list can be endless, so it has no end to go to, and a flat offset would walk it" ([TextDocument.jl:2103](../../../source/platform/text/TextDocument.jl#L2103)). The list path maps a place by line, run and character from the head. So "the same sums counted from its head" is no small step: it needs a caret form for a text with no total, which the finding lists only as a risk.
  2. **The decision.** The owner settled that every list gets one generic solution for its memory and has not chosen it. An interface for "the lines of a text" that the text stages are written against would be a solution for one kind of list before that choice.
  3. **A part is planned.** The caret and the band on the list path are the open section 2 of `syntax-tree-selection.md`.
  Today only a lazy collection printed as syntax (`SyntaxListToText`) gives such a text. The stream table of a task (TS-3) is the one view that would gain, and it works today. So the finding is right as a description of a limit and is no proposal that can start now.

### TS-9 The wrap and the cut of a drawn string repeat the word wrap, and find line starts by search

- **Kind:** several-ways · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 7.
- **Today:** `_text_lines` breaks a string of a widget greedily at spaces and returns strings ([WidgetToGraphics.jl:1293](../../../source/platform/widget/WidgetToGraphics.jl#L1293)). `_compute_soft_breaks` of `WordWrapping` breaks a line greedily at spaces and returns offsets ([WordWrapping.jl:107](../../../source/platform/text/WordWrapping.jl#L107)). The two differ: the widget drops the space at a break, the text keeps it. Because the widget wrap returns strings, `_find_line_starts` searches each drawn line in the text again to learn where it starts ([DrawnTextLine.jl:25](../../../source/platform/widget/DrawnTextLine.jl#L25)). The caret of a drawn string is 2 pixels wide in the colour of the text ([DrawnTextLine.jl:380](../../../source/platform/widget/DrawnTextLine.jl#L380)); the caret of a text comes from the `TextTheme`.
- **Example:**

  ```julia
  lines  = _text_lines(measure, font, text, bound)   # today: Vector{String}
  starts = _find_line_starts(text, lines)            # found again by search

  breaks = compute_soft_breaks(measure, font, text, bound)   # after: offsets, shared with WordWrapping
  ```
- **Problem:** Two break rules can give different rows for the same string in a label and in a field. The line starts are found by a search only because the wrap returns strings and not offsets.
- **Proposal:** One pure function of the style slice that gives the break offsets of a string in a font at a width. `WordWrapping` calls it for each run; the widget draws the rows between the offsets and records them. The caret width and the band of a drawn string read the `TextTheme`.
- **What goes away:** `_text_lines`, `_find_line_starts` (about 40 lines), and the second break rule.
- **What stays:** the "…" cut after `max_lines`, the read-only behaviour, the decision that a label is no text view.
- **Risk and open questions:** A change of the break rule moves pixels in the images of the tests.
- **Related plans:** `plan/pending/word-wrapping-projection.md` (remaining tests only).
- **Check:** confirmed. Value stays low. I read `_text_lines`, `_push_text_block!`, `_limit_text_lines`, `_compute_soft_breaks` and `_find_line_starts`. Both wraps break before a word that would pass the width; the widget returns strings and drops the space, the text returns offsets and keeps it. `_find_line_starts` finds each drawn line in the text again with `findnext`. The comment above `_text_lines` gives a reason only against the projection `WordWrapping` ("a `String` in a widget field is not a `TextDocument`"); a pure function of break offsets needs no document, so the reason does not stand against the proposal. The plan of the drawn text (`plan/done/a-text-that-a-widget-draws-is-read-like-a-text.md`) gives no reason for the search. Two notes for the one who builds it: the two wraps measure in different ways (the widget measures the whole candidate row, the text adds the widths of the words), so one rule moves pixels on one side; and the caret of a drawn string is the literal `2`, while `caret_width` of the `TextTheme` is a `LineWidth(2)` that scales, so the two carets differ at a zoom. Nothing is lost: the "…" cut works on rows, whatever gives the rows.

### TS-10 Concepts of the area that no code uses

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** 11 (design as if written today).
- **Today:** No code in `source/` or `example/` constructs `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxInsertion`, `TextFirstLine` or `TextColumnReferenceStep`; tests do. `SyntaxLeaf` has the fields `indentation` and `collapsed` ([SyntaxDocument.jl:475](../../../source/platform/syntax/SyntaxDocument.jl#L475)) that `SyntaxLeafToText` does not read. `TextSpacing` has no user in `source/`. Each of these has a reference map, a reader or a branch in the flat offset code.
- **Example:** `TextFirstLine` is 93 lines with its own IO map and four readers, and `text.md` says "No code in `source/` or `example/` uses `TextFirstLine`".
- **Problem:** Each unused type is one more case in every walk of the tree and of the flat offsets, and one more thing a new stage must handle.
- **Proposal:** Remove what no feature needs, or give it its user: drop `TextColumnReferenceStep`, `TextFirstLine`, the two leaf fields and `SyntaxInsertion`; keep the two wrappers only if the domain sweep of the syntax plan will use them.
- **What goes away:** about 250 lines and their tests.
- **What stays:** every shown feature. A column selection would be a new feature and can bring its step back.
- **Risk and open questions:** `simplest-syntax-document.md` decided that the wrappers coexist with `SyntaxNode` for good; removing two of them goes against the letter of that plan, so the owner decides.
- **Related plans:** `plan/pending/simplest-syntax-document.md` (in progress; phase 2.8 covers `SyntaxInsertion`). `plan/done/text-selection-variants.md` (done; its step T3 reserved `TextColumnReferenceStep` on purpose, with the column render deferred).
- **Check:** weakened. Value stays low. The counts hold: a search finds a construction of `SyntaxIndentation`, `SyntaxCollapsible`, `TextFirstLine` and `TextColumnReferenceStep` only in their own files and in tests, and none of `SyntaxInsertion` anywhere; `omnet-julia` and `inet-julia` use none of them. But four of the six things that the proposal drops are kept on purpose by a plan:
  - `SyntaxIndentation` and `SyntaxCollapsible`: `simplest-syntax-document.md` decided that the wrappers stay beside `SyntaxNode`, and its domain sweep (done for Julia, SQL, Markdown and XML, open for the others) is their user. `SyntaxToText` has their rows (SyntaxToText.jl:1760).
  - `SyntaxInsertion`: phase 2.8 of the same plan, not built yet.
  - `TextColumnReferenceStep`: reserved by step T3 of `text-selection-variants.md`.
  `TextSpacing` is no unused concept: it is a run type of the text model, the text example holds one, and the atomic catalog has a document for it (`example/platform/TextDocumentExample.jl:69` and 101). What is left without a plan: `TextFirstLine` (93 lines; `text.md` lists it under Limits as unused) and the fields `indentation` and `collapsed` of `SyntaxLeaf`, which no printer reads. That is about 100 lines, not 250.

## Covered by plans

- `simplest-syntax-document.md`: the two models of a syntax compound (`SyntaxNode` and the wrappers) coexist by decision; the empty delimiters that domains still pass (the entry nodes of JSON and YAML) belong to its domain sweep.
- `text-domain-kit.md`: `SyntaxToText` emits `TextLine`s. `syntax.md` describes this as done; the status line of the plan is older.
- `views-compose-as-content-composes.md`: the selection, the fold state and the caret move from content documents into view documents, the text view first.
- `word-wrap-for-each-paragraph.md`: stale. Its problem (one wrap cell for a block, `TextNewline`) no longer matches the code: each line has its own cell of soft breaks ([WordWrapping.jl:84](../../../source/platform/text/WordWrapping.jl#L84)).
- `word-wrapping-projection.md`: remaining tests of the wrap.
- `a-highlighted-text-marks-given-ranges.md`: one range type and one split; deferred and partly overtaken (TS-5).
- `a-text-has-a-gutter-beside-its-lines.md`: the gutter model and the Julia view; markers are open.
- `line-spacing-from-the-theme.md`: the code reads `:code_line_spacing` and `:prose_line_spacing` of the text theme ([SyntaxNatural.jl:88](../../../source/platform/syntax/SyntaxNatural.jl#L88)); the plan file waits for its parent plan.
- `the-text-of-a-syntax-tree-costs-its-lines-not-its-depth.md` (tentative): each compound keeps the lines of its subtree.
- `left-motion-stalls-on-introduced-text.md`: the left walk in four examples.
- `collapse-expand-syntax-nodes.md`, `syntax-tree-selection.md`, `julia-syntax-navigation.md`: fold state in JSON and XML, a range of siblings, tree navigation.
- `packages-compose-by-seams.md`: decision C7 on the natural tables (TS-6 asks for the plan that C7 names).
- `fix-text-configuring-run-example.md`, `xml-to-syntax-reference-parity.md`: local to an example and to XML.

## Examined and sound

- One `TextMeasure` (`compute_text_extent`, `compute_line_box`, `compute_caret_offsets`) serves `TextToGraphics`, `WordWrapping` and every widget: the measure is shared.
- One key table for every text ([TextDocument.jl:874](../../../source/platform/text/TextDocument.jl#L874)); the geometry keys are in `TextToGraphics` only. The split by what a reader reads is right.
- The read-only text of a widget is written once (`DrawnTextLine.jl`) and borrows the key table; this follows the owner's decision that a label is no text view.
- `TextView` holds the look of one showing (wrap, line spacing); the owner accepted it on 2026-11-05, and a table of rules can not give a look to one text.
- A caret and a box are two step types with the same data; a motion key moves only the caret. The reason in `text.md` holds.
- The wrap is a stage of its own and a value of the line (`soft_breaks`), so the list of lines does not depend on the width.
- `SyntaxCompoundToText` prints one level and joins the lines of its children; the compound contract (five functions) lets every compound share it.
- The text decorators share one rule (no character changes) and the flat run helpers (`_make_flat_runs`, `_map_flat_over_runs`).
- `InsertionToSyntaxLeaf` and `InsertionNothingToSyntaxLeaf` are shared by every domain; a domain passes only its policy.
- `JsonToSyntax` is declarative through `@projection_template`; it repeats little.
- The ladder of the natural notation composes existing projections and adds no printer or reader.
- Three ways to draw a value of no domain (reflected syntax, a form, a bounded tree) have different costs, and `reflection.md` states the choice.
- A parser for each format beside its printer: a saved file is the print of the tree, and a load is a parse; the two small character cursors of JSON and XML are local.
- `LetterMatch.jl` is pure string code in the widget slice; two other slices use it; a move would be tidiness only.

## Check of the report

A second agent tried to refute each finding at commit 3a9b4fae4: it opened the cited files, counted again, and read the plans and the design documents that name the same code. It ran no code. Each finding has a list item **Check** with what was read and what was corrected. Wrong facts are corrected where they stood.

| Id | Verdict | Value in the report | Value after the check | The main reason |
| --- | --- | --- | --- | --- |
| TS-1 | confirmed-with-corrections | high | high | Two forms of one edit are real, and four stages do not map the flat form, one of them in the Julia file view. The proposal must keep the cost of a key (the line index of the printer) and two rules of the lowered reader of the compound. |
| TS-2 | confirmed-with-corrections | high | medium | The repeat is real but smaller: about 220 lines in four places, and a widget that holds a `WidgetText` copies nothing. |
| TS-3 | confirmed-with-corrections | medium | medium | Four places draw program output outside the text domain. The facts of a task are no text; the stream table can not move before the lazy list of lines is decided; "read only" exists already as a stage that declines edits. |
| TS-4 | confirmed-with-corrections | medium | low | The builder saves about 30 lines. Numbers for every syntax file tab are a new feature and a choice of the owner. |
| TS-5 | covered-by-plan | medium | low | `a-highlighted-text-marks-given-ranges.md`, deferred by the owner; the owner chose `MarkedText` as a second document on 2026-10-21 and left that plan deferred. |
| TS-6 | covered-by-plan | medium | low | Decisions C1 and C7 of `packages-compose-by-seams.md`; only the later plan that C7 names is not written. |
| TS-7 | weakened | medium | low | `omnet-julia` shows a `FindBarView`; the text code moves and does not go; the arrangement has no text collection today. The direction is in section 3 of `filter-sort-and-find-any-table.md`, with no step. |
| TS-8 | weakened | medium | low | The limit has a stated reason (a flat offset over an endless list), and the proposal waits for the open decision on the memory of lazy lists. |
| TS-9 | confirmed | low | low | Two greedy wraps and a search for line starts; a pure function of break offsets joins them. |
| TS-10 | weakened | low | low | Four of the six things are kept on purpose by a plan. `TextFirstLine` and two fields of `SyntaxLeaf` are left, about 100 lines. |

Seen during the check and not in the report:

- The flat `evaluate_operation` of a text edit reads every line of the block for each Enter and each paste with a break (`get_flat_offsets`, `source/platform/text/TextDocument.jl:1976`), while a typed character costs log2 of the line count. A block has no line index of its own.
- `TextFolding` returns a flat edit unchanged (`source/platform/text/TextFolding.jl:336`), so an edit of a break below a closed fold in the Julia file view reaches the syntax stage with the offsets of the folded text. Read only, not run. It is part of TS-1.
