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

> the two directions, the horizontal and the vertical must be handled
> identically, that is a rule of the layout engine already documented I believe

After the example of one axis (§3.3, "A window that cuts or scrolls"): "looks
better now, I understand", and then "yes" to the question "Do I also make the
column rule the same as the row rule, so that both share any range that has a
max?" After Step 2: "yes" to a step that fixes the deviations that Step 2
found.

So:

1. The model changes once, for every widget and every layout (§3).
2. A test checks every widget and every layout against the rules, so a widget
   that breaks a rule fails a test (Step 2).
3. Examples that run with `run_example` in the REPL show each case, and a person
   drags a splitter or resizes the window to see the layout react (Step 1).
4. The documentation says the rules and the trap (Step 8).
5. The detail of a task gets the smallest change that uses the model (Step 7).
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

- **R1. A giver writes a maximum only on an axis where it cuts.** Each axis of
  a scroll area says whether its content fits the view or grows past it. On an
  axis that fits, the content gets `(view, view)`: text wraps there, and a part
  that can scroll stops there. On an axis that grows, the content gets
  `(view, ∅)` and the visible extent `view`, and the area scrolls it. The same
  rule holds on both axes; each scroll area says it for each axis, and both axes
  fit by default, which are the ranges that a scroll area gives today. The
  scroll areas are `WidgetScrollPane`, `WidgetTransformPane`, the pane of the
  rows of a `WidgetList`, a `WidgetTree` and a `WidgetTable`, and the pane of
  the cells of a table.
- **R2. A viewport takes its content between its minimum and its maximum, and
  scrolls the rest:** `e = clamp(C, m, M)`, and `e = max(m, C)` with no maximum.
  An authored size wins, as today. Every other widget keeps `e = max(m, C(M))`:
  it never draws smaller than its content, and its giver cuts.
- **R3. A row and a column share by one rule.** When the range on the main
  axis has a maximum, exact or bounded, the weighted children share it, as a row
  does today. When it has only a minimum `m` and the sum of the content is less,
  they share `m − sum`. With neither, the stack sums its children. Today a
  column shares only an exact height, because a bounded height in a page was
  only "what the view has left"; with R1 a page gets no maximum, so a maximum is
  always a cut, and the column follows the row.
- **R4. A stack gives each child with no weight the room that the others
  leave**, as today (layout-rules.md §4). With R2, a viewport child takes its
  content up to that room and scrolls the rest.
- **R5. A widget that builds only the rows that show reads the visible
  extent.** A widget that fills its own slot reads the exact range.

### 3.3 The cases, worked

**A window that cuts or scrolls**, on one axis: a window of 300 holds a fixed
part A of 192 and a part B that can scroll, with 384 of content.

| The window | Past 300 | B gets | Today | Without R1, with R2 |
| --- | --- | --- | --- | --- |
| cuts | lost | 108, and B scrolls inside | 384, the end of B is lost | 108 |
| scrolls | reached by a scroll of the window | 384, and the window scrolls | 384 | 108, two scroll bars |

A drag of a splitter that makes the window 250 gives 58 where it cuts, and 384
where it scrolls.

**A column and a row**, today, with the range `(0, 300)` on the main axis and the
parts `[A = 100, F = Fill]`: the row gives F 200, and the column gives F its
content. With R3 both give F 200.

- **A text above a table, in a cut slot of 400** (the detail of a task): the text
  is in a scroll area with no weight, and the table has a weight and a minimum
  of 200. The room of the text is `400 − gaps − 200 = 176`. By R2 the scroll area
  takes 176 of its 300 and scrolls. The table gets 200.
- **A code block in a page that scrolls:** the scroll area of the page grows on
  its height, so the page gets `(300, ∅)` (R1), its column has no maximum, and
  the room of the code block is free. By R2 the block takes its 400, and the
  page scrolls. The area fits on its width, so the text of the page wraps.
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

**R1, the givers.** A setting for each axis on `WidgetScrollPane`,
`WidgetTransformPane` and the panes of rows and cells: fits or grows.
`WidgetScrollPane` (`WidgetToGraphics.jl:6044-6047`);
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
Step 9 checks them.

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

Before Step 4 the examples show today's faults; they are the pictures to compare
with after Step 6. The tour
([examples-tour.md](../../documentation/guide/examples-tour.md)) lists them.

Found in this step: the sweeps run `test_printer`, `test_reader` and `test_repl`
on every example. `test_typein` runs only on five text examples. The sweeps of
position navigation, of click round trips and of text navigation skip widget and
layout examples, because the keyboard can not seed a first caret in them and no
`TextToGraphics` is at their top; they skip the prefix `layout_` too
(`ExampleSweeps.jl`).

### Step 2. The rules as a test — done

`test_layout_rules()` in `test/platform/projection/LayoutRulesTest.jl`, in the
platform suite:

- Each widget type and each layout type has a small sample with no authored size
  and no position, and a kind on each axis: `:rigid`, `:reflowing`, `:scrolls`,
  `:fills` (takes a slot and cuts its content there, else its content),
  `:authored` or `:overlay`. A type that is not placed alone has a reason. The
  samples of the catalog author sizes and positions, which win in every range, so
  the test does not use them.
- Each sample is printed on each axis with no range, an exact range, a bounded
  range and an "at least" range, above and below its content, and checked by the
  rule of its kind.
- A guard fails for a concrete type of the platform below `WidgetDocument` or
  `LayoutDocument` with no kind, and for a kind with no type. It leaves out the
  native twin `MFoo` of each `@document` type `Foo`, and the `…Style` documents.
- The worked cases of §3.3 are tests; the visible rows are checked with a lazy
  grid of ten million rows in a scroll area (`built < 30`). The data frame view
  is checked by `test_dataframes()` in Step 4.

Result: 435 checks pass, and 71 are `@test_broken`, each with its reason in
`_rules_broken`.

Found in this step:

- An exact range is one cell for both ends: `get_exact_width` and
  `get_exact_height` compare the cells by identity. Two cells with the same
  number are a bounded range with a minimum, and a part that fills a slot does
  not see a slot there.
- The rules give these deviations, which Step 3 fixes:
  - a layout (`HorizontalLayout`, `VerticalLayout`, `GridLayout`, `StackLayout`,
    the height of `FlowLayout`), `WidgetComposite`, `WidgetToolbar` and
    `WidgetToolbarItem` do not take a slot or a minimum that is more than their
    content;
  - `WidgetTabbedPane`, `WidgetShell` and the width of `WidgetSplitPane` take no
    minimum without a slot;
  - `WidgetSplitPane` in an exact width with a free height draws 1;
  - `WidgetShell` takes a slot only when it has one on both axes;
  - `WidgetAlert` does not wrap its description.

### Step 3. The deviations that Step 2 found — done

Each of these printers takes its minimum, and fills a slot that is more than its
content, by `e = max(m, C(M))`:

- `HorizontalLayout`, `VerticalLayout`, `GridLayout`, `StackLayout`, the height
  of `FlowLayout`, `WidgetComposite`, `WidgetToolbar` and `WidgetToolbarItem`;
- `WidgetTabbedPane`, `WidgetShell` and `WidgetSplitPane` with no slot; a shell
  takes a slot on one axis without one on the other;
- `WidgetSplitPane` in an exact width with a free height draws its slot;
- `WidgetAlert` wraps its description at its maximum width.

The marks "found in step 2" of the test become `@test`. Tests:
`test_layout_rules()`, the `SizeRange*` tests, `test_platform()`,
`test_dataframes()`.

How it is done:

- `_make_extent_at_least` (`LayoutToGraphics.jl`) raises the extent of a
  column, a row, a grid, a stack layout and the height of a flow to the minimum
  of its range; their rows, columns and cells stay their content.
- `_reactive_canvas_auto` takes `stretch`, a context whose minimum raises the
  extent, and `width` and `height`, cells that fix an axis with a slot. The
  composite and the shell use them; the shell takes a slot on each axis by itself.
- A toolbar gives its items a bounded range on both axes, so an item in a toolbar
  stays as large as what it shows, and an item takes its minimum by the rule.
- A pane of a split that declares no size and no weight takes an equal share;
  before, it got 0, and two such panes drew only the splitter.
- `WidgetAlert` breaks its description with `_text_lines` at its width.

Found in this step:

- `WidgetScrollBar` took no minimum either; it takes it now.
- A window that fits its content, such as a tooltip, gave its content its
  maximum as a slot (`ScreenToScreen.jl`), the trap of §2 in another place: with
  the content taking its slot, every tooltip window took its maximum width. The
  window gives its maximum as an edge now, and a window of a fixed size gives its
  size as a slot.
- Five tests expected the old reading, "a container that says nothing is its
  content, whatever it is offered": `LayoutCloseoutTest`, `GridSpanTest`,
  `WidgetSplitPaneTest` (which also expected the panes of 0), `WidgetToolbarTest`
  and the window of `TooltipNoteTest`. Each keeps its intent: the columns and
  rows of a grid stay their content, a flow wraps more when it is narrow, an item
  in a toolbar keeps its size.

Result: `test_layout_rules()` 554 pass and 22 broken, for Steps 5 and 6. The
platform suite, run in four parts of about 60 test functions each with 8 GB:
three failures, each a known failure of main (the `using` lists of
`FileChangeModule` and `ShellModule`, and the 33 names and the text of
`WidgetLink` in `InterfaceApiTest`). `test_dataframes()`: 603 pass.

### Step 4. R1, R5 and a shared minimum: each axis of a scroll area fits or grows — done

Each axis of a scroll area gets the setting fits or grows (§4), and both fit by
default, which keeps every range of today. On an axis that grows, the content
gets `(view, ∅)` and the visible extent (my recommended names:
`get_visible_width(ctx)`, `get_visible_height(ctx)`). Each reader of §2 is
changed to the kind that it is. A stack shares a minimum (the second sentence of
R3), so a `Fill` part in a view that grows still fills the view. The scroll areas
of pages that grow down say so on their height: the examples of Step 1, and the
pages that the tests and a search find. Tests: `test_layout_rules()`, the
`SizeRange*` tests, `test_platform()`, `test_dataframes()`.

How it is done:

- `WidgetScrollPane` and `WidgetTransformPane` have the field `grows`, a pair
  `(width, height)` of `Bool`, after `size`. On an axis with a view, the
  content gets `(view, view)` where it fits and `(view, ∅)` where it grows. The
  four places that build a scroll pane by position (the pane of the rows, the
  two panes of the parts of a table, and the graph pane) give
  `(width = false, height = false)`.
- The visible extent is a property of the context, `:visible_width` and
  `:visible_height`, in the layout module (`with_visible_size`,
  `get_visible_width`, `get_visible_height`), and not a field of the kernel
  `PrinterContext`: the kernel has no notion of a view. A scroll area gives its
  view on each axis that has one, so a scroll area inside another gives its own.
  `get_visible_height(ctx)` is the maximum of the range when it has one, because
  the giver cuts there; else the visible extent; else `nothing`. So a reader
  reads one value in a slot, in a bounded range and in an area that grows.
- A stack whose range on its main axis has a minimum and no maximum shares the
  minimum: `allocate_axis` divides it, and each weighted child gets its share as
  a minimum, `(share, ∅)`, and so draws `max(share, content)`. The stack is the
  sum of its children, at least the minimum. On the cross axis, a weighted child
  with no edge takes at least the minimum of the range. This is the rule of CSS
  for `flex-grow` in a container with a `min-height`.
- The readers of §2, each by its kind:

  | Reader | Kind | Reads |
  | --- | --- | --- |
  | the width of a lazy `WidgetTree`, measured over the rows that show | builds what shows | visible height |
  | a `WidgetTable` whose rows are a list (`WidgetTableParts.jl`) | builds what shows | visible height |
  | `DataFrameViewToWidget`, `TaskStreamLines`, the bar of `FrameStatistics` | builds what shows | visible height |
  | the width of a `WidgetTree`, `RosterToGraphics`, `DashboardToWidget`, `TaskGroupDocumentToWidgetPane`, the folder page, `GridList`, the panes | fills its slot | exact range |

- These scroll areas hold a page, and grow on their height: the settings, the
  appearance, a section and the dashboard of the explorer, a help entry, the
  work of the assistant, the log of the calls, the forms of an evaluator, the
  conversation of the assistant (in the split and in the card), the lines of a
  terminal, and the list of values of a column header; and the three pages of
  the examples of Step 1.

Found in this step:

- A table whose rows are a list raised an error in a range with no exact
  height. It reads the visible height now, so it works in an area that grows.
- The search of the API counted a query word also inside another word. The
  signature of `WidgetScrollPane` names `grows`, so "row" counted there, and
  `InterfaceApiTest` found the scroll pane first for "a row of widgets side by
  side". No wording of the docstring fixes it, because the signature is the only
  place of the scored text with "row". The owner said "yes" to a word that counts
  only where a word starts, as a forbidden word `-word` already matches. Both
  searches count so, the API and the guides (`_count_at_word_start` in
  `SearchQuery.jl`); a pattern still counts wherever it matches.
- A file tab (`make_file_tab_content`) holds any document: a text, a page, a
  table. It keeps fitting on both axes; Step 6 checks the code blocks of a
  Markdown file in it.
- omnet-julia has four scroll areas that hold a page: the workflow
  (`SimulationWorkflowToWidget.jl`), the tab of a study (`StudyVerbs.jl`), the
  study of the M/M/1/K demo (`Mm1kDocument.jl`) and the page of the catalog shell
  (`CatalogShellToWidget.jl`). They take `grows` in a commit of omnet-julia that
  lands with this branch (Step 9), because omnet-julia reads projectured-julia
  from main.
- The tests of the agent sessions (`test_external_agent_turn`,
  `test_assistant_overview`) fail in a process that also loads the umbrella
  package, because it loads `ProjecturedMCP`; with only the platform tests loaded
  they pass. This is known on main, and not a fault of this step.

Result: `test_layout_rules()` and the `SizeRange*` tests 562 pass and 22 broken,
for Steps 5 and 6. The platform suite, in four parts: the three known failures
of main, and the rank of "a row of widgets side by side", which the change of the
search fixes. The 23 test functions that check a rank of a search pass, but for
the two known failures of `InterfaceApiTest`. `test_dataframes()` and
`test_graph()`: 1241 pass. The naming guard passes.

### Step 5. R3: a column shares a maximum as a row does

`_vl_build` shares a range with a maximum, exact or bounded, as `_hl_build` does,
and so do the rows of `GridLayout` as its columns do. After Step 4 a page gets no
maximum, so a bounded height is always a cut. Tests: `test_layout_rules()`, the
`SizeRange*` tests, `test_platform()`, `test_dataframes()`.

### Step 6. R2: a viewport stops at its maximum

`WidgetScrollPane`, `WidgetTransformPane` and the widgets of rows take
`clamp(C, m, M)` and scroll the rest. The `@test_broken` marks of Step 2 become
`@test`. Tests: `test_layout_rules()`, `test_platform()`, `test_dataframes()`.

### Step 7. The detail of a task

In `_build_detail` (`TaskGroupToWidget.jl:445`) the facts go in a scroll area
with no weight, and the place of the result document gets a minimum, so the
table of the differences and the chart picture show in the split. Tests: the task
group tests of the platform, and the scalar differences and chart comparison
tests of omnet-julia.

### Step 8. The documentation

- [layout-rules.md](../../documentation/rule/layout-rules.md):
  - §1: a maximum means "the giver cuts here", and a part that can scroll draws
    `min(content, max)`;
  - §3: each axis of a scroll area fits (maximum = view) or grows (minimum =
    view, no maximum);
  - §3b: "a bounded range adds no clip" stays for a fixed part, and a part that
    can scroll never passes its maximum;
  - §4: a column shares as a row does, and a stack shares a minimum; the
    paragraph on "what the view has left" goes, because its reason goes;
  - §5: the cases of §3.3, the window that cuts or scrolls first;
  - §6: one rule for both axes, and each scroll area says for each axis whether
    it fits or grows;
  - a new section "The trap": a giver that does not cut must not give a
    maximum;
  - a new section "The visible extent": what a list that draws only its visible
    rows reads on an axis that grows.
- [layout.md](../../documentation/package/platform/layout/layout.md) and
  [widget.md](../../documentation/package/platform/widget/widget.md): the
  sentences on the size that a parent offers, the scroll pane, and the widgets
  of rows.
- [testing-guide.md](../../documentation/guide/testing-guide.md):
  `test_layout_rules()`.
- [examples-tour.md](../../documentation/guide/examples-tour.md): the examples
  of Step 1.

### Step 9. The wide check

`test_platform()`, `test_dataframes()` and the omnet-julia IDE tests, each
compared with a run on main, and a precompile of omnet-julia. The tests of the
assistant of omnet-julia that check a rank of a search, because a word of a
search counts only where a word starts (Step 4). The four scroll areas of
omnet-julia that hold a page take `grows` (Step 4). The examples of
Step 1 and the IDE detail of a statistical test and of a chart test, seen in a
window. Then the branch waits for approval to land.

## 6. Not in this plan

- The new design of the detail page of a task (the owner: "a different story").
- `ConstraintLayout` and `AnchoredLayout`, which do not give a range by these
  rules.

## 7. Decided

- The setting of a scroll area for each axis is the keyword
  `grows = (width = false, height = false)`, with both axes fitting by default.
  This was my recommendation; the owner said "yes" to Step 4, which named it.
- The names of the visible extent are `get_visible_width(ctx)` and
  `get_visible_height(ctx)`, my recommendation in the same Step 4.
