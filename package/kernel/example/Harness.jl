# ═══════════════════════════════════════════════════════════════════════════
# kernel-example/Harness.jl
#
# The layer-agnostic example harness core: the `Example` struct every example
# package builds and every test driver dispatches on, plus the harness entry
# points that compile against kernel API alone — `write_example_image` and
# `record_example_video` call the kernel backend seams (`write_image`,
# `record_video`; the SDL/Video packages register the methods when loaded),
# and `make_typein_gestures` builds kernel keyboard events.
#
# The name-lookup variants (`write_example_image("json")`, …) live in the
# `ProjecturedExample` umbrella, which owns the global `examples` registry.
# ═══════════════════════════════════════════════════════════════════════════

struct Example
    name::String
    make_document
    make_projection
    document
    projection
    # Optional presentation size for the screenshot harness. Most examples size
    # to their content; a few (e.g. the standalone assistant, which has no window
    # to fill) need a display width seeded so they render at a useful size. This
    # is a *presentation* choice and lives here, not as a fixed size baked into
    # the projection.
    render_width
    render_height
    # The projection's terminal output domain — `:abstract` (unknown / domain-agnostic),
    # `:syntax`, `:text`, or `:graphics`. It is the single pivot the discovered catalog
    # uses to decide *which tests apply* and *whether the example is runnable on screen*
    # (see Catalog.jl). Authored examples leave it `:abstract`; catalog entries set it by
    # construction. Presentation-only; does not affect projection behaviour.
    terminal
    # How this example came to be: `:manual` (hand-authored — the curated registry) or
    # `:generated` (derived by the discovered catalog from an `AtomicDocument` plus an
    # auto-found projection). Metadata only; lets tools/tests tell a curated example apart
    # from an auto-derived catalog entry, and lets the gallery/screenshots keep to `:manual`.
    origin
    Example(name, make_document, make_projection; render_width=nothing, render_height=nothing,
            terminal=:abstract, origin=:manual) =
        new(name, make_document, make_projection, make_document(), make_projection(),
            render_width, render_height, terminal, origin)
end

# ── Atomic documents: the hand-authored building blocks of the discovered catalog ──
# One meaningful instance per atomic (leaf-ish) document type, tagged with the domain it
# belongs to and a short leaf name. The catalog (see the `ProjecturedExample` umbrella's
# `Catalog.jl`) turns each into up to three `Example`s — the trivial single-step
# projection and the composite projections that reach `:text` and `:graphics` — under
# hierarchical `domain/name/variant` names. `make_document` is a thunk so every derived
# example gets a fresh, unaliased instance (the reactive layer mutates in place).
struct AtomicDocument
    domain::Symbol      # level 1 of the catalog hierarchy, e.g. :json — first, so a call
    name::String        # level 2 of the catalog hierarchy, e.g. "string" — reads "json/string"
    make_document       # () -> a fresh document instance
end

"""
    force_projected(node, depth = 0) -> nothing

Read every cell under a printed tree, so that whatever the printer deferred is
actually computed.

A projection prints lazily: it returns a tree of thunks, and the printers run
when the cells are read. Anything that only inspects a printer's `output` has
therefore not run the projection, it has run the first step of it. Two callers
need that difference and got it wrong in opposite directions — the catalog's
bridge search accepted a projection that throws on the first read, and a
precompile workload compiles almost nothing until it walks what it printed.

The depth cap guards against cyclic structure, not against size.
"""
function force_projected(node, depth::Int = 0)
    depth > 40 && return nothing
    node isa ProjecturedKernel.CellModule.AbstractCell &&
        return force_projected(node[], depth)
    for field in (:elements, :content, :canvas, :children, :items)
        hasproperty(node, field) || continue
        value = getproperty(node, field)
        value isa ProjecturedKernel.CellModule.AbstractCell && (value = value[])
        if value isa AbstractVector
            for child in value
                force_projected(child, depth + 1)
            end
        elseif value !== nothing && !(value isa AbstractString)
            force_projected(value, depth + 1)
        end
    end
    nothing
end

function write_example_image(example::Example, filename;
                              width=nothing, height=nothing,
                              max_width=1800, max_height=1200, kwargs...)
    write_image(example.document, example.projection, filename;
                width=width, height=height,
                max_width=max_width, max_height=max_height, kwargs...)
end

function record_example_video(example::Example, gestures, filename;
                              width=1200, height=800, fps=30, kwargs...)
    record_video(example.document, example.projection, gestures, filename;
                 width=width, height=height, fps=fps, kwargs...)
end

"""
    make_typein_gestures(text; hold=0.15, jitter=0.6) -> Vector

Turn `text` into a list of timed `record_video` gestures: one
`(event = KeyPress(char), hold = …)` per character, in order. Feed the result to
`record_video`/`record_example_video` to record someone typing `text`. The
recording needs an `initial_selection` (a text caret) for the keypresses to land.

To mimic human typing, each hold is `hold` scaled by a random factor in
`[1-jitter, 1+jitter]` (so `hold` is the *average* per-key duration and `jitter`
∈ `[0,1]` is how irregular the rhythm is). `jitter=0` gives a perfectly even
machine cadence. Holds are drawn fresh on every call.
"""
function make_typein_gestures(text::AbstractString; hold::Real=0.15, jitter::Real=0.6)
    j = clamp(Float64(jitter), 0.0, 1.0)
    [(event = KeyPress(c), hold = hold * (1 + j * (2 * rand() - 1))) for c in text]
end
