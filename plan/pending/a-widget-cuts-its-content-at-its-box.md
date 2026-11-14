# A widget cuts its content at its box

> **Kind:** plan · **Status:** a plan, written 2026-11-15 at `main` `11585943d`. Not approved for
> implementation. · **Stands on:** [layout-rules.md](../../documentation/rule/layout-rules.md),
> [widget.md](../../documentation/package/platform/widget/widget.md),
> [layout.md](../../documentation/package/platform/layout/layout.md)

A widget that is given a size smaller than its content draws the content past its edge. The text
lies over the widget next to it. This plan makes each widget cut its content at its box, makes a
text field keep its caret in view, and makes a `LayoutConstraint` with a set size cut its child.
The row, the column, the stack and the flow stay as they are: they only place their children.

## 1. The goal

When this plan is done, these must be true:

1. No widget draws past its box. This is true for a size that the widget sets itself (`width`,
   `height`, `size`, `rows`) and for an exact size that it gets from its parent.
2. A content that is larger than its box starts at the inner start edge of the box and is cut at
   the inner end edge. A widget does not draw over its own border or padding.
3. `WidgetText`, `WidgetTextarea` and `WidgetSpinBox` keep the caret in view. Their text scrolls
   when the caret goes past the edge.
4. `LayoutConstraint(child; width = Fixed(40))` keeps 40 in every layout, also when its child is a
   layout. The next child of a row starts at 40, and nothing draws past 40.
5. `test_layout_rules()` checks the ink of every widget type against its box, also with a set size.

## 2. What exists

A probe on 2026-11-14 printed each widget with a set size smaller than its content and compared
the box of the ink with the extent that the widget reports. A render to a PNG file showed the same
in pixels.

**These draw past their box:**

| Widget | Size | What passes the edge |
| --- | --- | --- |
| `WidgetText` | `width` | the text, to the right; nothing keeps the caret in view |
| `WidgetSpinBox` | `width` | the number, over its own buttons |
| `WidgetButton` | `size` | the caption, which is centred, on both sides |
| `WidgetSelect` | `width` | the selected value |
| `WidgetTextarea` | `width`, `rows` | the lines, to the right; the box grows to all lines, so `rows` does not hold |
| `WidgetAccordion` | `width` | the question and the answer |
| `WidgetAlert` | `width` | the title, and a long word of the description |
| `WidgetCard` | `width` | the title and the footer; the body is cut |
| `WidgetCard` | `height` | the body, down over the widgets below |
| `WidgetAvatar` | `size` | the initials |
| `WidgetShell` | `size` | the content, down; `_RULES_INK_BROKEN` holds it |
| `WidgetList` | `width` | the rows, when the list gets no height edge and so makes no pane |

**These cut:** `WidgetScrollPane`, `WidgetTransformPane`, `WidgetTitlePane`, `WidgetSplitPane`,
the tab page, the width of the body of a card, and `GridLayout`, `GridList` and `GridColumnList`
for a column or a row that has a set size or a share (`clip_child_to_slot`). `WidgetTable` cuts its
cells through its grids.

**The rule allows the fault.** [layout-rules.md](../../documentation/rule/layout-rules.md) §1 says:
"A widget told to be 40 wide draws 40 and lets its content overflow." §3b says that only a
container that gives an exact range cuts. The ink check of `LayoutRulesTest.jl`
(`_rules_is_ink_inside`) skips each axis whose kind is `:authored`, and a rigid widget in an exact
range smaller than its content draws its content (`exact_less = ==(n)`).

**A row and a column lose a `Fixed` size.** `_main_context` gives a child with a preferred size an
exact range, but `_vl_build` and `_hl_build` place the next child after the extent that the child
draws. A child whose content is wider than its `Fixed(40)` draws its content, and the next child
moves. Nothing overlaps, and nothing keeps 40. [OutlineRow.jl](../../source/platform/outline/OutlineRow.jl)
puts a layout into a `Fixed(menu_width)` slot of a row in this way.

**Real views with a set size:** text fields of a set width in the explorer filter (80), the
dashboard and the section title (240), the file chooser (240), the folder path field (320) and the
field in a natural sentence (16, `NaturalArrangement.jl`). The task buttons set only a height of
30, which one line fits.

## 3. Decisions

The owner decided D1 and D3 on 2026-11-15, and D4 on 2026-11-15 (option 1). The assistant proposed
D2, D5, D6 and D7. A proposed decision counts as approved when the owner approves this plan for
implementation. The owner can name one to see it first.

- **D1. A widget cuts its content at the size that it sets.** The owner chose this (option A).
  Rejected: the set size is a minimum and the widget grows with its content (option B).
- **D2. A widget takes an exact size that it gets, and cuts its content there.** Today a rigid
  widget in an exact range smaller than its content draws its content (`max(m, C)`), and the giver
  cuts at the outer edge, so a button loses its right border. Only the widget knows its border and
  its padding, so only the widget can cut at its inner box. A bounded range keeps the content as a
  floor: the rows and the columns measure a child by what it draws (§3b), and that measurement uses
  bounded ranges only. A table is not changed: it withholds the offer of a column whose cells it
  cuts, so those cells get no exact range.
- **D3. A layout only places its children.** The owner said this on 2026-11-15: a layout is not a
  widget. The row, the column, the stack, the flow and the composite build no viewport.
- **D4. The place where a size is written cuts at that size.** The owner chose this (option 1) for a
  size that is set on a layout and not on a widget. A `LayoutConstraint` cuts its child on each axis
  where it states a preferred size, a weight or a maximum, at the size that it gets, and reports
  that size. The grid cuts its columns and rows, because the grid holds their policies. Rejected:
  nothing cuts (content draws past a `Fixed` set on a layout); and a layout that never gives a child
  more than its own size (it changes the floor of D2, which the stacks measure with).
- **D5. A content larger than its box starts at the start edge.** A caption, a value or a title that
  does not fit is not centred. It starts at the inner start edge and is cut at the end, as a grid
  column shows the start of a cell (`_gl_child_x`). Rejected for this plan: an end mark "…" (see §6).
- **D6. A text field keeps its caret in view as a scroll pane keeps a selection in view.**
  `WidgetText`, `WidgetTextarea` and `WidgetSpinBox` get the view state `scroll_position`, written
  with `_write_view_state` as in `WidgetScrollPane`. The print maps the selection of the field
  through its content IO map to a box (`find_reference_box`), and draws with the least move from the
  stored offset that shows the caret (`_compute_shown_offset`). The IO map keeps the drawn offset,
  as `revealed_scroll` does, and the reader of the field writes it with each answer. So the text
  does not move while the caret moves inside the view. Rejected: an offset that the print derives
  from the caret alone; the text then moves with each step of the caret to the left from the end.
- **D7. `rows` of a text area is its set height.** The area is `rows` lines tall, cuts the other
  lines, and scrolls them by D6. Rejected: `rows` as a minimum height (option B of D1).

## 4. Steps

Each step is one commit in a worktree of projectured-julia, on a branch of its own.

1. **The rule and the test.** Change [layout-rules.md](../../documentation/rule/layout-rules.md):
   §1 (a set size cuts; the table of the four states: an exact size is taken and cut by the widget),
   §3b (who cuts: the widget at its inner box, the place where a size is written, the grid; a
   layout only places), and the sentence on the card in §3b. Change the pages of the widget slice
   and the layout slice that say the same. In `LayoutRulesTest.jl`: the ink check covers the
   `:authored` axes; each widget type that has a size field gets a second sample whose set size is
   less than its content; a `:rigid` axis expects `exact_less = ==(m.less)`; a check of a
   `LayoutConstraint` with `Fixed`, with a weight and with a maximum, whose child is a layout, in a
   row, a column, a stack and a flow. Each type that fails goes into a `@test_broken` set that
   names this plan, and the later steps take it out. The comment of `_RULES_INK_BROKEN` names
   `plan/done/a-layout-paints-only-what-the-screen-shows.md`.
2. **A widget cuts at its box (D1, D2, D5).** One function of the box code in
   `WidgetToGraphics.jl` puts the content canvas of a widget in a `GraphicsViewport` at the inner
   box, on each axis where the size of the widget is set or exact. `_resolve_width` and
   `_resolve_height` give an exact size where the range is exact. Each widget of §2, and each
   widget that the test of step 1 finds, uses the function. A `WidgetList` cuts its width also with
   no height edge. A `WidgetCard` cuts its height when it sets one. `WidgetShell` leaves
   `_RULES_INK_BROKEN`. Tests: `test_layout_rules()` and the test file of each widget changed.
3. **A text field keeps its caret in view (D6, D7).** `scroll_position` on `WidgetText`,
   `WidgetTextarea` and `WidgetSpinBox`; the offset in the print and in the IO map; the write in
   the reader. Test: a field of width 60 that holds a long text, a caret at its end, and a key press
   of Left and of Home. Assert the place of the caret in the output, not only that it exists.
4. **A `LayoutConstraint` cuts where it states a size (D4).** Its printer wraps the output of the
   child with `clip_child_to_slot` on each axis where it states a preferred size, a weight or a
   maximum, and the size that it gets is exact or bounded. Its reference mappers go through the
   step `content` of the viewport, as `make_slot_reference` does. Tests: `test_layout_rules()`, and
   in `test/platform/outline/OutlineTest.jl`: the menu column of a row is `menu_width` wide and
   nothing draws past it.
5. **The checks.** Run `test_platform()`, `test_dataframes()` (a layout change broke data frame
   edits before), and the suites of the domains that use a `LayoutConstraint` with a set size.
   Render the probe of §2 again: no text passes its box. Look at the explorer filter and the
   folder path field with a long text in a window. Measure the time of a frame of a large data frame
   view before and after step 2, because D2 adds a viewport to many cells.

## 5. Risks

- D2 changes every rigid widget in an exact range smaller than its content: it was as wide as its
  content and pushed its siblings; it now takes the range and cuts. A view that relied on the push
  shows less. The data frame suite and a look at the explorer, the task pages and the outline find
  such a view.
- A viewport per widget in an exact range adds a clip per cell of a table. If step 5 measures a
  slower frame, a widget builds its viewport only when its content is larger than its box.
- A `LayoutConstraint` that cuts adds a step `content` to the output path of its child. A path
  that a reader or a test builds by hand breaks. The tests of the outline and of the selection find
  it.

## 6. Not in this plan

- An end mark "…" on a cut caption or value.
- `wrap = true` on a text field with a set width wraps at the width of the parent, not at the set
  width.
- A `Fixed` size or a maximum in `child_width` or `child_height` of a row or a column. No view uses
  one.
- A widget with a box in a bounded range whose rigid content is wider than the maximum: an
  ancestor cuts it at its outer edge, as today.
