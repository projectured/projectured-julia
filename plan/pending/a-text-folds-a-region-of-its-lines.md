# A text folds a region of its lines

> **Kind:** plan · **Status:** pending, 2026-10-07. The owner decided T1 to T5 on
> 2026-10-07; §7 holds the steps. Steps 1 and 2 are done on the branch
> `text-gutter`; steps 3 and 4 wait for `SyntaxToText` to emit lines. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [syntax.md](../../documentation/package/platform/syntax/syntax.md),
> [a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md),
> [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md),
> [text-domain-kit.md](text-domain-kit.md)

## 1. The goal

The owner's words (2026-10-07), about what a line number counts (D4 of the
gutter plan): "there are two folds, one is the syntax fold, the other is a text
line region fold, the former cannot count the line numbers as if it would not
be folded but the latter can, for that the text domain should also support
folding and the syntax can be asked to emit foldable text regions".

So:

- **A syntax fold** is what exists: a closed syntax node prints no children, so
  its lines are not in the text, and the numbers below it change.
- **A text fold** is new: the text holds every line, and a closed region of
  lines hides all its lines but the first one in the view. The numbers count the
  hidden lines too, so the numbers below a text fold do not change.
- **The syntax can be asked to emit text regions**: for a collapsible node, the
  syntax prints its children and marks their lines as a region, in place of a
  syntax fold.

## 2. What other tools do

- **VS Code.** A `FoldingRangeProvider` of the language gives ranges of lines
  (a start line, an end line, a kind). The editor folds a range: it hides the
  lines after the start line, and the line numbers skip them.
- **CodeMirror 6.** The language marks foldable nodes (`foldNodeProp`) or gives
  a `foldService`; the fold state is a set of folded ranges in the state of the
  editor. A folded range shows a placeholder widget.
- **IntelliJ.** A `FoldingBuilder` of the language gives fold regions, and the
  folding model of the editor collapses them, with a placeholder text such as
  `{...}`.
- **Emacs.** `hideshow` and `outline` make the lines of a block invisible; the
  text stays in the buffer.

All of them divide the work as the owner does: the language says which regions
can fold, and the text editor folds them.

## 3. What exists

- **The syntax fold.** `SyntaxNode` and `SyntaxCollapsible` carry `collapsed`.
  A domain shares the cell of its own field with the node (JSON, XML, Markdown,
  reStructuredText, Book), so the state is in the document and undo records it.
  `SyntaxCompoundToText` prints no children for a closed node, draws an optional
  marker glyph and an ellipsis, and turns a click on either into
  `ToggleCollapseOperation(node)`. Ctrl+. makes a `ToggleCollapseOperation` with
  no target, which the syntax stage resolves to the innermost collapsible node at
  the caret ([collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md)).
- **A decorator that drops lines.** `TextFiltering` keeps only the lines that
  match a pattern. Its IO map keeps the input index of each output element, and a
  box on a dropped line has no image
  ([TextFiltering.jl](../../source/platform/text/TextFiltering.jl)).
- **Lines.** `TextLine` exists, but no projection makes one yet; the gutter plan
  has `SyntaxToText` emit lines in its step 4.
- **The text has no fold.** No text document or projection knows a region of
  lines.

## 4. Requirements

- **F1 Hide, not remove.** A closed region hides its lines but the first one.
  The lines stay in the text, so `TextLineNumbering` counts them, and a copy of
  a range over a closed region holds them.
- **F2 Show the fold.** The first line of a region shows a triangle in the fold
  lane of the gutter, open or closed. The first line of a closed region shows a
  placeholder at its end, such as `…`.
- **F3 Nest.** Regions nest, and a closed region hides the regions inside it.
- **F4 One a line.** At most one region starts on a line: the outermost, as in
  VS Code. So `[{` on one line gives the region of the array. The syntax fold is
  richer here (the owner, 2026-10-07): "the syntax domain document can absoletely
  have multiple foldable regions starting in the same line, so it's more complex
  than the text fold anyway". The inner node of such a line has no text region;
  T4 says what a builder that asks for text regions does with it.
- **F5 The syntax gives regions.** `SyntaxCompoundToText`, when its builder asks,
  makes a text region over the lines of each collapsible node, and the closed
  state of the region is the `collapsed` cell of the node, so the state stays in
  the document and undo records it.
- **F6 The caret.** The caret never stands in a hidden line, and Up and Down step
  over a closed region. A caret that an edit or a search puts into a hidden line
  opens the region (later).
- **F7 Lazy lists.** A region is found from its first line, never from the head
  of a list, because a lazy list counts from its head.
- **F8 Keys.** Ctrl+. folds and opens the region at the caret, as it does a
  syntax node. Fold all and open all come later.

## 5. The two folds side by side

| | syntax fold | text fold |
| --- | --- | --- |
| where the state is | `collapsed` of the syntax node, shared with the domain | the same cell, through the region that the syntax emits |
| the hidden lines | not printed, not in the text | in the text, not in the view |
| the numbers below | change | do not change |
| the cost of a closed fold | nothing is printed | the lines are printed, not laid out |
| the marker | inline, before the open delimiter | in the fold lane of the gutter |

A builder chooses one of them for a view. A large document folds cheaper with
the syntax fold, and a view of code wants stable numbers from the text fold.

## 6. Questions

To take one at a time.

- **T1 How a region is in the text. Decided (a), the owner, 2026-10-07:** a
  property of the first line of the region.
- **T2 Where the hidden lines leave the view. Decided (a), the owner,
  2026-10-07:** a decorator, `TextFolding` (tentative), after the numbers.
- **T3 The fold mark. Decided (a), the owner, 2026-10-07:** `TextFolding` fills
  the `fold` field of the gutter and takes the click and Ctrl+.
- **T4 How the syntax is asked. Decided (a), the owner, 2026-10-07:** a keyword
  of `SyntaxCompoundToText` chooses one kind of fold for a view.
- **T5 The placeholder. Decided (b), the owner, 2026-10-07:** the region can
  carry a placeholder, and `…` stands when it carries none.

### T1 How a region is in the text

**Decided (a), the owner, 2026-10-07: a property of the first line.** `TextLine`
gets a field that holds nothing or a region: the count of the lines after this
one that the region holds, and its `collapsed` cell. The names are tentative.

- **(a) A property of the first line.** `TextLine` gets a field, such as
  `fold`, that holds nothing or a region: the count of the lines after this one
  that the region holds, and its `collapsed` cell. A region is found from its
  first line forward, so a lazy list works (F7). F4 holds by construction: a line
  holds one region. The count is the work of the stage that makes the region,
  which prints the lines; a text edited by hand must keep the count when a line
  is split or joined inside the region.
- **(b) An element that holds its lines.** A region is an element of the block,
  such as `TextRegion(lines, collapsed)`, which holds lines and inner regions.
  Nesting is the structure, and an edit inside a region stays inside it with no
  count. But the path of a span gets one more level, and every reader of the
  lines, the flat offsets, `TextToGraphics`, the decorators and `TextToString`,
  must walk a tree of lines.
- **(c) A list of regions beside the lines.** `TextBlock` gets a list of regions
  by the index of their first and last line. An index into a lazy list counts
  from the head and moves when the head moves, and every added line moves the
  indices after it, so it fails F7.

My recommendation was (a), because a region is then local to its first line, as
the gutter is (D3 of the gutter plan), and the syntax, which makes the regions in
a view of code, prints the lines and knows their count. The count that an edit
by hand must keep is the cost; a text of plain lines with folds of its own is not
in this plan.

### T2 Where the hidden lines leave the view

**Decided (a), the owner, 2026-10-07: a decorator after the numbers.**
`TextFolding` drops the lines that a closed region hides, as `TextFiltering`
drops lines, and its reader steps the caret over them. `TextLineNumbering`
stands before it in a chain.

**Facts.** The geometry-free half of the text reader, the `@gestures TextBlock`
table, moves the caret by flat offsets over the elements, and a hidden line is
in the elements of the block. A decorator reads a key with `read_gesture` of its
input block. `TextFiltering` drops whole lines with a table of the input index of
each output element, and a box on a dropped line has no image.
`TextLineNumbering` counts the lines that it gets, so it must stand before the
place where the hidden lines leave.

- **(a) A decorator, such as `TextFolding`, after the numbers.** It drops the
  lines that a closed region hides, as `TextFiltering` drops lines, with the same
  kind of table. The numbers are already in the gutter of each line, and the
  gutter goes with its line, so the numbers that stay skip the hidden ones. Up
  and Down step over a closed region, because the hidden lines are not in the
  output. Its reader must also make Left and Right step over them: a motion key
  read against its input would move the caret into a hidden line, so it reads a
  motion key against its output. It is also the stage that knows every region
  and its state, which T3 and T5 need. The layout does not change.
- **(b) The layout.** `TextBlockToScrollLayout` lays out no hidden line. No new
  stage, but the hidden lines stay in the flat offsets that the gesture table
  moves the caret over, so the table, the geometry half of the reader and the
  layout each learn the regions.

My recommendation was (a), because the text already drops whole lines in one
decorator in this way, the fold then stays in one stage, and the order of the
chain says that the numbers count the hidden lines. The rule of the order goes in
the guide: `TextLineNumbering` before `TextFolding`.

### T3 The fold mark

**Decided (a), the owner, 2026-10-07: `TextFolding` fills the `fold` field.** It
puts the triangle on the first line of each region, turns a click on it into
`ToggleCollapseOperation(region)`, and gives an untargeted one, from Ctrl+., the
innermost region around the line of the caret.

**Facts.** A stage fills its field of the gutter by name (D10 of the gutter
plan). A click on a mark goes first to the projection of the mark; when it gives
no operation, the layout selects the mark, and the stage that filled the field
answers in its click reader (§5.4 of the gutter plan). `ToggleCollapseOperation`
holds the part that it flips as an object, and `evaluate_operation` flips
`target.collapsed`. One with no target, which Ctrl+. makes, is given its target
by "whichever projection owns the collapse state": the innermost collapsible
part around the selection
([Operations.jl](../../source/kernel/operation/Operations.jl)). A stage before it
passes an operation that has a target unchanged. The `collapsed` cell of a region
that the syntax makes is the `collapsed` cell of the node (F5).

- **(a) `TextFolding` fills the `fold` field.** It knows every region of its
  input and whether it is closed, so it puts the open or the closed triangle in
  the gutter of the first line of each region. A click on the triangle becomes
  `ToggleCollapseOperation(region)` in its click reader. An untargeted one, from
  Ctrl+., gets as its target the innermost region around the line of the caret,
  so the syntax stage before it passes it on. The flip writes the cell of the
  node, so the domain holds the state and undo records it. The regions can come
  from any stage, and the stage that folds is the stage that shows the fold.
- **(b) The stage that makes a region fills the field.** `SyntaxCompoundToText`
  knows its node and puts the triangle on its first line, and a click becomes
  `ToggleCollapseOperation(node)` as a click on its inline marker does today. But
  a region from another stage shows no triangle, and two stages share one
  feature: one shows the fold and another one hides the lines.

My recommendation was (a), because one stage then does the whole text fold: it
hides the lines, shows the triangle, and takes the click and the key. It uses
the operation that exists, with a region as its target.

### T4 How the syntax is asked, and two folds on one line

**Decided (a), the owner, 2026-10-07: one kind of fold for each view.** A keyword
of `SyntaxCompoundToText` chooses the syntax fold or text regions. With text
regions, the outer node keeps the region of a line that two nodes start, and the
inner node has no fold in that view.

**Facts.** A builder configures `SyntaxCompoundToText` today with its indent,
its two marker glyphs and the rule of which nodes carry a marker. A closed node
prints no children. A region is a property of its first line, and a line holds
one region (T1, F4). Several collapsible nodes can start on one line, such as
`[{` (the owner's remark under F4). A child prints its lines first, and its
parent then joins the first line of the child into its own open line, by the
join rule that step 4 of the gutter plan adds; so the child does not know, when
it prints, that its first line will start the region of its parent.

- **(a) One kind of fold for each view.** A keyword of `SyntaxCompoundToText`
  chooses the syntax fold or text regions. With text regions, each collapsible
  node prints its children always, and gives its first line a region over its
  lines, whose `collapsed` cell is its own. When the join puts the first lines of
  two nodes on one line, the region of the outer node stays, and the inner node
  has no fold in that view, as in VS Code. A builder that wants every node to fold
  takes the syntax fold.
- **(b) Text regions, and the inner node keeps the syntax fold.** Every node
  stays foldable. But the inner node must know, when it prints, that its first
  line will start the region of its parent, and only the parent knows that after
  the child prints; so the parent must tell the child through the printer
  context, or the child must print both ways.
- **(c) A line holds a list of regions,** the outermost first. The join appends
  the regions of the child to those of the parent. The triangle in the gutter
  folds the outermost region of its line, and Ctrl+. folds the innermost region
  around the caret, so the inner node folds too, with stable numbers. It changes
  T1 from one region on a line to a list, and F4 goes.

My recommendation was (a). It is the simplest, and it is what VS Code does; the
owner's remark says that the syntax fold is the richer one, and a builder that
needs it chooses it. (c) is the way to grow later, if the inner node of a line
must fold with stable numbers.

Step 4 of the gutter plan, `SyntaxToText` emits lines, comes first: a region is
a property of a `TextLine`.

### T5 The placeholder

**Decided (b), the owner, 2026-10-07: the region can carry a placeholder.** The
stage that makes a region can give it any document, which `TextFolding` puts at
the end of the first line of the closed region; with none, `…`. The syntax gives
`…}` and lets the region hold the line of the close delimiter, so a closed node
reads `{…}` with both folds.

**Facts.** A closed syntax fold reads `{…}` on one line: `SyntaxCompoundToText`
puts an ellipsis, in a style that its builder gives (`ellipsis_style`), between
the open and the close delimiter, and a click on it opens the node. CodeMirror and
IntelliJ show a closed region as `{…}` too. A text region hides the lines after
its first line, a count that its maker gives (T1). A decorator can add a span
that has no input, as `WordWrapping` adds a soft break.

- **(a) `TextFolding` adds `…` at the end of the first line** of a closed region,
  a span with no input in a style from its builder, and a click on it opens the
  region. The line after the region shows as any line does, so when a region
  holds the lines of the children of a node, its close delimiter stays on the
  next line: `{ …` and then `}`.
- **(b) The region can carry a placeholder.** The stage that makes a region can
  give it a placeholder, any document, which `TextFolding` puts at the end of
  the first line when the region is closed, and `…` when it gives none. The
  syntax then gives `…}` and lets the region hold the line of the close
  delimiter, so a closed node reads `{…}` as with the syntax fold. The cost: one
  more field of a region, and the `}` of the placeholder is a copy, on which no
  caret stands.
- **(c) No placeholder.** Only the triangle in the gutter shows that a region is
  closed.

My recommendation was (b), because a closed node then reads the same with both
folds, as in CodeMirror and IntelliJ, and the stage that knows the delimiter
gives it, as D2 lets a mark be any document. With no placeholder from its maker,
a region shows `…`, which is (a).

## 7. Steps (tentative)

Each step on its own commit, each with its test. Step 3 needs `SyntaxToText` to
emit lines (D7 of the gutter plan).

1. ✅ **Done (2026-10-07, branch `text-gutter`). The region of a line.** `TextLine` gets its `fold` field: nothing or a
   region with the count of the lines after the first, the `collapsed` cell and
   an optional placeholder (T1, T5). Test: the text document tests.
   *What the implementation found:* the region is the document `TextFold`
   (`line_count`, `collapsed`, `placeholder`), and `TextLine.fold` holds it. A
   fold is no candidate of the insertion, as a line and a gutter are not.
2. ✅ **Done (2026-10-07, branch `text-gutter`). `TextFolding`.** It drops the lines that a closed region hides, with a table
   of the input index of each output element, and maps a reference through it
   (T2). Its reader steps the caret over a closed region with all four arrows. It
   fills the `fold` field of the gutter with the triangle, puts the placeholder at
   the end of the first line, and turns a click on the triangle or on the
   placeholder, and Ctrl+., into `ToggleCollapseOperation(region)` (T3). An
   example of hand-made lines with nested regions and numbers. Test: a test of
   its own, with `TextLineNumbering` before it, which asserts that the numbers
   after a closed region stay.
   *What the implementation found:* the flat runs of `TextFiltering`
   (`_make_flat_runs`) count the implied break of a `TextLine`, so one run for
   each line shown maps a caret, a range and a box; a path into a line that is no
   text selection, such as one into its gutter, maps by the index of the line.
   The triangle is a `TextBlock` whose text follows `collapsed`, filled into the
   gutter as `TextLineNumbering` fills the numbers. The defaults are the text
   glyphs ▾ and ▸, because the icon table is in the widget slice, which the text
   can not name; a builder can give the Lucide chevrons and their font. A click
   that selects a caret past the end of the input line of a closed fold is on its
   placeholder. A write of a value of a part of a line, such as a widget in the
   gutter, maps by the index of the line. The example `text_folding_example` is a
   small JSON text with a fold of the object and a nested fold of the list, whose
   placeholder `…],` closes the list on its line; its renderer sends a block of
   lines to the chain and a block of spans, the text of a mark, to the text.
   Rendered to a PDF: open, the list closed (the next number is 8), and the
   object closed (`{…}`). Test: `test_text_folding()`, 18 assertions; the
   printer, reader and navigation tests of the example, 2637, 225 and 100.
3. ~~**The syntax emits regions.**~~ **Done 2026-10-08, branch `text-gutter`.**
   A keyword of `SyntaxCompoundToText` chooses text regions (T4): each
   collapsible node prints its children and gives its first line a region whose
   `collapsed` cell is its own and whose placeholder is `…` and its close
   delimiter. The join keeps the region of the outer node on a line that two
   nodes start.

   What was built: `SyntaxCompoundToText(; text_folds = true)`, and
   `SyntaxToText(; text_folds)`. A node then prints its children whether it is
   collapsed or not, in the layout and in every mapper (`_is_folded_by_syntax`).
   The `TextFold` of a node is made once for each print of the node
   (`_make_node_fold`): its `collapsed` is the cell of the node, so the toggle of
   `TextFolding` toggles the node; its `line_count` and its `placeholder` are cells
   that read the result of the splice. The splice puts it on the first line of the
   node, in place of a fold of a child that starts there; the join of a child
   keeps the fold of the open line and takes the fold of the first line of the
   child when the open line has none (rule 5 of Q2 of `text-domain-kit.md`, for
   folds; the join of gutters waits for the first producer of a gutter of syntax,
   step 8 of the gutter plan).

   **A choice made in the work (2026-10-08): only a collapsible node that
   indents is a region.** An inline node, such as the entry `"lanes": [` of a JSON
   object, starts on the same line as its value; as the outer node it would win
   that line, and with no closing delimiter of its own a closed entry would show
   `"lanes": […` with no `]`. A node that puts its children on lines of their own
   is a region of lines, so the line holds the fold of the value. Test:
   `SyntaxToTextTest.jl`, "SyntaxToText text folds".

   **Known:** a closed region hides its last line whole, so a separator that the
   parent puts after the closing delimiter, such as the `,` of `],`, does not show
   on the folded line: `"lanes": […]`.
4. **A view of code with text folds:** `SyntaxCompoundToText` with regions →
   `TextLineNumbering` → `TextFolding` → `TextBlockToScrollLayout` in a
   `WidgetScrollPane`. The testing guide and the text design document say the
   order: the numbers before the fold.
5. **Later, not in this plan:** a caret that an edit or a search puts into a
   hidden line opens its region (F6); fold all and open all; a list of regions
   on a line (T4 c).
