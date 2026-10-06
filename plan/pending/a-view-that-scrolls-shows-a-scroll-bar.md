# A view that scrolls shows a scroll bar

> **Kind:** plan · **Status:** pending, 2026-10-06. The decisions of §2 are
> made, and no question is open. No step has started. ·
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
not two. The slider solves the same problem with the value at the press, in
view state. The bar keeps its press in view state too. Step 1 decides the
fields and records them here.

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

## 5. Steps

Each step is one commit with its test. Each step updates
[widget.md](../../documentation/package/platform/widget/widget.md) for its
part.

- [ ] **1. The bar.** The gestures of §4.1. Tests:
  [WidgetScrollBarTest.jl](../../test/platform/projection/WidgetScrollBarTest.jl).
- [ ] **2. The pane makes its bars.** The fields of §4.3 with `:auto` and
  `nothing`, the
  overlay of §4.2, the order for the pointer, the write to `scroll_position`,
  and `follow_end`. Tests: a new `ScrollPaneBarTest.jl`, and
  [ScrollPaneHoverTest.jl](../../test/platform/projection/ScrollPaneHoverTest.jl)
  unchanged.
- [ ] **3. The table and the owner's bar.** A pane draws a given bar.
  `_make_part_pane` gives `nothing` to the header panes. The
  table gets its two fields and gives them to the pane of its cells. The five
  positional builds of `WidgetTable` get the new fields:
  [DataFrameViewToWidget.jl:145](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L145),
  [DataFrameViewToWidget.jl:220](../../source/adapter/dataframes/DataFrameViewToWidget.jl#L220),
  [CellTableToWidgetTable.jl:49](../../source/platform/widget/CellTableToWidgetTable.jl#L49),
  [MarkdownToLayout.jl:133](../../source/domain/markdown/MarkdownToLayout.jl#L133) and
  [FrameStatisticsToWidget.jl:236](../../source/platform/statistics/FrameStatisticsToWidget.jl#L236).
  Tests: [WidgetTableTest.jl](../../test/platform/projection/WidgetTableTest.jl)
  and [WidgetTablePartsTest.jl](../../test/platform/projection/WidgetTablePartsTest.jl).
- [ ] **4. The two owners move their bars into the table** (§4.6). Tests:
  `test_data_frame_view()` and `test_frame_statistics_feed()`.
- [ ] **5. `WidgetList` scrolls by itself** (§4.4). Tests: the list cases of
  [WidgetFormsTest.jl](../../test/platform/projection/WidgetFormsTest.jl),
  [MouseTargetMoveTest.jl](../../test/platform/projection/MouseTargetMoveTest.jl)
  and [WidgetForwardTest.jl](../../test/platform/projection/WidgetForwardTest.jl),
  and a new case: a list in a slot scrolls, and its border stays.
- [ ] **6. `WidgetTree` scrolls by itself**, and `FileSystemToWidgetTree` drops
  its pane. Tests: [WidgetTreeTest.jl](../../test/platform/projection/WidgetTreeTest.jl)
  and the tests of the file system.
- [ ] **7. The rule.** [layout-rules.md](../../documentation/rule/layout-rules.md),
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
