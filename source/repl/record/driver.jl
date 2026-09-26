# The run that `ProjecturedRepl.record_precompile_statements` traces.
#
# It is not run by a build. A person runs the recorder, this drives the editor
# the way a reader drives it, and Julia writes down every method instance it had
# to compile. The list is then checked in, and later builds replay it.
#
# Being outside the build is what lets this be slow and use a real window:
# nobody waits for it.
#
# Needs a display. SDL asks for an accelerated renderer, which the dummy video
# driver does not offer.

using ProjecturedRepl
using Projectured
using ProjecturedExample
using ProjecturedSdl: SdlBackend

using Projectured.EditorModule: Editor, evaluate!, print!
using Projectured.BackendModule: initialize_backend!, quit_backend!, configure_devices!
using Projectured.DeviceModule: Device, Display, Keyboard, Mouse
using Projectured.ClockModule: set_clock_time!
using Projectured.EventModule: WindowInput, MouseClick, MouseMove, MouseScroll,
    KeyDown, KeyPress, ModifierKeys
using Projectured.IntentModule: Intent
using Projectured.ProjectionModule: read_intent
using Projectured.OperationModule: Operation

const WIDTH, HEIGHT = 1600, 1000

# The workload a `:live` build runs, so that everything it compiles is in the
# recording too. A recording is only allowed to replace it if it is a superset.
ProjecturedExample.precompile_workload()

# The warm-up a binary runs: the application window, and a tab made with the
# Insert key. The examples below never type into a name buffer, and its first
# key compiles a method for every document type that the buffer can make.
ProjecturedExample.warm_application()

backend = SdlBackend()
initialize_backend!(backend)
devices = Device[Display(), Keyboard(), Mouse()]
configure_devices!(backend, devices)

t0 = time()

# The keys and the wheel, once each. A key's value is a run-time value, so one
# press compiles the same code as a thousand; what has to vary is the KIND of
# event.
const GESTURES = Any[
    MouseMove(40, 200; time = t0), MouseMove(400, 300; time = t0),
    MouseMove(800, 500; time = t0),
    MouseClick(:left, 400, 300; time = t0), MouseClick(:right, 400, 300; time = t0),
    MouseScroll(0, -3, 400, 300; time = t0), MouseScroll(0, 3, 400, 300; time = t0),
    KeyDown(:down, ModifierKeys(); time = t0), KeyDown(:up, ModifierKeys(); time = t0),
    KeyDown(:left, ModifierKeys(); time = t0), KeyDown(:right, ModifierKeys(); time = t0),
    KeyDown(:tab, ModifierKeys(); time = t0), KeyDown(:home, ModifierKeys(); time = t0),
    KeyDown(:end, ModifierKeys(); time = t0),
    KeyDown(:backspace, ModifierKeys(); time = t0),
    KeyDown(:delete, ModifierKeys(); time = t0),
    KeyDown(:return, ModifierKeys(); time = t0),
    KeyPress('x'; time = t0), KeyPress('1'; time = t0),
]

# One example, opened in the scene the editor builds and driven the way the
# editor drives it. One window id for all of them, so the backend reuses the one
# native window rather than opening a hundred.
function drive_example!(document, projection)
    screen = ProjecturedExample._build_window_scene(Any[document], String["example"];
                                                    width = WIDTH, height = HEIGHT)
    composed = ProjecturedExample._multi_window_projection(Any[projection])
    editor = Editor(backend, screen, composed, devices)
    set_clock_time!(editor.clock, time() - t0)
    print!(editor)
    for event in GESTURES
        set_clock_time!(editor.clock, time() - t0)
        change = read_intent(editor.projection, nothing,
                             Intent(WindowInput(:example, event), nothing), editor.iomap)
        operation = change isa Intent ? change.operation : change
        editor.operation = operation isa Operation ? operation : nothing
        evaluate!(editor)
        print!(editor)
    end
    nothing
end

driven = 0
refused = 0
for example in ProjecturedExample.examples
    try
        drive_example!(example.document, example.projection)
        global driven += 1
    catch err
        global refused += 1
        println("driver: ", example.name, " refused — ",
                first(split(sprint(showerror, err), "\n")))
    end
end
println("driver: drove ", driven, " examples, ", refused, " refused")

quit_backend!(backend)
println("driver: done")
