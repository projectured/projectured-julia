# Workflow domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [widget.md](../../platform/widget/widget.md), [serialization.md](../../platform/serialization/serialization.md)

The Workflow domain, `ProjecturedWorkflow`, holds the record of a piece of human work: the steps, the decisions and their options, a dated journal on each of them, and the elements of each node: documents of any domain, such as code, a page of text or a table. A person and the assistant write into the same record. This document says where the domain differs from the [shape of every domain](../../../design/domain-anatomy.md).

## How it works

### The documents

A workflow is an AND/OR tree. A step holds its sub-steps, and all of them belong to it; a decision holds its options, and one of them is chosen. The root of a workflow is a step, whose title is the goal.

| Type | Fields that matter |
| --- | --- |
| `WorkflowStep` | `title`, `state` (`:open`, `:active`, `:done`, `:dropped`), `children` (steps and decisions), `journal`, `elements`, `collapsed` |
| `WorkflowDecision` | `question`, `options`, `journal`, `elements`, `collapsed` |
| `WorkflowOption` | `title`, `state` (`:open`, `:chosen`, `:rejected`, `:parked`), `reason`, `children`, `journal`, `elements`, `collapsed` |
| `WorkflowEntry` | `time`, `author` (`:person`, `:assistant`), `kind` (`:comment`, `:decision`, `:state`, `:link`), `text`, `source` |
| `WorkflowJournal` | `workflow`, `kind`: a view of the entries of a whole tree |
| `WorkflowList` | `file_list`, `files`, `table`: the workflows of the open files of an editor |

The exploration tree is the decisions and their options. A rejected option keeps its children and its reason, as the record of a branch that was tried. Many steps can be `:active` at the same time. A loop is no node: a repeat is a new entry or a copy of a step.

The `time` of an entry is a text, `"yyyy-mm-ddTHH:MM:SS"` in local time, which sorts in the order of time; `find_workflow_time` reads it as a `DateTime`. The `text` of an entry and each element hold a document of any domain, such as a Markdown page. An element is the document itself, so a document pasted from a note or from another record keeps its identity and stands at both places. `collapsed` is state of the view (`get_view_state_fields`): the file does not keep it, and an undo does not take it back. The `source` of an entry holds the document it comes from, such as a turn of a conversation.

### The file

A workflow saves as a `.pred` file with the defaults of the format: each node writes its fields as keywords and reads back through its keyword constructor. An element that is a node of another file of the set writes a marker into that file, such as `<<node(file("page.md"), …)>>`, and the load puts the same object back into the element. An element with no file format of its own, such as a primitive, is written as its constructor. An element of a text format that no file of the set writes, such as a JSON object or a Markdown page, is written as the text of its format in a tagged string, `json"""…"""` ([serialization.md](../../platform/serialization/serialization.md#the-pred-format)), so one workflow stays one file. An element that the workflow holds at two places is written once, and the load gives one object again.

### The edits

Each edit is a builder that answers a `ReplaceReferencedValueOperation` that carries the node it writes into, or a `CompoundOperation` of them. A carried node passes unchanged through every reader above it, and a history takes the compound back as one step.

| Builder | What it does |
| --- | --- |
| `make_workflow_state_operation(node, state; author)` | gives a step or an option a state, and writes a `:state` entry |
| `make_insert_workflow_node_operation(parent, index, child)` | inserts a step or a decision under a step or an option, or an option under a decision |
| `make_delete_workflow_node_operation(parent, index)` | removes a child |
| `make_add_workflow_entry_operation(node, entry)` | appends an entry to the journal |
| `make_add_element_operation(node, document)`, `make_remove_element_operation(node, index)`, `make_move_element_operation(node, index, to)` | adds, removes and moves an element, from the outline kit |
| `make_choose_workflow_option_operation(decision, index; reason)` | chooses an option and writes a `:decision` entry; an option chosen before becomes `:open`, and the others keep their states |

`make_workflow_entry` and `make_workflow_decision` make the documents that the builders insert.

### The outline

Two projections draw a workflow as widgets: `WorkflowNodeToWidget` for a step, a decision and an option, and `WorkflowEntryToWidget` for an entry. `make_workflow_graphics_entries` chains each with `VerticalLayoutToGraphicsCanvas`, and the `__init__` of the module registers them as rows of the renderer, so a tab draws a workflow, and a node inside any other document.

The view is a quiet outline of the outline kit ([outline.md](../../platform/outline/outline.md)). The goal heads it, with the counts of the states of the steps under it, the count of the entries of its journal and its "⋯". Under that line stand the entries of the journal of the goal while they are shown, and the elements of the goal, as under the row of any node, because the menu of the goal adds both. Each node under it is a row, indented by its depth along the guide lines of the nodes above it (`make_outline_guides`): the fold, which shows under the pointer, the mark of the node, the title, then the reason of an option, "decided" or "undecided" after a decision, the count of the entries of the journal and the time of the last one, where the date or the hour changes. The mark of a step is a ring in the colour of its state, and a press on it opens the states; a decision is a diamond, and the mark of an option chooses it. The elements of a node stand under its row, each through the view of its own domain in a light inset, with a "⋯" of its own that moves and removes it. The menu of a row, behind the "⋯" that shows under the pointer, holds the states, the adds of a step, a decision or an option, a comment, "Add an element", the fold, Move up and Move down, and the delete. A document pasted while the caret is in the row of a node becomes an element of the node. A step, a decision or an option that the menu adds takes the caret at its title, so the person types it in place. "Add an element" adds a type-in of a kind with the caret in it, and Escape there removes it again. The menu of an element opens it in a new tab, moves it and removes it. A workflow with no step shows one quiet row, "The first step", and the first key typed there makes the first step. The count of the entries after a title is a chip: a press on it shows the entries of the journal of the node under its row, oldest first, each through the view of an entry, and hides them again (`journal_shown`, view state). "Comment" adds an entry at the end of the journal, shows the journal and puts the caret in the new entry. The keys of a row act on its node while the caret is in it: Return at the end of the title adds a sibling after it, Alt+Up and Alt+Down move it among its siblings, Tab makes it the last child of the step or option before it, and Shift+Tab makes it the sibling after its parent; the caret goes with the node.

The output holds the documents of the input that are not prose, and the renderer draws each one through the view of its own domain, so text, Markdown, syntax and widgets mix in one outline, and an edit in an element edits the document itself. The maps translate a path by the places where those documents sit. A title, a question, a reason and the text of an entry that is a `PrimitiveString` show as a quiet `WidgetText` whose content follows the value; the maps send `title.value{…}` to `content{…}` of the field.

One computation builds the output of the tree and the places of its documents, and the IO map holds both as computed cells. A change of the children, the journal, the elements or a fold builds the outline again, and the stage after it prints it again.

### The journal

`WorkflowJournal(workflow, kind)` is a second view of a workflow: a document that holds it, as the data frame view holds a frame. `WorkflowJournalToWidget` draws a choice of the kind above a timeline of every entry of the tree, the newest first: a group for each local day, and a row of the outline kit for each entry, with the avatar of the author and the time beside the text, and the node and the kind under it. The choice `:decision` gives the log of the decisions. The timeline is read only.

### The list of the open workflows

`WorkflowList` is a session document of each editor, as the list of the open files is. `get_session_workflow_list(; editor)` answers it. It holds the open file list of its editor in `file_list`, and `files` computes from it the open files whose document is a `WorkflowStep`: a file page, or the file document when no page holds it. A file comes when a tab or a page shows it, and goes when the last of them closes, so a workflow from any folder is in the list while it is open. The list reads no disk.

The list says `is_session_explorer_entry_type`, so the explorer of each window holds it from the start, after the lists of the session, and `+` adds it as "workflows". Its maker runs with its editor as the editor of the evaluation, so it reads the open file list of that editor. A file of an explorer keeps that it holds the list, and no file and no row.

In the tree, the list has its files as nodes. A file is a layer, so it has the tree of its workflow below it: a step and an option have their children, and a decision its options ([tree.md](../../platform/tree/tree.md)). A press on a file shows the page of the file, so an edit there goes into the history of the file, and Save writes it. A step and an option show their state as an icon and a pill in the colour of the role of the state; a decision shows "open" while no option is chosen. The node of the list counts the open workflows.

`WorkflowListToWidget` draws the page: a line that counts the open workflows and their open decisions, and under it `table`, an arrangement of a roster of the workflows, so a person filters, sorts and groups the rows. The roster has one part for each file, and the item of a part is its workflow, with its file document as `within`. The columns are `goal`, `state`, `active`, `last_entry`, `open_decisions` and `within.name`. All but `state` are facets of `WorkflowStep`:

| Facet | Value |
| --- | --- |
| `goal` | the title as text; for the root of a workflow, its goal |
| `active` | the titles of the active steps of the tree, the step too |
| `last_entry` | the time of the latest entry of the tree, to the minute |
| `open_decisions` | the count of the decisions of the tree that have no chosen option |

`register_roster_source!(:workflows, …)` gives the same rows to `StoreRecords(:workflows)`, so code and the assistant make a roster of the open workflows with `show_roster!`.

### The assistant

The `__init__` calls `register_assistant_api!(WorkflowModule => WORKFLOW_ASSISTANT_API)`: the five document types, the verbs below, `collect_workflow_entries`, `WorkflowList` and `get_session_workflow_list`. The assistant sees the list in the explorer, as `find_explorer_content()` answers it, and reads its rows with the verbs of the roster. A model finds them with `search_api` and calls them through `execute_julia_code`. Each verb writes as the assistant, takes a node or a `ReferencedDocument` of it, and lets the readers of the editor carry the operation from the node to the root, so the history of the tab records it.

| Verb | What it does |
| --- | --- |
| `start_workflow!(title; steps)` | makes a workflow, an active root step with one open step for each entry of `steps`, adds it to the explorer and opens it in a tab above the conversation of the assistant (the group that `pane_group_to_avoid` names becomes a horizontal split, the workflow a third of the height on top; a second workflow joins the top group; with no conversation the tab opens as `open_pane!` places it). The plan of work is a side area, as an explorer is: `accepts_opened_file` is `false` for a `WorkflowStep`, so a pane that a program opens goes to the documents and not into its group: the plan of work of a task of several stages |
| `record_workflow_decision!(node, question, options; chosen, reason)` | records a decision under a step or an option |
| `choose_workflow_option!(decision, index; reason)`, `reject_workflow_option!(decision, index; reason)` | settles an option |
| `add_workflow_entry!(node, text; kind, source)` | writes an entry |
| `add_workflow_step!(node, title)` | adds a step |
| `change_workflow_state!(node, state)` | changes a state |
| `add_element!(node, document)` | adds an element, from the outline kit |

The docstring of each verb says when to use it: at an important point of the work, never at every turn. A plan of work is a workflow and not the `WorkPlan` of an external agent: the agent's plan changes at each update and no file keeps it, while a workflow takes edits, holds what each stage made, and stays with the work. An `Assistant` holds the node of a workflow that its conversation records its work in, in its field `workflow`, and its `.pred` file keeps the link.

## How it fits

`ProjecturedWorkflow` depends on the kernel, the platform and `Dates`, and on no other domain. It uses the widget, layout, natural, serialization, assistant, tree, roster, arrangement and file format slices. No other package depends on it. It registers no file type and no notation: a workflow is a `.pred` file. It adds a kind to the first content of the explorer through `is_session_explorer_entry_type`, and a source of a roster.

## Design decisions

- **One tree for the plan, the rationale and the record.** The steps are the plan, the decisions and their options are the rationale, and the journal is the record, so one document answers what to do, why, and what happened. The plan of the domain gives the literature: `plan/done/a-workflow-records-steps-decisions-and-dates.md`.
- **A plan is a resource, not a program.** No state is enforced: a person skips, repeats and reorders steps, and the journal records it.
- **No new operation type.** Each edit is a builder over the generic write, as [operation.md](../../kernel/operation.md) asks.
- **Verbs, not tools.** A domain offers names to the assistant with `register_assistant_api!`; no seam adds a tool to the tool set of an editor.
- **A verb names its node.** Each verb takes the node that it acts on as its first argument, and the `workflow` of an assistant does not stand in for a node that a call leaves out. A verb does not know which assistant calls it, and an explicit node works the same for the built-in assistant and for an external agent that reaches the editor through MCP. The plan of the domain records the choice.
- **The list holds files, and a press shows the file.** A navigator page prints only the document at its address, so the history of a file does not record an edit on a page below it ([navigator.md](../../platform/navigator/navigator.md)). The nodes of the list are the open files, so a press shows the page of the file, with its history. The plan is `plan/pending/the-explorer-shows-the-open-workflows.md`.
- **The list holds the open file list of its editor.** A source that finds the open file list through the editor of the evaluation caches an empty answer when a read outside the loop computes it first.
- **The header is in the content of the card.** A `WidgetCard` gives a key only to its content, so a title in the title slot of a card would take no key.

## Usage

```julia
workflow = WorkflowStep(title = PrimitiveString("Ship the view"), children = [
    WorkflowStep(title = PrimitiveString("Survey"), state = :done),
    make_workflow_decision("How to store it", [".pdoc", ".pred"]; chosen = 2, reason = "text"),
])
run_example(workflow, make_workflow_projection_example(); name = "workflow")
evaluate_operation(nothing, make_workflow_state_operation(workflow.children[1], :active))
```

- Examples: `workflow_example` and `workflow_journal_example`, from `make_workflow_document_example()`, `make_workflow_journal_document_example()` and `make_workflow_projection_example()`.
- Test: `test_workflow()` runs the layering guard, the documents, the edits, the outline, the journal, the list of the open workflows, the walk-through, the API of the assistant and the link to a conversation. `test_workflow_file()` of the umbrella saves a workflow with markers into a Markdown page and a JSON file, and alone with a JSON and a Markdown element written inline.

## Limits

- The journal has the choice of a kind and no general filter, sort or find.
- The list holds a workflow only while its file is open. A new workflow comes from the explorer: `WorkflowStep` is an entry of a section with the alias "workflow", and a new one has the goal "New workflow".
- A double click on a row of the table of the list opens the page of the workflow below the history of its file, so the history of the file does not record an edit there. A press on the file in the tree shows the page of the file.
- The table of the list does not keep its arrangement when its last entry goes, so the next filter starts a new one.
