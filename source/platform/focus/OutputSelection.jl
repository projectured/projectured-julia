# Fragment of `FocusModule` — a selection that names a widget a projection drew
# for a document, where no document of the domain stands behind the widget: the
# table of a form, the box of a parameter, a heading.
#
# The widget is not a child of the document, so no field or index reaches it. A
# step that holds the widget itself does: the path evaluates to the widget, so a
# copy, a note and a whole-selection test reach it as they reach any document.
# The projection that drew the widget maps the step forward to the widget's place
# in its output, and makes its output follow that place, so the container that
# holds the widget rings it.

"""
    OutputReferenceStep(owner, node, output_path)

A reference step from `owner`, a document, to `node`, a document that a
projection drew for `owner` at `output_path` in its output. It evaluates to
`node`, and only from `owner`, so a path that another document reads fails.
"""
struct OutputReferenceStep <: ReferenceStep
    owner::Any
    node::Any
    output_path::Reference
end

get_reference_step_kind(::OutputReferenceStep) = :structural

function evaluate_reference_step(step::OutputReferenceStep, document)
    document === step.owner ||
        throw(ArgumentError("the drawn object belongs to another document"))
    step.node
end

Base.:(==)(a::OutputReferenceStep, b::OutputReferenceStep) =
    a.owner === b.owner && a.node === b.node && a.output_path == b.output_path
Base.hash(step::OutputReferenceStep, h::UInt) = hash(objectid(step.node), h)

# The drawn object is shown by its type: the object itself can be a large tree.
Base.show(io::IO, step::OutputReferenceStep) =
    print(io, ".drawn(", nameof(typeof(step.node)), ")")

"""
    make_output_reference(owner, node, output_path) -> Reference

The whole selection of `node`, which a projection drew for `owner` at
`output_path`, as a path from `owner` with its node types.
"""
make_output_reference(owner, node, output_path::Reference) =
    annotate_reference_types(owner,
        ConcreteReference(OutputReferenceStep(owner, node, strip_reference_types(output_path)),
                          EmptyReference()))

"""
    find_output_path(reference, owner) -> Reference | Nothing

Where the object that `reference` names from `owner` is in the output that was
drawn for `owner`, or `nothing` when `reference` names no object drawn for it.
"""
function find_output_path(reference, owner)
    reference isa ConcreteReference || return nothing
    step = reference.head
    (step isa OutputReferenceStep && step.owner === owner) || return nothing
    concat_references(step.output_path, strip_reference_types(reference.tail))
end

"""
    follow_output_selection!(root, forward; forward_mouse_target = nothing,
                             is_followed = node -> true) -> root

Make each document of the output tree `root` hold the part of the path
`forward()` answers that lies below it, and nothing when the path does not pass
through it. `forward()` answers a path from `root`, or `nothing`. So every
container holds its own part of the selection and rings the child that the part
names as a whole. `forward_mouse_target()`, when given, answers the path of the
part under the pointer, and each document holds its part of it in the same way.

The walk leaves out a node for which `is_followed` answers `false`, and what is
below it: a document of the domain that the projection put into a widget, or a
table whose rows are built on demand.
"""
function follow_output_selection!(root, forward::Function; forward_mouse_target = nothing,
                                  is_followed = node -> true)
    _follow_output!(root, (), :selection, forward, is_followed, IdDict{Any,Bool}())
    forward_mouse_target === nothing ||
        _follow_output!(root, (), :mouse_target, forward_mouse_target, is_followed, IdDict{Any,Bool}())
    root
end

"""
    follow_output_mouse_target!(root, forward; is_followed = node -> true) -> root

Make each document of the output tree `root` hold the part below it of the path of
the part under the pointer that `forward()` answers, as
[`follow_output_selection!`](@ref) does, for a view that keeps the selection of its
output in its own way. So each widget that the view makes lights while the pointer
is on it. `forward()` answers a path from `root`, or `nothing`; `is_followed` leaves
a node out, and what is below it.
"""
follow_output_mouse_target!(root, forward::Function; is_followed = node -> true) =
    (_follow_output!(root, (), :mouse_target, forward, is_followed, IdDict{Any,Bool}()); root)

function _follow_output!(node, prefix::Tuple, field::Symbol, forward, is_followed, seen)
    (haskey(seen, node) || !is_followed(node)) && return
    seen[node] = true
    if hasfield(typeof(node), field) && getfield(node, field) isa ReactiveCell
        set_cell_computation!(getfield(node, field),
                           () -> _get_output_part(forward(), prefix))
    end
    for (steps, child) in _child_document_refs(node)
        _follow_output!(child, (prefix..., steps...), field, forward, is_followed, seen)
    end
end

# The part of `path` below `prefix`, or `nothing` when `path` does not begin with it.
function _get_output_part(path, prefix::Tuple)
    path isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(path))
    length(steps) >= length(prefix) || return nothing
    all(i -> _is_same_output_step(steps[i], prefix[i]), eachindex(prefix)) || return nothing
    _prepend_steps(Tuple(steps[(length(prefix) + 1):end]), EmptyReference())
end

_is_same_output_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_is_same_output_step(a::RangeReferenceStep, b::RangeReferenceStep) =
    a.start == b.start && a.stop == b.stop
_is_same_output_step(a, b) = false

"""
    find_output_node_path(root, node) -> Reference | Nothing

The path from `root`, the output of a view, to `node`, a document of the input
of the view that the output holds, as a widget holds the document it shows. The
search goes by identity through the child documents, nearer ones first, and does
not enter `node`; `nothing` when the output does not hold it.
"""
function find_output_node_path(root, node)
    level = Any[(root, ())]
    seen = IdDict{Any,Bool}()
    while !isempty(level)
        next = Any[]
        for (candidate, steps) in level
            candidate === node && return _prepend_steps(steps, EmptyReference())
            haskey(seen, candidate) && continue
            seen[candidate] = true
            for (child_steps, child) in _child_document_refs(candidate)
                push!(next, (child, (steps..., child_steps...)))
            end
        end
        level = next
    end
    nothing
end

"""
    map_held_node_forward(output, node, reference) -> Reference | Nothing

`reference`, a path of `node`, as a path of `output`: the path to `node` in the
output before it. `node` is a document of the input of a view that the view puts
into its output whole, such as the document that a scroll pane of the view
shows, and that a later view draws. `nothing` when the output does not hold
`node`.

A view that holds a document of its input so maps a path of that document
forward, and [`map_held_node_backward`](@ref) maps it back: the path keeps the
steps of the input for as long as it has a pre-image (`PAR-CROSS-DOMAIN-LATE`),
so the part under the pointer reaches the document, and the later view finds
its own part in it.
"""
function map_held_node_forward(output, node, reference)
    prefix = find_output_node_path(output, node)
    prefix === nothing && return nothing
    annotate_reference_types(output, concat_references(prefix, strip_reference_types(reference)))
end

"""
    map_held_node_backward(output, node, reference) -> Reference | Nothing

`reference`, a path of `output`, as a path of `node`: the rest of the path after
the step that reaches `node`, a document of the input of the view that the
output holds. `nothing` when the path does not pass through `node`. The inverse
of [`map_held_node_forward`](@ref).
"""
function map_held_node_backward(output, node, reference)
    current = output
    rest = reference
    while true
        current === node && return rest
        rest isa ConcreteReference || return nothing
        current = try
            unwrap_cell(evaluate_reference_step(get_reference_head(rest), current))
        catch
            return nothing
        end
        rest = get_reference_tail(rest)
    end
end
