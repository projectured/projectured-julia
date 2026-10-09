# Fragment of `WorkflowModule` — the edits of a workflow: the operations that the
# view and the assistant make, and the verbs that the assistant calls.
#
# Each operation is a `ReplaceReferencedValueOperation` that carries the node it
# writes into, or a `CompoundOperation` of such writes, so it passes unchanged
# through every reader above the node, and a history inverts it as any other
# write.

# ── Operations ───────────────────────────────────────────────────────────

const _JOURNAL_PATH = Reference(FieldReferenceStep("journal"))
const _CARDS_PATH = Reference(FieldReferenceStep("cards"))

"""
    make_add_workflow_entry_operation(node, entry) -> Operation

Append `entry` to the journal of `node`.
"""
make_add_workflow_entry_operation(node, entry::WorkflowEntry) =
    make_insert_elements_operation(_JOURNAL_PATH, length(node.journal) + 1, Any[entry];
                                   root = node)

"""
    make_workflow_entry(text; author = :person, kind = :comment, source = nothing,
                        time = get_workflow_time()) -> WorkflowEntry

A new entry that says `text`: a string becomes a `PrimitiveString`, and a
document stays as it is.
"""
make_workflow_entry(text; author::Symbol = :person, kind::Symbol = :comment, source = nothing,
                    time::AbstractString = get_workflow_time()) =
    WorkflowEntry(time = String(time), author = _check_author(author), kind = _check_kind(kind),
                  text = _make_text(text), source = source)

"""
    make_workflow_state_operation(node, state; author = :person, time = get_workflow_time())
        -> CompoundOperation

Give `node`, a step or an option, the state `state`, and write a `:state` entry
that names the state into its journal.
"""
function make_workflow_state_operation(node::Union{WorkflowStep, WorkflowOption}, state::Symbol;
                                       author::Symbol = :person,
                                       time::AbstractString = get_workflow_time())
    state in get_workflow_states(node) ||
        throw(ArgumentError("A " * string(nameof(typeof(node))) * " has no state :" * string(state) *
                            "; its states are " * join((":" * string(s) for s in get_workflow_states(node)), ", ") * "."))
    entry = make_workflow_entry(String(state); author, kind = :state, time)
    CompoundOperation(Any[ReplaceReferencedValueOperation(node, "state", state),
                          make_add_workflow_entry_operation(node, entry)])
end

"""
    get_next_workflow_state(node) -> Symbol

The state after the state of `node`, in the order of `get_workflow_states`,
around the end.
"""
function get_next_workflow_state(node::Union{WorkflowStep, WorkflowOption})
    states = get_workflow_states(node)
    index = something(findfirst(==(node.state), states), 0)
    states[mod1(index + 1, length(states))]
end

"""
    make_insert_workflow_node_operation(parent, index, child) -> Operation

Insert `child` among the children of `parent`, so that it is the child at the
1-based `index`. A decision takes an option; a step and an option take a step or
a decision.
"""
function make_insert_workflow_node_operation(parent, index::Integer, child)
    _check_child(parent, child)
    make_insert_elements_operation(Reference(FieldReferenceStep(String(_get_children_field(parent)))),
                                   index, Any[child]; root = parent)
end

"""
    make_delete_workflow_node_operation(parent, index) -> Operation

Remove the child at the 1-based `index` from the children of `parent`.
"""
make_delete_workflow_node_operation(parent, index::Integer) =
    make_delete_elements_operation(Reference(FieldReferenceStep(String(_get_children_field(parent)))),
                                   index; root = parent)

"""
    make_add_workflow_card_operation(node, card) -> Operation

Append `card` to the cards of `node`.
"""
make_add_workflow_card_operation(node, card::WorkflowCard) =
    make_insert_elements_operation(_CARDS_PATH, length(node.cards) + 1, Any[card]; root = node)

"""
    make_delete_workflow_card_operation(node, index) -> Operation

Remove the card at the 1-based `index` from the cards of `node`.
"""
make_delete_workflow_card_operation(node, index::Integer) =
    make_delete_elements_operation(_CARDS_PATH, index; root = node)

"""
    make_workflow_decision(question, options; chosen = 0, reason = "", author = :person,
                           time = get_workflow_time()) -> WorkflowDecision

A new decision that asks `question`, with one open option for each of `options`.
When `chosen` is the index of an option, that option is `:chosen` with `reason`,
and the journal of the decision holds a `:decision` entry that names it.
"""
function make_workflow_decision(question, options; chosen::Integer = 0, reason = "",
                                author::Symbol = :person,
                                time::AbstractString = get_workflow_time())
    made = Any[WorkflowOption(title = _make_text(option)) for option in options]
    0 <= chosen <= length(made) ||
        throw(ArgumentError("`chosen` is " * string(chosen) * ", and the decision has " *
                            string(length(made)) * " options."))
    journal = Any[]
    if chosen > 0
        made[chosen].state = :chosen
        made[chosen].reason = _make_text(reason)
        push!(journal, make_workflow_entry(_describe_choice(made[chosen], reason);
                                           author, kind = :decision, time))
    end
    WorkflowDecision(question = _make_text(question), options = made, journal = journal)
end

"""
    make_choose_workflow_option_operation(decision, index; reason = "", author = :person,
                                          time = get_workflow_time()) -> CompoundOperation

Choose the option at the 1-based `index` of `decision`, for `reason`, and write a
`:decision` entry that names it into the journal of the decision. The other
options keep their states: a person rejects or parks each of them.
"""
function make_choose_workflow_option_operation(decision::WorkflowDecision, index::Integer;
                                               reason = "", author::Symbol = :person,
                                               time::AbstractString = get_workflow_time())
    option = decision.options[index]
    entry = make_workflow_entry(_describe_choice(option, reason); author, kind = :decision, time)
    CompoundOperation(Any[ReplaceReferencedValueOperation(option, "state", :chosen),
                          ReplaceReferencedValueOperation(option, "reason", _make_text(reason)),
                          make_add_workflow_entry_operation(decision, entry)])
end

_describe_choice(option, reason) =
    (r = _get_plain_text(reason); isempty(r) ? "Chose " * option.title.value * "." :
                                               "Chose " * option.title.value * ": " * r)

_get_plain_text(text::AbstractString) = String(text)
_get_plain_text(text::PrimitiveString) = text.value
_get_plain_text(text) = ""

_make_text(text::AbstractString) = PrimitiveString(String(text))
_make_text(text::Document) = text
_make_text(text) = PrimitiveString(string(text))

_check_author(author::Symbol) =
    author in WORKFLOW_ENTRY_AUTHORS ? author :
        throw(ArgumentError("An entry has no author :" * string(author) * "; its authors are :person and :assistant."))

_check_kind(kind::Symbol) =
    kind in WORKFLOW_ENTRY_KINDS ? kind :
        throw(ArgumentError("An entry has no kind :" * string(kind) * "; its kinds are " *
                            join((":" * string(k) for k in WORKFLOW_ENTRY_KINDS), ", ") * "."))

function _check_child(parent::WorkflowDecision, child)
    child isa WorkflowOption ||
        throw(ArgumentError("A decision holds options, and this is a " * string(nameof(typeof(child))) * "."))
    nothing
end

function _check_child(parent::Union{WorkflowStep, WorkflowOption}, child)
    child isa Union{WorkflowStep, WorkflowDecision} ||
        throw(ArgumentError("A step and an option hold steps and decisions, and this is a " *
                            string(nameof(typeof(child))) * "."))
    nothing
end

# ── The verbs of the assistant ───────────────────────────────────────────
#
# Each verb takes a node as a `ReferencedDocument`, makes the operation above, and
# lets the readers of the editor carry it from the node to the root, so the
# history of the tab that shows the workflow records it, as it records an edit of
# the person. A workflow that no view shows takes the operation directly.

function _evaluate_workflow_operation!(editor, node, operation, description)
    if node isa ReferencedDocument && editor isa Editor && editor.iomap !== nothing
        rooted = find_rooted_operation(editor, get_reference(node), relative -> operation;
                                       description)
        rooted === nothing || return evaluate_operation(editor, rooted)
    end
    evaluate_operation(editor, operation)
end

"""
    record_workflow_decision!(node, question, options; chosen = 0, reason = "",
                              editor = get_evaluation_editor()) -> ReferencedDocument

Record a decision under the step or the option `node`: the question, its options,
and, when `chosen` is the index of one, the chosen option and the reason. Answer
the new decision. The entry of the decision says that you made it.

Use it at an important point of the work: when a question with more than one
answer is settled, or when the person must settle one. Record the options that
were rejected too, with `reject_workflow_option!`, so the record shows what was
tried. Do not record every turn.

# Example

    record_workflow_decision!(step, "How to store a workflow",
                              [".pdoc binary", ".pred with markers"];
                              chosen = 2, reason = "a reference into another file is durable")
"""
function record_workflow_decision!(node, question, options; chosen::Integer = 0, reason = "",
                                   editor = get_evaluation_editor())
    parent = get_document(node)
    decision = make_workflow_decision(question, options; chosen, reason, author = :assistant)
    index = length(get_workflow_node_children(parent)) + 1
    _evaluate_workflow_operation!(editor, node,
        make_insert_workflow_node_operation(parent, index, decision),
        "Record the decision " * repr(_get_plain_text(question)))
    _get_child(node, index)
end

"""
    choose_workflow_option!(decision, index; reason = "", editor = get_evaluation_editor())
        -> ReferencedDocument

Choose the option at the 1-based `index` of `decision`, for `reason`, and write a
`:decision` entry by you into the journal of the decision. Answer the decision.
"""
function choose_workflow_option!(decision, index::Integer; reason = "",
                                 editor = get_evaluation_editor())
    _evaluate_workflow_operation!(editor, decision,
        make_choose_workflow_option_operation(get_document(decision), index; reason,
                                              author = :assistant),
        "Choose an option")
    decision
end

"""
    reject_workflow_option!(decision, index; reason = "", editor = get_evaluation_editor())
        -> ReferencedDocument

Reject the option at the 1-based `index` of `decision`, for `reason`. The option
stays, with its steps and its reason, as the record of a branch that was tried.
Answer the decision.
"""
function reject_workflow_option!(decision, index::Integer; reason = "",
                                 editor = get_evaluation_editor())
    option = get_document(decision).options[index]
    operation = CompoundOperation(Any[
        make_workflow_state_operation(option, :rejected; author = :assistant),
        ReplaceReferencedValueOperation(option, "reason", _make_text(reason))])
    _evaluate_workflow_operation!(editor, decision, operation, "Reject an option")
    decision
end

"""
    add_workflow_entry!(node, text; kind = :comment, source = nothing,
                        editor = get_evaluation_editor()) -> ReferencedDocument

Write an entry by you into the journal of `node`: a step, a decision or an
option. `text` is a string or a document, such as a Markdown page. `kind` is
`:comment`, `:decision` or `:link`; `source` is the document the entry comes
from, such as a turn of the conversation. Answer `node`.

Use it for a fact that the work needs later: a finding, a constraint, a result,
a link to a document. Do not record every turn.
"""
function add_workflow_entry!(node, text; kind::Symbol = :comment, source = nothing,
                             editor = get_evaluation_editor())
    entry = make_workflow_entry(text; author = :assistant, kind, source)
    _evaluate_workflow_operation!(editor, node,
        make_add_workflow_entry_operation(get_document(node), entry), "Add an entry")
    node
end

"""
    add_workflow_step!(node, title; editor = get_evaluation_editor()) -> ReferencedDocument

Add an open step that says `title` after the last child of `node`, a step or an
option. Answer the new step.
"""
function add_workflow_step!(node, title; editor = get_evaluation_editor())
    parent = get_document(node)
    index = length(get_workflow_node_children(parent)) + 1
    _evaluate_workflow_operation!(editor, node,
        make_insert_workflow_node_operation(parent, index, WorkflowStep(title = _make_text(title))),
        "Add the step " * repr(_get_plain_text(title)))
    _get_child(node, index)
end

"""
    change_workflow_state!(node, state; editor = get_evaluation_editor()) -> ReferencedDocument

Give the step or the option `node` the state `state`, and write a `:state` entry
by you that names it. A step is `:open`, `:active`, `:done` or `:dropped`; an
option is `:open`, `:chosen`, `:rejected` or `:parked`. Answer `node`.

Use it when a step starts, when it is done, or when it is dropped.
"""
function change_workflow_state!(node, state::Symbol; editor = get_evaluation_editor())
    _evaluate_workflow_operation!(editor, node,
        make_workflow_state_operation(get_document(node), state; author = :assistant),
        "Change the state to :" * string(state))
    node
end

"""
    add_workflow_card!(node, content; title = "", editor = get_evaluation_editor())
        -> ReferencedDocument

Add a card that shows the document `content` to `node`: a step, a decision or an
option. The card shows `content` through the view of its own domain, and an edit
in the card edits `content`. Answer `node`.

Use it to keep a document that the work needs in view: a table, a chart, a part
of a file.
"""
function add_workflow_card!(node, content; title = "", editor = get_evaluation_editor())
    card = WorkflowCard(title = _make_text(title), content = get_document(content))
    _evaluate_workflow_operation!(editor, node,
        make_add_workflow_card_operation(get_document(node), card), "Add a card")
    node
end

# The child at `index` of `node`, as a `ReferencedDocument` when `node` is one.
function _get_child(node::ReferencedDocument, index::Integer)
    field = _get_children_field(get_document(node))
    getproperty(node, field)[index]
end
_get_child(node, index::Integer) = get_workflow_node_children(node)[index]

# ── Reading ──────────────────────────────────────────────────────────────

"""
    collect_workflow_entries(workflow; author = nothing, kind = nothing, text = "")
        -> Vector{Pair}

Every entry of the tree under `workflow`, the oldest first, as `node => entry`.
`author` and `kind` keep only the entries of that author or kind; `text` keeps
only the entries whose text holds it, without regard to case.

Use it to read what was decided and found before you continue a workflow.
"""
function collect_workflow_entries(workflow; author::Union{Nothing, Symbol} = nothing,
                                  kind::Union{Nothing, Symbol} = nothing, text::AbstractString = "")
    found = Pair{Any, WorkflowEntry}[]
    _collect_entries!(found, get_document(workflow))
    needle = lowercase(String(text))
    filter!(found) do (_, entry)
        (author === nothing || entry.author === author) &&
        (kind === nothing || entry.kind === kind) &&
        (isempty(needle) || occursin(needle, lowercase(_get_entry_text(entry))))
    end
    sort!(found; by = pair -> last(pair).time)
end

function _collect_entries!(found, node)
    is_workflow_node(node) || return found
    for entry in node.journal
        push!(found, node => entry)
    end
    for child in get_workflow_node_children(node)
        _collect_entries!(found, child)
    end
    found
end

_get_entry_text(entry::WorkflowEntry) = _get_plain_text(entry.text)
