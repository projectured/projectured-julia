# Fragment of `ProjectionModule` — the default of `get_projection_gesture_bindings`,
# which `ProjectionInterface.jl` declares, `read_projection_gesture`, which fires
# the rows of that table, and `read_gesture` of a projection, the job of a stage that
# makes an operation of a gesture. The generic and higher-order projections that call
# `read_projection_gesture` are in a higher package; this fragment holds only the
# binding machinery.

# A projection with no table of its own owns no gesture.
get_projection_gesture_bindings(::Projection, iomap) = GestureBinding[]

"""
    read_projection_gesture(projection, iomap, event; answer = nothing) -> Operation | Nothing

Fire the first reified `get_projection_gesture_bindings(projection, iomap)`
binding whose pattern `matches` the event and whose `applicable`
precondition holds; a binding whose `operation` returns `nothing` is
skipped so a later one may still fire. The projection-layer analogue of
`read_bound_gesture`: a projection whose reader delegates here *fires* the very
table a listing *shows*. `answer` is the answer of the child, and with it only a
binding whose `override` condition holds for it fires ([`fire_gesture_bindings`](@ref)).

It answers a `CollectIntents` payload too, because `fire_gesture_bindings` does.
A projection that routes its gestures through here needs no separate collector.

These are the rules of the projection itself, without the table of its input. The
passing reads only them at a level whose input is the input of its child
([`read_child_intent`](@ref)), because the child reads the table of that input. So a
wrapper of the same input that has a rule of code adds a method of this function for
the kind of gesture that it reads, as a projection adds a method of `read_gesture`,
and calls the default for any other gesture.
"""
function read_projection_gesture(projection, iomap, event; answer = nothing)
    bindings = get_projection_gesture_bindings(projection, iomap)
    isempty(bindings) && return nothing
    input = get_iomap_input(iomap)
    selection = input isa Document ? get_selection(input) : nothing
    return fire_gesture_bindings(bindings, input, event; selection, answer)
end

"""
    read_gesture(projection, iomap, gesture; answer = nothing) -> Operation | Nothing

The operation that the rules of one stage make of `gesture`, or `nothing` when the
stage has nothing to say. It calls no child: [`read_intent`](@ref) asks the child
first, through the `read_intent` of the child, and then calls this with the answer
of the child as `answer` ([`read_child_intent`](@ref)).

The default fires the gesture table of the projection
([`get_projection_gesture_bindings`](@ref)), then the table of the input document
(`read_gesture(document, gesture)`), and the first answer wins. A `CollectIntents`
payload collects the rows of both, the projection's first. With no `answer`, any
rule that matches answers. With an `answer`, a rule answers only when its
`override` condition holds for it, and its operation then replaces the answer.

A projection adds a method for the kind of gesture that it reads, and Julia
chooses the method by the type of the gesture.

# Example

    # A click on the right edge of the drawn box makes the box narrower.
    function read_gesture(p::BoxToGraphics, iomap, click::MouseClick; answer = nothing)
        click.x >= iomap.input.width - 4 || return nothing
        ShrinkBoxOperation(iomap.input)
    end

See also `map_operation_backward`, the other job of a stage, and `read_intent`,
which passes a change from stage to stage.
"""
function GestureBindingModule.read_gesture(projection::Projection, iomap, gesture; answer = nothing)
    own = read_projection_gesture(projection, iomap, gesture; answer)
    input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
    table = input isa Document ? read_gesture(input, gesture; answer) : nothing
    gesture isa CollectIntents && return merge_collected_intents(_get_collected(own), _get_collected(table))
    own === nothing ? table : own
end

# A collection, or `nothing` for an answer that is none.
_get_collected(answer) = answer isa CollectedIntentsOperation ? answer : nothing
