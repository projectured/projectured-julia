"""
    TypeDispatchingModule

A higher-order projection that selects an inner projection based on the
runtime type of the input document. Enables polymorphic pipelines (e.g.
handling both JSON and XML in one pass) without scattering type-case logic
across individual projection methods.
"""
module TypeDispatchingModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
export TypeDispatchingProjection

"""
    TypeDispatchingProjection(pairs...)

A compound projection that dispatches to different projections based on
the input type. Given a list of `(Type, projection)` pairs, calling
`projection_print` applies the projection associated with the first
matching type.

# Example

    tdp = TypeDispatchingProjection(
        JsonDocument  => JsonToSyntax(),
        SyntaxDocument => SyntaxToText(),
        TextText => TextToGraphics(),
    )
    result = projection_print(tdp, some_json_doc)  # uses JsonToSyntax
"""
struct TypeDispatchingProjection <: Projection
    dispatch::Vector{Pair{DataType, Any}}
end

TypeDispatchingProjection(pairs::Pair...) =
    TypeDispatchingProjection(collect(Pair{DataType, Any}, pairs))

"""
    projection_print(tdp::TypeDispatchingProjection, input, recursion, ctx) -> output

Apply the projection whose type matches `input` first.
Throws an error if no matching type is found.
"""
function projection_print(tdp::TypeDispatchingProjection, input, recursion, ctx)
    for (T, proj) in tdp.dispatch
        if input isa T
            return projection_print(proj, input, recursion, ctx)
        end
    end
    error("TypeDispatchingProjection: no projection registered for type $(typeof(input))")
end

# TypeDispatchingProjection is a transparent wrapper — it returns the inner
# projection's IoMap directly, so input/output fields are already correct.

function projection_read(tdp::TypeDispatchingProjection, iomap, op)
    for (T, proj) in tdp.dispatch
        if iomap.input isa T
            return projection_read(proj, iomap, op)
        end
    end
    return nothing
end

function map_reference_forward(::TypeDispatchingProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::TypeDispatchingProjection, iomap, reference)
    return nothing
end

end # module
