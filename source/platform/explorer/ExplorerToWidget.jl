# Fragment of `ExplorerModule` — the view of an explorer: the tree and the
# navigator side by side, each drawn by the row of its own type, and the reader
# that turns a press on a node into a page in the navigator.
#
#     children[1].<rest>    tree.<rest>
#     children[2].<rest>    navigator.<rest>

"""
    ExplorerToWidget(; gap)

Draw an [`Explorer`](@ref) as a grid of one row: the tree, and the navigator in
three times its width, each drawn by the row of its own type, with `gap` between
them.

A press on a node selects it, and the navigator shows its page; the keys stay in
the tree, so a person walks the nodes and reads each page. Ctrl+press opens the
page in a new tab, and a double press or Return puts the keyboard in the page.
"""
@projection UntrackedCell struct ExplorerToWidget <: Projection
    gap::Int = get_widget_style(nothing, :section_gap)
end

const _EXPLORER_PARTS = ("tree" => 1, "navigator" => 2)

_make_steps(steps...) = extend_reference(EmptyReference(), steps...)

function print_document(p::ExplorerToWidget, recursion, explorer::Explorer, context)
    output = GridLayout(Any[getfield(explorer, :tree)[], getfield(explorer, :navigator)[]], 2;
                        horizontal_gap = p.gap, column_policies = Any[Relative(1), Relative(3)], row_policy = Fill)
    iomap = SimpleIoMap(p, explorer, output)
    set_output_path_computations!(output, explorer, path -> map_reference_forward(p, iomap, path); dormant = false)
    iomap
end

function map_reference_forward(::ExplorerToWidget, iomap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    reference isa ConcreteReference || return nothing
    head = get_reference_head(reference)
    head isa FieldReferenceStep || return nothing
    for (name, k) in _EXPLORER_PARTS
        head.name == name || continue
        return annotate_reference_types(iomap.output, concat_references(
            _make_steps(FieldReferenceStep("children"), RangeReferenceStep(k - 1, k)),
            strip_reference_types(get_reference_tail(reference))))
    end
    nothing
end

function map_reference_backward(::ExplorerToWidget, iomap, reference)
    reference isa ConcreteReference || return EmptyReference()
    steps = get_reference_steps(strip_reference_types(reference))
    length(steps) >= 2 && steps[1] == FieldReferenceStep("children") && steps[2] isa RangeReferenceStep ||
        return EmptyReference()
    k = steps[2].start + 1
    name = only(first(part) for part in _EXPLORER_PARTS if last(part) == k)
    _make_steps(FieldReferenceStep(name), steps[3:end]...)
end

# The steps from the root section to the node of the tree that `path`, from the
# explorer, names; `nothing` for a path that names no node.
function _find_node_steps(path)
    path isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    (length(steps) >= 2 && steps[1] == FieldReferenceStep("tree") && steps[2] == FieldReferenceStep("root")) ||
        return nothing
    steps[3:end]
end

# What the explorer answers for an answer of its tree: a selection of a node shows
# its page in the navigator and keeps the selection in the tree, or with Ctrl
# opens the page in a new tab; an open of a node moves into its page in the
# navigator. `nothing` for any other answer.
function _convert_explorer_answer(explorer::Explorer, operation, gesture)
    navigator = getfield(explorer, :navigator)[]
    if operation isa ReplaceSelectionOperation
        steps = _find_node_steps(operation.path)
        steps === nothing && return nothing
        address = _make_steps(steps...)
        gesture isa MouseClick && gesture.modifiers.ctrl &&
            return CompoundOperation(Any[operation, OpenPageOperation(navigator.content, address, :new_tab)])
        visit = make_navigator_open_operation(navigator, address)
        visit === nothing && return nothing
        # The visit writes the navigator, and its selection would leave the tree.
        writes = Any[part for part in visit.operations if !(part isa ReplaceSelectionOperation)]
        return CompoundOperation(Any[operation, writes...])
    end
    if operation isa OpenPageOperation && operation.document === nothing
        steps = _find_node_steps(operation.reference)
        steps === nothing && return nothing
        visit = make_navigator_open_operation(navigator, _make_steps(steps...))
        # The first press of a double press already shows the page, so the open
        # only puts the keyboard in it, as a visit does.
        visit === nothing && (visit = ReplaceSelectionOperation(
            annotate_reference_types(navigator, _make_steps(FieldReferenceStep("content"), steps...))))
        return reroot_operation(visit, (FieldReferenceStep("navigator"),))
    end
    nothing
end

function read_intent(p::ExplorerToWidget, recursion, change::Intent, iomap)
    answer = invoke(read_intent, Tuple{Projection,Any,Intent,Any}, p, recursion, change, iomap)
    operation = answer.operation
    converted = operation === nothing ? nothing : _convert_explorer_answer(iomap.input, operation, change.gesture)
    converted === nothing ? answer : Intent(answer.gesture, converted, answer.description, answer.domain)
end

# The tree and the navigator come back through the recursion of the renderer,
# which draws each with the row of its own type.
make_graphics_projection(::Type{<:Explorer}; measure, appearance) =
    ChainingProjection(
        ExplorerToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :section_gap)),
        GridLayoutToGraphicsCanvas())
