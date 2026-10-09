# Fragment of `WorkflowModule` — the workflow document types: a step, a
# decision, an option of a decision, an entry of a journal, and a card that
# holds a document of any domain.

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
- `cards` — the `WorkflowCard`s that a person or the assistant added.
- `collapsed` — the view shows the title row only.
"""
@document struct WorkflowStep <: WorkflowDocument
    title::PrimitiveString = PrimitiveString("")
    state::Symbol = :open
    children::CellVector = CellVector()
    journal::CellVector = CellVector()
    cards::CellVector = CellVector()
    collapsed::Bool = false
end

"""
A branch point of a workflow, as a question. Its options are the answers, and
one of them is chosen (OR).

- `question` — what is to be decided.
- `options` — the `WorkflowOption`s, in order.
- `journal`, `cards` and `collapsed` — as for a `WorkflowStep`.
"""
@document struct WorkflowDecision <: WorkflowDocument
    question::PrimitiveString = PrimitiveString("")
    options::CellVector = CellVector()
    journal::CellVector = CellVector()
    cards::CellVector = CellVector()
    collapsed::Bool = false
end

"""
One answer to the question of a `WorkflowDecision`.

- `title` — the answer.
- `state` — `:open`, `:chosen`, `:rejected` or `:parked`. A rejected option
  keeps its children and its reason: it is the record of a branch that was tried.
- `reason` — why the option has its state.
- `children` — the steps and the decisions that follow the option.
- `journal`, `cards` and `collapsed` — as for a `WorkflowStep`.
"""
@document struct WorkflowOption <: WorkflowDocument
    title::PrimitiveString = PrimitiveString("")
    state::Symbol = :open
    reason::PrimitiveString = PrimitiveString("")
    children::CellVector = CellVector()
    journal::CellVector = CellVector()
    cards::CellVector = CellVector()
    collapsed::Bool = false
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
"""
@document struct WorkflowEntry <: WorkflowDocument
    time::String = ""
    author::Symbol = :person
    kind::Symbol = :comment
    text::Any = PrimitiveString("")
    source::Any = nothing
end

"""
Content that a person or the assistant adds to a node: a document of any
domain, shown through the view of its own domain.

- `title` — what the card shows, or an empty text.
- `content` — the document. A document that another file owns is written to
  the file of the workflow as a marker into that file.
- `collapsed` — the view shows the title only.
"""
@document struct WorkflowCard <: WorkflowDocument
    title::PrimitiveString = PrimitiveString("")
    content::Any = nothing
    collapsed::Bool = false
end

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

"""
    get_workflow_states(node) -> Tuple

The states that `node` can have, in the order that a press steps through them.
"""
get_workflow_states(::WorkflowStep) = WORKFLOW_STEP_STATES
get_workflow_states(::WorkflowOption) = WORKFLOW_OPTION_STATES

"""
    is_workflow_node(document) -> Bool

Whether `document` is a node of the tree of a workflow: a step, a decision or
an option. A node has a journal and cards.
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
