# A context menu stands where its part stands

> **Status (2026-10-02): done.** Found by the live check of step 12 of
> [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md).

## The fault

A right click on a part that has its own position inside a `WidgetContextMenu`
opens no menu, and the part does not light. A `WidgetContextMenu` has no
`position` field, so in a composite the only way to place it is the position of
its part. The part draws at its position, but the menu makes its own canvas at
(0, 0), as large as the part and its insets, so the part draws outside the box of
the menu. The composite reaches a child at a point only inside the child's
canvas, and the menu tests a point against its own box (`_outside_widget`), so
the light and the right click both miss. The size code is older than the events
plan.

## The decision

Owner 2026-10-02, "Agreed", on Claude's option (a): the menu stands where its
part stands, as a `LayoutConstraint` does, which forwards the canvas of its child
as its own. The canvas of the menu takes the origin of the part's canvas, the part
draws inside the box at the content offset, and the composite reads the place of
the menu through it (`_get_placed_position`). Rejected: (b) the box of the menu
grows from its origin to cover the part, so a right click on the empty area
before the part would open the menu too; (c) a rule that a part inside a menu has
no position, with an error.

## Steps

- [x] 1. The printer of `WidgetContextMenu`: the origin of its canvas is the
  origin of the part's canvas, the part's canvas stands in a wrapper at the
  content offset less that origin, and the frame of the part in the menu is the
  content offset. `_get_placed_position` reads the position through the menu.
- [x] 2. A test: in a composite, a right click on a part that has its own
  position opens the menu, and a move onto the part lights it.
- [x] 3. The suites of the menu and of the composite, and the move of this plan
  to `plan/done/`.

Built (2026-10-02): `WidgetToGraphics.jl`. The canvas of the menu has the origin
of the child's canvas, and the child's canvas stands in a wrapper at the content
offset less that origin; `_get_context_menu_child_offset` is the content offset,
and `_get_context_menu_child_entry` gives the routing helpers the offset of the
wrapper. A menu whose child has no position draws as before. The test in
`ContextMenuWindowTest.jl` fails without the change (no light, no menu) and passes
with it; `test_context_menu_window`, `test_widget_context_menu` and the size tests
pass (90), and `test_platform` has 86667 pass, the known file system failure and 8
broken. `context-menu.md` says where the menu stands.
