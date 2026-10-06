# tool/video/check_assistant_undo.jl
#
# Run it as: julia --project=environment/all tool/video/check_assistant_undo.jl [<output>.mp4]
#
# The check of beats 2 and 3 of screenplay S2: the assistant adds a person to
# people.json, the person clicks in the tab of the file and presses Ctrl+Z, and
# the person is gone. A scripted model stands in for the real one and runs the
# code that qwen wrote in the rehearsal, so the check needs no model and no free
# memory for one. The session's gesture log is in a pane below the file, and the
# take prints the people, the steps of each history and the lines of the log
# after each beat.

using ProjecturedAll, ProjecturedExample, ProjecturedKernelExample, ProjecturedSDL,
      ProjecturedSDLExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "assistant_undo.mp4") : ARGS[1]
# The window is drawn 15% smaller than its logical size, so a video of 1280×720
# holds a logical window of 1506×847: more room for the code in the conversation.
const WIDTH, HEIGHT, DENSITY = 1506, 847, 0.85
const COMPOSER = (1059, 642)          # read off a frame of the window, in logical pixels
const FILE = (118, 129)               # a point on the text of people.json
const FILE_DOWN = (353, 353)          # where the wheel scrolls the file

const PEOPLE = """
[{"name": "Cleo", "age": 29, "city": "Lyon"}, {"name": "Ada", "age": 36, "city": "London"},
 {"name": "Bob", "age": 41, "city": "Oslo"}, {"name": "Eve", "age": 25, "city": "Rome"},
 {"name": "Dan", "age": 33, "city": "Madrid"}]"""

const CODE = """
people_tab_1 = find_pane("people.json")
people_1 = get_edited_document(people_tab_1)
frank_1 = JsonObject("name" => JsonString("Frank"), "age" => JsonNumber(30), "city" => JsonString("Paris"))
insert_elements!(people_1, length(people_1) + 1, [frank_1])
"""

_key(key; hold = 0.35, kwargs...) =
    (event = KeyDown(key, ModifierKeys(; kwargs...); time = time()), hold = hold)
_click(x, y; hold = 0.8) = (event = MouseClick(:left, x, y, ModifierKeys(); time = time()), hold = hold)

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

# The window of the take: the Files tab closed, so the file and the assistant have
# its room, and the session's gesture log in a pane below the file, with 20% of the
# height, with the focus back on the file.
function prepare_window!(document)
    # The selection is a path through the tree, so it is set again after the split
    # moves the group of the file one level down.
    selected = try_evaluate_reference(document, get_selection(document), nothing)
    tree = only(search_documents(document, node -> node isa PaneTree))
    files = only(g for g in get_pane_groups(tree)
                 if any(tab -> get_pane_tab_title_string(tab) == "Files", g.tabs))
    apply_pane_operation!(tree, make_pane_close_tab_operation(tree, files, 1))
    group = only(g for g in get_pane_groups(tree)
                 if any(tab -> get_pane_tab_title_string(tab) == "people.json", g.tabs))
    apply_pane_operation!(tree, make_pane_split_operation(tree, group; orientation = :horizontal,
                                                          side = :below,
                                                          tab = PaneTab("Gestures", get_session_gesture_log())))
    split, _ = get_pane_parent(tree, group)
    split.weights = [0.8, 0.2]
    tree.root.weights = [0.55, 0.45]      # the assistant a little wider, for its code
    apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    selected === nothing ||
        set_selection!(document, annotate_reference_types(document,
                                    first(search_references(document, node -> node === selected))))
    nothing
end

# An entry that prints what the window holds now and lets the take go on.
function say(label)
    editor -> begin
        tab = get_document(find_pane("people.json"; editor))
        people = get_edited_document(tab)
        window = only(search_documents(editor.document, node -> node isa UndoBuffer && node.content isa PaneTree))
        println(rpad(label, 24), "people ", [person["name"].value for person in people],
                "; steps (window, file) ", (length(window.undo_entries), length(tab.content.content.content.undo_entries)))
        for entry in get_session_gesture_log().entries
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
     (event = MouseScroll(0, -10, FILE_DOWN...; time = time()), hold = 1.5),
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
                                    width = WIDTH, height = HEIGHT, density = DENSITY, fps = 30,
                                    assistant = :ollama, llm = llm, root = directory,
                                    initial_hold = 1.0, final_hold = 1.0,
                                    prepare = prepare_window!)
    println("recorded: ", path)
end

main()
