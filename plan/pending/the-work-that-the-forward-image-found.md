# The work that the forward image found

Status: pending. Owner request 2026-09-29: "put it in a new plan".

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

- [ ] 1. For each widget, write down its extent and the parts it draws around
  the child, and what it must give the child: a slot less those parts, or a
  bounded range.
- [ ] 2. Build it, one widget at a time, with a size test for each, as
  `test_size_range_composite()` tests the composite.

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
