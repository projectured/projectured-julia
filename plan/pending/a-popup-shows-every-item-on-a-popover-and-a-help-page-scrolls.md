# A popup shows every item on a popover, and a help page scrolls

> **Status (2026-09-26): in progress** on the branch `popup-surface`, worktree
> `projectured-julia-popup-surface`. The owner took fixes 1, 2 and 3a below.

The owner opened the Help menu in the live application after
[a-press-on-a-menu-name-opens-its-menu.md](../done/a-press-on-a-menu-name-opens-its-menu.md)
landed, and reported three faults with a screenshot.

## The faults (found 2026-09-25)

- **G1. The menu shows one item of three.** The Help menu holds "Documents",
  "Projections" and "About"; the popup shows "Documents" only. Since the layout
  range landed, an item draws `max(minimum, content)` in the range it gets
  (`_resolve_size` in `WidgetToGraphics.jl`). A vertical `WidgetMenu` passes its
  own context to each item (`_menu_item_context`), and a popup window offers its
  content an exact size, so the first item is as tall as the window and the
  others are drawn below its edge. The test of the landed plan read which texts
  were drawn, not where.
- **G2. The popup does not look like the other widgets.** A `WidgetMenu` draws a
  transparent box with no border, which suits the menu bar. In a popup the
  window background shows: the default `bg` of `OpenWindowOperation`, a cream
  tooltip color. The theme has a popover surface (`theme.popover`, white, with a
  `theme.border` hairline), and the menu does not use it. The dropdown of
  `WidgetSelect`, a `VerticalLayout` of `WidgetOption` rows, has no border
  either.
- **G3. A help page does not scroll.** A tab gets no scroll pane, by design
  (`PaneGroupToWidgetTabbedPane`): a page that holds two parts below each other
  must scroll each part. Only the navigator and the assistant scroll, because
  their projections put their content in a `WidgetScrollPane`. The Documents and
  Projections pages are drawn through syntax and text, and no reader answers a
  wheel over them. A probe showed the same for a long JSON and a long Markdown
  tab.

## Decisions (owner, 2026-09-25)

- G1: a vertical menu withholds the height offer from its items, as the menu
  bar withholds the width.
- G2, the recommendation: a vertical menu draws the popover surface of the
  theme (fill, hairline border, small padding, square corners because the
  native window is square); a popup window takes the extent of what it draws,
  as a tooltip does, and no opener estimates its size; the select dropdown gets
  the same surface.
- G3, option (a): the help pages scroll, in a `WidgetScrollPane` put around
  them where the Help menu makes them. Option (b), every text tab scrolls, is
  rejected: "No scroll by default in a tab page, what if a page needs two below
  each other for example? That is a bad idea."

## The design

- **The width of a vertical menu.** Every item of a vertical menu is as wide as
  the widest one, so the hover layer spans the row. The menu reads the width
  each item needs, and offers that width back to every item. To keep this free
  of a cycle, an item measures what it needs in a cell of its own that does not
  read the offer (`natural_width` of its IO map), and prints a widget label with
  the width offer withheld. An element that is not a `WidgetMenuItem` is offered
  no width and keeps its own.
- **The surface.** `WidgetMenuToGraphicsCanvas` gets the style fields of the
  variant `vertical`: `vertical_border`, `vertical_padding`,
  `vertical_border_color`, `vertical_padding_color` and `vertical_content_color`.
  The theme gives the hairline of `theme.border`, the fill of `theme.popover` and
  a small padding. The menu bar, the variant `horizontal`, has no fields of its
  own and stays transparent. `_get_box_insets` learns the variant, as
  `_get_box_colors` already does.
- **The size of a popup window.** `ScreenToScreen` opens a popup with a
  `maximum_size`, so the backend gives the window the extent of what it drew.
  The width and the height of `OpenPopupOperation` become that maximum, with a
  default, and the three openers stop estimating.
- **The select dropdown** is a vertical `WidgetMenu` of its `WidgetOption` rows,
  so it gets the surface and the sizing of a menu.
- **The help pages.** The Help menu opens the Documents and the Projections
  lists inside a `WidgetScrollPane`, with the title of the list. `_find_tool_tab`
  looks into a scroll pane, so a second press focuses the tab and does not open
  a second one.

## Steps

- [x] 1. **G1.** A vertical menu withholds the height offer from its items.
  Test: the Help menu in its popup window draws all three items inside the
  window.

  Done. `_menu_item_context` withholds the offer on the axis along which the
  items follow each other. The popup test of `test_window_wrap` now asserts that
  both items of its menu are drawn inside the window, one below the other: 28
  pass.
- [x] 2. **G2, the width and the surface.** The natural width of an item, the
  row width of a vertical menu, and the surface fields. Test: every item of a
  vertical menu has one width; the surface draws the border and the fill of the
  theme; the menu bar draws none.

  Done. The item measures what it draws in a cell of its own (`measured`), and
  its IO map carries `natural_width`; a widget label prints with the width
  offer withheld. The dropdown offers each item `row_width`, a forward cell
  installed with `set_cell_computation!` once the items exist.

  **Found on the way:** the first version looped. In a window scene each item
  comes inside a `ReferenceDispatchingIoMap`, so the row width read the drawn
  width of the item, which reads the row width, and every read overflowed the
  stack (360 000 warnings in one run). `_menu_row_width` now reaches the item
  through the `inner_iomap` of a host wrapper (`_find_menu_item_iomap`), and it
  never reads the drawn width of an item: one that it can not reach counts
  nothing and still draws what it needs. `test_window_wrap` checks the widths
  through that wrapper. `test_widget_menu` and `test_window_wrap`: 73 pass.
- [x] 3. **G2, the popup size.** A popup window has a `maximum_size`; the
  openers pass no estimate. Test: the popup window of the Help menu fits what it
  draws.

  Done. `OpenPopupOperation` takes `width = 640` and `height = 800` by default,
  as the bound of the popup, and `ScreenToScreen` opens the window with that
  `maximum_size`. The submenu of a menu item, `WidgetContextMenu`, the context
  menu probe and the select pass no size. The estimates go, and with them the
  `font` field of `WidgetContextMenuToGraphicsCanvas` and the `width` and
  `row_height` fields of `ContextMenuProbeProjection`, which only served them.
- [x] 4. **G2, the select dropdown** is a vertical menu. Tests: the select
  tests and the window wrap test.

  Done, in the same commit as step 3, because both change the select opener.
  The dropdown is `WidgetMenu(options)`. `test_window_wrap` now draws the popup
  of the select with the rows of `make_opened_window_projections` and checks
  that the window has the bound and the drawn dropdown is smaller than it. The
  header of `WidgetSelectTest.jl` named the resolver that the last plan removed;
  it describes the present now. The popup suites: 170 pass before the fix of
  the window wrap test, and `test_window_wrap` 33 pass after it.
- [ ] 5. **G3.** The help pages open inside a scroll pane. Test: in the
  application, a wheel over the Documents tab moves its rows, and a second press
  on "Documents" opens no second tab.
- [ ] 6. The documents: `widget.md`, `screen.md`, `shell.md`.
- [ ] 7. A live check on the display, the verification against `main`, and the
  move of this plan to `plan/done/`.
