# A link looks like a link

Status: DONE, 2026-10-22, on the branch `widget-link`, in the worktree
`projectured-julia-widget-link`. Not landed on `main`.

## The ask

The owner, 2026-10-22: "is there a link support in the projectured-julia
navigator which renders like a typical link in a browser? [...] it would be nice
to have links in the navigator which could be just clicked and navigated
forward. Like the first cell in a table row with a single link click (as opposed
to a double click on the table row) and then the user could navigate back using
the navigator. Ctrl+click could open a new tab pane. Also, when a link is
clicked in a normal (non-navigator) tab pane, what should happen? I guess it
should open a new tab in this case."

A survey answered the question. On 2026-10-22 the owner agreed to three
proposals:

1. Close the pending plans `document-locator.md` and `document-link-feature.md`.
2. Add a `WidgetLink` to the widget slice. It draws its text in the link
   colour, with an underline while the pointer is on it, and the hand pointer.
   A click or Return opens the page here. Ctrl and a click, or a middle click,
   open it in a new tab. It replaces the copies of the link button.
3. A click on the name cell of a roster row opens the page and does not select
   the row.

Proposal 3 is done: the branch `open-files-roster` landed on main on
2026-10-22, with the plan
[the-first-column-of-a-roster-is-a-link.md](../done/the-first-column-of-a-roster-is-a-link.md).

## What is there

On main at `56d233ff1`:

- **The open.** A link answers `OpenPageOperation(document, reference, place)`.
  The nearest navigator takes `:here` as a new visit, so Back returns. In a tab
  with no navigator, the editor opens a new tab with a navigator on the page.
  This plan does not change the open.
- **The link.** `make_open_page_gestures(document, reference; domain)` in
  `source/platform/widget/OpenPageOperation.jl` makes two bindings: a click
  opens the page here, and Ctrl and a click open it in a new tab. A link is a
  `WidgetButton` with these gestures: on the page of a section and of its
  search, on the page of a folder, in the Tasks pane, and in the first cell of a
  roster row (`_make_item_link`).
- **Two links of their own.** `_make_blocker_part` of the work plan and
  `_make_agent_work_link` of the agent work bind `MouseClickPattern(:left)`
  with no modifier list, which matches every modifier. So Ctrl and a click open
  the page here.
- **No research link.** The card of a research item shows each link of the
  item as a muted `WidgetLabel`. A click on it does nothing.
- **Markdown and rst.** A link in the rendered view has the link colour, the
  hand pointer and a tooltip with its target. A click follows it, and Ctrl and a
  click open a new tab.

## The problem

1. **A link draws as a button.** It has a frame, a shadow and padding, so a row
   with a link is taller than a row of labels. The live check of the roster
   plan showed this on the page "Open files".
2. **Links act in three ways.** Ctrl and a click on a step link or on a part of
   the agent work open the page here, not in a new tab. A research link does
   not open.
3. **No link takes a middle click or a key.** No binding reads
   `MouseClickPattern(:middle)`. Return on a link button runs the empty action
   of the button, so nothing opens.
4. **Nothing says that a part is a link.** A link is a button with gestures, so
   a reader of the widget tree can not tell a link from a command, or find
   where it leads.

## The model

### `WidgetLink`

`WidgetLink(content, target; icon, tooltip, position, visible, margin, border,
padding, style)` is a widget document in `WidgetDocument.jl`.

- `content` is what `WidgetLabel` takes: a string, a cell, or a function of no
  arguments for a text that follows a value.
- `target` is where the link leads, in one of two forms:
  - A `DocumentLocator(document, reference)` names the part at `reference` from
    `document`. The open is `OpenPageOperation(document, reference, place)`.
  - A `Reference` is a path from the link itself, as the path form of the
    open. `EmptyReference()` opens the part that the link shows, and a reader
    above maps it, as the roster rows map the path of a cell to the item of the
    row.
- `icon` is an icon name before the text, as the page of a folder shows it.

`WidgetLinkToGraphicsCanvas` in `WidgetToGraphics.jl` draws it:

- The text is in the colour `link` of the widget theme. `WidgetTheme` gets the
  field `link::ThemeColor = ColorRole(:link)`. The colour theme has that role
  already.
- A link has no frame, no padding and no shadow, so it is as tall as a label.
- While the pointer is on the link, a rect of the link colour lies under the
  base line of the text. Its size reads the mouse target, as the hover layer of
  a button does (`_push_hover_layer!`). So a move onto the link paints the rect
  again, and nothing else.
- The pointer is the hand over the link.

The gestures are the table of the type, `get_document_gesture_bindings_own(::Type{WidgetLink})`,
which is how the widget slice declares the gestures of its types.
`read_bound_gesture` reads the table of the type, so the gesture help lists the
gestures of a link, and a link also has the tooltip of every widget.

| Gesture | Effect |
| --- | --- |
| click | open the page here |
| Ctrl and a click | open the page in a new tab |
| middle click | open the page in a new tab |
| Return | open the page here |

The SDL backend sends `:middle`, and the click recognition makes a
`MouseClick(:middle, ...)` for it. Tab stops at a link
(`is_focusable_document`), as it stops at the button that a link is now, so
Return reaches it. `make_interface_api` lists `WidgetLink` beside
`WidgetButton`, so the assistant finds it.

### A `DocumentLocator` is an address

The walk of a document goes into the fields of every value that is not a leaf
(`_is_walk_leaf` in `source/kernel/document/DocumentWalk.jl`). So a walk would
go from a link into its target, and a search would find the target below the
link. `is_walk_opaque(::DocumentLocator) = true`, in `ReferencedDocument.jl`
beside the struct, stops a walk at an address. No document stores a
`DocumentLocator` today, so no walk that runs now changes.

### One list of the open gestures

`make_open_page_gestures` stays for a button whose label is a command that
opens a page, such as "Open the task page" and "Open stdout". It gets the middle
click and Return too, so such a button opens a page the same way a link does.
`WidgetLink` and `make_open_page_gestures` make their bindings from one private
list.

### Who uses it

| Place | Now | After |
| --- | --- | --- |
| `_make_section_link`: the page of a section, the matches of a search | button | `WidgetLink(text, DocumentLocator(section, reference))` |
| `_build_folder_row`: the page of a folder | button with an icon | link with the icon |
| Tasks: the title of a group in a row of a list (`TaskGroupToWidget.jl`), and in `TaskPagesToWidget.jl` "in" and the group, the number of an execution, the text of a link record | button | link |
| Tasks: "Open the task page", "Open" and a name, "Open the group" | button | stays a button: a command |
| `_make_item_link`: the first cell of a roster row | button, path form | `WidgetLink(content, EmptyReference())` |
| `_make_blocker_part`: "step" and an id in the work plan | button | `WidgetLink(text, DocumentLocator(plan, reference))` |
| `_make_agent_work_link`: a part of the agent work | button | `WidgetLink(text, DocumentLocator(work, reference))` |
| The card of a research item: each link of the item | label | `WidgetLink(text, DocumentLocator(linked, EmptyReference()))` |

### A research link opens the item at its place

The card of an item has no study: the header of `ResearchToWidget.jl` says "The
card of an item needs no study". So a link names the linked item itself. The
research slice adds `find_navigator_address(study::ResearchStudy, item)`: the
place of the item in the list of its kind, found by identity, as
`_make_study_item_part` finds it. A navigator whose content is the study then
opens the item with its address and its parent. An explorer section asks each
of its entries, and `start_study!` adds the study to the explorer, so an open
from a plain tab finds the place too. "Open as a page" on an item also opens it
at that place.

### What stays

- A double click on a row or on a node still opens it: a roster row, a node of
  a tree, the number of a row of a data frame.
- A data frame gets no link. The number of a row selects the whole row for a
  move or a delete, and a data frame has no column that names its row. The rule
  of the roster plan, which the owner approved, keeps the double click there.
- A markdown link and an rst reference stay text of the text pipeline.
- `OpenPageOperation`, the navigator, and the open from a tab with no navigator
  do not change.

## Decisions

- **A link keeps its target as a `DocumentLocator`.** My decision. It is the
  pair of `OpenPageOperation`, and the kernel already names it "the address of
  a document". A field that held the document itself would put the target into
  the tree of the link, because the selection walk enters a field that holds a
  document. A locator is a plain value, and step 1 makes every walk stop at it.
- **The underline shows only while the pointer is on the link.** The owner
  agreed on 2026-10-22. The colour and the hand pointer say "link" at rest.
- **The mouse target goes to the innermost part.** The owner, 2026-10-22, when
  the live check of step 4 showed no underline on the page of a section and in
  a roster: "the mouse target should go to the innermost element, that's a
  principle. why would anybody swallow it? what if a large table cell contains
  some complex stuff? the mouse target should go deep in, the table can still
  highlight under the mouse" and "the link should always highlight". So every
  page that holds a link gives the link its part of the mouse target, and the
  roster keeps the cell in its mouse target. Step 4 does it.
- **A link has no tooltip of its own.** My decision, which changes the survey:
  the survey said that a link shows its target in a tooltip. The target is a
  path from a document, such as `entries[2]`, which says little to a person.
  The caller that knows the target gives the words, as the page of a section
  gives the note of an entry now.
- **A command stays a button.** My decision. A label that names an action, such
  as "Open stdout", is a button. A label that names the target, such as a
  title, is a link.
- **A link in a selected row keeps its colour.** My decision. It answers the
  open item "How a link looks in a row that the person selected" of the roster
  plan. The live check of step 4 looks at the contrast on the band of the
  selection.

## Steps

Do the work in the worktree `projectured-julia-widget-link`, on the branch
`widget-link` from main at `56d233ff1`. Before you edit a kernel file, check its line in
`SEALING.md` again: on 2026-10-22, `reference/ReferencedDocument.jl` is not
sealed.

0. [x] **Close the two plans.** `document-locator.md` and
   `document-link-feature.md` are in `plan/obsolete/`, each with a status line
   that says why. Done 2026-10-22 on the branch `widget-link`.
1. [x] **`WidgetLink`.** Add the document, the printer, the gesture table,
   the theme field `link`, the focus method, the export and the entry in
   `make_interface_api`. Add `is_walk_opaque(::DocumentLocator)`. Make one
   private list of the open gestures, and give `make_open_page_gestures` the
   middle click and Return. Add `test/platform/projection/WidgetLinkTest.jl`
   with `test_widget_link()`, and add it where `test_widget_button_behavior()`
   is listed. Its cases: the open of each gesture for each form of the target,
   the link colour, no frame, the height of a label, the underline only under
   the pointer, the hand pointer, Return on a link with the focus, and a walk
   that stops at a locator. Test: `test_widget_link()`,
   `test_widget_button_behavior()`, `test_open_page_operation()`,
   `test_referenced_document_editor()` (a new docstring can move the rank of a
   search of the interface), and the naming guard. Run the tests in a fresh
   process, because the dispatch table of the widgets is built once.
   **Done 2026-10-22.** What the step found and decided:
   - The document is in `WidgetDocument.jl`, the printer
     `WidgetLinkToGraphicsCanvas` in `WidgetToGraphics.jl`, and the gestures in
     `OpenPageOperation.jl`: `_make_open_page_bindings(open; domain)` makes the
     four bindings, and both `make_open_page_gestures` and the table of
     `WidgetLink` (`_WIDGET_LINK_BINDINGS`, domain "widget") call it.
   - The reader of a link calls `read_bound_gesture`, as the reader of a button
     does. It answers no mouse down, because a link has no pressed state.
   - The underline is `max(1, border_width)` thick, one thickness below the
     baseline of the text, and as wide as the text.
   - `find_first_baseline` of a link gives the baseline of its text, so a row
     that aligns its parts on the baseline aligns a link as it aligns a label.
   - The icon of a folder is a glyph, so it draws as a second `GraphicsText`.
   - Pass: `test_widget_link()` 27 of 27, `test_widget_button_behavior()` with
     no failure, `test_open_page_operation()` 92 of 92,
     `test_referenced_document()` 63 of 63, `test_referenced_document_editor()`
     111 of 111, and the naming guard.
2. [x] **The platform links.** Replace the buttons in the table "Who uses it",
   except the research link. Test: `test_explorer()`, `test_task_views()`,
   `test_roster_table()`, `test_roster()`, `test_document_tree()`,
   `test_navigator_gestures()`, `test_work_plan()`, `test_agent_work()` and
   `test_background_work()`. A link changes the height of a roster row, so run
   `test_dataframes()` too.
   **Done 2026-10-22.** What the step found and decided:
   - The private helper of the task pages that made a link button is
     `_make_open_button` now, renamed with `julia-rename.jl`, because it makes
     only the buttons of a command: "Open stdout", "Open stderr" and "Open the
     group". `_make_task_link` makes the links: "in" and the group, the text of
     a link of a kind, and the number of an execution.
   - A review of the diff found that a long research link did not break at the
     edge of the card, as the label that it replaces did. So a link breaks its
     text where a label breaks it (`_text_lines`), with a line under each line,
     and a text with a line break draws as several lines. A new case of
     `test_widget_link()` checks it.
   - The title of a group in a row of the Tasks pane, and "in" and the group on
     the page of a task, are functions, so the link follows a new title.
   - No test found a link by the type `WidgetButton`. The tests press the drawn
     text, so they pass with no change.
   - Pass: `test_widget_link()` 31 of 31, `test_explorer()` 267 of 267,
     `test_task_views()` 70 of 70, `test_task_pages()` 48 of 48,
     `test_roster_table()` 28 of 28, `test_roster()` 63 of 63,
     `test_document_tree()` 130 of 130, `test_navigator_gestures()` 26 of 26,
     `test_work_plan()` 83 of 83, `test_agent_work()` 158 of 158,
     `test_background_work()` 21 of 21, `test_open_page_operation()` 92 of 92,
     `test_widget_button_behavior()` with no failure, and `test_dataframes()`.
3. [x] **The research links.** Add `find_navigator_address(::ResearchStudy,
   item)`, and draw each link of a card as a `WidgetLink`. Test:
   `test_research()`, with a new case: a click on a link of a card opens the
   linked item at its place in the study, and Ctrl and a click open it in a new
   tab.
   **Done 2026-10-22.** The line of a link is a row of the word of the link, a
   muted label, and the linked item as a `WidgetLink` with the id and the text
   of the item. `describe_research_link` keeps the whole line as text for the
   assistant. `find_navigator_address(::ResearchStudy, ::ResearchItem)` is in
   `ResearchEdits.jl`, beside `find_study_item`. Pass: `test_research()` 238 of
   238.
   **Rebased onto the remote main 2026-10-25.** The remote rewrote the study as a
   quiet outline (`67db30f43`), which replaced the card of an item. A link of a
   row there is a chip of the outline that selects the linked item. The owner
   kept the remote version, so the rebase dropped the research code of this step
   and the research part of step 4: no `WidgetLink` in a research row and no
   `find_navigator_address(::ResearchStudy, ::ResearchItem)`.
4. [x] **The mouse target reaches every link.** Added 2026-10-22 by the owner's
   decision above. The first live check showed where the path of the part under
   the pointer stops:
   - On the page of a section and of its search, the path reaches the link as an
     introduced path of the page, but the page wires the mouse target of its
     root only (`set_output_path_computations!`), so no widget below the root
     gets its part. The page wires its tree, and each card that it computes
     later, when it makes the card.
   - In a roster the path stops at `rows[k].item`: the backward map turns a cell
     that holds no document into the item of the row, for the selection and the
     menu of the item. For the mouse target the rows answer the item and, below
     it, the cell as a part that the rows draw, an introduced step, as
     `.elements[2]‹.open{0}›` names a bracket that a view draws for an element.
     So the navigator still reads the item as the document under the pointer,
     the table lights the row, and each cell that the rows make reads its part
     from the mouse target of its row.
   - The card of a research item, the page of a step and the page of the work of
     an agent: a test shows whether the link gets its part, and the page is
     wired when it does not.
   Test: a new case in the test of each page: a move onto a link draws the line
   under it. Then `test_roster()`, `test_roster_table()`, `test_explorer()`,
   `test_navigator_gestures()`, `test_research()`, `test_work_plan()`,
   `test_agent_work()` and `test_dataframes()`.
   **Done 2026-10-22.** What the step found and decided:
   - The roster: `_map_mouse_target_backward` answers a cell of text with
     `[r].item‹[c]›`, a `ProjectionReferenceStep` of the rows below the item,
     and `_map_rows_forward` maps it to `cells[k][c]` of the table. The
     selection, the open and the menu still read the item. Each cell that the
     rows make computes its own mouse target from the mouse target of its row
     (`_follow_cell_mouse_target!`), so a cell that a table makes again later
     follows too, which a walk at print time does not give.
   - The page of a section and of its search follow the mouse target down their
     tree (`follow_output_mouse_target!`), and each card or table that the body
     computes later follows it when the body makes it
     (`_follow_body_child_mouse_target!`).
   - The page of a folder of a workspace wired the mouse target of its root
     only; it follows it down its tree now, as the page of any other folder did.
   - The card of a research item registers each line of a link and its link as
     containers at their places, so `_route_research_paths!` gives them their
     paths.
   - The page of a step and the page of the work of an agent passed the mouse
     target to their links already: their new cases passed with no change.
   - A test predicate `is_link_text_underlined(canvas, text)` in
     `WidgetLinkTest.jl`, exported by the platform test package, finds the line
     under a drawn text. The roster, the explorer, the step, the work of an
     agent and the research tests use it.
   - `test_dataframes()` was not run again: no file of this step draws a data
     frame or changes a layout.
   - Pass: `test_widget_link()`, `test_roster_table()`, `test_work_plan()` and
     `test_assistant_work()` (the log of that run was cleaned before its counts
     were read), `test_explorer()` 273 of 273, `test_document_tree()` 130 of
     130, `test_navigator_gestures()` 26 of 26, `test_roster()` 63 of 63,
     `test_background_work()` 21 of 21, `test_research()` 240 of 240.
5. [x] **The guides and a live check.** Update `widget.md` (the link and the
   open gestures), `roster.md`, `explorer.md`, `navigator.md` ("The open of a
   page"), `research.md`, `reference.md` (a walk stops at an address) and
   `keyboard-and-mouse-guide.md`. In a live SDL window, take pictures of the
   page "Open files" and of the page of a folder. Check that a row is as tall as
   a row of labels, the link colour at rest, the underline under the pointer,
   and the link colour in a selected row. Then click a link, Ctrl and click a
   link, and middle click a link. Move this plan to `plan/done/`.
   **Done 2026-10-22.** The guides: `widget.md`, `roster.md`, `explorer.md`,
   `navigator.md`, `research.md`, `reference.md`, `mouse-target.md` (a new
   section "The innermost part" and the decision of the owner) and
   `keyboard-and-mouse-guide.md`.

   The live check used a script in the scratchpad, built as the script of the
   plan of the open files: the application window with two text files, with
   `SdlBackend` on the display `:0`, and pushed SDL events. What it showed:
   - On the page "Open files", the names draw in the link colour with no frame,
     and the rows are 27 px apart, as rows of labels.
   - In a selected row the link keeps its colour, and it reads well on the band
     of the selection.
   - The first run showed no line under the pointer, on the page of a section
     and in the roster. That is how step 4 came in. After step 4, the pointer on
     `todo.txt` in the roster draws the line under it and lights the row, and
     the pointer on the title "Open files" of a card of the section page draws
     the line under it. The mouse target of the roster ends at
     `.rows[2].item‹RosterRowsToWidget: [1]›`.
   - A click on `todo.txt` opens its page in the same tab (5 tabs before and
     after, and "buy milk" shows). Ctrl and a click open a new tab (3 to 4), and
     a middle click opens a new tab (4 to 5). A Ctrl and a click sent through SDL
     needs a key down of Ctrl first, because a mouse event takes its modifiers
     from the last key event.
   - The page of a folder was not taken in the live window: the tree of Files
     shows the workspace, and the folder needs a double click there. The case of
     `test_explorer()` checks the line under a name of a folder page.
   - The new tab of Ctrl and a click, and of a middle click, opens in front of
     the tab of the link. A browser opens it behind. The open behaved so before
     this plan.
   The naming guard passes.

## Not in this plan

- An underline for a markdown link or an rst reference. The text layer draws
  them, and a text style has no underline.
- A link in a column of a roster other than the first.

## Open items

None. The edits of `keyboard-and-mouse-guide.md` that were not committed when
this plan was written landed in `97fec96a3`.
