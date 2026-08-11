"""
    TypeDispatchingProjectionModule

A higher-order projection that selects an inner projection based on the
runtime type of the input document. Enables polymorphic pipelines (e.g.
handling both JSON and XML in one pass) without scattering type-case logic
across individual projection methods.
"""
module TypeDispatchingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection,
       pure_print_document
import ..IntentModule: Intent
import ..GestureBindingModule: GestureBinding
export TypeDispatchingProjection

"""
    TypeDispatchingProjection(pairs...)

A compound projection that dispatches to different projections based on
the input type. Given a list of `(Type, projection)` pairs, calling
`print_document` applies the projection associated with the first
matching type (`input isa T`). The key may be any `Type` — a concrete type,
an abstract type, or a `Union` such as `Union{JsonNull,JsonBool}`.

# Example

    tdp = TypeDispatchingProjection(
        JsonDocument  => JsonToSyntax(),
        SyntaxDocument => SyntaxToText(),
        TextBlock => TextToGraphics(),
    )
    result = print_document(tdp, some_json_doc)  # uses JsonToSyntax
"""
struct TypeDispatchingProjection <: Projection
    dispatch::Vector{Pair{Type, Any}}
end

TypeDispatchingProjection(pairs::Pair...) =
    TypeDispatchingProjection(collect(Pair{Type, Any}, pairs))

"""
    print_document(tdp::TypeDispatchingProjection, recursion, input, ctx) -> output

Apply the projection whose type matches `input` first.
Throws an error if no matching type is found.
"""
function print_document(tdp::TypeDispatchingProjection, recursion, input, ctx)
    for (T, proj) in tdp.dispatch
        if input isa T
            return print_document(proj, recursion, input, ctx)
        end
    end
    error("TypeDispatchingProjection: no projection registered for type $(typeof(input))")
end

# Pure: same first-match dispatch, into the selected projection's pure interpreter.
function pure_print_document(tdp::TypeDispatchingProjection, recursion, input, ctx)
    for (T, proj) in tdp.dispatch
        if input isa T
            return pure_print_document(proj, recursion, input, ctx)
        end
    end
    error("TypeDispatchingProjection: no projection registered for type $(typeof(input))")
end

# TypeDispatchingProjection is a transparent wrapper — it returns the inner
# projection's IoMap directly, so input/output fields are already correct.

function read_intent(tdp::TypeDispatchingProjection, recursion, change::Intent, iomap)
    for (T, proj) in tdp.dispatch
        if iomap.input isa T
            return read_intent(proj, recursion, change, iomap)
        end
    end
    return Intent(change.gesture, nothing)
end

read_intent(tdp::TypeDispatchingProjection, iomap, payload) =
    read_intent(tdp, nothing, Intent(payload), iomap).operation

function map_reference_forward(::TypeDispatchingProjection, iomap, reference)
    # TypeDispatchingProjection is transparent: it returns the selected inner
    # projection's IoMap directly, so iomap.projection is the inner projection.
    # Delegate to it so that reference mapping works end-to-end (e.g. the Julia
    # leaf projections fall through to the generic default which unwraps
    # ProjectionReferenceStep wrappers).
    map_reference_forward(iomap.projection, iomap, reference)
end

function map_reference_backward(::TypeDispatchingProjection, iomap, reference)
    # Mirror of map_reference_forward: delegate to the inner projection.
    map_reference_backward(iomap.projection, iomap, reference)
end

end # module
