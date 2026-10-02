# A setting says what it sets

> **Status:** pending, not started. Written on 2026-10-02 at the owner's
> request, after a discussion of the appearance tab and the settings tab. The
> owner decided D1 to D3; section 5 lists the points that are still open.

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
  `_text_lines` in `WidgetToGraphics.jl`). A `WidgetLabel` draws one line. A
  `GridLayout` has no cell that spans two columns.
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

Each field of both tabs is a block (D1, D2; the form is open, O1):

1. the name of the field;
2. its description, in the small font and the muted color of the widget theme,
   broken at word boundaries to the width of the card;
3. its control, and in the settings tab the reset button beside it.

A field with no description has no line 2. The text drops the Markdown code
marks (the backticks) that some docstrings hold, so `<:` shows as `<:`.

The alternative form keeps the name and the control on one line and puts the
description under both. It is more compact, but the controls of two fields no
longer line up, because a grid can not span the description over both columns.

### 4.2 A label can wrap

`WidgetLabel(content; wrap = true)` breaks its text at word boundaries to the
width that its container offers (`ctx.maximum_width`), with the same
`_text_lines` that the card uses. With no offered width it draws one line, as
now. The default stays `false`, so every label that exists draws as before.

This is a new field of a widget, so it needs the owner's approval (O4).

### 4.3 A card says what it holds

The summary of the type is the description of the card (D3):

- the card of a theme takes the summary of its theme type;
- the card of a settings group takes the summary of its group type, and its
  note ("This editor does not use these settings.") follows on a line of its own
  (O3).

The first paragraph of each theme docstring and of each settings group docstring
becomes a text for a person: one or two sentences that say what the values of
the type change, in the words of the user, with no code mark. The text for a
programmer moves to the paragraphs after it. A writing rule says so, in
`documentation/rule/` and in the guide for a new domain.

The display reads the summary with `compute_docstring_summary`. The help slice
holds it now, and neither tab can reach the help slice without a new edge. It
moves to the documentation tool of the kernel, `tool/Documentation.jl`, which
every slice reaches and which reads docstrings already (O5).

### 4.4 The tooltip

With the description visible, the tooltip of a name says the same text again.
It goes (O2).

## 5. The decision log

- **D1. The description is always visible** (option B). Rejected: the tooltip
  only (A); a panel of the field under the pointer or with the focus (C).
- **D2. The description stands under the name.** Rejected: a third column beside
  the control.
- **D3. The card of a theme and of a settings group says what it holds**, with
  a text that is a part of the documentation of the type, and the display finds
  it there.

Open, with my recommendation:

- **O1. The form of a field.** Recommended: the name, the description, then the
  control (4.1), as the settings of VS Code show them. The other form keeps the
  name and the control on one line.
- **O2. The tooltip of a name goes.** Recommended: yes.
- **O3. The note of a settings card follows the summary** on a line of its own.
  Recommended: yes.
- **O4. `WidgetLabel` takes `wrap`** (4.2). A new field of a widget.
- **O5. `compute_docstring_summary` moves to the kernel** (`tool/Documentation.jl`,
  not sealed). Rejected: an edge from the appearance and the settings-managing
  slices to the help slice, which pulls the syntax and the text slices into the
  settings tab.

## 6. Steps

All the work is in a worktree, and each step is a commit.

- [ ] **S1. A label wraps** (O4). `WidgetLabel(…; wrap)`, its print with
  `_text_lines`, and its measure in a layout. Tests: a long text breaks at word
  boundaries inside the offered width, keeps one line with no offered width, and
  a label with no `wrap` draws as before (the images of all examples equal).
- [ ] **S2. The summary reader moves to the kernel** (O5), with its test; the
  help list calls it there.
- [ ] **S3. The first paragraphs.** The docstrings of the 29 themes and of every
  settings group start with a text for a person. A Sonnet sub-agent writes them
  from a brief; I review each one. The writing rule goes into
  `documentation/rule/writing-rules.md` and the guide for a new domain.
- [ ] **S4. The settings tab** shows the block of 4.1 for each setting and the
  summary on each card.
- [ ] **S5. The appearance tab** shows the block of 4.1 for each field and the
  summary on each card.
- [ ] **S6. Tests of what is drawn.** In both tabs: the description of a field is
  drawn under its name, inside the width of its card, on more than one line when
  it is long; a card draws the summary of its type; a field with no description
  has no line for it. A live window of the application, driven by pushed SDL
  events, opens both tabs, and the owner reviews the images.
- [ ] **S7. The guides**: `appearance.md`, `settingsmanaging.md`, `widget.md`,
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

None yet.
