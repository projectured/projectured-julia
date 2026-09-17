# Fragment of `FocusModule` — the walk of a whole-element selection over the
# structure of any document, with the four Alt + arrow keys.
#
# Up is the enclosing object, down is the first object inside, and left and
# right are the siblings. These are the meanings of the syntax walk. A domain
# that walks its own way answers the keys first, and this walk answers only
# what nothing inside answered.

"""
    SelectionWalkingProjection(; inner)

Wrap `inner`, and answer the four Alt + arrow keys that nothing inside
answered, by [`compute_selection_walk`](@ref) over the input document.

The wrapper is transparent: it prints as `inner`, and it maps references as
`inner` does.
"""
struct SelectionWalkingProjection <: Projection
    inner::Projection
end

SelectionWalkingProjection(; inner::Projection) = SelectionWalkingProjection(inner)

@iomap struct SelectionWalkingIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

function print_document(p::SelectionWalkingProjection, recursion, input, ctx)
    child_iomap = print_document(p.inner, recursion, input, ctx)
    SelectionWalkingIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

function read_intent(p::SelectionWalkingProjection, recursion, change::Intent,
                     iomap::SelectionWalkingIoMap)
    child = iomap.child_iomap
    answer = read_intent(child.projection, recursion, change, child)
    direction = get_selection_walk_direction(change.gesture)
    direction === nothing && return answer
    operation = answer isa Intent ? answer.operation : answer
    operation === nothing || return answer
    document = iomap.input
    selection = hasproperty(document, :selection) ? document.selection : nothing
    path = compute_selection_walk(document, selection, direction)
    Intent(change.gesture, path === nothing ? nothing : ReplaceSelectionOperation(path))
end

read_intent(p::SelectionWalkingProjection, iomap::SelectionWalkingIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

map_reference_forward(::SelectionWalkingProjection, iomap::SelectionWalkingIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap, reference)
map_reference_backward(::SelectionWalkingProjection, iomap::SelectionWalkingIoMap, reference) =
    map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)

"""
    get_selection_walk_direction(event) -> Symbol | Nothing

`:up`, `:down`, `:left` or `:right` for an arrow key pressed with Alt and no
other modifier, else `nothing`.
"""
function get_selection_walk_direction(event)
    event isa KeyDown || return nothing
    event.modifiers == ModifierKeys(alt = true) || return nothing
    event.key in (:up, :down, :left, :right) ? event.key : nothing
end

"""
    compute_selection_walk(document, selection, direction) -> Reference | Nothing

The selection one step of the walk makes, as a path from `document`:

- `:up` — the nearest enclosing object. From a caret, the object that holds
  the caret.
- `:down` — the first object inside the selected one, in the order of its
  fields, and the first element of a vector. An object with nothing inside
  keeps the selection.
- `:left` / `:right` — the previous / next object with the same parent: the
  neighbouring element of the same vector, or the neighbouring field in the
  order of the fields. At the first and the last one the selection stays.

`:down`, `:left` and `:right` need a whole selection, and answer `nothing` for
a caret, so a text reader can use the key. An object is a document that is not
a collection and that can hold a selection; a value such as a color is not one.
"""
function compute_selection_walk(document, selection, direction::Symbol)
    selection isa Reference || return nothing
    steps = collect(get_reference_steps(strip_reference_types(selection)))
    direction === :up && return _walk_up(document, steps)
    is_whole_selection(document, selection) || return nothing
    direction === :down && return _walk_down(document, steps)
    direction === :left && return _walk_sideways(document, steps, -1)
    direction === :right && return _walk_sideways(document, steps, 1)
    nothing
end

# A document the walk can stop at.
_is_walk_object(node) =
    node isa Document && !(node isa CollectionDocument) &&
    !(hasproperty(node, :selection) && getfield(node, :selection) isa ImmutableCell{Nothing})

_make_walk_path(steps) = _prepend_steps(Tuple(steps), EmptyReference())

_evaluate_walk_steps(document, steps) =
    try_evaluate_reference(document, _make_walk_path(steps), missing)

function _walk_up(document, steps)
    whole = _is_walk_object(_evaluate_walk_steps(document, steps))
    for n in (whole ? length(steps) - 1 : length(steps)):-1:0
        _is_walk_object(_evaluate_walk_steps(document, steps[1:n])) &&
            return _make_walk_path(steps[1:n])
    end
    nothing
end

_walk_children(node) = [ref for ref in _child_document_refs(node) if _is_walk_object(ref[2])]

function _walk_down(document, steps)
    children = _walk_children(_evaluate_walk_steps(document, steps))
    isempty(children) && return _make_walk_path(steps)
    _make_walk_path(vcat(steps, collect(first(children)[1])))
end

function _walk_sideways(document, steps, offset::Int)
    # The last step is a field, or the last two are a vector field and an index.
    for k in (1, 2)
        length(steps) >= k || break
        parent_steps = steps[1:(end - k)]
        parent = _evaluate_walk_steps(document, parent_steps)
        _is_walk_object(parent) || continue
        children = _walk_children(parent)
        own = steps[(end - k + 1):end]
        i = findfirst(ref -> collect(ref[1]) == own, children)
        i === nothing && continue
        j = clamp(i + offset, 1, length(children))
        return _make_walk_path(vcat(parent_steps, collect(children[j][1])))
    end
    nothing
end
