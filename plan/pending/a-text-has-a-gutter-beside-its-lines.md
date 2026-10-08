# A text has a gutter beside its lines

> **Kind:** plan · **Status:** pending, 2026-10-08. The design is decided. Steps 1,
> 2, 3 and 7 are done on the branch `text-gutter`, and step 5 for hand-made lines;
> steps 4 to 6 wait for `SyntaxToText` to emit lines, and step 8 is open. The owner decided D1, D2, D3, D8 and D10 on
> 2026-10-06, and D4, D5, D7 and D11 on 2026-10-07, and D6 through T3 of the
> fold plan; D5 through
> [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md),
> and D4 led to
> [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md).
> The names are tentative. ·
> **Stands on:** [text.md](../../documentation/package/platform/text/text.md),
> [syntax.md](../../documentation/package/platform/syntax/syntax.md),
> [widget.md](../../documentation/package/platform/widget/widget.md),
> [projection-system.md](../../documentation/package/kernel/projection-system.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
> [text-domain-kit.md](text-domain-kit.md)

## 1. The goal

The owner's words (2026-10-06): "we need a gutter for the text domain which can
contain additional content related to text lines in a text document. for
example, line numbers, line markers, collapse/expand markers, etc. arbitrary
content per line. The gutter should be automatically aligned vertically with the
text and follow its scroll."

So:

- A **gutter** is a column at the left of a text. It shows content for each
  line: a line number, a marker, a fold triangle, or any other small content.
- The content of a line stands at the height of that line, also when the lines
  have different heights and when a line wraps.
- The gutter moves with the text when the text scrolls up or down.
- A text without gutter content looks as it does today.

The requirements that this serves:
[PR-FOCUS-AND-REORGANIZE](../../documentation/requirement/accepted-requirements.md#pr-focus-and-reorganize)
(fold a part and open it again),
[PR-COMBINE-CONTENT-KINDS](../../documentation/requirement/accepted-requirements.md#pr-combine-content-kinds)
and [PR-ARBITRARY-NESTING](../../documentation/requirement/accepted-requirements.md#pr-arbitrary-nesting)
(any content in a gutter).

## 2. The words of this plan

| Word | Meaning |
| --- | --- |
| line | one `TextLine` of a `TextBlock`: the unit that a number counts |
| row | one visual line on the screen; a wrapped line has more than one row |
| gutter | the column at the left of the text; on one line, the document that the line holds in its `gutter` field |
| lane | one column of the gutter, such as the numbers or the fold triangles: one field of the gutter type |
| mark | the content of one lane on one line: any document, or nothing |

## 3. What a professional editor gives

CodeMirror 6, VS Code (Monaco), IntelliJ, Eclipse and Emacs all give these. The
plan must meet each one; §6 orders the work.

- **R1 Lanes.** The gutter is a row of lanes: markers, numbers, folds, changes.
  The order of the lanes is the same on every line of a view.
- **R2 Width.** A lane has the same width on every line, and the layout of a
  line finds it without a look at the other lines, because a text of a lazy list
  (`ListNode`) can have no end in either direction. A lane has an alignment: a
  number stands at the right, an icon in the middle. A new digit does not move
  the text.
- **R3 Content.** A mark is content of any kind: text, a glyph, an icon, an
  image, a widget, a value of a domain. Most lines have no mark in most lanes.
- **R4 Vertical place.** A mark stands on the first row of its line: a text on
  the baseline of that row, an icon in its line box. The other rows of a wrapped
  line have no mark. Some marks, such as a change bar, cover all the rows of the
  line.
- **R5 Scroll.** The gutter moves with the text up and down, in the same frame.
  It does not move when the text scrolls left or right.
- **R6 Folds.** A line that a fold hides has no row in the gutter. The first
  line of a fold shows the closed triangle.
- **R7 Pointer.** A click on a mark acts on its line: it folds, sets a
  breakpoint, or selects the line (a click on a number). A rest of the pointer
  shows the tooltip of a mark. The pointer is an arrow over the gutter, not an
  I-beam.
- **R8 Not text.** A key that moves the caret of the text never takes it into
  the gutter. A copy of a range of the text never holds a mark. The selection
  band of the text does not cover the gutter. A mark whose content can be edited
  holds a selection of its own, as any nested part does.
- **R9 Follow the line.** A mark stays with its line when lines are added or
  removed above it.
- **R10 Local.** An edit in one line draws the gutter of that line again, and no
  other row, unless the width of a lane changes. A long text lays out only the
  rows that the view shows.
- **R11 Numbers.** A line number counts the lines of the text. A text fold
  hides lines that the text holds, so it does not change the number of the lines
  below it; a syntax fold removes its lines from the text, so it does (D4). The
  number of the line of the caret is drawn brighter.
- **R12 Theme.** The gutter has its own background, a rule between it and the
  text, and its own colors and fonts from the theme.

## 4. What exists

**The text layout knows the lines.** `TextToGraphics` groups the block into
lines (`_line_groups`) and gives each line a sub-canvas with its own `y`, its
height and its first baseline
([TextToGraphics.jl](../../source/platform/text/TextToGraphics.jl), `print_document`).
A content edit lays out only its own line again (printer locality). The IO map
holds one `SegmentCoordinate` for each drawn piece, with the line box of its row.

**`TextLine` exists, but nothing makes one.** A `TextLine` holds spans and an
`indentation`, which is a property of the line and not a span, so no caret lands
in it ([text.md](../../documentation/package/platform/text/text.md)). The
`TextToGraphics` layout and the caret helpers know it. No projection in
`source/` emits one: `SyntaxToText` emits a `TextString("\n")` between lines, so
a syntax text arrives at `TextToGraphics` as one line group with many rows.
`SyntaxToText` emitting `TextLine` is step 3 of Phase 3 of
[text-domain-kit.md](text-domain-kit.md), decided on 2026-08-12 and not done.
`WordWrapping` and `TextHighlighting` pass a `TextLine` through unchanged, so a
`TextLine` does not wrap today.

**`TextLineNumbering` puts the number in the text.** It adds a span
`"<n> | "` before each line
([TextLineNumbering.jl](../../source/platform/text/TextLineNumbering.jl)). So the
number is in the caret space, every reference map must step past it, it moves
left with the text, and the second row of a wrapped line starts under the
number. Only its own example and its tests use
it. No view in `source/` shows line numbers, also not the Julia code view
(`JuliaToSyntax → SyntaxToText → TextToGraphics`).

**The fold marker is in the text.** `SyntaxCompoundToText` draws an optional
marker glyph before the open delimiter of a collapsible node, and an ellipsis
for a closed node. A click on either becomes `ToggleCollapseOperation(node)`:
`TextToGraphics` makes a caret, and the click reader of `SyntaxCompoundToText`
(`_resolve_click`) finds that the caret is on its own marker
([SyntaxToText.jl](../../source/platform/syntax/SyntaxToText.jl)). A closed node
prints no children.

**No marker exists.** No breakpoint, diagnostic or bookmark is drawn beside a
text line. The process domain has breakpoints, which it draws as a style of the
node.

**The table is the close analog.** `WidgetTable` has a header column beside its
rows. The table owns the panes of its parts and the one scroll offset of all of
them: the pane of the header column reads only the `y` of that offset, so it
moves up and down with the rows and not left and right
([WidgetTableParts.jl](../../source/platform/widget/WidgetTableParts.jl)). One
projection lays out both parts, so their rows agree by construction.

**A row reads the first baseline of a child.** `find_first_baseline(iomap)` is a
declared protocol through which a row reads the baseline of a child to align it
([Baseline.jl](../../source/platform/graphics/Baseline.jl)).

**A text scrolls as the content of one scroll pane.** A file tab is
`WidgetScrollPane(make_file_tab(path, wrap))`
([DocumentFile.jl](../../source/platform/fileformat/DocumentFile.jl)). The pane
keeps `scroll_position` on its document, and its printer puts the content in a
`GraphicsViewport` that clips it and moves it by the offset on both axes
([WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl),
`WidgetScrollPaneToGraphicsCanvas`). A wheel writes the offset with a
`ReplaceViewStateOperation`, so undo does not record a scroll. A text of a lazy
list scrolls by pixels in the same way; nothing moves its head. No code scrolls
the caret into view.

**A container gives a value to its content through the printer context.** A
table puts `:line_spacing` into the context of its cells with `with_property`,
and `TextToGraphics` reads it with `get_property`
([PrinterContext.jl](../../source/kernel/projection/PrinterContext.jl)).

## 5. The model (recommended, not decided)

### 5.1 The gutter is a property of the line

`TextLine` gets a field `gutter`: one document, or `nothing`. The gutter is a
property of the line, as the indentation is. So it is not in the caret space, it
is not in the flat string, and no caret lands in it (R8). A line keeps its gutter
when lines are added above it, because the gutter is in the line and not at an
offset (R9).

```julia
@document struct TextLine <: TextDocument
    elements::CollectionDocument = CellVector()
    indentation::Int = 0
    gutter::Any = nothing        # any document that the recursion prints to graphics
end

# The gutter of the platform, for a view of code. A view can bring its own type.
@document struct TextGutter <: TextDocument
    marker::Any = nothing        # a breakpoint, a diagnostic
    number::Any = nothing        # the number of the line
    fold::Any = nothing          # the triangle of a fold
end
```

The names are tentative.

**The gutter is a document, and its projection lays it out (D3, the owner).**
Each field of a gutter type is a lane, and each field holds a mark or nothing.
The projection of the gutter type, which the recursion chooses, decides the order
of the lanes, their widths and their alignment, and draws them. For `TextGutter`
it is `TextGutterToGraphics`, which takes its widths from the scaled theme, as a
text projection takes its styles. No width, alignment or order is in the
document, because they are presentation. A view that wants other lanes, such as
a log with a time and a level, brings its own gutter type and its projection.

The same projection prints the gutter of every line, so the lanes stand in
columns on every line, and each print reads only its own line. So a text of a
lazy list with no end works, and an edit in one line lays out only that line
(R2, R10).

**The width of a lane does not depend on the other lines.** The projection of a
gutter must give a lane the same width on every line, or the text of two lines
starts at two different `x`. `TextGutterToGraphics` (tentative) makes a lane as
wide as the larger of its width in the theme and its mark, and clips nothing. A
stage that wants a lane to grow gives every mark of the lane the same width:
`TextLineNumbering` pads each number to the digits of the largest number of a
finite text, as it does today, and the owner of a lazy text pads to the width
of its own numbers.

**A mark holds any document (D2, the owner).** `TextBlockToScrollLayout` prints the
gutter with `print_child(recursion, gutter, ctx)`, and the projection of the
gutter prints each mark in the same way, so the recursion chooses each
projection by its type, as for any other child (PAR-RECURSE-VIA-PRINT-CHILD,
PR-ARBITRARY-NESTING). A `TextBlock` with a number, a glyph of the icon font, an
image, a widget and a value of a domain are all marks. In the natural renderer
the recursion is `NaturalToGraphics`, which draws almost any document, and
`ChainingProjection` gives that recursion to each of its stages, so
`TextBlockToScrollLayout` has it.

The text stages between the stage that fills a field and `TextBlockToScrollLayout` copy
the gutter and never read its marks. So a mark of any domain goes through
`WordWrapping` and the other decorators unchanged.

### 5.2 The stage that knows a mark fills its field

Each projection fills the fields that it alone knows, on the lines of its own
output, and passes on the fields of its input. No projection reads the output of
another one, and no walker visits the lines (PAR-DECIDE-LOCALLY).

**A stage fills its field by name (D10, the owner).** A stage gets the name of
its field as a keyword, such as `TextLineNumbering(; field = :number)`. For each
line, it copies the gutter of its input line with that field replaced, with
`copy_document_fields`, and gives the other fields their cells as they are, so
they stay reactive. A line with no gutter gets a new one of the type that the
builder gives the stage, `TextGutter` by default. A gutter type that has no such
field is an error of the builder.

| Field of `TextGutter` | Who fills it | What it knows |
| --- | --- | --- |
| `number` | `TextLineNumbering`, a text decorator | the count of the lines, the caret line |
| `fold` | `TextFolding`, a text decorator ([a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md)) | every region of its input, and if it is closed |
| `marker` | a domain stage, through the syntax node (later) | a breakpoint, a diagnostic |
| a field of its own type | the owner of a long lazy text | its own numbers, because a lazy list counts from its head |

`TextLineNumbering` becomes simple. Its output line is its input line with the
`number` field filled. The caret space does not change, so its forward and
backward maps of a caret and of a box are the identity, and only a path into its
own field is its own.

### 5.3 The layout places the gutter

`TextBlockToScrollLayout` (D11) lays out the lines with the layout code of
`TextToGraphics`, so it alone knows where each line is, and it alone places the
gutter. Nothing else needs the geometry of a line, and nothing must keep two
parts in step (R5 by construction).

- **The output is a `ScrollLayout`** ([a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)): the gutter canvas is its left edge,
  and the canvas of the lines, with the caret and the selection band, is its
  center. Each gutter row stands at the `y` of its line, and the two canvases
  have the same height, so their rows agree by construction. In a
  `WidgetScrollPane` the gutter stays at the left edge; in any other place the
  chain ends with `LayoutToGraphics`, which draws the gutter at the left of the
  lines. `TextBlockToScrollLayout` gives it, and `TextToGraphics` stays as it is (D11).
- `TextBlockToScrollLayout` prints the gutter of each line once with `print_child` and
  keeps its IO map, keyed by the line, so a new layout reuses it
  (PAR-STABLE-IOMAP-IDENTITY). The extent of its output canvas is its size.
- The output of a gutter is aligned as a row aligns its children: when it draws
  text, it stands with `find_first_baseline` of its IO map on the first baseline
  of its line; when it draws no text, it stands in the middle of the line box of
  the first row (R4). Both use the existing protocol of
  [Baseline.jl](../../source/platform/graphics/Baseline.jl). Inside the gutter,
  its own projection aligns its marks.
- The layout of the gutter of a line reads only that line (R2, R10).
- `TextBlockToScrollLayout` maps a reference into a gutter forward by the IO map of that
  gutter, after the step to the node of the gutter in its output
  (PAR-DELEGATE-ONE-LEVEL).
- The gutter canvas is as wide as the gutter of one line, the first line or the
  head of a lazy list, because the projection of a gutter gives every line the
  same width (D3). It reads no wrapped content, so the width that the pane
  offers can read it with no cycle (Q4 of the scroll plan). A line whose gutter
  is `nothing` draws an empty row.
- The gutter canvas draws the arrow pointer over itself, and the I-beam stays
  over the lines (R7).
- The text of a lazy list gives a left edge that is a lazy list of gutter rows,
  with the same head as its lazy list of paragraph canvases, as the header
  column of a list table stands beside its rows. The pane limits the offset by
  the ends of the list of the center.

### 5.4 A click on a mark

A click on a mark goes down by position and its operation goes up, as for any
other child. No new event and no new channel is needed:

1. `TextBlockToScrollLayout` finds the gutter at the point, moves the point into the
   frame of the gutter, and gives the click to the reader of the gutter through
   its IO map (PAR-NO-GLOBAL-ROUTING). The projection of the gutter gives it to
   the mark at the point in the same way. Each lifts the operation that it gets
   with `reroot_operation` by its own step, so the operation of a mark arrives
   with the path `.elements[i].gutter.number…` (PAR-DELEGATE-AND-LIFT). So a
   widget in a mark answers its own click: a check box switches, a button gives
   its operation.
2. When the mark gives no operation, `TextBlockToScrollLayout` returns a
   `ReplaceSelectionOperation` to the mark, with the `MouseClick` as its gesture,
   as a click on the fold marker does today.
3. Each stage maps the path back. A stage that did not fill the field passes it
   to its input, because the line maps to a line and the field to the same field.
4. The stage that filled the field maps the path to its own input when the mark
   is a part of that input: a mark that shows a field of a domain node edits that
   field, as any edit does. When the mark is a document that the stage made, the
   path has no pre-image, and the stage answers in its click reader in place of
   it: `SyntaxCompoundToText` with `ToggleCollapseOperation(node)`, and
   `TextLineNumbering` with a selection of the whole line in its input.
5. A path into a mark that no stage answers has no pre-image, so the click does
   nothing.

A key goes along the selection. When the selection is in a mark, `TextBlockToScrollLayout`
gives the key to the reader of that mark and lifts the answer, so a mark whose
content can be edited takes the keys. A key that the text reads never moves the
caret of the text into the gutter, because the gutter is not in the caret space.

A rest of the pointer travels by position in the same way, so the tooltip of a
mark needs no more than the mouse target of today.

### 5.5 The decorators keep the gutter

| Projection | What it does with the gutter |
| --- | --- |
| `WordWrapping` | wraps inside a `TextLine` and keeps its gutter; the gutter stays on the first row |
| `TextFiltering` | keeps or drops a line with its gutter |
| `TextHighlighting`, `SelectionInverting` | copy the gutter |
| `TextFirstLine` | keeps the gutter of the first line |
| `TextToString` | ignores the gutter, so a copy never holds a mark (R8) |
| the console backend | prints the gutter as text before each line (later) |

### 5.6 Folds and the numbers

There are two folds (D4, the owner). A **syntax fold** is a closed syntax node,
which prints no children, so its lines are not in the text and the numbers
below it change. A **text fold** is a closed region of lines, which the text
holds and the view hides, so `TextLineNumbering` counts the hidden lines and the
numbers below it do not change. The syntax can be asked to emit a text region
for a collapsible node in place of a syntax fold. The design of the text fold is
[a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md).

### 5.7 Scroll

The gutter is the left edge of a `ScrollLayout`, which `WidgetScrollPane` takes
apart (D5, [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)).

- **Up and down.** The pane moves the left edge and the center by the same `y`,
  so the gutter stays beside its lines (R5).
- **Left and right.** The pane moves the center by the `x` and the left edge not
  at all, so the gutter stays at the left edge of the pane (R5).
- **The width.** The pane offers its content the width of the center viewport,
  so a text wraps at the width that the person sees.
- **A click** in the gutter reaches `TextBlockToScrollLayout` as a plain click, in the
  frame in which `LayoutToGraphics` places the parts. Its reader finds the part
  at the point with the function of the `layout` slice, in a pane and at the end
  of a chain alike.
- **The background** of the gutter is the background of the gutter canvas, from
  `TextTheme` (R12). The lines never pass under the gutter, because each part has
  a viewport of its own.

## 6. Steps (tentative)

The order of the work, each step on its own commit, each with its test.

1. ✅ **Done (2026-10-07, branch `text-gutter`). The gutter of a line.** It needs step 1 of the scroll plan, `ScrollLayout`.
   `TextLine.gutter`, `TextGutter`, `TextGutterToGraphics`,
   `TextBlockToScrollLayout` with the layout code that it shares with
   `TextToGraphics`, the layout of
   §5.3, the click and the key of §5.4, and an example of a block of hand-made
   lines with numbers, markers and a widget in a mark. The example and the test
   print through a dispatcher, because a mark needs a recursion (D8). Test:
   `test_text_to_graphics()` and a new gutter test.
   *What the implementation found:* `TextBlockToScrollLayout` prints the lines
   with the `TextToGraphics` that it holds and reads two things that its IO map
   now gives: the line groups, each of which names its `TextLine` (`line`), and
   the cells of each line (`line_cells`). A row of the gutter stands at
   `y + baseline of the line − baseline of the gutter`, or in the middle of the
   line when the gutter draws no text. A line whose gutter is `nothing` has no
   row. The left edge is an arrow region for the pointer. A mark whose mapper
   answers a point with the point itself, as a graphics shape does, is the part
   at the point, and a path that ends at the node of a mark names the mark
   itself. `text` depends on `layout` now, with a bare `using ..LayoutModule`, as
   the layering guard asks. The gutter of the pane needed the band rule of the
   scroll plan: a gutter is as high as the lines, whose height follows the
   offered width. The example `text_gutter_example` is seven lines of code in a
   scroll pane, with numbers as `PrimitiveNumber` marks, a breakpoint dot and a
   check box; its marks are of other types than `TextBlock`, because its own
   dispatcher sends a `TextBlock` to `TextBlockToScrollLayout`. Rendered to a
   PDF, scrolled by (60, 40), the gutter moves up only and stays at the left
   edge. Not done here: a lazy text has no gutter, and the gutter has no theme
   (R12). Test: `test_text_gutter()`, 29 assertions; `test_printer`,
   `test_reader` and `test_position_navigation` of the example, 2011, 225 and
   146; the text tests and the layering guard pass.
2. ✅ **Done (2026-10-07, branch `text-gutter`). Line numbers in the gutter.** `TextLineNumbering` on a block of lines puts
   a `:number` mark. A click on a number selects the line.
   *What the implementation found:* `TextLineNumbering` takes `field` and
   `gutter_type` and keeps its span mode for a block of spans, which has no line
   to hold a gutter. On a block of lines each output line shares the spans, the
   indentation, the selection and the part under the pointer of its input line,
   and has a gutter that `copy_document_fields` makes from the input gutter with
   every cell given, the number replaced. The number is a `TextBlock` whose text
   is a cell of the count of the lines, so a new line pads every number again
   and makes no line again. A path maps to the same path, but a path into the
   numbers, which has no pre-image; a selection of a number becomes the flat
   range of its line. Test: `test_text_gutter()`, 37 assertions with the
   numbering; `test_text_line_numbering()` and `test_inline_image_caret()` pass
   unchanged.
3. ✅ **Done (2026-10-08), as far as this plan goes. The decorators keep the gutter** (§5.5). `WordWrapping` wraps inside a
   line, and its list of the lines does not depend on the width, so a change
   of the width wraps each line again and makes no new list. The scroll pane
   offers the width of its center viewport, which reads the width of the
   gutter, so the width of the gutter must not depend on the wrap (Q4 of
   [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)).
   **Decided (b), the owner, 2026-10-07:** the decorators learn lines in
   [text-domain-kit.md](text-domain-kit.md), next to `SyntaxToText` emitting
   lines; this step keeps the gutter, which each decorator does by passing a line
   through, and `test_text_gutter()` asserts it for `WordWrapping`,
   `TextHighlighting`, `TextFiltering`, `SelectionInverting` and `TextFirstLine`.
   The options were (a) all of it here and (c) only `WordWrapping` here.
   *Found before the work, 2026-10-07.* Every
   decorator keeps the gutter of a line today, because each one passes a
   `TextLine` through unchanged. But none of them knows lines: `WordWrapping` does
   not wrap inside a line, `TextHighlighting` marks no match inside a line,
   `TextFiltering` takes a block of lines as one line, because it ends a line only
   at a `TextNewline`, and `TextFirstLine` does the same. To wrap inside a line,
   `WordWrapping` must put soft breaks inside a `TextLine`, against the rule that
   a line holds no break, and `TextToGraphics` must break a row at a soft break
   inside a line and map a caret across it; the flat runs of the decorators know
   only spans at the top of a block. This is the work that
   [text-domain-kit.md](text-domain-kit.md) names for its Phase 3: the remaining
   consumers learn lines. Its escape, `TextLineFlattening`, would drop the
   gutter, so it does not serve here.
4. **`SyntaxToText` emits lines: not a step of this plan (D7).** It is step 3
   of Phase 3 of [text-domain-kit.md](text-domain-kit.md), with the join rule of
   an inline child that it names. Steps 5 and 6 wait for it.
5. **Fold triangles in the gutter** (done for hand-made lines by steps 1 and 2 of the fold plan; the rest waits for its steps 3 and 4): the steps of [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md).
   `TextFolding` fills the `fold` field.
6. **The Julia code view** shows numbers and fold triangles. **Decided (b), the
   owner, 2026-10-08: only the code of a Julia file in its tab.** The file view
   prints its code through `SyntaxToText(text_folds = true)` →
   `TextLineNumbering` → `TextFolding` → `TextBlockToScrollLayout`, inside the
   scroll pane of the tab; a Julia snippet that stands inside another document,
   such as a message or a value of a form, draws as before. The other option was
   (a), every Julia code view, also a snippet of one line; a snippet has no scroll
   pane of its own, and numbers on one or two lines say nothing.

   What was built: `FileToContent(; content)` prints and reads the content of a
   file with a projection of its own in place of the recursion. The Julia domain
   defines `make_graphics_projection(::Type{JuliaFile})` (the seam whose rows come
   before the row of `FileDocument`) as `FileToContent(; content =
   make_julia_file_code_projection(...))`: `JuliaToSyntax` →
   `SyntaxToText(text_folds = true)` → `TextLineNumbering` → `TextFolding` →
   `TextBlockToScrollLayout`, with the theme and the code line spacing of the code
   view, and a recursion that prints the marks. Test: `test_julia_file_view()`.

   Rendered and checked (2026-10-08): a file in a scroll pane shows the numbers
   and the open triangles of `module`, of a function and of an `if`. **Known
   until the plan [a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md)
   does Julia:** a docstring is a leaf value that holds `'\n'`, so it is one line
   with rows, and the closing fence `"\n\"\"\"\n"` is a leaf value too, so the
   line of the function after it joins that line. A file of 16 lines with one
   docstring shows the numbers 1 to 9.

   **Found after the landing (2026-10-08):** an editor with settings opens a file
   with a history around its content, so the content of a `JuliaFile` is an
   `UndoBuffer`, and the view of the file had no row for it: the warm-up of the
   application and "every format draws" failed (`ApplicationTest.jl`). Now
   `FileToContent(; content, accepts)` takes its own projection only for a content
   that `accepts` answers `true` for, and the general recursion for any other; the
   Julia view accepts the code or a history that holds the code, and its recursion
   prints the history with `UndoBufferToAnyProjection`, so the history prints the
   code with the view of the file and the gutter shows under it. Test: the history
   cases of `test_julia_file_view()`.
7. ✅ **Done (2026-10-07), by the scroll plan. Scroll** (§5.7): steps 1 and 2 of the scroll plan; then a file tab of code
   keeps its gutter at the left edge.
8. **Markers.** A lane of markers keyed by a line, then marks that a domain
   node gives through its syntax node.

### The order across the plans (D7)

1. The steps on hand-made lines, in any order between the plans: steps 1 and 2
   of [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md), steps 1 to 3 of this plan, and steps 1 and 2 of [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md). Step 1 of this
   plan needs step 1 of the scroll plan.
2. Step 3 of Phase 3 of [text-domain-kit.md](text-domain-kit.md): `SyntaxToText`
   emits lines, with the join rule of an inline child.
3. The steps that need lines: step 3 of the scroll plan, steps 5 to 7 of this
   plan, and steps 3 and 4 of the fold plan.

## 7. Considered and not proposed

- **A column beside the text that reads the line boxes of the text.** A gutter
  container would read the rows from the IO map of its text child, through a
  protocol like `find_first_baseline`. It needs no change to the text documents,
  and it works with a block that has no lines. But the content of a lane must
  then come from outside the chain: a fold lane must find every collapsible node
  and map it forward to a row, which is a central walk over the parts
  (PAR-DECIDE-LOCALLY). It is also a projection that reads the output of another
  one.
- **A grid of lines.** Each line a row of a grid, with the marks in cells before
  it. A text becomes many texts: Up and Down, a selection over lines and the
  caret overlay all break.
- **Numbers as spans in the text** (today's `TextLineNumbering`). It fails R5,
  R8 and R4 for a wrapped line, and each reference map must step past it.
- **A mark as a span of zero width in the flow**, as Emacs puts a margin string
  at a position. It works with every shape of block at once, also with
  `TextString("\n")` lines. But every reader of the flat offsets and every
  decorator must learn a new element of zero width, and it puts a property of a
  line into the flow of the spans, against "a line is a document"
  ([text-domain-kit.md](text-domain-kit.md)).

## 8. Decisions for the owner

Every decision is taken. A recommendation that I gave is marked as mine.

- **D1 Where the gutter content lives, and who places it. Decided (a), the
  owner, 2026-10-06:** a field of `TextLine`, placed by `TextToGraphics` (§5).
  Not chosen: (b) a container beside the text that reads the line boxes, and
  (c) a span of zero width in the flow (§7). The cost that comes with it: a
  syntax view gets a gutter only after `SyntaxToText` emits lines (step 4).
- **D2 What a mark holds. Decided (b), the owner, 2026-10-06:** any document
  that the recursion prints to graphics (§5.1). Not chosen: (a) a `TextBlock`
  only, which I had recommended because an icon and an image are already text
  content. The owner's words: "the lanes should be able to contain anything that
  can be recursively projected to graphics".
- **D3 Who sets the order, the width and the alignment of a lane. Decided,
  the owner, 2026-10-06: the gutter of a line is one document of a type, and the
  projection of that type lays out its fields as it wants** (§5.1). The owner's
  words: "why not just fields in a type laid out however the projection in the
  text to graphics wants?" So the order, the width and the alignment are
  presentation, in a projection, and none of them is in the document.
  How it came there, on the same day:
  (a) the builder gives `TextToGraphics` a list of lanes with their widths and
  alignments; (b) the builder gives the order, and each mark gives its alignment
  and a minimum width, and a lane takes the largest minimum of its marks; (c) the
  text theme holds the list of lanes. I recommended (b). **(b) is wrong** (the
  owner): "the text document can also be infinite using ListNode"; the largest
  minimum of a lane needs every line, and a lazy list has no last line. The owner
  then proposed (d): each line holds an entry for every lane, with its width, its
  alignment and its mark. I set (e) beside it: the block holds the lanes once.
  The owner took (d), and I asked how to order the entries (D9). The owner then
  replaced the entries with a gutter type and its projection, which keeps the
  reason for (d), each line complete on its own, and puts no presentation in the
  document.
- **D9 The order of the lanes. Withdrawn:** the projection of the gutter type
  decides it (D3). The options were a list of names from the builder, the order
  of the entries in the line, and a place from 0 to 1 on each entry, as the
  placement gravity of a ruler column in Eclipse.
- **D10 How a stage fills one field of a gutter that an earlier stage made.
  Decided (b), the owner, 2026-10-06.**
  The stages run in the order of the chain, and each makes its own output lines.
  A projection never writes into the output of another one, so a later stage
  makes a new gutter that holds the fields of the gutter of its input line and
  its own field. `copy_document_fields(policy, document; replacements...)` in
  [DocumentCopy.jl](../../source/kernel/document/DocumentCopy.jl) rebuilds a
  document of any type with named fields replaced, and it uses a cell that it gets
  as it is, so the other fields keep the cells of the input and stay reactive.
  (a) One type: every text stage knows `TextGutter` and makes a new one from the
  cells of its input and its own field. A view with other lanes needs its own
  stages, which know its own type.
  (b) Any type, by the name of the field: a stage gets the name of its field as
  a keyword, such as `TextLineNumbering(; field = :number)`, and copies the
  gutter of its input with that field replaced. A line with no gutter gets a new
  one of the type that the builder gives the stage, `TextGutter` by default. A
  gutter type with no such field is an error of the builder.
  My recommendation was (b), because any stage then works with any gutter type,
  and the name of a field is already the API of a type (PAR-FIELD-NAMES-ARE-API).
- **D4 What a line number counts. Decided, the owner, 2026-10-07: the lines of
  the text, and there are two folds.** The owner: "there are two folds, one is the
  syntax fold, the other is a text line region fold, the former cannot count the
  line numbers as if it would not be folded but the latter can, for that the text
  domain should also support folding and the syntax can be asked to emit foldable
  text regions". The design of the text fold is [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md). The options were (a) the
  lines of the view, (b) the lines with every fold open, where the line of a
  closed syntax fold says how many lines it hides, and (c) the lines of the
  source file. I recommended (b); it made the syntax print the children of a
  closed node only to count them.
- **D5 Left and right scroll. Decided, the owner, 2026-10-07:** the gutter is
  the left edge of a `ScrollLayout`, and `WidgetScrollPane` takes it apart, so
  the gutter moves up and down with the lines and stays at the left edge (§5.7).
  The design is [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md), where the owner decided its six questions on 2026-10-07.
  How it came there: I offered (a) the scroll pane gives its `x` to its content
  as a property of the printer context, (b) two panes as the table, which needs
  a wrapper that splits the output of `TextToGraphics`, (c) a flag that keeps an
  element at its `x` in any viewport, as `position: sticky` in CSS, and (d) the
  gutter moves left with the text. I recommended (a); its limit was that a text
  which does not stand at the left of the content of its pane keeps its gutter
  at its place while the content beside it scrolls. The owner, 2026-10-06:
  "this is a serious issue, I like none of the options. I need to think about
  it, I would prefer the widget and graphics domain unchanged, no hacks". I then
  added (e), two projections of one text in two panes that share one offset,
  which lays out each line twice. The owner proposed the scroll component with
  a center, four edges and four corners in place of all of them.
- **D6 The fold marker. Decided, the owner, 2026-10-07, by D4 and by T3 of
  [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md):** the triangle of a text fold is in the fold lane of the gutter,
  and `TextFolding` fills it; the marker of a syntax fold stays inline. The
  options were (a) the gutter in place of the inline marker and (b) a choice of
  the builder.
- **D7 This plan and text-domain-kit. Decided (b), the owner, 2026-10-07:**
  text-domain-kit makes `SyntaxToText` emit lines, as its step 3 of Phase 3, and
  the three plans wait for it (§6, the order across the plans). **Facts.** The owner decided on
  2026-08-12 that [text-domain-kit.md](text-domain-kit.md) owns the change
  "`SyntaxToText` emits `TextLine`", and rejected a new plan for it: "that
  settles ownership, not direction". That plan also says that the join rule of an
  inline child is missing. The change is not done. Three plans now need it: this
  plan from its step 5, [a-text-folds-a-region-of-its-lines.md](../done/a-text-folds-a-region-of-its-lines.md) from its step 3, and [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md) in its step 3. These steps do
  not need it, because they work on hand-made lines: steps 1 to 3 of this plan,
  steps 1 and 2 of the fold plan, and steps 1 and 2 of the scroll plan.
  (a) This plan does it as its step 4, and text-domain-kit says so.
  (b) text-domain-kit does it as its step 3 of Phase 3, and this plan, the fold
  plan and the scroll plan wait for it at the steps above. Step 4 of this plan
  becomes a reference to it.
  My recommendation was (b), because the owner gave the change to
  text-domain-kit, and it serves more than the gutter: the indentation becomes a
  property of the line, and the decorators learn lines.
- **D8 A mark in a chain with no recursion. Decided (b), the owner,
  2026-10-06:** a chain that holds marks needs a recursion, and its builder
  gives one. `TextToGraphics` has no fallback of its own. A chain printed with
  `print_document(chain, document)` gives its stages `nothing` as the recursion
  ([ProjectionDefaults.jl](../../source/kernel/projection/ProjectionDefaults.jl)),
  as the examples and the tests of the text do. Then `TextToGraphics` can not
  print a mark. (a) `TextToGraphics` prints a mark whose content is a
  `TextBlock` with itself, and draws no other mark. (b) A chain that holds marks
  needs a recursion; the builder gives one, and a test prints through
  `NaturalToGraphics` or its own dispatcher. (c) `TextToGraphics` draws an empty
  box of the minimum width for a mark that it can not print. My recommendation
  was (b), because a fallback to itself decides in the text what the recursion
  must decide.

- **D11 Which projection gives a `ScrollLayout`. Decided (b), the owner,
  2026-10-07, named `TextBlockToScrollLayout`:** a projection of its own, which
  shares the layout code of `TextToGraphics`. The owner chose the name: its input
  and its output are one concrete type each, as in `TextBlockToString`,
  `PrimitiveStringToTextBlock` and the printers of the layouts, such as
  `HorizontalLayoutToGraphicsCanvas`. §5 names it where it does the work; D1 to
  D8 keep the name that they had when they were decided. A view of today must stay
  the same, and the type of an output must not change with the data, or a text
  whose first gutter appears later would switch its output from a canvas to a
  `ScrollLayout`. So the builder chooses it when it builds the chain (Q5 of the
  scroll plan).
  (a) A keyword of `TextToGraphics`: with it, the output is always a
  `ScrollLayout`, with an empty gutter for a line that has none; without it, the
  output is a canvas as today, and the gutter of a line is not drawn.
  (b) A projection of its own, such as `TextToScrollLayout`, which shares the
  layout code of `TextToGraphics`: the name of a projection says its output type,
  and `TextToGraphics` keeps one output type.
  My recommendation was (b), because a projection here is named by its input and
  its output, and a keyword that changes the output type breaks that name.

## 9. Risks

- Step 4 changes every reference map of `SyntaxToText`, which every syntax domain
  uses. The navigation sweeps and the printer locality test must stay the same.
- A new field on `TextLine` adds a cell to each line; a long text has many
  lines.
- A change of the width of a lane moves the text of every line that holds the
  lane, as in every editor at a new digit. The stage that gives the width
  decides when that happens.
