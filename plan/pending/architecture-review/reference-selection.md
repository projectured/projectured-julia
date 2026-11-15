# Architecture review: References, selection, focus, clipboard, links

Commit 3a9b4fae4. Reviewer area key: reference-selection.

## Scope

Paths: `source/kernel/reference` (12 files, 4 511 lines), `source/kernel/selection` (3 files, 589 lines),
`source/platform/focus` (7 files, 1 119 lines), `source/platform/clipboard` (6 files, 1 650 lines),
`source/platform/link` (7 files, 905 lines). For use, I also read the two files of the kernel that hold the
other half of the selection model: `source/kernel/operation/PathChain.jl` and
`source/kernel/projection/OutputPaths.jl`.

Read in full, about 5 400 lines of source:

- kernel reference: `ReferenceModule.jl`, `ReferenceInterface.jl`, `ReferenceStep.jl`, `ReferencePath.jl`,
  `ReferenceEvaluation.jl`;
- kernel selection: all three files;
- kernel: `operation/PathChain.jl`, `projection/OutputPaths.jl`;
- focus: all seven files;
- clipboard: `Clipboard.jl`, `ClipboardDocument.jl`, `ClipboardModule.jl`, and `ClipboardSliceToAny.jl` up to
  its reader (about 640 of 740 lines);
- link: `LinkDocument.jl`, `LinkToWidget.jl`;
- the step types of the higher packages: `TextRangeReferenceStep.jl`, `TextSpanReferenceStep.jl`,
  `TextColumnReferenceStep.jl`, `ChartSampleReferenceStep.jl`, `SequenceChartRowReferenceStep.jl`.

Sampled, by outline and by the functions that the findings cite:

- kernel reference: `ReferencedDocument.jl` (only `get_parent`); `ReferenceCase.jl`, `ReferenceRules.jl`,
  `ReferencePatternString.jl`, `ReferenceSyntax.jl`, `ReferenceBuilder.jl`, `ReferenceGlob.jl`,
  `ReferenceSearch.jl` (not read: the kernel audit covers them file by file);
- `kernel/operation/Operations.jl` (the selection and the mouse target operations, the write of a slot,
  `child_reference_steps`); `kernel/document/DocumentWalk.jl` (the first 100 lines);
- text slice: `TextDocument.jl` (the selection forms, lines 771-810, 970-1070, 1400-1500),
  `TextToGraphics.jl` (the pointer reader and the forward range, lines 255-330, 396-470);
- widgets: `DrawnTextLine.jl` (220 of 399 lines), `WidgetToGraphics.jl` (the readers of a label, a link, a
  toolbar item and a toggle group, and the table reference makers), `WidgetDocument.jl` (lines 20-84),
  `LayoutToGraphics.jl` (`read_child_event`, `_route_to_children`, `_point_backward`);
- domains: chart (`ChartPlotToGraphics.jl` reader and reference makers), sequence chart, graph
  (`GraphLayoutToGraphics.jl` reader);
- link: `LinkInterface.jl`, `UrlInterface.jl`, `OpenUrlOperation.jl` (signatures only), `ClipboardCollectionToAny.jl`
  (head and gesture table), `ClipboardWrapper.jl` (first 60 lines).

Documents read: `concepts.md`, `architecture-decisions.md`, the PAR sections "Projections", "References and
selection" and "Operations", `kernel/reference.md`, `kernel/selection.md`, `kernel/mouse-target.md`,
`platform/focus/focus.md`, `platform/clipboard/clipboard.md`, the head of `platform/link/link.md` and of
`platform/navigator/navigator.md`. Plans read (head, and the sections that touch a candidate): the ten plans
named in the task, `a-view-names-the-domain-part-under-a-point.md`, `the-work-that-the-forward-image-found.md`,
`done/text-range-reference-flat-cursor.md`, `done/copy-and-paste-text-with-the-system-clipboard.md`, and the
indexes of `kernel-audit/11-reference.md`, `12-selection.md`, `13-operation.md`, `17-projection.md`.

I ran no Julia. Every claim below comes from reading code. Where a claim is about behaviour that only a run
can show, the text says "by reading".

## State

The model of the area is sound and it is the right one. A selection is a path from the root. Each document
holds the rest of its path. The empty path is a whole part. A projection maps a path forward and backward
with two functions, and one default reader maps every operation that carries a path. Focus is the selection:
the focus slice holds no state. The mouse target reuses the same shape, and one family of operations
(`ReplacePathOperation`) carries both kinds of path backward. The link slice has one small interface that two
domains extend with no change in the platform.

The main weakness is that the generic mechanism was built once for the forward and backward maps, and not for
what sits around them. The same job is done several ways:

- two writers store a path along the tree, one for the selection and one for "every other kind";
- two walkers give an output tree its part of a path, behind seven function names;
- three functions list the child documents of a node, under three sets of rules;
- a place in a text has three path forms and four step types with the same two numbers;
- about thirty private helpers repeat path arithmetic that the reference layer does not give.

The second weakness is that a step type of a higher package is a second-class step. The open seam covers
evaluation. Thirteen places in generic code still ask "is this a field or a range" by type, so a new step
gets the default arm in each. The classification seam that could answer this exists, has one answer, and has
no reader.

The clipboard works on every domain with no code in the domain, which is the goal. Its structure has two
wrappers that exclude each other, and it keeps view state in the projection object.

## Inventory

### 1. The kinds of reference step

Twelve types subtype `ReferenceStep`. "Files" counts the `.jl` files under `source/` that name the type.

| Step | Where | Payload | Files | Producer | Notes |
| --- | --- | --- | --- | --- | --- |
| `RangeReferenceStep` (`[i]`, `{k}`, `{a:b}`) | [ReferenceStep.jl:31](../../../source/kernel/reference/ReferenceStep.jl#L31) | start, stop, direction | 126 | every domain | caret, element and range in one type |
| `FieldReferenceStep` (`.name`) | [ReferenceStep.jl:247](../../../source/kernel/reference/ReferenceStep.jl#L247) | name | 218 | every domain | also a key of a dict |
| `TypeReferenceStep` (`::T`) | [ReferenceStep.jl:295](../../../source/kernel/reference/ReferenceStep.jl#L295) | type | 8 | `@reference`, template engine | a token of the builder; folded away before a path is stored |
| `ProjectionReferenceStep` (`‹…›`) | [ProjectionReferenceStep.jl:22](../../../source/kernel/projection/ProjectionReferenceStep.jl#L22) | projection, output path | 25 | default backward map | a part that a view introduced |
| `OutputReferenceStep` | [OutputSelection.jl:19](../../../source/platform/focus/OutputSelection.jl#L19) | owner, node, output path | 3 | none in this repository | a drawn widget; step 5.4 of a pending plan removes it |
| `PointReferenceStep` | [PointReferenceStep.jl:4](../../../source/platform/graphics/PointReferenceStep.jl#L4) | x, y | 19 | every container (hit test) | a point in the frame of a node |
| `RegionReferenceStep` | [RegionReferenceStep.jl:14](../../../source/platform/graphics/RegionReferenceStep.jl#L14) | x, y, width, height | 4 | `TextToGraphics` forward map | a box in the frame of a node |
| `TextRangeReferenceStep` (`⌶{a:b}`) | [TextRangeReferenceStep.jl:39](../../../source/platform/text/TextRangeReferenceStep.jl#L39) | start, stop, direction | 10 | text reader | caret and range of characters of a text block |
| `TextSpanReferenceStep` (`▢(a:b)`) | [TextSpanReferenceStep.jl:4](../../../source/platform/text/TextSpanReferenceStep.jl#L4) | start, stop | 7 | `SyntaxToText` forward map | the text of a whole part |
| `TextColumnReferenceStep` (`▥(a:b)`) | [TextColumnReferenceStep.jl:38](../../../source/platform/text/TextColumnReferenceStep.jl#L38) | start, stop | 4 | none ([line 16](../../../source/platform/text/TextColumnReferenceStep.jl#L16)) | reserved |
| `ChartSampleReferenceStep` (`.sample(i)`) | [ChartSampleReferenceStep.jl:4](../../../source/domain/chart/ChartSampleReferenceStep.jl#L4) | index | chart | chart reader | row of a columnar series |
| `SequenceChartRowReferenceStep` (`.row(i)`) | [SequenceChartRowReferenceStep.jl:29](../../../source/domain/sequencechart/SequenceChartRowReferenceStep.jl#L29) | index | sequence chart | sequence chart reader | row of a columnar table |

Which seam each step answers:

| Step | `evaluate_reference_step` | `has_reference_step_child` | `@reference` build | `@reference_case` match | `@reference_rules` match | routed by the selection writer | caret moved in place | follows a splice | read as a whole part |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Range | yes | yes | built in | built in | built in | yes | yes | yes | yes |
| Field | yes | yes | built in | built in | built in | yes | – | yes | yes |
| Projection | yes | default | `.proj` | `.proj` | no | no | – | no | own rule |
| Output | yes, from its owner only | default | no | no | no | no | – | no | no |
| Point | yes | default | `.point` | `.point` | no | no | – | no | no |
| Region | yes | default | no | no | no | no | – | no | no |
| TextRange | yes | default | no | no | no | no | no | no | no |
| TextSpan, TextColumn | yes | default | no | no | no | no | – | no | no |
| ChartSample, SequenceChartRow | yes | default | `.sample`, `.row` | `.sample`, `.row` | no | no | – | no | no |

The last four columns are closed type switches in generic code (finding RS-5). `match_reference_step_value`,
the seam of `@reference_rules`, has no method at all (kernel audit L11-10).

### 2. The two chains that store a path along the tree

| | Selection | Mouse target ("every other kind") |
| --- | --- | --- |
| Writer | `_sync_selection!` [SelectionDefaults.jl:265](../../../source/kernel/selection/SelectionDefaults.jl#L265) | `replace_path_chain!` [PathChain.jl:19](../../../source/kernel/operation/PathChain.jl#L19) |
| Layer | selection (12) | operation (13) |
| Child of a step | `_selection_child` [:315](../../../source/kernel/selection/SelectionDefaults.jl#L315): a switch on Field and Range | `_find_path_child` [:91](../../../source/kernel/operation/PathChain.jl#L91): `evaluate_reference_step`, the open seam |
| What a document stores | the same path objects as its parent's tail | its own typed copy of the tail |
| Compare | `is_reference_equal`, with types | stripped of types |
| Validate before the write | yes, `_matched_selection` [:146](../../../source/kernel/selection/SelectionDefaults.jl#L146) | no |
| Caret moved in place | yes, `_mutate_terminal_step!` [:357](../../../source/kernel/selection/SelectionDefaults.jl#L357), Range only | no |
| Dormant branch | yes, `_keeps_branch` [:83](../../../source/kernel/selection/SelectionDefaults.jl#L83) | no |
| Clear | `clear_selection!` [:43](../../../source/kernel/selection/SelectionDefaults.jl#L43) | `_clear_path_chain!` [:103](../../../source/kernel/operation/PathChain.jl#L103) |
| Follows an insert or a delete | no (pending plan) | yes, `_find_written_chain` [:126](../../../source/kernel/operation/PathChain.jl#L126), called at [Operations.jl:502](../../../source/kernel/operation/Operations.jl#L502) |
| Forward wiring in a printer | one list for both: `_get_output_path_computations` in [OutputPaths.jl:49](../../../source/kernel/projection/OutputPaths.jl#L49) | the same |
| Backward | one family for both: `ReplacePathOperation` | the same |

### 3. The ways a selection crosses a projection

Forward (printer side):

| Way | Function | Users |
| --- | --- | --- |
| The same cell goes through | `getfield(input, :selection)` passed to the output | `JsonToSyntax.jl:129`, `YamlToSyntax.jl:113`, four text line stages |
| A computed cell at the output root | `make_output_path_cells` [OutputPaths.jl:29](../../../source/kernel/projection/OutputPaths.jl#L29) | 38 files |
| The same, on an output that exists | `set_output_path_computations!` [:41](../../../source/kernel/projection/OutputPaths.jl#L41) | 48 files |
| By hand | `Cell(@computation(map_selection_forward(…)))`, `map_mouse_target_forward` | 7 and 22 files |
| The tree below the root, child reads parent | `set_output_tree_path_computations!` [:79](../../../source/kernel/projection/OutputPaths.jl#L79) | 11 files |
| The tree below the root, each node reads the root | `follow_output_selection!` [OutputSelection.jl:92](../../../source/platform/focus/OutputSelection.jl#L92), `follow_output_mouse_target!` [:113](../../../source/platform/focus/OutputSelection.jl#L113) | 18 files call one of these four names |
| The same, for widgets | `follow_widget_output!` [WidgetDocument.jl:40](../../../source/platform/widget/WidgetDocument.jl#L40), `follow_built_children!` [:55](../../../source/platform/widget/WidgetDocument.jl#L55) | counted in the row above |
| The template engine | `collection(:field)`, `project(:field)` markers | every `@projection_template` |
| A document of the input held whole in the output | `map_held_node_forward` [OutputSelection.jl:330](../../../source/platform/focus/OutputSelection.jl#L330) | inspector views |
| A wrapper document made around a root | read inner selection, `concat_references`, `replace_selection!` | `make_clipboard_document`, `make_window_shell_document`, `make_window_scene` |

Backward (reader side):

| Way | Function | Notes |
| --- | --- | --- |
| The default reader maps the path | `map_reference_backward` on a `ReplacePathOperation` | one method for the selection and the mouse target |
| A container puts its step in front | `reroot_operation(operation, steps)` | 95 uses in the platform |
| A part with no input | `make_introduced_reference` | 120 uses |
| A verb at a place | `read_rooted_operation`, `Intent.route` | 13 uses in the platform |
| A direct write | `replace_selection!`, `set_selection!` outside an operation | about 40 call sites; most build a new root or a document that nothing holds yet |

The ways combine in one chain: each stage reads only the `selection` of its own input. The divergence is in
the tree rows (finding RS-3).

### 4. What a selection can be, by view

"yes" has a citation in the findings or below. "no (plan)" means a pending plan names the gap. "by reading"
means I inferred it from code and did not run it.

| View | Caret | Range of characters | Whole part | Range of siblings | Many parts |
| --- | --- | --- | --- | --- | --- |
| Text block (`TextToGraphics`) | click, keys | Shift+click, drag, Shift+keys, double and triple click ([TextToGraphics.jl:407-453](../../../source/platform/text/TextToGraphics.jl#L407)) | `∅`, `▢(a:b)` | – | no |
| Syntax tree (`SyntaxToText`) | yes, in a leaf | in the value of one leaf | Alt+double click, Alt+arrows | no (plan `syntax-tree-selection`) | no |
| Widget text (`DrawnTextLine.jl`) | click on a label, Alt+click on a control | Shift+click, drag, Shift+keys; no double click word | Alt+double click | – | no |
| Table (`WidgetTable`) | in the text of a cell | as widget text | cell, row header, column header, row, column ([WidgetToGraphics.jl:14287-14300](../../../source/platform/widget/WidgetToGraphics.jl#L14287)) | not found | no |
| Chart, sequence chart | – | – | legend, series, sample, row, by click | – | no |
| Graph | in the content of a vertex | as that content | vertex content | – | no |

Copy, cut, paste and delete, by what the selection names (all in the clipboard slice):

| The selection names | Copy | Cut | Paste | Delete |
| --- | --- | --- | --- | --- |
| A whole document | deep copy | the document itself, plus the content's Delete | replaces it, or the document takes it its own way | Delete of the content, else the slot is emptied |
| A whole value that is no document (`String`, `Number`, `Bool`) | as a primitive document ([ClipboardSliceToAny.jl:453](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L453)) | no | text typed over the value | no |
| A range in a `String` or `Number` field (`.field{a:b}`) | the characters | the characters | text at the range | the text reader |
| A range in a text block that a document holds (`⌶{a:b}`) | no, by reading (RS-2) | no | no | the text reader |
| A range in a text block that is the content, `text = true` | the characters | the characters | text | – (tests only) |
| A part that a view introduced | no (plan, step 5.4) | no | refused | no |
| A chart sample, a sequence chart row | no, by reading: the value is no document and no primitive | no | no | no |

### 5. How a click becomes a selection

One rule, with three places where it is applied:

1. Each container hit-tests and calls `read_child_event` ([LayoutToGraphics.jl:251](../../../source/platform/layout/LayoutToGraphics.jl#L251)).
   It applies the three press rules of the focus slice: a plain down gives the focus, an Alt+click keeps only a
   caret, an Alt+double click becomes the innermost whole part (`find_whole_part`,
   [WholeSelection.jl:111](../../../source/platform/focus/WholeSelection.jl#L111)).
2. A text leaf answers the caret with its own backward map of the point
   ([TextToGraphics.jl:436](../../../source/platform/text/TextToGraphics.jl#L436)).
3. A widget that draws text answers through `DrawnTextLine.jl`, written once for every widget.

Twenty-eight more sites test `is_selection_press`, `is_caret_press` or `is_whole_selection_press` in a reader
of their own (18 in `WidgetToGraphics.jl`, 5 in `WidgetTableParts.jl`, and 5 in the syntax tree, the pane,
the conversation and the fault mark). The pending plan `a-click-reaches-the-innermost-part-in-every-view` is at
work on exactly these, with ten owner decisions, so this review raises no finding there.

### 6. Focus and selection

One notion. No document has a `focused` field (grep over the widget, layout and shell slices). A key goes to
the child that the selection names. Three walks choose where the selection goes: the Tab walk
(`is_focusable_document`), the Alt+arrow walk (`is_selection_walk_stop`), and the press rules. All three use
one private list of children, `_child_document_refs` (finding RS-7).

### 7. The ways to point at another document

| Way | What it holds | Where |
| --- | --- | --- |
| The document itself | identity | `Link.target`, a pane tab, `OutputReferenceStep.node` |
| `DocumentLocator(start, reference)` | a start and a path, resolved at each read | kernel `ReferencedDocument.jl`; the target of a `Link` and of a `WidgetLink` |
| `ReferencedDocument(document, reference)` | a document with the path that reached it | what a read of a part answers; never stored |
| `Url` | an address in seven pieces | link slice; `find_url_document(::Val{scheme}, url)` resolves it |
| A navigator address | `content` and `address`, two fields | `Navigator`, `NavigatorVisit` |
| A place in an operation | a path from where the operation stands | `PasteOsClipboardOperation.place`, `Intent.route` |
| Julia code | `evaluate_reference(editor.document, @reference(…))` | `CopyReferenceOperation` (Ctrl+Shift+C) |

These have different lives (stored, transient, typed by a person), and each has one implementation. A link
type answers three functions (`is_link`, `get_link_target`, `get_link_content`); `Link`, `Url`, `MarkdownLink`
and `RstReference` do. I found no divergence worth a finding.

## Findings

### RS-1 One chain for every kind of path

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 4 (each node holds the rest of its path) and 7 (one mechanism, a missing case gets a row).
  `mouse-target.md` states the aim itself: "One mechanism serves both, and a third kind of path, if one is ever
  added, can reuse it the same way."
- **Today:** Every cell-layout document has two path fields, `selection` and `mouse_target`. Two writers store
  a path along the tree. `_sync_selection!` ([SelectionDefaults.jl:265](../../../source/kernel/selection/SelectionDefaults.jl#L265))
  writes the selection. `replace_path_chain!` ([PathChain.jl:19](../../../source/kernel/operation/PathChain.jl#L19)) writes
  "every other kind", and its docstring says so: "The selection keeps its own chain". Table 2 of the inventory
  lists ten rows in which the two differ (corrected by the check: the table has twelve rows, and the last
  two are the same for both). Three matter most:
  - the selection writer finds the child with a switch on two step types
    ([:315](../../../source/kernel/selection/SelectionDefaults.jl#L315)); the other writer uses the open seam
    `evaluate_reference_step` ([:91](../../../source/kernel/operation/PathChain.jl#L91));
  - only the mouse target follows an insert or a delete: `_find_written_chain` has the default
    `field = :mouse_target` ([:126](../../../source/kernel/operation/PathChain.jl#L126)) and the write of a slot calls it
    with no field ([Operations.jl:502](../../../source/kernel/operation/Operations.jl#L502));
  - only the selection is validated before the write and keeps a dormant branch.
- **Example:**
  ```julia
  # today: a kind of path is a function name, and each name has its own walk
  replace_selection!(root, path)        # SelectionDefaults.jl, 364 lines
  replace_mouse_target!(root, path)     # PathChain.jl, 204 lines

  # after: a kind of path is a value, and what differs is a row
  replace_path!(root, SelectionPath(), path)
  replace_path!(root, MouseTargetPath(), path)
  keeps_dormant_branch(::SelectionPath) = true
  is_path_validated(::SelectionPath)    = true
  follows_splice(::PathKind)            = true     # every kind
  ```
- **Problem:** A third kind (a named selection, a highlight, the result of a search) must pick one of two
  writers or add a third. A step type of a higher package routes in one chain and not in the other. The
  pending plan `an-insert-moves-the-paths-after-it` plans "a function of the reference slice that maps a path
  through a splice" for the selection, while `_move_spliced_path`
  ([PathChain.jl:145](../../../source/kernel/operation/PathChain.jl#L145)) does that for the mouse target already. So
  the next fix would be written twice, as the clear and the compare-and-write walks are today.
- **Proposal:** One path chain in the kernel, with the kind as a value. The policy of a kind is a few small
  functions: validated or not, keeps a dormant branch or not, saved or not. One descent to the child, by
  `evaluate_reference_step`. One follow of a splice, for every kind. `replace_selection!` and
  `replace_mouse_target!` stay as the two public names and call it.
- **What goes away:** `_selection_child`, `_set_selection_walk!`, one of the two clear walks, one of the two
  compare-and-write walks, the default `field = :mouse_target`. About 150 lines, and the second copy of every
  later change.
- **What stays:** The dormant selection, the atomic validation, the caret move that writes two cells, the
  mouse target that follows an edit. The selection gains the follow of a splice, which the owner asked for on
  2026-10-16.
- **Risk and open questions:** The two chains store differently. The selection shares path objects between a
  parent and its child, which is what makes the in-place caret move possible. The mouse target stores a typed
  copy per document. One chain must choose one storage, and the choice needs a count of the cells written per
  caret move and per pointer move (`PAR-REPEATED-MOVE-WRITES-NOTHING`). Check `SEALING.md` for each kernel file.
- **Related plans:** `plan/tentative/named-paths-in-a-document.md` (an idea, nothing planned; it says "the
  selection keeps its own code until a plan moves it into the model"); `plan/pending/an-insert-moves-the-paths-after-it.md`
  (not started); `plan/done/a-document-knows-the-part-under-the-pointer.md` (done; it built the second chain).
- **Check:** confirmed-with-corrections; value after the check: medium. I read `SelectionDefaults.jl` and
  `PathChain.jl` in full, `mouse-target.md`, the tentative plan, the splice plan and Q4 of the done plan. The
  facts hold. Two numbers were wrong and are corrected above: ten rows differ, not eleven, and `PathChain.jl`
  has 204 lines. Every kernel file named here is unsealed (⬜ in `SEALING.md`). The two chains are a decision
  of the owner and no accident: Q4 of `plan/done/a-document-knows-the-part-under-the-pointer.md` (2026-09-29,
  "Option 2") says "one wiring, in the general shape, and the selection code stays", and the tentative plan
  says "the selection keeps its own code until a plan moves it into the model". So this finding is the step
  that the tentative plan left open, and its value is lower than high: nothing that works today is broken by
  the two chains, and the merge pays only when a third kind of path or the splice plan is built. What the
  finding adds, and what holds: `an-insert-moves-the-paths-after-it.md` (2026-10-16) still says "No stored
  path moves with it" and plans a new map of a splice, while `_move_spliced_path` and
  `_follow_written_chain!` do that for the mouse target; and the descent of the path chain
  (`evaluate_reference_step`) is the right one of the two, because `_selection_child` routes a caret on a
  collection into the next element (kernel audit L12-1). The proposal loses no feature if the one chain keeps
  the shared path objects of the selection, which the caret move in place needs. One detail of the example is
  too simple: what happens to a path into a replaced range differs by kind (the mouse target falls back to
  the parent; M2 of the splice plan wants the next element), so it is a row of the kind and not
  `follows_splice = true` for every kind.

### RS-2 A place in a text has one path form

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** 4 (the selection is a path, one model) and 7. `PAR-ONE-BASED-INDEXING`: "`{k}` … both are
  readings of the same `RangeReferenceStep(start, stop)` axis and apply to any sequence, whether the items are
  elements or characters."
- **Today:** A `TextBlock` is the document of the text slice. A caret or a range in it has three accepted
  forms. `_text_flat_selection` ([TextDocument.jl:982](../../../source/platform/text/TextDocument.jl#L982)) reads all three:
  `⌶{a:b}`, a `TextRangeReferenceStep` on the block; `{a:b}`, the kernel `RangeReferenceStep` on the block
  ([:987](../../../source/platform/text/TextDocument.jl#L987)); and `.elements[i].elements[j].content{a:b}`, the form that
  an edit leaves ([:1466](../../../source/platform/text/TextDocument.jl#L1466)). Four step types hold the same two numbers:
  the kernel range (with a direction), `TextRangeReferenceStep` (with a direction), `TextSpanReferenceStep`
  (the text of a whole part) and `TextColumnReferenceStep`, which no code produces
  ([:16](../../../source/platform/text/TextColumnReferenceStep.jl#L16)). Code converts between the forms:
  `get_flat_caret` ([:1041](../../../source/platform/text/TextDocument.jl#L1041)) and `get_flat_range`
  ([:1066](../../../source/platform/text/TextDocument.jl#L1066)), called in eight files outside `TextDocument.jl`
  (corrected by the check: the report said "in five text stages", which is the list of the docstring);
  `_read_text_table_key` ([DrawnTextLine.jl:274](../../../source/platform/widget/DrawnTextLine.jl#L274)), which turns a
  kernel range into a text range and back to reuse the keys of the text slice; `_map_value_text_reference`
  ([WidgetToGraphics.jl:2717](../../../source/platform/widget/WidgetToGraphics.jl#L2717)).
- **Example:**
  ```julia
  # today: a text stage reads a place through a helper that knows three forms
  k = get_flat_caret(block, reference)          # ⌶{k}  or  .elements[i].elements[j].content{k}
  # and a widget converts to borrow the key table of the text slice
  set_selection!(block, make_flat_range_reference(a, b))        # {a:b}  ->  ⌶{a:b}
  path.head isa TextRangeReferenceStep || return nothing        # ⌶{a:b} ->  {a:b}

  # after: the kernel range step on the block, at every level
  @reference_case reference begin
      {a:b} => (a, b)
  end
  ```
- **Problem:** Generic code knows only the kernel range. The caret move in place
  ([SelectionDefaults.jl:357](../../../source/kernel/selection/SelectionDefaults.jl#L357)) and `copy_reference`
  ([ReferenceEvaluation.jl:316](../../../source/kernel/reference/ReferenceEvaluation.jl#L316)) skip a text range. The
  clipboard finds a text target only at a field step followed by a kernel range
  ([Clipboard.jl:426](../../../source/platform/clipboard/Clipboard.jl#L426)). So, by reading, a range in a text block that
  a document holds (a `BookParagraph`) copies nothing, and the clipboard carries a second text mode for a
  block that is the whole content ([ClipboardSliceToAny.jl:297](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L297)),
  which only two tests turn on. Each new text stage and each new consumer must handle each form.
- **Proposal:** The caret and the range of a text block are the kernel range step on the block: `{k}` and
  `{a:b}`, the flat offsets of today. The text reader emits that form, and the evaluation of an edit leaves
  that form. `TextRangeReferenceStep` goes. `TextSpanReferenceStep` stays as the one image of a whole part in
  a text, or becomes a kind of the range (see RS-5). `TextColumnReferenceStep` and its geometry go until a
  gesture produces it.
- **What goes away:** `TextRangeReferenceStep.jl` (70 lines), `TextColumnReferenceStep.jl` (55 lines) and
  `_compute_column_geo`, the structural branch of `_text_flat_selection` and `_parse_selection_range`, the two
  conversions in the widget slice, the `text` mode of the clipboard (see RS-8).
- **What stays:** The flat coordinate, which fixed the two encodings of a caret at a span boundary
  (`plan/done/text-range-reference-flat-cursor.md`). The direction of a range. The highlight of a whole part.
  Copy and paste of a range then need one more row (corrected by the check: the report said "with the code
  that exists", but `_find_text_kind` at [Clipboard.jl:476](../../../source/platform/clipboard/Clipboard.jl#L476)
  answers `nothing` for a field that holds a `TextBlock`, so `.content{a:b}` is still no text target).
- **Risk and open questions:** I did not trace why the done plan added a step type and did not use the kernel
  range on the block; the plan argues for the flat coordinate, not for the type. A range that is no caret
  evaluates to `document[start + 1]` ([ReferenceStep.jl:218](../../../source/kernel/reference/ReferenceStep.jl#L218)), so
  a `TextBlock` must answer a character there. Kernel audit L12-1 (a caret on a collection routes into the
  next element) must not apply to the block: its lines are under `.elements`, so by reading it does not.
- **Related plans:** `plan/done/text-range-reference-flat-cursor.md` (done; decision 2 wanted "one canonical
  form" and kept the structural reader); `plan/pending/syntax-tree-selection.md` (in progress; names the
  column step as reserved); `plan/pending/left-motion-stalls-on-introduced-text.md` (in progress, other subject).
- **Check:** weakened; value after the check: medium. I read the three step files, `_text_flat_selection`,
  `get_flat_caret`, the two conversions of the widget slice, `_find_text_target`, `text.md` and the done plan.
  The three forms are real, and the done plan gives no reason against the kernel range (its "distinct type"
  argument is about `TextSpanReferenceStep`). Three points make the finding smaller.
  (1) A shared helper joins the forms already. `get_flat_range` and `get_flat_caret` are called in eight files
  outside `TextDocument.jl`, and a stage that calls them names no form. So "each new text stage must handle
  each form" does not hold; only generic code outside the text slice (the caret move in place,
  `copy_reference`, the clipboard) meets the difference.
  (2) The structural form is kept on purpose. Step S8 of the done plan kept the structural reader as "a
  robustness the console/insertion paths rely on", because the kernel edit of a string leaves its caret in
  the string. To drop it, the edit of a text needs its own way to leave the flat form, and the proposal does
  not say how.
  (3) One gain was wrong and is corrected above: copy of a range in a block that a document holds needs a new
  row with either form.
  What the proposal would make worse: `{k:k+1}` and `[k+1]` are one value of the kernel step, so a selection
  of one character of a block becomes an element step on a document. `_is_slot_accepting`
  ([Clipboard.jl:376](../../../source/platform/clipboard/Clipboard.jl#L376)) takes every `RangeReferenceStep` for a
  slot of a list, and `_is_written_step` takes it for an element; the own type keeps that code away from a
  text today. A range that is no caret must also evaluate (`document[start + 1]`), where the text step
  evaluates with no read of the text. Two small parts hold as they stand: `TextColumnReferenceStep` has no
  producer, and the conversion in `_read_text_table_key` goes away with any single form.

### RS-3 One call gives an output tree its paths

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 and 8. Decision D6 of the owner (2026-11-10): "Each view writes the selection of its output",
  one call in its printer.
- **Today:** A printer that builds a tree of output documents must give each of them its part of the
  selection and of the mouse target, or a key stops at the first container that holds none. Two walkers do
  this. `set_output_tree_path_computations!` ([OutputPaths.jl:79](../../../source/kernel/projection/OutputPaths.jl#L79)) is in
  the kernel: each child reads the cell of its parent, the children come from `child_reference_steps`, there
  is no filter and no rule for a lazy list. `follow_output_selection!`
  ([OutputSelection.jl:92](../../../source/platform/focus/OutputSelection.jl#L92)) is in the focus slice: each node reads
  the path of the root and cuts its own prefix, the children come from `_child_document_refs`, a filter
  `is_followed` leaves nodes out, and a lazy list has its own rule
  ([:142](../../../source/platform/focus/OutputSelection.jl#L142)). Around them stand five more names:
  `make_output_path_cells`, `set_output_path_computations!`, `follow_output_mouse_target!`,
  `follow_widget_output!`, `follow_built_children!`. Eleven files call the first walker, and eighteen call
  the second through one of its names.
- **Example:** one print in [TaskGroupToWidget.jl:1059](../../../source/platform/task/TaskGroupToWidget.jl#L1059):
  ```julia
  # today
  follow_output_mouse_target!(root, forward_mouse_target; is_followed = …)
  follow_output_selection!(root, forward_selection; is_followed = _is_followed_by_selection)
  follow_output_mouse_target!(detail, below_detail(forward_mouse_target); is_followed = …)
  follow_output_selection!(detail, below_detail(forward_selection); is_followed = …)
  follow_output_mouse_target!(alone, below_alone(forward_mouse_target); is_followed = …)
  follow_output_selection!(alone, below_alone(forward_selection); is_followed = …)

  # after: every kind of path, every document of the tree, lazy lists too
  set_output_tree_path_computations!(root, input, map_forward; is_followed)
  ```
- **Problem:** The author of a view chooses among seven names, and the choice decides whether a lazy list
  works, which children are found, and whether a dormant selection is carried. The kernel walker names the
  kinds of path once (`_get_output_path_computations`); the focus walker names `:selection` and
  `:mouse_target` by hand, so a third kind needs a change in both. The plan of the click work counts about
  twenty printers that still need the call.
- **Proposal:** One function in the projection layer of the kernel wires the root and the tree below it, for
  every kind of path from the one list. It takes `is_followed`. The rule of a lazy list comes through a seam
  that the collection slice answers, because the kernel can not name `ListNode`. A child that a computation
  builds later follows the same rule as a list node that is built later, so `follow_built_children!` is that
  rule and not a second function.
- **What goes away:** `follow_output_selection!`, `follow_output_mouse_target!`, `follow_widget_output!` as
  separate entry points; one of the two tree walks (about 60 lines of the kernel one or about 200 of
  `OutputSelection.jl` move and merge); the six-call blocks in views.
- **What stays:** A lazy list still builds only the rows of its window. A view still leaves a domain document
  out with `is_followed`. The call stays in the printer, as D6 says.
- **Risk and open questions:** The two walkers differ in reactive cost: a chain of cells from parent to child,
  or one read of the root per node. Commit 88d5a916d fixed a tracking fault in the second; the one walker must
  keep that fix. Which storage is cheaper for a tree of 20 000 rows needs a measure.
- **Related plans:** `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress; D6 and Q3
  decide that each view makes the call; corrected by the check: step 5.4 of that plan also built the
  function, `follow_widget_output!` with `follow_built_children!`, in the widget slice, as "the functions of
  D6"); `plan/pending/a-graph-lights-the-part-under-the-pointer.md`
  (pending; it meets the `is_followed` filter).
- **Check:** confirmed-with-corrections; value after the check: medium. I read both walkers,
  `follow_widget_output!`, `follow_built_children!`, the call site in `TaskGroupToWidget.jl`, and D6, Q3 and
  the notes of step 5.4 of the click plan. Counts again: 11 files call `set_output_tree_path_computations!`
  (13 name it, less the definition and the export); 18 files call one of the four `follow_…` names (22 less
  two definitions and two exports), and 16 of them call `follow_widget_output!` or `follow_built_children!`.
  The correction: the click plan did choose the function. Step 5.4 built `follow_widget_output!(root, input,
  map_forward; is_followed)` and moved the views of projectured-julia and 20 views of omnet-julia to it. So
  the "after" line of the example exists already under that name, and what is left is smaller: the kernel
  walker with its 11 callers (no filter, no lazy list; it sets the cell of every child document that has
  one, also of a document of the domain that the output holds whole), and three files that call the focus
  functions directly. The example overstates the gain: the six calls of `TaskGroupToWidget` use two filters
  (the mouse target follows a `WidgetTable`, the selection does not) and three roots that stand at different
  places (`below_detail`, `below_alone`), and one call would lose both. The seam for a lazy list in the
  kernel is a new mechanism. To retire the kernel walker and call `follow_widget_output!` in its 11 files
  gives most of the gain with no new seam.

### RS-4 The reference layer gives the path arithmetic that each slice rewrites

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7. `PAR-REFERENCE-DSL`: "Build and match reference paths with the DSL, not by hand."
- **Today:** The reference layer exports the build of a path, its head and tail, `extend_reference`,
  `concat_references` and the prefix test. Four more questions are asked everywhere and answered by private
  code:
  - "the rest of a path below these steps": 14 private functions with the same body, for example
    `_find_path_below` in [ExplorerToWidget.jl:106](../../../source/platform/explorer/ExplorerToWidget.jl#L106),
    [WorkPlanToWidget.jl:80](../../../source/platform/workplan/WorkPlanToWidget.jl#L80) and four more files,
    `_get_path_below_steps` in [ProjectionTemplate.jl:1652](../../../source/kernel/projection/ProjectionTemplate.jl#L1652),
    `_find_path_below_steps` in [WidgetDocument.jl:73](../../../source/platform/widget/WidgetDocument.jl#L73),
    `_get_output_part` in [OutputSelection.jl:276](../../../source/platform/focus/OutputSelection.jl#L276). They differ in
    whether they strip the types and whether a range compares its direction;
  - "the documents on a path, or the innermost one": 13 loops that evaluate each prefix from the root again,
    among them `_find_deepest_part` ([SelectedPart.jl:8](../../../source/platform/focus/SelectedPart.jl#L8)),
    `_find_writable_slot` and `_split_at_place` ([Clipboard.jl:283](../../../source/platform/clipboard/Clipboard.jl#L283),
    [:345](../../../source/platform/clipboard/Clipboard.jl#L345)), `_selection_owner_node` and `_find_owner_document`
    ([Operations.jl:744](../../../source/kernel/operation/Operations.jl#L744), [:334](../../../source/kernel/operation/Operations.jl#L334)),
    `get_parent` ([ReferencedDocument.jl:396](../../../source/kernel/reference/ReferencedDocument.jl#L396)),
    `_find_innermost_document_path` ([PaneToWidget.jl:671](../../../source/platform/pane/PaneToWidget.jl#L671));
  - "the last step, and the path without it": four versions (`_split_terminal_step`, two `_drop_last_step`,
    `_drop_last`);
  - "a path from a vector of steps": `Reference(steps...)` exists
    ([ReferencePath.jl:80](../../../source/kernel/reference/ReferencePath.jl#L80)), and still 17 inline folds, 14 uses of
    `_make_steps_path` and 8 of `_prepend_steps` build it by hand.
  `get_reference_steps(strip_reference_types(x))` opens 164 call sites in 82 files (counted again by the check).
- **Example:**
  ```julia
  # today, in one view
  function _find_path_below(path, steps)
      for step in steps
          (path isa ConcreteReference && path.head == step) || return nothing
          path = path.tail
      end
      path
  end
  # and in the clipboard, one evaluation from the root for each prefix
  for count in (length(steps) - 1):-1:1
      node = try_evaluate_reference(input, _make_steps_path(steps[1:count]), missing)
      …
  end

  # after
  rest = get_reference_below(path, prefix)                 # a Reference, or nothing
  for (node, to_node, rest) in walk_reference(input, path) # one step of evaluation per node
      …
  end
  ```
- **Problem:** Each new view writes the helper again, and the copies do not agree on types and on the
  direction of a range. Each loop over the prefixes costs the square of the depth of the path.
- **Proposal:** Four functions in the reference layer: the rest of a path below a prefix; the last step with
  the path before it; a walk that answers each node on a path with the path to it and the rest; and, on top
  of that walk, the innermost node that satisfies a test. The layer decides once what "the same step" means.
- **What goes away:** About thirty private helpers and loops, roughly 300 lines, in the kernel, twelve platform
  slices and two domains.
- **What stays:** Every caller keeps its own test (a document, not a collection, accepts a paste).
- **Risk and open questions:** A few copies ignore the direction of a range on purpose; the one function needs
  that as an option or as the rule. `ReferencePath.jl` and `ReferenceEvaluation.jl` are kernel files: check
  `SEALING.md`.
- **Related plans:** `plan/pending/kernel-audit/13-operation.md` L13-13 notes that reference helpers sit in the
  operation layer (file level, two of the helpers above). No plan covers the platform copies.
- **Check:** confirmed; value after the check: medium. Every cited line holds. Counts again with grep: 13
  definitions of "the rest below these steps" (the report says 14; the names are `_find_path_below*`,
  `_get_path_below*`, `_get_output_part` and `_find_path_part`), four versions of the last step helper, 13
  uses of `_make_steps_path` and 7 of `_prepend_steps` beside their definitions, about 19 inline folds (the
  report says 17), and 164 sites in 82 files for the opening line (corrected above). The reference layer
  exports no function for any of the four questions (`ReferenceModule.jl:100-130`); `is_reference_prefix`
  answers only yes or no. `@reference_case` can not take the place of the helper, because the prefix is a
  value of the run in most copies (`_get_detail_steps(doc)`). The walk with one evaluation for each node
  exists already, private to the operation layer: `_find_documents_above`
  ([PathChain.jl:190](../../../source/kernel/operation/PathChain.jl#L190)). The proposal loses no feature. The copies
  differ in types and in the direction of a range, so each call site needs a look when it moves. This is a
  clean-up of helpers and no change of the model, so medium is the upper end.

### RS-5 A step says whether it reaches a part or names a place

- **Kind:** special-case · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** 7 (a missing case gets its row in the generic mechanism, never a special path) and 2 (a
  general step knows no domain).
- **Today:** `get_reference_step_kind` ([ReferenceInterface.jl:76](../../../source/kernel/reference/ReferenceInterface.jl#L76))
  is an open function that classifies a step. All eleven methods answer `:structural`, and its docstring says
  "No kernel walker reads the kind". The notes of the kernel audit fixes record "No caller … is left", kept
  "for a later decision". At the same time thirteen places in generic code classify a step by its type, with a
  default arm for every other type: `_selection_child`, `_drop_terminal_cursor` and `_mutate_terminal_step!`
  in the selection layer; `_is_written_step` ([PathChain.jl:137](../../../source/kernel/operation/PathChain.jl#L137));
  `_copy_reference_step`; `_is_whole_part`, `_cut_output_place` and `find_whole_selected_index`
  ([WholeSelection.jl:75](../../../source/platform/focus/WholeSelection.jl#L75)); `_is_same_output_step` and
  `_find_output_list_target`; `_is_slot_accepting` and `_find_text_target`
  ([Clipboard.jl:376](../../../source/platform/clipboard/Clipboard.jl#L376)); and the printer of a reference as text.
- **Example:**
  ```julia
  # today: a whole part is "a field step, or a one-wide kernel range in a vector"
  step isa FieldReferenceStep && return true
  (step isa RangeReferenceStep && step.stop == step.start + 1) || return false
  # so a selected chart sample, `series[2].sample(5)`, is no whole part, and Alt+Right does nothing

  # after: the step answers, and each of the thirteen places asks
  get_reference_step_kind(step, holder) === :part     # field, element, row, sample, drawn node
  get_reference_step_kind(step, holder) === :place    # caret, range of characters, point, region
  ```
- **Problem:** A step type of a higher package answers evaluation and nothing else, so it gets the default
  arm thirteen times. By reading: `compute_selection_walk` returns `nothing` for a selected sample
  ([SelectionWalking.jl:94](../../../source/platform/focus/SelectionWalking.jl#L94)), the clipboard refuses its slot, and a
  text caret is not moved in place. Each fix so far added a type test in one place.
- **Proposal:** Keep the seam and give it the answers that the generic code needs: a step reaches a part that
  the document holds, or names a place inside a value, or goes through a projection. A kernel range answers by
  its width and by what it stands on. The thirteen places read the kind. The rest of what a step can do
  (move with a splice, be written in place) becomes one more optional method each, with a default.
- **What goes away:** The thirteen type switches; the dead single answer `:structural`.
- **What stays:** Every behaviour of the two kernel steps. A domain step gains the walk, the copy and the ring
  of a whole part with one method.
- **Risk and open questions:** The kind of a kernel range depends on the holder (a string or a collection), so
  the function needs the holder as an argument. `ReferenceInterface.jl` was sealed when the audit ran. Step 5.4
  of the click plan changes what an introduced step evaluates to; the two changes should agree on the third
  kind.
- **Related plans:** `plan/pending/kernel-audit-fixes.md` (the note at line 429; decision open);
  `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` step 5.4 (in progress).
- **Check:** weakened; value after the check: low. The seam, its eleven methods and the audit note hold. But
  the thirteen places do not ask one question, so one kind does not replace them. I opened eight.
  `_selection_child` asks for the child, which is evaluation (RS-1). `_mutate_terminal_step!` and
  `_copy_reference_step` ask "is this step written in place" and are methods by type already.
  `_is_written_step` asks about a splice. `_is_same_output_step` compares two steps without the direction.
  `find_whole_selected_index` and `_find_output_list_target` match the shape `.field[i]`, which is a pattern
  and no classification. Only about four ask "a part or a place": `_is_whole_part`, `_cut_output_place`,
  `_drop_terminal_cursor` and `_is_slot_accepting`. Of these, `_cut_output_place` has no document at hand (its
  comment says so), so a kind that needs the holder can not serve it. So "the thirteen type switches go
  away" is too much: the proposal is one kind for about four places and three more optional methods. The
  steps that would gain are few: the two row steps of RS-6 and the text range of RS-2; if those two findings
  go ahead, no step of a higher package is left that names a part. The proposal also goes against the
  direction of a rule of the owner (2026-10-02, "we only introduce new reference steps if we must"): it makes
  a new step type cheaper, where RS-6 removes two. The example holds by reading: Alt+Right does nothing on a
  selected chart sample. What stays true and small: `get_reference_step_kind` has one answer and no reader,
  and the audit note leaves its removal open.

### RS-6 A row of a columnar document is the element step

- **Kind:** redundant · **Value:** low · **Effort:** small · **Confidence:** medium
- **Principle:** 7. The owner's rule for references: fields, an index and a position first; no new step
  unless it is needed.
- **Today:** Two domains each define a step with one field, `index`: `ChartSampleReferenceStep`
  ([ChartSampleReferenceStep.jl:4](../../../source/domain/chart/ChartSampleReferenceStep.jl#L4)) and
  `SequenceChartRowReferenceStep` ([SequenceChartRowReferenceStep.jl:29](../../../source/domain/sequencechart/SequenceChartRowReferenceStep.jl#L29)).
  Each registers the same builder and the same matcher for the DSL, and evaluates through an accessor of its
  domain ([ChartDocument.jl:863](../../../source/domain/chart/ChartDocument.jl#L863),
  [SequenceChartDocument.jl:914](../../../source/domain/sequencechart/SequenceChartDocument.jl#L914)). The reason given is
  right: a column of a hundred thousand rows must not become that many cells, so no document stands behind a
  row.
- **Example:**
  ```julia
  # today
  ConcreteReference(FieldReferenceStep("events"),
      ConcreteReference(SequenceChartRowReferenceStep(row), EmptyReference()))    # events.row(7)
  # after: the table answers an index, and the path uses the kernel step
  Base.getindex(events::SequenceChartEvents, row::Integer) = get_event_row(events, row)
  @reference(chart, events[row])                                                  # events[7]
  ```
- **Problem:** The kernel element step already means "the i-th item of a sequence" and evaluates
  `document[i]` ([ReferenceStep.jl:218](../../../source/kernel/reference/ReferenceStep.jl#L218)). The two domain steps
  carry about 90 lines of the same registration, can not be written with `@reference` after a typed node (the
  comment at [SequenceChartDocument.jl:928](../../../source/domain/sequencechart/SequenceChartDocument.jl#L928) says so),
  and a read of a part through `ReferencedDocument` extends its path with the kernel step only.
- **Proposal:** The series and the three tables answer `getindex` with the row. Their paths use `[i]`.
- **What goes away:** Two step types, two files, four DSL registrations.
- **What stays:** A row is still no document and no cell. A click on a sample still selects it.
- **Risk and open questions:** The selection writer must treat `[i]` on such a document as the end of the
  routing: `_selection_child` reads the item and stops when it is no document, so by reading it does. With
  RS-5 this finding is smaller: a domain step would then be a full step, and the gain is only the 90 lines.
- **Related plans:** none found.
- **Other area:** domains (chart, sequence chart).
- **Check:** confirmed-with-corrections; value after the check: low. I read both step files (32 and 58
  lines, the same registration) and the two evaluations. The finding follows a rule of the owner
  (2026-10-02: "we only introduce new reference steps if we must because the current steps cannot represent
  what is needed"; the column step of the data frame went for this reason). The correction is in the
  proposal: the same rule names the shape, a field and an index ("propose a field; a computed, read-only
  container is fine"), so the path is `events.rows[7]` and not `getindex` on the table document. With
  `getindex` on the document two things get worse. `_is_whole_part`
  ([WholeSelection.jl:75](../../../source/platform/focus/WholeSelection.jl#L75)) counts a one-wide range as a whole
  part only when its holder is a vector, a tuple or a collection document, so a selected row would be no
  whole part any more. And `_is_slot_accepting` ([Clipboard.jl:376](../../../source/platform/clipboard/Clipboard.jl#L376))
  takes every `RangeReferenceStep` for a slot of a list, so a paste or a cut on a selected row would be
  tried against the table; today the own step type gets the default arm and the clipboard refuses. The
  read-only container must refuse a write. No plan covers it.

### RS-7 The child documents of a node have one list

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high for the three lists,
  medium for the consequence
- **Principle:** 6 and 7. [DocumentWalk.jl:4](../../../source/kernel/document/DocumentWalk.jl#L4) states the aim: "There is
  exactly one traversal."
- **Today:** Three functions answer "which documents does this node hold, and by which step":
  1. `walk_document` with a `DocumentWalk` in the document layer. A node controls it with `is_field_walked`,
     `is_walk_opaque` and `is_element_collection`. The searches use it.
  2. `child_reference_steps(node)` in the operation layer
     ([Operations.jl:717](../../../source/kernel/operation/Operations.jl#L717)), an open function with methods for
     `CellVector` and `ObjectField`. It skips view state fields and does not ask `is_field_walked`.
     `find_document_path`, "next hole", the outline and `set_output_tree_path_computations!` use it.
  3. `_child_document_refs(node)` in the focus slice ([Focus.jl:11](../../../source/platform/focus/Focus.jl#L11)), private.
     It skips `selection` and `mouse_target` by name, opens a `CellVector` field into field and index pairs,
     and asks neither `is_field_walked` nor a method of list 2. The Tab walk, the Alt+arrow walk,
     `follow_output_selection!` and `find_output_node_path` use it.
- **Example:**
  ```julia
  # today: a link says "a search does not go through me"
  is_field_walked(::Link, name::Symbol) = name !== :target        # LinkDocument.jl:40
  # the search obeys; the Alt+arrow walk and find_document_path read `target` all the same

  # after: one list, with the walk as the rule
  for (steps, child) in get_child_documents(node; walk = DocumentWalk())
  ```
- **Problem:** A document type that controls how it is walked must say it up to three times, and nothing
  tells its author about lists 2 and 3. By reading, Alt+Down on a selected `Link` whose target is a document
  enters the target, and a path found by identity can go through a link.
- **Proposal:** One function gives the child documents of a node with the steps to each, under a
  `DocumentWalk`. It lives where steps can be built, beside `search_references`. `child_reference_steps` and
  `_child_document_refs` become calls of it with the walk they need.
- **What goes away:** The body of `_child_document_refs` and of the default `child_reference_steps`, the
  `CellVector` and `ObjectField` methods, about 60 lines, and the third place to register.
- **What stays:** The Tab order, the Alt+arrow order and the cycle guard of the focus walk.
- **Risk and open questions:** The three lists may differ on purpose in one case that I did not find; the
  click test of the pending plan would show it. The order of fields must stay the order of today.
- **Related plans:** `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred;
  it changes what a stop is, not how children are listed). Added by the check: kernel audit L13-3, an open
  question at `plan/pending/kernel-audit-fixes.md:2585`, covers the second list.
- **Check:** confirmed-with-corrections; value after the check: medium. The three lists and their rules
  hold. `walk_document` asks `is_field_walked` and never enters the selection or the mouse target.
  `child_reference_steps` skips every view state field of the type (`is_view_state_field(T, name)`).
  `_child_document_refs` skips only `selection` and `mouse_target` (`is_view_state_field(name)`) and makes one
  child with two steps for `field[i]`. The `Link` case holds by reading: `_walk_children`
  ([SelectionWalking.jl:135](../../../source/platform/focus/SelectionWalking.jl#L135)) reads `_child_document_refs`,
  which gives `.target`. The correction: a plan covers the second list, and the report did not name it.
  Kernel audit L13-3 recommends to delete `child_reference_steps` and its `CellVector` method and to use
  `search_references`, by the rule `PAR-SEARCH-DONT-WALK`; the owner has not answered it. Since that audit
  two more callers came, [OutputPaths.jl:87](../../../source/kernel/projection/OutputPaths.jl#L87) and
  [OutlinePaths.jl:181](../../../source/platform/outline/OutlinePaths.jl#L181), so its fix is no longer complete.
  The third list, in the focus slice, has no plan. What the one function must keep, or the Tab order
  changes: the focus walk enters a declared view state field that holds a widget, and it stops at a plain
  `Vector`, which `walk_document` enters.

### RS-8 One clipboard document that holds a list

- **Kind:** partial-feature · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism for every list), and the concept of view state in `concepts.md`: what a view
  keeps of how it shows the data belongs to a view document.
- **Today:** The clipboard is a wrapper document around a window. There are two: `ClipboardSlice` holds one
  stored document, `ClipboardCollection` holds a list ([ClipboardDocument.jl](../../../source/platform/clipboard/ClipboardDocument.jl)).
  Each has its own projection, 740 and 182 lines. `make_clipboard_projection(…; collection)` builds one or the
  other ([ClipboardWrapper.jl:47](../../../source/platform/clipboard/ClipboardWrapper.jl#L47)). A window with the collection
  has three gestures: add, remove and show
  ([ClipboardCollectionToAny.jl:141](../../../source/platform/clipboard/ClipboardCollectionToAny.jl#L141)). It has no copy,
  cut, note or paste. A window with the slice has no list. The two projections are the only
  `mutable struct … <: Projection` in `source/`
  ([ClipboardSliceToAny.jl:88](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L88),
  [ClipboardCollectionToAny.jl:30](../../../source/platform/clipboard/ClipboardCollectionToAny.jl#L30)): each keeps "which
  child is shown" in a cell of the projection object. `clipboard.md` records the cost: "The general sweeps skip
  it, because its display cell keeps state between tests." A flag `text` adds a third mode, which only two
  tests turn on (`ClipboardTest.jl:367`, `:972`). Each of the five verbs starts with the same three-way branch
  ([:466](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L466), [:500](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L500),
  [:561](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L561), [:582](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L582),
  [:633](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L633)).
- **Example:**
  ```julia
  # today: a host chooses one of two clipboards
  make_clipboard_document(document)                      # copy, cut, note, paste, show; one stored document
  make_clipboard_document(document; collection = true)   # add, remove, show; no paste

  # after: one clipboard; the newest entry is what a paste takes
  @document struct Clipboard <: ClipboardDocument
      content::Document
      entries::CellVector = CellVector()
      shown::Symbol = :content           # view state: :content or :entries
  end
  ```
- **Problem:** The list of copies does not combine with copy and paste. A second window on the same
  projection object would share the flag. The branch on what the selection names is written five times, so a
  new kind of target (a value, added on 2026-11-06) is added in each verb.
- **Proposal:** One clipboard document with a list of entries and a view state field. One immutable
  projection. One function resolves what the selection names into a target (a whole document, a value, a range
  of text), and the five verbs take that target. With RS-2 a range of text has one form, and the `text` flag
  goes.
- **What goes away:** `ClipboardCollection`, `ClipboardCollectionToAny.jl` (182 lines), the two mutable
  projections, the `text` flag and its two functions, four of the five copies of the branch.
- **What stays:** All seven gestures of the slice, and add, remove and show of the list, now in one window.
  The toggle stays a cell write. The system clipboard bridge is not touched.
- **Risk and open questions:** What a paste takes when the list holds several entries (the newest, or the
  selected one while the list is shown) is a small product decision. The gallery option
  `clipboard_collection = true` changes.
- **Related plans:** `plan/done/clipboard-to-t.md` (done; it set the wrapper outside the view);
  `plan/pending/select-a-widget-and-paste-it-into-a-tab.md` (in progress; its clipboard steps are done).
- **Check:** confirmed; value after the check: medium. Every cited line holds: the two wrappers, the two
  `mutable struct … <: Projection` (the only two under `source/`), the three gestures of the collection, the
  five verbs that begin with the same branch, the two tests of `text = true`, the sentence in `clipboard.md`.
  One more fact for the finding: `ToggleClipboardSliceOperation`
  ([ClipboardSliceToAny.jl:170](../../../source/platform/clipboard/ClipboardSliceToAny.jl#L170)) and
  `ToggleClipboardCollectionOperation` ([ClipboardCollectionToAny.jl:98](../../../source/platform/clipboard/ClipboardCollectionToAny.jl#L98))
  hold the projection object as a field and write its cell. So this operation writes no data, and the
  assistant or a test needs the projection object to make it. No document and no plan gives a reason for
  two wrappers; the collection is used only by the gallery option, two examples and the tests. Two limits.
  What a copy does to the list (it adds an entry, or it replaces the newest) is new behaviour that the owner
  decides, so the part with no open question is the view state field in the document and the one function
  that resolves the target. And the `text` flag does not go by RS-2 alone, because `_find_text_kind` refuses
  a field that holds a `TextBlock` (see the correction in RS-2).

## Covered by plans

- One step type for a part that a view drew (`ProjectionReferenceStep` and `OutputReferenceStep` as one model):
  `a-click-reaches-the-innermost-part-in-every-view.md`, decision P2 and step 5.4, in progress.
- The rules of a plain click, an Alt+click and an Alt+double click, and the private copies of the whole-part
  rule in 28 readers: the same plan, decisions D1 to D10 and steps 5 and 6, in progress.
- The selection follows an insert or a delete: `an-insert-moves-the-paths-after-it.md`, pending, not started
  (RS-1 says where its code should go).
- A range of sibling nodes in a syntax tree: `syntax-tree-selection.md`, in progress.
- Named selections and named highlights: `named-paths-in-a-document.md`, tentative (RS-1 is its base).
- Tab and the arrows as one walk with stops: `tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md`,
  deferred by the owner.
- A header, a cell and a row of a table as parts of their own: `the-work-that-the-forward-image-found.md`, paused.
- A view names the domain part under a point: `a-view-names-the-domain-part-under-a-point.md`, pending.
- A graph gives its vertices the mouse target: `a-graph-lights-the-part-under-the-pointer.md`, pending.
- Back and forward between a definition and its uses: `back-and-forward-between-a-definition-and-its-uses.md`, deferred.
- The left walk that stalls on introduced text: `left-motion-stalls-on-introduced-text.md`, in progress.
- The pattern language in the kernel with three matchers, and the rules seam with no method: kernel audit L11-10.
- A caret on a collection selects the next element: kernel audit L12-1.
- A new operation that carries a path needs three methods: kernel audit L13-2 and L13-8.

## Examined and sound

- Focus is the selection. The focus slice holds no state and names no widget type; a domain opts in with
  `is_focusable_document` and `is_selection_walk_stop`.
- The empty path is a whole part and `nothing` is no selection. Every walk and every mapper keeps the two apart.
- `ReplacePathOperation` is the one family for the selection and the mouse target on the way back; a
  projection that only maps a path needs no code for the second kind.
- The forward side names the kinds of path once (`_get_output_path_computations`), so a printer that calls
  `make_output_path_cells` wires every kind.
- Type checkpoints live on the nodes of a path, not as steps; `set_selection!` makes every stored path
  canonical and fails before it writes a cell.
- The dormant selection is a wrapper value that reads as `nothing` to code that does not ask for it. This
  keeps every reader written against a plain reference right.
- The link interface: three functions for a link type, three more with defaults for its face; `MarkdownLink`
  and `RstReference` plug in with no change in the platform. A search stops at a link by a rule of the link.
- `DocumentLocator` and `ReferencedDocument` are two things on purpose: an address that is resolved at each
  read, and a part with the path that reached it, which a write never stores.
- The system clipboard is read on a task and never in a reader; the one write chain for the process is right
  because the system clipboard is one.
- The text of a widget has its mouse and key selection written once in `DrawnTextLine.jl`, and it borrows the
  key table of the text slice. This is the owner's settled decision, and the code follows it.
- A table names its parts with field and index steps only (`rows[r]`, `columns[c]`, `column_headers[c]`).
- The clipboard reads only its own `selection`, because every write of the live selection starts at the root.
- The Tab walk guards cycles by identity, which a lazy list with `prev` and `next` needs.

## Check of the report

A second agent tried to refute each finding at commit 3a9b4fae4. It read the cited code, counted again with
grep, and read the plans and the documents that give a reason. It ran no Julia. The note of each check is
the list item **Check** under its finding.

| Id | Verdict | Value in the report | Value after the check | The main point |
| --- | --- | --- | --- | --- |
| RS-1 | confirmed-with-corrections | high | medium | The owner chose the two chains on 2026-09-29 (Q4, "the selection code stays"); the finding is the open step of the tentative plan. New and true: the splice plan would write a second map of a splice. |
| RS-2 | weakened | high | medium | `get_flat_range` and `get_flat_caret` join the forms for every text stage already; the structural form is kept on purpose; the kernel range on a block makes one character the same value as an element. |
| RS-3 | confirmed-with-corrections | high | medium | Step 5.4 of the click plan built `follow_widget_output!` as the one call; what is left is the kernel walker with 11 callers. The six calls of the example can not become one. |
| RS-4 | confirmed | medium | medium | Counts hold within two or three. A clean-up of helpers. |
| RS-5 | weakened | medium | low | The thirteen places ask at least five different questions; about four ask "a part or a place". It makes a new step type cheaper, against the direction of the owner's rule on new steps. |
| RS-6 | confirmed-with-corrections | low | low | Follows the owner's rule on new steps. The path should be a field and an index (`events.rows[7]`), not `getindex` on the table document. |
| RS-7 | confirmed-with-corrections | medium | medium | Kernel audit L13-3 covers the second list and was not named; the third list has no plan. |
| RS-8 | confirmed | medium | medium | Also: the two toggle operations hold the projection object. What a copy does to the list is the owner's decision. |
