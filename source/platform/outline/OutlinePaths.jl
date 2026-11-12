# Fragment of `OutlineModule` — the paths of an outline: the places of the output
# that hold a document of the input, and the routing of the selection and of the
# pointer to every part of the output.
#
# A projection of an outline builds its output in one computation, and the slots
# of the same build say where each document of the input sits. So the maps need
# no other state than the slots, and a new build brings new slots with it.

"""
    OutlineSlot(input, output; whole = false)

A place in the output of an outline that holds a document of the input: `input`
is the path of the document from the input, as a vector of steps, and `output`
its path from the output. A slot maps a place inside it to the same place inside
the other side, such as a range of a text.

A `whole` slot is a record and the row that draws it. The record maps to the row,
and a place inside the row that no slot before it holds, such as its mark, its
time or the gap between two parts, maps back to the record. So a press on a part
that the view drew names the record, and a menu that such a part opens belongs to
the record. A path inside the record that no slot holds maps to nothing.
"""
struct OutlineSlot
    input::Vector{Any}
    output::Vector{Any}
    whole::Bool
end

OutlineSlot(input, output; whole::Bool = false) = OutlineSlot(collect(Any, input), collect(Any, output), whole)

_is_same_outline_step(a::FieldReferenceStep, b::FieldReferenceStep) = a.name == b.name
_is_same_outline_step(a::RangeReferenceStep, b::RangeReferenceStep) = a.start == b.start && a.stop == b.stop
_is_same_outline_step(::Any, ::Any) = false

_has_outline_prefix(steps, prefix) =
    length(steps) >= length(prefix) && all(_is_same_outline_step(steps[i], prefix[i]) for i in eachindex(prefix))

_make_outline_reference(steps) =
    foldr((step, tail) -> ConcreteReference(step, tail), steps; init = EmptyReference())

# The path on the other side of the place that `steps` names, through the first
# slot that holds it, or `nothing`. A whole slot maps only the record forward, and
# any place inside its row back to the record.
function _map_outline_steps(slots, steps, from::Symbol, to::Symbol)
    for slot in slots
        prefix = getfield(slot, from)
        _has_outline_prefix(steps, prefix) || continue
        if slot.whole
            from === :input && length(steps) != length(prefix) && continue
            return _make_outline_reference(getfield(slot, to))
        end
        return _make_outline_reference(vcat(getfield(slot, to), steps[(length(prefix) + 1):end]))
    end
    nothing
end

"""
    map_outline_forward(slots, reference) -> Reference or nothing

The path in the output of the place that `reference`, a path in the input, names,
through the first of `slots` that holds it; the empty path for the input itself,
and `nothing` for a place that no slot holds.
"""
function map_outline_forward(slots, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    isempty(steps) && return EmptyReference()
    _map_outline_steps(slots, steps, :input, :output)
end

"""
    map_outline_backward(slots, reference; introduce = nothing) -> Reference or nothing

The path in the input of the place that `reference`, a path in the output, names,
through the first of `slots` that holds it, or `nothing` for a part that the view
drew.

A text that the view drew inside the row of a whole slot, such as the id or the
time of a record, is a part of the output of the view. With `introduce`, a
function of the path of the record in the input and of `reference`, a place in
the row maps to the record and the step of the view that `introduce` answers, so
a plain click puts the caret into that text and an Alt+click selects it. When
`introduce` answers `nothing`, as for the mark of the row or a gap, the place maps
to the record.
"""
function map_outline_backward(slots, reference; introduce = nothing)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    if introduce !== nothing
        slot = _find_outline_slot(slots, steps, :output)
        if slot !== nothing && slot.whole && length(steps) > length(slot.output)
            record = _make_outline_reference(slot.input)
            drawn = introduce(record, reference)
            drawn === nothing || return concat_references(record, drawn)
        end
    end
    _map_outline_steps(slots, steps, :output, :input)
end

# The first slot whose side `from` holds the place that `steps` names, or `nothing`.
function _find_outline_slot(slots, steps, from::Symbol)
    for slot in slots
        _has_outline_prefix(steps, getfield(slot, from)) && return slot
    end
    nothing
end

# Whether `steps` end in a caret, a place between two characters of a text.
_is_outline_caret(steps) = !isempty(steps) && last(steps) isa RangeReferenceStep && last(steps).start == last(steps).stop

"""
    map_outline_view_forward(projection, slots, reference) -> Reference or nothing

The forward map of a view that builds an outline with `slots`: a part that
`projection` drew maps to its place in the output, both one that a reference names
whole and a caret in a text of the row of a record (`find_outline_introduced_path`),
and any other path maps through the slots (`map_outline_forward`).
"""
map_outline_view_forward(projection, slots, reference) =
    something(find_introduced_path(projection, reference), find_outline_introduced_path(projection, reference),
              Some(map_outline_forward(slots, reference)))

"""
    make_outline_row_text_reference(projection, iomap, record, reference) -> Reference or nothing

The step of `projection` at `record`, a path in the input of `iomap`, for
`reference`, a place in a text that the view drew in the row of the record: a
caret in it, or the text as a whole, a `String` of the output of `iomap`. Any
other place answers `nothing`. A view of an outline passes it to
[`map_outline_backward`](@ref) as `introduce`.
"""
function make_outline_row_text_reference(projection, iomap, record, reference)
    _is_outline_caret(collect(get_reference_steps(strip_reference_types(reference)))) ||
        try_evaluate_reference(iomap.output, strip_reference_types(reference)) isa AbstractString ||
        return nothing
    document = try_evaluate_reference(iomap.input, record)
    make_introduced_reference(projection, document === nothing ? iomap.input : document,
                              annotate_reference_types(iomap.output, strip_reference_types(reference)))
end

"""
    find_outline_introduced_path(projection, reference) -> Reference or nothing

The path in the output of `projection` that `reference` names when it ends in a
step that `projection` introduced, as [`map_outline_backward`](@ref) makes for a
caret in a text that the view drew in a row: the path of the record in the input,
then the step, which holds the path of the place from the root of the output. The
path of the step is the answer; any other reference answers `nothing`.
"""
function find_outline_introduced_path(projection, reference)
    reference isa ConcreteReference || return nothing
    while reference.tail isa ConcreteReference
        reference = reference.tail
    end
    step = reference.head
    step isa ProjectionReferenceStep && step.projection === projection ? step.output_path : nothing
end

"""
    route_outline_paths!(input, output, image; embedded = ()) -> output

Make every document of the output tree `output` hold the part below it of the
image of the selection and of the part under the pointer of `input`. `image(path)`
answers the path in the output of a path in the input, or `nothing`. So a
container routes a key by its selection, and a row lights while the pointer is on
it. A document of the input that the output holds, one of `embedded`, keeps its
own paths, and the walk does not go into it, nor into `input` itself, which a
part names as the target of its writes, such as a switch of the view.
"""
function route_outline_paths!(input, output, image; embedded = ())
    set_output_path_computations!(output, input, image; dormant = false)
    kept = Base.IdSet{Any}(embedded)
    push!(kept, input)
    # The walk reads the fields of the parts, such as the text of a field, and a
    # build that called it must not follow them: a key would build the outline again.
    run_without_cell_tracking(() -> _route_outline_child_paths!(output, kept, Base.IdSet{Any}()))
    output
end

function _route_outline_child_paths!(node, embedded, seen)
    node in seen && return nothing
    push!(seen, node)
    for (step, child) in child_reference_steps(node)
        child = unwrap_cell(child)
        (child isa Document && !(child in embedded) && hasfield(typeof(child), :selection) &&
         getfield(child, :selection) isa Cell) || continue
        set_output_path_computations!(child, node,
            path -> path isa ConcreteReference && path.head == step ? path.tail : nothing)
        _route_outline_child_paths!(child, embedded, seen)
    end
    nothing
end
