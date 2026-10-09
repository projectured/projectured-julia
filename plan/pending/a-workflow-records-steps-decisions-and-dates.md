# A workflow records steps, decisions and dates

> **Status:** in progress on branch `workflow` (worktree
> `projectured-julia-workflow`). Written 2026-10-09. Steps 1 to 8 are done.

## 1. The request

The owner asked (2026-10-09) for "a workflow domain which contains documents
representing human workflows, decisions, branching points, an exploration tree,
etc." and: "I envision some kind of hierarchical structure with dashboard like
elements where you can add and remove content. We also record dates, and user
comments, assistants write important decisions into it, etc. This would be a
durable state which needs to be saved, new workflows can be started and
continued, the user can switch context, etc. and the assistant should be aware of
it and automatically use it to organize information."

The owner answered seven questions (2026-10-09); see section 6.

## 2. What the literature gives

The request joins four fields. Each has its own literature.

| Question | Literature | The lesson for this domain |
| --- | --- | --- |
| What to do, in which order | Workflow Patterns (van der Aalst et al., 2003), BPMN, Petri nets, statecharts (Harel, 1987), CMMN (case management), Hierarchical Task Analysis (Annett and Duncan, 1967), HTN planning | For a person, a plan is a resource and not a program (Suchman, *Plans and Situated Actions*, 1987). CMMN and HTA fit; strict flows do not. The model records a deviation and never enforces a flow. |
| Why: questions, options, decisions | IBIS (Kunz and Rittel, 1970), gIBIS (Conklin and Begeman, 1988), QOC (MacLean et al., 1991), Architecture Decision Records (Nygard, 2011), dialogue mapping (Conklin) | A decision is a question with options and a reason. Dialogue mapping is the model for the assistant: it writes the tree while the talk runs. |
| Which alternatives were tried | VisTrails version tree (Callahan et al., 2006), Variolite (Kery and Myers, 2017), Sensecape and Graphologue (UIST 2023), Tree of Thoughts (Yao et al., 2023) | Keep a dead branch and the reason it died. A rejected option is knowledge. |
| What happened, when, by whom; how to resume | org-mode (TODO states, timestamps, LOGBOOK, agenda), W3C PROV, lab notebooks, Mylyn task context (Kersten and Murphy, 2005), Rooms (Henderson and Card, 1986), activity-based computing (Bardram) | Each node keeps a dated log. A task keeps the set of documents that it uses; here the cards of a node are that set, and many workflows stay open at the same time, so no switch is necessary. |

Two kinds of branch exist, and the model keeps them apart: **parallel** steps
are all done (AND), and **alternatives** give one chosen option (OR). An AND/OR
tree (Nilsson; KAOS goal trees) holds both.

## 3. What exists (2026-10-09)

- **The `.pred` format and the markers between files**
  ([serialization.md](../../documentation/package/platform/serialization/serialization.md)).
  A `PredFile` writes any document as its constructor call. In memory the graph
  is the real graph; a save writes a marker only where a node belongs to another
  file: `<<node(file("a.json"), "entries[2].value")>>`,
  `<<section(file("page.md"), "Title")>>`,
  `<<definition(file("steps.jl"), "queue_step")>>`. A `FileProject` saves and
  loads a set of files in several formats. The owner: references are durable in
  this format, and Markdown, `.pred`, Julia and JSON combine through them now.
- **Widgets for a dashboard.** `WidgetCard`, `WidgetTabbedPane`,
  `WidgetSplitPane`, `WidgetTable`, `WidgetList`, `WidgetAccordion` and
  `WidgetTree` in
  [WidgetDocument.jl](../../source/platform/widget/WidgetDocument.jl). The task
  slice has a table above a detail in a split pane (`TaskGroupListToWidgetPane`).
- **The Graph domain** with layout engines draws a node-link view, as FSM and
  Process use it.
- **The Process domain** is an executable flowchart: `ProcessDecision` has a
  condition with a then and an else branch, and the domain has a runtime and a
  debugger ([ProcessDocument.jl](../../source/domain/process/ProcessDocument.jl)).
  It is a program, not a record of human work, so the workflow is a domain of its
  own. A step can hold a process model in a card.
- **The assistant** edits through the `ToolSet` and operations, so undo and the
  fault barrier apply. `register_undo_tools!` is the pattern for a domain that
  adds tools. The `Assistant` document has no field for a workflow; its
  `context::Int` is the size of the context.
- **No date type in a document.** Time exists only as `Float64` `time()` values
  in the task slice. `Dates` is a standard library; the pivot domain uses it.
- **The table of assistant conversations**
  ([a-table-shows-every-assistant-conversation.md](a-table-shows-every-assistant-conversation.md))
  adds `description`, `comment`, `work_state` and the time of a turn. Its
  step 2 gives a turn the time that a journal entry needs to name its source.

## 4. The design

### 4.1 The document: an AND/OR tree

The domain is `ProjecturedWorkflow`, in `source/domain/workflow/`. It depends on
no other domain. A workflow is its root step: a new workflow is a new step, so
no separate root type exists.

| Type | What it is | Children |
| --- | --- | --- |
| `WorkflowStep` | a thing to do; the root is the goal of the workflow | sub-steps and decisions, in order (AND) |
| `WorkflowDecision` | a branch point, as a question | options (OR) |
| `WorkflowOption` | one answer to a question, with a reason | the steps that follow it |
| `WorkflowEntry` | a dated record on a node: a comment, a decision, a change of state or a link | none |
| `WorkflowCard` | content that a person adds to a node: any document | none |

A sketch of the fields, not final:

```julia
@document struct WorkflowStep <: WorkflowDocument
    title::PrimitiveString
    state::Symbol = :open              # :open, :active, :done, :dropped
    children::CellVector = CellVector() # WorkflowStep and WorkflowDecision
    journal::CellVector = CellVector()  # WorkflowEntry, oldest first
    cards::CellVector = CellVector()    # WorkflowCard
end

@document struct WorkflowDecision <: WorkflowDocument
    question::PrimitiveString
    options::CellVector = CellVector()  # WorkflowOption
    journal::CellVector = CellVector()
    cards::CellVector = CellVector()
end

@document struct WorkflowOption <: WorkflowDocument
    title::PrimitiveString
    state::Symbol = :open              # :open, :chosen, :rejected, :parked
    reason::PrimitiveString             # why it was chosen, rejected or parked
    children::CellVector = CellVector() # the steps that follow it
    journal::CellVector = CellVector()
    cards::CellVector = CellVector()
end

@document struct WorkflowEntry <: WorkflowDocument
    time::String                        # "yyyy-mm-ddTHH:MM:SS", local time
    author::Symbol                      # :person or :assistant
    kind::Symbol                        # :comment, :decision, :state, :link
    text::Any                           # a PrimitiveString, a Markdown node, or any document
    source::Any = nothing               # a conversation turn, or any document
end

@document struct WorkflowCard <: WorkflowDocument
    content::Any                        # any document, shown by its own view
end
```

- **The exploration tree is the decisions and their options.** It is no
  structure of its own. A rejected option keeps its children and its reason.
- **The active work is a state, not a pointer.** Many steps can be `:active` at
  the same time, as parallel work is.
- **A loop is no node type.** A repeat is a new entry, or a copy of the step.
- **A change of state writes an entry.** The operation that changes a state
  adds a `:state` entry with the time and the author, as org-mode logs a TODO
  change. So the journal is complete without a separate history.

### 4.2 The file: `.pred` with markers

A workflow saves as one `.pred` file. A card that holds a node of another file
saves as a marker into that file: a section of a Markdown page, a node of a JSON
file, a definition in a Julia file. A card that holds a document with no file
format of its own, such as a primitive or a widget, is written inside the `.pred`
file. A document of a domain with a file format, such as a JSON object, must be in
a file of that format: the save refuses it and names it (found in step 2). The
project of a workflow is a `FileProject`: the `.pred` file and the files that its
markers name.

The time of an entry is a text, `"2026-10-09T14:02:00"`, so the `.pred` file
writes it as a string and needs no method for a type of `Dates` (see step 1).

### 4.3 A conversation and a workflow link either way

The owner (2026-10-09): "a workflow and a conversation can be connected in
either way".

- **From the workflow:** the `source` of an entry and the `content` of a card can
  hold a conversation turn or a whole conversation.
- **From the conversation:** the `Assistant` gets a field that holds a workflow
  node, or `nothing`. When it holds one, the workflow tools act on that node
  when a call names no other node.

In memory both are the real objects, and a cycle is a cycle. The save writes a
marker where the other file owns the node. A turn that no conversation file
saves is written inside the workflow file, so the workflow keeps the record.

### 4.4 The assistant writes, and the person edits later

The owner (2026-10-09): the assistant writes entries directly, and the person
can edit them later.

The workflow slice adds a small set of tools to the `ToolSet`, in the way of
`register_undo_tools!`:

- record a decision: a question, its options, the chosen option and the reason;
- add an entry: a comment or a link on a node;
- add a step, and change the state of a step or of an option;
- find entries: by text, by author, by kind and by time.

Each tool makes the operation that the UI makes for the person, with
`author = :assistant`, and lets the editor evaluate it. So undo, the log and the
fault barrier apply. The view shows the entries of the assistant in their own
role colour, and the person edits or deletes them as any other entry.

**The assistant writes only at important points.** The owner (2026-10-09):
"not each turn, only important points that the assistant think is valuable". No
summary of the workflow goes into each turn, and the assistant does not log each
turn. The assistant calls the workflow tools when it judges that a point is
valuable: a decision, a rejected option and its reason, a step that is done, a
fact that the work needs later. The descriptions of the tools say what counts as
such a point, so the model knows the workflow and when to use it.

### 4.5 The views

Five projections of the same document. The first three are the core.

**1. Outline.** The main view for edits, and a widget view: `WorkflowToWidget`.
The owner (2026-10-09): "the outline should be a widget view but you can combine
text, markdown, syntax, whatever and widgets in arbitrary ways". So a row is a
widget, and the title, an entry and a card inside it show through the view of
their own domain: text, Markdown, syntax or widgets. One line for each node: the
state, the title, the date of the last entry. A rejected option stays, in grey,
and collapses.

```
▾ ◐ Workflow domain                                  started 10-09
  ▾ ✓ Survey the literature                          done 10-09
  ▾ ? How to store a workflow
      ✗ .pdoc binary               rejected: not diffable, breaks across Julia versions
      ● .pred with markers         chosen 10-09 · person
  ▸ ◐ Outline view                                   active
  ▸ ○ Assistant tools
```

Enter adds a sibling, Tab indents, one key cycles the state, and one key adds an
entry. A card shows under its node, through the view of its own domain.

**2. Journal.** A `WidgetTable` of every entry of the tree, the newest first,
with the filter, the sort and the find of the table. The decision log is this
table with only the `:decision` entries.

**3. Catalog.** A table of the workflow files of a folder: the title, the state
of the root, the active steps, the time of the last entry and the count of open
decisions. To open a row opens the workflow in a tab, which continues it. Many
workflows are open at the same time, each in its own tab, so no operation
switches between them (the owner, 2026-10-09).

**4. Dashboard of the active node (deferred).** One page for "where am I": the
path from the root, the active steps, the next steps, the open decisions, the
last entries and the cards. Cards fill the space; to add or remove one is an
insert or a delete.

```
┌ Workflow domain › Outline view ─────────────────────────────────┐
│ NOW  ◐ Outline view            │ OPEN DECISIONS                  │
│ next ○ key to cycle the state  │ ? one journal for each node     │
├────────────────────────────────┴─────────────────────────────────┤
│ JOURNAL  10-09 14:02 assistant  decision: store as .pred  ↗ turn │
│          10-09 13:40 person     keep the records readable        │
├──────────────────────────────────┬───────────────────────────────┤
│ CARD  page.md § Design (live)    │ CARD  a pivot of the results  │
└──────────────────────────────────┴───────────────────────────────┘
```

**5. Exploration graph (deferred).** The Graph domain draws the decisions and
the options. The chosen path is strong, a dropped branch is grey, and the
pointer over a branch shows its reason.

### 4.6 The first release

The core: the five document types, the `.pred` save with markers, the
operations, the outline, the journal table, the catalog, the assistant tools and
the link to a conversation.

Deferred: the dashboard page, the exploration graph, due dates and schedules,
templates.

Not in the design (the owner, 2026-10-09): a summary of the workflow in each
turn, and an operation that switches to a workflow.

## 5. Steps

- [x] **1. The package triad and the documents.** `ProjecturedWorkflow`,
  `…Example`, `…Test`; the five types of 4.1; the lists of the full set, as
  [domain-inventory.md](../../documentation/design/domain-inventory.md) says.
  Test: `test_workflow_document()`, the layering guard and the naming guard.
  **Done (2026-10-09, branch `workflow`).** 42 tests pass. What was decided:
  - The `time` of an entry is a `String`, `"yyyy-mm-ddTHH:MM:SS"` in local
    time, not a `DateTime`. A `DateTime` in a `.pred` file needs a method of
    `is_pred_constructible` for a type of `Dates` in the domain, which is type
    piracy: two packages that add it collide at precompile. The text sorts in the
    order of time, and `find_workflow_time` reads it back as a `DateTime`.
  - The domain declares its root by hand (`abstract type WorkflowDocument`), as
    Book does, and not with `@domain`: the insertion kit of `@domain` serves a
    syntax view, and the outline is a widget view.
  - `collapsed` is a field of each node and of a card, as in Book, so a fold
    survives a print and a save.
  - Beside the lists of the guide, the registration also needed the CI matrix
    (`.github/workflows/CI.yml`), `DOMAIN_EDGES` of
    `test/projectured/PackageGraphTest.jl`, `test_workflow()` in
    `test/projectured/ProjecturedSuite.jl`, and the summary in
    `PROJECTURED_PACKAGES` of the builder.
- [x] **2. The `.pred` save.** `pred_arguments` and `make_pred_document` where
  the default does not fit. Test: a `FileProject` with a workflow `.pred`, a
  Markdown page and a JSON file saves, loads, and gives the same graph; a card
  into the Markdown section is the same object after the load.
  **Done (2026-10-09).** `test_workflow_file()` in
  `test/projectured/serializer/WorkflowFileTest.jl`, in `test_documents()` of the
  umbrella, 24 tests. The defaults fit every type, so the domain adds no method:
  each node writes its fields as keywords and reads back through its keyword
  constructor. A card into a paragraph of a page writes
  `<<node(file("page.md"), …)>>`, a card into a record of a JSON file writes
  `<<node(file("data.json"), …)>>`, the load gives the same objects, and a second
  save writes nothing. A card that holds a JSON object that no JSON file holds is
  refused with the reason, as the save refuses any node of a format domain that no
  file of its domain writes.
- [x] **3. The operations.** Add and delete a step, a decision, an option, an
  entry and a card; change a state, which adds a `:state` entry; each operation
  carries its author. Test: each operation and its undo.
  **Done (2026-10-09), before step 2.** `test_workflow_edits()`, 69 tests. What
  was decided:
  - No new operation type. Each edit is a builder (`make_workflow_state_operation`,
    `make_insert_workflow_node_operation`, `make_add_workflow_entry_operation`,
    `make_add_workflow_card_operation`, `make_choose_workflow_option_operation`, …)
    that answers a `ReplaceReferencedValueOperation` carrying the node, or a
    `CompoundOperation` of them, as
    [operation.md](../../documentation/package/kernel/operation.md) asks. A carried
    node passes unchanged through every reader above it, and a history takes the
    compound back as one step (tested through an `UndoBuffer`).
  - The author is an argument of the builder (`:person` for the view, `:assistant`
    for a verb), and the entry stores it.
  - To choose an option does not change the other options: the person or the
    assistant rejects or parks each of them, so no state is written that nobody
    decided.
  - The verbs of the assistant (`record_workflow_decision!`,
    `choose_workflow_option!`, `reject_workflow_option!`, `add_workflow_entry!`,
    `add_workflow_step!`, `change_workflow_state!`, `add_workflow_card!`) are in
    the same file. Each takes a node, or a `ReferencedDocument` of it, and lets
    `find_rooted_operation` carry the operation from the node to the root, so the
    history of the tab records it. `collect_workflow_entries` reads the journal of
    a whole tree.
- [x] **4. The outline view.** `WorkflowToWidget`; a title, an entry and a card
  show through the view of their own domain inside a widget row. Test: the
  printer and the reader on an example that holds a Markdown card and a JSON
  card.
  **Done (2026-10-09).** `test_workflow_to_widget()`, 36 tests through a headless
  editor that keeps its IO map; the printer, reader and REPL drivers pass on
  `workflow_example` (19722, 225 and 225 checks). What was decided and found:
  - Three projections, `WorkflowNodeToWidget` (a step, a decision, an option),
    `WorkflowEntryToWidget` and `WorkflowCardToWidget`, each chained with
    `VerticalLayoutToGraphicsCanvas` and registered as rows of the renderer
    (`register_natural_graphics!(:workflow, …)`). The output holds the documents
    of the input, and the renderer draws each one through the view of its own
    domain, so any domain mixes into the outline. The maps translate a path by
    the places of those documents (`_WorkflowSlot`).
  - One computation builds the output and its slots, and the IO map holds both
    as computed cells, as the row view of the data frames does: a change of the
    children, the journal, the cards or the fold builds a new card, and the chain
    prints it again. A layout prints its children once, so a static build showed
    a stale outline after "+ step" (found by the headless editor test).
  - The header row is the first row of the content of the card, not its title:
    `WidgetCard` gives a key only to its content, so a key never reached a title
    in the title slot.
  - A title, a question, a reason and a text entry show as a `WidgetText` whose
    content follows the value of the `PrimitiveString`; the slots map
    `title.value{…}` to `content{…}`, so an edit in the field is an edit of the
    title. It gives prose and a placeholder, so an empty title can be clicked.
  - The state is a `WidgetBadge` in the colour of its role, with a "›" button; a
    press answers `make_workflow_state_operation`. Each button answers its
    operation through a click gesture of its own, as the settings tab does.
  - The example is `workflow_example` in both registries. The navigation sweep
    skips it, for the reason that it skips the table and the pane examples: a
    widget view can not seed a caret with Ctrl+Home.
  - Limits, left for later: the row of add buttons under every node is heavy;
    an added node does not take the caret; a card whose content is a primitive
    draws it in the plain style of the renderer.
- [x] **5. The journal table.** Test: the rows, the order and the decision
  filter.
  **Done (2026-10-09).** `test_workflow_journal_to_widget()`, 11 tests; the
  printer, reader and REPL drivers pass on `workflow_journal_example`. A second
  view of a workflow is a document that holds it, as the data frame view holds a
  frame: `WorkflowJournal(workflow, kind)`, drawn by `WorkflowJournalToWidget` as
  a choice of the kind above a `WidgetTable` of time, author, kind, node and
  text, the newest first. The choice writes `kind` of the journal; `:decision` is
  the decision log. The output is a computed cell, so a new entry anywhere in the
  tree shows at the top. The table is read only: an entry is edited in the
  outline. The plan named "the filter, the sort and the find of the table"; the
  general filter of any table is a pending plan of its own
  (`filter-sort-and-find-any-table.md`), so the journal has the choice of the kind
  only.
- [x] **6. The assistant tools.** The tool descriptions say which points are
  important enough to record. Test: a `ScriptedLlm` turn that records a
  decision, then an undo.
  **Done (2026-10-09), as verbs of the API and not as tools.** The domain calls
  `register_assistant_api!(WorkflowModule => WORKFLOW_ASSISTANT_API)` in its
  `__init__`, as JSON does: the six document types, the seven verbs of 4.4 and
  `collect_workflow_entries`. Reason: a domain has no seam to add a tool to the
  tool set of an editor (the application registers its tools in
  `start_application!`), and the application declares that what the assistant
  may write is verbs that a model finds with `search_api` and calls through
  `execute_julia_code`, so their descriptions cost nothing until it asks. A new
  registry of domain tools would be a new mechanism. The docstring of each verb
  says when to use it: at an important point, never every turn.
  `test_workflow_assistant_api()`, 14 tests: the offered names, a search that
  finds a verb, and the code that a model writes, run by `execute_julia_code!`
  in an editor whose root is an `UndoBuffer`, which records a decision and
  rejects an option; two undos take both back. The test runs the code of the
  tool directly and not a turn of a `ScriptedLlm`: the turn adds the loop of the
  model and nothing of the domain.
- [x] **7. The link to a conversation.** The field of the `Assistant`; its
  `pred_arguments`. Test: a saved assistant and a saved workflow load with the
  link in each direction.
  **Done (2026-10-09).** `test_workflow_conversation()`, 14 tests. The `source` of
  an entry and the `content` of a card hold any document, so a turn of a
  conversation needs nothing new: in a project a turn is written inside the
  workflow file and loads as a `ConversationTurn`. The `Assistant` has the field
  `workflow` (any document, default `nothing`), and its `pred_arguments` write it
  when it holds one; in a project the file of the assistant writes
  `file("work.pred")`, and the load gives the same object. A tab of a workflow is
  named by its goal (`get_document_title`). **Not built:** "the workflow tools act
  on that node when a call names no other node". A verb runs in the code that
  `execute_julia_code` evaluates, and it does not know which assistant calls it;
  to know it would need a new mechanism, so it waits for the owner. Checks of the
  changed `Assistant` in the umbrella: `test_conversation_serialization`,
  `test_assistant_duplicate`, `test_user_interface_file`, `test_assistant_mvp`,
  `test_repository` and `test_documentation` pass. `test_external_agent_turn`
  passes alone (186 tests); in one process with the ACP package it fails, as the
  memory of the ACP plan records for main. The export block of the module
  follows the export guard: one statement for each fragment, in the order of the
  includes.
- [x] **8. The catalog.** Test: a folder of three workflows gives three rows; to
  open a row opens its tab.
  **Done (2026-10-09).** `test_workflow_catalog_to_widget()`, 13 tests.
  `WorkflowCatalog(folder, version)` and `WorkflowCatalogToWidget`: a "Read again"
  button and a table with one row for each `.pred` file of the folder that holds a
  `WorkflowStep`, the latest entry first: the goal, the state, the active steps,
  the last entry, the count of the open decisions and the file. A press on the
  goal answers `OpenFileOperation(path)`, which the pane slice evaluates as the
  Files pane does, so the workflow opens in a tab of its own: no new operation.
  The view reads the folder when it is built, and "Read again" raises `version`.
  No example joins the registries, because a folder is not hermetic. Left for
  later: a button that starts a new workflow, which needs an operation that
  writes a file.

## 6. The answers of the owner (2026-10-09)

1. **Storage:** "we can save .md, .json, but we can also save in .pred format and
   references are durable in that format. we can combine multiple formats using
   references, this is already possible (markdown, pred, julia, json)". So a
   card into another file needs no new locator.
2. **The assistant writes entries directly:** "yes, the user can edit later".
3. **The plan files are not the corpus of the domain:** "no". The domain does not
   read the files in `plan/`.
4. **A link either way:** "a workflow and a conversation can be connected in
   either way".
5. **The assistant writes only at important points:** "not each turn, only
   important points that the assistant think is valuable". No summary goes into
   each turn; see 4.4.
6. **The outline is a widget view that mixes any views:** "the outline should be
   a widget view but you can combine text, markdown, syntax, whatever and widgets
   in arbitrary ways". See 4.5.
7. **No switch operation:** "no, there's no need to switch to a workflow
   operation, the user can have multiple workflows open at a time".

## 7. Open questions

None now.
