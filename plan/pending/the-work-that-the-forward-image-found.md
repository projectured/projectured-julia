# The work that the forward image found

Status: pending. Owner request 2026-09-29: "put it in a new plan".
The order (owner 2026-10-02, "Agreed", on Claude's proposal): after the decided
points of [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md)
are built and checked, §2 is built directly, one widget at a time with a size
test for each, because it follows a rule that exists; the search of §1 runs and
brings its questions (how a selected header is drawn, how Alt and the arrows
reach a row and a column); §3 brings its question of the layout with its facts.

The plan [the-forward-image-of-a-part.md](../done/the-forward-image-of-a-part.md)
made every part of a widget map forward to the node that draws it, and a point
map back to the part drawn there. Its round trip test and its decisions found
three pieces of work that are not part of it. This plan holds them. Each needs
its own decisions before it is built.

## 1. A header, a cell and a row are parts of their own

**The rule** (owner 2026-09-29, Q12 of the forward image plan): "row_headers[k],
a row header can contain anything and an Alt+press should be able to also select
inside, the table reader can still allow selecting a row or a column by some
other means: e.g. Alt+cursor navigation. This whole issue is generic and exists
in all domains and cross domain nesting." A point maps back to the most specific
part that is drawn there, and a part that holds it is reached by navigation.
[reference.md](../../documentation/package/kernel/reference.md) states the rule,
in "The place of a part".

What `WidgetTable` does today, against the rule:

- A selected header is drawn as its whole row or column:
  `_wt_selection_shape` answers `:row` for `row_headers[k]` and `:col` for
  `column_headers[k]`. It must mark the header only.
- A point inside a header or a cell maps to the header or the cell
  (`_map_wt_point`), and not on into what the header or the cell holds, so an
  Alt+press does not reach a part inside it.
- Alt and an arrow key must reach a row and a column of a table.

The rule is generic, so the same questions stand in every container that draws
parts of other domains. Find the other places first, with the round trip test
of the widget examples as the check.

- [ ] 1. Find every backward map of a point that stops at a part which holds
  drawn parts of its own, in the widgets and in the other domains.
- [ ] 2. Decide with the owner how a selected header is drawn, and how Alt and
  the arrow keys reach a row and a column.
- [ ] 3. Build it, with a test for each case.

## 2. A widget with one child gives the child its own room

§3 of [layout-rules.md](../../documentation/rule/layout-rules.md): a container
gives a child a slot only where it knows its own extent without the child, and
the slot is its extent less the parts it draws around the child. Six widgets
give their one child the whole range that they were given:

- `WidgetDialog`, to its content and to each of its buttons, so a button with
  no width takes the width of the whole dialog window;
- `WidgetTitlePane`, so its content takes the height of the title bar too: in
  the split pane example a title pane is 121 by 60 and its content 300 by 800;
- `WidgetTooltip` and `WidgetContextMenu`, which are overlays and size to their
  content, so they must give a bounded range;
- the document content of `WidgetText` and `WidgetTextarea`.

- [x] 1. For each widget, write down its extent and the parts it draws around
  the child, and what it must give the child: a slot less those parts, or a
  bounded range.

  Facts (2026-10-02, `WidgetToGraphics.jl`). The tool is `with_inner_size`: it
  keeps the state of each axis (a slot stays a slot, an edge stays an edge, free
  stays free) and takes the parts around the child off, as the tabbed pane does
  with its insets and its tab strip.

  | Widget | Its extent | Parts around the child | What the child must get |
  | --- | --- | --- | --- |
  | `WidgetTitlePane` | the range it was given; with no slot, the title or the content | the insets; the title bar and its gap above | `with_inner_size`: the insets on both axes, and the title bar on the height |
  | `WidgetDialog` | its window, which the scrim fills; the card in it comes from what it holds | the margin, the border and the padding of the card; the title and a gap above the content; a gap and the row of buttons below it | the content: the edge of the window less those parts, bounded, because the card takes its size from it; each button: no offer on the width (a row) and the same bounded height |
  | `WidgetTooltip`, `WidgetContextMenu` | their content, capped at the edge (`_resolve_overlay`) | the insets | a bounded range: the edge less the insets, never a slot, because an overlay is as large as its content |
  | `WidgetText`, `WidgetTextarea` | the range, never under the content and the insets | the insets | `with_inner_size` with the insets, for a `Document` content and for the plain text view |

  Also found: `WidgetContextMenu` takes the size of the child canvas but not its
  place, so a child that has its own position draws outside the box of the menu,
  and a right click there opens no menu (the live check of 2026-10-02). That is
  a question of its own for the owner, and this step does not change it.
- [ ] 2. Build it, one widget at a time, with a size test for each, as
  `test_size_range_composite()` tests the composite.
  - [x] `WidgetTitlePane` (2026-10-02). The pane resolves its own extent from its
    range (`_resolve_width`, `_resolve_height`): it measured only what it drew, so
    in a slot of 300 by 200 it was 40 by 54. Its content gets
    `with_inner_size` of the range, less the insets and less the title bar and
    its gap. Test: `test_size_range_one_child()`. The three examples with a title
    pane keep their counts (12701 pass, 196 fail, 4 broken, the same without the
    change: the fails are type-in and navigation baselines).
  - [x] `WidgetTooltip` and `WidgetContextMenu` (2026-10-02). Each gives its
    child `_get_overlay_content_context`: the edge less the insets, bounded. In
    the exact range of a window, both took the whole window before (400 by 300
    for a label of 40 by 24). Test: `test_size_range_one_child()`; the context
    menu, popup, tooltip, tracking screen and shell tests pass (88 and 209).

## 3. The file chooser draws its parts at one place

`FileSystemChooserToWidget` puts the tree of the directory and the name field in
one `WidgetComposite`, and neither has a place of its own, so the field stands
over the tree. Its comment says that it adds the arrangement. Its rule that a
row of the tree types its own name into the field (`name_file`) is made but not
used. No dispatch table, example or test prints a chooser with it: the file
dialog test prints the dialog with the widget projection, which has no rule for
a chooser.

- [ ] 1. Find how the file dialog must draw its chooser, and connect the
  printer there.
- [ ] 2. Arrange the tree above the field, the tree filling the height. A
  `VerticalLayout` makes the file system package depend on the layout package;
  decide with the owner whether that is right, or whether a composite with the
  place of each part is.
- [ ] 3. Connect the rule that a row types its name, and test the dialog as a
  person uses it.
