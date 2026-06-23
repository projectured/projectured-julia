"""
    SequentialProjectionModule

Chains projections left-to-right for the printer and right-to-left for
the reader. Intermediate IoMaps are stored so the reader can walk backwards
through the chain, translating an event from the output domain back to the
input domain one step at a time.
"""
module SequentialProjectionModule

import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection, Change, as_change
import ..GestureBindingModule: collect_gestures, GestureBinding
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
    projection_read(seq::SequentialProjection, recursion, change::Change, iomap::SequentialProjectionIoMap)

Thread one `Change` through the chain. Search the steps from last to first until
one produces an operation (a change whose `operation !== nothing`), then walk
backwards through the earlier steps translating that change into each step's input
domain. The gesture rides along for free — it is a field of the threaded `Change`,
constant at every step. A nothing-change short-circuits.
"""
function projection_read(seq::SequentialProjection, recursion, change::Change, iomap::SequentialProjectionIoMap)
    n = length(seq.projections)
    start_i = n
    out = projection_read(seq.projections[n], recursion, change, iomap.step_iomaps[n])
    while out.operation === nothing && start_i > 1
        start_i -= 1
        out = projection_read(seq.projections[start_i], recursion, change, iomap.step_iomaps[start_i])
    end
    out.operation === nothing && return out
    for i in (start_i-1):-1:1
        out.operation === nothing && return out
        out = projection_read(seq.projections[i], recursion, out, iomap.step_iomaps[i])
    end
    return out
end

# 3-arg compatibility shim: legacy callers (tests, hit-test recursion) that pass a
# bare event/operation get it wrapped into a Change and the operation back.
projection_read(seq::SequentialProjection, iomap::SequentialProjectionIoMap, payload) =
    projection_read(seq, nothing, as_change(payload), iomap).operation

# Where the reader threads one change through the chain, the collector gathers
# every stage's gestures (each stage's own input document, plus projection-owned
# gestures), so the help shows the union available across the whole pipeline.
function collect_gestures(seq::SequentialProjection, recursion, iomap::SequentialProjectionIoMap)
    result = GestureBinding[]
    for (p, step) in zip(seq.projections, iomap.step_iomaps)
        append!(result, collect_gestures(p, recursion, step))
    end
    return result
end

function map_reference_forward(::SequentialProjection, iomap, reference)
    return nothing
end

function map_reference_backward(::SequentialProjection, iomap, reference)
    return nothing
end

end # module
