# Fragment of `WorkflowModule` — the page of the workflows of the open files: a line
# that counts them, and under it the table of the list, which the grid prints
# through the recursion, so a path in it is a path of the list.
#
#     table.<rest>    children[2].<rest>

"""
    WorkflowListToWidget(; gap)

Draw a [`WorkflowList`](@ref): a line that says how many workflows are open and
how many of their decisions are open, and under it the table of the list, which
fills the rest of the height. A row of the table shows a workflow: its goal, its
state, its active steps, the time of its last entry, the count of its open
decisions and the name of its file. A person filters and sorts the table in its
bar.
"""
@projection UntrackedCell struct WorkflowListToWidget <: Projection
    gap::Int = get_workflow_style(nothing, :gap)
end

const _WORKFLOW_LIST_TABLE_STEP = FieldReferenceStep("table")
const _WORKFLOW_LIST_TABLE_PLACE_STEPS = (FieldReferenceStep("children"), RangeReferenceStep(1, 2))

# The line above the table: the open workflows, and the open decisions in them.
function _format_workflow_list_line(list::WorkflowList)
    workflows = _collect_list_workflows(list)
    isempty(workflows) &&
        return "No workflow is open. A .pred file that holds a workflow shows here while a tab or a page shows it."
    parts = String[string(length(workflows), length(workflows) == 1 ? " open workflow" : " open workflows")]
    decisions = sum(_count_open_decisions, workflows; init = 0)
    decisions > 0 && push!(parts, string(decisions, decisions == 1 ? " open decision" : " open decisions"))
    join(parts, " · ")
end

function print_document(p::WorkflowListToWidget, recursion, list::WorkflowList, ctx)
    line = WidgetLabel("")
    set_cell_computation!(line, () -> _format_workflow_list_line(list))
    output = GridLayout(Any[line, getfield(list, :table)[]], 1; vertical_gap = p.gap, column_policy = Fill,
                        row_policies = Any[Content, Fill])
    iomap = SimpleIoMap(p, list, output)
    # The grid passes a key by its own selection, so it carries the path of the list
    # below it. The table is a document of the list, which holds its own.
    set_output_path_computations!(output, list, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

# `table.<rest>` ↔ the table in the grid.
function map_reference_forward(::WorkflowListToWidget, iomap::SimpleIoMap, reference)
    output = iomap.output
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(output))
    (reference isa ConcreteReference && get_reference_head(reference) == _WORKFLOW_LIST_TABLE_STEP) || return nothing
    rest = get_reference_tail(reference)
    is_fully_typed_reference(rest) ||
        (rest = annotate_reference_types(getfield(iomap.input, :table)[], strip_reference_types(rest)))
    concat_references(annotate_reference_types(output, extend_reference(EmptyReference(),
                                                                        _WORKFLOW_LIST_TABLE_PLACE_STEPS...)),
                      rest)
end

# A path into the table takes the step of the table; a path into the line names
# nothing, so a press on it leaves the selection where it is; a path to the grid
# itself names the whole list.
function map_reference_backward(::WorkflowListToWidget, iomap::SimpleIoMap, reference)
    steps = get_reference_steps(strip_reference_types(reference))
    isempty(steps) && return EmptyReference()
    (length(steps) >= 2 && steps[1] == _WORKFLOW_LIST_TABLE_PLACE_STEPS[1] &&
     steps[2] == _WORKFLOW_LIST_TABLE_PLACE_STEPS[2]) || return nothing
    concat_references(ConcreteReference(_WORKFLOW_LIST_TABLE_STEP, EmptyReference()),
                      get_reference_tail(get_reference_tail(reference)))
end
