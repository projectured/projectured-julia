# Fragment of `WorkPlanModule` — what a plan shows: the progress of its steps as
# a line and a bar, and the tree of its steps; or its Markdown text; or a link to
# the file that holds it. The tree is the `DocumentTree` that the link of the plan
# keeps, so its open nodes stay when the plan is drawn again.

"""
    WorkPlanToWidget(; gap)

Prints a [`WorkPlan`](@ref) by its content. A plan of steps shows a line of its
progress ([`describe_work_plan_progress`](@ref)), a bar filled to the share of
its completed steps, and the tree of its steps, a `DocumentTree` of the plan,
whose node of a step opens the page of the step on a double click. A plan with a
text shows the text as prose, and a plan with the address of a file shows a link
that opens the file. Each part reads the cells of the plan, so the view follows
each update of the plan. No part takes an edit.
"""
@projection UntrackedCell struct WorkPlanToWidget
    gap::Int = get_widget_style(nothing, :label_gap)
end

# The place of the tree among the parts of a plan of steps, and the steps from the
# root of the view to the root of the tree document.
const _STEP_TREE_PLACE = 3
const _STEP_TREE_STEPS = (FieldReferenceStep("children"), ElementReferenceStep(_STEP_TREE_PLACE),
                          FieldReferenceStep("child"), FieldReferenceStep("root"))

function print_document(p::WorkPlanToWidget, recursion, plan::WorkPlan, context)
    root = VerticalLayout(Any[]; gap = p.gap, child_width = Fill)
    iomap = ChildrenIoMap(p, plan, root, Cell(Any[]))
    # The layout routes a key by its selection, so it maps only a live selection.
    set_output_path_computations!(root, plan, path -> map_reference_forward(p, iomap, path); dormant = false)
    content = Cell(@computation _get_work_plan_content(plan))
    set_cell_computation!(getfield(root.children, :elements), () -> begin
        parts = _build_work_plan_parts(plan, content[])
        run_without_cell_tracking(() -> foreach(place -> _follow_layout_part!(root, parts[place], place),
                                                eachindex(parts)))
        Cell[Cell(part) for part in parts]
    end)
    iomap
end

# The content that a plan shows: its steps, else its text, else its file. A plan
# with none shows its steps, which say that there are none.
function _get_work_plan_content(plan::WorkPlan)
    isempty(plan.steps) || return :steps
    isempty(plan.text) || return :text
    isempty(plan.uri) ? :steps : :uri
end

function _build_work_plan_parts(plan::WorkPlan, content::Symbol)
    content === :text && return Any[make_prose_document(plan.text)]
    content === :uri && return Any[_make_file_link(plan.uri)]
    bar = WidgetProgressBar(() -> _compute_completed_share(plan); width = 0)
    Any[WidgetLabel(() -> describe_work_plan_progress(plan)),
        LayoutConstraint(bar; width = Fill),
        LayoutConstraint(_get_work_plan_step_tree(plan); width = Fill, height = Fill)]
end

# The tree of the steps of a plan, made by the first view of the plan and kept in
# its link.
function _get_work_plan_step_tree(plan::WorkPlan)
    link = plan.link
    link.step_tree === nothing && (link.step_tree = DocumentTree(plan; title = "Steps"))
    link.step_tree
end

# A link to the file at `uri`, a path or a `file://` URI: a press opens the file.
function _make_file_link(uri::AbstractString)
    path = startswith(uri, "file://") ? uri[(length("file://") + 1):end] : String(uri)
    WidgetButton(path; tooltip = "Open the file.",
                 gestures = GestureBinding[
                     GestureBinding(MouseClickPattern(:left), (_, _) -> OpenFileOperation(path);
                                    description = "Open the file", domain = "workplan")])
end

# ── The paths of the parts ───────────────────────────────────────────────────

# The part of `path` below `steps`, or `nothing` when `path` does not begin with
# them.
function _find_path_below(path, steps::Tuple)
    path isa Reference || return nothing
    found = get_reference_steps(strip_reference_types(path))
    (length(found) >= length(steps) && all(_is_same_step(found[k], steps[k]) for k in eachindex(steps))) ||
        return nothing
    extend_reference(EmptyReference(), found[(length(steps) + 1):end]...)
end

_is_same_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_is_same_step(a, b) = a == b

# A part that a layout builds after the print holds its part of the paths of the
# layout, and so do the documents below it. The tree document takes its part and
# goes no further: its root is the plan, whose paths are its own.
function _follow_layout_part!(layout, part, place::Int)
    steps = (FieldReferenceStep("children"), ElementReferenceStep(place))
    set_output_path_computations!(part, layout, path -> _find_path_below(path, steps))
    if part isa LayoutConstraint && part.child isa DocumentTree
        set_output_path_computations!(part.child, part, path -> _find_path_below(path, (FieldReferenceStep("child"),)))
    else
        set_output_tree_path_computations!(part)
    end
    part
end

# A path of the steps of the plan is the same path below the root of the tree
# document. The plan itself is the whole view, and a part that the view drew is
# named by its introduced path.
function map_reference_forward(p::WorkPlanToWidget, iomap, reference)
    reference isa Reference || return nothing
    introduced = find_introduced_path(p, reference)
    introduced === nothing || return introduced
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    (get_reference_steps(path)[1] == FieldReferenceStep("steps") &&
     _get_work_plan_content(iomap.input) === :steps) || return nothing
    concat_references(extend_reference(EmptyReference(), _STEP_TREE_STEPS...), path)
end

function map_reference_backward(p::WorkPlanToWidget, iomap, reference)
    reference isa Reference || return nothing
    path = strip_reference_types(reference)
    path isa EmptyReference && return path
    if _get_work_plan_content(iomap.input) === :steps
        inside = _find_path_below(path, _STEP_TREE_STEPS)
        inside === nothing || return inside
    end
    make_introduced_reference(p, iomap, path)
end

# ── Registration ─────────────────────────────────────────────────────────────

# A plan draws as its view, inside any document that a renderer draws. The parts
# of the view come back through the recursion of the renderer, which draws the
# tree of the steps and the prose of a text with their own rows.
make_graphics_projection(::Type{WorkPlan}; measure, appearance) =
    ChainingProjection(
        WorkPlanToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap)),
        VerticalLayoutToGraphicsCanvas())
