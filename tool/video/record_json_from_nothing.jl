# tool/video/record_json_from_nothing.jl
#
# Run it as: julia --project=environment/all tool/video/record_json_from_nothing.jl [<output>.mp4]
#
# Screenplay S3: JSON from nothing.
# The build moves the caret alone and never selects structure: `Right` leaves a
# string, a `,` after a value adds the next entry or element, and presses of
# `Right` carry the caret past the closing `}` or `]` of a nested container, where
# the `,` belongs to the outer object.
# The script first replays the timeline headless. It records only when every
# key produced an operation.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "json_from_nothing.mp4") : ARGS[1]
const WIDTH, HEIGHT, FPS = 900, 720, 30

_key(key; hold = 0.35, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_press(character; hold = 0.4) = (event = KeyPress(character), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)   # the human rhythm, D13
_right(; hold = 0.3) = _key(:right; hold = hold)                     # leave a string
# From inside the last string of a nested container: past the closing quote, the
# indentation of the next line and the closing `}` or `]`.
_leave_container() = [_right(; hold = 0.22) for _ in 1:5]

_entry_text(key, value) = vcat(_type(key), [_key(:tab)], [_press('"')], _type(value))
_entry_number(key, value) = vcat(_type(key), [_key(:tab)], _type(value))
_element_text(value) = vcat([_press('"')], _type(value))

const TIMELINE = vcat(
    [_press('{'; hold = 1.2)],
    _entry_text("name", "Alice"),        [_right(), _press(',')],
    _entry_number("age", "30"),          [_press(',')],                  # a number takes the `,`
    _entry_text("city", "Wonderland"),   [_right(), _press(',')],
    _type("address"), [_key(:tab), _press('{'; hold = 0.8)],
        _entry_text("street", "12 Rabbit Lane"), [_right(), _press(',')],
        _entry_text("zip", "12345"),
    _leave_container(), [_press(',')],
    _type("tags"), [_key(:tab), _press('['; hold = 0.8)],
        _element_text("admin"), [_right(), _press(',')],
        _element_text("editor"),
    _leave_container(), [_press(',')],
    _type("active"), [_key(:tab), _press('t'; hold = 2.5)],
)

function make_editor()
    example = only(live.example for live in live_examples if live.name == "json_build")
    document = example.make_document()
    projection = example.make_projection()
    set_selection!(document, EmptyReference())
    editor = Editor(ConsoleBackend(), document, projection, Device[Display(), Keyboard(), Mouse()])
    editor.iomap = print_document(projection, nothing, document,
                                  PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                                 Dict{Symbol,Any}(), Clock()))
    (editor, projection, example)
end

# Replay without rendering, and answer how many keys did nothing and what the
# document holds.
function check()
    editor, projection, _ = make_editor()
    dead = 0
    for entry in TIMELINE
        change = read_intent(projection, nothing, Intent(entry.event, nothing), editor.iomap)
        operation = change isa Intent ? change.operation : change
        if operation isa Operation
            evaluate_operation(editor, operation)
            editor.iomap = print_document(projection, nothing, editor.document,
                                          PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                                         Dict{Symbol,Any}(), Clock()))
        else
            dead += 1
        end
    end
    (dead, print_natural_text(editor.document))
end

function main()
    dead, text = check()
    println("keys that did nothing: ", dead, " of ", length(TIMELINE))
    println(text)
    if dead > 0
        println("NOT RECORDED: a key did nothing.")
        return
    end
    example = only(live.example for live in live_examples if live.name == "json_build")
    live = LiveExample("json_from_nothing", example, TIMELINE;
                       initial_selection = EmptyReference(),
                       width = WIDTH, height = HEIGHT, fps = FPS)
    scripted = 1.5 + sum(entry.hold for entry in TIMELINE) + 3.0
    println("scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", record_live_example(live, OUTPUT; initial_hold = 1.5, final_hold = 3.0))
end

main()
