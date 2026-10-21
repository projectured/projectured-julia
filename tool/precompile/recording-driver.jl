# The run that `ProjecturedREPL.record_precompile_statements` traces.
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

using ProjecturedREPL
using ProjecturedAll
using ProjecturedExample
using ProjecturedSDL: SdlBackend
using ProjecturedKernelExample: ScriptedLlm, make_scripted_turn, make_scripted_think,
    make_scripted_say, make_scripted_run

using ProjecturedAll.EditorModule: Editor, run_evaluate_stage!, run_print_stage!
using ProjecturedAll.BackendModule: initialize_backend!, quit_backend!, configure_devices!
using ProjecturedAll.DeviceModule: Device, Display, Keyboard, Mouse
using ProjecturedAll.ClockModule: set_clock_time!
using ProjecturedAll.EventModule: WindowInput, MouseMove, MouseScroll,
    KeyDown, KeyPress, ModifierKeys
using ProjecturedAll.GestureModule: MouseClick
using ProjecturedAll.IntentModule: Intent
using ProjecturedAll.ProjectionModule: read_intent
using ProjecturedAll.OperationModule: Operation

const WIDTH, HEIGHT = 1600, 1000

# The workload a `:live` build runs, so that everything it compiles is in the
# recording too. A recording is only allowed to replace it if it is a superset.
ProjecturedExample.precompile_workload()

# The warm-up a binary runs: the application window, and a tab made with the
# Insert key. The examples below never type into a name buffer, and its first
# key compiles a method for every document type that the buffer can make.
ProjecturedAll.warm_application()

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
    editor = Editor(screen, composed; backend = backend, devices = devices)
    set_clock_time!(editor.clock, time() - t0)
    run_print_stage!(editor)
    for event in GESTURES
        set_clock_time!(editor.clock, time() - t0)
        change = read_intent(editor.projection, nothing,
                             Intent(WindowInput(:example, event), nothing), editor.iomap)
        operation = change isa Intent ? change.operation : change
        editor.operation = operation isa Operation ? operation : nothing
        run_evaluate_stage!(editor)
        run_print_stage!(editor)
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

# A turn of the assistant in the window of the application, in the real loop of
# the editor, as a person starts one: a scripted model streams a thought, a text
# and a call of the code tool, and after its result a second text with Markdown and
# a block of code. So the recording holds the stream of an answer: the queue of the
# turn, the append of each delta, the parse at the end of a block, and a tool call
# in a code unit with held frames.
function drive_assistant_turn!()
    llm = ScriptedLlm([
        make_scripted_turn(make_scripted_think("I add two numbers."; delay = 0.01),
                           make_scripted_say("The sum of one and one\nis simple."; delay = 0.01),
                           make_scripted_run("1 + 1"); stop_reason = "tool_use"),
        make_scripted_turn(make_scripted_say("It is **2**.\n\n```julia\n1 + 1\n```\n"; delay = 0.01))])
    assistant = make_application_assistant(:anthropic; llm)
    settings = make_settings()
    root = mktempdir()
    document = make_application_document(String[]; root, assistant, settings)
    editor = build_editor(document, make_application_projection(); backend = SdlBackend(), settings,
                          window = (; title = "ProjecturEd", width = WIDTH, height = HEIGHT,
                                    opened_window_projections = make_opened_window_projections()),
                          fault_policy = FaultPolicy(),
                          make_application_wrappers(; root, assistant, document)...)
    start_application!(editor)
    assistant.input.value = "Add one and one."
    post_operation!(editor, SubmitProseOperation(assistant))
    # The loop runs on this task; a task of its own ends it when the turn ends.
    ender = @async try
        timedwait(() -> assistant.status === :streaming, 30.0; pollint = 0.01)
        timedwait(() -> assistant.status !== :streaming, 60.0; pollint = 0.01)
    finally
        post_operation!(editor, QuitEditorOperation())
    end
    run_editor!(editor)
    wait(ender)
    println("driver: the turn of the assistant ended, status ", assistant.status)
end

try
    drive_assistant_turn!()
catch err
    println("driver: the turn of the assistant refused — ", first(split(sprint(showerror, err), "\n")))
end
println("driver: done")
