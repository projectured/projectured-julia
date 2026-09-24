# The sizing model: what a parent, a child and the context can say

> **Status:** analysis for the owner's decision. Written 2026-09-24. Nothing is
> implemented.

## 1. Why the question comes back

The owner asked for the complete picture on 2026-09-24:

> what are the parameters on the parent, what are the parameters on the child,
> what are the parameters in the printer context, what are the combinations,
> what do they mean, what can be expressed and how, what are the limitations, I
> kind of hate that we still have to come back to the layout and we still didn't
> solve this once and for all

The case that brought it back: a result row of the evaluator is
`[prompt, result]`. With `child_width = Content` a text result wraps at an 800
pixel fallback and runs under the next pane (commit 70826ae6 fixed that). With
`child_width = Fill` a button result stretches over the whole row (S4,
2026-09-24). No policy gives "the natural size, but not past the edge".

The same fault has been met, and patched in place, at least five times (§4.2).

## 2. The parameters today

### 2.1 On the parent: the placement

| Where | Parameter | Meaning |
| --- | --- | --- |
| `HorizontalLayout`, `VerticalLayout` | `child_width`, `child_height` | the default `SizePolicy` of a bare child, on each axis |
| | `gap`, `horizontal_align`, `vertical_align` | spacing and alignment |
| `GridLayout`, `FormLayout` | `column_policy`, `row_policy`, `column_policies`, `row_policies` | the policy of every column and row, and the ones that differ |
| | `column_offers` | a column that keeps its offer from its cells and clips them |
| `FlowLayout` | `max_width` (default 400) | where a line breaks when the offer is larger or missing |
| `WidgetSplitPane` | `sizes` | the extent of each slot |
| `WidgetShell`, `WidgetScrollPane`, `WidgetTransformPane` | `size` | an authored extent; else the offer, less insets |
| `WidgetTable` | `column_policy`, `row_policy`, a cell policy (`:wrap`, `:clip`) | the grid inside the table |
| any child | `LayoutConstraint(child; width, height, min_*, preferred_*, max_*, weight_*)` | the placement of one child, over the default |

`SizePolicy(min, preferred, max, weight)` on one axis. The named forms:

| Policy | Fields | Meaning |
| --- | --- | --- |
| `Content` (the default) | nothing, nothing, nothing, 0 | grows with the content; an offer does not stretch it |
| `Fixed(n)` | n, n, n, 0 | `n` pixels, whatever is offered |
| `Relative(w)` | 0, 0, nothing, w | a share of the offer, by weight |
| `Fill` | `Relative(1.0)` | all of the offer |

### 2.2 On the child

- **An authored size**: a widget field that a caller writes (`width`, `height`,
  `size`, `rows`, `length`). It is `Fixed`: it wins over the offer and over the
  content. `0` or `nothing` authors nothing.
- **A style parameter** on the projection (a checkbox's box, a switch's track): a
  fixed number, chosen at the factory, also `Fixed`.
- **The content**: what the child draws. Two kinds, which the model does not
  tell apart today:
  - *rigid* content keeps its extent whatever the width: a button, a label on
    one line, a badge, a canvas;
  - *reflowing* content changes its extent with the width it may use: wrapped
    text, a flow, a card's text, a table cell that wraps.

### 2.3 In the printer context

`PrinterContext` carries one quantity on each axis, `available_width` and
`available_height`: a `Cell`, or `nothing`. It has one meaning, **the slot**:
"this is the extent you are given". The root is the window
(`ScreenToScreen.jl:72`).

## 3. How they combine today

### 3.1 What a container gives each child

On its **main axis** a stack sums its children. When it was offered an extent
and a child has a weight, it divides instead: `allocate_axis` starts each child
at `clamp(preferred, min, max)` and gives the rest to the weighted children by
weight, up to their `max`. A weighted child gets its share as a slot. Every other
child gets no slot (`withhold_offer`), and its drawn extent is its preferred
size. A weighted child's drawn extent is never read, because it depends on its
slot.

On its **cross axis**: a weighted child gets the container's own slot; a child
with a preferred extent gets that number; any other child gets no slot.

A container gives a slot only on an axis where it knows its extent without its
children (`layout-rules.md` §3), and it clips every axis that it bounded (§3b).

### 3.2 What a child does with it

| The child | With a slot | With no slot |
| --- | --- | --- |
| authored size | the authored size (the container clips it) | the authored size |
| rigid content, most widgets (`_resolve_size`) | stretches: `max(slot, content)` | its content |
| overlays (`_resolve_overlay`) | caps: `min(content, slot)` | its content |
| wrapped text (`WordWrapping`) | wraps at the slot | wraps at 800 px |
| `FlowLayout` | breaks at `min(max_width, slot)` | breaks at `max_width`, 400 |
| a graphics canvas | ignores it | its authored `w`, `h` |
| chart and sequence plots | take the slot, over a minimum | their authored size |

### 3.3 The results

| Placement → / child ↓ | `Content` | `Fill`, `Relative` | `Fixed(n)` |
| --- | --- | --- | --- |
| authored | authored | authored, clipped | authored, clipped |
| rigid (a button) | natural | **stretched** | stretched to `n` |
| reflowing (text) | **wraps at 800** | wraps at the slot | wraps at `n` |
| filling (a card, a plot) | content | the slot | `n` |

Two cells of this table are wrong for most places that use them: a rigid child
under `Fill` and a reflowing child under `Content`.

## 4. What can not be expressed

### 4.1 The missing combination

"The natural extent, but not past the edge" can not be written. A rigid child
must keep its size and a reflowing child must wrap at the edge. The placement can
only choose between `Content` (no edge: text passes it) and `Fill` (the edge is a
slot: a button stretches to it).

The policy is not the problem: `allocate_axis` already stops a weighted child at
its `max`, so "weight 1, `max` = the natural extent" would be right. The problem
is the channel. The context carries one quantity, and it always means "take
this". A child can not be told "you may use up to this", so no child can tell
the edge from its slot.

### 4.2 The same fault, patched five times

Each place below builds a limit of its own, because the context has none:

- `_resolve_overlay` (`WidgetToGraphics.jl:1113`): a tooltip, a menu and a
  context menu cap at the slot instead of stretching to it.
- The toolbar withholds the slot from its items (`WidgetToGraphics.jl:4964`):
  "a 140-pixel slider drawn in a toolbar came out 800 wide".
- The table list offers the column width only to a cell that wraps
  (`WidgetTableList.jl:96`).
- `FlowLayout` breaks at the smaller of its `max_width` and the slot.
- The card computes the width of its text from the slot (`_card_build`).

And two numbers that nobody chose stand where the edge is missing: the 800 of
`WordWrapping` and the 400 of `FlowLayout`. `layout-rules.md` §1 forbids such
numbers.

## 5. The proposal: the edge travels with the slot

### 5.1 The model

The context carries two quantities on each axis:

| Quantity | Meaning | Today |
| --- | --- | --- |
| the **slot** (`available_width`) | the extent the child takes | exists |
| the **limit** (new, for example `width_limit`) | the extent the child must not pass | missing |

A slot is always also a limit. A container gives a limit on every axis where it
knows how much room there is, whatever the policy of the child; it gives a slot
only where the policy asks for one, as today.

What a child does:

| The child | Slot | Limit, no slot | Neither |
| --- | --- | --- | --- |
| authored | authored | authored | authored |
| rigid | stretches to the slot | its content | its content |
| reflowing | reflows at the slot | reflows at the limit | does not reflow: one line |
| overlay | caps at the slot | caps at the limit | its content |

A child never draws smaller than its content (`layout-rules.md` §3b): rigid
content that is wider than its limit overflows, and the container that bounded
the axis clips it.

`Content` then means what it was always read as: **the natural extent, up to the
edge**. No new policy is needed. `Fill`, `Relative` and `Fixed` do not change.

### 5.2 Where the limit comes from

- **The cross axis of a stack**, and every axis of a grid cell, a card body, a
  pane, a split slot, a shell and a viewport: the container's own extent, less
  its insets. It never reads the child, so it has no cycle.
- **The main axis of a stack**: a child that is not weighted gets the stack's
  extent, less the gaps, less the drawn extents of the unweighted children
  before it, and less the minimums of all the others. A weighted child gets its
  slot, as today. So each limit reads only children that come earlier in one
  fixed order, and no cell reads its own result. For the evaluator row
  `[prompt, result]` the result's limit is the row, less the prompt, less the
  gap.

### 5.3 What goes away

- the 800 pixel fallback of `WordWrapping`, and the 400 of `FlowLayout`;
- the table list's own rule for a wrapping cell, and the card's own text width;
- `_resolve_overlay` as a special case: an overlay is a child that caps;
- the `Fill` of the evaluator rows: they go back to `Content`, and a button
  result keeps its size while a text result wraps at the pane.

The toolbar keeps withholding the slot, and it gives a limit.

### 5.4 The cost

This is a change of the model, not of one place:

- `PrinterContext` (`source/kernel/projection/PrinterContext.jl`, not sealed): the
  limit, and a helper beside `with_available_size` and `withhold_offer`.
- Every container that gives a slot: the stacks, the grid, the flow, the split,
  the shell, the viewports, the card, the table, the tabbed pane, the pane tree.
- `WordWrapping`, `FlowLayout`, `_resolve_size` and `_resolve_overlay`.
- Render tests at two limits for each kind of child, and a baseline diff of
  every suite that draws a layout, because every `Content` child changes: text
  that overflowed now wraps.

## 6. The alternatives

| | What | Fixes | Cost |
| --- | --- | --- | --- |
| **(a1)** | the evaluator alone gives `Fill` to a text result and `Content` to any other result | the evaluator row | small |
| **(a2) with `Fit`** | a new policy that a placement asks for: the slot is given as a limit; the channel of §5, used only where `Fit` is written | the places that write `Fit` | medium; the 800 stays wherever `Content` is used |
| **(a2) in two passes** | `Fit` = weight 1 with `max` = the natural extent, measured by printing the child once with no slot, as `ConstraintLayout` measures | the places that write `Fit`; no change to the context | medium; each `Fit` child is printed twice, and both copies stay live |
| **(§5)** | the limit in the context, and `Content` bounded by it | the whole class: §4.1 and the five patches of §4.2 | large |

## 7. The decision the owner makes

1. Which of the four.
2. If §5: the name of the limit, and whether it lands in steps (the cross axis
   and the containers first, the main axis of the stacks second, the removal of
   the patches of §4.2 last), each with its own baseline diff.
