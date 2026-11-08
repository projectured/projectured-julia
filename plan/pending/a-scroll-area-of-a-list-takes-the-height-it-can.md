# A scroll area of a list takes the height it can

> **Kind:** plan · **For:** developer · **Status:** a plan, written 2026-11-08 at `main` `140ae8853`.
> Nothing is built. The owner chose the general rule on 2026-11-08; the model below is a recommendation of the
> author and the owner has not approved it. · **Stands on:**
> [layout-rules.md](../../documentation/rule/layout-rules.md) §3, §3b, §3c,
> [layout.md](../../documentation/package/platform/layout/layout.md),
> [widget.md](../../documentation/package/platform/widget/widget.md)

## 1. The goal

A dashboard shown in a card of another dashboard shows its cards, and a press at a card hits it. In general:
a scroll area whose content is a list, and that gets no height from its container, is as tall as the limit of
its range, so the rows of the list show. A scroll area whose content is not a list, or whose container gives a
height, keeps its height.

## 2. The cause (checked)

- The pane prints its content, then takes its height from `_pane_extent(offer, content_cell, minimum, maximum)`
  (`WidgetToGraphics.jl:6198`, called at `:6622` for `WidgetScrollPane` and at `:7451` for `WidgetTransformPane`).
  With no offer it answers the height of the content canvas, between the minimum and the maximum of its range.
- The grid of a dashboard, and the list form of a linear layout (`LayoutList.jl`), report a width and a height
  of `0` by design: a lazy list can not know its whole height, because it counts from its head and is endless in
  both directions (`GridList.jl:15-23`, canvas height `Cell(Int32(0))` at `:145`).
- The outer dashboard sits in a range of 500..500, so its pane gets an exact offer. The inner dashboard sits in a
  grid row that is as tall as its cells, so its pane gets no offer and no minimum, only the maximum 466 (its
  visible height). The answer is `min(max(0, 0), 466) = 0`. The list inside builds its rows for 466, but the
  viewport has a height of 0, so nothing shows and a press hits nothing.
- The pane already knows that its content has no height. The scroll offset, the clamp to the ends of a list and
  the scroll bars ask `_has_no_extent_along(content, axis)`: `is_infinite_canvas(content)` and a list canvas
  that runs along the axis (`_find_list_canvas`). The height of the viewport is the one place that does not ask.
- The owner's note that this also fixes a table in a card was checked and does not hold as stated. A table of a
  list does not use this rule: it reads `get_visible_height` of its range and gives its own panes an exact height
  (`WidgetTableParts.jl:891`, `:975`). A table in a card is as tall as the visible height already. The table is
  hidden only when it sits in a pane that has height 0, as the inner dashboard does; this plan fixes that case.

## 3. How a pane knows that its content has no height

A height of `0` can not mean "no height": an empty column and an empty table also report `0`, and they must stay
`0`. The canvas of the content already carries the difference, in the type of its elements:

- A list that has a row has `elements` that is a `ListNode` (the head). The canvas is a list canvas.
- A list with no row has `elements = CellVector()` (`GridList.jl:141`, `LayoutList.jl:140`). The canvas is
  finite, with a height of `0`. The dashboard with no card prints a `WidgetLabel`, which is finite too.
- A finite layout, an empty layout and an empty table have finite elements.

So the pane asks the canvas that it places. It does not look at the IO map of a child.

## 4. Candidate models

### A. The pane asks the canvas it places (existing predicate)

On an axis with no offer, if `_has_no_extent_along(content_canvas, axis)`, the extent is the maximum of the range
(and not less than the minimum). Otherwise it is as today. The check is read inside the cell of the extent, so
the height follows the content when the first row comes or the last row goes (rule: a cache reads its inputs
inside the cell). With no maximum, the extent stays as today (the list has no visible extent to build for, so
there is no limit to take).

- Panes that change: a `WidgetScrollPane` with no offer whose content is a list canvas along the axis. Today such
  a pane is as tall as its minimum, often `0`; it becomes as tall as its maximum. So a pane changes only from
  invisible (or short) to as tall as its room. Found by the survey: the grid of `DashboardToWidget` in a card or
  in any layout without an edge; `FileView` (a lazy text, a file in a card; `FileView.jl:47`); the lazy text of a
  document in a pane with no offer; an explorer section or a help page that sits in a card (their panes
  have `Fill` today, so with a container that gives a height they do not change); the pages of
  `DataFrameViewToWidget`, `FileSystemDirectoryToWidget`, `FrameStatisticsToWidget` and
  `DocumentTreeToWidgetTree` when their list sits in a pane with no offer.
- Panes that do not change: every pane with an offer (a shell, a tab page, a split, `Fill` in an edge); every pane
  whose content is finite (settings, appearance, a help page, a conversation that is a vector); the panes inside
  a `WidgetTable` (exact offer); a pane around an empty list; the `WidgetTransformPane` (its content is a graph
  or a picture, never a list; the call at `:7451` keeps `_pane_extent` as it is).
- A person sees: a dashboard, a file or a lazy list in a card is visible and takes the height up to the edge
  that cuts, and then scrolls. A list with three rows in a card of 466 shows three rows and empty room below
  them. In a vertical layout with no weight, a pane of a list takes the room that the others leave, so a child
  after it must declare a minimum (the rule of layout.md that already holds for any tall content).
- Cost: no new field, no new function except a small one that tells the extent of a pane on an axis. The check of
  `is_infinite_canvas` walks the elements of a finite canvas; inside a cell it makes the cell depend on every
  element cell of a large finite canvas. Step 1 measures this; the answer may be a check of the canvas of the
  content only (the head and one level down, as `_find_list_canvas` does).

### B. The canvas says it (a new field)

A canvas gets a field (for example `height_known::Bool`, or `h = nothing` for "no height"), set by the printers of
the list forms. The pane reads the field. This is the most explicit, and it also lets an empty list say "no
height" when it wants to. But it adds a field to `GraphicsCanvas` (a change of the graphics primitive and of every
backend that reads `h`), and the canvas already says it with the type of its elements. It repeats a fact that the
canvas has, and two places can disagree. **Question for the owner (new field).** Not recommended.

### C. A (limit) with the end of the list (a shorter pane)

As A, but when the walk from the head reaches both ends of the list within the limit, the height is the sum of
the built rows, so a list with three rows is three rows tall and a dashboard of three cards has no empty room.
The walk is the one `_clamp_to_list_ends` already makes, bounded by the limit. It gives no whole-list number: it
gives the height of a list that ends within the limit, and the limit for a list that does not.

- Panes that change: the same as A, and the pane of a short list is as tall as its rows. The height changes when
  rows come or go, and a pane in a layout moves its siblings then.
- A person sees: no empty room below a short list in a card; a list that grows past the limit jumps to the limit
  once, then scrolls. The page under the card moves while rows are added.
- Cost: the pane reads the placed rows and both ends in a cell, which depends on the row prints and on the
  links of the list; every edit of a row height moves the pane. This is more reactive work and a second
  mechanism next to A.

## 5. Recommendation (the author's, not the owner's)

**A**, because the content canvas already tells the difference between a list and an empty or finite content, the
pane already uses that predicate for the offset, the ends and the bars, and A matches the rule the owner chose.
It never gives a lazy list a whole-list number, adds no field, and changes only panes that show nothing or too
little today. C is a refinement for later if the empty room below a short list looks wrong; it can be added to A
without undoing A.

## 6. Open questions for the owner

1. A pane with no offer and no maximum (no edge at all) keeps its content height (`0` for a list) under A. Is that
   right, or must it take the visible height of its context?
2. Is the empty room below a short list in a card acceptable for the first step (A), with C only on request?
3. The note that the rule "also fixes a table in a card" does not hold (section 2). Is the nested dashboard the
   case you meant, or is there a table in a card that is hidden today? If so, give the repro.
4. Does the rule apply to the `WidgetTransformPane` too? The author says no (no list is ever its content).

## 7. Steps (fixed)

1. **Measure and test the case.** Add a test that prints a dashboard in a card of a dashboard and checks the
   viewport rectangle of the inner pane (height greater than 0 and equal to its maximum), the position of a
   card text inside the clip, and a press at that place that hits the card. The helpers `_nav_drawn` and
   `_nav_texts` do not clip; the test reads the viewport rectangles. Check that it fails now. Also measure the
   cost of the check on a large finite canvas. Test: the new test in `test/platform/explorer/ExplorerTest.jl`
   (`test_explorer()`).
2. **The extent of a pane on an axis.** Add one function in `WidgetToGraphics.jl` that tells the extent of a pane
   on an axis from the offer, the placed canvas, the minimum and the maximum, with the rule of A, and use it at
   `:6622` (height and width). The content cell reads the canvas elements inside the cell. Tests:
   `test_scroll_pane_bar()`, `test_widget_rows_scroll()`, `test_pane_geometry()`, and the test of step 1.
3. **The empty and the finite cases.** Tests that an empty vertical layout, an empty list, an empty table and a
   dashboard with no card keep a height of `0`, and that the first row of a list that was empty gives the pane
   its height, and the removal of the last row gives it back. Test: the same files, narrow.
4. **The suites that size by these rules.** `test_layout_rules()` (including the lazy grid of ten million rows),
   then `test_dataframes()` (the layout rule of the repository: the platform suite alone has missed data frame
   edits), `test_explorer()`, `test_navigator_to_widget()`, `test_dashboard_render()`, `test_table()` and the
   task page suite (`test/platform/task`). Compare any failure with the baseline on `main` before calling it a
   regression.
5. **Documentation.** Change layout-rules.md §3 (the text on a viewport with no offer) and the scroll-pane
   section of widget.md: a pane of a list takes the maximum of its range. Test: `test_documentation()`.
6. **Look at the pixels.** Start a fresh process, show a dashboard in a card, force the tree and read the pixels
   of the SDL backend: the cards of the inner dashboard are drawn, and Alt+click at one selects it.

## 8. Risks

- A pane of a list in a vertical layout with no weight now takes all the room the others leave, and a sibling
  after it with no minimum gets no space. Step 4 and a search of the layouts that hold such a pane catch it.
- A cell that depends on the elements of a large finite canvas makes the pane compute again for each element
  change. Step 1 measures it; the fallback is a check of the head and one level down.
- A list that becomes empty collapses its pane to `0` and the layout around it moves. This is the same
  rule as for any empty content; question 2 and C do not change it.
- The viewport has a height while the rows are still being built from the visible height; the two numbers are the
  same maximum, so no cell reads its own result. Step 2 checks that no cycle appears.
