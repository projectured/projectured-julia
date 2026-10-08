# Fragment of `DisplayModule`: the workload of the first window, which a package
# runs in its `@compile_workload` so that its package image holds that code.

"""
    WorkloadBackend()

A backend with no device. It takes no input, and it reads the whole output of
each frame, as a backend that draws reads it, so that every view of the window
prints. [`run_display_workload`](@ref) runs the editor with it where no window
opens.
"""
struct WorkloadBackend <: Backend end

initialize_backend!(::WorkloadBackend) = nothing
quit_backend!(::WorkloadBackend) = nothing
take_from_devices!(::WorkloadBackend, devices) = nothing

function write_to_devices!(::WorkloadBackend, devices, screen::ScreenDocument)
    for window in screen.windows
        _read_graphics(window.content)
    end
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

Show `value` as the first [`display_in_editor`](@ref) of a session shows it,
with `backend`, until the editor has drawn `frames` frames, then stop the
editor. A `Document` is shown as it is, another value through
`make_value_document`. A package calls it in its `@compile_workload`, so that
its package image holds the code of the first window. The session of
`display_in_editor` stays as it is.
"""
function run_display_workload(value; backend::Backend = WorkloadBackend(), frames::Int = 1)
    document = value isa Document ? value : make_value_document(value)
    session = _start_session(document, summary(value); backend, tabs = true, refresh_every = nothing)
    try
        deadline = time() + 300
        while get_frame_count(session.editor.frame_measurements) < frames
            (time() > deadline || !_is_session_alive(session)) && break
            sleep(0.01)
        end
    finally
        _close_session!(session)
    end
    nothing
end
