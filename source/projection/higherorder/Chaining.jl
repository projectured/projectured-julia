# Fragment of `ProjectionAlgebraModule`.
#
# Chains projections left-to-right for the printer and right-to-left for
# the reader. Intermediate IoMaps are stored so the reader can walk backwards
# through the chain, translating an event from the output domain back to the
# input domain one step at a time.
# Each `step_iomaps` cell holds one stage's IoMap, recomputed (re-printed) when an
# upstream stage's output changes *structurally*. `output` is a computed cell over the
# LAST stage's raw output — exactly as the old eager Sequential threaded it
# (`current = iomap.output`): if the final stage exposes a Cell-valued output it is
# preserved (consumers like an inner text pipe do `seqiomap.output[]`), because
# `@iomap` unwraps only the `output` field's own cell, revealing the last stage's
# (possibly Cell-valued) output. Reading it pulls the last stage cell, which recomputes
# lazily if a structural change upstream invalidated the chain. (Only the threading
# *between* stages unwraps a Cell-valued output to the plain value the next stage
# prints — see `_seq_stage`.) As an `@iomap` struct, `output` is a stored computed cell
# rather than a synthesized property, so `iomap.output` / `hasproperty` work uniformly.
@iomap struct ChainingIoMap
    projection::Any
    input::Any
    step_iomaps::Any    # Vector{Cell}; wrapped by @iomap so `iomap.step_iomaps` reads the vector
    output::Any         # computed: the last stage's output — `step_iomaps[end][].output`
end

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
    return ChainingIoMap(seq, input, step_iomaps,
                                   Cell(@computation step_iomaps[end][].output))
end

# Pure: thread each stage's immutable output straight into the next stage — no
# per-stage cells, no iomaps. Each stage recurses through the pure interpreter.
function print_document_pure(seq::ChainingProjection, recursion, input, ctx)
    out = input
    for p in seq.projections
        out = print_document_pure(p, recursion, out, ctx)
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
    out_cell   = Cell(@computation unwrap_cell(iomap_cell[].output))
    (iomap_cell, out_cell)
end

"""
    read_intent(seq::ChainingProjection, recursion, change::Intent, iomap::ChainingIoMap)

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

**A claim that no step can carry is no claim.** When a step can not translate the
operation a later step made of the gesture, nothing of that operation reaches the
input, so the gesture is unclaimed again: that step and the ones before it read the
raw gesture, as if no later step had answered. A text insert on a delimiter, or a
comma in a number, dies at the step that owns the delimiter or the number, and that
step then answers the key with its own meaning.
"""
function read_intent(seq::ChainingProjection, recursion, change::Intent, iomap::ChainingIoMap)
    change.gesture isa CollectIntents &&
        return Intent(change.gesture, _collect_intents(seq, recursion, iomap))
    change.route === nothing || return _read_routed_chain(seq, recursion, change, iomap)
    return _read_chain_from(seq, recursion, change, iomap, length(seq.projections))
end

# Read `change` from step `last_i` back to the first: search from `last_i` for a
# step that answers, then carry its answer back through the steps before it. A
# step that can not carry the answer reads the raw gesture itself, together with
# the steps before it.
function _read_chain_from(seq::ChainingProjection, recursion, change::Intent,
                          iomap::ChainingIoMap, last_i::Int)
    start_i = last_i
    out = read_intent(seq.projections[start_i], recursion, change, iomap.step_iomaps[start_i][])
    while out.operation === nothing && start_i > 1
        start_i -= 1
        out = read_intent(seq.projections[start_i], recursion, change, iomap.step_iomaps[start_i][])
    end
    out.operation === nothing && return out
    for i in (start_i-1):-1:1
        carried = read_intent(seq.projections[i], recursion, out, iomap.step_iomaps[i][])
        carried.operation === nothing && return _read_chain_from(seq, recursion, change, iomap, i)
        out = carried
    end
    return out
end

# An operation with a route to a place in the chain's input. The route is mapped
# forward through each stage that prints the place as the same document, as the
# printer maps a reference; the first stage that does not, or the last stage, is
# the one whose readers hold the place. From that stage the operation comes back
# up through the earlier stages, as an answer does.
function _read_routed_chain(seq::ChainingProjection, recursion, change::Intent,
                            iomap::ChainingIoMap)
    n = length(seq.projections)
    place = try_evaluate_reference(iomap.input, change.route, nothing)
    place === nothing && return Intent(change.gesture, nothing)
    stage, route = 1, change.route
    while stage < n
        stage_iomap = iomap.step_iomaps[stage][]
        next_iomap = iomap.step_iomaps[stage + 1][]
        forward = map_reference_forward(stage_iomap.projection, stage_iomap, route)
        forward === nothing && break
        try_evaluate_reference(next_iomap.input, forward, nothing) === place || break
        stage, route = stage + 1, forward
    end
    routed = Intent(change.gesture, change.operation, change.description, change.domain, route)
    out = read_routed_intent(seq.projections[stage], recursion, routed, iomap.step_iomaps[stage][])
    for i in (stage - 1):-1:1
        out.operation === nothing && return out
        out = read_intent(seq.projections[i], recursion, out, iomap.step_iomaps[i][])
    end
    out
end

# 3-arg payload form: callers (tests, hit-test recursion) that pass a
# bare event/operation get it wrapped into a Intent and the operation back.
read_intent(seq::ChainingProjection, iomap::ChainingIoMap, payload) =
    read_intent(seq, nothing, Intent(payload), iomap).operation

# Where threading one gesture stops at the first stage that answers, a collection
# takes every stage's answer. This is the one place the two differ, and it is
# Lisp's `merge-commands`: a stage returns its own commands merged with the ones
# its child produced, rather than whichever came first.
#
# Walk last stage to first. At each step, map what the later stages contributed
# into this stage's input domain — the same backward threading an ordinary
# operation gets — then put this stage's own contribution in front of it. What
# arrives at stage 1 is expressed in the chain's input vocabulary, ready to run.
function _collect_intents(seq::ChainingProjection, recursion, iomap::ChainingIoMap)
    accumulated = nothing
    for i in length(seq.projections):-1:1
        step = iomap.step_iomaps[i][]
        own = read_intent(seq.projections[i], recursion, Intent(CollectIntents()), step).operation
        mapped = accumulated === nothing ? nothing :
                 read_intent(seq.projections[i], recursion,
                             Intent(CollectIntents(), accumulated), step).operation
        accumulated = merge_collected_intents(_collected(own), _collected(mapped))
    end
    accumulated
end

# A stage that has nothing to say may answer with anything at all; only a real
# collection counts.
_collected(op::CollectedIntentsOperation) = op
_collected(::Any) = nothing

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
