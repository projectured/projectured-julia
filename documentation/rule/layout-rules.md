# Layout

> **Kind:** rule · **For:** developer · **Status:** current · **Stands on:** [architecture-invariants.md](architecture-invariants.md)

How every widget and every layout gets its size. One rule, both axes, no
exceptions and no constants.

The space of a widget, the padding inside its edge, the gap between children
and the space at the edge of a slot, follows [spacing-rules.md](spacing-rules.md).
In the examples below, a name such as `section_gap` is a role of the widget
theme. A builder reads it with `get_widget_style(widget_theme, :section_gap)`
and writes no number.

## 1. The rule

A parent gives each child, on each axis, a **range**: a minimum `m` and a
maximum `M` (`PrinterContext`: `minimum_width`, `maximum_width`,
`minimum_height`, `maximum_height`). The child draws

```
e = A                  when the child authored the size A
e = clamp(C, m, M)     when the child is a viewport with no slot, and scrolls the rest
e = max(m, C(M))       otherwise
```

where `C(x)` is the child's content when it may use the extent `x`. Rigid
content (a button, a one-line label) has the same extent for every `x`;
reflowing content (wrapped text, a flow) is laid out at `x`. A `nothing`
minimum is 0, and a `nothing` maximum is no edge, so with no maximum a viewport
draws `max(m, C)`. A viewport is a part that can scroll: a scroll pane, a
transform pane, and the pane of the rows of a list, a tree or a table (§3).

**A maximum is an edge that cuts.** The giver of a maximum, or an ancestor of
the giver, clips there, and nothing past the maximum shows. So a giver writes a
maximum only on an axis where a clip is. A scroll area that grows on an axis does
not cut its content there, and gives a minimum with no maximum (§3). §6 shows the
fault of a maximum that does not cut.

An axis is in one of four states:

| State | Range | The child |
| --- | --- | --- |
| exact | `(s, s)` | takes `s`: it stretches to it, and text wraps at it; its giver cuts at `s` |
| bounded | `(0, l)` | draws its content, laid out up to `l`; a viewport stops at `l`, and an ancestor cuts there |
| at least | `(m, ∅)` | draws at least `m`, and grows with its content |
| free | `(0, ∅)` | draws its content, with no edge |

An overlay (a tooltip, a menu, a context menu) caps instead of stretching:
`e = min(max(A, C(M)), M)`.

A container gives an exact range to a child that it sizes (§3, §4), and a
bounded range to a child that it only bounds. It gives a range with only a
minimum to the content of a scroll area that grows, and to a weighted child that
shares a minimum (§4). It gives a free range on an axis where it has no edge.
`with_exact_size`, `with_bounded_size`, `with_size_range` and `with_free_axis`
make the four states.

A printer that fills a slot, and is its content where it has none, reads
`get_exact_width(ctx)` and `get_exact_height(ctx)`: the cell of an exact range,
and `nothing` for the other states. An exact range is one cell for both ends.
Two cells that hold the same number make a bounded range with a minimum, and a
printer that fills a slot sees no slot there. A printer that builds only the rows
that show reads `get_visible_height(ctx)` instead (§3c).

Four policies say everything:

| policy | size on that axis |
| --- | --- |
| `Fixed(n)` | `n`, whatever is offered |
| `Content` | grows with the content; an offer does not stretch it |
| `Relative(w)` | a share `w` of what the parent offers, against its siblings' weights |
| `Fill` | all of what is offered — `Relative(1.0)` |

`Fill === Relative(1.0)` is not a special case. Two `Fill` siblings share the
offer equally, which is what a weight of one each means.

**An authored size is `Fixed`.** `w.width`, `w.height`, `w.size`, a row count — a
caller that wrote a number meant it, so it wins over the offer and the content
does not raise it. A widget told to be 40 wide draws 40 and lets its content
overflow. `0` means the widget authored nothing, and it is then `Content`.

**No constant.** A widget with no size of its own, no offer and no content has no
extent on that axis, and the answer is `0`. A number invented in a printer is a
size nobody chose, in a place nobody looks. A **default** on the document
constructor is the same constant wearing a keyword: it wins over every offer and
nobody wrote it, so a widget that can measure its content has none. A widget that
cannot — a progress bar, a slider, a skeleton, a highlight, an avatar — keeps its
number, and that number is what it **authored**: see the note on style parameters
below for why it is not its content. A progress ring can measure: its content is
one line of the theme font, so it authors no size. An offer stretches its box,
and the ring keeps its diameter at the start of the box.

**A style parameter is not a constant.** A checkbox's 18-pixel box, a switch's
44×24 track, a progress bar's 8-pixel thickness and a slider's 24-pixel height are
arguments to those projections, set at the `WidgetToGraphics(…)` factory beside
the theme's colours, and a caller building the projection may pass others. The
test is not whether a number appears, but whether anyone can choose it:

| | |
| --- | --- |
| a size constant in a printer body | nobody chose it, nobody can reach it — forbidden |
| a style parameter on a projection | chosen at the factory, replaceable by a caller — allowed |

**Such a number is `Fixed`, not content.** It reads like content — it is what the
widget has instead of something to measure — but the two behave differently under
an offer, and only one of them is right. Content loses to an offer, so a progress
bar handed a 700-pixel slot would draw a 700-pixel bar. The number is what the
widget **authored**, so it wins, and a caller who wants a thicker bar passes one
to the projection. Measured: routed as content, the bar drew `260×700`; authored,
it draws `260×8`.

## 2. Where a policy lives

**In `LayoutConstraint`, never on the widget.**

A policy is a statement about a *relationship*. `Relative(1.0)` means nothing
without a parent that divides; `Fill` means nothing without a parent that offers.
The same `WidgetCard` must fill the width in a conversation column and be
content-wide in a toolbar — so the container decides, and the card is placed
twice, unchanged.

`LayoutConstraint` already sits between a container and its child and already
carries `min` / `preferred` / `max` / `weight` per axis. A `SizePolicy` is a way
of writing those four:

```julia
LayoutConstraint(pane; height = Fill)          # weight 1, preferred 0
LayoutConstraint(card; height = Fixed(30))     # min = preferred = max = 30
```

`Fixed(n)` **is** `preferred` with `min = max = n`. It is not a fifth field.

A layout carries a **default** for its children — `child_width`, `child_height` —
and a bare child uses it. A wrapper is the same vocabulary written explicitly for
the one child that differs.

Both defaults are read on **both** axes: the one the layout divides, and the one
it does not. On the cross axis a weight takes the stack's edge exactly, or with no
edge at least the minimum of the stack's range, a declared
preferred extent takes that number exactly, and anything else is `Content`: it gets
a bounded range, its content up to the stack's edge, raised to the placement's
minimum and cut at the placement's maximum. A bare child has weight `0`, so
`Content` is what a stack gives unless it says otherwise: a badge in a column stays
badge-shaped, and a paragraph in the column wraps at the column's edge.

```julia
VerticalLayout(turns; gap = section_gap, child_width = Fill, child_height = Content)
```

## 3. What a container offers

```
slot(axis) = my extent on that axis    when I know it independently of my children
             nothing                   when my extent on that axis comes FROM them
edge(axis) = the edge I was given, less my insets
```

The second line is not taste. A child that reads an extent its parent computed
from its children reads the parent's own outer size, and the reactive cell cycles
and overflows the stack. `with_bounded_size` gives a child the edge and no slot,
and `with_free_axis(ctx, axis)` gives it neither.

The edge is a different value. It is the maximum of the range that the container
was given, a cell of the container's own parent, and never the container's own
extent. So a stack whose extent on its cross axis comes from its children still
gives each `Content` child the edge as a bounded range, and no cell reads its own
result.

So a `VerticalLayout` gives no slot on its height, a `HorizontalLayout` none on
its width, a `WidgetCard` none on its height and a `WidgetToolbar` none on its
width — each because its extent on that axis is the sum or the maximum of what
it holds. Each still gives its edge.

A `WidgetComposite` gives no slot on either axis: its children overlap, each at
its own position, and its extent is the largest of theirs. It gives each child,
on both axes, the range that a stack gives on its cross axis
(`make_cross_axis_context`), from the composite's `child_width` and
`child_height` or the `LayoutConstraint` that the child is. A bare child is
`Content`: a label in a window has the size of its text. The edge is the
composite's edge less its insets and less the position of the child, so a
`Fill` child ends at the edge of the composite. The root of a pane tree sets
both defaults to `Fill`, so its panes divide the whole window.

A **viewport** — `WidgetScrollPane`, `WidgetTransformPane` — gives an offer on
every axis where it has an extent of its own, an authored size or the space
its parent gave.
There its extent never comes from its content, which is what a viewport is.

Each axis of a viewport says whether its content **fits** the view or **grows**
past it (`grows = (width = false, height = true)` for a page). Where the content
fits, the offer is exact, `(view, view)`: a text wraps there. Where it grows, the
offer is a minimum, `(view, ∅)`: a weighted part takes at least its share of the
view (§4), and the content can be taller. Both axes fit by default. On both kinds
of axis the viewport gives the view as the **visible extent**: a part that builds
only the rows that show reads `get_visible_height(ctx)`, which is the maximum of
its range when it has one, else its minimum, and else that view (§3c).

On an axis where it has neither, a viewport passes its own range on, less its
insets, and takes its content between the minimum and the maximum of that range:
`e = clamp(C, m, M)`, and `e = max(m, C)` with no maximum. A `WidgetScrollPane`
whose content on that axis is a list, which has no extent to measure, takes
`e = M` (not less than `m`), so the rows that show are visible: a dashboard in a
card of a dashboard shows its cards. With no maximum there is no edge to take, and
`e = max(m, C)` holds. A list that has a row is told from an empty content by the
canvas of the content, so an empty list, an empty column and a finite content keep
the extent of their content. A short list leaves empty room under its last row.
The pane stops at an edge, because the giver cuts there, and scrolls the rest. If such an axis grows, the
content gets the minimum of that range and no maximum, and the maximum is the
visible extent. Every other widget keeps `e = max(m, C(M))`. This is what keeps
a collapsed card body — clipped to `Fixed(30)` in height — as wide as its text.
A list has no extent of its own, so a viewport measures a list that runs along
such an axis: a walk from the head that reaches both ends of the list within `M`
gives `C`, and else `C = M`. So a short list takes only its children, and the
walk reads only the children that the viewport draws.

A `WidgetShell` offers its content the same way: its authored `size`, else the
space its parent gave, less its insets and its bands. So the shell of a window
fills the window with no number of its own, and a shell with neither takes the
extent of its content. A shell never offers 0.

The two directions cannot form a cycle. A clipped axis gives the content a
cell to read. An unclipped axis reads a cell that the content produces.

## 3b. Who clips

```
A container that hands a child a slot (an exact range) on an axis
MUST clip that axis to the slot it handed out.
```

A slot is a promise about space, not a constraint on the child. Nothing makes a
widget fit: `_resolve_size` returns an authored size whatever is given, and
otherwise `max(minimum, content)` — so the content is a floor **above** the slot,
and a widget never draws smaller than what it holds. That is deliberate. A widget that
clamped itself to the offer would report the offer as its extent, and a stack could
no longer tell a child that is too big from one that fits, which is the measurement
`Content` and `allocate_axis` both run on.

So the promise is kept by the party that made it. The container emits a
`GraphicsViewport` at the slot, sized to the slot, holding the child's canvas — the
element `WidgetScrollPane` has always emitted — and reports **its own box** rather
than what the child reached.

**Per axis with a slot, not per widget.** An axis a container withholds — because its own
extent comes from the child — has nothing to clip against, and clipping to an extent
derived from the content is the cycle §3 describes. So a tab page clips both axes, a
split clips its main axis always and its cross axis when it was offered one, and a
card clips its width but not its height.

**A bounded range adds no clip of its own.** Its maximum is the room of an
ancestor that gave a slot, less what lies between, and that ancestor clips. Rigid
content that is wider than its edge overflows into the room of its siblings, and
the ancestor's clip ends it. A viewport in a bounded range stops at the edge and
scrolls, so its content never reaches the clip.

**Clipping is not scrolling.** A viewport bounds; a scroll pane bounds *and* holds an
offset that moves the content inside. Content that must scroll brings a
`WidgetScrollPane` of its own. A container must never wrap a child in one to get the
clipping: that hands the child's scroll to the wrong widget, and a child that manages
its own panes — a transcript above a composer — then scrolls as one block.

A scroll pane inside a clipped slot means two viewports over the same rectangle. That
is a scissor rect, not a surface, and the alternative is a type test in the printer.

**A widget of rows scrolls by itself.** A `WidgetTable`, a `WidgetList` and a
`WidgetTree` that get an edge, exact or bounded, on an axis that they scroll take
their rows up to it and scroll the rest there, inside their border; with no edge
they are as tall as their rows. So the
maker of such a widget brings no pane, and a pane around one has nothing left to
scroll.

**A bar is an overlay.** A scroll bar lies over the content, at the inner edge of
the border of the widget that scrolls, and takes no space. So a bar that shows
changes no extent, and a text does not wrap again at a narrower edge.

## 3c. The visible extent

A part that builds only the rows that show must know how much of it shows. Its
range does not always tell it: on an axis that grows, the content of a scroll
area has no maximum. So each scroll area also gives its view as a second value,
the **visible extent** (`with_visible_size`). A scroll area inside another gives
its own view, and the parts below it keep the value.

```
get_visible_height(ctx) = ctx.maximum_height     when the range has a maximum: the giver cuts there
                          ctx.minimum_height     else, when the range has a minimum: the share of the giver
                          the visible extent     else, from the nearest scroll area
                          nothing                else
```

`get_visible_width` reads the width in the same way. So a part reads one value in
a slot, in a bounded range and in a scroll area that grows.

The minimum comes before the visible extent because, on an axis that grows, a
stack gives a weighted part its share of the view as a minimum (§4). Two tables
of the same weight below a card, in a view of 907, each get `(357, ∅)`. Each
table shows 357, the height that it shows in a page of a fixed size. With the
visible extent, each table is as tall as the whole view. The visible extent is
a property of the context of the layout package, and not a field of
`PrinterContext`, because the kernel has no view.

| A part that | Reads | Such as |
| --- | --- | --- |
| builds only the rows that show | `get_visible_height` | a `WidgetTable` whose rows are a list, the rows of a data frame, the lines of a task stream, the bar of the frame statistics, the width of a `WidgetTree` measured over its shown rows |
| fills its own slot | `get_exact_width`, `get_exact_height` | a shell, a split, a tabbed pane, a roster, a dashboard |

A part that builds the rows that show must not read `get_exact_height`. In a
scroll area that grows that is `nothing`, and the part then has no count of rows
to build. A lazy grid of ten million rows in a scroll area that grows builds
fewer than 30 rows (`test_layout_rules()`).

## 4. When a stack distributes instead of summing

A stack sums its children on its main axis. It **distributes** its edge instead
when both of these hold:

```
the stack has an edge on its main axis        ctx.maximum_width or ctx.maximum_height !== nothing,
                                              exact or bounded
  or a minimum and no maximum there           the minimum is shared as a minimum
and some child carries a weight on that axis  (Fill or Relative)
```

The rule is the same for a row and a column, and for the columns and the rows of
a `GridLayout`.

**A minimum is shared as a minimum.** A stack whose range on its main axis is
`(m, ∅)`, as a page in a viewport that grows gets, divides `m`, and gives each
weighted child its share as a minimum, `(shareᵢ, ∅)`. The child draws
`max(shareᵢ, content)`, and the stack is the sum of its children, at least `m`.
So a `Fill` part in a short page fills the rest of the view, and in a long page
it keeps its content and the page scrolls, as `flex-grow` does in a CSS
container with a `min-height`. On the cross axis, a weighted child with no edge
takes at least the minimum of the range.

Nothing is declared on the stack. A child asking for a share can only have one
when the stack has something to share, and a share of a sum of its own children is
the cycle of §3. The edge is what the stack is offered, so a row with a `Fill`
child fills the room its parent gives it, even when that parent gives only an edge:
a page gives every block the width of its view, as CSS gives a block the width of
its container.

An edge is where the giver cuts, so a stack divides it whether it is exact or
bounded. A page that grows down sits in a viewport that grows on its height, which
gives the page `(view, ∅)` (§3), so its blocks get no edge there. In a viewport
that fits, the view is an edge, and the blocks share it.

**Only a weighted child gets a slot.** Every other child gets the room the others
leave, as a bounded range, and draws its content up to it:

```
Fixed(k)       (k, k)
unweighted i   (minᵢ, min(maxᵢ, room_i))
room_i       = edge − gaps − Σ(j < i, unweighted) eⱼ − Σ(j > i or weighted) minⱼ
```

`eⱼ` is what child `j` drew. A room reads only the children before it, and the
allocation reads the unweighted children after they are drawn, so no child's
extent depends on the allocation or on itself. `WidgetSplitPane` works the same
way. A viewport with no weight takes its content up to its room and scrolls the
rest (§1). A `Content` row of a grid gets the edge of the grid less the gaps, less
what the `Content` rows above it drew and less the minimums of the other rows, as
a `Content` column gets its width.

**A child after the others counts only by its minimum.** A label after a
scroll pane declares no minimum, so the room of the pane leaves no space for it.
In a column of 300 that cuts:

```
VerticalLayout([WidgetScrollPane(16 lines), WidgetLabel("stdout")])
  the pane: 300 of its 384, and it scrolls    the label: at 300, and the giver cuts it
VerticalLayout([WidgetScrollPane(16 lines), LayoutConstraint(WidgetLabel("stdout"); min_height = 24)])
  the pane: 276                               the label: at 276, and it shows
```

**A stack places a child after the extent that the child before it drew**, and
not after the slot of that child. So a minimum on a placement holds only for a
child that draws at least its range. A widget, a layout and a viewport do. A
printer that draws its content in any range, such as the text of a phrase, leaves
the rest of its slot to the next child.

**The order decides between children that reflow.** A child that reflows — wrapped
text, a flow — counts the children after it only by their minimums, so it takes
the room before they are drawn: in a row `[long text, button]` the text wraps at
the whole row and the button passes the edge. Give the text a weight, and it gets
exactly what the button leaves; two texts side by side share the row by their
weights. A text after a button needs nothing: it gets what the button left.

`allocate_axis(available, mins, maxs, prefs, weights, gap, n)` is the one
allocator, shared by the stacks and the split.

**A container with no edge divides nothing.** `WidgetSplitPane` divides its main
axis, so with no offer on that axis it has nothing to divide. It then withholds
that axis from its children and each slot is the child's own extent — a declared
size, from `sizes` or a `LayoutConstraint`, or else what the child draws. Offering
an unallocated slot instead would tell the child it has no room at all, and the
child would draw nothing.

## 5. The worked cases

The numbers come from the measure of `test_layout_rules()`: a line is 24 pixels
high, and a character is 10 pixels wide. That test checks the first four cases.
Each case has an example in a window with a splitter, so you can drag the
splitter and see the parts take their space: `run_example("layout_…")`.

**A window that cuts or scrolls.** A column holds a part A of 8 lines, which does
not scroll, and a scroll pane B with 16 lines of content:

```julia
VerticalLayout([A, WidgetScrollPane(B)])        # A: 192 px; B: 384 px of content
```

| The window | The column gets | B draws | Past the window |
| --- | --- | --- | --- |
| cuts at 300 | `(300, 300)` | `300 − 192 = 108`, and scrolls its content | nothing shows |
| cuts at 250 | `(250, 250)` | 58 | nothing shows |
| a scroll area of 300 that grows on its height | `(300, ∅)` | 384 | the window scrolls to it |

The window that cuts is the detail of a task (`layout_text_above_table`). The
window that scrolls is a page with a code block (`layout_scroll_area_in_page`).

**A text above a table, in a slot that cuts.** This is the detail of a task:

```julia
VerticalLayout([WidgetScrollPane(text),                              # 12 lines: 288 px
                LayoutConstraint(table; height = Fill, min_height = 120)]; gap = 6)
```

In `(400, 400)` the room of the text is `400 − 6 − 120 = 274`. Its scroll pane
takes 274 of its 288 and scrolls. The table gets the 120 that is left.

**A column and a row share alike.** In the range `(0, 300)` the parts
`[Fixed(100), Fill]` get `[100, 200]` in a row and in a column, and the columns
and the rows of a grid get the same. In the range `(300, ∅)` they get
`[100, 200]` too. With `[Fixed(400), Fill]` in `(300, ∅)` the `Fill` part keeps
its content, and the stack is taller than 300. `layout_shares` shows the four
policies in one column.

**A part that fills, in a page that scrolls.** A column of a header, a `Fill`
part and a footer is in a scroll area of 300 that grows on its height, so the
column gets `(300, ∅)`. With a header of 2 lines the `Fill` part takes the rest
of the 300. With a header of 40 lines the column is taller than 960, and the
area scrolls to the footer (`layout_fill_in_scroll_area`).

**A scroll pane below a header:**

```julia
WidgetShell(size = Point2D(300, 400))
  └ VerticalLayout(gap = section_gap)                    # declares nothing
      ├ WidgetLabel("header")                            # 24 px, Content
      └ LayoutConstraint(WidgetScrollPane(…); height = Fill)
```

- the shell gives the column the slot `(400, 400)`;
- the stack sees a weight on `:y`, so it distributes rather than sums;
- the label has no weight, keeps its 24, and gets no slot;
- the pane gets the slot `400 − 8 − 24 = 368`, which is 400 less one `section_gap` of 8 and the label, clips its content, and scrolls.

Without the wrapper the pane has no weight, and it gets the same 370 as a
bounded range. It takes its content up to 370 and scrolls the rest: a content of
2 lines gives a pane of 48, and a content of 40 lines a pane of 370. The `Fill`
makes the pane take the 370 also when its content is short.

**A row of a label, a field that takes the rest, and a button**, in 400 pixels
with a gap of `form_column_gap`, which is 8 (`layout_row_edge`):

```julia
HorizontalLayout([WidgetLabel("Name:"),                          # 50 px
                  LayoutConstraint(WidgetText(""); width = Fill),
                  WidgetButton("Go")]; gap = form_column_gap)      # 42 px
```

- the label's room is `400 − 16 − 0 − 0 = 384`, and it draws its 50;
- the button's room is `400 − 16 − 50 − 0 = 334`, and it draws its 42;
- the field gets the rest: `400 − 16 − 50 − 42 = 292`.

## 6. The trap: a maximum that does not cut

**A giver that does not cut must not give a maximum.** A range carries no mark
of its giver, so a printer reads each maximum as an edge that cuts, and a
viewport stops there. Take the window of §5 that scrolls, a scroll area of 300 around the column
of A and B:

| The scroll area | The column gets | B draws | The person sees |
| --- | --- | --- | --- |
| grows on its height | `(300, ∅)` | 384 | B whole, and one scroll bar, of the window |
| fits on its height | `(300, 300)` | 108 | B of 108 with a scroll bar of its own, in a window that also scrolls |

The second row is the trap. A scroll area that fits gives its view as a maximum,
and the column shares it as if it were a cut. So a scroll area that holds a page
must grow on the axis that the page grows on:
`WidgetScrollPane(page; grows = (width = false, height = true))`.

The same trap has two other forms:

- **A slot where the giver only bounds.** A window that fits its content, such
  as a tooltip, gives its maximum as an edge. If it gives the maximum as a slot,
  a content that fills its slot takes the whole maximum, and every tooltip is as
  wide as its maximum.
- **A maximum as the count of the rows that show.** A part that must know how
  much shows reads the visible extent (§3c). A giver must not write a maximum for
  it.

`test_layout_rules()` prints each widget type and each layout type in each state
of §1, and checks what it draws by the rule of its kind. Its guard fails for a
type with no kind, so a new type gets checked too.

## 7. What this replaces

Written down because the reasoning is easy to lose and expensive to rebuild:

- a widget does **not** decide its own policy, and does not carry layout fields;
- there is **no** per-axis rule: width and height differ only in the range that
  a parent gives. A row and a column share their main axis by one rule (§4), and
  so do the columns and the rows of a grid;
- there is **no** fixed scroll axis: each scroll area says for each axis whether
  its content fits or grows, both fit by default, and the rule of each setting is
  the same on both axes (§3);
- there is **no** maximum that does not cut: a giver writes a maximum only where
  a clip is, and a part that must know how much shows reads the visible extent
  (§3c, §6);
- there are **no** size constants: a stray constant in `WidgetToGraphics.jl`
  can silently become the height of every scroll pane in a column, and text with
  no edge does not wrap at a number that nobody chose — it wraps at the edge its
  parent gives, or not at all;
- there is **no** local limit: a toolbar, a card, a table and an overlay read the
  range their parent gives, and none of them computes an edge of its own;
- a container that divides an axis is **not** exempt: with no edge it withholds
  that axis and takes each slot from the child, the same as any other `Content`.
