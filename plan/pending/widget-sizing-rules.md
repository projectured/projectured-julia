# One sizing rule, for every widget and both axes

> **Kind:** plan · **Status:** pending · **Stands on:**
> [architecture-invariants.md](../../documentation/rule/architecture-invariants.md)

## The rule

```
size(axis) = clamp( own fixed size (axis)
                    else available (axis)      when the parent allocated one
                    else content (axis),
                    min(axis), max(axis) )
```

Four sources, one order, both axes, every widget. **No constant, ever.**

Two switches — parameters of the rule, not exceptions to it:

| switch | meaning | who declares it |
| --- | --- | --- |
| `content_is_not_a_source` | the widget is a viewport: it shows less than it holds | `WidgetScrollPane`, `WidgetTransformPane` |
| `available_caps_not_fills` | `available` is a maximum, not a target | `WidgetTooltip`, `WidgetContextMenu`, `WidgetMenu` |

And a second rule set, which is **not** the same question and already exists:

```
allocate_axis(available, mins, maxs, prefs, weights, gap, n)
```

How a container divides its own resolved size among its children.
`LayoutToGraphics:361` and `WidgetSplitPane:2344` share it.

## Why the axes look different today

Width fills and height does not, and that is **not** a per-axis rule. There is a
`_resolve_width` and no `_resolve_height`. Once both exist, the difference falls
out of which allocation a parent supplies: a column allocates width, a row
allocates height, and the same rule produces the right answer for each.

## What is there today

Surveyed: all 40 `print_document` methods of
[WidgetToGraphics.jl](../../source/widget/WidgetToGraphics.jl).

| pattern | width | height | widgets |
| --- | --- | --- | --- |
| A content only | content | content | Label, Insertion, Text, ContextMenu, MenuItem, Badge, RadioGroup, Toggle, ToggleGroup, Table, Tree, Tooltip |
| B `_resolve_width` | available → authored → ≥ content | content | StatusBar, Card, Progress, Slider, Alert, Skeleton, Select, Option, SpinBox, List, Textarea, Accordion |
| C own size | `w.size` | `w.size` | Button (≥ content), Avatar, Highlight, Skeleton height, Separator |
| D viewport | available → own size → **400** | available → own size → **300** | ScrollPane, TransformPane |
| E container | `allocate_axis` | `allocate_axis` | SplitPane, TabbedPane, Dialog |
| F **no extent** | reports `0` | reports `0` | Menu, Composite, Shell, TitlePane, Toolbar, TabbedPane, ScrollBar |
| G theme number | literal | literal | Checkbox 18, Switch 44×24, Progress 8, Slider 24 |

**A is B with no allocation offered. C is B with the authored size winning — which
is the rule. D is B plus a constant. E is the other rule set. F and G are not
rules; they are absences.**

### The eight deviations

| # | what | where |
| --- | --- | --- |
| 1 | five size constants | `_SCROLL_FALLBACK_WIDTH` 400, `_SCROLL_FALLBACK_HEIGHT` 300, `_SCROLLBAR_FALLBACK_LENGTH` 200, `_SCROLLBAR_FALLBACK_THICKNESS` 16, `_SPLIT_SLOT_FALLBACK` 200 |
| 2 | four theme numbers acting as sizes | checkbox 18, switch 44×24, progress 8, slider 24 |
| 3 | eight widgets report `0 × 0` | `_reactive_canvas_auto` and the 3-argument `_make_canvas` hard-code `Int32(0), Int32(0)` |
| 4 | precedence inverted | ScrollPane and TransformPane let `available` beat the authored size |
| 5 | no `_resolve_height` | height never fills, anywhere |
| 6 | a dead field | `WidgetTooltip.size` is never read; its comment claims it is |
| 7 | two allocations erased rather than declared | Toolbar sets `width = nothing`, Card sets `height = nothing` |
| 8 | **a viewport over-constrains its content** | `WidgetScrollPane:3213` seeds **both** axes into its content |

Only five printers read `w.size` at all: Button, ScrollPane, TransformPane,
ScrollBar, Avatar.

## The conversation, under the rule

What it must do:

1. content fills the available space **horizontally**;
2. **vertically** a card grows with its content, and collapses;
3. the transcript and the draft scroll **separately**, divided by a split.

How the rule delivers each, and what has to change:

| the chain | rule | today |
| --- | --- | --- |
| the tab gives the assistant its box | E — the tabbed pane allocates | seeds both axes into the tab content — correct |
| the split divides that height | E — `allocate_axis` over weight 1.0 and min/preferred 200 | correct |
| each half fills its slot | rule + `content_is_not_a_source` | ScrollPane prefers `available` — correct **by accident**, since it has no own size |
| a card fills the width | B — `_resolve_width` | correct |
| a card grows with its height | height = content | correct: the card strips the vertical axis for its children, *"the card is content-tall"* |
| the transcript scrolls | content taller than the viewport | **broken — deviation 8** |

**Deviation 8 is the whole of it.** A vertical scroll pane hands its content the
viewport height, so a column of cards is told it has exactly the room it has been
given, can never overflow, and there is nothing to scroll. A viewport must pass
the **cross** axis and withhold the **scroll** axis — which is exactly what the
card already does for its own children, and what the toolbar does for width.

So the conversation needs one change, and it is the general one: **a viewport
allocates across, never along.**

## Steps

Each step keeps the images green (see below) before the next begins.

1. **`_resolve_size(ctx, axis, own, content_min; caps=false)`** — the rule, once.
   `_resolve_width` becomes a call to it. Nothing else changes yet.
2. **Height fills too.** Give every pattern-B widget the height half. The 12 of
   them keep content as the floor.
3. **Deviation 8 — a viewport allocates across, never along.** ScrollPane and
   TransformPane pass the cross axis to their content and withhold the scroll
   axis. **This is the step the conversation needs.**
4. **Deviation 4 — flip the two precedences.** An authored size wins over an
   allocation, as everywhere else.
5. **Deviation 1 — delete the five constants.** A widget whose chain runs out is
   `0`, and a `0` is a bug the images will show.
6. **Deviation 3 — the eight zero-extent widgets report a real extent.** Each is
   a container: its extent is its children's, laid out. This is the largest step
   and it moves alone.
7. **Deviation 2 — the four theme numbers become minimum sizes**, so content can
   still push them out.
8. **Deviations 6 and 7 — delete the dead `WidgetTooltip.size`; replace the two
   erasures with the declared switches.**
9. **The overlays declare `available_caps_not_fills`** and read the allocation, so
   a tooltip stops running off the window.

## The safety net: every widget, before and after

**39 examples**, one per widget plus the two conversation ones:

```
widget_example  widget_label  widget_text  widget_checkbox  widget_button
widget_button_action  widget_button_image  widget_tooltip  widget_menu_item
widget_menu  widget_toolbar  widget_composite  widget_title_pane
widget_split_pane  widget_scroll_bar  widget_scroll_pane  widget_transform_pane
widget_shell  widget_tabbed_pane  widget_badge  widget_separator  widget_card
widget_switch  widget_progress  widget_slider  widget_radio_group  widget_avatar
widget_alert  widget_skeleton  widget_toggle  widget_toggle_group  widget_select
widget_textarea  widget_accordion  widget_table  widget_tree  widget_disabled
widget_focus  conversation_widget
```

The procedure, run at every step:

1. `write_example_image(name, "before/<name>.bmp")` for all 39, on the base commit.
2. Take the step.
3. Write the same 39 into `after/`.
4. Compare each pair and report three numbers per example: identical, changed
   pixels, changed size.

**A change is not a failure and identity is not success.** Steps 2, 3, 5 and 6
are *meant* to change pictures. What the comparison buys is that every change is
one somebody looked at and named. So each step's commit records, per example,
either "unchanged" or one line saying what changed and why it is right.

Add `tool/widget-images.jl` to do the writing and the comparing, so the procedure
is a command and not a description.

## What "done" means

- One `_resolve_size`, called by every widget, on both axes.
- `grep -c "FALLBACK" source/widget/WidgetToGraphics.jl` answers `0`.
- No widget reports a `0 × 0` extent.
- The 39 images differ from the base only where a step said they would.
- In the campaign window: the transcript scrolls, the composer stays put, and a
  card fills the width and grows with its content.

## Open questions

1. **Should `available` reach a widget that does not fill?** Today the toolbar and
   the card erase it. With `available_caps_not_fills` declared instead, the
   information survives and the widget decides. Prefer that — an erased allocation
   is unrecoverable by anything below.
2. **What is the extent of a container that has no children?** `0` is honest;
   `0` is also what deviation 3 produces today by accident. The images will not
   tell these apart, so a test must.
