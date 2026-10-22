# Fragment of `WorkflowModule` — the workflows of the open files of an editor: a
# session document that the explorer holds from the start, whose tree children are
# the open files that hold a workflow, and whose page is a roster of those
# workflows. The facets of a workflow give the columns of the roster.

"""
    WorkflowList()

The workflows of the files that an editor holds open, as one document.
`file_list` is the [`OpenFileList`](@ref) of the editor, and `files` computes from
it the open files whose document is a [`WorkflowStep`](@ref): a file page, or the
file document when no page holds it. A file comes when a tab or a page shows it,
and goes when the last of them closes, so a workflow from any folder is in the
list while it is open. `table` is the arrangement of a roster with one row for
each of those workflows, which the page draws, and a person filters and sorts.

In a tree, the list has a node for each file, and the node of a file has the
steps, the decisions and the options of its workflow below it. A press on a file
shows the page of the file, so an edit there goes into the history of the file.

Every list of an editor is the list of the session of that editor
([`get_session_workflow_list`](@ref)), and the explorer of each window holds it
from the start.

# Example

    list = get_session_workflow_list()
    [get_document_title(get_edited_document(file)) for file in list.files]
"""
@document struct WorkflowList <: WorkflowDocument
    file_list::Any
    files::Any
    table::Any
end

const _WORKFLOW_LIST_COLUMNS = ["goal", "state", "active", "last_entry", "open_decisions", "within.name"]

# The list over the open file list of the editor of the evaluation, with the files
# that hold a workflow and the table of their workflows. The first content of an
# explorer makes it with its editor as the editor of the evaluation.
function WorkflowList()
    list = WorkflowList(Cell(get_session_open_file_list()), Cell(CellVector(Any[])), Cell(nothing))
    set_cell_computation!(getfield(list, :files), () ->
        CellVector(Any[file for file in list.file_list.files if _find_file_workflow(file) !== nothing]))
    roster = Roster(_OpenWorkflows(list); columns = _WORKFLOW_LIST_COLUMNS, title = "Workflows")
    link_roster!(roster, list)
    list.table = ArrangementDocument(roster, ArrangementEntry[])
    list
end

# The workflow that the open file `file` shows, or `nothing` when its document is
# no workflow.
function _find_file_workflow(file)
    document = get_edited_document(file)
    document isa WorkflowStep ? document : nothing
end

# The workflows of the files of `list`, in the order of the files.
_collect_list_workflows(list::WorkflowList) =
    WorkflowStep[workflow for workflow in (_find_file_workflow(file) for file in list.files) if workflow !== nothing]

"""
    get_session_workflow_list(; editor = find_evaluation_editor()) -> WorkflowList

The workflows of the open files of the session of `editor`: by default the editor
of the evaluation, or of the loop that runs the calling code. Each editor has its
own, made at the first call. With no editor, a new list over an empty file list,
which nothing fills.

Use it to read which workflows the person has open, and how far each one is.

# Example

    list = get_session_workflow_list()
    [get_document_title(get_edited_document(file)) for file in list.files]

See also `WorkflowList` and `get_session_open_file_list`.
"""
function get_session_workflow_list end

get_session_workflow_list(; editor = find_evaluation_editor()) =
    editor isa Editor ?
        get_session_document!(() -> run_with_evaluation_editor(WorkflowList, editor), editor, WorkflowList) :
        WorkflowList()

get_document_title(::WorkflowList) = "Workflows"
get_insertion_aliases(::Type{WorkflowList}) = ["workflows"]
make_insertion_document(::Type{WorkflowList}) = get_session_workflow_list()
is_explorer_entry_type(::Type{WorkflowList}) = true
is_session_explorer_entry_type(::Type{WorkflowList}) = true

# The list is a tool of the session: a paste does not replace it, and a duplicate
# would be the same list. Its files are the open files of the editor, which the
# walk of the documents reaches there.
accepts_pasted_document(::WorkflowList) = false
has_document_duplicate(::WorkflowList) = false
is_walk_opaque(::WorkflowList) = true

# A file keeps that a tab or an explorer shows the list, not the files, which
# belong to a session.
pred_arguments(::WorkflowList) = (), Pair{Symbol,Any}[]
make_pred_document(::Type{<:WorkflowList}, positional, keywords) = get_session_workflow_list()

# ── The roster ───────────────────────────────────────────────────────────

# The workflows of the files of a list: one part for each file, and its workflow
# as the item, with the file document that holds it as `within`.
struct _OpenWorkflows
    list::Any
end

get_roster_item_type(::_OpenWorkflows) = WorkflowStep
collect_roster_parts(source::_OpenWorkflows, link) = collect(Any, source.list.files)

function collect_roster_items(::_OpenWorkflows, link, file)
    workflow = _find_file_workflow(file)
    workflow === nothing && return RosterItem[]
    holder = file isa FilePage ? find_page_file(file) : file
    RosterItem[RosterItem(workflow, holder === nothing ? file : holder)]
end

# The facets of a step, which the columns of the list show and a person filters
# and sorts by.
get_item_facets(::Type{WorkflowStep}) = [
    "goal" => "the title of the step as text; for the root of a workflow, its goal",
    "active" => "the titles of the active steps of the tree of the step, the step too",
    "last_entry" => "the time of the latest entry of the journals of the tree, to the minute",
    "open_decisions" => "the count of the decisions of the tree that have no chosen option"]
compute_item_facet(step::WorkflowStep, ::Val{:goal}) = step.title.value
compute_item_facet(step::WorkflowStep, ::Val{:active}) =
    join((active.title.value for active in _collect_active_steps(step)), ", ")
compute_item_facet(step::WorkflowStep, ::Val{:last_entry}) = _format_readable_time(_get_last_entry_time(step))
compute_item_facet(step::WorkflowStep, ::Val{:open_decisions}) = _count_open_decisions(step)

# The text of the time of the latest entry of the tree under `workflow`, or an
# empty text for a workflow with no entry.
function _get_last_entry_time(workflow)
    entries = collect_workflow_entries(workflow)
    isempty(entries) ? "" : last(last(entries)).time
end

# The steps under `node` that are active, `node` too, in the order of the tree.
function _collect_active_steps(node, found = Any[])
    node isa WorkflowStep && node.state === :active && push!(found, node)
    is_workflow_node(node) || return found
    for child in get_workflow_node_children(node)
        _collect_active_steps(child, found)
    end
    found
end

# The count of the decisions under `node` that have no chosen option.
function _count_open_decisions(node)
    is_workflow_node(node) || return 0
    own = node isa WorkflowDecision && !any(option -> option.state === :chosen, node.options) ? 1 : 0
    own + sum((_count_open_decisions(child) for child in get_workflow_node_children(node)); init = 0)
end

# ── The tree ─────────────────────────────────────────────────────────────

# The list has its files as nodes, and a file the tree of its workflow, by the rule
# of a layer. A step and an option have their children, and a decision its options.
get_tree_children_steps(::WorkflowList) = ((FieldReferenceStep("files"),),)
get_tree_children_steps(::Union{WorkflowStep, WorkflowOption}) = ((FieldReferenceStep("children"),),)
get_tree_children_steps(::WorkflowDecision) = ((FieldReferenceStep("options"),),)

# The list counts its open workflows, and says how many decisions are open in them.
function get_document_decoration(list::WorkflowList)
    workflows = _collect_list_workflows(list)
    counts = isempty(workflows) ? DocumentCount[] : [DocumentCount(string(length(workflows), " open"))]
    DocumentDecoration(; icon = :list, counts, tooltip = () -> _make_workflow_list_note(workflows))
end

# What the row of the list says when the pointer rests on it: what it holds, and
# how many workflows and open decisions it counts.
_make_workflow_list_note(workflows) =
    TooltipNote(; title = "Workflows", text = "The workflows of the files that this window holds open.",
                facts = ["Open" => string(length(workflows)),
                         "Open decisions" => string(sum(_count_open_decisions, workflows; init = 0))])

# A step and an option say their state by an icon and by a pill in the colour of
# its role, as the badge of the outline does; a decision says when it is open.
get_document_decoration(node::Union{WorkflowStep, WorkflowOption}) =
    DocumentDecoration(; icon = _get_state_icon(node.state),
                       counts = [DocumentCount(string(node.state); role = _get_state_badge_role(node.state))])
get_document_decoration(decision::WorkflowDecision) =
    DocumentDecoration(; icon = :circle_help,
                       counts = any(option -> option.state === :chosen, decision.options) ? DocumentCount[] :
                                [DocumentCount("open")])

_get_state_icon(state::Symbol) =
    state === :active ? :circle_play :
    state in (:done, :chosen) ? :circle_check :
    state in (:dropped, :rejected) ? :x :
    state === :parked ? :circle_pause : :circle
