# A study and a workflow read as one quiet outline, from the empty document to the whole record

> **Kind:** plan · **Status:** pending, written 2026-10-23. The design of §2 is
> agreed with the owner, and the owner agreed to every recommendation of §9 the
> same day ("Agree with all"), with two additions to G5 and G7. The steps are built
> in a worktree beside the repository. · **Stands on:**
> [research.md](../../documentation/package/domain/research/research.md),
> [workflow.md](../../documentation/package/domain/workflow/workflow.md),
> [widget.md](../../documentation/package/platform/widget/widget.md),
> [context-menu.md](../../documentation/package/platform/widget/context-menu.md),
> [domain.md](../../documentation/package/platform/domain/domain.md),
> [explorer.md](../../documentation/package/platform/explorer/explorer.md),
> [a-study-records-questions-evidence-and-decisions.md](../done/a-study-records-questions-evidence-and-decisions.md),
> [a-workflow-records-steps-decisions-and-dates.md](../done/a-workflow-records-steps-decisions-and-dates.md),
> [document-insertion-completion.md](../done/document-insertion-completion.md),
> [a-graph-lights-the-part-under-the-pointer.md](a-graph-lights-the-part-under-the-pointer.md),
> [tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md](tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md)

This plan replaces the views of the Research and the Workflow domains with one
compact notation: a row shows what was written, and one menu on the row holds
every action. It adds elements, a list of documents of any domain that a research
item and a workflow node hold. It builds the parts that other documents can use
too, in the platform: a row that shows its controls under the pointer, a menu that
a button opens and the keyboard drives, and an insertion that shows its
candidates in a popup.

## 1. The request

On 2026-10-23 the owner asked for a study of the documents and the projections of
the two domains, and then for a new design. The words of the owner, in order:

- "The current projections produce a notation which is not good because there are
  two many buttons, too many separate buttons for chevrons, very little styling
  using different font sizes, styles, colours, etc. It often shows not even filled
  information. So it's difficult for the user to process the information."
- "I want a new and consistent, easy to process and visually appealing design. I
  don't know if we need all the buttons being present all the time, that may just
  be too distracting. Maybe editing the invisible parts should be an extra action."
- "hover could immediately show the ... menu and there's no need to explicit
  buttons. These are not clicked that often."
- "we could make the chevron, the kind the ID, the you and time on one side and mor
  compact. We should not write esc to... That's boring."
- "Show the date only when it changes", "Full menu is fine", "The four meta on the
  left could use the vertical space a bit more, no?"
- "We can have both time based and type based view for research." "Can we have a
  one line meta if the text is one line only?"
- "Apply the same compact layout to the research map."
- "the attachments are basically elements, maybe we should call them that. Just
  arbitrary document elements that can added to workflow and research items. Code,
  additional text, tables, plots, etc." "Drop the title, the document's own heading
  is enough."

The request for this plan: "Take care of making changes which are generic in
nature to be also available for other usages. I'm thinking of extending the
document insertion with popup as shown in the design, etc. Take care of what is
already available and reuse if applicable. Ask if some generic behaviour is almost
good but needs to change, it's ok. Design decisions should be asked. At the end we
should have a beautiful UX, which is visually appealing, works from empty document
to a complete workflow or research document, all steps are covered."

## 2. The design

The design is a canvas of nine boards, made in the same conversation:
<https://claude.ai/artifact/Nz24LYAEmT7QMaCPnoy9tp>. The board "Today" draws the
views as the code builds them now. The two outline boards are interactive. The
rules below are the design in words, and each step of §10 names the rules that it
builds.

- **R1. The row.** Every research item and every workflow node is one row of three
  columns: a meta column of 72 pixels, the text column, and a menu column of 24
  pixels. The meta column stacks its parts on the lines that the text takes anyway.
  Line 1 holds the fold chevron, the mark and the id. Line 2 holds the avatar of
  the author (14 pixels) and the local time. Line 3 holds the date, only where the
  day differs from the day of the row above. The card frame of today goes away;
  the gutter, the indent and the white space show the structure.
- **R2. A row of one line.** When the text takes one line and nothing stands under
  it, or when the row is folded, the meta column keeps only line 1. The avatar,
  the time and a changed date follow the text on its line.
- **R3. Type and colour.** The document title is 24/30 bold. A section label is 11
  pixels, bold, in capitals. The text is 15/22 medium, a field is 13/20, a relation
  and the meta are 12. An id is Ubuntu Mono 12 bold, a time Ubuntu Mono 11. Colour
  means a status or the selection, and nothing else: ink, muted, line, hover,
  selection tint, accent (active, the assistant), settled (accepted, done,
  chosen), rejected (rejected, dropped) and parked.
- **R4. The mark.** The mark is the icon of the kind, coloured by the status. A
  decided research item adds a dot to its mark, and a rejected item strikes its
  text, so the status reads without colour too. A step shows its state as a ring:
  open, active (half filled), done (filled with a check), dropped (crossed). An
  option shows open, chosen, rejected or parked; a decision is a diamond.
- **R5. Only what was written.** A field with no value takes no space. A filled
  field is one line that starts with a lowercase word of its meaning: "answered
  by", "decides", "predicts", "because", "but".
- **R6. Relations.** The links out of a row and the links into it stand on one line
  as id chips: "addresses Q1 · rests on S1 · tested by X1 N1 · supported by E1". The
  pointer on a chip shows the text of the item; a press on a chip selects the item.
- **R7. No controls at rest.** The pointer on a row lights it, and shows its fold
  chevron and its "⋯". The "⋯", a press on the mark of a research item, a right
  click and a key open one menu, which holds every action of the row, in one order:
  what changes the status, what adds a linked thing, what changes the view, and
  last the delete. The keys of an action stand beside it. A press on the mark of a
  step opens its four states; a press on the mark of an option chooses it.
- **R8. The selection.** The row that holds the caret has the selection tint and
  keeps its "⋯". The person types in place. A text field shows its box only while
  it holds the caret.
- **R9. Edit all fields.** This item of the menu shows every field of the row, the
  empty ones too, until the caret leaves the row.
- **R10. A decision in the row.** "Accept…" and "Reject…" open a panel in the row:
  Accept or Reject as a pair of toggles, a reason, and Record and Cancel. Record
  writes the decision and the status in one edit.
- **R11. No instruction on the screen.** No "Esc to leave" and no "Enter to keep".
  The keys are in the menus and in the help.
- **R12. The views of a study.** A switch in the header shows the study by kind (a
  section for each kind, empty kinds hidden), by time (a group for each day), or
  as a map. The header holds the title, the counts of the statuses, and the
  question with its answer. The map draws each item as a small form of the row, and
  draws the links of the argument as lines. Accept and reject are no lines: a
  decision lists them as chips, and the pointer on a decision lights its items and
  its lines.
- **R13. The views of a workflow.** The outline is a tree with guide lines. A
  decision says "decided" or "undecided" after its question, and an option its
  reason. The count of the journal entries of a node stands after its title, and a
  press on it opens the entries under the row. The journal is a timeline grouped
  by day with a filter of the kinds. The catalog is a list of the workflows of a
  folder with a bar of the progress of each.
- **R14. Elements.** Every research item and every workflow node holds `elements`,
  a list of documents of any domain: code, text, a table, a chart, a formula sheet.
  Each element draws through the view of its own domain, in a light inset after
  the fields, and edits in place. It has no title; its own heading names it. The
  pointer on an element shows its kind, its own fold and its own "⋯": Fold, Move up,
  Move down, Open in a tab, Copy, Remove. A folded element is one line: its kind,
  its first line and its size. A folded row and a vertex of the map show the count
  of the elements. "Add an element" in the menu of a row opens an insertion field,
  where the person types a kind and picks it from a list.

## 3. What exists (2026-10-23, `main` 56d233f)

Five surveys of the code found the parts below. The words "reuse", "change" and
"missing" sort them.

### 3.1 The insertion of a document

- **Reuse.** `@domain`, `@insertion`, `get_insertion_candidates`,
  `get_insertion_names`, `complete_insertion`, `resolve_insertion`,
  `make_insertion_document` and `append_insertion_operation`
  (`source/platform/domain/Domain.jl`). `InsertionToSyntaxLeaf`
  (`source/platform/syntax/InsertionToSyntax.jl:41-92`) draws "Insert a new ⟨typed⟩
  here", completes on Tab, commits on Enter and cancels on Escape. A
  `DocumentInsertion` inside a widget view draws through the syntax fallback
  (`SyntaxNatural.jl:47-52`), so the same field works inside a row.
- **Reuse.** The candidates come from the type tree, not from a registry: the steer
  of 2026-07-08 in [document-insertion-completion.md](../done/document-insertion-completion.md)
  says "no registry and no constant candidate tables". The explorer narrows the
  candidates with a trait, `is_explorer_entry_type`.
- **Change.** The match is a lowercase prefix of the whole name (`_matching`), so
  "ch" finds "Chart" but not "Sequence chart". The filter takes only the type of
  the place (`find_declared_place_type`), and a list of elements is an untyped
  `CellVector`. Escape leaves a `DocumentNothing`; in a list it must remove the
  element.
- **Missing.** No candidate list is drawn: the only feedback is the pale
  continuation. No seam gives a type an icon or a display name at the level of the
  type. For that reason the explorer opens a menu for Insert, and its design says
  so ([explorer.md](../../documentation/package/platform/explorer/explorer.md),
  "Insert opens a menu").

### 3.2 Menus and popups

- **Reuse.** `make_context_menu_binding`, `OpenContextMenuOperation` and
  `ContextMenuWindowProjection` (`source/platform/widget/ContextMenuWindow.jl:49-170`).
  A menu item answers `EditMenuPartOperation`, which the window lifts through the
  readers of the part, so the history records it. The explorer "+" and the
  navigator crumbs already open a menu from a left click.
- **Reuse.** `NavigatorChoiceList` (`source/platform/navigator/NavigatorDocument.jl:96`,
  its view in `NavigatorChoiceListToWidget.jl`) is a list that a person types into:
  typing narrows, Up and Down move, Return chooses. It lives in the navigator slice
  and its rows name reference steps.
- **Change.** The window opens at the point of the click, not under the button. A
  vertical `WidgetMenu` answers no key. A menu item draws its icon and its label,
  and no column of keys (`WidgetToGraphics.jl:2774-2812`). The SDL key map has no
  Menu key (`SdlBackend.jl:462-500`); the palette command "Show the context menu"
  is the only way from the keyboard.

### 3.3 The pointer

- **Reuse.** Every document has a `mouse_target`, and a widget lights through a
  layer whose size and colour are cells (`_push_hover_layer!`,
  `WidgetToGraphics.jl:271-285`), so a light rebuilds nothing. The outline views
  already route the mouse target to every row container
  (`_route_research_paths!`, `_route_workflow_paths!`), so "the pointer is on this
  row" is one cell.
- **Change.** The buttons that a view draws are not followed
  (`follow_output_mouse_target!`, `OutputSelection.jl:104`, is not called), so they
  most likely do not light today.
- **Missing.** No container shows a child only under the pointer. `visible` is read
  when the printer starts, not in a cell. When the menu window opens, the pointer
  leaves the main window and its mouse target clears, so a "⋯" that shows on hover
  hides while its own menu is open. Nothing draws a hover band behind a row of a
  layout.

### 3.4 The selection, the keys and the folds

- **Reuse.** The focus ring reads the selection in its size cells only
  (`_push_focus_ring!`, `WidgetToGraphics.jl:287-313`). A computed Bool on
  `get_selection(item) !== nothing` tells that the caret is in a row, and a Bool
  that does not change stops the invalidation.
- **Reuse.** The key tables of a document reach it in a widget view: a chain reads
  its stages from the last to the first, and the default reader hands a declined key
  to the table of the document (`Chaining.jl:117-161`, `ProjectionDefaults.jl:143-154`).
  The pivot binds Alt+arrows, Delete and Enter this way (`PivotZoneEdit.jl:195-203`).
  Tab and the arrows are claimed by the layouts and the text, so a table needs
  `override(...)` and a reader that passes `claimed`, as the explorer does
  (`ExplorerToWidget.jl:255-279`).
- **Reuse.** `make_insert_elements_operation`, `make_delete_elements_operation` and
  `MoveRangeOperation` (`dragging/Dragging.jl:53-130`) splice and move list elements
  with their cells; a move into the `children` of the step above is an indent.
- **Reuse.** `ReplaceViewStateOperation` keeps a write out of the history. The study
  keeps its folds as `folded`, which its file leaves out (`ResearchDocument.jl:364-374`).
  `DocumentTree.expanded` keeps folds by document identity on a view document.
- **Change.** A workflow node keeps `collapsed` in the document, so its file saves
  every fold. `is_view_state_field` (`DocumentDefaults.jl:59`) knows only
  `selection` and `mouse_target`; the study leaves `folded` out with a method of
  `pred_arguments`.
- **Missing.** No path follows an insert, so an added row does not take the caret
  (pending [an-insert-moves-the-paths-after-it.md](an-insert-moves-the-paths-after-it.md)).
  A scroll pane does not bring the selection into view. Up and Down do not move
  between rows of a widget view (pending plan of the keyboard, N1 to N7).

### 3.5 Type, colour, icons, layout and text

- **Reuse.** `TextRole` reaches every size from the base font, Ubuntu Mono included
  (`FontRole.jl`). The colour roles cover the design: `:text`, `:text_muted`,
  `:border`, `:hover`, `:accent_tint` or `:selection_band`, `:accent`,
  `:success_*`, `:error_*`, `:warning_*`, `:surface_sunken`. Dark mode follows any
  `ColorRole`.
- **Reuse.** All nine icons of the kinds exist in `LUCIDE_ICON_GLYPHS`, and the study
  maps kinds to icons in `_RESEARCH_ICONS`. `WidgetIcon` with `WidgetIconMark(:dot)`
  is an icon with a status dot.
- **Reuse.** `HorizontalLayout` with `:baseline`, `LayoutConstraint` with `Fixed` and
  `Fill`, `GridLayout`, `FlowLayout` for chips, `StackLayout` for overlays.
  `WidgetLabel` wraps at its width.
- **Change.** `WidgetIcon` draws only inside a tree row and a tab. A button draws no
  widget as its label, and a badge can not be pressed. A badge has no font of its
  own, so no chip can be monospaced. `WidgetAvatar` shows initials in a 13 pixel
  font, too large at 14 pixels. `WidgetText` with a plain value draws one line. The
  `gap` of the two themes is a bare `Int`, outside the scale of spacing.
- **Missing.** No line height in a widget (a label is single spaced). No letter
  spacing. No ellipsis at a width and no limit of lines. No layout that puts a part
  after the text when the text takes one line. No guide lines of a tree. No dashed
  outline of a rectangle (`StyleStroke.dash` is reserved). No helper that shows a
  date only where it changes.

### 3.6 The graph and the roster

- **Reuse.** The graph draws edges, labels and vertices, and maps the mouse target
  into the layout (`GraphToGraphLayout.jl:153-155`). The map of a study already
  builds one vertex per item and one labelled edge per linked pair.
- **Change.** The research map builds its graph without the selection and mouse
  target cells; the state machine diagram shows how (`FsmDiagramToGraph.jl:176-182`).
  The vertex is a `WidgetCard`, which doubles the box of the vertex.
- **Missing.** Nothing draws a light under the pointer (pending
  [a-graph-lights-the-part-under-the-pointer.md](a-graph-lights-the-part-under-the-pointer.md);
  its fact 3 is partly out of date). No engine makes a layered layout, and only
  Adaptagrams routes right angles.
- **Not a fit.** A roster groups rows into one aggregate row and draws every row as
  a table row, so the view by time is a mode of the outline, not a roster.

### 3.7 Saving elements

- **Reuse.** A `CellVector` writes as a list in a `.pred` file, and a shared node is
  written once with markers. The folder save of a study gives each node of a text
  format its own file, such as `h1-statement-1.md`, and `study.pred` refers to it
  (`collect_study_blocks`, `ResearchFolder.jl:27-80`). The holder checks of a delete
  walk every field, so they cover `elements` with no change.
- **Change.** A `.pred` file owns only the documents that no text format owns
  (`PredFile.jl:45-63`). The save of a `.pred` tab is strict, so it refuses a JSON
  object or a Markdown page that a card holds; `WorkflowFileTest.jl:63-79` asserts
  it. A workflow has no folder save. A study folder numbers its files with one
  counter over all blocks, so a new element renames every later file.

### 3.8 The empty documents

- A study is an explorer entry with the alias "study" (`ResearchExplorer.jl:36-40`).
  An empty study draws its title field and nine section headers, each with a
  "+ kind" button.
- A workflow is no explorer entry and has no alias. The catalog has no button that
  starts one; a new workflow is a new `.pred` file.

No file that this plan changes is sealed: the sealed files are the layers `fault`,
`performance`, `cell`, `struct` and `clock` of the kernel ([SEALING.md](../../SEALING.md)).

## 4. The generic parts

Each part goes into the platform, and each names the other places that can use it.
The names are tentative; each step checks them against
[naming-rules.md](../../documentation/rule/naming-rules.md).

- **G1. The outline kit.** A slice of the platform (D1) holds what both domains
  draw: `OutlineTheme` with the sizes and the type of R1 and R3; the row of R1 and R2;
  the mark of R4; the chip of R6; the field line of R5; the guide lines of a tree;
  the shown dates of R1 (a helper that takes the times of the rows in their order
  and answers which rows show their date). Other users: the conversation turns, the
  task rows, the process steps, any list of records with an author and a time.
- **G2. A row that shows its controls under the pointer.** A container draws a
  hover band and the selection tint behind its children, and gives its children two
  cells: "the pointer is here" and "the caret is here". A control that shows only
  then keeps its size and takes a transparent colour at rest, so a light rebuilds
  no row. The container keeps "here" true while a menu that it opened is open, and
  a hidden control leaves the order of Tab. Other users: the rows of the explorer,
  of a table and of a dashboard.
- **G3. A menu that a button opens and the keyboard drives.** A press on a widget
  opens the context menu window under that widget. A vertical menu in that window
  answers Up, Down, Home, End, Return and Escape, and an item draws its keys in a
  column on the right, from `find_bound_keys`. A key opens the menu of the part that
  holds the selection (D2). This changes every menu of the context menu window
  (D3).
- **G4. A list that a person types into.** `NavigatorChoiceList` moves into the
  widget slice as a generic choice list: a query, rows of an icon, a label and a
  note, and an operation per row. The navigator uses it as before.
- **G5. An insertion with a popup.** `InsertionToSyntaxLeaf` takes an option that
  opens the choice list of G4 under the field while the person types, and updates
  it on each key. Up, Down and Return go to the list. Escape removes an insertion
  that is an element of a list. The match adds word prefixes, so "ch" finds
  "Sequence chart" (D4). The filter takes a trait beside the type of the place. A
  type gets an icon and a note at the level of the type: the note is the summary
  of its docstring, as the help list makes it (`compute_help_entries`), and the
  icon is a new trait with no icon as its default. Other users: the Insert of the
  explorer can type and filter by its trait, which removes the reason of its
  design decision; the Insert of a dashboard; Ctrl+T in a tab (D5).
  The field of an insertion shows a short pale text, such as "Type a kind", while
  it is empty, and the text goes away at the first key, as the placeholder of a
  `WidgetText` does. The sentence "Insert a new ⟨typed⟩ here" goes away. The owner
  asked for it on 2026-10-23: "the document insertion initial text [should]
  disappear when the typein starts as in other places and have a better text".
- **G6. The kinds of an element.** A trait says that a document type can stand as
  an element (D6). The candidates come from the type tree with that trait, and their
  names from the aliases, so "formula sheet" finds `FormulaEnvironment`.
- **G7. Elements.** One builder draws a list of elements as R14 says, with the fold
  and the menu of each element, and one set of builders adds, moves, removes and
  copies an element and opens it in a tab. A domain holds the list in a field
  named `elements` and calls the builders. One verb of the assistant adds an
  element to any holder (D18).
  Most elements come from the clipboard, not from a type-in: "most added elements
  in workflow and research would not be typed in there but copy pasted or note
  pasted to keep identity" (the owner, 2026-10-23). A paste on a row adds the
  stored document as an element through `make_pasted_document_operation`, the hook
  of the clipboard: after a note (Ctrl+N) the element is the document itself, so it
  stands at two places and the file writes a marker; after a copy (Ctrl+C) or a
  paste of a copy (Ctrl+Shift+V) it is a copy. The menu of a row holds "Paste as an
  element" while the clipboard holds a document. The add by kind stays for a new,
  empty document.
- **G8. Text that fits.** `WidgetLabel` takes a limit of lines with an ellipsis at
  the width. `WidgetText` wraps a long plain value, and draws its box only while it
  holds the caret (R8). A layout puts a trailing part after the text when the text
  takes one line, and stacks it otherwise (R2). Widgets take their line height
  from the theme (D15).
- **G9. An icon, a chip and an avatar in any layout.** `WidgetIcon` draws in any
  layout, with its marks. A button and a toolbar item take a widget as their label,
  so a mark can be pressed. A badge takes a text role and a small radius, which
  makes a monospaced chip, and takes gestures. `WidgetAvatar` takes an icon and
  scales its font to its size.
- **G10. The folds and the other state of one view.** One way declares the fields of
  a type that are state of the view (D9): the file, the copy and the search leave
  them out. The folds of a tree are a set keyed by document identity, written as
  view state. The study keeps `folded`; the workflow uses the same set.
- **G11. Select a document and bring it into view.** A builder answers the selection
  of a document that a root holds, found by identity, and the scroll pane brings the
  selection into view. Other users: the navigator, the search results, the
  "go to definition" of code.
- **G12. A graph that lights the part under the pointer.** The pending plan of the
  graph does this for every graph: the vertex under the pointer, its edges and its
  neighbours. This plan takes its steps into §10 and adds an option that leaves a
  class of edges out of the lines.
- **G13. A text format inside a `.pred` file.** The answer to D7 decides how a
  workflow file saves a Markdown, JSON or Julia element. Every holder of documents
  in a `.pred` file gets the same answer: a dashboard card, a workflow, a study saved
  from its tab.

## 5. The research domain

- **The outline.** `ResearchStudyToWidget` and `ResearchItemToWidget` are rebuilt on
  G1, G2, G3, G8 and G9, as R1 to R11 say. The card of an item still needs no study,
  so an item draws the same in a report, in a workflow element and in a vertex. The
  back links of R6 are computed in the view. Empty sections are hidden, and the
  section header shows its "⋯" under the pointer, with "Add a ⟨kind⟩", "Fold all"
  and the switch to the view by time.
- **The menu of an item.** Accept… and Reject… (items with a status); the linked adds
  of today, worded by the link ("Add evidence that supports H1"); Add an element;
  Edit all fields; Fold; Open in the map; Copy the id; Delete ⟨id⟩….
- **A decision in the row.** Record writes `make_record_decision_operation` with the
  reason and the basis that the panel holds. The draft of the panel is view state.
- **Edit all fields.** An item id in the view state shows the full form of R9 while
  the caret is in that row. A link field shows its chips and a "+" that opens the
  choice list of G4 over the items of the study, matched by id and text.
- **The view by time.** A mode of the outline (D10): one group per local day, the
  rows sorted by time, each row the same row as by kind. The slots of the view map
  each item, not each list.
- **The map.** `ResearchMapToGraph` builds its graph with the selection and the mouse
  target cells (G12), leaves out the accept and reject edges (D12), and draws a
  vertex as the small row of R12: the mark with its dot, the id, the text in two
  lines, the author and the time, the count of the elements.
- **Elements.** Every kind of item gets `elements::CellVector`, after its content
  field. The folder save names a block by the id, the field and the index in the
  field, such as `x1-elements-2.jl`, so a new element renames no other file.
- **The report.** The answer to D11 decides whether the report is a fourth view.
- **The empty study.** It shows its title with the caret and one quiet row for the
  first question (D19). The first key turns that row into Q1.

## 6. The workflow domain

- **The outline.** `WorkflowNodeToWidget` is rebuilt on the kit, as R1 to R8, R11 and
  R13 say, with guide lines for the tree. A press on the mark of a step opens the
  menu of its four states (G3), and a choice writes `make_workflow_state_operation`.
  A press on the mark of an option writes `make_choose_workflow_option_operation`.
- **The menu of a node.** For an option: Choose, Reject, Park, Reopen. Then Add a step,
  Add a decision (Add an option for a decision), Comment, Add an element; Fold, Show
  the journal, Move up, Move down; Delete….
- **The journal of a node.** A press on the count after the title opens the entries
  under the row, newest last, with a one-line comment field at the end.
- **The keys.** Enter at the end of a title adds a step after it, Tab and Shift+Tab
  indent and outdent, Alt+Up and Alt+Down move, Delete removes, Left and Right fold
  (D14). Each edit puts the caret in the new place with a `ReplaceSelectionOperation`
  in the same `CompoundOperation`.
- **Elements.** `cards` becomes `elements`, a list of documents, and `WorkflowCard`
  goes away; the title goes away too, by the decision of the owner. `collapsed`
  leaves the documents and becomes view state of the root (D8).
- **The journal view and the catalog.** `WorkflowJournalToWidget` becomes the
  timeline of R13, with a toggle of kinds. `WorkflowCatalogToWidget` becomes the list
  of R13, with "New workflow".
- **The explorer.** `WorkflowStep` becomes an explorer entry with the alias
  "workflow" (D20).
- **The empty workflow.** It shows its goal with the caret and one quiet row for the
  first step (D19).

## 7. From the empty document to the whole record

The walk-throughs list every step of a person, and the rule or part that covers it.
Step 16 of §10 tests each walk-through with gestures, from the empty document to
the saved file and back.

### 7.1 A study

1. The person presses "+" on a section of the explorer and picks Study, or types
   "study" in a new tab. The tab shows the title "New study" selected and one quiet
   row under it (D19, §5).
2. The person types the title, then moves into the quiet row and types the question.
   Q1 exists from the first key, by the person, now (R1).
3. The pointer on Q1 shows its "⋯" (R7, G2). "Add a hypothesis for Q1" adds H1 with the
   link, and the caret is in its text (§5).
4. "Edit all fields" on H1 shows Prediction and Basis (R9). "+" on Basis opens the
   list of the items, and the person types "S" (G4). A source that does not exist yet
   comes from the "⋯" of the Sources header (§5).
5. "Add an experiment that tests H1" adds X1. "Add an element" on X1 opens the
   insertion field; the person types "jul" and picks Julia code (G5, G6). The code
   draws as code in the row (R14).
6. The assistant adds R1 and E1 with its verbs; the rows show the assistant avatar
   (§8).
7. "Accept…" on H1 opens the panel; the person writes the reason and presses Record
   (R10). D3 appears under Decisions, and H1 shows its dot.
8. The person adds A1 from the "⋯" of Q1 and accepts it. The header shows the
   answer with its status (R12).
9. The switch shows the study by time, then as a map (R12). The pointer on D2 lights
   its items.
10. Ctrl+S saves; a new tab of the file shows the same study (G13, D7). Ctrl+Z takes
    back each edit, one at a time.

### 7.2 A workflow

1. The person presses "+" in the explorer and picks Workflow, or "New workflow" in a
   catalog (D20). The tab shows the goal selected and one quiet row (D19).
2. The person types the goal, then the first step; Enter adds the next step, Tab
   indents it (D14).
3. A press on the mark of a step opens its states; Active writes the state and an
   entry of the journal (R7, §6).
4. "Add a decision" adds a question with one option; Enter in an option adds the next
   option. A press on the mark of an option chooses it, and "Reject" or "Park" in its
   menu settles it. The reason of an option is a field of the option, which "Edit all
   fields" shows while it is empty (R9, R13).
5. "Comment" opens the field at the end of the journal of the row; the count after
   the title shows the entries (R13).
6. "Add an element" adds a text note, a Julia call and a JSON object (R14, G5).
7. The journal view shows the day of the work; the catalog lists the workflow with
   its progress (R13).
8. Ctrl+S saves the workflow with its elements (G13, D7), and the file opens again
   to the same tree.

## 8. The assistant

- One verb adds an element to an item or a node, by the answer to D18. The
  `describe_study` text names the elements of each item by kind and first line.
- `add_workflow_card!` goes away. The sentences that `register_assistant_api!` gives
  for both domains name the elements.
- The verbs keep their author `:assistant`, so the avatar of R1 tells the person
  which rows the assistant wrote.

## 9. The decisions

Every decision is made. The owner agreed to every recommendation on 2026-10-23:
"Agree with all". Each decision keeps its options, and the chosen option is the
recommended one.

- **D1. Where the outline kit lives.** (a) A new slice of the platform,
  `source/platform/outline/`, `OutlineModule`, used by both domains and open to
  others. (b) The widget slice. (c) A copy in each domain. **Decided: (a)**; the
  widget slice holds widgets, and the kit is a set of builders and one theme.
- **D2. The key that opens the menu of a row.** The SDL key map has no Menu key.
  (a) Shift+F10, the key that other desktops use, plus the command of the palette
  that exists. (b) Add the Menu key to the key map of SDL as well. **Decided:
  (a).**, and (b) as a second step if a person asks for it.
- **D3. The change of every context menu.** G3 gives every vertical menu of the
  context menu window the keys and the column of keys, and lets a button open a menu
  under itself. (a) For every menu. (b) Only for the menus of the outline.
  **Decided: (a)**; the explorer, the pivot and the data frame menus gain the
  same keys.
- **D4. The match of an insertion.** Today a typed name must be a prefix of the
  whole name. (a) A prefix of the whole name or of any word, the whole-name matches
  first, for every insertion. (b) Only in the popup. **Decided: (a)**.
- **D5. Where the popup opens.** (a) An option of the insertion field, on for the add
  of an element, the Insert of the explorer, the Insert of a dashboard and Ctrl+T in
  a tab; off where a person types in place, as in a JSON array. (b) On everywhere.
  **Decided: (a)**.
- **D6. Which documents can be an element.** The steer says no registry. (a) A trait
  that each domain sets on the documents that stand alone, with aliases for the
  names: a Markdown page ("text"), Julia code ("code"), a chart, a formula sheet, a
  math expression, a JSON value, a YAML value, a SQL statement, a pivot ("table"),
  a graph, a sequence chart, a state machine, a process. (b) Every root of a
  `@domain`. **Decided: (a)**, with the list given here for the owner to change.
- **D7. A text format inside a `.pred` file.** A `.pred` tab refuses a JSON object or a
  Markdown page today, and a workflow has no folder save. (a) A `.pred` file writes
  such a node inline, as the text of its own format inside a tagged string, and the
  load reads it with that format; a formula already writes its code as text. (b) The
  save of a `.pred` tab writes such nodes into files beside it, as the study folder
  does, for every `.pred` file. (c) A folder save for a workflow only.
  **Decided: (a)**: one workflow stays one file, and the same answer serves every
  holder. A node that a project file owns still writes a marker.
- **D8. The folds of a workflow.** Today every `collapsed` is saved in the file.
  (a) Folds become view state of the tab, not saved, as in a study. (b) Keep them in
  the file. **Decided: (a)**.
- **D9. Where the state of one view lives.** The architecture rule asks for a view
  document; the study keeps `folded` in the document and leaves it out of the file.
  (a) Keep the state on the root document, and declare such fields with one trait of
  the type, read by the file, the copy and the search; this changes
  `is_view_state_field` of the kernel, which is not sealed. (b) A view document for
  each tab, through `make_document_view`. **Decided: (a)** for this plan; (b) is
  larger and touches every file tab.
- **D10. The view by time.** (a) A mode of the study outline, chosen by the switch, in
  the same tab. (b) A document of its own, as the map is. **Decided: (a)**.
- **D11. The report.** The report of a study is a Markdown page that the outline does
  not show. (a) A fourth view of the switch: By kind, By time, Map, Report. (b) The
  report stays in a tab of its own. **Decided: (a)**, so the whole study is
  reachable from one tab.
- **D12. The decision lines of the map.** (a) Accept and reject are never lines; the
  pointer on a decision lights its items. (b) A toggle shows them. **Decided:
  (a).**.
- **D13. The layout of the map.** No engine makes a layered layout. (a) Keep the
  engines of today, and make the vertices small; a layered layout is a later plan.
  (b) A layered layout now, which needs flow constraints in the C interface of
  Adaptagrams. **Decided: (a)**.
- **D14. The keys of an outline.** (a) In a workflow: Enter at the end of a title adds a
  sibling, Tab and Shift+Tab indent and outdent and so take Tab from the focus walk
  inside the outline, Alt+Up and Alt+Down move, Delete removes, Left and Right fold.
  In a study: Enter at the end of a text adds an item of the same kind, and the other
  keys are the same except Tab. (b) The same keys without Tab. **Decided: (a)**.
- **D15. Line height and letter spacing.** (a) Widgets take a line height from the
  theme, and the section label stays bold capitals with no letter spacing.
  (b) Letter spacing too, in the font and in every backend. **Decided: (a)**.
- **D16. Dashed outlines.** The design draws an empty field and the insertion field
  with a dashed line, and no backend draws a dashed rectangle. (a) A solid light
  outline. (b) Dashed rectangles in every backend. **Decided: (a)**.
- **D17. Old files.** A workflow file with `cards` or `collapsed` does not load once
  the fields go away. (a) No migration; the owner set aside the compatibility of the
  study for the same reason. (b) The load reads `cards` into `elements`.
  **Decided: (a)**, unless files that people keep exist.
- **D18. The verb of the assistant.** (a) One verb in the platform,
  `add_element!(holder, document)`, for any document with `elements`. (b) One verb in
  each domain. **Decided: (a)**.
- **D19. The empty document.** (a) A new study or workflow shows its title and one quiet
  row (the first question, the first step), which becomes the first item on the first
  key. (b) The title and nothing else; the "⋯" of the header adds the first item.
  **Decided: (a)**.
- **D20. A new workflow.** (a) `WorkflowStep` becomes an explorer entry with the alias
  "workflow", and the catalog gets "New workflow", which writes a new `.pred` file in
  its folder. (b) Only the explorer. **Decided: (a)**.

## 10. The steps

Each step is a commit on a branch of its own. Each names its narrowest test, which
must pass, and the rules (R) and parts (G) that it builds. A step that changes a
generic behaviour updates the design document of that slice in the same commit.

- [ ] **1. Theme and type for outlines.** The outline slice (D1) with `OutlineTheme`:
  the sizes of R1 as theme fields of a size kind, the type of R3 as `TextRole`s, the
  colours of R3 as roles that exist. Widgets take a line height from the theme (D15).
  The `gap` of the two themes becomes a spacing. Test: `test_theme()`,
  `test_line_spacing()`, `test_style()` (no literal size outside a theme).
- [ ] **2. Text that fits (G8).** A limit of lines with an ellipsis on `WidgetLabel`; a
  wrapped plain value in `WidgetText`; a `WidgetText` with no box at rest; the layout
  of R2. Test: `test_word_wrapping()`, `test_widget_text_editing()`, a new test of the
  layout of R2 at two widths.
- [ ] **3. Icon, chip and avatar (G9).** Test: `test_widget_button_labels()` and a new
  test that draws a pressable `WidgetIcon` with a dot in a layout.
- [ ] **4. A row that shows its controls (G2).** The hover band, the tint, the two cells,
  the menu that keeps the row lit, the order of Tab. The drawn buttons of a view get
  `follow_output_mouse_target!`. Test: `test_mouse_target_chain()` and a new test: a
  move of the pointer onto a row changes the colour of its "⋯" and rebuilds no row.
- [ ] **5. Menus that a button opens and the keyboard drives (G3, D2, D3).** Test:
  `test_widget_context_menu()`, `test_widget_menu()`: the menu opens under its button,
  Up, Down and Return choose, Escape closes, the keys of an item are drawn, Shift+F10
  opens the menu of the selection.
- [ ] **6. The choice list (G4).** It moves into the widget slice; the navigator uses it.
  Test: the navigator tests of `test_platform()` pass unchanged, and a new test types
  into a list of three rows.
- [ ] **7. The insertion with a popup (G5, G6, D4, D5, D6).** The word match and its rank,
  the trait filter, the icon and the note of a type, the popup option, Escape in a list,
  the trait on the documents of D6. The explorer Insert types and filters. Test:
  `test_document_insertion()`: "ch" finds Chart and Sequence chart in that order; Enter
  inserts the first; Escape removes the element; the explorer Insert with "stu" adds a
  study.
- [ ] **8. View state and folds (G10, D9).** The trait of the fields of view state; the fold
  set. Test: `test_pred_file()` leaves a view field out; `test_document_duplicate()`
  copies none.
- [ ] **9. A text format inside a `.pred` file (G13, D7).** Test: `test_pred_file()` and
  `test_serialization()`: a workflow with a JSON and a Markdown element saves alone and
  loads to the same graph; a node that a project file owns still writes a marker.
- [ ] **10. Elements (G7, D18).** The builders, the drawing of R14 with the fold and the
  menu of an element, `add_element!`. Test: a new `test_elements()` in the outline
  slice: add, move, remove, copy, fold, and undo of each.
- [ ] **11. Select and show (G11).** Test: a new test: a press on a chip selects the item
  and the scroll pane shows it.
- [ ] **12. The graph lights the part under the pointer (G12, D12, D13).** The steps of the
  pending graph plan, and the option that leaves a class of edges out. Test:
  `test_graph()`, `test_graph_projection()`.
- [ ] **13. The research outline (R1 to R12, §5, D10, D11, D14, D19).** The row, the menu,
  the decision panel, Edit all fields, the back links, the view by time, the empty
  study, the keys, `elements` on every item and the names of the folder save. Test:
  `test_research()`; `ResearchToWidgetTest` asserts the parts of each rule;
  `ResearchMapToGraphTest` counts 12 edges in the example.
- [ ] **14. The workflow outline (R1 to R8, R11, R13, R14, §6, D8, D14, D17, D19, D20).** The
  tree, the state menu, the journal of a node, the keys, `elements` in place of
  `cards`, the folds as view state, the journal view, the catalog, the explorer
  entry. Test: `test_workflow()`, `test_workflow_file()`.
- [ ] **15. The assistant (§8).** Test: `ResearchAssistantApiTest`,
  `WorkflowAssistantApiTest`.
- [ ] **16. The walk-throughs (§7).** Two tests of gestures: each walk-through from the
  empty document to the saved file and back, with an undo of each edit. Test:
  `test_research_combinations()` and a new workflow test beside it. The examples of
  both domains show a study and a workflow with elements, and `test_domain_examples()`
  draws them.
- [ ] **17. The documents.** research.md, workflow.md, widget.md, context-menu.md,
  domain.md, explorer.md and a new outline.md say what is; the limits that this plan
  removes go away. Test: `test_documentation()`.

## 11. Not in this plan

- Up and Down between rows of any widget view, and Tab between parts: the pending plan
  of the keyboard holds them; this plan binds only the keys of D14 on the documents.
- A layered layout of a graph (D13).
- A view document for every file tab (D9 b).
- The elements of a dashboard: a `DashboardCard` keeps its title; it can take the
  builders of G7 in a later plan.
- Files on the disk as elements, such as a PDF: an element is a document.
