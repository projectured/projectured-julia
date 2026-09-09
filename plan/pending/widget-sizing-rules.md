# One sizing rule, and one place that parametrises it

> **Kind:** plan · **Status:** pending · **Stands on:**
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)

## The rule

> The settled rules live in
> [layout-rules.md](../../documentation/rule/layout-rules.md). This plan is how
> they were arrived at and what still has to change to reach them.

```
size(axis) = clamp( policy(axis) resolved against the parent's offer,
                    min(axis), max(axis) )
```

Four policies, one order, **both axes, every widget**. No constant, ever.

| policy | size on that axis |
| --- | --- |
| `Fixed(n)` | `n` |
| `Fill` | the parent's offer |
| `Content` | grows with content; the offer is ignored |
| `Relative(weight)` | a share of the parent's, through `allocate_axis` |

## Where the policy lives

**Not on the widget.** A policy is a statement about a *relationship*:
`Relative(1.0)` means nothing without a parent that divides, and `Fill` means
nothing without a parent that offers. The same `WidgetCard` must fill the width
in a conversation column and be content-wide in a toolbar, so the container
decides and the card is placed twice, unchanged.

It lives in **`LayoutConstraint`**, which already sits between a container and its
child and already carries `min` / `preferred` / `max` / `weight` per axis. It
gains the four policies.

**One home, not two.** A layout carries a *default constraint*, and a bare child
means "use it". A wrapper is the same type, written explicitly, for the one child
that differs:

```julia
VerticalLayout(gap = 6, align = :left;
               child = LayoutConstraint(; width = Fill, height = Content))
```

The root falls out of the same type: the window already offers a size, so a root
widget's default constraint is `Fill` on both axes.

## What a parent offers, and why it is not a choice

```
offer(axis) = my size on that axis    when my policy is Fixed, Fill or Relative
              nothing                 when my policy is Content
```

The second line is forced by the reactive graph, not by taste.
[LayoutToGraphics.jl:614](../../source/layout/LayoutToGraphics.jl#L614) states it:

> *"a vertical stack sizes its height from the sum of its children, so a child
> must not carry an `available_height` that ultimately reads this layout's own
> outer height — that closes a feedback loop and stack-overflows."*

A container whose size derives from its children must not hand that size back to
them. So the offer is **derived from the policy**, and no widget decides anything.

## What this dissolves

| written by hand today | becomes |
| --- | --- |
| `VerticalLayout` strips height ([614](../../source/layout/LayoutToGraphics.jl#L614)) | `height = Content` → offers nothing on that axis |
| `HorizontalLayout` strips width ([523](../../source/layout/LayoutToGraphics.jl#L523)) | the same, other axis |
| `WidgetCard` strips height ([3849](../../source/widget/WidgetToGraphics.jl#L3849)) | `height = Content` |
| `WidgetToolbar` strips width ([3522](../../source/widget/WidgetToGraphics.jl#L3522)) | `width = Content` |
| `WidgetScrollPane` seeds both axes ([3213](../../source/widget/WidgetToGraphics.jl#L3213)) | offers both; the **content's** policy decides whether it overflows |
| five size constants | a policy always yields a value |
| two inverted precedences | the policy *is* the precedence |
| `_resolve_width` with no height twin | one `_resolve_size(ctx, axis, constraint, content)` |

**There is no scroll-axis rule anywhere.** A viewport offers on both axes because
its own size is known independently of its content. Whether the content overflows
is the content's `Content` policy. Nothing knows which axis scrolls.

## What is there today

All 40 `print_document` methods of
[WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl), surveyed:

| pattern | width | height | widgets |
| --- | --- | --- | --- |
| A content only | content | content | Label, Insertion, Text, ContextMenu, MenuItem, Badge, RadioGroup, Toggle, ToggleGroup, Table, Tree, Tooltip |
| B `_resolve_width` | available → authored → ≥ content | content | StatusBar, Card, Progress, Slider, Alert, Skeleton, Select, Option, SpinBox, List, Textarea, Accordion |
| C own size | `w.size` | `w.size` | Button, Avatar, Highlight, Skeleton height, Separator |
| D viewport | available → own size → **400** | available → own size → **300** | ScrollPane, TransformPane |
| E container | `allocate_axis` | `allocate_axis` | SplitPane, TabbedPane, Dialog |
| F **no extent** | reports `0` | reports `0` | Menu, Composite, Shell, TitlePane, Toolbar, TabbedPane, ScrollBar |
| G theme number | literal | literal | Checkbox 18, Switch 44×24, Progress 8, Slider 24 |

A is B with no offer. C is B with the authored size winning. D is B plus a
constant. E is the allocator. F and G are absences.

The eight deviations: five size constants
(`_SCROLL_FALLBACK_WIDTH` 400, `_SCROLL_FALLBACK_HEIGHT` 300,
`_SCROLLBAR_FALLBACK_LENGTH` 200, `_SCROLLBAR_FALLBACK_THICKNESS` 16,
`_SPLIT_SLOT_FALLBACK` 200); four theme numbers acting as sizes; eight widgets
reporting `0 × 0`; two inverted precedences; no `_resolve_height`; the dead
`WidgetTooltip.size`; and the two hand-written erasures.

Only five printers read `w.size` at all: Button, ScrollPane, TransformPane,
ScrollBar, Avatar.

## The conversation, constructed

```julia
WidgetSplitPane(:vertical, [
  LayoutConstraint(WidgetScrollPane(conversation; follow_end = true, padding = 5);
                   width = Fill, height = Relative(1.0), min_height = 0),
  LayoutConstraint(WidgetScrollPane(draft; padding = 5);
                   width = Fill, height = Fixed(200)),
])

VerticalLayout(gap = 6, align = :left;
               child = LayoutConstraint(; width = Fill, height = Content))
  WidgetCard(title = header("user"))
    VerticalLayout(gap = 6, align = :left;
                   child = LayoutConstraint(; width = Fill, height = Content))
      WidgetCard(title = header("text"))
        <the part's own document>

LayoutConstraint(WidgetCard(title = header("text")); height = Fixed(30))  # collapsed
```

What each requirement rests on:

| requirement | what carries it |
| --- | --- |
| content fills horizontally | `width = Fill` in the layouts' default constraint; the literals `_CARD_WIDTH = 760` and `_PART_WIDTH = 720` are deleted |
| cards grow vertically with content | `height = Content` in the same default |
| collapse | `height = Fixed(30)` on one child — the clipping `WidgetScrollPane` in `_maybe_clip` disappears |
| the two halves scroll separately | the split's two `LayoutConstraint`s, `Relative(1.0)` and `Fixed(200)` — unchanged from today |
| the transcript actually scrolls | the column's `height = Content` outgrows the viewport the pane offers |

## A correction to the diagnosis

**The assistant's split pane bounds itself correctly, and did all along.**
Measured, with the canvas extent rather than a text dump:

```
the assistant chain, no offer            3 turns -> (410, 201)    12 turns -> (410, 201)
the assistant chain, offer 1200x900      3 turns -> (1200, 900)   12 turns -> (1200, 900)
```

An earlier reading of this plan said "the offer arrives and is ignored". That
rested on measuring the size of `print_object` over the drawn tree, and **a
viewport that clips still holds its whole content in the tree** — so that number
grows with the turn count whether or not anything is bounded. It could not answer
the question it was asked.

What is still unmeasured is whether the **window and the pane tab** deliver an
offer to the assistant at all. That measurement is blocked: the window's content
canvas reports `0 x 0`, which is deviation 3 — eight widgets report no extent.

**So step 7 is not cleanup.** It is what makes the chain measurable end to end,
and it should come before the rest.

## Steps

Each step keeps the images green before the next begins.

1. **The policy type — DONE.** `SizePolicy`, with `Fixed(n)`, `Content`,
   `Relative(w)` and `Fill`. It is **not** a fifth field: each policy writes the
   four that `LayoutConstraint` already has, so a size is decided in one place.
   `LayoutConstraint(child; width = Fill, height = Content)`; a field written
   beside a policy wins over it. **All 39 images unchanged** — nothing reads the
   vocabulary yet.

   `Fill === Relative(1.0)` falls out rather than being declared: two `Fill`
   siblings share the offer equally, which is what a weight of one each means.
2. **`_resolve_size(ctx, axis, intrinsic, content_min)` — DONE.** The rule,
   once, both axes: the offer if there is one, else the authored value, never
   under the content. `_resolve_width` and the new `_resolve_height` are calls to
   it. **All 39 images unchanged.**
3. **The offer is derived — DONE.** `withhold_offer(ctx, axis)` in
   `PrinterContextModule` is the rule, written once: a container whose extent on
   an axis comes **from** its children must not offer that extent back down, or a
   child reads the container's own outer size and closes a reactive cycle. The
   four hand-written copies now call it — `VerticalLayout` (`:y`),
   `HorizontalLayout` (`:x`), `WidgetCard` (`:y`), `WidgetToolbar` (`:x`).
   **All 39 images unchanged.**

   The scroll pane is untouched, and that is the point: its own extent does not
   come from its content, so it offers on **both** axes. Nothing anywhere knows
   which axis scrolls.
4. **A default policy on each stack — DONE.** `VerticalLayout` and
   `HorizontalLayout` carry `child_width` and `child_height`, and a bare child
   means "use them". `layout_min` / `layout_max` / `layout_preferred` /
   `layout_weight` take the default as a last argument; a `LayoutConstraint`
   wrapper still wins over it. **All 39 images unchanged.**

   The default is two `SizePolicy` fields rather than a childless
   `LayoutConstraint`, because a constraint's `child` is required and a
   child-less one would be a second shape of the same idea. The vocabulary is
   still one type.

   `GridLayout`, `FlowLayout` and `StackLayout` do not carry a default yet: they
   allocate differently and none of them is in the conversation's path. They
   follow when a case needs them.

   **The instrument earned its place here.** Two new fields changed the
   all-positional arity of both stacks from four to six, and four call sites
   passed four — `MarkdownToLayout`, `CollectionToLayout`, `RstToLayout` twice,
   and the conversation. `conversation_widget` stopped drawing, the comparison
   said `GONE`, and the `.failed` file named the arity.
5. **Every widget resolves through `_resolve_size`.** Patterns A, B, C and D
   collapse into it. Split into reviewable pieces, because this touches 40
   widgets and each piece is meant to be looked at:

   - **5a — the two inverted precedences — DONE.** `WidgetScrollPane` and
     `WidgetTransformPane` let an authored size win over an offer, as every other
     widget already does. **All 39 images unchanged**, because no example both
     authors a size and receives an offer. Measured where they do not reach:
     an authored `120x60` under an offer of `900x700` now draws `120x60`, and
     drew `900x700` before. That is what lets a card set its panes' size and keep
     it.
   - **5b — the height half — four widgets DONE.** `WidgetStatusBar`,
     `WidgetAlert`, `WidgetCard` and `WidgetTextarea` resolve height through
     `_resolve_height`: the offer if there is one, else the authored value, never
     under the content. **All 39 images unchanged.** Measured where they do not
     reach: a card that drew `200x86` with no offer draws `900x700` under one, and
     filled the width only before. The remaining pattern-B widgets follow.

     **What this exposed about the safety net.** Every example draws its widget
     standalone, inside a composite or a vertical stack — and both of those offer
     no height. So the 39 exercise the *content* path and never the *offer* path,
     which is the path every remaining step changes. The net still catches
     breakage, as it did at step 4, but it cannot judge whether filling is right.
     A fixture that puts widgets under a real offer is needed before the net means
     what the plan claims.

   - **`widget_offered` — the fixture — DONE.** A `WidgetShell` of a known size
     seeds its extent into its content on both axes; a horizontal split divides
     that width between two columns. The left column holds an alert and a card
     that must **fill** what they are given; the right holds one scroll pane that
     **authored** `200x90` and one that authored nothing. Both panes are filled
     with colour, because a fixture that guards a size has to draw the size it
     guards.

     Looked at: the alert and the card stretch to the 380-wide slot, the authored
     pane draws `200x90` against an offer of the whole column, and the pane with
     no size fills the column. That is both branches of 5a and the width half of
     5b, visible. The example set is **40** now, and the baseline holds it.
   - **5c** — pattern A and C resolve through the rule.
6. **Delete the five constants — BLOCKED, and the block is the finding.**
   Tried, reverted. `widget_offered` changed by 26.7 % and the change was a
   regression: **the scroll pane with no authored size vanished.**

   Why it vanished is what the constant was hiding. That pane sits in a
   `VerticalLayout`, which withholds its main axis (height) from its children
   because its own height is the sum of theirs. A viewport takes no size from its
   content — that is what a viewport is. So the pane had no authored height, no
   offered height, and no content height, and its whole height was
   `_SCROLL_FALLBACK_HEIGHT = 300`.

   **A stack cannot give a child a share of its main axis**, because its own main
   axis is the sum of its children and a share of an unknown total is a cycle. So
   a scrolling pane inside a column can only get a height by authoring one.

   The capability that is missing: **a stack whose main axis is offered should be
   able to fill it and distribute it**, rather than always summing its children.
   Then a column inside a split takes the height the split passes across, and can
   allocate it — and the constant has nothing left to hide.

   That is a new step, and it comes before this one:

   **6a — a stack distributes its main axis when a child asks — `VerticalLayout`
   DONE.** No policy is declared on the layout. The condition is derived:

   ```
   filling = ctx.available_height !== nothing && any child carries a weight on :y
   ```

   A child asking for a share can have one only when the layout was offered a
   height itself; a share of a sum of its own children is the cycle. Both
   conditions together decide, so nothing has to be written on the layout.

   **Only a weighted child is offered a slot.** Every other child keeps the
   withheld axis, so its height does not depend on the allocation, and reading it
   to compute the allocation closes no loop. That is the same trick `_split_build`
   uses, arrived at from the other side.

   Measured on the case that started this:

   ```julia
   VerticalLayout(Any[
       WidgetLabel(Point2D(0, 0), "header"),
       LayoutConstraint(WidgetScrollPane(...); height = Fill),
   ]; gap = 6)                                     # the layout declares nothing
   ```

   ```
   window      : 300 x 400
   scroll pane : 374 px tall     (was 300, from _SCROLL_FALLBACK_HEIGHT)
   unused below:   0 px          (was 74)
   ```

   **All 40 images unchanged**, because nothing in them carries a weight yet.

   **6b — `HorizontalLayout` — DONE.** The mirror of the same, on `:x`. All 40
   images unchanged.

   **6c — the constants are gone — DONE.** All five deleted;
   `grep -c FALLBACK source/widget/WidgetToGraphics.jl` answers `0`.

   The fixture's unsized pane is wrapped in `height = Fill` first, so it shows the
   working arrangement rather than the constant. **One picture moved, and it is
   right**: that pane was `300 px` — the constant — and stopped short of the
   bottom with a grey band under it; it is `318 px` now and reaches the edge.
   `420 - 90 (the authored pane) - 12 (the gap) = 318`. The authored pane is
   unchanged at `200x90`.

   **Two more were hiding outside the surveyed file.** `_SHELL_FALLBACK_WIDTH`
   1280 and `_SHELL_FALLBACK_HEIGHT` 720 in
   [WorkbenchToWidget.jl](../../source/workbench/WorkbenchToWidget.jl) — the survey
   read `WidgetToGraphics.jl` only. Deleting them broke a workbench click test,
   which drew the shell with `print_document(proj, doc)` — a bare context, no
   offer — and clicked coordinates that existed only because of the 1280.

   The test says its window size now: a shell outside a window has no extent, and
   a test that clicks at a coordinate has to say how big the window is rather than
   let a printer invent it. `test_workbench()` is back to its baseline, 108 pass,
   1 broken, 0 fail.
7. **The eight zero-extent widgets report a real extent** — each is a container,
   so its extent is the bounds of what it drew. The largest step; it moves alone.

   - **7a — the five auto-extent canvases — DONE.** `_reactive_canvas_auto` reads
     the bounds of its elements instead of answering `0 x 0`:
     `WidgetMenu`, `WidgetComposite`, `WidgetShell`, `WidgetTitlePane`,
     `WidgetToolbar`. `graphics_size` already existed for exactly this.

     A projection that measures nothing — a composite holds already-drawn
     canvases, not words — has no `measure` field, so `_p_measure` answers
     `nothing` and the measure-free form is used.

     **One picture moved, and it is right: `widget_split_pane` now draws its
     splitter.** Before, the left title pane reported zero width, so the divider
     had nowhere to sit; now the pane reports what it drew and the splitter
     appears between the two. 162 bytes of 70 kB, same canvas size.

   - **7b — the 3-argument `_make_canvas` — DONE.** It reports the bounds of its
     children too, which covers `WidgetTabbedPane`, `WidgetScrollBar`, the split's
     empty case, and every inner offset wrapper built the same way. The bounds are
     a computed cell, because a child's own extent may be a cell with no value yet
     when the canvas is built. **All 40 images unchanged.**

     **And the blocked measurement now reads.** Through the real chain — window,
     screen, pane tree, tabbed pane, tab, assistant — at a window of 1200x900:

     ```
     3 turns  -> (1196, 892)
     12 turns -> (1196, 892)
     ```

     The transcript does **not** grow with the turn count. The offer reaches the
     assistant and the split honours it, end to end.
8. **The four theme numbers — EXAMINED, no change.** The checkbox's 18, the
   switch's 44×24, the progress bar's 8 and the slider's 24 are constructor
   arguments to those projections, set at the `WidgetToGraphics(…)` factory beside
   the theme's colours. A caller building the projection passes its own.

   They are each widget's **content** on that axis, which the rule allows — a
   checkbox's box *is* its content. The test is not whether a number appears but
   whether anyone can choose it, and these are chosen in the open. The rules
   document says so now, so this is not re-litigated.
9. **The overlays — `WidgetTooltip` DONE.** The field is not deleted; it is
   honoured. `_resolve_overlay(ctx, axis, authored, content)` is the overlay rule:
   the size the caller asked for is one floor, the content is the other, and the
   parent's offer is the **ceiling** — an overlay is capped by its window, never
   stretched to it. A tooltip that filled its window would be a panel.

   **One picture moved and it is right.** `widget_tooltip` went from `184x38` to
   `360x56` — which is exactly the `Point2D(360, 56)` the example has always
   passed and the printer has always ignored. The line claiming "at least the
   requested size" is true now.

   `WidgetContextMenu` and `WidgetMenu` still read no offer, so they can run off
   a window edge. They take the same helper next.
10. **The conversation is rebuilt** as constructed above: the two width literals
    and `_maybe_clip`'s scroll pane are deleted.

## The safety net: every widget, before and after

39 examples — 37 widget ones plus `widget_disabled`, `widget_focus` and
`conversation_widget`:

```
widget  label  text  checkbox  button  button_action  button_image  tooltip
menu_item  menu  toolbar  composite  title_pane  split_pane  scroll_bar
scroll_pane  transform_pane  shell  tabbed_pane  badge  separator  card  switch
progress  slider  radio_group  avatar  alert  skeleton  toggle  toggle_group
select  textarea  accordion  table  tree  disabled  focus     + conversation_widget
```

At every step:

1. write all 39 into `before/` on the step's base commit;
2. take the step;
3. write all 39 into `after/`;
4. compare each pair — identical, changed pixels, changed size.

**A changed picture is not a failure and an identical one is not success.** Steps
5 through 10 are meant to change what things look like. What the comparison buys
is that every change is one somebody looked at and named, so each step's commit
records, per example, either "unchanged" or one line saying what moved and why it
is right.

`tool/widget-images.jl` does the writing and the comparing, so this is a command
and not a description.

## What "done" means

- One `_resolve_size`, both axes, called by every widget.
- `grep -c FALLBACK source/widget/WidgetToGraphics.jl` answers `0`.
- No widget reports `0 × 0`.
- No widget document carries a layout field; no printer strips an axis by hand.
- The 39 images differ from the base only where a step said they would.
- In the campaign window: the transcript scrolls, the composer stays put, a card
  fills the width and grows with its content, and a collapsed card is 30 tall.

## Decided

1. **`Fixed(n)` IS `preferred` with `min = max = n`.** `LayoutConstraint` already
   carries `preferred_width`; a fifth field saying the same thing would be a
   second way to say one thing. `Fixed` is a constructor over the three fields
   that exist.
2. **A container with no children reports `0`**, and a test separates that from
   the eight widgets that report `0` today by accident. The images cannot tell
   them apart, so the test is what makes step 7 checkable.

## Step 0 — the instrument comes first — **DONE**

`tool/widget-images.jl`, written before step 1, because every step is measured
with it:

- `write_widget_images(directory)` — all 39 examples into that directory;
- `compare_widget_images(before, after)` — per example: identical, or the changed
  pixel count and any size change.

The baseline is taken on the commit this branch starts from.

All 39 draw. The comparison was checked against a deliberately corrupted image
and reported it: `widget_card  CHANGED  same size 330x132  45 bytes differ`.
`write_image` is a backend seam, so the tool loads `ProjecturedSdl` to fill it.
