# tool/video/record_json_from_nothing.jl
#
# Run it as: julia --project=environment/all tool/video/record_json_from_nothing.jl [<output>.mp4] [--gestures]
#
# Screenplay S3: JSON from nothing.
# The build moves the caret alone and never selects structure: `Right` leaves a
# string, a `,` after a value adds the next entry or element, and `Down`
# carries the caret to the end of the line of the closing `}` or `]` of a
# nested container, where the `,` belongs to the outer object.
# The script first replays the timeline headless. It records only when every
# key produced an operation.
# With `--gestures`, a panel in a corner shows each key and the operation it made.
# With `--check`, the script stops after the replay.

using ProjecturedAll, ProjecturedExample, ProjecturedSDL, ProjecturedSDLExample, ProjecturedVideo

const GESTURES = "--gestures" in ARGS
const PATHS = filter(argument -> !startswith(argument, "--"), ARGS)
const OUTPUT = isempty(PATHS) ? joinpath(pwd(), "json_from_nothing.mp4") : PATHS[1]
const GESTURE_LINES = 8     # the lines the panel shows
# The panel needs room beside the JSON, so a take with it is wider. The panel
# font is monospaced: 60 characters of an operation keep the panel right of the
# widest line of the JSON.
const OPERATION_WIDTH = 60
const WIDTH, HEIGHT, FPS = (GESTURES ? 1280 : 900), 720, 30

_key(key; hold = 0.35, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...);
                                                     time = time()), hold = hold)
_press(character; hold = 0.4) = (event = KeyPress(character; time = time()), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)   # the human rhythm, D13
_right(; hold = 0.3) = _key(:right; hold = hold)                     # leave a string
# From the last value of a nested container: the next line holds only the
# closing `}` or `]`, so Down puts the caret at its end, after the brace.
_leave_container() = [_key(:down; hold = 0.4)]

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

# The panel of gestures. The recorder at the root writes each key and the
# operation it made into the log, and the overlay draws the log in a corner. A
# selection is kept, and drawn muted, so the presses of Right that carry the
# caret out of a container show too.
_shows_in_overlay(gesture, operation) = !(operation === nothing || operation isa DoNothingOperation)

# The panel measures its text from the font files, where SDL draws each glyph,
# so a long line fits the panel. The check draws nothing and needs no SDL.
function _with_gesture_overlay(projection; capacity = GESTURE_LINES, measure = FontFileMeasure())
    log = GestureLog(; capacity = capacity)
    GestureLogRecordingProjection(
        inner = GestureLogOverlayProjection(inner = projection, log = log, anchor = :bottom_right,
                    content = make_gesture_log_content_projection(; measure,
                                                                    operation_width = OPERATION_WIDTH)),
        log = log, filter = _shows_in_overlay)
end

# The take starts from an empty JSON document. Its placeholder draws `empty json`,
# and `{` on it makes the object.
make_seed() = JsonNothing()

function make_editor()
    example = only(live.example for live in live_examples if live.name == "json_build")
    document = make_seed()
    # The check keeps every line of the log, to show the longest one.
    projection = GESTURES ? _with_gesture_overlay(example.make_projection(); capacity = 1000,
                                                  measure = FontFileMeasure()) :
                            example.make_projection()
    set_selection!(document, EmptyReference())
    editor = Editor(document, projection; backend = ConsoleBackend(),
                    devices = Device[Display(), Keyboard(), Mouse()])
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
    if GESTURES
        lines = [string(entry.index, "  ", rpad(entry.gesture, 18), entry.operation)
                 for entry in projection.log.entries]
        println("gesture lines: ", length(lines), ", the longest before the cut: ", maximum(length, lines))
        foreach(println, lines[max(1, end - 11):end])
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
    "--check" in ARGS && return
    build = only(live.example for live in live_examples if live.name == "json_build")
    example = Example("json_from_nothing", make_seed,
                      GESTURES ? () -> _with_gesture_overlay(build.make_projection()) :
                                 build.make_projection)
    live = LiveExample("json_from_nothing", example, TIMELINE;
                       initial_selection = EmptyReference(),
                       width = WIDTH, height = HEIGHT, fps = FPS)
    scripted = 1.5 + sum(entry.hold for entry in TIMELINE) + 3.0
    println("scripted seconds: ", round(scripted; digits = 1))
    println("recorded: ", record_live_example(live, OUTPUT; initial_hold = 1.5, final_hold = 3.0))
end

main()
