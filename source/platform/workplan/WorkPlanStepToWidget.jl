# Fragment of `WorkPlanModule` — the page of one step: its facts, a line each, and
# a link to each step that it waits for. Each line reads only the cells of its
# facts, so a change of a status draws its line again.

"""
    WorkPlanStepToWidget(; gap)

Prints a [`WorkPlanStep`](@ref) as its page: its title, its state and its
priority, what it shows while it runs, its description, its reason, and the
steps that it waits for. A line whose fact is empty is not shown. Each step that
it waits for is a link: a press answers `OpenPageOperation` with the plan of the
step and the path of that step in it, so a navigator opens it as a page. A step
that no plan holds, and an id that names no step of its plan, show the id with
no link. No part takes an edit.
"""
@projection UntrackedCell struct WorkPlanStepToWidget
    gap::Int = get_widget_style(nothing, :label_gap)
end

function print_document(p::WorkPlanStepToWidget, recursion, step::WorkPlanStep, context)
    blockers = HorizontalLayout(Any[]; vertical_align = :center, gap = p.gap)
    set_cell_computation!(getfield(blockers.children, :elements), () -> begin
        parts = _build_blocker_parts(step)
        run_without_cell_tracking(() -> foreach(place -> _follow_layout_part!(blockers, parts[place], place),
                                                eachindex(parts)))
        Cell[Cell(part) for part in parts]
    end)
    root = VerticalLayout(Any[
        WidgetLabel(() -> step.title),
        WidgetLabel(() -> string("status ", _describe_step_state(step), " · priority ", step.priority)),
        _make_fact_label(() -> step.active_title, "while it runs: "),
        _make_fact_label(() -> step.description, ""),
        _make_fact_label(() -> step.reason, "reason: "),
        blockers]; gap = p.gap, child_width = Fill)
    iomap = ChildrenIoMap(p, step, root, Cell(Any[]))
    set_output_path_computations!(root, step, path -> map_reference_forward(p, iomap, path); dormant = false)
    set_output_tree_path_computations!(root)
    iomap
end

# A line that says `prefix` and the fact that `fact()` reads, and takes no line
# while the fact is empty.
function _make_fact_label(fact::Function, prefix::AbstractString)
    label = WidgetLabel(() -> prefix * fact())
    set_cell_computation!(getfield(label, :visible), () -> !isempty(fact()))
    label
end

# The words "blocked by" and a part for each id of `blocked_by`: a link to the step
# that the id names in the plan of `step`, or the id when there is no such step.
# No part while the step waits for no step.
function _build_blocker_parts(step::WorkPlanStep)
    ids = collect(String, step.blocked_by)
    isempty(ids) && return Any[]
    plan = _get_step_plan(step)
    Any[WidgetLabel("blocked by"), (_make_blocker_part(plan, id) for id in ids)...]
end

function _make_blocker_part(plan, id::AbstractString)
    path = plan === nothing ? nothing : _find_work_plan_step_path(plan.steps, id)
    path === nothing && return WidgetLabel(String(id))
    reference = extend_reference(EmptyReference(), path...)
    WidgetLink("step " * id, DocumentLocator(plan, reference); tooltip = "Open the page of the step.")
end

# A step names no part of its page: each part of the page is a part that the page
# drew, named by its introduced path.
map_reference_forward(p::WorkPlanStepToWidget, iomap, reference) =
    reference isa EmptyReference ? reference : find_introduced_path(p, reference)

# ── Registration ─────────────────────────────────────────────────────────────

# A step draws as its page, inside any document that a renderer draws, as the page
# of a navigator.
make_graphics_projection(::Type{WorkPlanStep}; measure, appearance) =
    ChainingProjection(
        WorkPlanStepToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap)),
        VerticalLayoutToGraphicsCanvas())
