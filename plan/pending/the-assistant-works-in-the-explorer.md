# The assistant works in the Explorer

Status: IN PROGRESS, 2026-10-21, on the branch `assistant-explorer` (worktree
`projectured-julia-assistant-explorer`). No decision is open.

## The ask

The owner, 2026-10-21: "1: check what's missing for the assistant in the
explorer". After the report of four gaps, to "Shall I write this as a plan?":
"yes".

## The problem

The person reads, adds, removes, renames, orders and opens the entries of the
Explorer with the mouse and the keys. The assistant can do none of this. The
facts, on main at 31b107f18:

1. **The scope of the assistant names nothing of the Explorer.**
   `make_editor_api` (`source/platform/application/Application.jl`) holds no
   name of `ExplorerModule`: not `Dashboard`, `DashboardCard`, `ExplorerSection`,
   `get_session_explorer_content` or `AddExplorerEntryOperation`. The docstring of
   `Dashboard` tells an assistant to insert into `cards`, but the assistant can
   not make a `Dashboard`. `get_session_explorer_content` answers the plain
   section, so a write into it is a direct write of a cell, which no undo takes
   back.
2. **A row of the Explorer has no command for the assistant.** Every rule of
   `@gestures Explorer` (`ExplorerEntryEdits.jl:192`) reads the selection of the
   person, and the table has the condition `when(_find_shown_node_steps(doc,
   sel) !== nothing)`. `describe_commands` and `run_command!`
   (`source/platform/gesturehelp/PartCommands.jl`) read only the table of the
   document at the end of the path of the part. So on a section or an entry they
   answer the commands of that document, and never "Remove from explorer",
   "Rename", "New section", "Add…" or a move. The menu of a row
   (`_make_row_menu_operation`, `ExplorerRowMenu.jl:14`) builds these operations
   for any node by its steps, with no selection.
3. **No verb shows a page in the Explorer.** `open_page!`
   (`NavigatorPageOpen.jl:71`) always opens a new tab. A press on a row makes the
   navigator of the Explorer visit the page, and `_add_tree_reveal`
   (`ExplorerToWidget.jl:275`) opens the rows above it. No verb does the same.
4. **The guide that the assistant reads first names what it can not call.** The
   system text sends the assistant to `resource://guide/guide/orientation`
   first. That guide names `evaluate_operation(editor, op)` (`orientation.md:54`)
   and `color_black`, `color_red` (`orientation.md:191`). None is in the scope.

## The model

The owner's rules decide the shape: the assistant acts at a part by its route,
as the context menu does, and never moves the selection of the person; and each
edit of the assistant is an operation of the user interface, which undo takes
back.

1. **The assistant reaches the content of the Explorer as a part of the window.**
   A new verb `find_explorer_content(; editor)` answers the root section as a
   `ReferencedDocument`, read from the root of the window through the first tab
   that shows an `Explorer`. It answers `nothing` when no tab shows one. So
   `insert_elements!(content.entries, index, [dashboard])` is an edit through the
   readers, which undo takes back. `Dashboard`, `DashboardCard` and
   `ExplorerSection` join the scope. `get_session_explorer_content` stays out of
   the scope, because it invites a direct write.
2. **A document on the path of a part gives commands to the part.** A new generic
   of the gesture help slice, `collect_part_commands(holder, steps)`, answers
   the `GestureRow`s that `holder` gives to its part at `steps`. The default
   answers none. `_collect_part_rows` walks the documents on the path of the
   part from the root of the window. Each document answers for the rest of the
   steps, and its rows join the rows of the table of the part. `run_command!`
   roots the operation of a holder at the place of the holder with
   `read_rooted_operation`, so every reader above the holder lifts it.
3. **The menu of a row and the commands of a row are one list.** One function,
   `_make_row_items(explorer, steps)`, builds the items of the Explorer for a
   node. The menu and the method of `collect_part_commands` for `Explorer` both
   call it. The method leaves out the commands of the table of the document of
   the row, because `_collect_part_rows` reads that table already. The list
   gets "Move the entry earlier" and "Move the entry later" for an entry, with
   their keys, so the menu shows them too.
4. **A page opens in the Explorer by its own verb.** A new verb
   `open_explorer_page!(part; editor)` makes the navigator of the Explorer visit
   the page of `part`, and opens the rows of the tree above it, as a press on a
   link on a page does. The selection of the person does not move. The part is a
   node of the content, or a document that an entry holds, which
   `find_navigator_address(::ExplorerSection, document)` finds. For a part that
   the Explorer does not hold, the verb throws, and the message says to add the
   document first.
5. **The orientation guide names only what the assistant can call, or says who
   calls it.** The Intent bullet names the verbs first, and says that
   `evaluate_operation` is for the code of a package. The example of a canvas
   uses `StyleColor`.

## Decisions

The owner accepted the three recommendations on 2026-10-21: "I accept and
implement".

1. The generic `collect_part_commands(holder, steps)` is a new mechanism. The
   other choice is a method of `_collect_part_rows` for the Explorer only, which
   no other holder can use. I recommend the generic: a pane tree and a dashboard
   also give commands to the parts that they hold.
2. `open_explorer_page!(part)` is a new verb. The other choice is a keyword of
   `open_page!`, such as `open_page!(part; place = :explorer)`. I recommend the
   new verb: a keyword that changes where a page opens is easy to miss in a
   list of verbs.
3. The two moves join the menu of a row. The other choice is that the commands
   of a row get them and the menu does not. I recommend one list: the person and
   the assistant then see the same commands.

## Steps

Each step runs in a worktree, has its own commit, and does not land on main
without the approval of the owner.

1. [x] **The content of the Explorer in the scope.** `find_explorer_content`,
   and `Dashboard`, `DashboardCard`, `ExplorerSection` in `make_editor_api`.
   Test, in `test/projectured/editor/AssistantVerbsTest.jl`: the verb answers the
   root section; an insert of a dashboard into `entries` adds a row; the tool
   `undo` takes it back; the selection of the person does not move. If the
   readers do not carry the insert to the root, record the cause in "As built"
   and stop for a decision.
2. [x] **The commands of a row.** `collect_part_commands`, the walk in
   `_collect_part_rows`, the root of a holder in `run_command!`,
   `_make_row_items`, and the method for `Explorer`. Tests: in
   `AssistantVerbsTest.jl`, `describe_commands` on a section lists "Rename",
   "New section", "Add…", "Remove from explorer" and the two moves;
   `run_command!(entry, "Remove from explorer")` removes the entry, undo puts it
   back, and the selection does not move. In `test/platform/explorer/ExplorerTest.jl`,
   the menu of a row has the same items as the commands of that row.
3. [x] **A page in the Explorer.** `open_explorer_page!` in the explorer
   slice of the scope. Test, in `AssistantVerbsTest.jl`: on an entry and on a
   node below an entry, the navigator shows the page, the tree shows its row,
   and the selection does not move; a document that the Explorer does not hold
   throws.
4. [ ] **The words.** `EDITOR_SYSTEM` gets one sentence for each new verb and
   for `describe_commands` on a row. `orientation.md` changes at lines 54 and
   191. `explorer.md` gets a section "What an assistant calls", and
   `navigator.md` names `open_explorer_page!` beside `open_page!`.
   `tool/assistant/rehearsal.jl` gets three tasks: add a dashboard of two charts
   to the Explorer, remove an entry, and show the task list in the Explorer.
   Run the rehearsal once on its seeds and record the result. The plan moves to
   `plan/done/`.

## Not in this plan

- The legend of the frame statistics. The owner deferred it on 2026-10-21:
  "don'd do the legend stuff, I defer that part".
- The commands that a pane tree or a dashboard gives to the parts that they
  hold. The generic of step 2 makes them possible.
- The filter and the search of the Explorer for the assistant. `search_documents`
  already finds a document in the window.

## As built

- **Step 1.** `find_explorer_content` is in `ExplorerDocument.jl`. It walks the
  tabs of the window as `find_pane_reference` does, and in each tab it searches
  for an `Explorer` whose root is the session content, with the depth and the
  filter of `_find_window_explorer_content`. The answer is the section with the
  reference `<tab>.content.<layers>.tree.root`. A probe on main showed that an
  insert into `entries` of this part goes through the readers to the root, undo
  takes it back, and the selection does not move, so no new operation is needed.
  The Explorer slice now uses the kernel `AgentModule` for
  `run_on_editor_task!`. The docstring of `ExplorerSection` names
  `find_explorer_content` in place of `get_session_explorer_content`. Tests:
  `test_assistant_verbs()` 62 pass; `test_referenced_document_editor()` 109 pass
  and 2 fail, the 2 known failures of main at lines 369 and 381.
- **Step 2.** `collect_part_commands(holder, steps)` is in
  `PartCommands.jl`. `_collect_part_commands` walks the documents on the path
  of the part from the root; each command keeps the place of the document that
  gave it, and `run_command!` roots the operation at that place. A command whose
  words a nearer row has is left out, so the nearest wins. The explorer slice now
  uses the gesture help slice, and the edge `explorer → gesturehelp` is in
  `PLATFORM_SLICE_EDGES`.
  `_collect_row_commands(explorer, steps; selects)` builds the menu of a row and
  the commands of a row. Each command has a name, an operation, its keys from
  `find_bound_keys` and the text of its tooltip, so the tooltips of the menu stay
  as main has them. The builders of a removal, a move and a new section take
  `selects`. Without it, a removal is only the delete, and a move and a new
  section add with no navigator and no selection.
  A change from the model: the commands of a row for a verb leave out "Rename"
  and "Add…". Rename only puts the caret in the title, and Add… only opens the
  menu of the kinds; both are for the person. The assistant renames with
  `replace_referenced_value!(entry, :title, text)` and adds with
  `insert_elements!`. A move is offered only where the entry can move, so the
  first entry has no "Move the entry earlier". The keys show in `describe_commands`,
  such as "Remove from explorer: Delete".
  A limit that stays: a path of the navigator does not follow an insert or a
  delete before it, so after a removal by the assistant the page of a later entry
  can show the entry after it. The person's Delete visits the section page for
  this reason. `plan/pending/an-insert-moves-the-paths-after-it.md` is the general
  fix. Tests: `test_assistant_verbs()` 70 pass, `test_explorer()` 249 pass,
  `test_platform_layering()` 7 pass.
- **Step 3.** `open_explorer_page!` is in `ExplorerDocument.jl`, in the explorer
  slice, because the navigator slice is below the explorer. It roots the visit
  writes (`_get_visit_writes`, so no selection) and the reveal of the tree at the
  place of the explorer with `read_rooted_operation`. A change from the model: the
  address of a part is the rest of its reference below the root section, else the
  path where an entry holds the nearest document on the reference of the part,
  with the rest of the reference after it. So a part of a held document opens too,
  also when another tab shows that document. A fact found: the open files of the
  editor (`OpenFileList`) have no `find_navigator_address` method, so the explorer
  does not find the file of a tab through them, and the verb refuses it. The test
  uses the "Editor" section in a tab of its own for the held case.
  Tests: `test_assistant_verbs()` 79 pass, run with the step 4 changes in place.
