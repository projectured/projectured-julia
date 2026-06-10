"""
    SequentialProjectionModule

Chains projections left-to-right for the printer and right-to-left for
the reader. Intermediate IoMaps are stored so the reader can walk backwards
through the chain, translating an event from the output domain back to the
input domain one step at a time.
"""
module SequentialProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..IoMapModule: SimpleIoMap
import ..IoMapApiModule: IoMap
export SequentialProjection, SequentialProjectionIoMap

struct SequentialProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    step_iomaps::Vector{Any}
end

"""
    SequentialProjection(projections...)

A compound higher-order projection that applies a sequence of projections
one after the other.  Given projections `[p₁, p₂, …, pₙ]`, calling
`projection_print` feeds the input through:

    input → p₁ → p₂ → … → pₙ → output

Each intermediate result is a reactive data structure produced by the
previous projection's `projection_print`.  Because every primitive
projection already returns lazy, incremental reactive structures,
the full chain is automatically lazy and incremental — changes at the
source propagate through each layer only when (and as far as) needed.

# Example

    seq = SequentialProjection(
        JsonToSyntax(),
        SyntaxToText(),
        TextToGraphics()
    )
    sdl_texts = projection_print(seq, json_doc)
"""
struct SequentialProjection <: Projection
    projections::Vector{Any}
    SequentialProjection(projections::Vector{Any}) = new(projections)
end

SequentialProjection(ps...) = SequentialProjection(collect(Any, ps))

"""
    projection_print(seq::SequentialProjection, recursion, input, ctx) -> output

Apply each projection in order, threading the reactive output of one
as the input to the next.
"""
function projection_print(seq::SequentialProjection, recursion, input, ctx)
    current = input
    step_iomaps = Any[]
    for p in seq.projections
        iomap = projection_print(p, recursion, current, ctx)
        push!(step_iomaps, iomap)
        current = iomap.output
    end
    return SequentialProjectionIoMap(seq, input, current, step_iomaps)
end

"""
    projection_read(seq::SequentialProjection, iomap::SequentialProjectionIoMap, event)

Try each step from last to first until one handles `event` (returns non-nothing).
Then walk backwards through all earlier steps, translating the operation into
each step's input domain.  Short-circuits if any step returns `nothing`.
"""
function projection_read(seq::SequentialProjection, iomap::SequentialProjectionIoMap, event)
    n = length(seq.projections)
    start_i = n
    op = projection_read(seq.projections[n], iomap.step_iomaps[n], event)
    while op === nothing && start_i > 1
        start_i -= 1
        op = projection_read(seq.projections[start_i], iomap.step_iomaps[start_i], event)
    end
    op === nothing && return nothing
    for i in (start_i-1):-1:1
        op === nothing && return nothing
        op = projection_read(seq.projections[i], iomap.step_iomaps[i], op)
    end
    return op
end

function map_reference_forward(::SequentialProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::SequentialProjection, iomap, reference)
    return nothing
end

end # module
