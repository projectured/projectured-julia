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

The slice uses the widget, layout, tooltip and style slices. It holds builders
and no projection: a domain projection calls them inside its build, maps the
places of its documents in the output with its own slots, and routes the paths
of the selection and of the pointer to every part, so each row reads its light
from its own cells. The research domain builds the outline of a study so.

## Design decisions

- **A kit, not a widget.** A row is made of widgets that exist, a `:row` card,
  labels, quiet fields and toolbar items, so every printer and reader of the
  widget slice serves it. The kit holds only the arrangement and the theme.
- **No control at rest.** The fold and the menu of a row show under the pointer
  and with the caret, and the menu holds every action of the row. The mark and
  the "⋯" open the same menu, so a person who does not know the right click finds
  it.

## Usage

- Tests: `test_outline()` for the theme, a row that lights and opens its menu,
  and the shown dates.
