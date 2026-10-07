# A scroll pane keeps the edges of its content in view

> **Kind:** plan · **Status:** pending, 2026-10-07. The owner decided Q1 to Q6 on
> 2026-10-07 (§7); §8 holds the steps, which nobody started. The names are
> tentative. ·
> **Stands on:** [widget.md](../../documentation/package/platform/widget/widget.md),
> [graphics.md](../../documentation/package/platform/graphics/graphics.md),
> [projection-system.md](../../documentation/package/kernel/projection-system.md),
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
> [a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md)

## 1. The goal

The gutter of a text must move up and down with the text and must not move left
and right ([a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md),
D5). The owner rejected the four ways that plan offered: "I would prefer the
widget and graphics domain unchanged, no hacks".

The owner's words (2026-10-06): "how about a special scroll component or way of
operation or something which takes an object as content that is projected to
something which can have top/bottom left/right and center parts (plus corners
maybe) and the scroll works in a way that scrolls the center part in 4
directions and keeps the top/bottom left/right parts in sync and always on
screen. this could also be used by the widget table (not necessarily in this
plan)".

So:

- A content can have nine **parts**: a center, four edges and four corners.
- The scroll moves the center in all four directions.
- The top and the bottom edge follow the center left and right. The left and the
  right edge follow it up and down. The corners never move.
- The edges and the corners stay on the screen.
- The text uses it for its gutter: the gutter is the left edge, the lines are the
  center. The table can use it later for its header row, its header column and
  its corner.

## 2. The words of this plan

| Word | Meaning |
| --- | --- |
| part | one of the nine regions of a content: the center, an edge or a corner |
| center | the part that scrolls on both axes |
| edge | the top, the bottom, the left or the right part; it scrolls on one axis |
| corner | a part where two edges meet; it does not scroll |
| frame | a content that has parts |

## 3. What other tools do

- **Java Swing.** `JScrollPane` has a viewport, a row header (left), a column
  header (top) and four corners. The headers are viewports that follow the main
  viewport on one axis. A line-number gutter of a Swing text editor is usually
  the row header. `JTable` puts its own header into the column header of the
  scroll pane that holds it (`configureEnclosingScrollPane`), so the content
  gives a part to the pane.
- **Excel.** Freeze panes: the rows above and the columns at the left of a split
  stay on the screen, and the rest scrolls.
- **Flutter.** `TableView` pins a number of rows and columns.
- **Qt.** `QAbstractScrollArea.setViewportMargins` keeps a margin around the
  viewport, and a `QTableView` puts its header views there and moves them itself.
- **AppKit.** `NSScrollView` has a horizontal and a vertical ruler view.

The owner's model is the most general: four edges and four corners, where Swing
has two edges.

## 4. What exists

- **`WidgetScrollPane`** keeps `scroll_position` on its document. Its printer
  prints the content, takes its output as a `GraphicsCanvas`, and puts it in a
  `GraphicsViewport` that clips it and moves it by the offset
  ([WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl),
  `WidgetScrollPaneToGraphicsCanvas`). A wheel writes the offset with a
  `ReplaceViewStateOperation`.
- **`WidgetTable` builds the model by hand.** Its header row, its cells and its
  header column are three `WidgetScrollPane`s that share one offset, the
  `scroll_position` of the table. The header row reads the `x`, the header column
  the `y`, and the cells both. The table prints all the parts in one print, and
  the parts share cells for their sizes: the cells decide the width of each
  column, and the header row takes those widths
  ([WidgetTableParts.jl](../../source/platform/widget/WidgetTableParts.jl)).
- **`GraphicsViewport`** clips and moves a canvas. No backend needs a change to
  draw more of them.
- **The order of the slices.** `text` depends on `graphics` and not on `layout`
  or `widget`; `widget` depends on `layout` and `text`
  ([package-rules.md](../../documentation/rule/package-rules.md)). So a type
  that `TextToGraphics` names must be in `graphics` or in a slice below `text`.

## 5. Requirements

- **S1 Parts.** A frame has a center and up to four edges and four corners. Any
  part can be absent.
- **S2 One offset.** The center moves by both axes of one offset, the top and the
  bottom edge by its `x`, the left and the right edge by its `y`. The parts never
  disagree, because they read the same offset.
- **S3 In view.** The edges and the corners stay in the pane, and the center gets
  the rest of it.
- **S4 Sizes agree.** The left edge has the height of the center, and its rows
  stand beside the rows of the center: the lines of a text, the rows of a table.
  The top edge has the width of the center, and its columns stand above the
  columns of the center. The content that makes the parts makes them agree.
- **S5 Input.** A wheel over any part moves the one offset, so a wheel over the
  gutter scrolls the text. A click goes by position into the part under it.
- **S6 No end.** A content of a lazy list that has no end works, as the list form
  of a table does today.
- **S7 Elsewhere.** A frame that is not in such a scroll pane is drawn as one
  whole, with its edges around its center, and does not scroll.
- **S8 Unchanged.** The graphics types of today and the backends do not change,
  and no hack ties a pane to a part inside its content.

## 6. Questions

To take one at a time. Q1 is first, because the others depend on it.

- **Q1 Where the parts come from. Decided (b), the owner, 2026-10-07** (§7).
- **Q2 Where the type of a frame lives. Decided, the owner, 2026-10-07: the
  `layout` slice, as `ScrollLayout`** (§7.3).
- **Q3 The scroll component. Decided (a), the owner, 2026-10-07:**
  `WidgetScrollPane` learns a `ScrollLayout` (§7.4).
- **Q4 Sizes. Decided (a), the owner, 2026-10-07:** the pane offers its content
  the width of the center viewport (§7.5).
- **Q5 Elsewhere. Decided (a), the owner, 2026-10-07:** the builder decides, and
  a chain for another place ends with `LayoutToGraphics` (§7.2, §7.3).
- **Q6 Input. Decided (a), the owner, 2026-10-07:** the pane gives its content a
  point in the frame of the layout that puts the parts together (§7.6).

### Q1 Where the parts come from

The parts that must agree are made from one geometry: the gutter rows and the
lines come from one layout of the text (gutter plan, D1), and the header row and
the columns of a table from one decision of the widths.

- **(a) The content document is a frame.** A builder or a projection makes a
  document with nine fields, each a document. The scroll component prints each
  part on its own with its recursion, each into its own viewport. The table fits:
  its grids are separate prints that share cells for their sizes. A text fits
  less: the gutter and the lines are two prints, so the gutter lays out each line
  a second time to find where it is. And the text exists only inside a chain, so
  no builder holds it to make the frame; a stage of the chain must make it.
- **(b) One print gives the parts.** The scroll component prints its content
  once, and the output of that print is a frame: its fields are the graphics of
  the center, the edges and the corners. The text fits: `TextToGraphics` makes
  the gutter canvas and the lines canvas from one layout and puts them in the
  left edge and the center. The table fits too, because it prints its parts in
  one print today. The cost: such an output is not one canvas, so a place that
  expects one canvas needs the frame put together (Q5), and the type of the
  frame must be one that `TextToGraphics` can name (Q2).

My recommendation was (b), because the parts that must agree come from one
projection and one layout, which is what D1 of the gutter plan decided and what
the table does today. (a) separates the parts that must agree.

## 7. The model so far

### 7.1 One print gives a type of its own (Q1, the owner)

The owner, 2026-10-07: "perhaps it would be better to have a special type for
this one print step which the scroll pane can take apart and put into the right
graphics viewports with the right offsets".

So the content of the scroll pane prints to a type that exists only to carry
the parts from that one print to the pane:

```julia
# In the layout slice (Q2, §7.3).
@document struct ScrollLayout <: LayoutDocument
    center::Any                 # any document; from TextToGraphics, a GraphicsCanvas
    top::Any = nothing          # any document, or nothing
    bottom::Any = nothing
    left::Any = nothing
    right::Any = nothing
    top_left::Any = nothing
    top_right::Any = nothing
    bottom_left::Any = nothing
    bottom_right::Any = nothing
end
```

- **The pane takes it apart.** It puts each part in a `GraphicsViewport` of its
  own, at the place of that part in the pane, and moves each by the one offset:
  the center by `(-x, -y)`, the top and the bottom by `(-x, 0)`, the left and
  the right by `(0, -y)`, the corners not at all (S2). The left viewport is as
  wide as the left part, the top one as high as the top part, and the center
  gets the rest (S3).
- **No backend sees it.** The pane takes it apart before anything is drawn, and
  a `GraphicsViewport` and a `GraphicsCanvas` exist, so the graphics types and
  the backends of today do not change (S8).
- **The fields are the reference vocabulary** (PAR-FIELD-NAMES-ARE-API). A click
  in the left viewport goes by position into the left part, and the pane maps it
  to the output reference `.left…` of its content, so the projection that made
  the parts reads from the first step which part was clicked. A caret that the
  content maps forward to `.center…` is in the center viewport.
- **The content makes the parts agree** (S4). `TextBlockToScrollLayout` makes
  the gutter canvas and the lines canvas from one layout, with the same height and the same
  rows. The table, later, makes its header row from the widths of its cells, as
  it does today.

### 7.2 Q5 The special type where no scroll pane takes it apart

**Decided (a), the owner, 2026-10-07: the builder decides.** A chain that ends
in the special type is for a pane that takes it apart; a chain for any other
place ends with the projection that puts the parts together into one canvas.

**Facts.** The scroll pane takes the output of its content as a
`GraphicsCanvas` and fails on any other type. A layout reads the extent of a
child output that is no graphics as 0, so it draws nothing for it and gives no
error ([LayoutToGraphics.jl](../../source/platform/layout/LayoutToGraphics.jl),
`_child_w`). A wrapper that shows the output of its content as its own output,
such as a chain, a `RecursiveProjection` or a fault barrier, passes the type on
unchanged. A property of the printer context goes down to the whole subtree
([PrinterContext.jl](../../source/kernel/projection/PrinterContext.jl)).

So the type must reach only a pane that takes it apart, or something must turn
it into one canvas. A text with line numbers is useful elsewhere too, such as a
block of code in a page.

- **(a) The builder decides.** A chain that ends in the special type is for a
  pane that takes it apart. A chain for any other place ends with a projection
  that puts the parts together into one canvas, the edges around the center.
  Nothing looks through a stage and nothing goes down the context. The cost: a
  type of content that is shown both in such a pane and elsewhere needs two
  chains; and the special type in a plain layout shows nothing, with no error,
  unless the layout learns to report it.
- **(b) The chain always ends with one canvas, and the pane looks through.** The
  projection that puts the parts together ends every chain, so every place gets
  one canvas. The pane asks the IO map of its content, by a protocol such as
  `find_first_baseline`, for the parts, and draws them in its viewports in place
  of the one canvas. The cost: the pane draws the input of the last stage of its
  content in place of its output, and each part canvas stands in two trees, of
  which only one is drawn.
- **(c) The pane asks for parts in the context.** The pane puts a property into
  the printer context, and a text gives the special type only when it finds the
  property. The cost: the property goes down to the whole subtree, so a
  container between the pane and the text would get the special type, unless
  every such container removes the property.

My recommendation was (a), because the builder already chooses each stage of a
chain, and (a) adds no channel. (b) is near to a pane that rewrites the output
of its content, and (c) needs every container to know the property.

### 7.3 Q2 Where the special type lives

**Facts.** Three things name the type: `TextToGraphics` in the `text` slice,
which makes it; the scroll pane in the `widget` slice, which takes it apart; and
the projection that puts the parts together into one canvas (Q5), which every
builder of a chain for another place names. `text` depends on `graphics`, and
`widget` on `text` and `layout` ([package-rules.md](../../documentation/rule/package-rules.md)).
Code lives in the lowest package whose API it names (PAR-LOWEST-PACKAGE), and a
projection lives at or above the slices of its input and its output
(PAR-PROJECTION-PLACEMENT). The type names nothing but the kernel, and the
projection that puts it together names `graphics`.

- **(a) The `graphics` slice.** The type and the projection that puts the parts
  together are new files of `graphics`, beside `Baseline.jl`, which also exists
  only for what a container reads from a child. No graphics type of today, no
  projection of today and no backend changes, and no backend ever sees the new
  type, because a pane takes it apart and the projection turns it into a canvas.
- **(b) A new slice between `graphics` and `text`.** The `graphics` slice stays as
  it is. The cost: a new module of `ProjecturedPlatform`, a row in the table of
  [package-rules.md](../../documentation/rule/package-rules.md), its layering
  guard and its design document, for one type and one projection.
- **(c) The `text` slice**, beside its first maker. The type is not about text,
  and the table, in `widget`, would name a type of `text` for its header row.

My recommendation was (a). It is the lowest home that the rules give, and the
owner's concern, as I read it, was a change that the graphics types and every
backend must honour; an added type that no backend sees is not that.

**Decided, the owner's proposal, 2026-10-07: the `layout` slice, as
`ScrollLayout`.** The owner: "could it be in layout perhaps and call it
ScrollLayout?" It is better than (a) and (b):

- The `layout` slice places documents of any kind next to each other, and a
  `ScrollLayout` places nine parts: the edges around the center.
- **The projection that puts the parts together (Q5) is the printer of the
  layout.** `LayoutToGraphics` prints a `ScrollLayout` as one canvas, with the
  edges around the center, so no other projection is needed. A chain for a
  place with no such pane ends with `LayoutToGraphics`.
- A child of a layout is any document with a projection to a `GraphicsCanvas`,
  and the natural renderer prints a graphics document as itself
  (`GraphicsDocument => GraphicsToGraphics()` in
  [NaturalProjection.jl](../../source/platform/natural/NaturalProjection.jl)). So
  the canvases that `TextToGraphics` makes are children as they are. A table can
  also give a `ScrollLayout` of its grids, which are documents.
- Swing names the same thing so: `JScrollPane` places its viewport, its headers
  and its corners with a `ScrollPaneLayout`.
- **The cost: `text` depends on `layout`.** `layout` comes before `text` in the
  include order of `ProjecturedPlatform`, and none of the slices that `layout`
  depends on (Collection, Focus, Graphics, Projection) depends on `text`, so the
  edge makes no cycle. The row of `text` in the table of
  [package-rules.md](../../documentation/rule/package-rules.md) gets Layout, and
  the layering guard of the platform gets the edge.

### 7.4 Q3 The scroll component

**Decided (a), the owner, 2026-10-07: `WidgetScrollPane` learns a second way of
operation.** When the output of its content is a `ScrollLayout`, it takes it
apart; when it is a canvas, it works as today.

**Facts.** `WidgetScrollPane` holds `scroll_position` and `follow_end`. Its
printer prints the content and puts the output in one `GraphicsViewport`. Its
reader turns a wheel into a write of the offset, limits the offset by the extent
of the content or, for a lazy list, by the ends of the list, and leaves
`follow_end` when the person scrolls. The table makes three `WidgetScrollPane`s
that share one offset.

- **(a) `WidgetScrollPane` learns a second way of operation.** When the output of
  its content is a `ScrollLayout`, it takes it apart into a viewport for each
  part (§7.1); when it is a canvas, it works as today. One wheel, one offset, one
  `follow_end`, one place that limits the offset. Every pane of today keeps its
  behaviour. The change is in the printer and the reader of `WidgetScrollPane`.
- **(b) A new widget beside it**, which takes only a `ScrollLayout`.
  `WidgetScrollPane` does not change. The cost: the wheel, the limits of the
  offset, `follow_end` and the ends of a lazy list exist twice, or move into
  helpers that both share.
- The way of the table, several panes that share one offset, does not fit: one
  print gives the parts (Q1), and a builder can not split one output among
  panes.

My recommendation was (a), because the owner asked for "a special scroll
component or way of operation", and (a) keeps one scroll component with one set
of rules for the offset. A content that gives a canvas sees no change.

### 7.5 Q4 Sizes

**What follows from Q1 to Q3.** The pane prints its content once and gets a
`ScrollLayout` whose parts are canvases, each with its `w` and `h` cells. The
left column is as wide as the widest of the left edge and the two left corners,
the top row as high as the highest of the top edge and the two top corners, and
the same on the right and at the bottom. The center viewport gets the rest of
the pane. The offset is limited by the extent of the center less the extent of
the center viewport. The content makes an edge as long as the center on the axis
on which they move together (S4); the pane does not stretch it.

**Decided (a), the owner, 2026-10-07: the pane offers the width of the center
viewport**, and the extent of an edge must not depend on the offered width.

**The question was the width that the pane offers its content.** A text that wraps
reads the width from the printer context: `WordWrapping` reads the cell
`ctx.maximum_width`
([WordWrapping.jl](../../source/platform/text/WordWrapping.jl), `_wrap_width_cell`),
and the pane offers its content a cell on a clipped axis. But `WordWrapping`
runs before `TextToGraphics`, which makes the gutter, so the wrap does not know
how wide the gutter is.

- **(a) The pane offers the width of the center viewport.** The offered width is
  a cell: the width of the pane less the widths of the left and the right
  column, which the pane reads from the parts. A text wraps at what the person
  sees. The rule that comes with it: the extent of an edge must not depend on the
  offered width, or the cells make a cycle (PAR-ACYCLIC-CELLS). The width of a
  gutter depends only on its marks, so it holds when `WordWrapping` keeps the
  list of the lines independent of the width and wraps only inside each line,
  and `TextToGraphics` reads the width of the gutter without reading the
  wrapped content.
- **(b) The pane offers its whole width**, and the content takes its edges from
  it. `TextToGraphics` knows the width of the gutter, but `WordWrapping` before
  it does not. So a wrapped text is wider than the center viewport by the width
  of the gutter, and it scrolls left and right by that much.
- **(c) The builder gives the widths of the edges in advance**, from the theme,
  and the pane offers its width less those. No cycle can form. But a lane that
  grows at a new digit, as the numbers do, must then have its width fixed in
  advance.

My recommendation was (a), because only (a) wraps a text at the width that the
person sees with no width fixed in advance. Its rule is a rule of good printer
locality too: a change of the width wraps the lines again and does not make the
list of the lines again.

The height is the same question on the other axis: the pane offers the height
of the center viewport, less the top and the bottom row. Nothing wraps on that
axis today.

### 7.6 Q6 Input

**Decided (a), the owner, 2026-10-07: the frame of the layout that puts the
parts together.**

**Facts.** The pane gives its content a plain `MouseClick`, moved into the frame
of the content: it takes off the origin of the content and adds the scroll
offset (`_find_scroll_pane_local_point` in
[WidgetToGraphics.jl](../../source/platform/widget/WidgetToGraphics.jl)). A move
and a dwell go the same way. A wheel goes to the content first, and the pane
scrolls when the content gives no operation. A key goes to the content. A chain
gives an earlier stage the same gesture when a later stage gives no operation
([Chaining.jl](../../source/platform/projection/higherorder/Chaining.jl),
`_read_chain_from`). So in a chain `… → TextToGraphics → LayoutToGraphics`,
`TextToGraphics` reads a click in the frame in which `LayoutToGraphics` places
the parts.

A `ScrollLayout` has no one frame in the pane: each part is in its own
viewport. So the pane must choose the frame of the point that it gives on.

- **(a) The frame of the layout that puts the parts together.** The pane moves a
  point into the frame in which `LayoutToGraphics` places the parts, and adds the
  scroll offset on each axis on which the part under the point moves: both for
  the center, `y` for the left and the right edge, `x` for the top and the
  bottom edge, none for a corner. The content gets a plain event, as from any
  container, and reads it in the same way under the pane and at the end of a
  chain. One function of the `layout` slice gives the place of each part, for
  the pane, for `LayoutToGraphics` and for the content, so the three agree by
  construction.
- **(b) The frame of each part, and the pane names the part.** An event has no
  field for a part, so the pane needs a new payload, or it answers in place of
  its content with a reference `.left` and a point, which is a hit test of the
  content done by the pane. Either is a new channel (PAR-NO-NEW-SYNTHETIC-EVENT).

A key and a wheel need no decision: a key goes to the content as today, and a
wheel over any part goes to the content first and moves the one offset when the
content gives no operation (S5). A popup that the content opens goes back by the
difference of the two frames at the point, as today.

My recommendation was (a), because the content then reads one frame wherever it
stands, and no new channel is needed.

## 8. Steps (tentative)

Each step on its own commit, each with its test.

1. **`ScrollLayout` in `layout`.** The document, its fields as the reference
   vocabulary, the one function that gives the place of each part (§7.6), and
   `LayoutToGraphics`, which prints it as one canvas with the edges around the
   center, and maps a reference and a click through it. Test: a layout test with
   a canvas in each part; an example.
2. **`WidgetScrollPane` takes a `ScrollLayout` apart** (§7.4): a viewport for
   each part, the offsets (§7.1), the sizes and the width that it offers (§7.5),
   the frame of a point (§7.6), and the wheel over any part (S5). A content that
   gives a canvas sees no change. Test: a scroll pane test with a
   `ScrollLayout` of canvases: a click in each part reaches the content at the
   right point, a wheel over an edge moves the one offset, the offered width is
   the width of the center viewport; and the scroll pane tests of today pass
   unchanged.
3. **The text gives a `ScrollLayout`**: `TextBlockToScrollLayout`, with the
   gutter as the left edge, in
   [a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md).
   `text` gets the edge to `layout` in the table of
   [package-rules.md](../../documentation/rule/package-rules.md) and in the
   layering guard of the platform.
4. **Not in this plan:** the table gives a `ScrollLayout` of its grids in place
   of its three panes.
