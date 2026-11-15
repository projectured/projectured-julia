# Fragment of `ProjecturedExample` — the workload of this package: each example,
# opened in a window as the editor opens it, and sent one event of each kind.

const _EXAMPLE_WORKLOAD_WIDTH, _EXAMPLE_WORKLOAD_HEIGHT = 1600, 1000

# The pointer, the buttons, the wheel and the keys, once each. The value of a key
# is a run-time value, so one press compiles the same code as a thousand; what
# must vary is the kind of the event.
function _make_example_workload_events(time::Float64)
    Any[ProjecturedAll.EventModule.MouseMove(40, 200; time),
        ProjecturedAll.EventModule.MouseMove(400, 300; time),
        ProjecturedAll.EventModule.MouseMove(800, 500; time),
        ProjecturedAll.GestureModule.MouseClick(:left, 400, 300; time),
        ProjecturedAll.GestureModule.MouseClick(:right, 400, 300; time),
        ProjecturedAll.EventModule.MouseScroll(0, -3, 400, 300; time),
        ProjecturedAll.EventModule.MouseScroll(0, 3, 400, 300; time),
        (ProjecturedAll.EventModule.KeyDown(key, ProjecturedAll.EventModule.ModifierKeys(); time)
         for key in (:down, :up, :left, :right, :tab, :home, :end, :backspace, :delete,
                     :return))...,
        ProjecturedAll.EventModule.KeyPress('x'; time),
        ProjecturedAll.EventModule.KeyPress('1'; time)]
end

# One example, in the scene that the editor builds for it, driven the way the
# editor drives it: each event is read into an operation, evaluated and printed.
function _drive_workload_example!(example, backend, devices, start::Float64)
    screen = _build_window_scene(Any[example.document], String["example"];
                                 width = _EXAMPLE_WORKLOAD_WIDTH,
                                 height = _EXAMPLE_WORKLOAD_HEIGHT)
    editor = ProjecturedAll.EditorModule.Editor(screen, _multi_window_projection(Any[example.projection]);
                                                backend, devices)
    ProjecturedAll.ClockModule.set_clock_time!(editor.clock, time() - start)
    ProjecturedAll.EditorModule.run_print_stage!(editor)
    for event in _make_example_workload_events(start)
        ProjecturedAll.ClockModule.set_clock_time!(editor.clock, time() - start)
        intent = ProjecturedAll.IntentModule.Intent(ProjecturedAll.EventModule.WindowInput(:example, event),
                                                    nothing)
        change = ProjecturedAll.ProjectionModule.read_intent(editor.projection, nothing, intent,
                                                              editor.iomap)
        operation = change isa ProjecturedAll.IntentModule.Intent ? change.operation : change
        editor.operation = operation isa ProjecturedAll.OperationModule.Operation ? operation : nothing
        ProjecturedAll.EditorModule.run_evaluate_stage!(editor)
        ProjecturedAll.EditorModule.run_print_stage!(editor)
    end
    nothing
end

"""
    run_example_workload(; examples = ProjecturedExample.examples) -> Nothing

The workload of this package: open each example in a window of a backend with no
device, as the editor opens it, and send it the pointer, the buttons, the wheel
and the keys, one event of each kind. Each event is read, evaluated and printed,
so the readers of the examples run as well as their printers.

An example that fails does not stop the others. At the end the workload throws
an error that names each example that failed.
"""
function run_example_workload(; examples = ProjecturedExample.examples)
    backend = ProjecturedAll.DisplayModule.WorkloadBackend(; events = ProjecturedAll.EventModule.Event[])
    devices = ProjecturedAll.DeviceModule.Device[ProjecturedAll.DeviceModule.Display(),
                                                 ProjecturedAll.DeviceModule.Keyboard(),
                                                 ProjecturedAll.DeviceModule.Mouse()]
    start = time()
    failures = String[]
    for example in examples
        try
            _drive_workload_example!(example, backend, devices, start)
        catch exception
            push!(failures, string(example.name, ": ",
                                   first(split(sprint(showerror, exception), "\n"))))
        end
    end
    isempty(failures) ||
        error("The workload of ProjecturedExample failed for ", length(failures), " of ",
              length(examples), " examples:\n", join(failures, "\n"))
    nothing
end
