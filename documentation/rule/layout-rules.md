# Layout

> **Kind:** rule · **Status:** current · **Stands on:**
> [architecture-invariants.md](architecture-invariants.md)

How every widget and every layout decides its size. One rule, both axes, no
exceptions and no constants.

## 1. The rule

```
size(axis) = clamp( policy(axis) resolved against the parent's offer,
                    min(axis), max(axis) )
```

Four policies say everything:

| policy | size on that axis |
| --- | --- |
| `Fixed(n)` | `n`, whatever is offered |
| `Content` | grows with the content; an offer does not stretch it |
| `Relative(w)` | a share `w` of what the parent offers, against its siblings' weights |
| `Fill` | all of what is offered — `Relative(1.0)` |

`Fill === Relative(1.0)` is not a special case. Two `Fill` siblings share the
offer equally, which is what a weight of one each means.

**No constant.** A widget with no size of its own, no offer and no content has no
extent on that axis, and the answer is `0`. A number invented in a printer is a
size nobody chose, in a place nobody looks.

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

```julia
VerticalLayout(turns; gap = 6, child_width = Fill, child_height = Content)
```

## 3. What a container offers

```
offer(axis) = my extent on that axis    when I know it independently of my children
              nothing                   when my extent on that axis comes FROM them
```

The second line is not taste. A child that reads an extent its parent computed
from its children reads the parent's own outer size, and the reactive cell cycles
and overflows the stack. `withhold_offer(ctx, axis)` is that rule, written once.

So a `VerticalLayout` withholds height, a `HorizontalLayout` withholds width, a
`WidgetCard` withholds height, a `WidgetToolbar` withholds width — each because
its extent on that axis is the sum or the maximum of what it holds.

A **viewport** — `WidgetScrollPane`, `WidgetTransformPane` — offers on **both**
axes, because its own extent never comes from its content. That is what a viewport
is. Nothing anywhere knows which axis "scrolls".

## 4. When a stack distributes instead of summing

A stack sums its children on its main axis and offers them none of it. It
**distributes** instead when both of these hold:

```
the stack was offered a main-axis extent      (ctx.available_* !== nothing)
and some child carries a weight on that axis  (Fill or Relative)
```

Nothing is declared on the stack. A child asking for a share can only have one
when the stack has something to share, and a share of a sum of its own children is
the cycle of §3.

**Only a weighted child is offered a slot.** Every other child keeps the withheld
axis, so its extent does not depend on the allocation and is safe to read while
computing it. `WidgetSplitPane` has always worked this way; the stacks do now too.

`allocate_axis(available, mins, maxs, prefs, weights, gap, n)` is the one
allocator, shared by the stacks and the split.

## 5. The worked case

A scroll pane that should take what a header leaves, and scroll:

```julia
WidgetShell(size = Point2D(300, 400))
  └ VerticalLayout(gap = 6)                              # declares nothing
      ├ WidgetLabel("header")                            # 26 px, Content
      └ LayoutConstraint(WidgetScrollPane(…); height = Fill)
```

- the shell offers `400`;
- the stack sees a weight on `:y`, so it distributes rather than sums;
- the label is unweighted, keeps its 26, and is not offered a slot;
- the pane takes the remaining `374`, clips its content, and scrolls.

Without the wrapper the pane has no height at all — no size of its own, none
offered, and none from its content — and `0` is the right answer to a question
nobody asked.

## 6. What this replaces

Written down because the reasoning is easy to lose and expensive to rebuild:

- a widget does **not** decide its own policy, and does not carry layout fields;
- there is **no** per-axis rule: width and height differ only in which offer a
  parent supplies, and a row and a column want opposite answers from the same rule;
- there is **no** scroll-axis rule: a viewport offers both axes and the content's
  own policy decides whether it overflows;
- there are **no** size constants: five once stood in
  `WidgetToGraphics.jl`, and the 300 among them was the entire height of every
  scroll pane in a column.
