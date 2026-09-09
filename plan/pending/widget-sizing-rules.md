# One sizing rule, and one place that parametrises it

> **Kind:** plan · **Status:** pending · **Stands on:**
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)

## The rule

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

## Steps

Each step keeps the images green before the next begins.

1. **The policy type.** `Fixed` / `Fill` / `Content` / `Relative` and the four
   `LayoutConstraint` fields that carry them, beside the existing
   min/preferred/max/weight. Nothing reads them yet.
2. **`_resolve_size(ctx, axis, constraint, content)`** — the rule, once, both
   axes. `_resolve_width` becomes a call to it with the old defaults, so no
   picture moves.
3. **The offer is derived.** A container offers per the rule above. The four
   hand-written strips are deleted and replaced by their policy.
4. **A default constraint on each layout** — `VerticalLayout`,
   `HorizontalLayout`, `GridLayout`, `FlowLayout`, `StackLayout` — and a bare
   child means "use it".
5. **Every widget resolves through `_resolve_size`.** Patterns A, B, C and D
   collapse into it. The two inverted precedences go with them.
6. **Delete the five constants.** A chain that runs out is `0`, and a `0` is a
   bug the images show.
7. **The eight zero-extent widgets report a real extent** — each is a container,
   so its extent is its children laid out. The largest step; it moves alone.
8. **The four theme numbers become `min`**, so content can still push them out.
9. **Delete `WidgetTooltip.size`; the overlays take `Content` with
   `max = offer`,** so a tooltip stops running off the window.
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
