# A setting says what it sets

> **Status:** pending, implemented on the branch `field-descriptions`, not landed. Written on 2026-10-02 at the owner's
> request, after a discussion of the appearance tab and the settings tab. The
> owner decided D1 to D8 on 2026-10-02 and asked for the work.

## 1. The request

The owner asked: "did we extend the appearance and settings widget tab panes
with the documentation on the fields? this would help the user to know what he
is setting". Both tabs show the documentation of a field only as the tooltip of
its name, which a person sees only when the pointer rests on the name. The owner
chose:

- the description of a field is always visible (option B of the discussion);
- it stands under the name of the field;
- the card of a theme and the card of a settings group also say what they hold;
  that text is a part of the documentation of the type, and the display finds it
  there.

## 2. What exists

- **The settings tab** (`SettingsToWidget`). `@settings` takes a string before a
  field as `"Label: description"`; `SettingDescription` holds `label` and `text`.
  A card for each group holds a grid of three columns: the label, whose tooltip
  is the text, the control, and a reset button. The card description is a note
  when the editor does not use the group, or reads it only at the start.
- **The appearance tab** (`AppearanceToWidget`). `@theme` takes a string before a
  field as its docstring (`get_theme_field_texts`, `find_theme_field_text`). A
  card for each theme holds a grid of two columns: the name, whose tooltip is the
  docstring, and the control. Every field of the 29 themes has a docstring.
- **Wrapping.** A `WidgetCard` breaks its title and its description at word
  boundaries to the width that it is offered (`_push_text_block!` and
  `_text_lines` in `WidgetToGraphics.jl`), and so does a `WidgetLabel`, at the
  edge of the range that its parent gives (finding 1). A `GridLayout` has no
  cell that spans two columns.
- **The summary of a type.** `compute_docstring_summary(T)` in the help slice
  answers the first paragraph of the docstring of `T`; the help list uses it. The
  first paragraph of a theme docstring is written for a programmer today, for
  example "The theme of the JSON projections. `@theme` declares it, so
  `ScaledJsonTheme` holds each value times its scale, …".
- **No test** rests the pointer on a name in either tab and sees a tooltip.

## 3. The words

- **The description of a field**: the text of the field docstring, without the
  label part of a setting.
- **The summary of a type**: the first paragraph of the docstring of the type,
  which a person reads at the top of the card.

## 4. The design

### 4.1 A field shows its description under its name

Each field of both tabs keeps its row of the grid: the name and the control, and
in the settings tab the reset button. Under that row, the grid has a row of its
own for the description, which spans every column of the grid (D1, D2, D4). The
description is in the small font and the muted color of the widget theme, and
it breaks at word boundaries to the width of the columns that it spans. So the
names and the controls line up in their columns, and a description reads as a
part of the field above it.

A field with no description has no description row. The text drops the Markdown
code marks (the backticks) that some docstrings hold, so `<:` shows as `<:`.

### 4.1a The grid spans a child over columns

`LayoutConstraint(child; column_span = n)` says that `child` takes `n` columns of
a `GridLayout` (D4). The grid fills its rows in order, as now; a child with a
span takes its column and the `n - 1` columns after it, and starts a new row when
the row has not that many columns left. A span past the number of columns takes
the rest of the row.

- A spanning child adds nothing to the width of a column, so a long description
  does not widen the column of the names. When every column that it spans hands
  out its extent, it gets their width with the gaps; otherwise it may reach from
  its first column to the edge that the grid was offered, and a text in it
  breaks there (finding 2). The grid is as wide as such a child. A grid that was
  offered no width gives it no edge.
- It adds to the height of its row, as every child does.
- With no span, every child takes one column, and the grid lays out as before:
  the images of all examples stay equal, and the tables, which build grids, do
  not change.
- A grid whose children are a list (`GridColumnList.jl`) takes no span; the
  constraint is ignored there.

### 4.2 A label breaks its text already

A `WidgetLabel` breaks its text at the edge of the range that its parent gives,
exact or bounded (`print_document` of `WidgetLabelToGraphicsCanvas`). So a
description that a grid offers the width of the columns it spans breaks there,
and no new field is needed. The owner approved a `wrap` field (D7) when the plan
said that a label draws one line, which was wrong; finding 1.

### 4.3 A card says what it holds

The summary of the type is the description of the card (D3):

- the card of a theme takes the summary of its theme type;
- the card of a settings group takes the summary of its group type, and its
  note ("This editor does not use these settings.") follows on a line of its own
  (D6).

The first paragraph of each theme docstring and of each settings group docstring
becomes a text for a person: one or two sentences that say what the values of
the type change, in the words of the user, with no code mark. The text for a
programmer moves to the paragraphs after it. A writing rule says so, in
`documentation/rule/` and in the guide for a new domain.

The display reads the summary with `compute_docstring_summary`. The help slice
holds it now, and neither tab can reach the help slice without a new edge. It
moves to the documentation tool of the kernel, `tool/Documentation.jl`, which
every slice reaches and which reads docstrings already (D8).

### 4.4 The tooltip

With the description visible, the tooltip of a name says the same text again.
It goes (D5).

## 5. The decision log

- **D1. The description is always visible** (option B). Rejected: the tooltip
  only (A); a panel of the field under the pointer or with the focus (C).
- **D2. The description stands under the name.** Rejected: a third column beside
  the control.
- **D3. The card of a theme and of a settings group says what it holds**, with
  a text that is a part of the documentation of the type, and the display finds
  it there.

- **D4. The description has a row of its own under the row of the name and the
  control, and spans the columns of the grid**, so the names and the controls
  line up. The grid gains a column span, `LayoutConstraint(child;
  column_span)`; the owner asked for it as a layout constraint. Rejected: the
  name, the description and the control one under the other, as VS Code shows
  them, whose controls do not line up.
- **D5. The tooltip of a name goes.**
- **D6. The note of a settings card follows the summary** on a line of its own.
- **D7. `WidgetLabel` takes `wrap`** (4.2). Not needed: a label breaks its
  text already; finding 1.
- **D8. `compute_docstring_summary` moves to the kernel** (`tool/Documentation.jl`,
  not sealed). Rejected: an edge from the appearance and the settings-managing
  slices to the help slice, which pulls the syntax and the text slices into the
  settings tab.

## 6. Steps

All the work is in a worktree, and each step is a commit.

- [x] **S0. The grid spans a child over columns** (4.1a). `column_span` of
  `LayoutConstraint`, and the placement, the widths, the offers and the row
  count of `GridLayoutToGraphicsCanvas`. Tests: a spanning child starts a new
  row when its row is short, adds nothing to a `Content` column, is offered the
  width of its columns and the gaps, and a grid with no span draws as before
  (the images of all examples equal, and the table tests pass).
- [x] **S1. A label wraps** (D7). Not needed; finding 1.
- [x] **S2. The summary reader moves to the kernel** (D8), with its test; the
  help list calls it there.
- [x] **S3. The first paragraphs.** The docstrings of the 29 themes and of every
  settings group start with a text for a person. A Sonnet sub-agent writes them
  from a brief; I review each one. The writing rule goes into
  `documentation/rule/writing-rules.md` and the guide for a new domain.
- [x] **S4. The settings tab** shows the block of 4.1 for each setting and the
  summary on each card.
- [x] **S5. The appearance tab** shows the block of 4.1 for each field and the
  summary on each card.
- [x] **S6. Tests of what is drawn.** In both tabs: the description of a field is
  drawn under its name, inside the width of its card, on more than one line when
  it is long; a card draws the summary of its type; a field with no description
  has no line for it. A live window of the application, driven by pushed SDL
  events, opens both tabs, and the owner reviews the images.
- [x] **S7. The guides**: `appearance.md`, `settingsmanaging.md`, `widget.md`,
  `style.md`, and the user guide.

## 7. Risks

- A card is taller by a line or more for each field. The cards of the appearance
  tab start closed, so the tab stays short; the settings cards are open.
- A description breaks only where the card offers a width. In a pane that offers
  none, it is one long line. The test of S6 runs at a narrow window width.
- A first paragraph that a programmer tool shows (the help list, `?T` in the
  REPL) changes its words. The help list shows a summary, so a text for a person
  fits there too.

## 8. Not in this plan

- A filter box that searches the names and the descriptions (option D of the
  discussion).
- A panel of the field under the pointer (option C).

## 9. Findings during the work

1. **A label breaks its text already** (2026-10-02). `WidgetLabelToGraphicsCanvas`
   breaks its text at the edge of the range that its parent gives, exact or
   bounded; a test of `LayoutCloseoutTest` shows it for a `Fixed` column. The
   plan said that a label draws one line, from a reading of the card printer
   only, so it asked for a `wrap` field. The span of a grid offers the spanning
   child the width of its columns as a bound, and the label breaks there.
2. **A description breaks at the edge of the grid** (2026-10-02). With the width
   of the columns that it spans, a description broke at about 250 pixels in the
   settings tab, whose columns are a label, a switch and a button, so a short
   text took two or three lines. A spanning child reaches from its first column
   to the edge that the grid was offered; it still widens no column.
3. **A line break did not always end a line** (2026-10-02). `_text_lines` kept a
   text that fit its bound on one line, line breaks included, so the note of a
   settings card could not follow the summary on a line of its own. A line break
   always ends a line now; the images of all 105 examples stay equal.
4. **The tests that find a place by scrolling** (2026-10-02). The settings tab is
   taller with the descriptions, so the test of the scroll scrolls until the row
   of the undo steps is in the window, and checks that "Log faults" is in the
   window before it presses there, instead of three steps of the wheel.
5. **The checks** (2026-10-02). The tests of the span, the layouts, the tables,
   the two tabs, the wrappers, the help, the theme, the summary, the guards and
   the application give 591 and 730 pass (2 old broken markers of the navigator);
   the export and the argument guards show only the failures of `main`. The
   images of all 105 examples equal those of `fb90cbd04`. The images of the two
   tabs for the owner are in `/var/tmp/field-descriptions/shots/`.
6. **The summaries** (2026-10-02). A Sonnet sub-agent wrote the first paragraph of
   the 29 themes and the 5 settings groups, and kept the text for a programmer
   in the paragraphs after it; review fixed "markdown" to "Markdown". A helper
   `strip_code_marks` of the kernel tool layer drops the backticks of a
   docstring that the tabs show.
7. **A description is closer to its field** (2026-10-02, the owner's request after
   the first images). The grid has one `vertical_gap`, so a description stood
   as far from the next field as from its own row. `GridLayout` takes
   `row_gaps`, the gap above each row, with `nothing` for `vertical_gap`; a
   weighted row shares what the gaps leave. The settings tab puts 0 above a
   description and 12 between two settings; the appearance tab puts 0 above a
   description and the section gap of the widget theme between two fields. The
   combined tests give 1330 pass, and the images of all 105 examples stay equal.
