# A text that a widget draws is read like a text

**Status (2026-11-13): in progress.** The owner decided E1 and E2, and approved
the plan for implementation ("good, go", 2026-11-13), so P1 to P8 are approved
with the plan.

**Goal:** a person can select in a text that a widget draws, such as the path
"/home/projectured/workspace/inet-cpp" of a project card: put the caret with the
mouse, move it with the keys, select a range with the mouse and with the keys,
and copy it. The text stays read-only. The behavior is written once, in the
helpers that every such widget shares, and the keys come from the one key table
of the text domain.

**Repository:** projectured-julia. No file that the plan changes is sealed
(`SEALING.md` seals only kernel files, and the plan changes none).

**Branch:** `innermost-click`, in the worktree
`../projectured-julia-innermost-click`, after the pause of step 6 of
[a-click-reaches-the-innermost-part-in-every-view.md](a-click-reaches-the-innermost-part-in-every-view.md).

## 1. The request

The owner, on the caret that a click puts into the text of a label (2026-11-13):

> hmm, just having the caret is not very good, can't navigate with cursor,
> cannot select a range, cannot copy-paste. We should reconsider the plans. This
> would be desirable to have but we should not reinvent the text domain
> everywhere.

> No, I don't necessarily want to allow editing all strings, so don't replace
> them with a text view or whatever.
>
> just selection with mouse, navigation with cursor, range selection with both,
> copy with clipboard would be nice. But I don't want to repeat the all of this
> behavior in every place. That would be bad.

## 2. What exists

- **The widgets that record their text.** The label, the badge, the avatar, the
  alert, the card (its title and its description) and the group of facts draw
  their text themselves and record each line that they draw as a
  `DrawnTextLine`: the text element, the part of the input that it shows, such
  as `.content`, and the character where the line starts
  (`source/platform/widget/DrawnTextLine.jl`). They share the helpers
  `_read_drawn_text`, `_map_drawn_text_forward`, `_map_drawn_text_backward` and
  `make_drawn_selection_elements`, which draws the caret and the band of the
  part selected as a whole.
- **A click puts the caret.** A plain click on such a text puts the caret at the
  character (`.content{k}`), and an Alt+click does it in every widget (D10 of
  the plan of the click).
- **A key reaches the widget and is lost.** The containers give a key to the
  widget that holds the selection. `_read_drawn_text` reads a press and a move
  only, so the key gets no answer.
- **The one key table of the text domain.** `@gestures TextBlock`
  (`source/platform/text/TextDocument.jl`) moves the caret by a character and by
  a word, extends a range with Shift, goes to the start and the end of the text
  with Ctrl+Home and Ctrl+End, and selects all with Ctrl+A. It also types,
  removes and indents. Home, End, Up, Down, Page Up and Page Down need the
  places of the lines, so the reader of `TextToGraphics` answers them, not the
  table.
- **The mouse in a text view.** A plain press puts the caret and starts a drag
  (`StartDragOperation`); each `DragMove` and the `DragEnd` move the moving end
  of the range. Shift with a press or a click extends the range.
- **The drags that a widget uses.** A tab moves when a person drags it, a list
  that offers it moves an element, a slider moves its thumb, and a divider
  moves.
- **The clipboard.** A selection `<document>.<field>{a:b}` whose field holds a
  text is a text target (`_find_text_target` in
  `source/platform/clipboard/Clipboard.jl`); a copy reads its characters. Not
  yet run on a label.
- **A table keeps its grid keys.** When the caret is inside the text of a cell,
  the table gives a plain arrow to that text and moves between cells only from
  a whole cell (`_wt_key_navigate`). For a read-only cell, the key is lost today.

## 3. Decisions

- **E1 (owner, 2026-11-13). The keys come from the one table.** On each key,
  the shared helper makes a short-lived text block of the string of the part
  that holds the caret. Nothing draws the block and nothing keeps it. The helper
  gives it the caret or the range, asks the key table what the key does, and
  maps the new caret or range back to the part, `.content{a:b}`. An answer that
  edits, such as a typed letter, a removal, a break, an indent or a style, is
  dropped, so the text stays read-only. The owner chose this over a key table of
  its own for strings: "let's go with option A then". Rejected: a second table
  that copies the rules (they drift apart; D1 of the one text domain plan, "There
  should only be one text domain"); the rules moved into functions of a plain
  string that two tables call (more work in the text domain, and two lists of
  keys).
- **E2 (owner, 2026-11-13). A range with the mouse keeps the existing drags.** A
  plain drag over a widget text selects a range, unless the part around it uses
  the drag, as a tab, a movable list element, a slider or a divider does; there
  the drag keeps its meaning. An Alt+drag always selects a range in a widget
  text, as an Alt+click always puts the caret. Shift with a click extends the
  range. The owner: "yes, keep the meaning of existing drags, so option A, I
  agree". Rejected: only an Alt+drag makes a range (a drag over a paragraph of a
  card would select nothing).
- **P1 (proposed by the assistant; approved with the plan, 2026-11-13). One place.** The keys, the drag and the
  drawing of a range go into the shared helpers of the widget slice:
  `_read_drawn_text` reads a key and a drag as well as a press, and
  `make_drawn_selection_elements` draws a range. Each widget that records its
  lines gets the behavior from them, and a widget with a reader of its own (the
  card, the group of facts) calls the same helper for a key and a drag. No widget
  holds a rule of its own for a key. Rejected: a rule in each widget.
- **P2 (proposed by the assistant; approved with the plan, 2026-11-13). The string of a part.** The block holds the
  string that the part shows, one line for each line of the string, so the flat
  place of a character in the block is its place in the string (a break counts
  one in both). A caret or a range of the part is `part{a:b}`, the form that a
  click already gives. A key moves the caret only inside the part that holds it;
  it does not cross to another part of the same widget, such as from the title
  of an alert to its description. Rejected: one block of every line that the
  widget draws (the parts are different fields, and a range across them has no
  path).
- **P3 (proposed by the assistant; approved with the plan, 2026-11-13). The keys that need the places of the
  lines.** Home and End go to the start and the end of the drawn line of the
  caret, and Shift with them extends the range. Up and Down move the caret to
  the nearest character of the drawn line above or below, by the records of the
  lines; on the first line Up, and on the last line Down, give no answer, so the
  key goes on to the container, which moves its row. Page Up and Page Down give
  no answer. Rejected: no Home and End (a person expects them); the geometry
  half of `TextToGraphics` (it reads the places of a printed text block, which a
  widget text does not have).
- **P4 (proposed by the assistant; approved with the plan, 2026-11-13). The drawing of a range.** A range draws a
  band behind its characters on each line, in the color of the band of a whole
  part, and draws no caret. Rejected: a caret at the moving end as well (the text
  view draws none on a range).
- **P5 (proposed by the assistant; approved with the plan, 2026-11-13). The drag.** A plain press on the text puts
  the caret and starts a drag, as the text view does, unless the widget is a
  control (it has bindings of its own) or a container around it claims the
  press for a drag of its own. An Alt press always starts the drag of a range.
  `DragMove` and `DragEnd` move the moving end to the nearest character of the
  part. How a container claims its drag before the text is the first finding of
  step 3, recorded here then.
- **P6 (proposed by the assistant; approved with the plan, 2026-11-13). The copy.** Ctrl+C on a range copies its
  characters through the text target of the clipboard. Where the clipboard does
  not do it for a widget, the fix goes into the clipboard rule, not into the
  widgets. Ctrl+X and Ctrl+V do nothing on a read-only text.
- **P7 (proposed by the assistant; approved with the plan, 2026-11-13). The controls.** After the behavior works in
  the widgets that record their lines, the controls record the line of their
  text too: the button (stash `3f8923c5d` holds its start), the toolbar item,
  the segment of a toggle group, the name of a menu, the link and the title of a
  tab. On a control a plain click acts (D9), so only an Alt+click puts the caret
  and only an Alt+drag selects a range.
- **P8 (proposed by the assistant; approved with the plan, 2026-11-13). The guides.** The keyboard and mouse guide,
  the gestures guide and the guides of the widget and the text describe the
  selection in a widget text.

## 4. Steps

One commit for each step. Each step runs the narrowest tests of what it
changes: `test_widget_label_caret()`, the widget sets of the changed widgets,
`test_text()` where the text table is read, and the clipboard sets where the
copy changes.

- [x] 1. **The keys (E1, P1, P2, P3).** `_read_drawn_text` answers a key on the
  part that holds the selection through the short-lived block and the table, and
  the line records for Home, End, Up and Down. Tests: Left, Right, Shift with
  them, Ctrl with them, Home, End, Ctrl+A and Up and Down in a label of two
  lines, and a typed letter that changes nothing.

  Done (2026-11-13): `read_drawn_text_key(drawn, widget, event, measure)` in
  `DrawnTextLine.jl`, exported with the other helpers of the drawn lines, and
  `_read_drawn_text` calls it after the bindings, so the label, the badge, the
  avatar and the alert take the keys. It reads the string of the part from the
  widget (`try_evaluate_reference`), because a drawn line can be cut with "…".
  The kernel range step keeps the moving end (`direction`), so Shift extends
  from the anchor. A part selected as a whole is the range of all its
  characters, so Left and Right give the caret at its start and its end (as D10
  in a code view), and Up and Down on it go on to the container. A key that the
  table answers with an edit gives `nothing`, so it goes on: Return reaches the
  list around a label. `test_widget_label_caret` 61, and 11 widget, table, tab
  and menu sets and `test_dataframes` 622 pass.
- [x] 2. **The drawing of a range (P4).** `make_drawn_selection_elements` draws
  the band of a range. Test: the band covers the characters of the range on
  each line.

  Done (2026-11-13): `_make_drawn_bands` draws a band behind the characters
  that a range holds on each line, by the caret offsets of the line, and the
  band of a whole part as before; a range draws no caret.
  `test_widget_label_caret` 63, `test_widget_card_fold` 77 and
  `test_widget_fact_group` 55 pass.
- [x] 3. **The mouse (E2, P5).** A press and a drag, Shift with a click, and an
  Alt+drag. Tests: a drag over a label selects a range; a drag of a tab and of
  a movable list element keeps its meaning; an Alt+drag on a tab title selects
  a range.

  Done (2026-11-13): `read_drawn_text_pointer(drawn, canvas, widget, event,
  measure; control)` in `DrawnTextLine.jl`: a left press gives the caret, or
  with Shift the moving end there, and `StartDragOperation`; `DragMove` and
  `DragEnd` move the moving end to the nearest character of the part, also off
  the text (`_find_nearest_drawn_caret`), and the anchor stays
  (`_extend_drawn_selection`). A press with Alt reads no binding. A control (a
  label with bindings of its own, as a chip) starts the drag only with Alt.
  `_read_drawn_text` also takes a click with Shift.

  Found: the drags of the containers keep their meaning with no extra code. A
  list that moves its elements does it in `DraggingProjection`, a wrapper that
  takes the left press before the content reads it, and a tab, a divider, a
  slider and the right edge of a table header take a press on their own surface
  before or beside a child. The test of the edge of a header expected no drag
  at all from a press on the text of a header; it now expects no drag of the
  width, and the drag of a range in the header text, as E2 says (a header uses
  no drag away from its edge). A title of a tab is drawn by the tabbed pane, not
  by a label, so the Alt+drag on it waits for the controls (step 6).
  `test_widget_label_caret` 73, `test_widget_table_list` 263, the drag sets
  (`test_drag_tracking` 60, `test_pane_drag` 259, `test_split_pane_drag` 43
  with its 5 known broken), `test_dragging` 23, `test_dataframes` 622 and 11
  widget sets pass; `test_application` fails only at its known `:1013`.
- [x] 4. **The copy (P6).** Ctrl+C on a range of a label through the clipboard
  of the window. Test: the clipboard holds the characters of the range.

  Done (2026-11-13): the copy needed no code: the text target of the clipboard
  takes a range of the field `content` of a label and copies its characters to
  the slice and to the system clipboard. A paste and a cut wrote into the label
  before, because a label accepted pasted text; the read-only widgets of
  `_is_read_only_text` (the label, the badge, the avatar, the alert) now answer
  `accepts_pasted_text` with `false`, the hook that the clipboard reads for a
  document whose text a paste must leave alone. The title and the description
  of a card are fields of a card, which holds other documents too, so this hook
  can not protect them without refusing a paste into the card's content; step 5
  records how they stay read-only. `test_clipboard` fails only at its known
  `ClipboardTest.jl:502` to `:504`; the new checks of a label pass.
- [x] 5. **The card and the group of facts (P1).** Their readers call the
  helper for a key and a drag.

  Done (2026-11-13): the readers of the card and of the group of facts call
  `read_drawn_text_key`, `read_drawn_text_pointer` and a new shared helper of a
  click, `find_drawn_click_selection` (the caret, or with Shift the range from
  the anchor), which the label uses too, so the rule of a click with Shift is
  written once. A card with bindings of its own starts the drag of a range only
  with Alt. A paste: the card, the group of facts and a fact hold other
  documents, such as a form, so the document rule of step 4 would refuse a
  paste into them too. The clipboard reads a field form of the same hook,
  `accepts_pasted_text(document, field)`, for the document that holds the text
  (default: the document rule); the card answers `false` for `title` and
  `description`, the group for `title`, and a fact for `label` and `value`.
  `test_widget_card_fold` 83, `test_widget_fact_group` 62,
  `test_widget_label_caret` 73, `test_dataframes` 622 and 9 widget, pane and
  task sets pass; `test_clipboard` and `test_application` fail only at their
  known lines; the naming guard passes.
- [ ] 6. **The controls (P7).** One commit for each group of controls.

  The button, done (2026-11-13): the button records the line of its label as
  the part `.action.label` (`_build_button`, from stash `3f8923c5d`), draws the
  caret and the band (`_make_drawn_text_canvas`), and maps them both ways. Its
  reader gives an event to `_read_control_text` first: an Alt+click gives the
  caret, a press with Alt starts the drag of a range, a key moves in the label
  while the selection is there, and a drag moves the range. A plain press acts
  and does not look pressed with Alt. A command (`Action`) refuses a paste. Two
  tests follow E2 and D10: an Alt+double click on the text of a button selects
  the label of its action, the innermost part (Alt+Up reaches the button); the
  pointer test counts only the drag of the width of a column, not the drag of a
  range in the header text. `test_widget_label_caret` 86, `test_widget_selection`
  119, `test_part_pointer_shape` 32 and 15 widget, button, toolbar, window and
  pointer sets pass.

  The toolbar item (a1ba2cab0), the segments of a toggle group (da9d9712c)
  and the link (1b2c109d1), done (2026-11-13) by a Sonnet agent on the pattern
  of the button and checked: each records its text (`.action.label` when the
  item has no icon; `.options[i]`, also in the step look; `.content` of a text
  face), draws the caret and the band, maps both ways, gives an event to
  `_read_control_text` first, and refuses a paste (`Action`; the field
  `options`; the field `content` of a link). `test_widget_label_caret` 129,
  `test_widget_toolbar` 84, `test_widget_link` 48, `test_chart` 562 and
  `test_sequencechart` 476 (they build a toolbar item), `test_clipboard_edits`
  34 pass; `test_clipboard` and `test_application` fail only at their known
  lines.

  Found: a copy of a range of an option of a toggle group takes nothing,
  because the text target of the clipboard needs a field step before the range,
  and an option is an element of a vector (two range steps). A key on an option
  selected as a whole answers nothing, because `_split_part_range` reads the
  element step as a range of `.options`; the caret and the range of an option
  take the keys.

  Open: the items of a menu and the names of a menu bar. `WidgetMenuItem` has an
  IO map of its own with children (its label can be a widget), measures its size
  in a cell apart from the cell that draws, and draws the text of a shortcut;
  it needs its own design of where the records live. The guides say that these
  take no caret.
- [x] 7. **The guides (P8)** and a run of the click test over the catalog.

  The guides, done (2026-11-13): `widget.md` describes the shared helpers, the
  paste rules and the controls; `keyboard-and-mouse-guide.md` how a person
  selects in a text that the editor shows; `text.md` that a widget text takes
  the keys of the table; `domain.md` and `operation.md` the field form of
  `accepts_pasted_text`.

  Run 5 of the click test over the catalog (2026-11-13, scratchpad
  `step6/run5`): 3166 lines in 301 of 546 examples, against 3194 in run 4. An
  Alt+click with no caret falls from 968 to 692 lines, and a plain click that
  does nothing from 232 to 200. A move that names another part than the
  Alt+double click rises from 611 to 889: on a control the move names the
  control as a whole, so it lights, and the Alt+double click selects the text in
  it, the innermost part. That is the design of P7, so the click test must take
  a control as the part of its move; this goes to the click test, step 8 of the
  plan of the click. `test_documentation` fails only at the 3 private names that
  main has.
