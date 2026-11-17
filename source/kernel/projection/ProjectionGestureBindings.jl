# Fragment of `ProjectionModule` — the default of `get_projection_gesture_bindings`,
# which `ProjectionInterface.jl` declares, `read_projection_gesture`, which fires
# the rows of that table, and `read_gesture` of a projection, the job of a stage that
# makes an operation of a gesture. The generic and higher-order projections that call
# `read_projection_gesture` are in a higher package; this fragment holds only the
# binding machinery.

# A projection with no table of its own owns no gesture.
get_projection_gesture_bindings(::Projection, iomap) = GestureBinding[]

"""
    read_projection_gesture(projection, iomap, event; claimed = nothing) -> Operation | Nothing

Fire the first reified `get_projection_gesture_bindings(projection, iomap)`
binding whose pattern `matches` the event and whose `applicable`
precondition holds; a binding whose `operation` returns `nothing` is
skipped so a later one may still fire. The projection-layer analogue of
`read_bound_gesture`: a projection whose reader delegates here *fires* the very
table a listing *shows*. `claimed` is the answer that a part nearer the gesture
already gave, and with it only an `override` binding fires
([`fire_gesture_bindings`](@ref)).

It answers a `CollectIntents` payload too, because `fire_gesture_bindings` does.
A projection that routes its gestures through here needs no separate collector.
"""
function read_projection_gesture(projection, iomap, event; claimed = nothing)
    bindings = get_projection_gesture_bindings(projection, iomap)
    isempty(bindings) && return nothing
    input = get_iomap_input(iomap)
    selection = input isa Document ? get_selection(input) : nothing
    return fire_gesture_bindings(bindings, input, event; selection, claimed)
end

"""
    read_gesture(projection, iomap, gesture; claimed = nothing) -> Operation | Nothing

The operation that one stage makes of `gesture`, a gesture that no stage nearer
the screen turned into an operation, or `nothing` when the stage has nothing to
say. It calls no child: [`read_intent`](@ref) calls it for its own stage, and
passes a change to a child only through the `read_intent` of the child.

The default fires the gesture table of the projection
([`get_projection_gesture_bindings`](@ref)), then the table of the input document
(`read_gesture(document, gesture)`), and the first answer wins. A `CollectIntents`
payload collects the rows of both, the projection's first. `claimed` is the
answer that a part nearer the gesture already gave; with it, only an `override`
rule answers, and its answer wins over the claimed one.

A projection adds a method for the kind of gesture that it reads, and Julia
chooses the method by the type of the gesture.

# Example

    # A click on the right edge of the drawn box makes the box narrower.
    function read_gesture(p::BoxToGraphics, iomap, click::MouseClick; claimed = nothing)
        click.x >= iomap.input.width - 4 || return nothing
        ShrinkBoxOperation(iomap.input)
    end

See also `map_operation_backward`, the other job of a stage, and `read_intent`,
which passes a change from stage to stage.
"""
function GestureBindingModule.read_gesture(projection::Projection, iomap, gesture; claimed = nothing)
    own = read_projection_gesture(projection, iomap, gesture; claimed)
    input = (iomap !== nothing && hasproperty(iomap, :input)) ? iomap.input : nothing
    table = input isa Document ? read_gesture(input, gesture; claimed) : nothing
    gesture isa CollectIntents && return merge_collected_intents(_get_collected(own), _get_collected(table))
    own === nothing ? table : own
end

# A collection, or `nothing` for an answer that is none.
_get_collected(answer) = answer isa CollectedIntentsOperation ? answer : nothing
