# The wheel scrolls a cut text, and a tab strip that does not fit

Status: pending. Branch `widget-scroll`, worktree `projectured-julia-widget-scroll`.

## 1. The ask

The owner, 2026-11-15, after the plan
[a-widget-cuts-its-content-at-its-box](../done/a-widget-cuts-its-content-at-its-box.md) landed:
"solve scrolling in text field and area, and also tab pane selector parts if they don't fit the
space".

## 2. Facts

- A `WidgetText` and a `WidgetTextarea` cut a text that is larger than their box, and draw it at
  the offset `scroll_position` (view state). The build moves the offset by the least amount that
  shows the caret (`_compute_text_scroll`). The reader writes the drawn offset back with its next
  answer (`_keep_text_scroll`). No reader of the two widgets reads `MouseScroll`, so the wheel
  moves nothing in them.
- A scroll pane gives the wheel to its content first, and scrolls itself only when the content
  answers `nothing` (`_self_scroll`). A pane at its end answers `nothing`, so the next pane out
  scrolls.
- A notch over a pane moves `lines_per_notch` lines (3), at most the view less one line. A fast run
  of notches grows by `wheel_growth` (1.25), which the pane keeps in the view state `wheel_run`
  (`_compute_wheel_turn`, `_add_wheel_run`). A touchpad turn moves by its fraction. Ctrl and the
  wheel zoom and never scroll.
- If the build keeps the caret in view at each print, a turn of the wheel that moves the caret
  out of the view is taken back at the next print. So the build must know when the caret moved
  after the turn.
- A `WidgetTabbedPane` cuts its tab strip at the width of its slot, and a vertical or horizontal
  turn over the strip scrolls it (`tab_scroll`, view state). The rule test lists the tabbed pane in
  `_RULES_INK_BROKEN`: it draws past the extent that it reports in some state.
- An image of ten tabs in a pane of width 300 (2026-11-15) shows four faults:
  - The line under the tabs runs past the right edge of the pane, over the next widget, to the
    end of the strip. The page panel and the box do the same. They take the width
    `max(strip_w, page_w)`, not the width of the slot.
  - The open tab can be out of view: with tab 9 open, the strip shows tabs 1 to 3.
  - Nothing shows that more tabs exist, and only the wheel reaches them.
  - A tab whose name is longer than the pane is cut at the pane, and its close button is out of
    view.
- A widget opens a popup with `OpenPopupOperation`, as a select and a menu do.

## 3. Decisions

- **D1** (proposed by the assistant): a turn of the wheel over a text widget moves its text on the
  axis of the turn when the text is larger than the box on that axis. Else the turn goes on to the
  pane around the widget. So a vertical turn over a one-line field scrolls the page, and a field
  takes only a horizontal turn. Rejected: a vertical turn moves a field sideways, as over the tab
  strip. That stops the scroll of a form at each field under the pointer.
- **D2** (proposed by the assistant): a notch moves the text as a notch moves a pane: the same
  step, the same speed-up of a fast run, the same touchpad fraction. A text widget keeps its own
  `wheel_run`. A turn at the end of the text moves nothing and goes on to the pane around it.
  Ctrl and the wheel never scroll a text.
- **D3** (proposed by the assistant): the wheel leaves the caret where it is, also outside the
  view. The text stays where the wheel put it while the widget holds the selection that it held at
  the turn. The view state `scrolled_selection` keeps that selection. A new selection, from a key,
  a click or an edit, moves the text again to show the caret. Rejected: the wheel moves the caret
  with the text. No editor that a person knows does that.
- **D4** (proposed by the assistant): a disabled text widget scrolls with the wheel too. A turn is
  no edit, and a person can read a long disabled text.
- **D5** (proposed by the assistant): the tab strip shows the open tab, as a text widget shows its
  caret, and the wheel moves it away until the open tab changes. A keyboard switch of a window tab
  is read above the tabbed pane, so it does not clear `scrolled_tab`: after a turn, a switch away
  and back to the tab of the turn shows the strip where the wheel put it.

- **D6** (the owner, 2026-11-15, option C): when the tabs do not fit, the tabs first shrink to
  share the width, and their names are cut with "…". Below a minimum width, a menu button at the
  right end of the strip shows, only while tabs are hidden. It lists all tabs, and a click opens
  one. Rejected by the owner: A, arrow buttons at the ends; B alone, the menu button with no
  shrink.
- **D7** (proposed by the assistant): in a slot, when the tabs at their natural width do not fit,
  only the names shrink. The icon, the badges and the close button stay whole. Each name is at
  most a cap wide, and the cap is the largest that lets the tabs and the new-tab button fit; a
  name that is shorter than the cap keeps its width. A cut name ends with "…". A name that holds
  the caret keeps its whole width. With no slot, the strip keeps its natural width. Rejected: all
  tabs take the same width. A short name then takes space that it does not need.
- **D8** (proposed by the assistant): a name shrinks to no less than four widths of "M" of its
  font, or its own width when that is less. The count is a field of the projection,
  `minimum_name_ems`, 4 by default.
- **D9** (proposed by the assistant): when the names at their minimum do not fit, the menu button
  shows at the right end of the strip, outside the part that scrolls, with the icon
  `chevron_down`. The strip scrolls as before in the rest of the width. A click on the button
  opens the context menu window at the button, with one item for each tab, in the order of the
  strip, with the whole name. The menu is a layer of the list of pages, so an item opens its tab
  as a click on the tab does: in a plain pane it selects `selector_element_pairs[i]`, and in a
  group of window tabs the pane tree maps that to `tabs[i]`. Rejected: a popup whose items hold
  final operations, as the list of a select does. The pane of a window group is an output of the
  pane tree, so no final operation can open its tab.

## 4. Steps

1. [x] The wheel in a text field and a text area (D1–D4). `WidgetText` and `WidgetTextarea` get
   the view state `wheel_run` and `scrolled_selection`, and their projections get
   `lines_per_notch` and `wheel_growth`. The build gives the offset, the largest offset and the
   view; the reader reads `MouseScroll` before the text domain. Tests in `WidgetTextEditTest.jl`:
   a horizontal turn over a cut field, a vertical turn over it that goes on, a turn over a cut
   text area and at its end, Ctrl and the wheel, and the caret that shows again after a key.
   Done 2026-11-15. The IO map field `scroll` holds `(offset, room, view)`, so the reader has the
   largest offset and the view that the build computed. `_is_following_selection` compares the
   selection with `scrolled_selection` by `==`. `_keep_text_scroll` clears `scrolled_selection`
   at the next answer after the selection changed, so a caret that comes back to the place of the
   turn shows too. The build reads the selection box only while it follows the selection.
   `test_widget_text_editing`: all pass, 14 new assertions.
2. [x] The tab strip that does not fit (D5–D9).
   - [x] The parts that do not depend on the answer, done 2026-11-15. The page panel, the box
     and the line under the tabs take the width of the slot (`_get_tabbed_pane_inner_width`).
     The strip moves by the least amount that shows the open tab, except while the open tab is
     `scrolled_tab`, the tab that was open at the last turn of the wheel (D5). A click on a tab
     writes the drawn offset and clears `scrolled_tab`, so the strip does not jump. Both fields
     are declared view state. Found on the way: in a slot, the reader read the width of the strip
     view at the wrong level of the output, so it took the strip as one that fits. The wheel then
     moved nothing, and a click on a scrolled strip hit the wrong tab. The IO map now keeps the
     width that the printer used (`strip_view_width`). Test in `WidgetTabStripTest.jl`.
   - [x] The names shrink and are cut with "…" (D7, D8). Done 2026-11-15.
     `_tab_strip_geometry` takes the width of the slot, which the IO map keeps
     (`strip_slot_width`), so the printer and the reader compute the same shrunk strip. The
     geometry gives `view_w`, `menu_x` and `menu_w`; `_tab_view_w` is gone. The cap is a binary
     search over the widths (`_compute_name_cap`), and the cut takes the wider of the two fonts of
     a name (`_cut_tab_name`).
   - [x] The menu button and its menu of the tabs (D9). Done 2026-11-15. The button is drawn like
     the new-tab button, in a canvas of its own after the view of the strip. Its click answers
     `OpenContextMenuOperation` with the source `selector_element_pairs[1]`, one step below the
     part, and the point under the button. Tests in `WidgetTabStripTest.jl`: the shrink, the cut
     names, and the menu item that opens its tab through `find_menu_item_part`.
3. [ ] The guides: the widget page and the docstrings of the two widgets. Move the plan to
   `plan/done/`.

## 5. Open question

None. The question of the tab strip was answered with D6.

## 6. Not in this plan

- A scroll bar on a text area.
