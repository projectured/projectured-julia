# The sizing model: a range on each axis

> **Status:** pending. The owner chose the model of §4 on 2026-09-24 and asked
> for this plan. Nothing is implemented.

## 1. The request and the decisions

The owner, 2026-09-24, after the evaluator row stretched a button:

> I need to get the complete picture to decide
>
> what are the parameters on the parent, what are the parameters on the child,
> what are the parameters in the printer context, what are the combinations,
> what do they mean, what can be expressed and how, what are the limitations, I
> kind of hate that we still have to come back to the layout and we still didn't
> solve this once and for all

> hey, I don't care about the evaluator, that's just a special case, I said it
> already, I want to solve it once and for all
>
> so I kind of chose §5

> write the plan and make sure the documentation is also updated when the plan
> gets executed

So:

1. The model changes once for every container and every child, not for one
   case. The evaluator row is one of its consumers.
2. The context carries a range on each axis (§4).
3. Each step updates the documents that it makes wrong, and the last step checks
   the whole documentation (§7).

## 2. The model today

### 2.1 The parameters

**On the parent, the placement.** The placement decides the policy of a child
(`layout-rules.md` §2):

| Where | Parameter | Meaning |
| --- | --- | --- |
| `HorizontalLayout`, `VerticalLayout` | `child_width`, `child_height` | the default policy of a bare child, on each axis |
| | `gap`, alignment | spacing and alignment |
| `GridLayout`, `FormLayout` | `column_policy`, `row_policy`, `column_policies`, `row_policies`, `column_offers` | the policy of the columns and rows |
| `FlowLayout` | `max_width` (default 400) | where a line breaks |
| `WidgetSplitPane` | `sizes` | the extent of each slot |
| `WidgetShell`, `WidgetScrollPane`, `WidgetTransformPane` | `size` | an authored extent; else what the parent gave, less insets |
| `WidgetTable` | column and row policies, a cell policy (`:wrap`, `:clip`) | the grid inside the table |
| any child | `LayoutConstraint(child; width, height, min_*, preferred_*, max_*, weight_*)` | the placement of one child, over the default |

`SizePolicy(min, preferred, max, weight)`: `Content = (∅, ∅, ∅, 0)`,
`Fixed(k) = (k, k, k, 0)`, `Relative(w) = (0, 0, ∅, w)`, `Fill = Relative(1.0)`.

**On the child.** An authored size (`width`, `height`, `size`, `rows`,
`length`), which always wins; the style numbers of its projection; and its
content. Content is *rigid* (its extent does not change with the width: a
button, a one-line label, a canvas) or *reflowing* (its extent changes with the
width: wrapped text, a flow, a card's text, a table cell that wraps).

**In the context.** One value on each axis, `available_width` and
`available_height`: a `Cell`, or `nothing`. It means "this is your extent; take
it".

### 2.2 How they combine

A stack gives a value only to a weighted child on its main axis, and only when
it was given one itself; on its cross axis it gives its own value to a weighted
child and `preferred` to a `Fixed` one. Every other child gets `nothing`
(`withhold_offer`). A child that gets a value stretches to it
(`_resolve_size`: `max(value, content)`); a child that gets none draws its
content.

| Placement → / child ↓ | `Content` | `Fill`, `Relative` | `Fixed(k)` |
| --- | --- | --- | --- |
| authored | authored | authored, clipped | authored, clipped |
| rigid (a button) | natural | **stretched** | stretched to `k` |
| reflowing (text) | **wraps at 800** | wraps at the value | wraps at `k` |

### 2.3 What can not be expressed

"The natural extent, but not past the edge." A child can only be told "take
this" or nothing, so a rigid child stretches whenever a reflowing sibling needs
the edge. Five places build the missing edge by hand:

- `_resolve_overlay` (`WidgetToGraphics.jl:1113`): a tooltip, a menu and a
  context menu cap at the value instead of stretching to it;
- the toolbar withholds the value from its items (`WidgetToGraphics.jl:4964`),
  because "a 140-pixel slider drawn in a toolbar came out 800 wide";
- the table list gives the column width only to a cell that wraps
  (`WidgetTableList.jl:96`);
- `FlowLayout` breaks at the smaller of its `max_width` and the value;
- the card computes the width of its text itself (`_card_build`).

Two numbers that nobody chose fill the gap: the 800 of `WordWrapping` and the
400 of `FlowLayout`, which `layout-rules.md` §1 forbids.

## 3. The alternatives that were not chosen

- **Only the evaluator** gives `Fill` to a text result and `Content` to any
  other: it fixes one consumer.
- **A `Fit` policy** that a placement asks for: the edge is given only where
  `Fit` is written, and the 800 stays everywhere else.
- **`Fit` in two passes**: the natural extent measured by printing the child once
  with no value, as `ConstraintLayout` measures; each such child is printed
  twice, and both copies stay live.

## 4. The model: a range on each axis

### 4.1 The range

The context carries, on each axis, a **minimum** and a **maximum**:

| Value | Meaning for the child |
| --- | --- |
| **maximum** | the edge: do not draw past it; the container clips there |
| **minimum** | the extent to take at least: stretch to it when the content is smaller |

An axis is in one of three states:

| State | Range | Meaning | Given by |
| --- | --- | --- | --- |
| exact | `(s, s)` | "you are `s`" | `Fill`, `Relative`, `Fixed` |
| bounded | `(0, l)` | "what you need, up to `l`" | `Content` in a parent that has an edge (new) |
| free | `(0, ∅)` | "what you need, with no edge" | an axis that grows with its content |

A placement minimum reaches the child as well: `LayoutConstraint(child;
min_width = 120)` in a bounded parent gives `(120, l)`.

This is the model of Flutter's box constraints (constraints go down, sizes go
up, the parent places), with one difference kept from `layout-rules.md` §3b: a
child never draws smaller than its content, and the container clips what passes
the maximum.

### 4.2 The names

| Today | After |
| --- | --- |
| `ctx.available_width`, `ctx.available_height` | `ctx.minimum_width`, `ctx.maximum_width`, `ctx.minimum_height`, `ctx.maximum_height`, each a `Cell` or `nothing`; a `nothing` minimum is 0 and a `nothing` maximum is no edge |
| `with_available_size(ctx; width, height)` | `with_exact_size(ctx; width, height)`: minimum and maximum are the same cell |
| — | `with_bounded_size(ctx; width, height)`: minimum `nothing`, maximum the cell |
| `withhold_offer(ctx, axis)` | `withhold_offer(ctx, axis)`: minimum and maximum `nothing` |

The names follow `naming-rules.md`; Step 1 checks them against it again.

### 4.3 The calculation on one axis

**Names.** `∅` is "no value".

| Name | What it is |
| --- | --- |
| `m`, `M` | the range that the container itself received: its minimum and its maximum |
| `ins` | the container's own insets on the axis: margin, border, padding, bands |
| `B` | the room inside the container: `B = M − ins`, or `∅` when `M = ∅` |
| `S` | the extent of the container when it is exact: `S = M − ins` when `m = M`, else `∅` |
| `g`, `n` | the gap between children, and the count of children |
| `minᵢ prefᵢ maxᵢ wᵢ` | the placement of child `i`; a `∅` minimum counts as 0 |
| `(mᵢ, Mᵢ)` | the range that child `i` receives |
| `eᵢ` | the extent that child `i` draws |
| `A` | the size that the child authored, or `∅` |
| `C(x)` | the content's extent when it may use `x`. Rigid: `C(x) = C`. Reflowing: laid out at `x`, so `C(x) ≤ x` unless a piece that can not break is longer. `C(∅)` is the content with no edge |

**The child.** Every printer follows one rule:

```
e = A                  when A ≠ ∅
e = max(m, C(M))       otherwise
```

| State | Result |
| --- | --- |
| exact `(s, s)` | `max(s, C(s))`: stretch to `s`; text wraps at `s` (today's rule) |
| bounded `(0, l)` | `C(l)`: a button keeps its size; text wraps at `l` |
| free `(0, ∅)` | `C(∅)`: the natural size; text does not wrap |
| `(120, l)` | `max(120, C(l))` |

An overlay caps instead of stretching: `e = min(max(A, C(M)), M)`.

The container clips each child at the maximum it gave on each axis where it
gave one.

**The cross axis of a stack** (the width of each child in a column, the height
of each child in a row):

```
wᵢ > 0      (mᵢ, Mᵢ) = (B, B)
Fixed(k)    (mᵢ, Mᵢ) = (k, k)
otherwise   (mᵢ, Mᵢ) = (minᵢ, min(B, maxᵢ))           ← new: today (∅, ∅)
extent of the stack = S when S ≠ ∅, else maxᵢ eᵢ
```

**The main axis of a stack** (the width of each child in a row, the height of
each child in a column):

```
Fixed(k)                  (mᵢ, Mᵢ) = (k, k)                                 ← new on this axis

unweighted (wᵢ = 0)       mᵢ = minᵢ
                          Mᵢ = B − g·(n−1)
                                 − Σ(j < i, wⱼ = 0) eⱼ                       the unweighted before it, drawn
                                 − Σ(j > i, wⱼ = 0) minⱼ                     the unweighted after it, their minimums
                                 − Σ(wⱼ > 0) minⱼ                            the weighted, their minimums
                          Mᵢ = min(Mᵢ, maxᵢ)                                 ← new
                          (Mᵢ = ∅ when B = ∅)

weighted, S ≠ ∅           a = allocate_axis(S; min, max, pref, w, g), with prefⱼ = eⱼ for the unweighted
                          (mᵢ, Mᵢ) = (aᵢ, aᵢ)                                (today)

weighted, S = ∅           as unweighted                                      ← new

extent of the stack = S when it distributes, else Σ eᵢ + g·(n−1)
```

Every value reads only values computed before it: the unweighted children in
their order, then the allocation. No cell reads its own result.

**A grid.** A column is to its cells what a child is to a row. A weighted or
`Fixed` column gives its cells `(x, x)`, where `x` is its width. A `Content`
column gives `(0, X)`, where `X` is the column's maximum from the main-axis
formula over the columns. The rows are the same on the other axis.

**A container with one content** (a viewport, a shell, a split slot, a tab
page, a pane, a card) passes its own range on, less its insets, in the same
state: an authored size `A` gives `(A − ins, A − ins)`; an exact range gives
`(S, S)`; a bounded range gives `(0, B)`; a free axis gives `(0, ∅)`. On an axis
where its extent comes from its content (the height of a card), it gives
`(0, ∅)`, as today. A viewport in a bounded parent therefore takes its
content's extent up to the edge, and clips and scrolls past it.

**Text and flow.** `WordWrapping` wraps at `M`, and does not wrap when `M = ∅`.
`FlowLayout` breaks at `min(max_width, M)`, where `max_width` is `∅` unless a
caller wrote it.

**The root.** The window gives its content `(size, size)`.

### 4.4 Worked examples

These become tests (Step 3 and Step 4).

1. A column that receives `(500, 500)`, with a label (40), a long paragraph and a
   button (30), all `Content`:

   ```
   today:       40;  wraps at 800 and is cut at 500;  30
   new:         each receives (0, 500):  40;  C(500) ≤ 500;  30
   child_width = Fill, today and new:  500; 500; 500
   ```

2. A row that receives `(400, 400)`, `g = 8`: a label "Name:" (50), a field with
   `Fill`, a button "Go" (30):

   ```
   M₁ = 400 − 16 − 0 − 0 − 0 = 384     e₁ = 50
   M₃ = 400 − 16 − 50 − 0    = 334     e₃ = 30
   a₂ = allocate(400; pref = [50, 0, 30], w = [0, 1, 0], g = 8) = 304
   ```

3. A row that receives `(400, 400)`, `g = 8`, with two long paragraphs, both
   `Content`:

   ```
   M₁ = 400 − 8 − 0   = 392     e₁ = 392
   M₂ = 400 − 8 − 392 = 0       the second paragraph has no room
   ```

   The order decides. To share a row between two children that reflow, the
   placement gives them weights: with `child_width = Fill` each receives
   `(196, 196)`. This is the one combination where `Content` is not enough on
   its own, and `layout-rules.md` says so.

4. A card 300 wide: the card gives its body `(300 − ins, 300 − ins)` on the
   width. A label in the body, rigid, stretches to it as today; the card's text,
   reflowing, wraps at it, and the card no longer computes a text width of its
   own.

## 5. What changes where

### 5.1 projectured-julia

| File | Change |
| --- | --- |
| `source/kernel/projection/PrinterContext.jl` | the range, the helpers of §4.2 |
| `source/kernel/projection/ProjectionInterface.jl`, `ProjectionModule.jl` | the exports and the mentions |
| `source/screen/ScreenToScreen.jl`, `ScreenDocument.jl`, `source/sdl/Sdl.jl` | the root gives `(size, size)` |
| `source/layout/LayoutToGraphics.jl` | the stacks, the grid, the flow, the constraint and stack layouts |
| `source/widget/WidgetToGraphics.jl` | `_resolve_size`, `_resolve_overlay`, the shell, the split, the tabbed pane, the viewports, the card, the accordion, the toolbar, the menu, the table |
| `source/widget/WidgetTableList.jl` | a wrapping cell reads the maximum; the local rule goes |
| `source/text/WordWrapping.jl` | wraps at the maximum; the 800 goes |
| `source/pane/PaneToWidget.jl` | passes the range |
| `source/chart/ChartPlotToGraphics.jl`, `source/sequencechart/SequenceChartPlotToGraphics.jl` | read the maximum |
| `source/fault/FaultLogOverlay.jl`, `source/gesturelog/GestureLogOverlay.jl` | place their panel against the maximum |
| `source/conversation/EvaluatorToWidget.jl` | the rows go back to `Content` |
| 15 test files that name `available_width` or `with_available_size` | follow the names |

No file under `source/kernel/` that this plan touches is sealed today
(`SEALING.md`); each step checks again before it edits one.

### 5.2 omnet-julia

19 files read `available_width` or call `with_available_size`, among them
`TimelineView.jl`, `SimulationEmbedToWidget.jl`, `CatalogShellToWidget.jl`,
`OmnetWorkbenchToWidget.jl`, `SimulationWorkflowToWidget.jl`, and tests. They
follow on a branch of their own, tested against the projectured-julia worktree
through a scratch environment, and land right after it. inet-julia reads none.

## 6. The steps

Each step: the code, its tests, **the documents it makes wrong**, a baseline
diff of the suites it touches against the counts before the step, and a commit.
Step 0 takes the baseline.

- [ ] **Step 0: the baseline.** `test_all()` of projectured-julia, and the
      omnet-julia suites of `plan/pending/widget-constructors-live-values-and-a-pointer.md`
      Step 2, before any change. The places of the failures are kept.

- [ ] **Step 1: the range in the context.** `PrinterContext` gets the four
      values; `with_exact_size`, `with_bounded_size` and `withhold_offer` make
      them. `available_width` and `available_height` stay readable, as the
      maximum of an exact range and `nothing` otherwise, so that every reader
      works unchanged until Step 5. No behaviour changes.
      - Tests: the helpers, and `available_width` of each state.
      - Documents: the docstring of `PrinterContext`;
        `documentation/package/kernel/projection-system.md` (the context);
        `documentation/rule/naming-rules.md` (the `with_…` example).

- [ ] **Step 2: the child rule.** `_resolve_size` becomes `max(m, C(M))`;
      `_resolve_overlay` caps at `M`; `WordWrapping` wraps at `M` and loses its
      800; `FlowLayout` breaks at `min(max_width, M)` and its `max_width` is
      `nothing` by default. No container gives a bounded range yet, so the only
      change a user sees is text that has no edge: it no longer wraps at 800.
      - Tests: the child rule in each of the four states of §4.3, for a rigid
        widget, a wrapped text, an overlay and a flow, asserting the drawn
        extent.
      - Documents: `documentation/package/text/text.md` (the wrap width);
        `documentation/package/widget/widget.md` (how a widget sizes itself);
        `documentation/rule/layout-rules.md` §1 (the rule) and §3b (who
        clips).

- [ ] **Step 3: the containers and the cross axis.** The root, the viewports,
      the shell, the split, the tab page, the pane tree and the card give exact
      ranges as today; the cross axis of the stacks gives a `Content` child
      `(minᵢ, min(B, maxᵢ))`; the grid gives a `Content` column's cells
      `(0, X)`.
      - Tests: examples 1 and 4 of §4.4 as render tests, asserting the
        coordinates at two widths; a render test that fails on the code before
        the step.
      - Documents: `documentation/package/layout/layout.md` ("The size that a
        parent offers"); `layout-rules.md` §2 (where a policy lives) and §3
        (what a container offers).

- [ ] **Step 4: the main axis of the stacks.** The formula of §4.3 for the
      unweighted children, `Fixed` on the main axis, and a weighted child in a
      stack that is not exact.
      - Tests: examples 2 and 3 of §4.4; a test that a stack of stacks with
        bounded ranges on both axes does not loop.
      - Documents: `layout-rules.md` §4 (when a stack distributes) and §5 (the
        worked case), with example 3 and its rule for two children that
        reflow.

- [ ] **Step 5: the patches go, and the old names.** The toolbar gives its
      items a bounded range instead of withholding the width; the table list
      and the card lose their own text widths; `_resolve_overlay` is the
      overlay form of the child rule; the evaluator rows go back to `Content`.
      `available_width`, `available_height` and `with_available_size` go, and
      every reader of §5.1 reads the range.
      - Tests: the toolbar, the table list, the card and the overlays keep
        their current render tests; a render test of the evaluator row with a
        button result and with a long text result.
      - Documents: `widget.md` (the toolbar, the overlays, the table);
        `layout-rules.md` §6 (what this replaces).

- [ ] **Step 6: omnet-julia.** The 19 files follow the names and the model on
      a branch, with the baseline of Step 0 compared over both worktrees.
      - Documents: the two pending plans of omnet-julia that name
        `available_width` (`campaign-runner-run-table.md`, `qtenv-window.md`).

- [ ] **Step 7: the documentation, as a whole.** A search of both repositories
      for the old names and the old numbers (`available_width`,
      `available_height`, `with_available_size`, `800`, the "no offer" wording
      of `Content`) finds none outside `plan/done/`. `layout-rules.md`,
      `layout.md`, `widget.md`, `text.md` and `projection-system.md` are read
      end to end and agree with §4 and with each other; the design documents
      (`documentation/design/system-anatomy.md`, `engineer-tour.md`,
      `concepts.md`) are searched for statements about sizing; on 2026-09-24
      none of them names the context. The documentation index
      (`documentation/README.md`) still names every document with what it
      answers.

- [ ] **Step 8: the landing** of both repositories, when the owner says so.

## 7. The documentation, by step

| Document | Step | What changes |
| --- | --- | --- |
| `documentation/rule/layout-rules.md` | 2, 3, 4, 5 | the rule becomes the range; §1 the child rule; §2 and §3 what a container gives; §3b clipping at the maximum; §4 and §5 the main axis and the worked cases; §6 what this replaces |
| `documentation/package/layout/layout.md` | 3 | "The size that a parent offers" becomes the range |
| `documentation/package/widget/widget.md` | 2, 5 | how a widget sizes itself; the toolbar, the overlays, the table |
| `documentation/package/text/text.md` | 2 | `WordWrapping` wraps at the maximum and has no fallback |
| `documentation/package/kernel/projection-system.md` | 1 | the context carries a range |
| `documentation/rule/naming-rules.md` | 1 | the `with_…` example names the new helpers |
| docstrings of `PrinterContext`, `SizePolicy`, `Content`, `Fill`, `WordWrapping`, `FlowLayout` | 1, 2, 3 | the meaning in the range |
| omnet-julia pending plans | 6 | the names |
| every document | 7 | the search and the reading of Step 7 |

## 8. The relation to the other plans

`plan/pending/widget-constructors-live-values-and-a-pointer.md` records the
S4 take. A button that is the whole result of a form fills its row until Step 5
of this plan puts the evaluator rows back to `Content`. The owner decides
whether the real S4 take waits for Step 5.
