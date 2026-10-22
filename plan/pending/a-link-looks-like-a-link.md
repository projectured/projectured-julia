# A link looks like a link

Status: PENDING, 2026-10-22. Not started.

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

The gestures are a `@gestures WidgetLink` table. `read_bound_gesture` reads the
table of the type, so the gesture help lists the gestures of a link.

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
1. [ ] **`WidgetLink`.** Add the document, the printer, the `@gestures` table,
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
2. [ ] **The platform links.** Replace the buttons in the table "Who uses it",
   except the research link. Test: `test_explorer()`, `test_task_views()`,
   `test_roster_table()`, `test_roster()`, `test_document_tree()`,
   `test_navigator_gestures()`, `test_work_plan()`, `test_agent_work()` and
   `test_background_work()`. A link changes the height of a roster row, so run
   `test_dataframes()` too.
3. [ ] **The research links.** Add `find_navigator_address(::ResearchStudy,
   item)`, and draw each link of a card as a `WidgetLink`. Test:
   `test_research()`, with a new case: a click on a link of a card opens the
   linked item at its place in the study, and Ctrl and a click open it in a new
   tab.
4. [ ] **The guides and a live check.** Update `widget.md` (the link and the
   open gestures), `roster.md`, `explorer.md`, `navigator.md` ("The open of a
   page"), `research.md`, `reference.md` (a walk stops at an address) and
   `keyboard-and-mouse-guide.md`. In a live SDL window, take pictures of the
   page "Open files" and of the page of a folder. Check that a row is as tall as
   a row of labels, the link colour at rest, the underline under the pointer,
   and the link colour in a selected row. Then click a link, Ctrl and click a
   link, and middle click a link. Move this plan to `plan/done/`.

## Not in this plan

- An underline for a markdown link or an rst reference. The text layer draws
  them, and a text style has no underline.
- A link in a column of a roster other than the first.

## Open items

None. The edits of `keyboard-and-mouse-guide.md` that were not committed when
this plan was written landed in `97fec96a3`.
