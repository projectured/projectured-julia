# The window has one system for space

## The goal

The user (2026-11-03) saw that the padding, the margins and the gaps of the
window are not consistent, and that the window looks wrong because of it:

- some dividers run from one edge to the other, and some stop short;
- a part of a split pane reaches the divider but not the edge of the window;
- the space between the toolbar and the tab group looks wrong;
- the filter field of the Explorer has no space above it;
- the details pages of the IDE have no consistent spacing;
- many layouts have no gap where their content needs one.

The user asked for a set of rules that looks good, and for a splitter that
looks as in Visual Studio Code. This plan puts the rules into the themes and
the widgets of projectured-julia, and into the pages of omnet-julia.

Two pages show the study and the values:

- the rules page, with the causes in the code, the ten rules and the chosen
  values: https://claude.ai/artifact/HgtbC5fRLCFH9kbSpgy9iz
- the playground, with fourteen screens and a slider for each value:
  https://claude.ai/artifact/3SWGvwjk3KpHPeusKtaCP4
- the derivation of the rules from first principles, from a window with no
  space at all: https://claude.ai/artifact/LSyJQotJh7cRRhA6FAHDNC, with its
  text in
  [spacing-starts-from-first-principles.md](spacing-starts-from-first-principles.md)

## Why the window looks wrong now

1. **The tab group pads its page.** `tabbed_pane_padding` is 8 on each side
   (`WidgetTheme.jl:124`, read at `WidgetToGraphics.jl:809`). A split pane in
   a tab starts and stops 8 px inside the tab group, but the split pane itself
   has no padding. So a part of the split has 8 px at one side and 0 px at the
   other.
2. **The bands of the window have no edges.** The toolbar, the gap under it
   (`item_gap`, `WidgetToGraphics.jl:732`), the tab group padding and the tab
   padding (`item_gap`, `:820`) give 20 px of empty space with no line. Under
   the tab there is 0 px. The tab strip is a pill as wide as its tabs (`:4992`).
3. **Each layout picks its own gap.** The default gap of a layout is 0
   (`LayoutDocument.jl:151`, `:198`). The layouts of `source/` use ten
   different gaps from 0 to 24. `section_gap` is 8, 10 or 14 by theme. A row of
   buttons has a gap of 0, 2, 6 or 12 by place.
4. **The themes name the space by widget, not by role.** `item_gap` does
   eleven jobs that are not the gap between the items of a bar. `band_padding`
   is `Inset(6, 10, 6, 10)`, which is 6 at the top and 10 at the bottom.
5. **The pages of omnet-julia do not read the theme of the window.** They read
   `get_theme_defaults(WidgetTheme)`, so the scale of the appearance and the
   IDE theme of `WorkbenchRender.jl:161-162` do not reach them.
6. **The splitter has one state.** It is a 1 px rect of the border colour
   (`WidgetToGraphics.jl:4436`). Nothing shows where to grab it.

## The decisions

**The values.** The user chose them in the playground (2026-11-03). In px,
`Inset(top, bottom, left, right)`:

| Role | Field | Now | Chosen |
|---|---|---|---|
| around the strip and the page of a tab group | `tabbed_pane_padding` | 8, 8, 8, 8 | 0 |
| inside a tab | `tab_padding`, new; now `item_gap` | 2 on each side | 4, 4, 8, 8 |
| under the toolbar | `band_gap`, new; now `item_gap` | 2 | 0 |
| from the filter bar to the tree of the Explorer | now `section_gap` | 8 | 4 (`item_gap`) |
| between the items of a bar | `item_gap` | 2 | 4 |
| around a row of a tree | `tree_row_padding`, new; now `item_gap` | 2, 2, 0, 0 | 2, 2, 8, 8 |
| a level of a tree | `indent` | 12 | 12 |
| inside a table cell | `control_padding` | 5, 5, 10, 10 | 4, 4, 8, 8 |
| the space that a slot gives to what it holds, once | `slot_padding`, new | none | 8 on each side |
| inside a card, a dialog, an alert | `container_padding` | 12 | 8 |
| between cards and sections | `section_gap` | 8, 10 or 14 by theme | 8 |
| under a title | `title_gap` | 4 | 2 |
| between the lines of facts | `line_gap`, new; now `item_gap` | 2 | 2 |
| inside a button, a field | `control_padding` | 5, 5, 10, 10 | 4, 4, 8, 8 |
| between push buttons | `button_gap`, new | 0, 2, 6 or 12 | 8 |
| between an icon and its label | `label_gap` | 6 | 6 |
| between the rows of a form | `form_row_gap` | 8 | 6 |
| between a label column and a control column | `form_column_gap` | 12 | 8 |
| inside a dropdown, around its commands | `menu_padding`, new; now `item_gap` | 2 | 4 |
| inside a command of a menu | `menu_item_padding` | 4, 4, 12, 12 | 4, 4, 8, 8 |
| inside the band of a file page | `band_padding` | 6, 10, 6, 10 | 4, 4, 8, 8 |

**The look.** The user chose (2026-11-03):

- the tab strip stays a pill as wide as its tabs;
- a 1 px line under the menu bar, under the toolbar, under the tab row and
  above the status bar;
- the line under the tab row has a gap under the selected tab, so that tab
  joins its page;
- the link groups of the Explorer page stay cards;
- a table keeps its border, and stands 8 px from the edges of its slot, in a
  tab and in a split, so two tables in a split never touch;
- the splitter as in Visual Studio Code: a 1 px line of `border` at rest, and
  a 4 px band of `ring` on the middle of the line when the pointer stays on it
  for 0.3 s and while it is dragged, with a fade of 0.1 s. The grab area stays
  7 px.

**The space at an edge is given once, by the first box in a slot.** The user
chose this (2026-11-03, "F2 looks good") after real screens of each option in
twelve cases. So:

- The frame reaches the edges: the lines of the window, the tab strip and the
  dividers of a split. A tab group and a split pane add no space around what
  they hold.
- A slot of the frame, the page of a tab or a slot of a split, puts the space
  that it gives, `slot_padding`, into the offer that it makes to what it holds.
  The value is an `Inset`, so it can differ by side. "How a box takes the
  space" below says how.
- The first box in the slot that has an edge gives that space around itself,
  and passes `Inset(0, 0, 0, 0)` to what it holds. So a page in a card, a page
  in a page, a dialog or a cell never gets the space twice, and no page adds a
  padding of its own. A widget that holds nothing, such as a label, also
  takes the space around itself.
- The input is the printer context, and the type of the box decides how the
  box takes the space. The user accepted this on 2026-11-04 (decision D1 of
  [spacing-starts-from-first-principles.md](spacing-starts-from-first-principles.md#8-what-the-user-decided)).
  No printer searches up the path for a parent with an edge, and no slot looks
  at what its document becomes.
- A layout draws no edge, so it passes the space on by side: a column gives
  the left and the right space to each child, the top space to its first child
  and the bottom space to its last child, and a row does the same across. A
  grid gives each side to the cells at that side. This follows from D1, and
  the user accepted it on 2026-11-04: without it, the layout of the filter bar and the tree of
  the Explorer takes the space around itself, and the bands of the tree stop
  8 px short of the edges.
- A split pane and a tab group give nothing themselves, and each of their slots
  gives `slot_padding` again. So the dividers reach the lines, and two tables
  in a split have 8 px on each side.
- A card, a dialog, a table cell and an alert keep their own padding inside
  their edge, as now.

**How a box takes the space.** The user accepted this design on 2026-11-04,
after rejecting a copy of the projection for each print ("a copy of the
projection is a terrible idea"). It is the design as it would be made from the
start, with no weight for the amount of code that changes.

- The space is a part of the offer. `PrinterContext` holds it as a field next
  to the size range of each axis, not as a property that flows down the whole
  tree. Each function that makes the offer for a child states the space, and
  where it states none, the space is 0. So a printer that does not know the
  space can not pass it one level too deep. A chain of projections is one
  print, so each of its stages sees the same offer.
- A box computes its shape once: the outer box, the margin, the border, the
  padding and the content, from its projection, its document and the given
  space. The space lies outside the margin and inside the image of the box, so
  a parent counts it in the extent, as it counts a margin. The IO map of the
  box carries the shape. Its readers, the hit tests and the rings of a
  selection read the shape there, and never compute it again from the
  projection and the document.
- No printer makes a copy of its projection for a value of one print.
  `TextToGraphics` does that for `:line_spacing` now (`TextToGraphics.jl:117`
  and `:448`). Step 5 removes it: the text printer reads the line spacing from
  the context, and its IO map carries the line positions for its readers.

**A scroll pane is symmetric.** The user (2026-11-03): "it should be
symmetric, so if it touches the bottom then it should also touch the top". So
the scroll pane gives the space at its view: it cuts its content 8 px inside
every edge, at every scroll position, and its bar stays at its outer edge.
Android by default (`clipToPadding`) and Qt (`setViewportMargins`) do the same.
CSS, macOS and iOS let the padding scroll with the content, which is symmetric
only in the middle of the scroll. The user accepted this look, S2, on
2026-11-04 (decision O1). The cost: the view loses 16 px of height, and text
disappears 8 px before the line.

**The band of a selected row reaches the edges of its slot.** The user
accepted this on 2026-11-04 (decision O3), as in Visual Studio Code and
JetBrains. A `WidgetTree` and a `WidgetList` take the top and the bottom
space around themselves, and their own scroll pane cuts inside it. They take
the left and the right space as the side padding of their rows, and
`tree_row_padding` where they are given none, as in a card. So a band reaches
the slot edges, and the first letter of a row stays 8 px from the edge. Two
trees in a split can have bands that touch the divider from both sides; the
divider is a line and a tree has no border. A table keeps its border and its
8 px. A tree that scrolls sideways scrolls its side space with its rows.

**Rejected**, with the real screens of each:

- the child adds its space: twice the space in a card, a page, a dialog or a
  cell;
- every slot gives 8: a split in a tab stands 8 px inside, and its dividers
  stop short;
- every slot gives 8, and a split fills: the tab group holds a document and
  does not see that it becomes a split;
- a table fills its slot with no border: the user wants a table to keep its
  8 px, and two tables in a split must not touch.

## Steps

Work in a git worktree of a branch. Make one commit for each step. Before step
1, run the tests of each step on `main` and keep the counts, so a failure that
was there before is not taken for a regression. Landing on `main` needs the
approval of the user.

- [x] 1. **Give each job of `item_gap` its own field.** The screen must not
      change. Add `tab_padding` (`Inset(2, 2, 2, 2)`), `tree_row_padding`
      (`Inset(2, 2, 0, 0)`), `band_gap` (2), `menu_padding` (2), `popup_gap` (2)
      and `line_gap` (2) to `WidgetTheme`, and move the readers:

      | Reader | Place | Field |
      |---|---|---|
      | the padding of a dropdown | `WidgetToGraphics.jl:598` | `menu_padding` |
      | the popup of a menu item, of a select, of a context menu window | `WidgetToGraphics.jl:645`, `:9792`, `ContextMenuWindow.jl:97` | `popup_gap` |
      | the gap under the toolbar | `WidgetToGraphics.jl:732` | `band_gap` |
      | the tab padding, now one `Int` for both axes | `WidgetToGraphics.jl:820` and `_tab_strip_geometry` | `tab_padding` |
      | the row padding of a tree, now one `Int` | `WidgetToGraphics.jl:12168` | `tree_row_padding` |
      | the items of an accordion, a choice list, the value list of a column, the prompt of the input dialog | `WidgetToGraphics.jl:10575`, `WidgetChoiceList.jl:109`, `WidgetColumnHeader.jl:259`, `WidgetDocument.jl:755` | `line_gap` |

      The other readers of `item_gap` space the items of a bar and keep it:
      the toolbar, the status bar, the pager, the filter bar, the column chooser
      and the chips of a pivot table. Check: an image of the editor window from
      the SDL backend is the same before and after; `test_widget_tab_strip()`,
      `test_widget_tab_label()`, `test_widget_tree()`,
      `test_widget_select_dropdown()` and `test_widget_shell_layout()` give the
      counts of the baseline.

      Done. Facts:

      - The select, the menu item and the shell read the new fields as `Int`
        cells. `ContextMenuWindowProjection` has the field `popup_gap` now.
      - `tab_padding` of the tabbed pane is an `Inset`. `_tab_strip_geometry`
        returns `pad` as a named tuple `(top, bottom, left, right)` of `Int`.
        The width of a tab adds `left + right`, the height adds
        `top + bottom`. The label and the icon stand at `left` and `top`. The
        button column stands `right` from the end of the tab.
      - `row_padding` of the tree is an `Inset`. Only `top` and `bottom` are
        read (the row height and the vertical place of the text and the
        icon). `left` and `right` are not read yet, because a row places its
        content from `indent` and the chevron column.
      - `_get_line_gap(theme)` stands next to `_get_bar_item_gap` in
        `WidgetTheme.jl`.
      - The 44 images of `tool/widget-images.jl` are the same before and
        after. The tests of the step gave 377 Pass, 0 Fail, 0 Error, 0 Broken.
- [x] 2. **Set the chosen values** of `control_padding`, `container_padding`,
      `menu_item_padding`, `band_padding`, `item_gap`, `title_gap`,
      `form_row_gap`, `form_column_gap`, `tab_padding` and `menu_padding`. Move
      the readers whose job is a role that already exists: the gap of a dialog
      (`WidgetToGraphics.jl:2825`) to `section_gap`, the gap in a select
      (`:9789`) to `label_gap`, and the rows of the appearance tab
      (`AppearanceToWidget.jl`) to `form_row_gap`. A test that hard-codes a
      value of the old defaults reads it from the theme instead:
      `WidgetScaleTest.jl:87`, `WidgetCardFoldTest.jl:75`, `:100` and
      `:211-212`, `AppearanceTabTest.jl:164-168`, `AppearanceFileTest.jl:47`,
      `MouseTargetMoveTest.jl:306-320`, `ExplorerTest.jl:703`. Check:
      `test_widget_scales()`, `test_widget_card_fold()`,
      `test_appearance_tab()`, `test_appearance_file()`,
      `test_mouse_target_move()`, `test_explorer()` and `test_dataframes()` pass
      with the counts of the baseline; in an image of the window, a button is
      26 px high and a tab 24 px.

      Done. Facts:

      - The theme has the chosen values. A dialog reads `section_gap`. A
        select reads `label_gap`; its gap is the space between the value and
        the chevron. The appearance tab reads `form_row_gap` in the grids of a
        setting (`AppearanceToWidget.jl` at the two `GridLayout` calls and the
        list of the sections of a card). It keeps `item_gap` for the colour
        swatches side by side and for the colour and the font of one field
        (a field is one item, not a row of the form).
      - The dialog gap is also the space between its buttons side by side.
        The role `section_gap` covers both until step 7 splits them.
      - Images: 23 of the 44 examples changed; 21 are the same. The changed
        ones are `widget`, `widget_tooltip`, `widget_menu`, `widget_toolbar`,
        `widget_toolbar_item`, `widget_title_pane`, `widget_split_pane`,
        `widget_shell`, `widget_offered`, `widget_tabbed_pane`, `widget_card`,
        `widget_progress_ring`, `widget_alert`, `widget_toggle`,
        `widget_toggle_group`, `widget_select`, `widget_textarea`,
        `widget_accordion`, `widget_table`, `widget_table_offered`,
        `widget_table_frozen`, `widget_disabled` and `conversation_widget`.
        The same: `widget_button`, `widget_tree`, `widget_focus` and the
        examples of fixed size (label, text, checkbox, switch, slider and the
        like).
      - Measured with the font of the examples (Ubuntu 20): a button is 33 px
        high (text line 25 plus 4 + 4) and the tab strip of `widget_tabbed_pane`
        is 31 px high (23 plus 4 + 4; it was 27). The heights 26 and 24 hold
        for a text line of 18 and 16 px. The example `widget_button` gives its
        button a fixed size, so its image does not change.
      - Tests that read the theme now: `WidgetScaleTest` (the growth of a
        control), `WidgetCardFoldTest` (the padding of a card and the places
        of the clicks), `AppearanceTabTest` (the spin box and the inverse of
        the item gap), `AppearanceFileTest`, `MouseTargetMoveTest` (the place
        of the two buttons in a card), `ExplorerTest` (the press on a tab goes
        to the text of the tab) and `DataFrameViewTest` (the step of a row).
        Counts: the ten platform functions 797 Pass, 0 Fail; `test_dataframes`
        603 Pass. `test_platform_layering` has the one known failure.

      Facts found after the step. The suite of step 4 found these, in
      functions that step 2 did not run. Each is a place that the values move
      on purpose, so each fix is in a test, but for the forward map of the bar
      of a table.

      - `title_gap` 2: the split pane example has no offer of a height, so it
        is as tall as its title panes, 50 px and not 52. The press at y 50 of
        `test_split_pane_drag` and `test_part_pointer_shape` was under the
        split. The splitter takes a press over its full height. The tests
        press at the middle of the height that the split draws (748a71b6b).
      - `container_padding` 8: the last row of the list in the card of
        `ScrollPaneHoverTest.jl:124` moves 4 px down, to y 162 to 189, so the
        press at y 160 found row 39. The test computes the press from the
        theme: 200, less the border and the padding of the card and the border
        of the list, less 1 (78f02f8b6).
      - `container_padding` 8 and `title_gap` 2: the form of the find bar
        stands 6 px higher, its label at y 32 and not 38, so the press of
        `FindBarViewToWidgetTest.jl:137` is over the second line of the text
        and not the third. The test checks the second line, where the caret is
        at another column (988e6d666).
      - The settings tab is shorter: the row of the undo steps starts at y 290
        and not 312 (step 3 adds 1 px), in a window of 300.
        `SettingsTabTest.jl` makes the window 280 px high, so the row starts
        below it, and reads that height in its other checks (6b7c6777f).
      - `control_padding` 4, 4, 8, 8: the rows of `widget_table_frozen` are
        shorter, and 3 px of row 4 show at the bottom of the view, under the
        horizontal bar, which lies over the content. `test_widget_round_trip`
        took each cell of row 4 for a cell that maps back to the wrong part.
        The test now finds the box of the part that a point maps to, and tries
        the points of the cell outside that box. Cells 1 to 3 have none, so
        they are covered. Cell 4 reaches 1 px past the end of the bar, to
        x 310 in the square at the corner of the two bars, and a point there
        maps back to it. For the box, the table maps the field of a bar
        forward: it mapped a point on its bar back to the field, but the field
        forward to nothing, a defect of `main`. Now the field maps to the canvas that the bar
        prints, in the table whose rows are a vector and in the table whose
        rows are a list, as the scroll pane maps its own bars
        (`_map_table_bar_forward`, `WidgetTableParts.jl`). The 44 images are
        the same, and `test_dataframes` has 603 Pass (0a4b62ea3).
- [x] 3. **Draw the four lines.** The shell draws a 1 px line of `border`
      under the menu bar, under the toolbar and above the status bar, and
      `band_gap` becomes 0. Each line takes 1 px of height, as a splitter takes
      its width. The tab group draws a 1 px line under its tab row, with a gap
      under the selected tab. Check: `test_widget_shell_layout()`,
      `test_widget_shell_pointer()`, `test_window_shell()` and
      `test_widget_tab_strip()` pass, with the shell test changed for the
      lines; a pixel scan of an image of the window finds the four lines, the
      gap under each selected tab, and the outer divider from the line under
      the toolbar to the line above the status bar.

      Done. Facts:

      - New style fields: `band_line_stroke` of `WidgetShellToGraphicsCanvas`
        and `tab_row_line_stroke` of `WidgetTabbedPaneToGraphicsCanvas`. Both
        are `StyleStroke(t.border, t.border_width)` from the theme. `band_gap`
        of the theme is 0.
      - The shell adds the width of `band_line_stroke` (at least 1 px) to the
        height of the menu bar, of the toolbar and of the status bar. A band
        that the shell does not have has no line. The line of the menu bar and
        the line of the toolbar stand at the bottom of their band, the line of
        the status bar at its top. A line is as wide as the shell. The
        pointer readers use the offsets of the child entries, so they follow
        with no change.
      - The tab geometry has two new fields, `rule` and `page_top` (the strip
        height plus `rule`). The page, its box, its ring, its offered height
        and its child offset start at `page_top`. The line under the tab row
        starts at the left edge of the padding box and ends at its right edge.
        It has a gap from the left to the right edge of the selected tab, in
        step with the scroll of the strip.
      - Images: 3 of the 44 examples changed: `widget`, `widget_shell`,
        `widget_tabbed_pane`. The other 41 are the same.
      - Pixel scan of a window with a menu bar, a toolbar, a status bar and
        two tab groups in a split (the gallery shell around
        `widget_split_tabs`, 1000 x 560): lines of `border` at y 35 (menu
        bar), y 75 (toolbar) and y 530 (status bar), each over the full width.
        The line under the tab rows is at y 119, with a gap at x 12-110 and
        x 513-615 (the selected tabs). The divider is at x 500, y 76 to 529,
        and it touches the line under the toolbar and the line above the
        status bar.
      - Tests: `test_widget_shell_layout` changed in two assertions, each by
        exactly the 1 px line (`content[2] == menu[2] + height(menu) + 1`,
        `y + h + 1 == status[2]`). Counts: shell layout 14, shell pointer 6,
        window shell 149, tab strip 29, tab label 24, explorer 313, mouse
        target move 85, all Pass; `test_dataframes` 603 Pass.

      Facts found after the step. The suite of step 4 found these, in
      functions that step 3 did not run. The lines are correct, and each fix is
      in a test helper that took a line for something else.

      - The line under a tab row is one or two 1 px rects, so the test of a
        nested split (`PaneToWidgetTest.jl:204`) found 7 horizontal 1 px rects,
        not the 1 splitter. The test takes a 1 px rect for a splitter only
        where the pointer at its middle is the double arrow of a grab, and the
        four checks of the places of the two splitters pass (72543d915).
      - The line under the menu bar of a shell is a rect after the background,
        so `AnchorPointTest.jl:116` went to the line by the index 2 and read a
        field that a rect does not have. The test takes the first canvas of
        the shell, which is the menu bar (c40b0d201).
      - The eight functions of the two lists, in one process: before the
        fixes 243 Pass, 16 Fail, 3 Error, 7 Broken; after them 264 Pass,
        0 Fail, 0 Error, 7 Broken (the anchor test runs 2 more checks, which
        the Error stopped). With six
        functions of the table in the same process: 664 Pass, 0 Fail,
        0 Error, 7 Broken.
- [x] 4. **A box computes its shape once, and its IO map carries it.** The
      screen must not change.
      - A type for the shape of a box holds the outer box, the margin, the
        border, the padding and the content of a widget. One function computes
        it from the projection, the document and a given space, which is 0 in
        this step. It takes the place of `_get_box_insets`, `_content_offset`
        and `_inset_total` (`WidgetToGraphics.jl:140-155`) at each of their
        uses: about 175 in `WidgetToGraphics.jl` and 14 in other files.
      - Each widget printer puts the shape into its IO map. A printer that
        returns a `SimpleIoMap` or a `ChildrenIoMap` now returns an IO map of
        the widget slice that holds the shape.
      - Each reader, hit test and ring of a selection reads the shape from the
        IO map.
      - `TypeDispatching.jl` and `PredicateDispatching.jl` do not change. No
        printer makes a copy of its projection, so the projection that a
        dispatch gives a reader is the projection of the IO map.
      Check: `tool/widget-images.jl` finds every image the same; the platform
      suite, part by part, and `test_dataframes()` give the counts of the
      baseline.

      Done. Facts:

      - The shape is `BoxGeometry` (`WidgetToGraphics.jl`, the section of the
        box). It has four fields from the outside in: `space`, `margin`,
        `border` and `padding`, each `(left, top, right, bottom)` of `Int`.
        `_compute_box_geometry(p, w, space; variant)` computes it.
        `_make_box_geometry_cell(p, w, space; variant)` keeps it in a cell,
        which each computation of the print reads, so a change of an inset of
        the theme or of the document still reaches the screen. In this step
        every printer gives the space `inset_default`.
      - The functions on the shape: `_get_sides_outside(box, part)` gives the
        sides outside `:border`, `:padding` or `:content`;
        `_get_content_offset(box)`, `_get_inset_total(box)` and
        `_get_border_rect(box, width, height)` use it. `_push_box_parts!` and
        `_push_following_box_bands!` take the shape and draw inside its space.
        `_NO_BOX_GEOMETRY` is the shape of a widget that draws no box: a widget
        that is not visible, an icon, a highlight, and the rows of a list or a
        tree that prints as its rows.
      - The IO maps: `WidgetBoxIoMap` for a widget with no child and
        `WidgetChildrenIoMap` for a container. Each has the fields of
        `SimpleIoMap` or of `ChildrenIoMap`, and the field `box`. Each IO map
        of a widget of its own (`WidgetValueIoMap`, `WidgetTableListIoMap`,
        `WidgetRowsPaneIoMap` and the `Widget…ToGraphicsCanvasIoMap`s) also has
        the field `box`. `_get_box_geometry(iomap)` reads the shape. These
        names are not exported. `WidgetChildrenIoMap` has a method of
        `get_child_iomaps` and of `find_first_baseline`, as `ChildrenIoMap`
        has, and `WidgetBoxIoMap` gives `find_first_baseline` to its
        projection, as `SimpleIoMap` does.
      - The commits: 4a (d819f1518) the type, the functions, the IO maps and the
        widgets with no child; 4b (c1164ba61) every container, so no widget
        printer returns a `ChildrenIoMap`; 4c (3c9548773) the list, the tree,
        the table and `WidgetTableParts.jl`, and the delete of `_get_box_insets`,
        `_content_offset`, `_inset_total` and `_get_rows_content_offset`.
      - A widget that is not visible returns the IO map of its kind with
        `_NO_BOX_GEOMETRY`, so its readers (`iomap::WidgetBoxIoMap`) are the
        readers that it had for `SimpleIoMap`.
      - A printer that read the insets once at the print reads the cell once
        there (the scroll pane, the transform pane, the tabbed pane, the tree,
        the table, the rows pane, the slider, the card, the accordion). A reader
        reads the cell when it reads. The insertion and the dialog print with
        no cell, so their IO map holds the shape as a value.
      - The variant of a menu item and of a menu is read inside the cell of the
        shape. The reader of a tabbed pane gives the shape of its IO map to
        `_tab_strip_geometry`. A badge that a tab or a row of a tree draws has
        no IO map, so its host computes its shape
        (`_compute_box_geometry(p.badge, badge, inset_default)`).
      - Two tests follow the types: `AppearanceTabTest.jl:64` finds a card by
        its `WidgetChildrenIoMap`, and `WidgetRowsScrollTest.jl:65` reads the
        shape from the IO map.
      - Images: 44 of 44 the same after 4a, after 4b and after 4c.
      - Tests of each group, in one process: 4a 31 functions, 1881 Pass,
        1 Fail; 4b 37 functions, 1819 Pass, 2 Fail; 4c 33 functions, 1994 Pass,
        1 Fail. The failures are in the code of step 3 too, with this step
        taken out, and not in the baseline: `test_widget_round_trip` (the four
        cells of the last row of `widget_table_frozen` map back to the
        horizontal bar) and `test_scroll_pane_hover`
        (`ScrollPaneHoverTest.jl:124`: a press gives `items[39]`, not
        `items[40]`). Step 4 does not fix them. The causes and the fixes are
        under steps 2 and 3.
      - The platform suite, part by part: 176638 Pass, 19 Fail, 3 Error,
        7 Broken (baseline: 175016 Pass, 3 Fail, 7 Broken). The three Fail of
        the baseline are the same. The other 16 Fail and 3 Error are in the code
        of step 3 too, with this step taken out, in the same counts (one process
        for the eight functions): `test_split_pane_drag` 8 Fail and 2 Error (a
        press at x 300 starts no drag), `test_pane_to_widget` 3 (the line under
        each tab row is a 1 px rect too, so the test finds 7 and not 1),
        `test_anchor_point` 1 Error, `test_find_bar_view_to_widget` 1,
        `test_part_pointer_shape` 1, `test_settings_tab` 1,
        `test_scroll_pane_hover` 1 and `test_widget_round_trip` 1. Steps 1 to 3
        ran none of these functions. `test_platform_examples` has 159150 Pass,
        570 more than the code of step 3 (158580): the walk gives one test to each
        cell that it forces, and each widget IO map holds the cell of its shape.
        `test_dataframes`: 603 Pass, as the baseline.
      - The recorded calls: after this step 89 of the 838 recorded calls of
        `ProjecturedSDL` and 84 of the 768 of `ProjecturedDataFrames` do not
        resolve, more than the share of 10 %, so their precompilation warns
        that it failed and compiles more while it runs. Some of them name a
        signature that this step changed (a widget IO map with a new field, a
        reader of a `SimpleIoMap` or a `ChildrenIoMap` of a widget, a helper
        that takes the shape). The lists are recorded again after step 8.
- [x] 5. **The text printer takes the line spacing from the context.**
      `TextToGraphics` makes no copy of itself: it reads `:line_spacing` from
      the context where it lays out the lines, and its IO map carries the line
      positions and the line height that its readers (`char_to_coord` and the
      others) need. The screen must not change. Check: `tool/widget-images.jl`
      finds every image the same, among them the text field
      (`WidgetToGraphics.jl:1923`) and the cells of a table (`:11410`), which
      set the property; `test_syntax_to_text()` and the platform suite, part by
      part, give the counts of the baseline.

      - [x] 5a. The text printer makes no copy of itself.
      - [x] 5b. No widget printer makes a projection. This part runs after
        step 6, because both change `WidgetToGraphics.jl`.

      5a is done in `c5e96d517`. The facts:
      - `_get_line_spacing(p, ctx)` gives the spacing of one print: the
        `:line_spacing` property of the context where one is set, else
        `p.line_spacing`. `print_document` calls it once, and no other place
        reads `p.line_spacing`. `_with_line_spacing` is deleted.
      - The layout takes the spacing as an argument: `_layout_group`,
        `_layout_overlay`, `_print_listnode`, `_layout_list_line` and
        `_build_line_node` take `spacing` after `p`, and `_GroupLayout` holds it
        in a `const` field that `_close_line!` reads.
      - `TextToGraphicsIoMap` holds `p` itself and a new field `line_spacing`,
        the spacing of the print. The places and the heights of the lines are
        already in `char_to_coord` and in the output, so the IO map carries no
        other new field. One reader lays a line out again,
        `_map_list_lines_forward` for a line of a lazy list, and it reads
        `iomap.line_spacing`. The caret readers, the keys Home, End, Up and
        Down, and `map_reference_forward` read the places of the lines from
        `char_to_coord` or the output.
      - The 44 widget images are the same, and 19 more images of code, prose,
        markdown and the text spacing examples are the same byte for byte. The
        lazy examples are not drawn: the image writer overflows its stack on
        an endless list; `test_text_to_graphics` covers that path.
      - 14 text test functions, among them `test_syntax_to_text`: 1259 Pass,
        as before. The platform suite on the code of step 4 with this step:
        176810 Pass, 19 Fail, 3 Error, 7 Broken, the known failures of that
        code. The 172 more Pass are in `test_platform_examples`, which gives a
        test to each cell it forces, and each text IO map holds one more cell.
      - Found in 5a: two widget printers make a new `TextToGraphics` on each
        print, `_print_plain_text_view` (with a `WordWrapping` chain for a
        field that wraps) and the selector of a tabbed pane. They are new
        projections and not copies, but a projection is fixed configuration.
        `_print_plain_text_view` also reads `w.line_spacing` outside a cell and
        drops it when the context is `nothing`.

      5b, as the user accepted it on 2026-11-04 (the user asked for it in
      this step and not in a plan of its own):
      - A widget printer prints its text view through `recursion`, as it
        prints a document in its content now. No widget printer builds a
        projection.
      - The offer decides the wrap. `WordWrapping` wraps a line only where
        the context gives a maximum width, so a field that wraps offers its
        text a bounded width, and a field that does not wrap offers a free
        width. One text printer, `WordWrapping` and then `TextToGraphics`,
        serves both, with no flag and no new type of view.
      - The dispatch of `WidgetToGraphics(...)` holds that text printer, as
        it holds the printers of the layouts: widgets embed text, and in the
        Explorer the recursion is the widget dispatch alone. The printer uses
        the default text theme, as the fields do now.
        **Replaced on 2026-11-05, see below.**
      - `_print_plain_text_view` reads `w.line_spacing` in its computation
        and keeps it when the context is `nothing`.
      - The risk: a composition that puts a text printer of its own before the
        widget dispatch draws the fields with that printer, for example in the
        colors of the text theme of an editor. If the screen changes, the work
        stops, and the user decides.

      The first try of 5b stopped at this risk. It put the rule
      `TextBlock => ChainingProjection(WordWrapping, TextToGraphics)` at the
      end of the widget dispatch, and 8 of 179 images changed. In the natural
      view (`NaturalProjection.jl:166`) the widget dispatch comes before
      `TextDocument => prose_chain`, so the new rule drew the prose of the
      documents at single spacing and not at the prose spacing 1.3. Each line
      of `conversation_widget` was about 2 px shorter (407 px to 392 px), and
      the labels of `graph_services` changed size, so its force layout moved.
      The text of a widget and the text of a document are both a `TextBlock`,
      and a table of rules picks by type, so no order of the rules serves
      both. The user rejected a type of its own for the text of a widget, and
      accepted this design on 2026-11-05. It replaces the rule in the widget
      dispatch, and the one text printer for all tables:
      - The dispatch of `WidgetToGraphics(...)` has no rule for `TextBlock`.
      - Each table of rules that draws a widget with text has one rule for
        `TextBlock`. It draws the text documents of that table and the text
        of its widgets. The table chooses if the rule wraps (`WordWrapping`
        and then `TextToGraphics`) or not (`TextToGraphics` alone). A wrap is
        not mandatory.
      - A widget gives its text view all of its own look. The spans carry the
        font and the color, as now. The offer always carries the line
        spacing: `w.line_spacing`, else single spacing, so the spacing of the
        printer of the table never applies to a widget. The offer carries the
        wrap: `wrap = false` offers a free width, so the text never wraps;
        `wrap = true` offers the width of the box, so the text wraps where the
        rule of the table wraps and stays one line where it does not. The user
        accepted this consequence.
      - The caret and the selection band of a widget text take the text theme
        of the printer of the table. Before, they took the default theme,
        which a zoom does not scale.
      - Only the prose box of an outline row (`OutlineRow.jl:37`) sets
        `wrap = true`. The workflow views and the research views show it, so
        their tables get a rule that wraps.
      Check: `tool/widget-images.jl` finds every image the same; a test finds
      that no printer in `source/platform/widget/` calls the constructor of a
      projection inside a print; `test_widget_text_fit`, the text field tests
      and the platform suite, part by part, give the counts before 5b.

      5b is done in `2624e869e` (code) and `73cbcafbc` (tests). The facts:
      - `_print_plain_text_view` and the view of a tab name print through
        `print_child(recursion, view, offer)`. No printer in
        `source/platform/widget/` builds a projection in a print.
        `_make_text_view_offer(w, ctx; wrap)` makes the offer: it always sets
        `:line_spacing` (`w.line_spacing`, else `SingleSpacing()`, also when
        the context is `nothing`, which becomes a `PrinterContext()`); a field
        with `wrap = false`, and the tab name, offer a free width
        (`with_free_axis(ctx, :x; space = ctx.space)`, so the space of the
        offer stays); a field with `wrap = true` passes the bounded width of
        its box on. `w.line_spacing` is read in the computation of the
        reconciled cell.
      - The dispatch of `WidgetToGraphics(...)` has no rule for `TextBlock`.
        `WidgetToGraphics(...; text)` ends the dispatch with `TextBlock => text`
        for a projection that stands alone as a table; it is `nothing` by
        default, so a table that splices `.dispatch` adds its own rule.
      - `_compute_soft_breaks` returns no break at a free width
        (`wrap_w >= _NO_WRAP_WIDTH`) before it measures a word. The test
        uses a measure that fails when it is asked, in `test_word_wrapping`.
      - The rule of each table, and why (the text theme is the scaled
        `TextTheme` of the appearance):
        - `NaturalToGraphics`: keeps `TextDocument => prose_chain`, which wraps
          (when `wrap`) and takes the text theme. Nothing stands before it for
          a `TextBlock`. The workflow and research views, and the outline row
          that sets `wrap = true`, draw through this table or the research
          one, so their text wraps. The Explorer window opens a workflow or a
          research document in a tab through this table, and through the
          application table below.
        - `make_application_content_projections`: keeps
          `TextDocument => text_to_graphics`, which wraps. Its two bare widget
          renderers (the explorer and the workspace) get
          `text = TextToGraphics(measure, text_theme)`, no wrap: they show the
          fields of the file tree, which never set `wrap`.
        - the workspace rows of `FileSystemToSyntax.jl`, the system process
          page and the document tree: `text = TextToGraphics(measure, text
          theme)`, no wrap, the same reason.
        - `make_tabs_projection` and `make_window_shell_projection`:
          `TextBlock => TextToGraphics(measure, text theme)` before
          `Any => NestingProjection(projection)`, no wrap. Without the rule
          the text of a widget of the tab strip or of a bar would go to the
          projection of the content. `make_opened_window_projections` has
          `Document => NaturalToGraphics`, which takes a `TextBlock`; kept.
        - the tables of the task views: one rule `texts` before the
          documents, no wrap.
        - `make_research_map_projection`: `WordWrapping` and then
          `TextToGraphics`, because the rows of a map show the outline box.
        - the examples and the tests that splice the widget dispatch add
          `TextBlock => TextToGraphics(measure)` or pass `text`.
      - The slices `tree`, `systemprocess`, `task` and `pane` use `TextModule`
        now, and `PLATFORM_SLICE_EDGES` lists `text` for each.
      - The static test is `test_widget_printer_projection` in
        `test/platform/widget/WidgetPrinterProjectionTest.jl`. It walks the
        syntax tree of each file of the slice and reports a call of the
        constructor of a `Projection` type in a function. A constructor of a
        projection type may build its own type. The allowed functions, each
        a factory that runs once when a renderer is built: `WidgetToGraphics`,
        `make_graphics_projection` (the method for a document type),
        `make_context_menu_window_projection`,
        `make_object_field_widget_dispatch` and `_nest_value_widget`. It found
        no print that builds a projection after the two targets.
      - The first try (the rule in the widget dispatch) changed 8 images. This
        design changes none: the 44 widget images and the 135 images of the
        examples are the same byte for byte (my `all-images.jl` against the
        set of `9cbe98463`), and `explorer.png` and `settings.png` of the
        window (`window.jl 674`) are the same pixel for pixel.
      - Tests: the platform suite, part by part, gives 178571 Pass, 3 Fail
        (the known `CheckLayering.jl:889`, `InterfaceApiTest.jl:46` and `:49`),
        0 Error, 7 Broken; the first run of this code had 58 Error, all from
        a test table with no rule for a `TextBlock`, which nine test files now
        hold. `test_dataframes` 603 Pass, `test_research` 382 Pass;
        `test_languageserver`, `test_julia`, `test_workflow`, `test_sql`,
        `test_chart` and `test_sequencechart` pass; `test_pivot` has 335 Pass
        and 1 Error at `PivotZoneEditTest.jl:84`, the known failure of main
        (the text "Rows" is not drawn), which is not from this step.
      - Found, not changed: a `wrap = true` text in a table whose rule does not
        wrap stays one line (the user accepted it); in `make_window_shell_projection`
        and `make_tabs_projection` a `TextBlock` that is a document of the
        content now goes to the rule of the table and not to the content
        projection (no example or test image changes).
- [x] 6. **A slot gives its space once.** `tabbed_pane_padding` becomes 0.
      Add `slot_padding` (8 on each side), and set `tree_row_padding` to
      `Inset(2, 2, 8, 8)`.
      - `PrinterContext` gets the given space as a field of the offer. The
        functions that make an offer (`with_exact_size`, `with_bounded_size`,
        `with_size_range`, `with_inner_size`, `with_free_axis`) state it, and a
        context made for a child that states none has 0. `PrinterContext.jl` is
        ⬜; check `SEALING.md` again at the edit.
      - The tabbed pane offers `slot_padding` to its page
        (`WidgetToGraphics.jl:5113`), and the split pane to each slot
        (`:4299-4301`). Both offer 0 to all else that they print, such as the
        names of the tabs and the bars. The shell offers 0.
      - Each box printer puts the given space into its shape (step 4), and
        offers 0 to what it holds. The authored size of a box does not hold the
        space (`_resolve_size`), so a field of an authored width keeps it.
      - A layout passes the space on by side: a column gives the left and the
        right space to each child, the top to its first child and the bottom to
        its last; a row does the same across; a grid gives each side to the
        cells at that side (`LayoutToGraphics.jl`, the vertical layout at
        `:1160`, the horizontal at `:917`, the grid at `:1594`; `LayoutList.jl:141`).
        A layout that gives each child its own offer still prints a child once
        when nothing changed.
      - The scroll pane adds the given space to its padding (`:6025`), so it
        cuts its content inside the space on every side and keeps its bar at
        the outer edge. The color of its content fills the band.
      - `WidgetTree` and `WidgetList` put the top and the bottom space into
        their shape, and their own scroll pane cuts inside it. Their rows take
        the left and the right space as side padding, and `tree_row_padding`
        where it is 0: the place of the content of a row, its chevron box and
        its natural width move with it (list: `:10330`, `:10356`; tree:
        `:12612-12624`, `:12665`, `:12788`).
      - A printer of a domain that draws takes the space as a box:
        `TextToGraphics` and each printer to graphics of a domain. A printer
        that prints graphics of its own with the context it got offers them 0,
        such as `NavigatorToWidget.jl:87`.
      - A fixed height that holds a box in a slot grows by the space: the row of
        the options of an Assistant (`AssistantToWidget.jl`, about `:107`) and
        the estimate of the shown rows of a data frame
        (`DataFrameViewToWidget.jl:95`).
      - The filter bar of the Explorer (`ExplorerToWidget.jl:81`) has no
        padding of its own, and stands `item_gap` above the tree (`:90`).
      - `SystemProcessToWidget.jl:38` drops the `container_padding` around its
        root.
      Check: a new test prints each kind of widget, layout and domain canvas
      as the page of a tab and as the body of a card: in the tab it finds 8 px
      at each edge, and in the card no space added to the padding of the card;
      a test finds that each printer of the widget dispatch takes the space,
      or is a frame or a layout that passes it; `test_explorer()`,
      `test_widget_tree()`, `test_dataframes()` and `test_platform_layering()`
      pass; a pixel scan of an image of the window finds the inner divider of
      the Explorer from the line under the tab row to the line above the status
      bar, the tree and the page 8 px from every edge, the band of the selected
      row of the tree from the window edge to the inner divider with its first
      letter 8 px from the edge, and a scrolled settings page cut 8 px inside
      every edge with its bar at the edge.

      Done in 4eacd3372 (6a), 686ad179e (6b), cd72e20cc (6c), d20ed2be8 (6d)
      and e9b7e0638 (6e). The facts:

      - The offer: `PrinterContext` has the field `space::NTuple{4,Int}`,
        `(left, top, right, bottom)`, next to the ranges. The ranges hold the
        space: an exact width is the width of the child with its space.
        `with_exact_size`, `with_bounded_size`, `with_size_range`,
        `with_inner_size` and `with_free_axis` take the keyword `space`, and
        give 0 where a caller gives none. `make_child_context`,
        `make_element_context`, `with_clock` and `with_property` keep the space,
        as they keep the ranges, so a wrapper that passes its offer on (a
        `LayoutConstraint`, a fault barrier, a decorator) and each stage of a
        chain see the same offer. A root context has 0.
      - The widget box: `_compute_box_geometry(p, w, space)` takes the tuple, and
        each printer gives `_get_given_space(ctx)`. A box offers 0: its content
        context comes from `with_inner_size`, and a part that it prints with
        its own range gets `_with_no_space(ctx)` (the value slot, the name view
        of a tab, the overlay of the shell). `_resolve_size` and
        `_resolve_overlay` add the space to an authored size; a printer that
        adds its insets to an authored inner extent (the text field, the
        separator, the progress bar, the slider, the textarea, the card, the
        accordion, the skeleton) takes the space out (`_get_space_total`). The
        focus ring, the pointer shapes, the clear surface and the light of an
        item stand on the margin box (`_get_part_rect(box, :margin, w, h)`),
        inside the space. An icon and a highlight have a shape that holds only
        the space. A composite is a box: it takes the space, and a clear rect
        gives it its extent at the right and at the bottom.
      - The frame takes no space (`_NO_SPACE`): the shell, the split pane, the
        tabbed pane, and the dialog, which fills its window. The tabbed pane
        offers `slot_padding` to its page and the split pane to each slot, with
        the new style field `slot_padding` of each projection.
      - The scroll pane takes the space into its padding
        (`_compute_scroll_pane_geometry`): it cuts its content inside the space
        and its bars stay at the inner edge of its border. The rect of its
        content color fills the band. The transform pane takes the space as a
        box, outside its border.
      - The tree and the list: `_make_rows_box_geometry_cell` puts the top and
        the bottom space into the shape. `_get_row_side_padding` gives the side
        padding of the rows: the side space, else the side of the row padding
        of the projection (`tree_row_padding` for a tree, `control_padding` for
        a list). The x of each `WTreeRow`, its chevron box and the natural width
        move with it. A widget that scrolls its rows itself carries the side
        space to the print of its rows in the property `:row_side_space`, next
        to `:rows_of`.
      - The layouts: `_get_child_space` and `_with_child_space` in
        `LayoutToGraphics.jl`. A column and a row give the space by side, a grid
        gives each side to the cells at that side, a stack gives the whole space
        to each child, a flow and a constraint layout take it around themselves
        (which child stands at a side depends on the extents), an anchored layout
        gives it to its content and none to its children. A layout of a list
        (`LayoutList.jl`) gives the space on its axis to the child whose
        document node has no neighbour on that side, and reads a neighbour only
        for a side that has space.
      - The domains: `TextToGraphics` takes the space as a box; the stack of
        lines, the overlays and the regions stand inside it, the segment
        coordinates stay in the frame of the stack, and `TextToGraphicsIoMap`
        has the field `space`, which the reader of a point takes off.
        `WordWrapping` breaks the lines at the edge less the side space, because
        the text printer of the chain takes it. A fault mark stands inside the
        left and the top space. `NavigatorToWidget` offers its address no space.
      - The theme: `tabbed_pane_padding` 0, `slot_padding` `Inset(8, 8, 8, 8)`,
        `tree_row_padding` `Inset(2, 2, 8, 8)`. The row of the options of an
        Assistant is `option_bar_height` and the top and the bottom of
        `slot_padding` (`AssistantToWidgetSplitPane(theme; slot_padding)`). A
        data frame counts its shown rows from the height less the space at its
        top and its bottom. The Explorer gives its parts `item_gap`.
        `SystemProcessToWidget` has no `padding`.
      - Places that pass a received context unchanged to a child, and what each
        does now: the chain stages, the fault barrier, the recursion, the
        decorators (tooltip, dragging, arranging, focus cycling, gesture log,
        overlays, window managing) and `LayoutConstraint` keep the space, which
        is right for a pass-through. A printer that makes widgets or syntax and
        no graphics (`ConversationToWidget`, `UrlViewToWidget`,
        `ObjectFieldToWidget`, `PaneToWidget`) passes it, and no graphics
        printer reads it there. `_print_value_slot`, `_print_tab_name_view`, the
        overlay of the shell, the anchored children and the address of the
        navigator now offer 0.
      - A cache by the offer: the layout of a list keeps the print of a child by
        the child document (`take_kept_list_print!`); `_LayoutListChild` holds
        the space of its print, and a kept print serves only for the same space.
        No other code compares or hashes a context.
      - Images: 44 of 44 the same after 6a, 6b and 6c. After 6d, 5 change:
        `widget`, `widget_offered`, `widget_split_pane`, `widget_tabbed_pane`
        (the strip at the edge, the page 8 px inside) and `widget_tree` (8 px at
        the sides of the rows).
      - The window (1000 x 640, the Explorer and the Settings tab), before
        `images/step6-window-before`, after `images/step6-window-after`: the
        inner divider is at x 169 from y 86, the line under the tab row, to y
        616, the line above the status bar (before: x 173, y 94 to 607). The
        filter field starts at x 8 and 8 px under the tab row; the rows of the
        tree start their content at x 8. The band of the selected row runs from
        x 0 (under the 2 px mark of the current row) to x 168, next to the
        divider (before: x 10 to 172); its chevron glyph stands at x 11 and its
        label at x 47 at depth 0. The scrolled settings page draws from y 95 to
        607 and from x 8, 8 px inside the page (y 87 to 615, x 0 to 679), and
        its bar is at x 670 to 679, at the right edge of the page.
      - Tests changed by 6d, each to the new place from the theme:
        `WidgetTreeTest.jl` (the chevron box of a row starts at the left of
        `tree_row_padding`), `WidgetRowsScrollTest.jl` (the press on a chevron
        moves by the same side padding), `ExplorerTest.jl` (the back button of
        the page stands the divider, `slot_padding` and the padding of a toolbar
        item past the divider, in place of "within 12 px"),
        `MouseTargetMoveTest.jl` (the move onto the button in the left slot of
        a split pane is the slot padding inside the slot) and
        `WidgetPointTest.jl` (the points that map into the two slots of a split
        pane are the slot padding inside each slot). New: `SlotSpaceTest.jl`,
        `test_slot_space`: each type of the widget dispatch is a sample of a
        box, of the frame or of the layout dispatch; each box printed with a
        space holds it and is larger by it; the frame takes none; a card and a
        scroll pane offer 0; a tab page and a split slot give `slot_padding`;
        a column, a row, a grid, a stack, a flow and a `LayoutConstraint` pass
        it as above; the text takes it and its reader reads it.
      - A fix to 6b in 6d: a composite counts the space at its right and at its
        bottom in its extent with a clear rect, because no child and no part of
        its box lies there (the test found it).
      - Counts: tests of 6b, 30 functions in one process, 2069 Pass; of 6c, 15
        functions, 1963 Pass. The platform suite, part by part, after 6d with
        the tests of 6e: 177865 Pass, 7 Fail, 0 Error, 7 Broken (the branch
        before: 176836 Pass, 3 Fail, 7 Broken); the 3 Fail of the baseline are
        the same, and the other 4 are the assertions of
        `MouseTargetMoveTest.jl` and `WidgetPointTest.jl` that 6e moves, which
        pass after it (85 and 19 Pass). `test_platform_examples` has 160247
        Pass, 925 more: the walk tests each cell that it forces, and a box that
        is given a space makes more cells. `test_dataframes` 603 Pass, as the
        baseline. `test_printer_context_range` 67 Pass.
      - Found and not changed: the other printers to graphics of the domains
        (chart, sequence chart, graph, math, roster, chips, text gutter, the
        cache of a canvas as an image) take no space: they draw inside a widget
        box in every place that the window shows them. A lazy list of text lines
        and the lazy grids (`GridList.jl`, `GridColumnList.jl`) take no space.
        The ring around a child selected as a whole holds the space of the
        child. omnet-julia builds `AssistantToWidgetSplitPane(conversation_theme)`
        with the default `slot_padding`, not the scaled one.
- [ ] 7. **Every gap of a widget layout has a role.**
      - These fields of other themes read the role of the widget theme, and go
        away:
        - `ConversationTheme`: `part_gap`, `turn_gap` and `section_gap` →
          `section_gap`; `role_gap` → `label_gap`; `option_gap` →
          `button_gap`; `card_gap` → 0, because the transcript and the
          composer are slots of a split.
        - `TaskTheme`: `stack_gap` → `section_gap`; `inline_gap` → `label_gap`.
        - `OutlineTheme`: `section_gap` → `section_gap`; `row_padding` →
          `tree_row_padding`; `meta_gap` → `item_gap`.
        - `TooltipTheme`: `padding` → `control_padding`; `section_gap` and
          `gap` → `title_gap`; `fact_gap` and `head_gap` → `form_column_gap`;
          `fact_row_gap` → `line_gap`; `key_padding` → `compact_padding`;
          `key_gap` → `item_gap`.
        - `FaultTheme` and `GestureLogTheme` `panel_padding`, and
          `GestureHelpTheme` `palette_padding` → `container_padding`.
        - `McpLogTheme` `gap`, `TerminalTheme` `gap` and
          `FrameStatisticsTheme` `gap` → `form_row_gap`.
        - `DataFrameTheme` `expression_gap` → `item_gap`.
      - A field of a job that only its theme has stays.
      - Add `button_gap` (8). Each row of push buttons takes it, among them the
        literal `gap = 12` of `FilePageToWidget.jl:74` and the row of
        `AssistantListToWidget.jl:122`, which has no gap now.
      - Each other literal gap or padding of a widget layout in
        `source/platform` reads a role.
      Check: a new static check in the platform suite, which parses
      `source/platform` as the layering guard does, finds no number literal
      other than 0 as `gap`, `horizontal_gap`, `vertical_gap`, `padding` or
      `margin` of a layout or a widget; `test_platform()` passes with the
      counts of the baseline.
- [ ] 8. **The splitter shows a band.** The split pane draws a band of
      `splitter_band_width` (a new field, 4) in `ring` on the middle of a
      divider, while the pointer is on its grab area for 0.3 s, and at once
      while it is dragged. The band fades in 0.1 s. The split pane reads the
      clock of its context only during the delay and the fade, as the scroll
      bar does, so a split at rest draws no frame. Check: a test with a clock
      that the test writes finds no band before 0.3 s on the grab area, the
      band after it, the band at once during a drag, and no band after the
      release and the fade; the band shows in the running editor.

      Step 8 is the last code step in this repository, so after it, record the
      lists of compiled calls again with `record_repository_calls!()`.
      Steps 4 to 8 change the signatures of many widget functions, and after
      step 4, 89 of the 838 calls of `ProjecturedSDL` and 84 of the 768
      calls of `ProjecturedDataFrames` no longer resolve. That is more than
      the stale share of 10 %, so each package warns "precompilation failed"
      and compiles more while it runs. Also record each list of an
      application, `precompile/<application>.txt`, that names a changed
      function. Check: a load of each package writes no warning about calls
      that no longer resolve.
- [ ] 9. **The pages of omnet-julia follow the rules.** This step starts after
      steps 1 to 8 are on `main` of projectured-julia.
      - Each page builder takes the widget theme of its builder, scaled, in
        place of `get_theme_defaults(WidgetTheme)`.
      - `WorkbenchRender.jl:161-162` no longer sets `control_padding` and
        `item_gap`.
      - A page needs no padding of its own, because its slot gives it (step 6).
        A page that sets a padding at its root drops it.
      - Inside a card, lines of facts take `line_gap`, rows of a form take
        `form_row_gap`, and sections take `section_gap`.
      - The gaps of the legacy `SimulationTheme` read the roles:
        `stack_gap` → `section_gap`, `inline_gap` → `label_gap`, `label_gap`
        → `form_column_gap`.
      Check: the presentation tests of omnet-julia pass; `OmnetIdeApp`
      compiles ahead; a pixel scan of an image of the IDE finds each details
      page 8 px from the edges of its tab.
- [ ] 10. **Write the spacing documentation.** The guides say what the code
      does after steps 1 to 9. They follow
      [writing-rules.md](../../documentation/rule/writing-rules.md), and they
      name no artifact and no private repository.
      - Write `documentation/rule/spacing-rules.md`, kind rule, standing on
        [layout-rules.md](../../documentation/rule/layout-rules.md). It
        answers "how much space goes where, and who gives it?" Its parts come
        from [spacing-starts-from-first-principles.md](spacing-starts-from-first-principles.md):
        1. The principles in terms of what a person sees: what touches what,
           what never touches what, what is closer and what is further, and
           the five rules over all of them (once, symmetry, one content edge,
           one value for each relation, the least space that works).
        2. The window with no space at all, and why each space that the
           window has needs a reason in one of the principles.
        3. The roles: each theme field, its job, its value, and the principle
           that asks for it. A table, as in the decisions of this plan.
        4. Who gives a space: the padding of a box inside its edge, the gap of
           a layout between its children, and the space at the edge of a slot,
           given once through the printer context. It says how a split, a
           layout, a scroll pane, a tree and a list pass or take that space,
           and why the printer context decides it and not the path upward or
           the child.
        5. What other tools do, in a short table, with the sources.
        6. How to space a new widget, a new layout or a new page: which role to
           read, and what a builder must not do: a number as a gap or a
           padding, or a padding of its own at the root of a page. It names
           the static check of step 7.
      - Add its row to `documentation/README.md`, and a line to
        [layout-rules.md](../../documentation/rule/layout-rules.md) that
        points to it for the space. Its examples that show a number as a gap
        read a role.
      - Change [widget.md](../../documentation/package/platform/widget/widget.md):
        the list of the spacing fields of the theme; the shape of a box that
        its IO map carries for its readers; the space that a slot gives once,
        as a part of the offer; the scroll bar at the outer edge and the cut inside the
        space; the side space in the rows of a tree and a list; and the
        splitter band.
      - Change [tooltip.md](../../documentation/package/platform/tooltip/tooltip.md)
        for the fields of `TooltipTheme` that read a role after step 7.
      - Add to [new-domain-guide.md](../../documentation/guide/new-domain-guide.md)
        that the printer of a domain canvas takes the space of its slot into its shape, as
        steps 4 and 6 do it.
      - Add to [architecture-rules.md](../../documentation/rule/architecture-rules.md)
        that a printer never makes a copy of its projection for a value of one
        print: the value comes in through the context, and what a reader needs
        of it goes out through the IO map.
      Check: `test_documentation()` passes, but for the 7 failures of the
      baseline (private names in `assistant.md` and `precompile.md`); a grep
      of `documentation/` finds no field name that step 1, 2 or 7 removes.

## Not in this plan

- The spacing inside the drawings of the domains: chart, graph, sequence
  chart, markdown and RST blocks, research map.
- A density setting, such as compact and comfortable.
- A migration of a saved appearance file: a saved
  `~/.config/projectured/appearance.toml` holds every field, so it keeps the
  old values until "Reset all".
