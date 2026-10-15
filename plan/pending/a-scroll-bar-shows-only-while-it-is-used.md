# A scroll bar shows only while it is used

> **Status (2026-10-15): pending.** The owner asked for it: "the scroll bars
> should auto hide and show only if its being dragged or the mouse is over the
> bar, this is typical in modern UIs so the scroll bar doesn't hide anything".
> The owner agreed to step 2 (show the bar after a scroll) and step 3 (fade).
> Steps 1 and 2 are done.

## The goal

A scroll bar shows nothing at rest. It shows while the pointer is on the bar,
while its thumb is dragged, and for a short time after the view scrolls. It
fades in and fades out.

## The facts (2026-10-15)

1. One printer draws every bar: `print_document(p::WidgetScrollBarToGraphicsCanvas, …)`
   in `source/platform/widget/WidgetToGraphics.jl`. It draws the bars that a
   `WidgetScrollPane` makes (`:auto`), the bars of a list, a tree and a table
   (they share the pane), and the bars that a maker gives as a
   `WidgetScrollBar`: the data frame view, the frame statistics and the task
   pages.
2. The track is transparent at rest (`track_color = color_transparent`). The
   thumb is `thumb_color`, the `border` color of the theme. While the cell `lit`
   is true, the track is `track_hovered_color` and the thumb
   `thumb_hovered_color`.
3. `lit` is `_is_under_pointer(w) || w.thumb_drag !== nothing`. An owned drag
   also sets `thumb_drag` on the bar (`make_owned_scroll_bar_drag`), so `lit` is
   true during every drag of a thumb.
4. A pane finds a bar under a point by its place, not by its paint
   (`_find_pane_bar_at` reads `bar.place`). A bar with transparent parts still
   takes the move, the press and the drag.
5. A color of a bar is a cell. A change of `lit` paints the area of the bar
   again and prints nothing again.
6. A printer reads the animation clock from `ctx.clock`, as
   `WidgetProgressRing` does. The loop draws frames only while a cell reads the
   clock with `get_reactive_clock_time` (`has_clock_readers`, `Feeds.jl`).
   `get_clock_time` records no dependency.

## Steps

### Step 1: a bar shows nothing at rest

- ✅ Make the default rest color of the thumb `color_transparent`. The bar then
  shows only while `lit` is true.
- ✅ Update the comment over `WidgetScrollBarToGraphicsCanvas(theme; …)`, the
  docstrings of `WidgetScrollPane` and `WidgetScrollBar`, and the section "The
  scroll bars" of `documentation/package/platform/widget/widget.md`.
- ✅ Update the tests that assert the rest color: `WidgetScrollBarTest.jl`,
  `ScrollPaneBarTest.jl`, `WidgetTableBarTest.jl`, `WidgetColorTest.jl`. Only the
  first two assert it. The five bar tests pass: 208 of 208.
- ✅ `tool/widget-images.jl`: draw the bar of the gallery lit, so its picture
  shows a bar. The example `make_widget_scroll_bar_document_example` puts the
  mouse target on its bar, as the focus example puts a selection. The tool
  itself does not change.
- ⬜ Check in the live app: a pane, a list, a table and the data frame view.
  This check runs once, after step 3, for the three steps.

A projection that wants a bar at rest passes `thumb_color`. No setting is added.

### Step 2: a bar shows after a scroll

- ✅ The printer keeps the clock time of the last scroll in a cell. A scroll is
  a change of `value` that keeps `thumb_size`. A change of both is a change of
  the size of the content, such as a typed line or a log that grows, and does
  not show the bar.
- ✅ The first print starts with no scroll, so a new pane does not show its bar.
  The cell keeps the last value and thumb size in the closure of its
  computation (`_make_change_time_cell`), because the cell layer gives a
  computation no value of its last run.
- ✅ The bar shows while `lit` is true or for `show_duration` seconds after the
  last scroll. The cell reads `get_reactive_clock_time` only during that time,
  so a bar at rest makes no frames. With no clock, the bar shows only while
  `lit` is true.
- ✅ `show_duration` is a field of the projection with a keyword, 1.0 s by
  default.
- ✅ After a scroll only the thumb shows, in the new style field
  `thumb_scrolled_color` (the theme `border`, the color of the thumb at rest
  before step 1). The track shows only under the pointer, as macOS and GTK do.
- ✅ A context whose clock no code writes keeps a thumb that a scroll showed. Two
  overlays print so: `FaultLogOverlay` and `GestureLogOverlay`. A bar then
  stays visible, never hidden under the pointer.
- ✅ Test with a `Clock` that the test writes with `set_clock_time!`
  (`WidgetScrollBarTest.jl`). The five bar tests pass: 218 of 218.

### Step 3: a bar fades in and out

- ⬜ The printer keeps the clock time of the last change of "shown". The alpha
  of the track and of the thumb goes from 0 to 1, or from 1 to 0, over
  `fade_duration` seconds, 0.15 s by default.
- ⬜ The cell reads `get_reactive_clock_time` only during a fade.
- ⬜ Test the alpha at three clock times of a fade, and that a bar at rest reads
  no clock.

## Decisions

- No new event, operation, field of a document or setting. The state of a show
  and of a fade lives in cells of the printer, and the clock is the one that
  exists.
- Not `SetTimerOperation`: a `TimerExpire` has no point and no window, so it has
  no route down to one pane.
