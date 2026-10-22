# The explorer shows the open workflows

Status: IN PROGRESS, 2026-10-22, on the branch `workflow-explorer`, in the worktree
`projectured-julia-workflow-explorer`. Not landed on `main`.

## The ask

The owner, 2026-10-22: "should we add the workflow domain to the explorer so both
the user and the assistant can keep track of workflows?"

The answers to the questions that followed:

- "check what a roster is, that may help show the workflows" and "workflows
  should be present in the explorer if the package is loaded".
- To "can I add this new generic trait, which the first content of the explorer
  reads?": "yes".
- To the question of the folder that holds the workflow files: "I don't think we
  should limit where workflow files can be", and "we may simply use a pred file
  from the files and show in the workflow by the roster when it gets opened, no?"
- To "can the new list replace `WorkflowCatalog`, so that I remove the catalog
  and `collect_workflow_files`?": "agreed".

## The problem

1. **The explorer has no entry for workflows.** A `.pred` workflow file shows in
   Files as a leaf. An open workflow tab that "Add to explorer" adds is a leaf
   too. The workflow domain has no method of `get_tree_children_steps` and no
   method of `is_explorer_entry_type`.
2. **A loaded domain can not add an entry to the first content.**
   `make_editor_explorer_content` (`source/platform/application/ApplicationExplorer.jl`)
   builds the first content from a fixed list, and the platform names no domain.
3. **The assistant does not see the workflows.** `find_explorer_content()` shows
   Files, Tasks and Dashboards, and no workflow. Q2 of
   `plan/done/a-workflow-records-steps-decisions-and-dates.md` asks how the model
   learns that a workflow exists.
4. **The catalog reads the disk in a computation.** `WorkflowCatalog` lists the
   workflows of one folder. `collect_workflow_files` reads that folder inside
   the computation of the view. The view builds its table by hand, with no
   filter, sort or find.

## The model

- **One new trait in the tree slice.** `is_session_explorer_entry_type(type) -> Bool`,
  beside `is_explorer_entry_type` in `TreeInterface.jl`. The default in
  `TreeDefaults.jl` is `false`. A type that answers `true` has a constructor
  with no arguments. `make_editor_explorer_content` puts
  `get_session_document!(type, editor, type)` after the lists of the session,
  for each insertion candidate of `Document` that answers `true`. This is the
  same way that the `+` list reads `is_explorer_entry_type`. The session getter
  of the kind makes the same call, so the two give the same document. The
  explorer slice gets no code.
- **The workflow list.** `WorkflowList` is a session document of each editor, as
  `AssistantList` is. `get_session_workflow_list(; editor)` answers it with
  `get_session_document!(WorkflowList, editor, WorkflowList)`.
  - Its insertion alias is `workflows`. `make_insertion_document` gives the
    session list. `is_explorer_entry_type` and `is_session_explorer_entry_type`
    answer `true`.
  - `pred_arguments` is empty, and `make_pred_document` gives the session list.
    So a saved explorer keeps that it holds the list, and not the rows.
- **The items are the open files whose document is a workflow.** The workflow
  domain adds a roster source, as `_SessionTasks` gives the tasks
  (`source/platform/task/TaskGroupList.jl`).
  - The parts of the source are the files of `get_session_open_file_list(; editor)`.
  - The item of a part is the document of the file, when it is a `WorkflowStep`.
    The file document is the `within` of the row, so `within.name` and
    `within.folder` name the file.
  - A file is in the open file list while a tab or an explorer page shows it.
    So a workflow from any folder is in the list while it is open.
  - The source reads no disk.
  - `register_roster_source!(:workflows, …)` gives the source to
    `StoreRecords(:workflows)` and to `describe_roster_sources()`.
  - `ItemsWithin` is not used, because it finds a type at any depth. Each
    sub-step would then be a row.
- **The facets of a workflow.** `get_item_facets(::Type{WorkflowStep})` declares
  three facets, which `compute_item_facet` gives:
  - `active`: the titles of the active steps of the tree.
  - `last_entry`: the time of the latest entry of the tree.
  - `open_decisions`: the count of the decisions that have no chosen option.
- **The page of the list.** The list holds an `ArrangementDocument` of a
  `Roster` of the source, linked to the list, as `BackgroundWorkLog` does. The
  columns are `title`, `state`, `active`, `last_entry`, `open_decisions` and
  `within.name`, which are the columns of the catalog. The arrangement slice
  gives the filter, the sort, the group and the find. A double click on a row
  opens the workflow as a page.
- **The tree.**
  - The list has its files as children: a computed `CellVector` of the open
    files that hold a workflow, the same file pages that "Open files" holds. A
    press shows the page of the file, so an edit goes into its history. To
    "can the rows below the Workflows entry be the file pages, with one new rule
    that gives a file page the tree children of its document?", the owner
    answered: "yes, I agree but take care, another agent is working on the open
    file list".
  - The rule is the default of `get_tree_children_steps` in the tree slice: a
    layer, a document whose `get_edited_field` names a field, has the children
    of the document that it shows. It is in the tree slice and not in the file
    format slice, because the other agent changes the file format slice, and
    because one rule also covers a `FileDocument` that the open file list holds
    when no page shows it. The default of `get_document_decoration` follows the
    layer already, and `ConversationPart` delegates to its content by hand.
  - A `WorkflowStep` and a `WorkflowOption` have their `children`, and a
    `WorkflowDecision` has its `options`. The journal and the cards are not
    nodes of the tree.
  - The label is the title, from `get_document_title`.
  - `get_document_decoration` gives each node its state in the colour of its
    role, as the outline draws its badge. The list shows the count of its rows.
- **The assistant.** `WORKFLOW_ASSISTANT_API` adds `WorkflowList` and
  `get_session_workflow_list`. The assistant sees the entry in
  `find_explorer_content()`, reads the rows with the verbs of the roster and
  the arrangement, and shows a workflow with `open_explorer_page!`.
- **The catalog goes.** `WorkflowCatalog`, `WorkflowCatalogToWidget`,
  `collect_workflow_files`, their test and their part of `workflow.md` are
  removed. `ProjecturedWorkflow` moves from 0.1.0 to 0.2.0, because an export
  is removed.

## Steps

Do the work in a worktree of its own. Commit each step. Do not land on `main`
before the owner approves.

1. [x] **The trait and the first content.** Done; see [As built](#as-built). `is_session_explorer_entry_type` in
   the tree slice, and its use in `make_editor_explorer_content`. A test in
   `test/platform/explorer/ExplorerTest.jl`: a probe kind that answers `true`
   is in the first content after the lists of the session, once for each
   editor, and the asserts on the entries 2 to 4 keep. Run `test_explorer()`.
   Update `tree.md`, `explorer.md` and `application.md`. Commit.
2. [x] **The workflow list.** Done; see [As built](#as-built). `WorkflowList`, its source, the facets, the tree
   methods, the decorations and the API. A test in `ProjecturedWorkflowTest`:
   - an editor with two open `.pred` files, one a workflow and one not, gives
     one row with the file in `within`;
   - a release of the file takes the row away;
   - the first content holds the list;
   - the tree shows the file page, and below it the steps, the decisions and
     the options;
   - the facets give their values.
   A test in `TreeTest.jl`: a layer has the children of the document that it
   shows. Run `test_workflow()` and the platform tests of each slice that draws
   a tree. Commit.
3. [ ] **The catalog goes.** Remove the catalog, its test and its exports. Set the
   version to 0.2.0. Update `workflow.md`. In omnet-julia, remove the 16 lines
   of `asset/precompile/PrecompileStatements.jl` that name the catalog, and run
   `CampaignExplorerTest` and `CampaignLoopTest`. They read the explorer
   entries by their index. Commit in each repository.
4. [ ] **A live check.** In a window, open a `.pred` workflow from Files. The
   Workflows entry shows it with its steps, and the page shows its row. Close
   the file, and the row goes. The assistant finds the list through
   `find_explorer_content()`. Move the plan to `plan/done/`. Commit.

## Limits

- A saved explorer file replaces the first content. A window that restores a
  file saved before the package was loaded has no Workflows entry. The person
  adds it with `+`.
- A package that loads after the window started adds no entry to that window.
- A workflow that is closed is not in the list. "Add to explorer" on its file
  keeps it at hand.

## Open items

- The workflow of an assistant that is not in a file of its own is not in the
  list. No verb sets `Assistant.workflow`; only its constructor takes it.
- A double click on a row of the table opens the page of the workflow below the
  history of its file, so that history does not record an edit there. This is
  the limit of `navigator.md` for any page below a history.
- The three lists of the platform (open files, tasks, assistants) stay in the
  fixed list of `make_editor_explorer_content` and do not use the trait.

## As built

- **Step 1.** The trait is in `TreeInterface.jl`, its default in
  `TreeDefaults.jl`, and its export in `TreeModule.jl`.
  - `_collect_session_explorer_entry_types()` in `ApplicationExplorer.jl` reads
    the method table of the trait, as `compute_loaded_settings_types()` reads
    the methods of `get_setting_descriptions`. It keeps each type whose method
    answers `true`, and sorts them by the names of the types.
  - Decision: the first content does not read `get_insertion_candidates(Document)`,
    as the `+` list does. That function probes the constructor of each subtype
    of `Document` and compiles a method for each, and the first content runs at
    each window start.
  - The call of the trait and the constructor run with `Base.invokelatest`, so
    a method that a package added after the caller started still counts.
  - The test of the first content now counts the kinds of the trait, so a
    process that loads a package with such a kind passes it too. A new testset
    uses a probe kind that a `Ref` switches on and off. It checks the place of
    the entry, one document for each editor, and no second copy when the host
    gives it.
  - `test_explorer()`: 257 of 257 pass. The naming guard passes.
  - The guides `tree.md`, `explorer.md` and `application.md` name the trait.
    `explorer.md` lists the limit of a restored content file.
- **Step 2 stopped before code, 2026-10-22.** Open item 2 fails by design. The
  history of a file is an `UndoBuffer` between its `FilePage` and its document,
  and it records only the operations that pass its own reader
  (`UndoBufferToAny.jl`). A navigator page prints only the document at its
  address, and `navigator.md` lists the limit: a history inside the content of a
  navigator does not record an edit on a page below the root. With the tree
  children of the list as the workflows, a press on a workflow shows a page
  below the history of its file. The edit applies, but the file shows no unsaved
  edits, and undo in the file does not take it back. The proposal to the owner:
  the tree children of the list are the file pages that hold a workflow, as in
  "Open files", and one rule of the file format slice gives a file page the tree
  children of the document that it shows.
- **Decisions and facts for step 2.**
  - The list holds the open file list of its editor in a field, and its source
    reads that field. A source that finds the list through the evaluation editor,
    as `_SessionTasks` does, caches an empty answer when a read outside the loop
    computes it first. So the first content makes the document of a kind inside
    `run_with_evaluation_editor(…, editor)`, and `WorkflowList()` reads
    `get_session_open_file_list()` there.
  - The page of the list does not keep its arrangement when the last entry goes.
    `keep_held_arrangement` does that, but it is on the branch `open-files-roster`
    (commit `dd4c70bd6`), not on `main`. The page calls it after that branch lands.
  - The suite `test_workflow()` does not run `test_workflow_journal_to_widget()`:
    line 29 of `WorkflowSuite.jl` is a tuple, not a call. Step 2 fixes the line.
- **For step 2.** `WorkflowList()` is the maker of the first content, so the
  `@document` of the list must not generate a constructor with no arguments.
  Give its fields no defaults, as `AssistantList` does. Another session works
  on `the-open-files-show-as-a-roster.md` (branch `open-files-roster`): it adds
  a field `table` to `OpenFileList` and keeps `files`, which the source reads.
- **Step 2, done 2026-10-22.**
  - `WorkflowList.jl`: the list (`file_list`, `files`, `table`), its maker, the
    session getter, the traits of a session tool, the source `_OpenWorkflows`,
    the facets `goal`, `active`, `last_entry` and `open_decisions` of
    `WorkflowStep`, the tree methods and the decorations. The three helpers of
    the catalog moved here, so step 3 deletes the catalog file whole.
  - `WorkflowListToWidget.jl`: the page, a line above the table, in the shape of
    the page of the background work log. It is a row of the natural graphics of
    the domain, chained with `GridLayoutToGraphicsCanvas`.
  - The tree slice: the default of `get_tree_children_steps` follows a layer.
    `ApplicationExplorer.jl` makes the document of a kind inside
    `run_with_evaluation_editor`.
  - A fault that the workflow test found in step 1: the collector kept only a
    `DataType`, and the type of a `@document` is a `UnionAll`, so the list was
    not in the first content. The collector now keeps any `Type`, and the probe
    kind of `ExplorerTest.jl` is parametric, so the test covers the case.
  - With the workflow package loaded, the save test of the explorer read its
    sections at fixed indices. It now adds the count of the marked kinds, as the
    test of the first content does.
  - The column `goal` and not `title`: a cell whose value is a document takes
    keys, and an edit there goes into the history of the window and not of the
    file. A text value shows as a label.
  - `test_workflow()` now runs `test_workflow_journal_to_widget()` (11 tests),
    which the tuple at line 29 skipped.
  - Tests: the tests of each slice that draws a tree (`test_document_tree`,
    `test_explorer`, `test_assistant_work`, `test_conversation_tree`,
    `test_document_decoration`, `test_system_process`, `test_task_document`,
    `test_work_plan`) end with exit code 0. `test_explorer()` and
    `test_workflow()` in one process with the workflow package loaded: 481 of
    481 pass. The naming guard passes.
