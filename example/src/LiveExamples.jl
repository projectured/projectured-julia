# ═══════════════════════════════════════════════════════════════════════════
# example/src/LiveExamples.jl
#
# A `LiveExample` captures an existing `Example` and pairs it with a *timeline*
# of predefined, timed entries. The same timeline drives two consumers:
#
#   - `record_live_example(live, "x.mp4")` — headless MP4 (via `record_video`),
#   - `play_live_example(live)`            — a real window the user watches.
#
# A timeline entry is a NamedTuple carrying either an `event` (a device event run
# through the reader, like live input) or an `operation` (a domain `Operation`
# value or a `doc -> op` thunk injected straight into the evaluator), plus a
# `hold` in seconds. `hold` is the dwell after the entry: the recorder turns it
# into `round(hold*fps)` frames (video time), the live player into a wall-clock
# delay before the next entry.
# ═══════════════════════════════════════════════════════════════════════════

"""
    LiveExample(name, example, timeline; initial_selection=nothing,
                width=900, height=600, fps=30)

Bundle an existing `Example` with a timed `timeline` (see file header for the
entry format). `initial_selection` seeds the caret (needed for keyboard typein);
it is either a `ReferencePath` or a `doc -> path` thunk evaluated against the
fresh document. `width`/`height`/`fps` are the presentation defaults for both
recording and live playback.
"""
struct LiveExample
    name::String
    example::Example
    timeline::Vector
    initial_selection
    width::Int
    height::Int
    fps::Int
    LiveExample(name, example, timeline; initial_selection=nothing,
                width=900, height=600, fps=30) =
        new(String(name), example, collect(timeline), initial_selection,
            Int(width), Int(height), Int(fps))
end

# ── Timeline builders ─────────────────────────────────────────────────────

"""
    timed_event(event; hold=0.4) -> NamedTuple

A timeline entry that feeds `event` through the reader (like live input).
"""
timed_event(event; hold::Real=0.4) = (event = event, hold = Float64(hold))

"""
    timed_operation(operation; hold=0.4) -> NamedTuple

A timeline entry that injects `operation` straight into the evaluator. `operation`
is an `Operation` value or a `doc -> op` thunk evaluated at fire time against the
current document — use the thunk form when the op must reference live state.
"""
timed_operation(operation; hold::Real=0.4) = (operation = operation, hold = Float64(hold))

# Resolve an `initial_selection` (path or `doc -> path` thunk) against `document`.
_resolve_selection(::Nothing, document) = nothing
_resolve_selection(sel::Function, document) = sel(document)
_resolve_selection(sel, document) = sel

# ── Drivers ────────────────────────────────────────────────────────────────

"""
    record_live_example(live::LiveExample, filename=tempname()*".mp4"; kwargs...) -> String

Record `live`'s timeline into a headless MP4. Reuses `record_video` against the
example's bare document/projection (same content origin as the live window, so a
single timeline's mouse coordinates work in both). Extra `kwargs` pass through to
`record_video` (e.g. `supersample`, `final_hold`, `wait_for`).
"""
function record_live_example(live::LiveExample, filename::AbstractString=tempname()*".mp4"; kwargs...)
    document   = live.example.make_document()
    projection = live.example.make_projection()
    record_video(document, projection, live.timeline, filename;
                 width=live.width, height=live.height, fps=live.fps,
                 initial_selection=_resolve_selection(live.initial_selection, document),
                 kwargs...)
end

function record_live_example(name::AbstractString, filename::AbstractString=tempname()*".mp4"; kwargs...)
    record_live_example(_lookup_live_example(name), filename; kwargs...)
end

"""
    play_live_example(live::LiveExample; width=live.width, height=live.height,
                      initial_hold=0.5)

Open a real window and replay `live`'s timeline at wall-clock speed so the user
watches the scripted session. The example is wrapped in a single
`WindowDocument`/`ScreenDocument` (the same single-window scene `run_example`
builds), so the backend opens a native window; scripted events are routed to that
window via `play_live!`. The window stays interactive after the timeline ends.
"""
function play_live_example(live::LiveExample; width::Integer=live.width,
                           height::Integer=live.height, initial_hold::Real=0.5)
    document   = live.example.make_document()
    projection = live.example.make_projection()

    sel = _resolve_selection(live.initial_selection, document)
    sel === nothing || set_selection!(document, sel)

    window_id = Symbol(live.name)
    win = WindowDocument(; id=window_id, title=live.name,
                         x=100, y=100, width=width, height=height, content=document)
    screen = ScreenDocument([win])

    # Lift the seeded selection to a screen-rooted path, mirroring `run_example`.
    inner_sel = getfield(document, :selection)[]
    inner_sel === nothing || set_selection!(screen, @reference windows[1].content.^(inner_sel))

    composed = _multi_window_projection([projection])
    # Timeline operations are authored in the bare-content domain (like the
    # recorder); in the windowed scene they must be rerooted to the screen by the
    # steps that lead to this window's content. Event entries are rerooted by the
    # reader automatically, so they need no prefix.
    play_live!(SdlBackend(), composed, screen, live.timeline;
               window_id=window_id, initial_hold=initial_hold,
               op_prefix = @reference windows[1].content)
end

function play_live_example(name::AbstractString; kwargs...)
    play_live_example(_lookup_live_example(name); kwargs...)
end

function _lookup_live_example(name::AbstractString)
    idx = findfirst(l -> l.name == name, live_examples)
    idx === nothing && error("Unknown live example: \"$name\". Available: " *
                             join(getfield.(live_examples, :name), ", "))
    live_examples[idx]
end

# ── Predefined live examples ─────────────────────────────────────────────────

# Type "world" into the first string value of the json object ("Alice"), then
# step the caret right a couple of times. Pure events; needs a caret seed.
const json_typein_live = LiveExample("json_typein", json_example,
    vcat(
        make_typein_gestures(" world"),
        [timed_event(KeyDown(:left, Modifiers(), false); hold=0.4),
         timed_event(KeyDown(:left, Modifiers(), false); hold=0.6)],
    );
    initial_selection = @reference entries[1].value.value{5})

# Jump the selection with a timed *operation* (no single event triggers it), then
# type at the new caret. Demonstrates timed operations and events together.
const json_select_and_edit_live = LiveExample("json_select_and_edit", json_example,
    vcat(
        [timed_operation(ReplaceSelectionOperation(@reference entries[4].value.entries[1].value.value{11}); hold=0.6)],
        make_typein_gestures("!"),
    );
    initial_selection = @reference entries[1].value.value{5})

const live_examples = LiveExample[
    json_typein_live,
    json_select_and_edit_live,
]
