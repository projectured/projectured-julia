# Fragment of `DisplayModule`: the workloads of the first window, which a package
# runs in its `@compile_workload` so that its package image holds that code.

"""
    WorkloadBackend(; events = make_workload_events())

A backend with no device. It reads the whole output of each frame, as a backend
that draws reads it, so that every view of the window prints. After its first
output, it gives `events` to the window of that output, one for each read, as a
hand gives them. [`run_display_workload`](@ref) runs the editor with it where no
window opens.

It also gives the inputs that [`send_workload_inputs!`](@ref) queues, each to
the window that the input names, one in each frame, before `events`.
"""
mutable struct WorkloadBackend <: Backend
    events::Vector{Event}
    inputs::Vector{WindowInput}
    # The queue of `inputs` takes a send from the task of a workload and a take
    # from the task of the loop.
    lock::ReentrantLock
    window_id::Union{Nothing,Symbol}
    writes::Int
    writes_at_last_event::Int
end

WorkloadBackend(; events::Vector{Event} = make_workload_events()) =
    WorkloadBackend(events, WindowInput[], ReentrantLock(), nothing, 0, 0)

"""
    send_workload_inputs!(backend, inputs::Vector{WindowInput}) -> Nothing

Give `inputs` to the editor of `backend`, in their order, as the devices of the
backend give them. A workload calls it from its own task, outside each frame and
each call on the editor, as a hand gives its input from outside the program.
"""
function send_workload_inputs! end

function send_workload_inputs!(backend::WorkloadBackend, inputs::Vector{WindowInput})
    lock(() -> append!(backend.inputs, inputs), backend.lock)
    nothing
end

"""
    has_workload_inputs(backend) -> Bool

Whether `backend` holds inputs that it did not give to its editor yet.
"""
function has_workload_inputs end

has_workload_inputs(backend::WorkloadBackend) =
    lock(() -> !isempty(backend.inputs) || !isempty(backend.events), backend.lock)

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
# It shows no window, so a code unit runs on the thread of the loop.
shows_held_frames(::WorkloadBackend) = false

take_from_devices!(backend::WorkloadBackend, devices) =
    lock(() -> _take_workload_input!(backend), backend.lock)

function _take_workload_input!(backend::WorkloadBackend)
    if !isempty(backend.inputs)
        # A hand gives one input in a frame, so the frame of each input prints
        # before the next input arrives.
        backend.writes_at_last_event == backend.writes && return nothing
        backend.writes_at_last_event = backend.writes
        input = popfirst!(backend.inputs)
        return WindowInput(input.window_id, _stamp_event(input.event, time()))
    end
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
    make_workload_table(rows::Int = 1000) -> WidgetTable

A table of `rows` rows of a number and its square, whose rows come from a lazy
list, as the rows of a large table do: a window shows a few of them. A list of
rows needs a width for each column. A workload shows it, so that its image holds
the code that draws such a table.
"""
make_workload_table(rows::Int = 1000) =
    WidgetTable(; column_headers = Any[WidgetLabel("n"), WidgetLabel("square")],
                column_policy = Fixed(80),
                cells = make_index_list(rows, 1, k -> CellVector(Cell[Cell(WidgetLabel(string(k))),
                                                                       Cell(WidgetLabel(string(k * k)))])))

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

"""
    run_natural_rows_workload(domain::Module) -> Nothing

Build the natural table of the first window of the display with the rows that
`domain` registers. The entry file of a package whose slice registers natural
rows calls it in its `@compile_workload`, so that its package image holds the
code of its rows, which every first window builds. A domain registers its rows
in its `__init__`, which runs when the package loads, after its workload, so
the workload runs it first ([`run_module_initializers!`](@ref)).
"""
function run_natural_rows_workload(domain::Module)
    run_module_initializers!(domain)
    NaturalToGraphics(; measure = FontFileMeasure(), appearance = Appearance())
    nothing
end

"""
    run_module_initializers!(root::Module) -> Nothing

Run the `__init__` of each module that `root` defines, at any depth, and then
the `__init__` of `root`. Julia runs them when a package loads, after its
`@compile_workload`, so a workload that needs what they register, such as the
rows of a view, runs them first. A slice registers by a key, so a second run
replaces what the first registered.
"""
function run_module_initializers!(root::Module)
    for name in names(root; all = true)
        isdefined(root, name) || continue
        value = getfield(root, name)
        (value isa Module && value !== root && parentmodule(value) === root) &&
            run_module_initializers!(value)
    end
    isdefined(root, :__init__) && parentmodule(getfield(root, :__init__)) === root &&
        Base.invokelatest(getfield(root, :__init__))
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

"""
    make_workload_file(type::Type) -> NamedTuple

The file that a workload opens for the documents of `type`: `(; name, text,
shown)`, the name of the file with its extension, its text, and a text that the
window draws when it shows the file, a `String` for a whole drawn text or a
`Regex` for a part of one. A domain adds a method for the type of its files, or,
for a domain with no file of its own, for a type of its documents, whose `.pred`
file the text is. `run_file_workload` of the application opens it.
"""
function make_workload_file end

"""
    collect_workload_file_types() -> Vector{Type}

Each type that has a method of [`make_workload_file`](@ref) in this session, in
the order of the names of the types. A workload that opens the file of every
format of a session, such as the workload of a binary, opens these.
"""
collect_workload_file_types() =
    sort!(Type[method.sig.parameters[2].parameters[1] for method in methods(make_workload_file)];
          by = string)
