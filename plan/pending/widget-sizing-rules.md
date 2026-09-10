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

   The scroll pane is untouched at this step: on an axis where it has an extent,
   that extent does not come from its content, so it offers there. Step 10
   completes the rule for the axis where it has none. Nothing anywhere knows
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
   follow when a case needs them. **`GridLayout`'s case arrived** — the run table
   of the campaign runner — and it is steps 14 to 17.

   **The instrument earned its place here.** Two new fields changed the
   all-positional arity of both stacks from four to six, and four call sites
   passed four — `MarkdownToLayout`, `CollectionToLayout`, `RstToLayout` twice,
   and the conversation. `conversation_widget` stopped drawing, the comparison
   said `GONE`, and the `.failed` file named the arity.
5. **Every widget resolves through `_resolve_size`** — and the rest of this was
   **not mechanical**, which was the finding. `_resolve_width` treated an authored
   width as a *minimum* and let an offer win; step 5a made the two viewports do the
   opposite. Both are defensible and the codebase did both. What `w.width` *means*
   was a decision, not a refactor, and a person made it: it is a fixed size.

5. **Every widget resolves through `_resolve_size` — DONE.** Patterns A, B, C
   and D collapse into it. Split into reviewable pieces, because this touches 40
   widgets and each piece is meant to be looked at:

   - **5a — the two inverted precedences — DONE.** `WidgetScrollPane` and
     `WidgetTransformPane` let an authored size win over an offer, as every other
     widget already does. **All 39 images unchanged**, because no example both
     authors a size and receives an offer. Measured where they do not reach:
     an authored `120x60` under an offer of `900x700` now draws `120x60`, and
     drew `900x700` before. That is what lets a card set its panes' size and keep
     it.
   - **5b — the height half — DONE, in two passes.** `WidgetStatusBar`,
     `WidgetAlert`, `WidgetCard` and `WidgetTextarea` resolve height through
     `_resolve_height`: the offer if there is one, else the authored value, never
     under the content. **All 39 images unchanged.** Measured where they do not
     reach: a card that drew `200x86` with no offer draws `900x700` under one, and
     filled the width only before.

     **The other seven followed later**, when steps 14 to 17 had made the offer
     reach places it never had: Select, Option, SpinBox, List, Accordion, Progress
     and Slider each computed a height by hand. **All 42 images unchanged**, and
     that is the point — no example offers those widgets a height, so the pictures
     cannot judge this and the measurement is the check:

     | | no offer | offered 900×700 |
     | --- | --- | --- |
     | select | 220×38 | 220×**700** |
     | option | 95×38 | 900×**700** |
     | spin box | 77×38 | 900×**700** |
     | list | 200×114 | 200×**700** |
     | accordion | 412×108 | 900×**700** |
     | progress | 260×8 | 260×**8** |
     | slider | 260×24 | 260×**24** |

     **The last two rows are a correction to the rules, and the measurement is
     what forced it.** Step 8 called a style parameter the widget's *content* on
     that axis. Routed as content, the progress bar drew `260×700` — content loses
     to an offer, and a 700-pixel progress bar is not a progress bar. Such a
     number is what the widget **authored**: it is `Fixed`, it wins over the
     offer, and a caller who wants a thicker bar passes one to the projection.
     `documentation/rule/layout-rules.md` §1 says so now, and `WidgetSkeleton`
     had already been written that way.

     **One widget resolves neither axis, and it is left alone on purpose.**
     `WidgetToggleGroup` sums its segment widths and adds its padding to a text
     height, and 5c's sweep of pattern A did not reach it. Its width is not a
     one-line change: `iomap.segment_widths` is what its reader hit-tests a press
     against, so a group that filled an offer would have segments that no longer
     tile it and a press near the right edge would miss. It needs the segments to
     divide the allocation, which is `allocate_axis` on a control rather than a
     container — a step of its own, and nothing offers a toggle group a width
     today.

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
   - **What `w.width` means — DECIDED and DONE.** It is `Fixed`. A caller that
     wrote a number meant it, so it wins over the offer, and the content does not
     raise it. Twelve pattern-B widgets treated it as a floor the offer overrode,
     so a caller who wrote `220` got whatever the parent had.

     **This exposed the constant the survey missed.** Eight document constructors
     carried a **default** width — Card 320, Alert 360, Accordion 360, Select 220,
     Option 220, SpinBox 120, List 220, Textarea 320. A default that wins over
     every offer is the constant §1 forbids, wearing a keyword: nobody wrote it,
     and it cannot be told from a size somebody chose. Those are `0` now.
     Progress, Slider, Skeleton, Highlight and Avatar keep theirs, because they
     have no content to measure and there the number **is** the content.

     Two pictures moved and both are right. In `widget` the select, slider and
     textarea are `220`, `260` and `340` — exactly what the example authored and
     what was ignored, and the select's chevron is no longer pushed off its own
     box. In `conversation_widget` the cards are their content's width instead of
     at least `320`. Card, alert and accordion are byte-identical again once the
     defaults are gone.
   - **5c — pattern A and C resolve through the rule — DONE.**

     **Pattern C first** — Button, Separator, Skeleton, Highlight each compared an
     authored size against their content by hand, and the button's field was
     named `minimum_size`. All 40 images unchanged: every example authors a size
     larger than its content, so `max` and `Fixed` agree there.

     **Then the prerequisite the plan did not name.** `child_width` and
     `child_height` were read on the main axis only. On the cross axis a stack
     passed its own offer to every child, so `Content` could not be said there at
     all — and pattern A filling would have stretched every badge in every column.
     `_cross_context` is the same rule on the other axis: a weight takes the
     offer, a declared preferred extent takes that number, anything else is
     `Content` and the offer is withheld. A bare child has weight `0`, so
     `Content` is the default and nothing had to be declared to get it.

     `widget_offered` says `child_width = Fill` on both columns now. It was the
     one example living off the pass-through — with the two words written down,
     all 40 images are identical to before the change.

     **Then pattern A** — Label, Badge, Toggle, MenuItem, RadioGroup, and
     `WidgetText` in both its branches. All 40 images unchanged, which is the
     cross-axis policy working. Measured where the examples do not reach, the
     same badge column under an offer of `500`:

     ```
     bare column        115 wide
     child_width=Fill   500 wide
     ```

     **Three printers are left, each for its own reason.** `WidgetToggleGroup`'s
     width is the sum of its segments, so filling means distributing the slack
     among them with `allocate_axis`. `WidgetTable` and `WidgetTree` build their
     canvas from a column geometry, which has to fill before the canvas can. None
     of the three is a deviation from the rule — each is a container whose
     children have to share what it fills.
6. **Delete the five constants — DONE, and the block it started as is the
   finding.**
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
7. **The eight zero-extent widgets report a real extent — DONE.** Each is a
   container, so its extent is the bounds of what it drew. The largest step; it moves alone.

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

   **`WidgetContextMenu` and `WidgetMenu` — DONE.** Both are capped now.
   `_reactive_canvas_auto` takes an optional `cap` context for the menu, whose
   extent is computed by that helper rather than in its own printer. All three
   overlays read the offer as a ceiling. **All 40 images unchanged.**
10. **The conversation — DONE, the two width literals are gone.** A turn card and
    a part card take the width they are offered; the transcript's `child_width = Fill`
    says so and `WidgetCard` resolves it. `760` and `720` made every conversation
    the same width whatever it was shown in.

    **One picture moved.** `conversation_widget` went from `760x798` to `752x798`
    and its cards are content-wide rather than 760 — because that example draws
    the conversation with **no offer**, so content is the only source left. In a
    window there is an offer and they fill. Correct by the rule, and the picture
    is honest about what the example does.

    **The collapse clip — DONE, and it removed the last literal.** `_maybe_clip`
    returns `LayoutConstraint(body; height = Fixed(30))`, and `WidgetCard` reads
    that constraint: `_card_body` turns a pinned height into a `WidgetScrollPane`
    with **no size at all**, printed with a context whose `available_height` is
    that number. The pane needs no `Point2D`, so no width is written anywhere.

    **This exposed the real gap, and it is the scroll pane's.** A pane with no
    authored size and no offer answered `0` on that axis, so the collapsed card
    lost its width and `conversation_widget` went `752 -> 594`. That `0` was the
    one place the rule of §1 stopped one policy short: a viewport had `Fixed` and
    the offer, but no `Content`.

    `_pane_extent(offer, content_cell)` is that missing policy, written once. An
    axis with an offer clips against it. An axis with none withholds the offer,
    lets the content size itself, and takes the content's extent. The two cannot
    cycle: a clipped axis offers a cell the content reads, an unclipped axis reads
    a cell the content produces. The printer recurses **before** it builds its
    extent cells, because on an unclipped axis the extent is the content's.

    **One picture moved and it is right.** `conversation_widget` went `752x798` to
    `854x798`: the collapsed thinking card is still clipped to the same one row,
    but its width is its text's rather than the deleted `_CARD_WIDTH`. That card
    is the widest thing in the example, so the canvas grew to it. The example
    draws with no offer, so content is the only source left — in a window there is
    an offer and the cards fill it. **The other 39 images are unchanged.**

11. **The suite found what the pictures cannot — DONE.** The 40 images guard what
    a printer draws. They say nothing about a test that clicks a coordinate, and
    nothing about a call site no example reaches. `test_substrate()` found both.

    **Three call sites still passed the old positional arity.** Step 4 added
    `child_width` and `child_height` to both stacks, and
    `ObjectToWidget._collapsible_card` (twice) and `EmbedToSyntax` (once) still
    passed four positional arguments. Each threw a `MethodError` at print time.
    Five tests failed for it, and **they were already failing on `main`**, which
    carries steps 0 to 7b. The fix adds the two fields. No picture changed,
    because no example reaches those two files. **56018 pass against main's
    53735**: 2270 assertions could not run before.

    **A split pane with no offer gave every slot zero.**
    `ProjectionConfiguringTest` clicks a checkbox in a control bar and prints with
    a bare `PrinterContext()`. The split then offered each child a slot of `0`,
    the children drew nothing, the pane reported a height of `1`, and no click
    reached anything. `_SPLIT_FALLBACK` used to make that pane `400x401`.

    The fix is the rule of §3, which the split was the last container to miss: an
    axis it cannot divide is an axis it must not offer. It now withholds the main
    axis when there is no offer, and each slot is the child's declared size or
    what the child drew. The checkbox is hit at `x = 175..185` again, the same
    band as on `main`. **All 40 images unchanged.**

    **What this says about the safety net.** Every remaining failure on this
    branch is also on `main`, and five of main's are fixed here. The pictures were
    necessary and not sufficient: a size that nothing draws still has to be right.

12. **Whoever hands out a slot clips it — DONE.** The campaign window found
    this, and it is the last thing between the rules and a working conversation
    pane. Three symptoms, one cause.

    A tab's content is drawn over the tab strip, the transcript and the composer
    scroll as one block, and the wheel only answers at the left edge of the pane.
    The cause is [PaneToWidget.jl:364](../../source/pane/PaneToWidget.jl): every
    tab's content is wrapped in a `WidgetScrollPane`, and its own comment says
    why — "the scroll pane is what keeps a tab inside its own pane". It is there
    to **clip**, because `WidgetTabbedPane` does not clip its page, and a scroll
    pane was the nearest widget that owns a `GraphicsViewport`. Scrolling came
    along as a side effect, and that outer pane holds the transcript *and* the
    composer.

    Measured, at a window of 900x700, through the campaign's own projection:

    ```
    GraphicsViewport y=4    892x28                        the tab strip
    GraphicsCanvas   y=32   888x660  reaches (892, 692)   the page - NOT a viewport
      GraphicsCanvas y=32   892x664                       the pane scroll pane
        GraphicsViewport y=36 884x656                     its viewport
          the assistant, reaching (884, 651)
    ```

    The page declares `888x660` and reaches `892x692`. The assistant itself is
    right: offered `800x600` it draws `800x595` at 0 turns and at 9.

    Only three printers clip anything today — `WidgetScrollPane`,
    `WidgetTransformPane`, and the tab **strip** of `WidgetTabbedPane`. Not a
    split's slots, not a card's body, not a tab's page.

    The rule is §3b of [layout-rules.md](../../documentation/rule/layout-rules.md),
    written down first because it is the reasoning that is expensive to rebuild.

    - **12a — the tab page is a viewport — DONE.** The page was
      `_make_canvas(cox, coy + sel_h, [content])`, a plain positioned canvas. It
      is a `GraphicsViewport` of the slot the content was offered, per bounded
      axis. One picture moved by two pixels: `widget` is `1024x768` rather than
      `1026x768`, the page no longer overhanging its own inset.
    - **12b — the pane domain stops wrapping — DONE.** `PaneToWidget` hands the
      tab its content directly, and the campaign's chain is one viewport of
      `884x656` holding an assistant that reaches `884x651`. Two nested viewports
      became one, and the only scrollers left are the assistant's own.

      Three things travelled with the wrapper, and one of them was a finding.
      The reference paths named `::WidgetScrollPane`; the node under
      `selector_element_pairs[i]` is the tab's own content now, whose type differs
      per tab, so the checkpoint is read with `get_reference_node_type`.
      `_PANE_PADDING` was 4 pixels on top of the tabbed pane's own 4, and the pane
      border carries the whole 8.

      **`_after_content_step` was dead code.** It looked for a `content` step —
      the scroll pane's field — but `selector_element_pairs[i]` names a `Pair` and
      every deeper path starts with that pair's `element`, so it never matched and
      the backward map always answered with the tab. Removing the wrapper is what
      made that visible. The code says so now, and says that a selection inside a
      tab's content travels by `_forward_selection!` instead.
    - **12c — a split clips its slots — DONE.** Main axis always, cross axis when
      it was offered one. It reports its slots now rather than what its children
      reached: `widget_split_pane` goes `433x54` to `601x54`, and `601` is what
      the example asked for — `sizes=[300, 300]` plus the splitter. The old `433`
      was the two labels, and the authored sizes were ignored. `SplitPaneDragTest`
      read a child's position off the `GraphicsCanvas` elements of the output; a
      slot is a `GraphicsViewport` now, and the test says so.
    - **12d — a card clips its body's width — DONE**, and not its height, which
      comes from the content. All 40 images unchanged.

    **What is left open.** A tab holding a raw document scrolled only because the
    clipper happened to be a scroll pane. Clipping and scrolling are separate
    needs: such a tab must bring a `WidgetScrollPane`, or `PaneTab` must carry a
    parameter saying its content scrolls. That is a decision, not a refactor.

13. **The campaign window, run — DONE, and it found three faults.** The plan's
    last acceptance line is the one the work started for: in the campaign window
    the transcript scrolls, the composer stays put, a card fills the width and
    grows with its content, and a collapsed card is 30 tall. Running it found
    three faults that no image and no printed tree could show, because all three
    are about what an **event** does.

    - **A scroll pane did not clamp.** `_scroll_by` added the delta with no floor
      at `0` and no ceiling at `content - viewport`, so a pane scrolled its
      content clean out of its own viewport: a transcript that fits was pushed
      60 px above the top by one wheel notch. It clamps now, and a scroll that
      would move nothing answers `nothing` — which is also what lets an outer
      pane take over at the end of an inner one's travel.
    - **`follow_end` was a lock, not a state.** The printer's offset ignored
      `scroll_position` outright when following, so the wheel wrote a cell nothing
      read and a pinned transcript could not be scrolled at all. The wheel turns
      it now: scrolling away from the end releases the pin and starts from the
      end, and scrolling back to the end pins it again.
    - **A split a tab's content built lost its drag.** `PaneToWidget` answered
      every `ResizeSplitPaneOperation` by looking for a pane node holding that
      split, and returned `nothing` when it found none — and a split inside a
      tab's content has no pane node. The grab started and the first motion went
      nowhere. It passes the operation on now; the tree still declines to turn a
      foreign resize into a pane weight, which is all it ever meant to say.
      `PaneReaderTest` asserted the old contract by name, and asserts the new one.

    **And one the work itself introduced.** A split allocated the whole offer to
    its slots and then placed the first child at its own content origin, so a pane
    tree drew `1908x1208` in a `1900x1200` window. Moving `_PANE_PADDING` into the
    pane border at step 12b doubled that overhang and made it visible. Both panes
    report the box they were offered now.

    **What this says about the instrument.** The 40 images guard what a printer
    draws and `test_substrate()` guards what the projections answer. Neither can
    see a wheel or a drag, and all four faults above lived there. The measurement
    that found each of them was the same shape: build the campaign's own chain,
    send the event, and print what came back.
14. **The grid offers what it will give — DONE, and the picture found the half
    this plan had missed.** `GridLayoutToGraphicsCanvas` recursed every child with
    the parent's own context, so each cell was offered the grid's whole extent on
    **both** axes. A cell that authored nothing fills it, and a grid's column
    width is its widest cell and its row height its tallest — so one column or
    one row swallows the offer.

    Measured in the campaign runner's table, in the coordinates of the whole
    canvas, inside a scroll pane 538 pixels tall:

    | | header | row 1 | row 2 | row 3 |
    | --- | --- | --- | --- | --- |
    | the table alone | 571 | 1126 | 1681 | 2236 |
    | the table in a stack | 571 | 608 | 645 | 682 |

    555 = 538 + 17, the offer plus the cell gap. Every run fell below the fold.
    **This is step 3 for the grid**: both extents come from the children, so the
    grid offers neither.

    **`:y` alone was not enough, and this step said it would be.** It deferred
    `:x` to step 15. The picture refused that: with the height withheld the rows
    became the height of their text, and then ONE column was 300 wide and the
    other two were clipped out of the pane. A column's width is derived exactly
    as a row's height is, so §3 reaches it in the same breath. Step 15 is where a
    column or a row says that it stretches, and a weighted one is offered its
    slot then — **until something can say so, nothing may be offered.**

    **A picture is what caught it.** `widget_table_offered` is a new example: the
    table of `widget_table` inside a 300×140 `WidgetScrollPane`, because a bare
    table is offered nothing and cannot show this at all. The baseline drew one
    header cell over the whole pane.

    `omnet-julia` holds the workaround today: `SimulationFilterToWidget` wraps the
    table in a `VerticalLayout` inside the pane, and a stack offered a height that
    holds no weighted child sums instead of distributing and offers that height to
    nobody. **Step 16 deletes that wrapper.**

    **Checked.** 41 images: **40 unchanged, and `widget_table_offered` changed**
    — from one cell over the whole pane to three columns and four rows, each the
    height of its text. That is the only picture this step is about.
15. **A column and a row take a policy, and the default is implicit — DONE.**
    This is step 4 for the grid, and it is the case step 4 said it was waiting
    for.

    | policy | a column | a row |
    | --- | --- | --- |
    | `Content` | as wide as its widest cell | as tall as its tallest cell |
    | `Fixed(n)` | exactly `n` | exactly `n` |
    | `Relative(w)` | a share of what is left | a share of what is left |
    | `Fill` | `Relative(1.0)` | `Relative(1.0)` |

    `GridLayout` has half of this already: `column_stretch::Vector{Int}` gives a
    weighted column its content width **plus** a share of
    `available − Σcontent − gaps`. **`column_stretch` folds into `Relative(w)`**
    and stops being a second way to say one size. There is no row equivalent
    today, and this is where one arrives.

    The grid carries `column_policy` and `row_policy` — one policy each, the
    default for every column and every row — with a per-column and a per-row
    vector for the ones that differ. **Both default to `Content`**, which is what
    a grid has always meant, so no caller changes.

    **A grid must not offer an item its total when that total came from the
    item.** §4's rule applies per column: a weighted column is offered a slot, and
    every other keeps the withheld axis, so its extent is safe to read while the
    allocation is computed. The same per row, on `:y`.

    **And the rule is wider than "weighted", which a stack overflow proved.**
    The first cut read a column's content whenever its weight was zero — so a
    `Fixed(40)` column was told 40, handed 40 to its cells, and then had its
    cells read to decide its width. That is a closed cycle, and Julia answered
    with `detected a stack overflow` twenty times over. **The cells of any item
    that is offered its extent are never read**, weighted or not; `_gl_offers` is
    that one question, asked in both places.

    **Checked.** 22 assertions in `test_layout_closeout`, up from 16: a grid that
    says nothing is `Content` on both axes; a `Fill` row takes what a `Content`
    row leaves of a seeded 400 and a plain grid stays under 100; a `Fixed(40)`
    column is 40 and asks for no share of the 600 it was offered. All 41 images
    are **identical to step 14** — every default is `Content`, which is what a
    grid always did.

    `column_stretch` is gone. `FormLayout` says `column_policies=[Content, Fill]`
    now, which is the same sentence in the one vocabulary.
16. **`WidgetTable` takes them — DONE.** The same two defaults and the same two vectors,
    and a table's own default is `Content` on both axes — a table that says
    nothing draws as it does today.

    **A table's policies are its BODY's.** A header strip is a column, or a row,
    of the same grid, and it is always `Content`: as wide, or as tall, as the
    labels in it. So the table shifts its own vectors over the strip when there is
    one, and `_wt_shift` is that one line.

    The campaign runner's five columns then say what they are for:
    `configuration` `Content`, `run` `Fixed`, `iteration parameters` `Fill`,
    `INI file` `Content`, `directory` `Fill`.

    **Checked, in `omnet-julia`.** The runner's five columns say what they are
    for — `iteration parameters` and `directory` `Fill`, the other three
    `Content` — and **the `VerticalLayout` wrapper is gone**: the table sits in
    its scroll pane directly. `test_filter_run_table_bounded` still passes, which
    is what says the fix landed at the grid rather than being moved around, and
    every other filter test with it.

    **A stack offers its cross axis only to a child that asked for it.** The pane
    needed `width = Fill` beside its `height = Fill`, or it was as wide as the
    table, the table was as wide as its text, and the two `Fill` columns had
    nothing to divide. Measured: a 900-wide offer draws a 900-wide table and a
    1400-wide offer a 1400-wide one, the two `Fill` columns splitting the slack
    evenly, and the rows 37 apart in both.

    A width a person can drag is not here. A policy is where a drag would write,
    which is what makes it possible later.
17. **A header strip stays put while the body scrolls — DONE.**

    **What a table is today.** `WidgetTable` carries both strips, and both are
    optional: `column_headers` is the top strip — a header **row** — and
    `row_headers` is the left strip — a header **column**. `_wt_grid_children`
    lays all of it out as **one** `GridLayout`: the column headers take grid row
    1, the row headers take grid column 1, `row_offset` and `col_offset` say
    whether each is there, and the corner is an empty cell. A strip aligns with
    the body because it is the same grid, and it scrolls with the body for the
    same reason.

    Frozen panes is four regions and two offsets:

    | | fixed on x | scrolls on x |
    | --- | --- | --- |
    | **fixed on y** | the corner | the column headers |
    | **scrolls on y** | the row headers | the body |

    **The pane freezes, and the content declares.** `WidgetScrollPane` gains a
    frozen extent and holds that many pixels of its content still on each axis
    while the rest travels. Three reasons it is not in the table:

    - **One scroller.** A table that scrolled itself would need its own `size`
      and `scroll_position`, and a pane around it would scroll a thing that
      scrolls. Every wheel and drag already reaches the pane.
    - **It is not about tables.** A sequence chart, a spreadsheet and a log with
      a fixed first line all want it. The pane holds a prefix of *anything*.
    - **The table already knows the number.** `_wt_geometry` computes `col_x` and
      `row_y`, the cumulative edges, so the frozen extent is
      `col_x[col_offset + 1]` by `row_y[row_offset + 1]`, and zero on an axis with
      no strip.

    A content that declares none freezes nothing, which is every content today —
    and that is not only a default, it is the whole cost. **A pane whose content
    answers `nothing` is the one viewport it has always been**, so nothing pays
    for a feature it does not use; only a table's pane walks its content four
    times.

    **Checked, and measured rather than looked at.** `widget_table_frozen` is a
    new example: a table with both strips in a 320×150 pane, scrolled 40 across
    and 60 down. Its four regions come out as

    | region | box | what is in it |
    | --- | --- | --- |
    | body | (28, 37) 292×113 | the cells, travelled on both axes |
    | column headers | (28, 0) 292×37 | `Status`, `Method`, `Amount` — travelled on x only |
    | row headers | (0, 37) 28×113 | `3`, `4`, `5` — travelled on y only |
    | corner | (0, 0) 28×37 | the empty corner cell, and it has not moved |

    `test_frozen_table_headers` asserts the shape: 18 assertions that a plain
    content is one viewport, that a table's four regions tile the pane and reach
    nothing past it, and that both strips sit at the pane's edge whatever the
    scroll is.

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
- In the campaign runner: a table row is the height of its text, its columns fill
  the pane's width, its header strips stay put while the body scrolls, and
  `omnet-julia` holds no wrapper to make any of that happen.

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
