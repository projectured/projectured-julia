"""
    PlaybackModule

Scripted live playback: drive the editor's read-eval-print loop while firing a
predefined timeline on a wall-clock schedule, so a scripted session unfolds in a
real window. Extracted from Editor.jl; builds on the editor-loop primitives
(`read!`/`evaluate!`/`print!`/`perf!`).
"""
module PlaybackModule

# The read/evaluate/print/perf loop steps are internal to `EditorModule` (not
# exported), so they have to be named explicitly.
using ..EditorModule: Editor, read!, evaluate!, print!, perf!
using ..PerformanceCounterModule
using ..ProjectionApiModule
using ..IntentModule
using ..EventModule
using ..OperationModule
using ..ReferenceModule
using ..BackendModule
using ..DeviceModule

export play_live!

# Walk a reference path into a tuple of steps (outermost first), for rerooting.
_path_to_steps(::EmptyReferencePath) = ()
function _path_to_steps(path::ConcreteReferencePath)
    steps = Any[]
    cur = path
    while cur isa ConcreteReferencePath
        push!(steps, cur.head)
        cur = cur.tail
    end
    Tuple(steps)
end

"""
    _timeline_operation(editor::Editor, entry, window_id::Symbol, op_prefix::Tuple) -> Operation or nothing

Turn one timeline entry into an operation, mirroring `read!`. An entry carrying
`event` is wrapped in `WindowInput(window_id, event)` and run through the
reader pipeline (the same path live input takes), which already roots the
resulting operation in the document root. An entry carrying `operation` is taken
directly — either an `Operation` value or a `doc -> op` thunk evaluated against
the current `editor.document` — and its reference path is rerooted by
`op_prefix` (the steps from the document root to the wrapped content), since a
directly-injected operation bypasses the reader's rerooting. Returns `nothing`
when nothing applies.
"""
function _timeline_operation(editor::Editor, entry, window_id::Symbol, op_prefix::Tuple)
    # An `await` entry (see `timed_await`) is a pure pause: it injects no
    # operation. The live loop renders and yields every frame, so an async turn
    # already kicked off by a prior ENTER streams in live during its dwell.
    haskey(entry, :await) && return nothing
    if haskey(entry, :operation)
        op = entry.operation isa Function ? entry.operation(editor.document) : entry.operation
        op isa Operation || return nothing
        return isempty(op_prefix) ? op : reroot_operation(op, op_prefix)
    else
        editor.iomap === nothing && return nothing
        env = WindowInput(window_id, entry.event)
        change = read_intent(editor.projection, nothing, Intent(env, nothing), editor.iomap)
        op = change isa Intent ? change.operation : change
        return op isa Operation ? op : nothing
    end
end

"""
    play_live!(editor::Editor, timeline; window_id::Symbol, initial_hold::Real=0.5,
               op_prefix::ReferencePath=EmptyReferencePath())

Run the read-eval-print loop while firing a predefined `timeline` on a
wall-clock schedule, so the user watches the scripted session unfold in a real
window. Entry `i` fires `initial_hold + Σ hold[1..i-1]` seconds after start;
`hold` is the dwell after the entry is applied (the same field used by
[`record_video`](@ref), so one timeline drives both the headless recording and
this live playback).

Each entry carries either an `event` (wrapped in an `WindowInput` for
`window_id` and run through the reader, like live input) or an `operation` (a
domain `Operation` value, or a `doc -> op` thunk, injected straight into the
evaluator). At most one scheduled entry is applied per frame, so each resulting
state is visible. Real user input is still polled every frame, so the user can
interact and the window-close button / Escape quits cleanly. After the last
entry the window stays live and interactive.

`op_prefix` reroots directly-injected `operation` entries: a timeline authored
in the bare-content domain (the same coordinates the recorder uses) needs its
operation paths prefixed by the steps from the live document root to that
content (e.g. `windows[1].content` when the example is wrapped in a window).
Event entries are unaffected — the reader already roots them.
"""
function play_live!(editor::Editor, timeline; window_id::Symbol, initial_hold::Real=0.5,
                    op_prefix::ReferencePath=EmptyReferencePath())
    n = length(timeline)
    prefix_steps = _path_to_steps(op_prefix)
    # fire_at[i]: seconds from start at which entry i is applied.
    fire_at = Vector{Float64}(undef, n)
    acc = Float64(initial_hold)
    for i in 1:n
        fire_at[i] = acc
        acc += Float64(timeline[i].hold)
    end
    start = time()
    next = 1
    try
        while true
            with_performance_counters() do
                @performance_time :read_time read!(editor)
                # When no real-input operation is pending and the next scheduled
                # entry is due, inject it. Real input wins the frame; the scheduled
                # entry retries on the following frame.
                if editor.operation === nothing && next <= n && (time() - start) >= fire_at[next]
                    editor.operation = _timeline_operation(editor, timeline[next], window_id, prefix_steps)
                    next += 1
                end
                @performance_time :evaluate_time evaluate!(editor)
                @performance_time :print_time    print!(editor)
                perf!(editor)
            end
            sleep(0.01)
        end
    catch e
        e isa QuitEditorException || rethrow()
    end
end

"""
    play_live!(backend::Backend, projection, document, timeline;
               window_id::Symbol, initial_hold::Real=0.5)

Bootstrap overload: initialise the backend, wire up an `Editor`, and run the
scripted live loop above. Like [`run_editor!`](@ref), the pipeline is expected to
produce a `ScreenDocument` so the backend opens a real window; `window_id` is the
`WindowDocument.id` scripted events are routed to.
"""
function play_live!(backend::Backend, projection, document, timeline;
                    window_id::Symbol, initial_hold::Real=0.5,
                    op_prefix::ReferencePath=EmptyReferencePath())
    initialize_backend!(backend)
    try
        devices = Device[Screen(), Keyboard(), Mouse()]
        editor = Editor(backend, document, projection, devices)
        play_live!(editor, timeline; window_id=window_id, initial_hold=initial_hold,
                   op_prefix=op_prefix)
    finally
        quit_backend!(backend)
    end
end

end # module
