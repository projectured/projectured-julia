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
  that it gives, `slot_padding`, into the printer context of what it holds.
  The value is an `Inset`, so it can differ by side. It uses the existing
  `with_property` and `get_property`, as `:line_spacing` does: a new key, not
  a new mechanism.
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

- [ ] 1. **Give each job of `item_gap` its own field.** The screen must not
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
- [ ] 2. **Set the chosen values** of `control_padding`, `container_padding`,
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
- [ ] 3. **Draw the four lines.** The shell draws a 1 px line of `border`
      under the menu bar, under the toolbar and above the status bar, and
      `band_gap` becomes 0. Each line takes 1 px of height, as a splitter takes
      its width. The tab group draws a 1 px line under its tab row, with a gap
      under the selected tab. Check: `test_widget_shell_layout()`,
      `test_widget_shell_pointer()`, `test_window_shell()` and
      `test_widget_tab_strip()` pass, with the shell test changed for the
      lines; a pixel scan of an image of the window finds the four lines, the
      gap under each selected tab, and the outer divider from the line under
      the toolbar to the line above the status bar.
- [ ] 4. **A slot gives its space once.** `tabbed_pane_padding` becomes 0.
      Add `slot_padding` (8 on each side), and set `tree_row_padding` to
      `Inset(2, 2, 8, 8)`.
      - The tabbed pane and the split pane put `:space_to_give` =
        `slot_padding` into the context of each slot (`with_property`).
      - One helper takes the space for a box: it reads `:space_to_give`, gives
        it as the outer inset of the box, lowers the size that the box is
        offered by it, and gives the box a context with `Inset(0, 0, 0, 0)` for
        what it holds. Each printer of a box with an edge or of a widget that
        holds nothing calls it at its start: the widget printers and the
        printers of the domains that draw a canvas. The split pane, the
        tabbed pane and the shell do not.
      - A layout printer passes the space on by side: a column gives the
        left and the right space to each child, the top to its first child and
        the bottom to its last; a row does the same across; a grid gives each
        side to the cells at that side. A layout that gives each child its own
        context must still print a child once when nothing changed.
      - The scroll pane gives the space at its view: it cuts its content at the
        inset on every side, and keeps its bar at its outer edge.
      - `WidgetTree` and `WidgetList` take the top and the bottom space around
        themselves, and their own scroll pane cuts inside it. Their rows take
        the left and the right space as side padding, and `tree_row_padding`
        where it is 0.
      - The filter bar of the Explorer (`ExplorerToWidget.jl:81`) has no
        padding of its own, and stands `item_gap` above the tree (`:90`).
      - `SystemProcessToWidget.jl:38` drops the `container_padding` around its
        root.
      Check: a new test prints each kind of widget, layout and domain canvas
      as the page of a tab and as the body of a card: in the tab it finds 8 px
      at each edge, and in the card no space added to the padding of the card;
      `test_explorer()`, `test_widget_tree()`, `test_dataframes()` and
      `test_platform_layering()` pass; a pixel scan of an image of the window
      finds the inner divider of the Explorer from the line under the tab row
      to the line above the status bar, the tree and the page 8 px from every
      edge, the band of the selected row of the tree from the window edge to
      the inner divider with its first letter 8 px from the edge, and a
      scrolled settings page cut 8 px inside every edge with its bar at the
      edge.
- [ ] 5. **Every gap of a widget layout has a role.**
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
- [ ] 6. **The splitter shows a band.** The split pane draws a band of
      `splitter_band_width` (a new field, 4) in `ring` on the middle of a
      divider, while the pointer is on its grab area for 0.3 s, and at once
      while it is dragged. The band fades in 0.1 s. The split pane reads the
      clock of its context only during the delay and the fade, as the scroll
      bar does, so a split at rest draws no frame. Check: a test with a clock
      that the test writes finds no band before 0.3 s on the grab area, the
      band after it, the band at once during a drag, and no band after the
      release and the fade; the band shows in the running editor.
- [ ] 7. **The pages of omnet-julia follow the rules.** This step starts after
      steps 1 to 6 are on `main` of projectured-julia.
      - Each page builder takes the widget theme of its builder, scaled, in
        place of `get_theme_defaults(WidgetTheme)`.
      - `WorkbenchRender.jl:161-162` no longer sets `control_padding` and
        `item_gap`.
      - A page needs no padding of its own, because its slot gives it (step 4).
        A page that sets a padding at its root drops it.
      - Inside a card, lines of facts take `line_gap`, rows of a form take
        `form_row_gap`, and sections take `section_gap`.
      - The gaps of the legacy `SimulationTheme` read the roles:
        `stack_gap` → `section_gap`, `inline_gap` → `label_gap`, `label_gap`
        → `form_column_gap`.
      Check: the presentation tests of omnet-julia pass; `OmnetIdeApp`
      compiles ahead; a pixel scan of an image of the IDE finds each details
      page 8 px from the edges of its tab.
- [ ] 8. **Write the spacing documentation.** The guides say what the code
      does after steps 1 to 7. They follow
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
           the static check of step 5.
      - Add its row to `documentation/README.md`, and a line to
        [layout-rules.md](../../documentation/rule/layout-rules.md) that
        points to it for the space. Its examples that show a number as a gap
        read a role.
      - Change [widget.md](../../documentation/package/platform/widget/widget.md):
        the list of the spacing fields of the theme; the space that a slot
        gives once; the scroll bar at the outer edge and the cut inside the
        space; the side space in the rows of a tree and a list; and the
        splitter band.
      - Change [tooltip.md](../../documentation/package/platform/tooltip/tooltip.md)
        for the fields of `TooltipTheme` that read a role after step 5.
      - Add to [new-domain-guide.md](../../documentation/guide/new-domain-guide.md)
        that the printer of a domain canvas takes the space of its slot with
        the helper of step 4.
      Check: `test_documentation()` passes; a grep of `documentation/` finds
      no field name that step 1, 2 or 5 removes.

## Not in this plan

- The spacing inside the drawings of the domains: chart, graph, sequence
  chart, markdown and RST blocks, research map.
- A density setting, such as compact and comfortable.
- A migration of a saved appearance file: a saved
  `~/.config/projectured/appearance.toml` holds every field, so it keeps the
  old values until "Reset all".
