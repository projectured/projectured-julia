# A view that scrolls shows a scroll bar

> **Kind:** plan · **Status:** pending, 2026-10-06. The decisions of §2 are
> made, and no question is open. Steps are in progress on the branch
> `scroll-bars`. ·
> **Stands on:** [widget.md](../../documentation/package/platform/widget/widget.md),
> [layout-rules.md](../../documentation/rule/layout-rules.md),
> [view-and-edit-a-data-frame.md](view-and-edit-a-data-frame.md),
> [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md),
> [a-table-scrolls-its-own-parts.md](../done/a-table-scrolls-its-own-parts.md)

This plan gives a scroll bar to every view that scrolls: a scroll pane, a
list, a tree and a table. It says where the bar sits, when it shows, what a
press and a drag on it do, and how the owner of a lazy list gives the bar its
numbers.

## 1. The goal

A person sees where a view is in its content, and moves the view with the
pointer, in every view that scrolls. A maker of a widget does nothing for it:
a widget that scrolls shows its bar.

The plan also moves the bar of the data frame view and of the frame
statistics into the widget table. [filter-sort-and-find-any-table.md](filter-sort-and-find-any-table.md)
step 2 expects the bar there.

## 2. The owner's decisions (2026-10-06)

- **D1. Overlay bars.** A bar is drawn over the content and takes no space
  in the layout. A gutter bar was rejected: it takes width from the content
  when it shows, the text wraps narrower and grows taller, and that can show or
  hide the bar again.
- **D2. A list scrolls by itself.** `WidgetList` and `WidgetTree` scroll
  their own rows, as `WidgetTable` does. A maker does not wrap them in a
  `WidgetScrollPane`. The reasons:
  - The border of the list stays still while its rows scroll.
  - The bar sits inside the border of the list.
  - A maker cannot forget the wrap.
  - Keeping the selection in view is local to the list.
  - Lazy rows become possible later.
- **D3. A press on the track moves one page.** This is the default of
  Windows, macOS, Qt and Chrome. Shift+click jumps to the point. Alt is not
  used, as macOS uses Option, because Alt+click selects a whole widget here.
- **D4. The owner gives a bar document.** For a lazy list, the owner builds
  a `WidgetScrollBar` and gives it to the widget that scrolls. The widget
  draws that document at its edge. The owner sets `value` and `thumb_size`,
  and changes a write of `value` into a scroll of its own, as it does now.
  Two numbers in fields of the table were the other choice.
- **D5. The names** are `vertical_scroll_bar` and `horizontal_scroll_bar`.
  The word `bar` alone also names the expression bar, the status bar and the
  title bar.
- **D6. The track of an overlay bar is transparent at rest.** Only the thumb
  covers the content until the pointer comes onto the bar.
- **D7. `nothing` means no bar.** A field of a bar that holds `nothing` draws
  no bar on that axis.
- **D8. `:auto` is the default.** A field of a bar holds `:auto`, `nothing`
  or a `WidgetScrollBar`. CSS names the same rule `overflow: auto`.

## 3. What exists

- `WidgetScrollBar` ([WidgetDocument.jl:1467](../../source/platform/widget/WidgetDocument.jl#L1467))
  is a control with `orientation`, `value` from 0 to 1 and `thumb_size`. A
  press, a button down, or a move with the left button held puts the middle of
  the thumb under the pointer and writes `value`
  ([WidgetToGraphics.jl:6203](../../source/platform/widget/WidgetToGraphics.jl#L6203)).
  A move off the bar is not read, so a drag stops at the edge of the bar.
- `WidgetScrollPane` draws no bar. Only the wheel scrolls it
  ([`_self_scroll`](../../source/platform/widget/WidgetToGraphics.jl#L5570)).
  It keeps `scroll_position` in pixels and `follow_end`.
- `WidgetTable` scrolls its own parts: the header row, the header column and
  the cells, each in a pane made by `_make_part_pane`
  ([WidgetTableParts.jl:148](../../source/platform/widget/WidgetTableParts.jl#L148)).
  The panes share the one `scroll_position` of the table. No part has a bar.
- `WidgetList` ([WidgetToGraphics.jl:8628](../../source/platform/widget/WidgetToGraphics.jl#L8628))
  and `WidgetTree` ([WidgetToGraphics.jl:10533](../../source/platform/widget/WidgetToGraphics.jl#L10533))
  do not scroll. Each draws its box around all its rows. In a pane, the top
  border scrolls away and the bottom border is cut off.
  `FileSystemToWidgetTree` wraps its tree in a pane
  ([FileSystemToWidget.jl:111](../../source/platform/filesystem/FileSystemToWidget.jl#L111)).
- Two owners put a bar beside a table whose rows are a list. Each builds a
  `GridLayout` of `[table | bar]` with the bar column `Fixed`, and each
  changes a write of `value` into a jump of its anchor:
  - [DataFrameViewToWidget.jl:107](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L107)
    and its conversion at [DataFrameViewToWidget.jl:672](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L672);
  - [FrameStatisticsToWidget.jl:280](../../source/platform/statistics/FrameStatisticsToWidget.jl#L280)
    and its conversion at [FrameStatisticsToWidget.jl:378](../../source/platform/statistics/FrameStatisticsToWidget.jl#L378).
- `WidgetSlider` has the drag that the bar needs: `MouseDown` takes the knob
  with `StartDragOperation`, `DragMove` writes, `DragEnd` ends, and
  `DragCancel` puts back `press_value`
  ([WidgetToGraphics.jl:7302](../../source/platform/widget/WidgetToGraphics.jl#L7302)).
- The theme has `scroll_bar_thickness` (10) and `scroll_thumb_minimum` (8)
  ([WidgetTheme.jl:183](../../source/platform/widget/WidgetTheme.jl#L183)).

## 4. The model

### 4.1 The bar

A bar reads these gestures:

| Gesture | Result |
|---|---|
| Press on the track | `value` moves one page toward the pointer, and stops at 0 and at 1. |
| Shift and press on the track | The middle of the thumb goes to the pointer. |
| Press on the thumb | A drag starts with `StartDragOperation`, as on the slider. |
| `DragMove` | `value` = the value at the press + the move along the axis ÷ (track length − thumb length). The thumb keeps the point where the pointer took it. A move off the bar still moves the thumb. |
| `DragEnd` | The drag ends. |
| `DragCancel` | The drag ends, and `value` goes back to the value at the press. |
| Wheel | Not read. The wheel goes to the view under the bar. |
| Pointer over the bar | The thumb takes the hovered color, and the pointer is an arrow, also over a text. |

**One page** in units of `value` is `thumb_size / (1 − thumb_size)`. For a
pane, that is one view height. For a lazy list, it is the shown rows. The bar
computes the page from its own two fields, so no owner changes for it.

**One page for each press.** A real press is a `MouseDown` and then a
`MouseClick`. A script sends a `MouseClick` alone. Each must move one page,
not two. Step 1 decided it so: the page step happens on the `MouseClick`, and
a `MouseDown` on the track answers nothing. So a real click and a scripted
click each move one page, and the bar keeps no state of the press for it. The
step comes at the release of the button, not at the press. A repeat while the
button is held (§6) would move the step to the `MouseDown`.

**The state of the drag.** The bar keeps one field of view state,
`thumb_drag`: `(along, value)` at the press, or `nothing`, as a table keeps
`column_drag`. Shift and a press on the track jump and start a drag from there,
as GTK does.

**The colors.** The projection of the bar has `track_color` (transparent),
`track_hovered_color`, `thumb_color` and `thumb_hovered_color`, and
`WidgetScrollBarStyle` has the same four fields. The bar is lit while its mouse
target is set or its thumb is dragged.

### 4.2 Where a bar sits and when it shows

- A bar is drawn over the content, at the inner edge of the border of the
  widget that scrolls, over its padding. CSS puts a bar in the same place.
  The vertical bar is at the right edge, and the horizontal bar is at the
  bottom edge. When both show, each stops before the corner square.
- A bar is `scroll_bar_thickness` thick. Its thumb is at least
  `scroll_thumb_minimum` long.
- A bar takes no space. The content keeps its extent when a bar shows.
- The track is transparent at rest, so only the thumb covers the content
  (D6). While the pointer is on the bar, the track shows in the track color
  of the theme.
- The bar is above the content for the pointer too. A press, a move and a
  dwell in the rectangle of a bar go to the bar first.
- A bar that the widget makes shows only while its axis of the content is
  larger than the view. An owner's bar shows while it is `visible`.

### 4.3 The pane

`WidgetScrollPane` gets two fields, `vertical_scroll_bar` and
`horizontal_scroll_bar`. Each holds one of these values:

- **`:auto`, the default (D8).** The pane makes the bar of that axis from
  its extents in pixels:
  - `value` = offset ÷ (content extent − view extent)
  - `thumb_size` = view extent ÷ content extent

  A write of `value` of that bar becomes a write of `scroll_position`, as view
  state. A drag up from the end of a pane that follows the end stops the
  follow. A drag to the end follows again, as the wheel does now.
- **A `WidgetScrollBar`.** The pane draws that bar at its edge and computes
  nothing. The maker of the bar sets its `value` and `thumb_size`, and
  changes a write of its `value` into a scroll of its own (D4). The write
  carries the bar itself, so it passes unchanged through every container
  above, as every widget write does.
- **`nothing`.** No bar on that axis (D7). The wheel still scrolls it.

With `:auto`, on an axis where the content is a list, the pane has no extent.
It makes no bar there, and only an owner's bar shows.

The pane makes its own bar at each print. A print of the pane during a drag
ends the drag. The panes of the parts of a table have the same property.

Step 2 built it so:

- **The thickness** of a bar is `scroll_bar_thickness`, a field of the
  projection of the pane that reads the theme. The pane offers the bar that
  thickness across and the edge of its view and its padding along, less the
  corner when the other bar shows.
- **A bar shows while its `thumb_size` is less than 1**, for a bar of the pane
  and for the bar of a maker alike. A hidden bar is an empty canvas in its place,
  and its place has no extent, so it takes no point.
- **The path of a bar** is the field that asks for it, also when the field
  holds `:auto`, as the path `items[2]` of a list ends at no document. A move
  on a bar answers that path as the part under the pointer, and the backward
  map of a point on the bar gives it too. The bar that the pane makes reads the
  mouse target of the pane to light; the bar of a maker gets its own.
- **The drag of a thumb comes to the pane.** The bar answers
  `StartDragOperation` with the empty path, and the pane keeps it as its own
  path, so a path never needs to reach a bar that the pane made. A
  `DragMove`, a `DragEnd` and a `DragCancel` at the pane go to the bar whose
  `thumb_drag` is set.
- **A press, a click and a dwell on a bar are the bar's**, and do not reach
  the content under it. The wheel over a bar scrolls the content under it.

### 4.4 A list and a tree

- `WidgetList` and `WidgetTree` get `scroll_position`, as view state, as
  `WidgetTable` has.
- The rule is the rule of the table. A widget that gets a slot on an axis
  fills it and scrolls its rows there. A widget with no slot is as large as
  its content.
- The widget draws its margin and its border at its own extent. It puts its
  rows in an inner `WidgetScrollPane` that shares the `scroll_position` cell
  and takes the padding of the widget as its own padding, as
  `_make_part_pane` does. So the border stays still, and the bar sits at the
  inner edge of the border.
- The references of a row do not change: `items[i-1:i]` and
  `roots[i].children[j]`. The inner pane is a part of the printer, not of the
  document. The printer maps a row through its inner pane.
- `FileSystemToWidgetTree` drops its pane. Its mappers lose the step
  `content` ([FileSystemToWidget.jl:117](../../source/platform/filesystem/FileSystemToWidget.jl#L117)).

Steps 5 and 6 built it so:

- **The inner pane holds the widget itself.** A pane gives its content an exact
  height, and a list with an exact height would wrap itself again without end.
  So the second print of the widget carries the property `:rows_of` of the
  context, which holds the widget, and a print with that property draws the rows
  alone: no box, and no slot of its own. A path of the pane is then a path of
  the widget without the step `content`, and the IO map of the widget,
  `WidgetRowsPaneIoMap`, maps both ways by that rule.
- **The widget has the fields of a pane.** `WidgetList` and `WidgetTree` get
  `scroll_position`, `vertical_scroll_bar` and `horizontal_scroll_bar`, as
  `WidgetTable` has, and the inner pane shares their cells. The path of a bar is
  its field on the widget.
- **The mouse target of the inner pane** is the mouse target of the widget, with
  `content` in front, or the bar that the widget names. So a row lights and a bar
  lights from the mouse target of the widget, and the pane sends the leave of
  the pointer to its content.
- **The rows know they have no box.** The IO maps of the rows of a list and of a
  tree hold `bare`, and their readers take the offset of the rows from it.
- **The box of a widget that scrolls itself has square corners.** The bands that
  follow the slot draw no radius.
- `ReflectionToWidget` builds its tree by position, so it names the new fields
  too, and its tree scrolls itself in a slot.
- [ScrollPaneHoverTest.jl](../../test/platform/projection/ScrollPaneHoverTest.jl)
  tests the routing of a pane over rows. A list directly in the pane now scrolls
  itself, so the test puts the list in a `VerticalLayout`, which gives it no
  slot.

### 4.5 The table

- `WidgetTable` gets the same two fields and gives them to the pane of its
  cells. The vertical bar starts under the header row, and the horizontal bar
  starts to the right of the header column.
- The panes of the header row and of the header column get `nothing`: no
  bar.
- With `:auto`, the pane of the cells makes the bar from pixels, on an axis
  where the parts are a vector. On an axis where the parts are a list, there
  is no bar unless an owner gives one.

### 4.6 The owner of a lazy list

- `DataFrameViewToWidget` gives its bar to `vertical_scroll_bar` of the
  table. Its `GridLayout` loses the column of the bar. `_convert_table_write`
  stays: it still finds a write of `value` of its bar.
- `FrameStatisticsToWidget` does the same with `_make_frame_scroll_bar`. It
  loses the column `Fixed(p.scroll_bar_width)`. It also loses the parameter
  `scroll_bar_width` if nothing else reads it.
- Each owner keeps its count of the shown rows, from its height and its row
  step.

Step 4 found that the drag of the thumb of an owner's bar can not come back to
the table by a path. The default backward map of a view names a part of its
output by an introduced reference, and the chain drops a routed gesture whose
route does not evaluate on its input, which an introduced reference never does.
A change of the chain is a change of the routing design, so step 4 did not make
it. The owner keeps the drag instead, as the data frame view keeps the drag of
the edge of a column:

- `thumb_drag` holds `(along, value, travel)`: the place of the press along
  the bar, the value, and the length of track that the thumb can move along.
  So a part of the drag needs no geometry, only the document of the bar.
- `read_scroll_bar_drag(bar, gesture)` answers a `DragMove`, a `DragEnd` and a
  `DragCancel` from `thumb_drag` alone. The bar reads its own drag with it.
- `make_owned_scroll_bar_drag(answer, bar, press)` keeps the place of the press
  in the frame of the owner, the frame of the gesture that the owner reads, and
  marks the drag `owned = true`. The bar, the pane and the table leave an owned
  drag to its owner, so a gesture that a grid gives its selected child does not
  move the thumb twice.
- The data frame view starts the drag at itself, as it does for the edge of a
  column, and reads each part with `read_scroll_bar_drag`. The statistics do the
  same through a new IO map, `FrameStatisticsToWidgetIoMap`, which holds their
  bar.
- `DataFrameViewToWidget` and `FrameStatisticsToWidget` lose `scroll_bar_width`:
  the table draws the bar at the thickness of its widget theme.
- The bar of the data frame view lights from the mouse target of the view, as
  the table does, because no path reaches it. The statistics give their table
  no mouse target, so their bar lights only while its thumb is dragged.

## 5. Steps

Each step is one commit with its test. Each step updates
[widget.md](../../documentation/package/platform/widget/widget.md) for its
part.

- [x] **1. The bar.** The gestures of §4.1. Tests:
  [WidgetScrollBarTest.jl](../../test/platform/projection/WidgetScrollBarTest.jl)
  42 pass; `test_data_frame_view()` 52 pass, with its bar case changed to
  Shift and a click, and a page.
- [x] **2. The pane makes its bars.** The fields of §4.3 with `:auto` and
  `nothing`, the overlay of §4.2, the order for the pointer, the write to
  `scroll_position`, and `follow_end`. Tests: a new
  [ScrollPaneBarTest.jl](../../test/platform/projection/ScrollPaneBarTest.jl), 40
  pass, and [ScrollPaneHoverTest.jl](../../test/platform/projection/ScrollPaneHoverTest.jl)
  unchanged, 27 pass. `test_platform()`: 100057 pass, 8 broken, and the 2
  failures of `InterfaceApiTest.jl` that `main` has too (32 names where it
  expects 31, and the docstring of `WidgetProgressRing`).
- [x] **3. The table and the owner's bar.** A pane draws a given bar.
  `_make_part_pane` gives `nothing` to the header panes, and `_make_cells_pane`
  gives the pane of the cells the cells of the two fields of the table and a
  mouse target that names a bar while the mouse target of the table does. The
  five positional builds of `WidgetTable` get the new fields:
  [DataFrameViewToWidget.jl:145](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L145),
  [DataFrameViewToWidget.jl:220](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L220),
  [CellTableToWidgetTable.jl:49](../../source/platform/widget/CellTableToWidgetTable.jl#L49),
  [MarkdownToLayout.jl:133](../../source/domain/markdown/MarkdownToLayout.jl#L133) and
  [FrameStatisticsToWidget.jl:236](../../source/platform/statistics/FrameStatisticsToWidget.jl#L236).
  The table reads a press, a button up and a click on a bar of its cells, and
  the drag of a thumb, before its own readers, and gives them to the pane of
  the cells; the backward map of a point on a bar answers the field of the bar
  in the table. A table whose rows are a list passes the answer through
  `_add_top_row`. The start of a drag names the table with the empty path, so
  the drag comes back to the table. Tests: a new
  [WidgetTableBarTest.jl](../../test/platform/projection/WidgetTableBarTest.jl), 20
  pass; the fourteen table tests of the platform pass unchanged, and
  `test_data_frame_view()` 52 pass.
- [x] **4. The two owners move their bars into the table** (§4.6). Tests:
  `test_data_frame_view()` 56 pass, with a press and a drag of the thumb
  through the chain; `test_frame_statistics_feed()` 138 pass, with the drag
  that the statistics keep; `test_dataframes()` 587 pass.
- [x] **5. `WidgetList` scrolls by itself** (§4.4).
- [x] **6. `WidgetTree` scrolls by itself**, and `FileSystemToWidgetTree` drops
  its pane. Steps 5 and 6 are one commit, because the two widgets share the
  code of the inner pane. Tests: a new
  [WidgetRowsScrollTest.jl](../../test/platform/projection/WidgetRowsScrollTest.jl),
  29 pass; the list cases of `test_widget_forms()` 87, `test_mouse_target_move()`
  76, `test_widget_forward()` 22, `test_widget_point()` 19 and
  `test_widget_tree()` 42 pass unchanged; `test_scroll_pane_hover()` 27,
  `test_filesystem_to_widget()` and `test_workspace_to_filesystem()` pass with
  the changes above. `test_platform()`: 100929 pass, 8 broken, the two failures
  of `InterfaceApiTest.jl` that `main` has, and one of `McpLogTest.jl` that comes
  from the test process: a process that also loads `ProjecturedTest` highlights
  the Julia code of the log, so "x = 1" is drawn as tokens. In a process that
  loads only the tests of the platform, `test_mcp_log_pane()` passes, 14 of 14.
- [x] **7. The rule.** [layout-rules.md](../../documentation/rule/layout-rules.md),
  "Clipping is not scrolling": a widget of rows scrolls by itself in a slot,
  and a bar is an overlay.
- [ ] **8. A live check** in the app, with pushed SDL events. Check the file
  tree, a data frame, the frame statistics, the settings page and a log:
  - the bar shows only on overflow;
  - a press moves one page, and Shift+click jumps;
  - a drag keeps the point where the pointer took the thumb;
  - Escape during a drag puts the view back.

## 6. Not in this plan

Each item needs a decision of its own.

- **A repeat of the page step while the button is held.** A timer exists
  (`SetTimerOperation`, `TimerExpire`), and the gesture tracker uses it for the
  dwell. It is not known if a `TimerExpire` can reach a widget deep in the
  tree. If it cannot, the repeat needs a new event, such as a gesture for a
  held button. That is a new mechanism, so it waits for the owner.
- PgUp, PgDn, Home and End on a view that scrolls.
- Keep the selection or the caret in view.
- `WidgetTextarea` that scrolls at its `rows`. It needs the caret in view
  first.
- A scroll in a menu, a context menu and the dropdown of a select. Each now
  stops at its largest size and clips.
- Bars on `WidgetTransformPane`.
- A bar that fades when the pointer leaves. It needs a timer.
- A horizontal bar of the data frame view when its columns are a list (more
  than 64 columns). Its value comes from `column_anchor`. It is a new feature
  of the view.

## 7. Considered and not chosen

- **A gutter bar** (D1).
- **The maker wraps a list in a pane** (D2).
- **Two numbers in fields of the table**, in place of a bar document (D4).
  It gave one kind of bar and no new reference step, but the owner chose the
  bar document.
- **A hidden bar, `visible = false`, for no bar.** The owner chose `nothing`
  (D7), which needs no bar document.
- **A constructor that builds `[content | bar]` in a `GridLayout`.** It
  changes the document tree: `get_edited_field(:content)`, the title of a
  file tab, the `.pred` file of a pane and every selection path through the
  pane. A bar next to the pane must also read the output of the pane to know
  the extents, and a projection does not read the output of another.

## 8. Open questions

None. The owner decided the last one, the default value, as D8.

## 9. Risks

- **Positional builds.** A new field in `WidgetScrollPane` and in
  `WidgetTable` changes every positional build. A wrong order of the fields
  does not always fail. `_make_part_pane` and the five builds of step 3 are
  all of them in projectured-julia, its tests and its examples. omnet-julia
  builds these two types only with the short constructors, such as
  `WidgetTable(headers, rows)` and `WidgetScrollPane(content; size)`.
- **A list or a tree in a slot stops growing.** A page that depends on that
  growth changes. omnet-julia puts tables and a list in about ten panes, for
  example `EmbedPanes.jl` and `SimulationResultFrameToWidget.jl`. Step 8 must
  look at those pages too.
- **The inner pane of a list changes the tree of IO maps** of the list: the
  mouse target, the tooltip, the selection band and the context menu go
  through it. Steps 5 and 6 run the tests of each one.
- **An overlay covers the edge of the content.** A cell under a bar is harder
  to press. The bar is 10 pixels thick.
- **The `.pred` file of a pane** writes every field. A `nothing` bar must
  write as `nothing`, and `:auto` as `:auto`. Step 2 checks both. An owner's
  bar is made by a printer and is never saved.
- **The test helper of the data frame view** finds the IO map of the bar in
  the grid ([DataFrameViewTest.jl:47](../../test/adapter/dataframes/DataFrameViewTest.jl#L47)).
  Step 4 changes it to find the bar in the table.
