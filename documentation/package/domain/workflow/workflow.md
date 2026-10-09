# Workflow domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [widget.md](../../platform/widget/widget.md), [serialization.md](../../platform/serialization/serialization.md)

The Workflow domain, `ProjecturedWorkflow`, holds the record of a piece of human work: the steps, the decisions and their options, a dated journal on each of them, and cards that show documents of any domain. A person and the assistant write into the same record. This document says where the domain differs from the [shape of every domain](../../../design/domain-anatomy.md).

## How it works

### The documents

A workflow is an AND/OR tree. A step holds its sub-steps, and all of them belong to it; a decision holds its options, and one of them is chosen. The root of a workflow is a step, whose title is the goal.

| Type | Fields that matter |
| --- | --- |
| `WorkflowStep` | `title`, `state` (`:open`, `:active`, `:done`, `:dropped`), `children` (steps and decisions), `journal`, `cards`, `collapsed` |
| `WorkflowDecision` | `question`, `options`, `journal`, `cards`, `collapsed` |
| `WorkflowOption` | `title`, `state` (`:open`, `:chosen`, `:rejected`, `:parked`), `reason`, `children`, `journal`, `cards`, `collapsed` |
| `WorkflowEntry` | `time`, `author` (`:person`, `:assistant`), `kind` (`:comment`, `:decision`, `:state`, `:link`), `text`, `source` |
| `WorkflowCard` | `title`, `content`, `collapsed` |
| `WorkflowJournal` | `workflow`, `kind`: a view of the entries of a whole tree |

The exploration tree is the decisions and their options. A rejected option keeps its children and its reason, as the record of a branch that was tried. Many steps can be `:active` at the same time. A loop is no node: a repeat is a new entry or a copy of a step.

The `time` of an entry is a text, `"yyyy-mm-ddTHH:MM:SS"` in local time, which sorts in the order of time; `find_workflow_time` reads it as a `DateTime`. The `text` of an entry and the `content` of a card hold a document of any domain, such as a Markdown page. The `source` of an entry holds the document it comes from, such as a turn of a conversation.

### The file

A workflow saves as a `.pred` file with the defaults of the format: each node writes its fields as keywords and reads back through its keyword constructor. A card that holds a node of another file writes a marker into that file, such as `<<node(file("page.md"), …)>>`, and the load puts the same object back into the card. A card that holds a document with no file format of its own, such as a primitive, is written inside the `.pred` file. A document of a domain with a file format, such as a JSON object, must be in a file of that format; the save refuses it and names it.

### The edits

Each edit is a builder that answers a `ReplaceReferencedValueOperation` that carries the node it writes into, or a `CompoundOperation` of them. A carried node passes unchanged through every reader above it, and a history takes the compound back as one step.

| Builder | What it does |
| --- | --- |
| `make_workflow_state_operation(node, state; author)` | gives a step or an option a state, and writes a `:state` entry |
| `make_insert_workflow_node_operation(parent, index, child)` | inserts a step or a decision under a step or an option, or an option under a decision |
| `make_delete_workflow_node_operation(parent, index)` | removes a child |
| `make_add_workflow_entry_operation(node, entry)` | appends an entry to the journal |
| `make_add_workflow_card_operation(node, card)`, `make_delete_workflow_card_operation(node, index)` | adds and removes a card |
| `make_choose_workflow_option_operation(decision, index; reason)` | chooses an option and writes a `:decision` entry; the other options keep their states |

`make_workflow_entry` and `make_workflow_decision` make the documents that the builders insert.

### The outline

Three projections draw a workflow as widgets: `WorkflowNodeToWidget` for a step, a decision and an option, `WorkflowEntryToWidget` and `WorkflowCardToWidget`. `make_workflow_graphics_entries` chains each with `VerticalLayoutToGraphicsCanvas`, and the `__init__` of the module registers them as rows of the renderer, so a tab draws a workflow, and a node inside any other document.

A node is a card. Its first row holds a button that folds it, the state as a badge in the colour of its role with a button that steps it, the title and the time of the last entry. Under that row stand the reason of an option, the journal, the cards and the children, then a row of buttons that add a step, a decision, an option, a comment and a card. A card and a child each have a button that removes them.

The output holds the documents of the input, and the renderer draws each one through the view of its own domain, so text, Markdown, syntax and widgets mix in one outline, and an edit in a card edits its content. The maps translate a path by the places where those documents sit. A title, a question, a reason and the text of an entry that is a `PrimitiveString` show as a `WidgetText` whose content follows the value, so they draw as prose with a placeholder; the maps send `title.value{…}` to `content{…}` of the field.

One computation builds the output of a node and the places of its documents, and the IO map holds both as computed cells. A change of the children, the journal, the cards or the fold builds a new card, and the stage after it prints the card again.

### The journal

`WorkflowJournal(workflow, kind)` is a second view of a workflow: a document that holds it, as the data frame view holds a frame. `WorkflowJournalToWidget` draws a choice of the kind above a table of every entry of the tree, the newest first: the time, the author, the kind, the node and the text. The choice `:decision` gives the log of the decisions. The table is read only.

### The assistant

The `__init__` calls `register_assistant_api!(WorkflowModule => WORKFLOW_ASSISTANT_API)`: the six document types, the verbs below and `collect_workflow_entries`. A model finds them with `search_api` and calls them through `execute_julia_code`. Each verb writes as the assistant, takes a node or a `ReferencedDocument` of it, and lets the readers of the editor carry the operation from the node to the root, so the history of the tab records it.

| Verb | What it does |
| --- | --- |
| `record_workflow_decision!(node, question, options; chosen, reason)` | records a decision under a step or an option |
| `choose_workflow_option!(decision, index; reason)`, `reject_workflow_option!(decision, index; reason)` | settles an option |
| `add_workflow_entry!(node, text; kind, source)` | writes an entry |
| `add_workflow_step!(node, title)` | adds a step |
| `change_workflow_state!(node, state)` | changes a state |
| `add_workflow_card!(node, content; title)` | adds a card |

The docstring of each verb says when to use it: at an important point of the work, never at every turn. An `Assistant` holds the node of a workflow that its conversation records its work in, in its field `workflow`, and its `.pred` file keeps the link.

## How it fits

`ProjecturedWorkflow` depends on the kernel, the platform and `Dates`, and on no other domain. It uses the widget, layout, natural, serialization and assistant slices. No other package depends on it. It registers no file type and no notation: a workflow is a `.pred` file.

## Design decisions

- **One tree for the plan, the rationale and the record.** The steps are the plan, the decisions and their options are the rationale, and the journal is the record, so one document answers what to do, why, and what happened. The plan of the domain gives the literature: `plan/done/a-workflow-records-steps-decisions-and-dates.md`.
- **A plan is a resource, not a program.** No state is enforced: a person skips, repeats and reorders steps, and the journal records it.
- **No new operation type.** Each edit is a builder over the generic write, as [operation.md](../../kernel/operation.md) asks.
- **Verbs, not tools.** A domain offers names to the assistant with `register_assistant_api!`; no seam adds a tool to the tool set of an editor.
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
- Test: `test_workflow()` runs the layering guard, the documents, the edits, the outline, the journal, the API of the assistant and the link to a conversation. `test_workflow_file()` of the umbrella saves a workflow with markers into a Markdown page and a JSON file.

## Limits

- The row of add buttons stands under every node, and an added node does not take the caret.
- A card whose content is a primitive draws it in the plain style of the renderer.
- The journal has the choice of a kind and no general filter, sort or find.
- A verb takes its node as an argument: the `workflow` of an assistant is not the node that a verb acts on when a call names none, because a verb does not know which assistant calls it.
