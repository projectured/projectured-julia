# tool/video/check_assistant_undo.jl
#
# Run it as: julia --project=environment/all tool/video/check_assistant_undo.jl [<output>.mp4]
#
# The check of beats 2 and 3 of screenplay S2: the assistant adds a person to
# people.json, the person clicks in the tab of the file and presses Ctrl+Z, and
# the person is gone. A scripted model stands in for the real one and runs the
# code that qwen wrote in the rehearsal, so the check needs no model and no free
# memory for one. The take draws the panel of the gesture and operation log at
# the bottom left, and prints the people, the steps of each history and the lines
# of the log after each beat.

using Projectured, ProjecturedExample, ProjecturedKernelExample, ProjecturedSdl,
      ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "assistant_undo.mp4") : ARGS[1]
const COMPOSER = (1000, 518)          # read off a frame of the window
const FILE = (300, 120)               # a point on the text of people.json
const OPERATION_WIDTH = 60            # the characters of an operation in the panel

const PEOPLE = """
[{"name": "Cleo", "age": 29, "city": "Lyon"}, {"name": "Ada", "age": 36, "city": "London"},
 {"name": "Bob", "age": 41, "city": "Oslo"}, {"name": "Eve", "age": 25, "city": "Rome"},
 {"name": "Dan", "age": 33, "city": "Madrid"}]"""

const CODE = """
people_tab_1 = find_pane(editor, "people.json")
people_1 = get_edited_document(people_tab_1)
frank_1 = JsonObject("name" => JsonString("Frank"), "age" => JsonNumber(30), "city" => JsonString("Paris"))
insert_elements!(editor, people_1, length(people_1) + 1, [frank_1])
"""

_key(key; hold = 0.35, kwargs...) =
    (event = KeyDown(key, ModifierKeys(; kwargs...); time = time()), hold = hold)
_click(x, y; hold = 0.8) = (event = MousePress(:left, x, y, ModifierKeys(); time = time()), hold = hold)

_find_assistant(editor) =
    let found = search_documents(editor.document, node -> node isa Assistant)
        isempty(found) ? nothing : found[1]
    end

function turn_finished(turns::Integer)
    editor -> begin
        assistant = _find_assistant(editor)
        assistant === nothing && return false
        length(assistant.conversation.turns) >= turns && assistant.status === :idle
    end
end

# The panel of the log. The recorder at the root writes each key with the operation
# it made, and each operation of a verb with its description; the overlay draws
# the newest lines at the bottom left, over the lower part of the navigator.
const LOG = Ref{Any}(nothing)
_shows_in_overlay(gesture, operation) = !(operation === nothing || operation isa DoNothingOperation)
function _with_gesture_overlay(projection)
    log = GestureLog(; capacity = 8)
    LOG[] = log
    GestureLogRecordingProjection(
        inner = GestureLogOverlayProjection(inner = projection, log = log, anchor = :bottom_left,
                    content = make_gesture_log_content_projection(; measure = FontFileMeasure(),
                                                                    operation_width = OPERATION_WIDTH)),
        log = log, filter = _shows_in_overlay, fold_typing = true)
end

# An entry that prints what the window holds now and lets the take go on.
function say(label)
    editor -> begin
        tab = get_document(find_pane(editor, "people.json"))
        people = get_edited_document(tab)
        window = only(search_documents(editor.document, node -> node isa UndoBuffer && node.content isa PaneTree))
        println(rpad(label, 24), "people ", [person["name"].value for person in people],
                "; steps (window, file) ", (length(window.undo_entries), length(tab.content.content.undo_entries)))
        LOG[] === nothing || for entry in LOG[].entries
            println("    log: ", entry)
        end
        true
    end
end

function make_timeline()
    [_click(COMPOSER...; hold = 1.0),
     (await = say("before the prompt"), hold = 1.0),
     make_typein_gestures("Add Frank, 30, from Paris to people.json."; hold = 0.02, jitter = 0.0)...,
     _key(:return; hold = 1.0),
     (await = turn_finished(3), hold = 60.0),
     (await = say("after the turn"), hold = 1.5),
     _click(FILE...; hold = 1.0),
     _key(:z; ctrl = true, hold = 1.5),
     (await = say("after Ctrl+Z in the file"), hold = 1.5)]
end

function main()
    directory = mktempdir()
    write(joinpath(directory, "people.json"), PEOPLE)
    llm = ScriptedLlm([
        make_scripted_turn(make_scripted_say("I add Frank to people.json."; delay = 0.0),
                           make_scripted_run(CODE; tool_id = "tu_frank", delay = 0.0);
                           stop_reason = "tool_use"),
        make_scripted_turn(make_scripted_say("Frank, 30, from Paris is the last person."; delay = 0.0)),
    ]; delay = 0.0)
    path = record_application_video([joinpath(directory, "people.json")], make_timeline(), OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :ollama, llm = llm, root = directory,
                                    initial_hold = 1.0, final_hold = 1.0,
                                    wrap_projection = _with_gesture_overlay)
    println("recorded: ", path)
end

main()
