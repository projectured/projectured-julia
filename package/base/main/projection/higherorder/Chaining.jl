"""
    ChainingProjectionModule

Chains projections left-to-right for the printer and right-to-left for
the reader. Intermediate IoMaps are stored so the reader can walk backwards
through the chain, translating an event from the output domain back to the
input domain one step at a time.
"""
module ChainingProjectionModule

import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection,
       pure_print_document
import ..IntentModule: Intent
import ..GestureBindingModule: GestureBinding
import ..ProjectionGestureBindingsModule: collect_gesture_bindings
import ..IoMapModule: SimpleIoMap
import ..IoMapModule: IoMap, reconcile_child_iomap
import ..CellModule: Cell, AbstractCell, unwrap_cell
export ChainingProjection, ChainingProjectionIoMap

# Each `step_iomaps` cell holds one stage's IoMap, recomputed (re-printed) when an
# upstream stage's output changes *structurally*. `iomap.output` returns the LAST
# stage's raw output — exactly as the old eager Sequential threaded it
# (`current = iomap.output`): if the final stage exposes a Cell-valued output, it is
# preserved (consumers like an inner text pipe do `seqiomap.output[]`). Reading it
# pulls the last stage cell, which recomputes lazily if a structural change upstream
# invalidated the chain. (Only the threading *between* stages unwraps a Cell-valued
# output to the plain value the next stage prints — see `_seq_stage`.)
struct ChainingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    step_iomaps::Vector{Cell}
end

function Base.getproperty(io::ChainingProjectionIoMap, name::Symbol)
    name === :output && return getfield(io, :step_iomaps)[end][].output
    getfield(io, name)
end

# `:output` is synthesized, not a field, so `propertynames` must list it too —
# otherwise `hasproperty(iomap, :output)` is false while `iomap.output` works, and
# a caller guarding its access with `hasproperty` silently skips every chain.
Base.propertynames(::ChainingProjectionIoMap, private::Bool=false) =
    (fieldnames(ChainingProjectionIoMap)..., :output)

"""
    ChainingProjection(projections...)

A compound higher-order projection that applies a sequence of projections
one after the other.  Given projections `[p₁, p₂, …, pₙ]`, calling
`print_document` feeds the input through:

    input → p₁ → p₂ → … → pₙ → output

Each intermediate result is a reactive data structure produced by the
previous projection's `print_document`.  Because every primitive
projection already returns lazy, incremental reactive structures,
the full chain is automatically lazy and incremental — changes at the
source propagate through each layer only when (and as far as) needed.

# Example

    seq = ChainingProjection(
        JsonToSyntax(),
        SyntaxToText(),
        TextToGraphics()
    )
    sdl_texts = print_document(seq, json_doc)
"""
struct ChainingProjection <: Projection
    projections::Vector{Any}
    ChainingProjection(projections::Vector{Any}) = new(projections)
end

ChainingProjection(ps...) = ChainingProjection(collect(Any, ps))

"""
    print_document(seq::ChainingProjection, recursion, input, ctx) -> output

Apply each projection in order, threading the reactive output of one as the input
to the next. Each stage's `print_document` is wrapped in a computed cell keyed on
the previous stage's output cell, so a *structural* change in a stage's output
(e.g. a projection that swaps which child it exposes) re-prints exactly that stage
and the stages after it — value changes still propagate through each stage's
existing IoMap without re-printing (the per-stage output cell reads only the
structural choice, not inner values).

The chain is **forced once here** so the initial build happens eagerly at print
time (the same timing the rest of the pipeline assumes), not lazily on the first
reader/render access. Cells stay re-pullable, so a later structural change still
recomputes only the affected stages; we just don't defer the *first* compute.
"""
function print_document(seq::ChainingProjection, recursion, input, ctx)
    step_iomaps = Cell[]
    out = Cell(input)                         # stage 1's input, as a (constant) cell
    for p in seq.projections
        iomap_cell, out = _seq_stage(p, recursion, out, ctx)
        push!(step_iomaps, iomap_cell)
    end
    foreach(getindex, step_iomaps)            # eager initial build (forces every stage)
    return ChainingProjectionIoMap(seq, input, step_iomaps)
end

# Pure: thread each stage's immutable output straight into the next stage — no
# per-stage cells, no iomaps. Each stage recurses through the pure interpreter.
function pure_print_document(seq::ChainingProjection, recursion, input, ctx)
    out = input
    for p in seq.projections
        out = pure_print_document(p, recursion, out, ctx)
    end
    out
end

# One stage: its IoMap reconciles over the previous stage's output cell — the
# shared `reconcile_child_iomap` rebuilds the stage only when its input's identity
# swaps structurally, and reuses the stage's (reactive) IoMap while the input is the
# same object, so a content edit propagates through that held IoMap with no re-print.
# Its output cell unwraps a Cell-valued `iomap.output` (projections may expose a
# reactive output) to the plain value the next stage prints. A helper so each closure
# captures its own `p`/`prev`.
function _seq_stage(p, recursion, prev::Cell, ctx)
    iomap_cell = reconcile_child_iomap(() -> prev[], v -> print_document(p, recursion, v, ctx))
    out_cell   = Cell(() -> unwrap_cell(iomap_cell[].output))
    (iomap_cell, out_cell)
end

"""
    read_intent(seq::ChainingProjection, recursion, change::Intent, iomap::ChainingProjectionIoMap)

Thread one `Intent` through the chain. Search the steps from last to first until
one produces an operation (a change whose `operation !== nothing`), then walk
backwards through the earlier steps translating that change into each step's input
domain. The gesture rides along for free — it is a field of the threaded `Intent`,
constant at every step. A nothing-change short-circuits.

Reading is **last to first**, the mirror of printing. A step that produces no
operation passes the raw gesture on to the step before it, so the input-domain
stage — the last one visited, the one that owns the meaning of an edit — gets its
say on any key the output layers decline (a `,` on a delimiter where the text edit
would die becomes a JSON sibling insert). A step *also* sees the gesture when an
operation has already been produced, so it can supersede a claimed key rather than
translate it: that is the `override` flag on a `GestureBinding`, not a privilege
the chain hands out. A structural gesture therefore never has to reconstruct what
the output layers would have done in order to decline — if they did anything, they
already did it.
"""
function read_intent(seq::ChainingProjection, recursion, change::Intent, iomap::ChainingProjectionIoMap)
    n = length(seq.projections)
    start_i = n
    out = read_intent(seq.projections[n], recursion, change, iomap.step_iomaps[n][])
    while out.operation === nothing && start_i > 1
        start_i -= 1
        out = read_intent(seq.projections[start_i], recursion, change, iomap.step_iomaps[start_i][])
    end
    out.operation === nothing && return out
    for i in (start_i-1):-1:1
        out.operation === nothing && return out
        out = read_intent(seq.projections[i], recursion, out, iomap.step_iomaps[i][])
    end
    return out
end

# 3-arg payload form: callers (tests, hit-test recursion) that pass a
# bare event/operation get it wrapped into a Intent and the operation back.
read_intent(seq::ChainingProjection, iomap::ChainingProjectionIoMap, payload) =
    read_intent(seq, nothing, Intent(payload), iomap).operation

# Where the reader threads one change through the chain, the collector gathers
# every stage's gestures (each stage's own input document, plus projection-owned
# gestures), so the help shows the union available across the whole pipeline.
function collect_gesture_bindings(seq::ChainingProjection, recursion, iomap::ChainingProjectionIoMap)
    result = GestureBinding[]
    for (p, step) in zip(seq.projections, iomap.step_iomaps)
        append!(result, collect_gesture_bindings(p, recursion, step[]))
    end
    return result
end

# Compose forward-mapping through the chain: thread the reference through each
# stage's own `map_reference_forward`, input domain → … → output domain. Stages
# wire their own `output.selection`, so this is unused for cursor wiring; it
# exists so a reference (including a graphics-domain `PointReferenceStep` produced by
# the final stage) resolves end-to-end through a Sequential — e.g. anchoring a
# popup to a widget. A stage that drops the reference returns `nothing`, which
# short-circuits.
function map_reference_forward(::ChainingProjection, iomap, reference)
    ref = reference
    for cell in iomap.step_iomaps
        ref === nothing && return nothing
        step = cell[]
        ref = map_reference_forward(step.projection, step, ref)
    end
    ref
end

function map_reference_backward(::ChainingProjection, iomap, reference)
    return nothing
end

end # module
