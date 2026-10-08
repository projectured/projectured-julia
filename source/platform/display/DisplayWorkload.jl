# Fragment of `DisplayModule`: the workload of the first window, which a package
# runs in its `@compile_workload` so that its package image holds that code.

"""
    WorkloadBackend(; events = make_workload_events())

A backend with no device. It reads the whole output of each frame, as a backend
that draws reads it, so that every view of the window prints. After its first
output, it gives `events` to the window of that output, one for each read, as a
hand gives them. [`run_display_workload`](@ref) runs the editor with it where no
window opens.
"""
mutable struct WorkloadBackend <: Backend
    events::Vector{Event}
    window_id::Union{Nothing,Symbol}
    writes::Int
    writes_at_last_event::Int
end

WorkloadBackend(; events::Vector{Event} = make_workload_events()) =
    WorkloadBackend(events, nothing, 0, 0)

"""
    make_workload_events() -> Vector{Event}

The gestures of a first look at a window of 1000 × 600: the pointer comes to its
middle, the wheel turns down and up, a click, then the keys Down and Right. Their
times are set when the backend gives them.
"""
make_workload_events() = Event[
    MouseMove(500, 300; time = 0.0),
    MouseScroll(0, -3, 500, 300; time = 0.0),
    MouseScroll(0, 3, 500, 300; time = 0.0),
    MouseDown(:left, 500, 300; time = 0.0),
    MouseUp(:left, 500, 300; time = 0.0),
    KeyDown(:down, ModifierKeys(); time = 0.0),
    KeyDown(:right, ModifierKeys(); time = 0.0),
]

initialize_backend!(::WorkloadBackend) = nothing
quit_backend!(::WorkloadBackend) = nothing

function take_from_devices!(backend::WorkloadBackend, devices)
    (backend.window_id === nothing || isempty(backend.events)) && return nothing
    backend.writes_at_last_event = backend.writes
    WindowInput(backend.window_id, _stamp_event(popfirst!(backend.events), time()))
end

# `event` with the time `time` in place of its own. The time is the last field of
# every event, and the full constructor takes every field.
function _stamp_event(event::Event, time::Float64)
    type = typeof(event)
    type(ntuple(i -> getfield(event, i), fieldcount(type) - 1)..., time)
end

function write_to_devices!(backend::WorkloadBackend, devices, screen::ScreenDocument)
    for window in screen.windows
        backend.window_id === nothing && (backend.window_id = window.id)
        _read_graphics(window.content)
    end
    backend.writes += 1
    nothing
end

# Read `node` and each part of it: a view prints its children when its output is
# read.
function _read_graphics(node)
    node isa AbstractCell && return _read_graphics(node[])
    if node isa GraphicsCanvas
        for element in node.elements
            _read_graphics(element)
        end
    end
    node isa GraphicsViewport && _read_graphics(node.content)
    nothing
end

"""
    run_display_workload(value; backend = WorkloadBackend(), frames = 1) -> Nothing

Show `value` as a user shows it with [`display_in_editor`](@ref), with `backend`
as the backend that a caller who names none gets, until the editor has drawn
`frames` frames and a frame after the last event of a `WorkloadBackend`; then
stop the editor. A `Document` is shown as it is, as the first call of
`display_in_editor` shows the document of a value. A package calls it in its
`@compile_workload`, where no editor of `display_in_editor` runs, so that its
package image holds the code of the first window.
"""
function run_display_workload(value; backend::Backend = WorkloadBackend(), frames::Int = 1)
    with(DEFAULT_BACKEND => backend) do
        if value isa Document
            session = _start_session(value, summary(value); backend = nothing, tabs = true,
                                     refresh_every = nothing)
            try
                _wait_for_workload(session, backend, frames)
            finally
                _close_session!(session)
            end
        else
            display_in_editor(value)
            try
                _wait_for_workload(lock(() -> _SESSION[], _SESSION_LOCK), backend, frames)
            finally
                close_display_editor!()
            end
        end
    end
    nothing
end

# Wait until the editor of `session` has drawn `frames` frames and, for a
# `WorkloadBackend`, has given every event and drawn once after the last.
function _wait_for_workload(session::_EditorSession, backend::Backend, frames::Int)
    deadline = time() + 300
    while time() < deadline && _is_session_alive(session)
        drawn = get_frame_count(session.editor.frame_measurements) >= frames
        given = !(backend isa WorkloadBackend) ||
                (isempty(backend.events) && backend.writes > backend.writes_at_last_event)
        drawn && given && return nothing
        sleep(0.01)
    end
    nothing
end
