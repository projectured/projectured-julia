# Fragment of `WorkflowModule` — the workflow document types: a step, a
# decision, an option of a decision, and an entry of a journal. A node holds the
# documents of any domain that the work needs as its elements.

abstract type WorkflowDocument <: Document end

# ── The tree ─────────────────────────────────────────────────────────────

"""
A thing to do. The root of a workflow is a step: its title is the goal of the
workflow.

- `title` — what the step is.
- `state` — `:open`, `:active`, `:done` or `:dropped`. Many steps can be
  `:active` at the same time, as parallel work is.
- `children` — the sub-steps and the decisions of the step, in order. Each one
  is a `WorkflowStep` or a `WorkflowDecision`, and all of them belong to the
  step (AND).
- `journal` — the `WorkflowEntry`s of the step, the oldest first.
- `elements` — documents of any domain that a person or the assistant added,
  such as code, a page of text, a table or a chart; the outline draws each
  through the view of its own domain. A document that another file owns is
  written to the file of the workflow as a marker into that file, and one of a
  text format that no file writes as its text.
- `collapsed` — the view shows the title row only. It is state of the view: the
  file leaves it out.
- `journal_shown` — the view shows the entries of the journal under the row. It
  is state of the view too.
- `first_text` — the quiet row that the outline of a workflow with no step
  shows, where the first key a person types makes the first step. It is state of
  the view.

Use it to read or build a thing to do in a workflow, with its sub-steps.

# Example

    step_1 = WorkflowStep(title = PrimitiveString("Write the view"), state = :active)

See also `add_workflow_step!`, `change_workflow_state!`.
"""
@document struct WorkflowStep <: WorkflowDocument
    title::PrimitiveString = PrimitiveString("")
    state::Symbol = :open
    children::CellVector = CellVector()
    journal::CellVector = CellVector()
    elements::CellVector = CellVector()
    collapsed::Bool = false
    journal_shown::Bool = false
    first_text::PrimitiveString = PrimitiveString("")
end

"""
A branch point of a workflow, as a question. Its options are the answers, and
one of them is chosen (OR).

- `question` — what is to be decided.
- `options` — the `WorkflowOption`s, in order.
- `journal`, `elements`, `collapsed` and `journal_shown` — as for a `WorkflowStep`.

Use it to read or build a branch point of a workflow, with its options.

# Example

    decision_1 = WorkflowDecision(question = PrimitiveString("Where does the view live?"))

See also `record_workflow_decision!`, `WorkflowOption`.
"""
@document struct WorkflowDecision <: WorkflowDocument
    question::PrimitiveString = PrimitiveString("")
    options::CellVector = CellVector()
    journal::CellVector = CellVector()
    elements::CellVector = CellVector()
    collapsed::Bool = false
    journal_shown::Bool = false
end

"""
One answer to the question of a `WorkflowDecision`.

- `title` — the answer.
- `state` — `:open`, `:chosen`, `:rejected` or `:parked`. A rejected option
  keeps its children and its reason: it is the record of a branch that was tried.
- `reason` — why the option has its state.
- `children` — the steps and the decisions that follow the option.
- `journal`, `elements`, `collapsed` and `journal_shown` — as for a `WorkflowStep`.

Use it to read or build one answer of a decision, with its state and reason.

# Example

    option_1 = WorkflowOption(title = PrimitiveString("a widget view"), state = :chosen)

See also `choose_workflow_option!`, `WorkflowDecision`.
"""
@document struct WorkflowOption <: WorkflowDocument
    title::PrimitiveString = PrimitiveString("")
    state::Symbol = :open
    reason::PrimitiveString = PrimitiveString("")
    children::CellVector = CellVector()
    journal::CellVector = CellVector()
    elements::CellVector = CellVector()
    collapsed::Bool = false
    journal_shown::Bool = false
end

# ── The record ───────────────────────────────────────────────────────────

"""
A dated record on a node of a workflow.

- `time` — when the entry was made: local time, as the text
  `"yyyy-mm-ddTHH:MM:SS"`, which sorts in the order of time.
- `author` — `:person` or `:assistant`.
- `kind` — `:comment`, `:decision`, `:state` or `:link`.
- `text` — what the entry says: a `PrimitiveString`, or a document of any
  domain, such as a Markdown page.
- `source` — the document the entry comes from, such as a turn of a
  conversation, or `nothing`.

Use it to read a dated record in the journal of a node.

# Example

    entry_1 = make_workflow_entry("The view embeds an element."; author = :assistant)

See also `add_workflow_entry!`, `collect_workflow_entries`.
"""
@document struct WorkflowEntry <: WorkflowDocument
    time::String = ""
    author::Symbol = :person
    kind::Symbol = :comment
    text::Any = PrimitiveString("")
    source::Any = nothing
end

# ── The views ────────────────────────────────────────────────────────────

"""
The journal of a whole workflow as a document of its own: a view that shows every
entry of the tree of `workflow`, the newest first.

- `workflow` — the root of the workflow, which the view reads and does not copy.
- `kind` — `:all`, or the kind of the entries that the view shows, such as
  `:decision` for the log of the decisions.

Use it to show the entries of a whole workflow as one document.

# Example

    journal_1 = WorkflowJournal(workflow = workflow_1, kind = :decision)

See also `collect_workflow_entries`, `WorkflowEntry`.
"""
@document struct WorkflowJournal <: WorkflowDocument
    workflow::Any = nothing
    kind::Symbol = :all
end

# Which nodes an outline shows folded is state of the view, not a thing the
# workflow says: the file and a search leave it out.
get_view_state_fields(::Type{<:Union{WorkflowStep, WorkflowDecision, WorkflowOption}}) = (:collapsed, :journal_shown)
get_view_state_fields(::Type{<:WorkflowStep}) = (:collapsed, :journal_shown, :first_text)

# A person adds a new empty workflow by name, as an entry of an explorer or in a tab.
get_insertion_aliases(::Type{WorkflowStep}) = ["workflow"]
make_insertion_document(::Type{WorkflowStep}) = WorkflowStep(title = PrimitiveString("New workflow"))
is_explorer_entry_type(::Type{WorkflowStep}) = true

# A plan of work is a side area, as an explorer is: a pane that a program opens
# goes to the documents, and not into the group of the plan.
accepts_opened_file(::WorkflowStep) = false

# The name of a tab that shows a node of a workflow or its journal: the text that
# names the node.
get_document_title(node::Union{WorkflowStep, WorkflowDecision, WorkflowOption}) =
    get_workflow_node_title(node).value
get_document_title(journal::WorkflowJournal) =
    journal.workflow === nothing ? "Journal" : "Journal of " * get_document_title(journal.workflow)

# ── The values of the fields ─────────────────────────────────────────────

"The states of a `WorkflowStep`, in the order that a press steps through them."
const WORKFLOW_STEP_STATES = (:open, :active, :done, :dropped)

"The states of a `WorkflowOption`, in the order that a press steps through them."
const WORKFLOW_OPTION_STATES = (:open, :chosen, :rejected, :parked)

"The kinds of a `WorkflowEntry`."
const WORKFLOW_ENTRY_KINDS = (:comment, :decision, :state, :link)

"The authors of a `WorkflowEntry`."
const WORKFLOW_ENTRY_AUTHORS = (:person, :assistant)

# The form of the `time` of an entry.
const _WORKFLOW_TIME_FORMAT = Dates.DateFormat("yyyy-mm-ddTHH:MM:SS")

"""
    format_workflow_time(time::DateTime) -> String

The text that the `time` of a `WorkflowEntry` holds for `time`.
"""
format_workflow_time(time::Dates.DateTime) = Dates.format(time, _WORKFLOW_TIME_FORMAT)

"""
    get_workflow_time() -> String

The text that the `time` of a `WorkflowEntry` made now holds: the local time,
to the second.
"""
get_workflow_time() = format_workflow_time(Dates.now())

"""
    find_workflow_time(entry::WorkflowEntry) -> Union{DateTime, Nothing}

The time of `entry` as a `DateTime`, or `nothing` when its text is not a time.
"""
function find_workflow_time(entry::WorkflowEntry)
    text = entry.time
    isempty(text) && return nothing
    try
        Dates.DateTime(text, _WORKFLOW_TIME_FORMAT)
    catch
        nothing
    end
end

# The time of an entry as a person reads it, to the minute: `"2026-10-09 14:02"`. A
# text that is not a time stays as it is.
function _format_readable_time(text::AbstractString)
    time = isempty(text) ? nothing : find_workflow_time(WorkflowEntry(time = String(text)))
    time === nothing ? String(text) : Dates.format(time, "yyyy-mm-dd HH:MM")
end

"""
    get_workflow_states(node) -> Tuple

The states that `node` can have, in the order that a press steps through them.
"""
get_workflow_states(::WorkflowStep) = WORKFLOW_STEP_STATES
get_workflow_states(::WorkflowOption) = WORKFLOW_OPTION_STATES

"""
    is_workflow_node(document) -> Bool

Whether `document` is a node of the tree of a workflow: a step, a decision or
an option. A node has a journal and elements.
"""
is_workflow_node(document) = document isa Union{WorkflowStep, WorkflowDecision, WorkflowOption}

"""
    get_workflow_node_title(node) -> PrimitiveString

The text that names `node`: the title of a step or an option, the question of a
decision.
"""
get_workflow_node_title(node::WorkflowStep) = node.title
get_workflow_node_title(node::WorkflowOption) = node.title
get_workflow_node_title(node::WorkflowDecision) = node.question

"""
    get_workflow_node_children(node) -> CellVector

The nodes below `node` in the tree: the children of a step or an option, the
options of a decision.
"""
get_workflow_node_children(node::WorkflowStep) = node.children
get_workflow_node_children(node::WorkflowOption) = node.children
get_workflow_node_children(node::WorkflowDecision) = node.options

# The name of the field that `get_workflow_node_children` reads.
_get_children_field(::Union{WorkflowStep, WorkflowOption}) = :children
_get_children_field(::WorkflowDecision) = :options
