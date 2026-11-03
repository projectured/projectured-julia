# A maximum is an edge that cuts

> **Status:** pending. Asked for on 2026-11-03. Nothing is implemented.

## 1. The request

The fault that started it: in the OMNeT++ IDE, the detail of a statistical test
shows the table of the scalar differences only when the detail is alone. In the
split below the table of the tests, the detail shows the summary line of the
table, then stdout and stderr, and no rows. The chart picture of a chart test
uses the same place, so it has the same fault.

The owner, 2026-11-03:

> The layout issues pop up every now and then and I don't like this. Can't we
> simply make this work once and for all for god's sake?

> Yes exactly and also update the documentation if necessary so we don't fall
> into this trap ever again

> yes, and I also want beside tests several examples for all interesting cases
> which can be run the REPL using projectured. I should be able to see how the
> layouts react in various cases.

> Also, the detail page layout should probably change, but it's a different
> story.

So:

1. The model changes once, for every widget and every layout (§3).
2. A test checks every widget and every layout against the rules, so a widget
   that breaks a rule fails a test (Step 2).
3. Examples that run with `run_example` in the REPL show each case, and a person
   drags a splitter or resizes the window to see the layout react (Step 1).
4. The documentation says the rules and the trap (Step 7).
5. The detail of a task gets the smallest change that uses the model (Step 6).
   Its new design is not in this plan.

## 2. The model today, and the trap

A parent gives each child a range on each axis: a minimum `m` and a maximum `M`
([layout-rules.md](../../documentation/rule/layout-rules.md) §1). Today the
maximum means two different things:

| Giver | What `M` means |
| --- | --- |
| a split slot, a tab, a window, a grid cell, a `Fixed` child | **a cut**: the giver clips there, and nothing past `M` shows |
| a scroll area, for its content (`WidgetToGraphics.jl:6044-6047`) | **the view now**: the content gets `(view, view)`, but it can be taller, and the area scrolls it |

A child can not tell the two apart. Two faults follow.

**A viewport can not stop at an edge.** In the detail of a task the facts take
their full height, and the table gets what is left. A scroll area around the
facts would have to stop at the room that the column gives it. But the same room
in a page is only what the view has left: a page of 300 pixels in a scroll area
holds a text of 240 and a code block of 400 in its own scroll area. Today the
block is 400 and the page scrolls. If a scroll area stopped at its room, the
block would be 60 pixels with a scroll bar of its own. So
[layout-rules.md](../../documentation/rule/layout-rules.md) §3b says "a bounded
range adds no clip", and a scroll area follows its content on such an axis.

**The visible rows hide in the same value.** A widget that builds only the rows
that show reads `get_exact_height(ctx)` as "how much is visible now":
`WidgetTree` (`WidgetToGraphics.jl:12540`, `:12627`), the cells of a table
(`WidgetTableParts.jl:957`, `:1234`), `DataFrameViewToWidget.jl:95`,
`TaskPagesToWidget.jl:340`, `RosterToGraphics.jl:152`,
`FrameStatisticsToWidget.jl:126` and `DashboardToWidget.jl:55`.

**The trap on record.** `plan/done/layout-sizing-model.md` §4.3 says "a viewport
in a bounded parent takes its content's extent up to the edge, and clips and
scrolls past it". The rules and the code do not do that, and the sentence led to
a wrong diagnosis on 2026-11-03.

## 3. The model

### 3.1 One meaning for each value

| Value | Meaning |
| --- | --- |
| minimum | at least this; a stack shares it among its weighted children when its content is less |
| maximum | the giver cuts here; nothing past it shows |
| visible extent (new) | how much of the content shows now; a scrolling viewport sets it for its content |

The context already carries four states on an axis. The fourth gets a rule now:

| State | Range | The child |
| --- | --- | --- |
| exact | `(s, s)` | takes `s`; its giver cuts at `s` |
| bounded | `(0, l)` | draws its content up to `l`; its giver cuts at `l` |
| at least | `(m, ∅)` | draws at least `m`, and grows with its content |
| free | `(0, ∅)` | draws its content |

### 3.2 The rules

- **R1. A giver writes a maximum only on an axis where it cuts.** A scrolling
  viewport gives its content `(view, ∅)` on each axis that it scrolls, and the
  visible extent `view` on that axis. The scrolling viewports are
  `WidgetScrollPane`, `WidgetTransformPane`, the pane of the rows of a
  `WidgetList`, a `WidgetTree` and a `WidgetTable`, and the pane of the cells
  of a table.
- **R2. A viewport takes its content between its minimum and its maximum, and
  scrolls the rest:** `e = clamp(C, m, M)`, and `e = max(m, C)` with no maximum.
  An authored size wins, as today. Every other widget keeps `e = max(m, C(M))`:
  it never draws smaller than its content, and its giver cuts.
- **R3. A stack shares a minimum.** When the range on its main axis has a
  minimum `m` and the sum of its content is less, its weighted children share
  `m − sum`. An exact range shares `s`, as today. With no minimum and no exact
  range, a stack sums its children, as today.
- **R4. A stack gives each child with no weight the room that the others
  leave**, as today (layout-rules.md §4). With R2, a viewport child takes its
  content up to that room and scrolls the rest.
- **R5. A widget that builds only the rows that show reads the visible
  extent.** A widget that fills its own slot reads the exact range.

### 3.3 The cases, worked

- **A text above a table, in a cut slot of 400** (the detail of a task): the text
  is in a scroll area with no weight, and the table has a weight and a minimum
  of 200. The room of the text is `400 − gaps − 200 = 176`. By R2 the scroll area
  takes 176 of its 300 and scrolls. The table gets 200.
- **A code block in a page that scrolls:** the page gets `(300, ∅)` from its
  scroll area (R1), so its column has no maximum, and the room of the code block
  is free. By R2 the block takes its 400, and the page scrolls.
- **`Fill` in a scroll area:** a column of a header, a `Fill` panel and a footer
  gets `(300, ∅)`. With 100 pixels of content, by R3 the panel takes the other
  200. With 900 pixels of content the column is 900, and the area scrolls.
- **A row of a label, a field that fills and a button, in 400:** no change
  (layout-rules.md §5).

### 3.4 The same model elsewhere

- **Flutter.** Constraints go down, sizes go up, and the parent places. A
  scroll view gives its child no maximum on the axis that it scrolls, and
  `SingleChildScrollView` takes its child's size within its own constraints:
  R1 and R2. A sliver gets the extent of the viewport in a value of its own,
  `SliverConstraints`: R5.
- **CSS.** The content of a scroll container has an automatic height, and the
  automatic minimum size of a scroll container in a flex layout is 0, so it
  shrinks: R1 and R2. `min-height` with `flex-grow` shares a minimum: R3.
- **Jetpack Compose.** `Constraints` carries a minimum and a maximum on each
  axis, and `verticalScroll` measures its child with an infinite maximum
  height: R1.

## 4. What changes where

From an inventory of every place that makes or reads a range (2026-11-03).

**R1, the givers.** `WidgetScrollPane` (`WidgetToGraphics.jl:6044-6047`);
`WidgetTransformPane` (`WidgetToGraphics.jl:6883`; with no extent it gives an
exact 0 today); the pane of the rows (`_print_rows_pane`,
`WidgetToGraphics.jl:10120-10136`); the pane of the cells of a table
(`WidgetTableParts.jl:957`, `:1234`). A `ScrollLayout` center and the body of a
card with a pinned height reach their content through a `WidgetScrollPane`, and
change with it.

**R2, the viewports.** The extent of `WidgetScrollPane` (`_pane_extent`) and of
`WidgetTransformPane`; `_scrolls_rows_itself` (`WidgetToGraphics.jl:10104`),
which today scrolls the rows only in an exact range.

**R3, the stacks.** `_vl_build` (`LayoutToGraphics.jl:1123`), `_hl_build`
(`LayoutToGraphics.jl:888`), and the rows and columns of `GridLayout`
(`LayoutToGraphics.jl:1484`).

**R5, the readers.** Each of the readers in §2 is one of two kinds: it fills its
own slot, and keeps the exact range, or it builds the rows that show, and reads
the visible extent. Step 4 decides each one.

**omnet-julia.** Its views place scroll areas and tables in the pages of the IDE.
Step 8 checks them.

## 5. The steps

Each step is a commit on the branch of a worktree. Each step updates the
documents that it makes wrong.

### Step 1. The examples — done

Examples that show each case, with names that start with `layout_`, in
`example/platform/LayoutCaseDocumentExample.jl`, registered in
`PlatformExamples.jl` and in the `examples` of `ProjecturedExample`, and
exported from both packages. The catalog holds one atom for each document type,
so these composite examples are not in it. Each one is a window with a splitter,
so a person drags it and sees the layout react: `run_example("layout_…")` in the
REPL.

| Example | What it shows |
| --- | --- |
| `layout_text_above_table` | the detail of a task: a text in a scroll area above a table with a minimum (R2, R4) |
| `layout_scroll_area_in_page` | a code block in its own scroll area, in a page that scrolls (R1) |
| `layout_fill_in_scroll_area` | a `Fill` panel in a scroll area, with short content on one side of the splitter and long content on the other (R3) |
| `layout_shares` | `Fixed`, `Content`, `Relative(2)` and `Relative(1)` with minimums in one column (R3, R4) |
| `layout_row_edge` | a label, a field that fills and a button; a long text before a button, with and without a weight (R4) |
| `layout_rows_in_slot_and_page` | a table in a cut slot, and a table and a list in a page (R2, R5) |

Before Step 3 the examples show today's faults; they are the pictures to compare
with after Step 5. The tour
([examples-tour.md](../../documentation/guide/examples-tour.md)) lists them.

Found in this step: the sweeps run `test_printer`, `test_reader` and `test_repl`
on every example. `test_typein` runs only on five text examples. The sweeps of
position navigation, of click round trips and of text navigation skip widget and
layout examples, because the keyboard can not seed a first caret in them and no
`TextToGraphics` is at their top; they skip the prefix `layout_` too
(`ExampleSweeps.jl`).

### Step 2. The rules as a test

`test_layout_rules()` in the platform suite:

- It prints every widget atom and every layout atom of the catalog in the four
  states of §3.1, and checks R2 for a viewport and `e = max(m, C(M))` for any
  other widget, and the overlay rule for an overlay.
- A table in the test gives the kind of each widget and layout type: rigid,
  reflowing, viewport, overlay or container. A guard fails when a concrete type
  has no kind or no atom, so a new widget can not skip the rules.
- The worked cases of §3.3 are tests, and so are the readers of R5: a tree and a
  data frame view in a scroll area build the rows that show.

A check that fails before Steps 3 to 5 is `@test_broken`, with the step that
fixes it in its `# @broken:` comment.

### Step 3. R3: a stack shares a minimum

`_vl_build`, `_hl_build` and `GridLayout` share a minimum among their weighted
children. Nothing gives an "at least" range yet, except a placement minimum
(`LayoutConstraint(…; min_height)` in a bounded parent), so this step changes
only that case. Tests: `test_layout_rules()`, the `SizeRange*` tests.

### Step 4. R1 and R5: a scroll area gives no maximum, and the visible extent

The context carries the visible extent on each axis (my recommended names:
`get_visible_width(ctx)`, `get_visible_height(ctx)`). The givers of §4 give
`(view, ∅)` and the visible extent. Each reader of §2 is changed to the kind
that it is. Tests: `test_layout_rules()`, `test_platform()`, `test_dataframes()`.

### Step 5. R2: a viewport stops at its maximum

`WidgetScrollPane`, `WidgetTransformPane` and the widgets of rows take
`clamp(C, m, M)` and scroll the rest. The `@test_broken` marks of Step 2 become
`@test`. Tests: `test_layout_rules()`, `test_platform()`, `test_dataframes()`.

### Step 6. The detail of a task

In `_build_detail` (`TaskGroupToWidget.jl:445`) the facts go in a scroll area
with no weight, and the place of the result document gets a minimum, so the
table of the differences and the chart picture show in the split. Tests: the task
group tests of the platform, and the scalar differences and chart comparison
tests of omnet-julia.

### Step 7. The documentation

- [layout-rules.md](../../documentation/rule/layout-rules.md): §1 the four states
  and the meaning of each value; R1 to R5; §3 and §3b, the viewport; §4, the
  minimum that a stack shares; §5, the cases of §3.3; and a section "The trap":
  a maximum that the giver does not cut makes every child guess, so give a
  maximum only where you cut.
- [layout.md](../../documentation/package/platform/layout/layout.md) and
  [widget.md](../../documentation/package/platform/widget/widget.md): the
  sentences on the size that a parent offers, the scroll pane, and the widgets
  of rows.
- [testing-guide.md](../../documentation/guide/testing-guide.md):
  `test_layout_rules()`.
- [examples-tour.md](../../documentation/guide/examples-tour.md): the examples
  of Step 1.

### Step 8. The wide check

`test_platform()`, `test_dataframes()` and the omnet-julia IDE tests, each
compared with a run on main, and a precompile of omnet-julia. The examples of
Step 1 and the IDE detail of a statistical test and of a chart test, seen in a
window. Then the branch waits for approval to land.

## 6. Not in this plan

- The new design of the detail page of a task (the owner: "a different story").
- `ConstraintLayout` and `AnchoredLayout`, which do not give a range by these
  rules.

## 7. Open

- **R1 and the width (found in Step 1).** Text in a scroll area wraps at the
  maximum width that the area gives its content: the code lines of
  `layout_scroll_area_in_page` wrap at the width of the view. A scroll area that
  gave its content no maximum width would stop every text in it from wrapping.
  CSS gives the content of a scroll container the width of the container and an
  automatic height: the width is an edge to lay out against, and the content
  grows down. My recommendation: R1 applies to the height, the axis on which a
  page grows, and a scroll area keeps giving its view as the maximum width; open.

- The names of the visible extent: my recommendation is
  `get_visible_width(ctx)` and `get_visible_height(ctx)`; open.
