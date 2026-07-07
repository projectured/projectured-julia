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
    Example(name, make_document, make_projection; render_width=nothing, render_height=nothing, terminal=:abstract) =
        new(name, make_document, make_projection, make_document(), make_projection(),
            render_width, render_height, terminal)
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
