# Spacing

> **Kind:** rule · **Status:** current · **Stands on:** [layout-rules.md](layout-rules.md)

How much space goes where in a window, and who gives it. Each space has a reason in a rule about what a person sees, a role in the widget theme names its value, and the printer context gives it once at the edge of a slot. [layout-rules.md](layout-rules.md) says how a widget gets its size, and this document says how it gets its space.

## 1. The principles

**P0. The eye sees marks only.** A mark is text, an icon, a line or a fill. Space is the distance between two marks. A box that draws nothing has no edge that a person can see, so its padding is only a part of the distance between the marks around it. Every rule below is a rule about the distance between marks.

### What touches what

- **T1.** Two areas that share a boundary meet at one line or at one change of fill. No empty band lies between them. The toolbar and the tab row, two panes of a split, the tab row and its page, and a page and the status bar all follow this rule.
- **T2.** A line runs until it meets another line or the edge of the window. A divider ends on the line under the tab row and on the line above the status bar.
- **T3.** A fill that marks an area reaches the edges of that area. The fill of the header row of a table reaches both sides of the table. A fill that is a shape of its own, such as a pill, a chip or a card, stands clearly inside its area, never 1 or 2 px short of an edge.
- **T4.** The parts of one joined control touch: the segments of a toggle group and the tabs of a tab strip.

### What never touches what

- **N1.** Text and icons never touch a line, or the edge of a fill, that is not a part of them. The text of a button does not touch its border. A label does not touch a divider. The first line of a page does not touch the edge of the window.
- **N2.** Two lines never run side by side. When the border of a box would lie on a divider or on another border, space comes between them, or one of them is not drawn.
- **N3.** Two separate things with edges of their own never touch. Two buttons, two cards and two tables keep their edges visible.

### What is closer and what is further

- **C1.** Things that belong together are closer than things that do not. The parts of one item are closer than two items of a group, and two items of a group are closer than two groups.
- **C2.** A title is closer to what it names than to what comes before it.
- **C3.** The space between two things with edges is not smaller than the space inside each of them. Otherwise two cards read as one.
- **C4.** A distance is measured between marks, so the space of an item includes the padding of its own box. Two toolbar buttons that each have 4 px of padding and stand 4 px apart have 12 px between their icons. That is more than the 6 px between an icon and its label.

### Five rules over all of them

- **R1. Once.** The space between content and one visible edge is given once. Two spaces with no mark between them add up, and the sum looks like a mistake.
- **R2. Symmetry.** The space on one side of a thing equals the space on the opposite side, unless the two sides mean different things. A divider has the same space on both sides. A view has the same space at its top and at its bottom.
- **R3. One content edge.** The first marks of a region start on one line.
- **R4. One value for one relation.** The same relation has the same distance everywhere, and the distance comes from one scale of roles (section 3).
- **R5. The least space that works.** Space costs room on the screen. Use the least space that keeps the rules above. A dense view, such as code, a tree, a table or a log, uses the smallest steps.

### What the principles leave open, and the choice

- **A view that scrolls.** Its cut edge is a visible edge, so N1 holds there at every scroll position, and R2 requires the same answer at the top and at the bottom. A scroll pane cuts its content inside the space of its slot, which is `slot_padding`, on every edge. The cost is that the view loses 16 px of height at the default value, and text disappears 8 px before the line.
- **A table in a slot.** A table keeps its border and stands `slot_padding` from the edges of its slot, so two tables in a split never touch (N3).
- **A tree and a list in a slot.** They have no border. The band of a selected row reaches the edges of its slot (T3), and the text of the row stands `slot_padding` inside the edge (N1). Two trees in a split can have bands that touch the divider from both sides, because the divider is a line.

## 2. The window with no space at all

Set every padding, margin and gap to 0, and keep the lines, the borders and the fills. Then:

- T1 to T4 hold. The areas touch, the lines run to the lines, and the fills reach their edges, because nothing adds space. The frame of the window needs no space at all.
- N1 breaks everywhere. The text of a button touches its border, the text of a cell touches the grid line, a command touches the border of its menu, and the first line of a page touches the edge of the window and the divider.
- N2 and N3 break. Two buttons of a row touch, two cards touch, and two tables in a split touch, with their borders on the divider.
- C1 and C2 break. An icon touches its label, the rows of a form touch, and groups do not separate from each other.

So each space must have a reason in an N rule or a C rule. A space that no N rule and no C rule requires is a space to remove. This is the test for every value in section 3.

| Space that the window adds | Rule that requires it | Role |
| --- | --- | --- |
| inside a control, a tab, a menu command, a cell, a row | N1 | a padding |
| inside a card, a dialog, an alert | N1 | `container_padding` |
| between the push buttons of a row, between the items of a bar, between cards | N3 | `button_gap`, `item_gap`, `section_gap` |
| between a title and its body, between the lines of facts, between the rows of a form, between an icon and its label | C1, C2 | `title_gap`, `line_gap`, `form_row_gap`, `label_gap` |
| at the edge of a slot, once | N1, N2, R1 | `slot_padding` |
| inside the cut edge of a view that scrolls | N1, R2 | the space of the slot |
| none, in the tab group, the split pane, the shell and the dialog | T1, T2 | `tabbed_pane_padding` is 0 |

## 3. The roles

A role is a field of `WidgetTheme` ([WidgetTheme.jl](../../source/platform/widget/WidgetTheme.jl)). Its kind is `Spacing`, so the spacing scale of the appearance scales it. A builder reads a role and writes no number (section 6). The values below are the defaults at scale 1, in pixels. A value of four numbers is the top, the bottom, the left and the right, in the order of `Inset`. A value of one number is the same on every side.

### Space inside an edge

| Field | Value | Job | Rule |
| --- | --- | --- | --- |
| `control_padding` | 4, 4, 8, 8 | a button, a text field, a cell of a table, a row of a list | N1 |
| `container_padding` | 8 | a card, a dialog, an alert, and an overlay panel | N1 |
| `compact_padding` | 2, 2, 6, 6 | a badge, and a key cap of a tooltip | N1 |
| `tab_padding` | 4, 4, 8, 8 | a tab of a tab strip | N1 |
| `menu_item_padding` | 4, 4, 8, 8 | a command of a menu and of a context menu | N1 |
| `menu_name_padding` | 4, 4, 6, 6 | the name of a menu on a menu bar | N1 |
| `menu_padding` | 4 | a dropdown, around its commands | N1 |
| `menu_bar_padding` | 2 | a menu bar | N1 |
| `toolbar_padding` | 4 | a toolbar | N1 |
| `toolbar_item_padding` | 4 | a button of a toolbar | N1, C4 |
| `status_bar_padding` | 4, 4, 8, 8 | a status bar | N1 |
| `band_padding` | 4, 4, 8, 8 | the band of a file page | N1 |
| `tree_row_padding` | 2, 2, 8, 8 | a row of a tree | N1 |
| `toggle_group_padding` | 2 | a toggle group, around its toggles | N1 |
| `slot_padding` | 8 on each side | what a slot of the frame gives to what it holds, once (section 4) | N1, N2, R1 |
| `tabbed_pane_padding` | 0 | the edge of a tab group around its strip and its page | T1, T2 |

### Space between things

| Field | Value | Job | Rule |
| --- | --- | --- | --- |
| `item_gap` | 4 | the items of a bar, the filter bar, the chips of a row, the key caps of a tooltip, the facts of a line of an outline | N3 |
| `button_gap` | 8 | the push buttons of a row | N3 |
| `section_gap` | 8 | the cards and the sections of a page, the rows of a radio group, and the parts of a dialog | N3, C1 |
| `bar_gap` | 8 | the items of a menu bar | N3 |
| `band_gap` | 0 | the bands of the shell, which a 1 px line separates | T1 |
| `title_gap` | 2 | a title and what it names | C2 |
| `line_gap` | 2 | the lines of a list of facts, and the items of an accordion or a choice list | C1 |
| `label_gap` | 6 | an icon or a mark and its label | C1 |
| `form_row_gap` | 6 | the rows of a form, and the parts of a terminal, of an MCP log and of a statistics page | C1 |
| `form_column_gap` | 8 | the label column and the control column of a form | C1 |
| `popup_gap` | 2 | a part and the popup that opens at it | C1 |
| `indent` | 12 | one level of a tree | C1 |
| `accordion_body_gap` | 2 | the open body of an accordion item | C1 |
| `header_gap` | 4 | the name of a column and the glyph of its sort | C1 |

### Small offsets inside a part

`shadow_offset` (2) is the offset of the shadow under a button. `chevron_nudge` (1) lowers the chevron of a card under the middle line of its header. `stepper_glyph_inset` (3) is the space between the marks of a spin box and the edge of its stepper. `switch_knob_padding` (2), a control size, is the space between the knob of a switch and its track. `splitter_band_width` (4), a control size, is the width of the band that a splitter shows.

A theme of a slice holds a space only where the job is not a role above, such as the distance of a tooltip from its part (`part_gap` of `TooltipTheme`) and the column gap of an outline row (`column_gap` of `OutlineTheme`). The builder of a slice takes a `widget_theme` and reads the roles above.

## 4. Who gives a space

A space has three givers. Each space has one giver, so no space is given twice.

1. **The padding of a box** lies inside its edge. The box draws the edge, so the box sets the padding. A card, a dialog, a button, a table cell and a menu read their padding from the theme and draw it.
2. **The gap of a layout** lies between its children. A layout places its children, so it sets the space between them. It reads the gap from a role, and a child never adds a space for a neighbour.
3. **The space at the edge of a slot** lies between the edge of a slot of the frame and what the slot holds. A tab page and each slot of a split pane give it. The value is `slot_padding`, and the printer context carries it down.

### The space in the printer context

`PrinterContext` holds the space as a field `space`, a tuple `(left, top, right, bottom)` of pixels, next to the range of each axis ([layout-rules.md](layout-rules.md) §1). The functions that make an offer for a child (`with_exact_size`, `with_bounded_size`, `with_size_range`, `with_inner_size` and `with_free_axis`) take the keyword `space`. Where a caller gives none, the space is 0. `make_child_context` keeps the space of its parent, so a wrapper that passes its offer on gives its child the same space. The ranges hold the space: an exact width is the width of the child with its space.

The first box in a slot that has an edge takes the space. A box computes its shape once, and the shape holds the space outside its margin: from the outside in, the space, the margin, the border and the padding. The extent of the box holds the space, as it holds a margin, and the box draws nothing in it. The box then gives 0 to what it holds. So a page in a card, a card in a page, a dialog and a cell never get the space a second time, and no page adds a padding of its own. A widget that holds nothing, such as a label, takes the space around itself.

### How each part passes or takes the space

| Part | What it does with the space of its offer |
| --- | --- |
| Shell, tab group, split pane, dialog | Take none. They are the frame. The lines of the window and the dividers of a split reach the edges. |
| Tab group | Gives `slot_padding` to the page of the selected tab. It gives 0 to the strip and the names of the tabs. |
| Split pane | Gives `slot_padding` to each slot. A divider has the same space on both sides (R2). |
| Column and row | Give each child the space at the sides across the axis. They give the space before the axis to the first child, and the space after it to the last child. |
| Grid | Gives each side to the cells at that side. |
| Stack | Gives the whole space to each child, because the children overlap. |
| Flow, constraint layout | Take the space around themselves, because which child stands at a side depends on their extents. |
| Layout of a list | Gives the space on its axis to the child whose document node has no neighbour on that side. |
| Card, button, field and other boxes | Take the space outside their margin and give 0 to what they hold. |
| Scroll pane | Adds the space to its padding. It cuts its content inside the space on every side, at every scroll position, and its bars stay at the outer edge, at the inner edge of its border. |
| Tree and list | Take the top and the bottom space around themselves, and their own scroll pane cuts inside it. Their rows take the left and the right space as their side padding, and `tree_row_padding` where the slot gives none. So the band of a selected row reaches the edges of the slot. |
| Text printer | Takes the space as a box. Its lines, its caret and its highlight stand inside it, and its IO map carries the space for its readers. |

The printers to graphics of the domains, such as chart, graph and sequence chart, take no space. The window shows them inside a widget box, which holds the space.

### An example

A tab page holds a column of three labels. The tab group gives `slot_padding` to the page, which is 8 px on each side. The page is a `VerticalLayout`, so it passes the space by side:

| Child | Space `(left, top, right, bottom)` |
| --- | --- |
| first label | `(8, 8, 8, 0)` |
| second label | `(8, 0, 8, 0)` |
| third label | `(8, 0, 8, 8)` |

Each label takes its space around itself, so the first line of the page is 8 px from the top edge of the page, and the last line is 8 px from the bottom edge. The labels stand `gap` apart in the column, and the gap reads a role. If a card held the column, the card would take the 8 px outside its margin and give 0 to its column.

### Why the space is in the printer context

Three other inputs can decide the space at an edge, and each fails where the printer context holds.

- **The path upward.** A slot could search the path for the nearest parent with an edge. The direct parent is often a layout that draws nothing, so the search must skip it. Across a projection the path names the domain document and not the widget that it became.
- **The child.** A slot could look at what its document becomes. The slot learns that only after the child prints, and the print needs the space.
- **The printer context.** The slot gives a space, so it puts the amount into the offer, and the amount goes down with the print. Each function that makes an offer states the space, and where it states none, the space is 0. So a printer that does not know the space cannot pass it one level too deep. A chain of projections is one print, so each stage sees the same offer.

The type of a box sets how the box takes the space. An alert pads itself by its type, because the amount does not say that a tinted fill lies there.

### A printer makes no copy of itself

A printer reads a value of one print from the context. It does not make a copy of its projection with that value in it. The text printer reads `:line_spacing` from the context, and its IO map carries what its readers need. [architecture-rules.md](architecture-rules.md) states the rule.

## 5. What other tools do

Most tools agree on four points:

- **Two layers of space.** The space inside the edge of a container and the space between its children. Newer systems put the space between children on the parent.
- **A scale.** Values come from a scale on a 4 px base, or from the style of the platform.
- **The container owns the space at its own edge.** A nested container adds none.
- **No border on the rows of an IDE list or table.** Settings screens use framed cards.

They differ on the margin and on the scroll edge. Where a margin exists, it causes double space, and only CSS collapses it. The padding of a scroll container scrolls with the content in CSS, Compose and Flutter. It stays fixed in Android views and in Qt.

| Tool | What it does | Source |
| --- | --- | --- |
| CSS | Padding and margin on every box. `gap` on flex and grid containers, with a default of 0. Vertical margins of siblings collapse, but not in flex or grid. The padding of a scroll container is part of the scrollable overflow. | [gap](https://developer.mozilla.org/en-US/docs/Web/CSS/gap), [margin collapsing](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_box_model/Mastering_margin_collapsing), [css-overflow-3](https://drafts.csswg.org/css-overflow-3/) |
| Qt widgets | The style gives a layout margin of 11 for a window and 9 for another widget, and a spacing of 6. A layout that is not at the top has margin 0. `setViewportMargins` reserves space outside the view, and the space does not scroll. | [QLayout](https://doc.qt.io/qt-6/qlayout.html), [qlayout.cpp](https://github.com/qt/qtbase/blob/dev/src/widgets/kernel/qlayout.cpp), [QAbstractScrollArea](https://doc.qt.io/qt-6/qabstractscrollarea.html) |
| Jetpack Compose | `Modifier.padding`, and no margin. `Arrangement.spacedBy` for the gap. `contentPadding` scrolls with the content. A `Scaffold` consumes the insets that it passes down, so a child does not pad them twice. | [modifiers](https://developer.android.com/develop/ui/compose/modifiers), [Arrangement](https://developer.android.com/reference/kotlin/androidx/compose/foundation/layout/Arrangement) |
| Flutter | A `Padding` widget, `spacing` on `Row` and `Column`. `ScrollView.padding` is a `SliverPadding` inside the scrollable, so it scrolls. A scroll view consumes the `MediaQuery` padding on its main axis. | [Padding](https://api.flutter.dev/flutter/widgets/Padding-class.html), [scroll_view.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/scroll_view.dart) |
| Android views | Padding on any view, and a margin on the child that its parent reads. `clipToPadding` is true by default, so children clip to the padding. | [ViewGroup](https://developer.android.com/reference/android/view/ViewGroup) |
| SwiftUI | The `.padding()` modifier adds. A stack takes a `spacing`. `contentMargins` insets scrollable content. | [padding](https://developer.apple.com/documentation/swiftui/view/padding(_:_:)), [contentMargins](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:)) |
| Fluent and WinUI | A base unit of 4 px. 8 px between buttons. | [Fluent 2 layout](https://fluent2.microsoft.design/layout), [layout panels](https://learn.microsoft.com/en-us/windows/apps/design/layout/layout-panels) |
| Tailwind and Bootstrap | A scale on a 0.25 rem step. `gap-*` for the space between children. | [Tailwind theme](https://tailwindcss.com/docs/theme), [Bootstrap spacing](https://getbootstrap.com/docs/5.3/utilities/spacing/) |
| Visual Studio Code | A divider hit area of 4 px. Lists have no padding, so rows reach the edge of the view. | [sash.css](https://github.com/microsoft/vscode/blob/main/src/vs/base/browser/ui/sash/sash.css), [list.css](https://github.com/microsoft/vscode/blob/main/src/vs/base/browser/ui/list/list.css) |
| JetBrains | "Do not add borders between rows or columns" in a table. | [table](https://plugins.jetbrains.com/docs/intellij/table.html) |

This system follows Compose and Flutter in how it passes the edge space: a parent gives an amount in the context, and a child that has an edge consumes it. It follows Android views and Qt in the scroll edge: the space stays fixed and the content is cut inside it. It has no margin as a source of space between siblings. The space between siblings is the gap of their layout.

## 6. How to space a new widget, a new layout or a new page

1. **Read a role.** Find the space in section 3 by the rule that requires it: a padding inside an edge, a gap between children. Read it from the widget theme with `get_widget_style(widget_theme, :role)`.
2. **Hold the role in the projection.** The projection has a field for the value, and its builder fills the field from the `widget_theme` that it takes. The terminal does it:

   ```julia
   @projection UntrackedCell struct TerminalToWidget <: Projection
       gap::Int = get_widget_style(nothing, :form_row_gap)
   end

   make_terminal_projection(; theme = nothing, widget_theme = nothing) =
       TerminalToWidget(; gap = get_widget_style(widget_theme, :form_row_gap))
   ```

3. **Take the space of the slot into the box.** A printer that draws a box takes `ctx.space` into its shape and gives 0 to what it holds. A printer that passes its offer on gives the space to the child at the side that the child stands. A printer that draws a canvas of its own, as the text printer does, puts the space into its extent.
4. **Add a role when the job is new.** A job that no role names gets a field in `WidgetTheme`, with a docstring that says what it changes on the screen. Do not reuse a role of another job to avoid a field.

A builder must not do these:

- **A number as a gap or a padding.** `gap = 6` and `padding = Inset(4, 4, 8, 8)` in a layout or a widget break R4, because the value does not follow the theme or the scale. `test_widget_gap_role()` parses `source/platform` and reports each number other than 0 as `gap`, `horizontal_gap`, `vertical_gap`, `padding` or `margin` of a layout or a widget. A product of a role and a number, such as `2 * p.gap`, is not a literal, and the test does not see it.
- **A padding of its own at the root of a page.** The slot gives the space of the page (R1). A page that pads its root adds a second space.
- **A copy of the projection for a value of one print.** `test_widget_printer_projection()` reports a call of a projection constructor inside a print in `source/platform/widget/`.
- **A printer that reads the space and passes it one level too deep.** A box gives 0 to what it holds. `test_slot_space()` prints each widget of the dispatch as the page of a tab and as the body of a card, and checks that the space reaches the first box once.

The examples in [layout-rules.md](layout-rules.md) write a number as a gap to show the size rules. A real builder writes a role there.
