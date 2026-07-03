"""
    TypeDispatchingProjectionModule

A higher-order projection that selects an inner projection based on the
runtime type of the input document. Enables polymorphic pipelines (e.g.
handling both JSON and XML in one pass) without scattering type-case logic
across individual projection methods.
"""
module TypeDispatchingProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..ChangeModule: Change
import ..GestureBindingModule: collect_gestures, GestureBinding
export TypeDispatchingProjection

"""
    TypeDispatchingProjection(pairs...)

A compound projection that dispatches to different projections based on
the input type. Given a list of `(Type, projection)` pairs, calling
`projection_print` applies the projection associated with the first
matching type (`input isa T`). The key may be any `Type` — a concrete type,
an abstract type, or a `Union` such as `Union{JsonNull,JsonBool}`.

# Example

    tdp = TypeDispatchingProjection(
        JsonDocument  => JsonToSyntax(),
        SyntaxDocument => SyntaxToText(),
        TextText => TextToGraphics(),
    )
    result = projection_print(tdp, some_json_doc)  # uses JsonToSyntax
"""
struct TypeDispatchingProjection <: Projection
    dispatch::Vector{Pair{Type, Any}}
end

TypeDispatchingProjection(pairs::Pair...) =
    TypeDispatchingProjection(collect(Pair{Type, Any}, pairs))

"""
    projection_print(tdp::TypeDispatchingProjection, recursion, input, ctx) -> output

Apply the projection whose type matches `input` first.
Throws an error if no matching type is found.
"""
function projection_print(tdp::TypeDispatchingProjection, recursion, input, ctx)
    for (T, proj) in tdp.dispatch
        if input isa T
            return projection_print(proj, recursion, input, ctx)
        end
    end
    error("TypeDispatchingProjection: no projection registered for type $(typeof(input))")
end

# TypeDispatchingProjection is a transparent wrapper — it returns the inner
# projection's IoMap directly, so input/output fields are already correct.

function projection_read(tdp::TypeDispatchingProjection, recursion, change::Change, iomap)
    for (T, proj) in tdp.dispatch
        if iomap.input isa T
            return projection_read(proj, recursion, change, iomap)
        end
    end
    return Change(change.gesture, nothing)
end

projection_read(tdp::TypeDispatchingProjection, iomap, payload) =
    projection_read(tdp, nothing, Change(payload), iomap).operation

# Gather from the projection that matches the (transparent) input's type, exactly
# as the reader dispatches to it.
function collect_gestures(tdp::TypeDispatchingProjection, recursion, iomap)
    for (T, proj) in tdp.dispatch
        if iomap.input isa T
            return collect_gestures(proj, recursion, iomap)
        end
    end
    return GestureBinding[]
end

function map_reference_forward(::TypeDispatchingProjection, iomap, reference)
    # TypeDispatchingProjection is transparent: it returns the selected inner
    # projection's IoMap directly, so iomap.projection is the inner projection.
    # Delegate to it so that reference mapping works end-to-end (e.g. the Julia
    # leaf projections fall through to the generic default which unwraps
    # ProjectionReference wrappers).
    map_reference_forward(iomap.projection, iomap, reference)
end

function map_reference_backward(::TypeDispatchingProjection, iomap, reference)
    # Mirror of map_reference_forward: delegate to the inner projection.
    map_reference_backward(iomap.projection, iomap, reference)
end

end # module
