# Layout

> **Kind:** rule · **Status:** current · **Stands on:** [architecture-invariants.md](architecture-invariants.md)

How every widget and every layout gets its size. One rule, both axes, no
exceptions and no constants.

## 1. The rule

A parent gives each child, on each axis, a **range**: a minimum `m` and a
maximum `M` (`PrinterContext`: `minimum_width`, `maximum_width`,
`minimum_height`, `maximum_height`). The child draws

```
e = A                  when the child authored the size A
e = max(m, C(M))       otherwise
```

where `C(x)` is the child's content when it may use the extent `x`. Rigid
content (a button, a one-line label) has the same extent for every `x`;
reflowing content (wrapped text, a flow) is laid out at `x`. A `nothing`
minimum is 0, and a `nothing` maximum is no edge.

An axis is in one of three states:

| State | Range | The child |
| --- | --- | --- |
| exact | `(s, s)` | takes `s`: it stretches to it, and text wraps at it |
| bounded | `(0, l)` | draws its content, laid out up to `l` |
| free | `(0, ∅)` | draws its content, with no edge |

An overlay (a tooltip, a menu, a context menu) caps instead of stretching:
`e = min(max(A, C(M)), M)`.

A container gives an exact range to a child that it sizes (§3, §4), a bounded
range to a child that it only bounds, and a free range on an axis where it has
no edge. `with_exact_size`, `with_bounded_size` and `with_free_axis` make the
three states. A printer that fills a slot, and is its content where it has
none, reads `get_exact_width(ctx)` and `get_exact_height(ctx)`: the cell of an
exact range, and `nothing` for a bounded or a free one.

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
it does not. On the cross axis a weight takes the stack's edge exactly, a declared
preferred extent takes that number exactly, and anything else is `Content`: it gets
a bounded range, its content up to the stack's edge, raised to the placement's
minimum and cut at the placement's maximum. A bare child has weight `0`, so
`Content` is what a stack gives unless it says otherwise: a badge in a column stays
badge-shaped, and a paragraph in the column wraps at the column's edge.

```julia
VerticalLayout(turns; gap = 6, child_width = Fill, child_height = Content)
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

On an axis where it has neither, a viewport has nothing to clip against. It
passes its own range on, less its insets, and takes the content's own extent,
exactly as `Content` says. A pane therefore clips the axes it was given and follows its
content on the rest, and nothing anywhere names an axis that "scrolls". This is
what keeps a collapsed card body — clipped to `Fixed(30)` in height — as wide as
its text.

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

**A bounded range adds no clip.** Its maximum is the room of an ancestor that gave
a slot, less what lies between, and that ancestor clips. Rigid content that is
wider than its edge overflows into the room of its siblings, and the ancestor's
clip ends it.

**Clipping is not scrolling.** A viewport bounds; a scroll pane bounds *and* holds an
offset that moves the content inside. Content that must scroll brings a
`WidgetScrollPane` of its own. A container must never wrap a child in one to get the
clipping: that hands the child's scroll to the wrong widget, and a child that manages
its own panes — a transcript above a composer — then scrolls as one block.

A scroll pane inside a clipped slot means two viewports over the same rectangle. That
is a scissor rect, not a surface, and the alternative is a type test in the printer.

## 4. When a stack distributes instead of summing

A stack sums its children on its main axis. It **distributes** its edge instead
when both of these hold:

```
the stack has an edge on its main axis        (ctx.maximum_* !== nothing, exact or bounded)
and some child carries a weight on that axis  (Fill or Relative)
```

Nothing is declared on the stack. A child asking for a share can only have one
when the stack has something to share, and a share of a sum of its own children is
the cycle of §3. The edge is what the stack is offered, so a row with a `Fill`
child fills the room its parent gives it, even when that parent gives only an edge.

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
way.

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

## 5. The worked case

A scroll pane that should take what a header leaves, and scroll:

```julia
WidgetShell(size = Point2D(300, 400))
  └ VerticalLayout(gap = 6)                              # declares nothing
      ├ WidgetLabel("header")                            # 26 px, Content
      └ LayoutConstraint(WidgetScrollPane(…); height = Fill)
```

- the shell gives an offer of `400`;
- the stack sees a weight on `:y`, so it distributes rather than sums;
- the label is unweighted, keeps its 26, and is not offered a slot;
- the pane takes the remaining `374`, clips its content, and scrolls.

Without the wrapper the pane is offered no height, so it clips nothing: it takes
the height of its content and the column grows with it. The `Fill` is what makes
it a viewport in that column.

A row with a label, a field that takes the rest, and a button, in 400 pixels with a
gap of 8:

```julia
HorizontalLayout([WidgetLabel("Name:"),                          # 50 px
                  LayoutConstraint(WidgetText(""); width = Fill),
                  WidgetButton("Go")]; gap = 8)                  # 30 px
```

- the label's room is `400 − 16 − 0 − 0 = 384`, and it draws its 50;
- the button's room is `400 − 16 − 50 − 0 = 334`, and it draws its 30;
- the field gets the rest: `400 − 16 − 50 − 30 = 304`.

## 6. What this replaces

Written down because the reasoning is easy to lose and expensive to rebuild:

- a widget does **not** decide its own policy, and does not carry layout fields;
- there is **no** per-axis rule: width and height differ only in which offer a
  parent supplies, and a row and a column want opposite answers from the same rule;
- there is **no** scroll-axis rule: a viewport clips every axis it has an extent
  for and follows its content on the rest, and no axis is named anywhere;
- there are **no** size constants: a stray constant in `WidgetToGraphics.jl`
  can silently become the height of every scroll pane in a column, and text with
  no edge does not wrap at a number that nobody chose — it wraps at the edge its
  parent gives, or not at all;
- there is **no** local limit: a toolbar, a card, a table and an overlay read the
  range their parent gives, and none of them computes an edge of its own;
- a container that divides an axis is **not** exempt: with no edge it withholds
  that axis and takes each slot from the child, the same as any other `Content`.
