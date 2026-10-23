# Outlines

> **Kind:** design · **Status:** current · **Stands on:** [system-anatomy.md](../../../design/system-anatomy.md), [widget.md](../widget/widget.md), [context-menu.md](../widget/context-menu.md), [style.md](../style/style.md)

The outline slice of `ProjecturedPlatform` holds what an outline of records
draws: a study of the research domain, a workflow, and any list of records with
an author and a time. It holds one theme and the builders of the parts of a row.
A domain builds its view from them, so its outline reads like every other one.

## How it works

### The row

A row has three columns. The first holds the facts of the record: its fold, its
mark, its id, its author and its time. They stand on the lines that the text
takes anyway: the fold, the mark and the id on the first line, the author and the
time on the second, and the date on the third, only where the day differs from
the day of the row above. The second column holds the text of the record and what
stands under it: the fields that hold a value, each after the word of its
meaning, the links as chips, and the documents of the record. The third holds the
menu of the row. A row of one line, or a folded row, keeps only the first line of
its facts, and its author, time and date follow its text on its line.

`make_outline_row(outline; facts, body, menu, indent, revealed, title, compute_menu)`
makes the row: a `WidgetCard` of the variant `:row`, which draws no panel at rest,
the hover layer while the pointer is on it and the selection band while the caret
is in it. Both colours are cells of the card, so a light draws the band again and
builds no row. The controls of `revealed`, such as the fold and the "⋯", take no
colour at rest and keep their size, so the row does not move when they show.

The parts of a row each have a builder: `make_outline_facts` stands each line of
facts on a line of the text, `make_outline_label` and `make_outline_text` draw a
text in a text role of the theme, `make_outline_mark` the mark of a record,
`make_outline_control` a control that shows under the pointer, `make_outline_chip`
the id of a linked record, `make_outline_avatar` the author, `make_outline_field`
a field after its word, `make_outline_relations` the links as groups of chips, and
`make_outline_section` the label of a section. A text of a record is a quiet
`WidgetText` that wraps at its column and draws its box only while it holds the
caret, and it reads its value in a cell of its own, so a key draws the text again
and builds no row.

`keys` of `make_outline_row` are the key bindings of a row, such as Return at the
end of its text and Alt+Up: the card of the row reads a key that no part of the
row takes while the caret is in the row. Each domain gives its own, and a key that
moves a record answers the move and a `SelectDocumentOperation` of the record with
the caret where it was, which the editor resolves after the move.

A press on a chip answers what its maker gives, such as the
`SelectDocumentOperation` of the linked record: the view whose input holds the
record names its place, so the record is selected where its section holds it, and
the scroll pane around the view brings its row into view.

### Elements

A record that holds a list field named `elements` holds documents of any domain
there: code, a page of text, a table, a chart. `make_outline_element(outline;
content, menu, revealed)` draws one: the document through the view of its own
domain, in a light inset, with its own "⋯", which shows under the pointer. The
block is a `:row` card, so it lights as a row does, and `get_outline_element_steps()`
gives the steps from the block to the document, for the slots of a domain.

`make_add_element_operation(holder, document; index)`,
`make_remove_element_operation(holder, index)` and
`make_move_element_operation(holder, index, to)` edit the list; each names
`holder`, so it acts the same from any part, and a move is a remove and an insert
in one edit. The document goes in as it is, so a document that a note of the
clipboard holds stands at two places and keeps its identity. `make_element_menu`
holds Move up, Move down, Remove and, when given, Open in a tab.
`make_element_choice_list(holder)` lists the kinds of document that stand as an
element (`is_element_type`), with their icons and the first sentence of their
docstrings, and a choice adds a new one. `add_element!(holder, document)` is the
verb of the assistant: it goes through the readers of the editor, so the history
of the tab records it.

### The paths

A domain view builds its output in one computation, with `OutlineSlot`s that say
where each document of the input sits. `map_outline_forward(slots, reference)` and
`map_outline_backward(slots, reference)` map a path through the first slot that
holds it. A `whole` slot is a record and its row: the record maps to the row, and
any place of the row that no slot before it holds maps back to the record, so a
press on the facts of a row selects the record, and a menu that its mark opens
belongs to it. `route_outline_paths!(input, output, image; embedded)` makes every
document of the output hold its part of the image of the selection and of the
part under the pointer, so each row reads its light from its own cells; a
document of the input that the output holds keeps its own paths.

### The menu of a row

`compute_menu()` makes the menu of a row when it opens, so each item names the
record as it is then. A right click on the row opens it at the pointer, Shift+F10
opens it under the row while the caret is in it, and the mark and the "⋯" open it
under themselves with `make_outline_menu_operation`. The menu opens in the context
menu window, so its keys, F2 and its close are those of every menu
([context-menu.md](../widget/context-menu.md)).

### The theme

`OutlineTheme` holds the sizes and the type of a row. The widths of the columns
are control sizes, the gaps and the line heights are spacings, and the type is
a text role of the colour theme, so the scale of the appearance and the palette
apply to an outline as to any other view. A projection holds the values with
`make_theme_values_field(OutlineTheme, theme)` and reads them at a print with
`unwrap_cell`; each builder takes them as `outline`. The light of a row takes the
colours of a row of a list from the widget theme.

The heights of a line of text and of a line of a field are spacings,
`text_line` and `field_line`. A builder gives them to a label or a text field
as an `ExactSpacing`, so the facts of a row stand on the lines of its text.

### The dates

`compute_shown_dates(days)` answers which rows of an outline show their date:
the first row with a day, and each row whose day differs from the day of the
row above it with a day. A domain passes the day of each row in the order of
the rows, in any form that compares, and `nothing` for a row with no time.

## How it fits

The slice uses the widget, layout, tooltip, style and domain slices; the domain
slice gives the kinds of document that stand as an element. It holds builders
and no projection: a domain projection calls them inside its build, maps the
places of its documents in the output with its own slots, and routes the paths
of the selection and of the pointer to every part, so each row reads its light
from its own cells. The research domain builds the outline of a study so, and the
workflow domain the outline of a workflow.

## Design decisions

- **A kit, not a widget.** A row is made of widgets that exist, a `:row` card,
  labels, quiet fields and toolbar items, so every printer and reader of the
  widget slice serves it. The kit holds only the arrangement and the theme.
- **No control at rest.** The fold and the menu of a row show under the pointer
  and with the caret, and the menu holds every action of the row. The mark and
  the "⋯" open the same menu, so a person who does not know the right click finds
  it.

## Limits

- A row is not lit while its own menu is open: the pointer leaves the window of
  the row when the menu window opens.
- A key that moves the caret does not scroll a pane: only a selection to show
  does.

## Usage

- Tests: `test_outline()` for the theme, a row that lights and opens its menu,
  and the shown dates; `test_elements()` for the add, the move and the remove of
  an element and the undo of each, its menu, the list of the kinds and the steps to
  an element.
