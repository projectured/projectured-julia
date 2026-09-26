# tool/video/record_assistant_window.jl
#
# Run it as: julia --project=environment/all tool/video/record_assistant_window.jl [<output>.mp4]
#
# Screenplay S2: the assistant edits a file and arranges the window. The model is
# the real qwen3.8:27b through Ollama, on the GPU of this machine, with a seed. The
# person's side is scripted: a prompt, the assistant adds Frank to people.json,
# the person scrolls to him, clicks in the file and presses Ctrl+Z, then a second
# prompt, and the assistant opens a tab with a table. The session's gesture log is
# in a pane below the file. A warm-up with a scripted model runs the same steps
# first, so the take does not fire its entries in a burst after a slow start.

using Projectured, ProjecturedExample, ProjecturedKernelExample, ProjecturedOllama,
      ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "assistant_window.mp4") : ARGS[1]
const COMPOSER = (1000, 518)          # read off a frame of the window
const FILE = (300, 120)               # a point on the text of people.json
const FILE_MIDDLE = (500, 300)        # where the wheel scrolls the file
const TURN_CAP = 600.0                # seconds a turn may take before the take goes on

const PEOPLE = """
[{"name": "Cleo", "age": 29, "city": "Lyon"}, {"name": "Ada", "age": 36, "city": "London"},
 {"name": "Bob", "age": 41, "city": "Oslo"}, {"name": "Eve", "age": 25, "city": "Rome"},
 {"name": "Dan", "age": 33, "city": "Madrid"}]"""

const PROMPTS = ["Add Frank, 30, from Paris to people.json.",
                 "Open a second tab beside the first one with a table of the people in people.json, sorted by name."]

_key(key; hold = 0.35, kwargs...) =
    (event = KeyDown(key, ModifierKeys(; kwargs...); time = time()), hold = hold)
_click(x, y; hold = 0.8) = (event = MousePress(:left, x, y, ModifierKeys(); time = time()), hold = hold)
# A move of the pointer, which changes nothing, and gives the viewer time to read.
_look(x, y; hold) = (event = MouseMove(x, y, MouseButtons(), ModifierKeys(); time = time()), hold = hold)
_scroll(x, y; hold) = (event = MouseScroll(0, -10, x, y; time = time()), hold = hold)

_find_assistant(editor) =
    let found = search_documents(editor.document, node -> node isa Assistant)
        isempty(found) ? nothing : found[1]
    end

# True when the conversation holds `turns` turns and the assistant is idle again,
# which is what the end of a real turn looks like.
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
    log = get_session_gesture_log()
    clear_gesture_log!(log)
    log.count = 0
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
                                                          tab = PaneTab("Gestures", log)))
    split, _ = get_pane_parent(tree, group)
    split.weights = [0.8, 0.2]
    apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    selected === nothing ||
        set_selection!(document, annotate_reference_types(document,
                                    first(search_references(document, node -> node === selected))))
    nothing
end

# The steps of the take. `typing` types as a person does, or fast for the warm-up.
function make_timeline(; typing, read, cap)
    [_click(COMPOSER...; hold = 1.0),
     make_typein_gestures(PROMPTS[1]; typing...)...,
     _key(:return; hold = 1.0),
     (await = turn_finished(3), hold = cap),
     _look(FILE_MIDDLE...; hold = read),
     _scroll(FILE_MIDDLE...; hold = read),
     _click(FILE...; hold = 1.0),
     _key(:z; ctrl = true, hold = read),
     _click(COMPOSER...; hold = 1.0),
     make_typein_gestures(PROMPTS[2]; typing...)...,
     _key(:return; hold = 1.0),
     (await = turn_finished(5), hold = cap)]
end

# A scripted model that makes the two calls of the rehearsal at once, for the
# warm-up.
function make_warm_up_llm()
    insert = """
    people_tab_1 = find_pane(editor, "people.json")
    people_1 = get_edited_document(people_tab_1)
    frank_1 = JsonObject("name" => JsonString("Frank"), "age" => JsonNumber(30), "city" => JsonString("Paris"))
    insert_elements!(editor, people_1, length(people_1) + 1, [frank_1])
    """
    table = """
    rows_1 = sort([[person["name"].value, person["age"].value, person["city"].value] for person in people_1]; by = first)
    open_pane!(editor, WidgetTable(["name", "age", "city"], rows_1); title = "People by name",
               target = get_parent(editor, people_tab_1))
    """
    ScriptedLlm([
        make_scripted_turn(make_scripted_run(insert; tool_id = "tu_1", delay = 0.0); stop_reason = "tool_use"),
        make_scripted_turn(make_scripted_say("Done."; delay = 0.0)),
        make_scripted_turn(make_scripted_run(table; tool_id = "tu_2", delay = 0.0); stop_reason = "tool_use"),
        make_scripted_turn(make_scripted_say("Done."; delay = 0.0)),
    ]; delay = 0.0)
end

function record(output, llm, timeline; initial_hold, final_hold)
    directory = mktempdir()
    write(joinpath(directory, "people.json"), PEOPLE)
    record_application_video([joinpath(directory, "people.json")], timeline, output;
                             width = 1280, height = 720, fps = 30,
                             assistant = :ollama, llm = llm, root = directory,
                             initial_hold = initial_hold, final_hold = final_hold,
                             prepare = prepare_window!)
end

function main()
    warm_up = joinpath(dirname(OUTPUT), "assistant_window_warm_up.mp4")
    started = time()
    record(warm_up, make_warm_up_llm(),
           make_timeline(; typing = (hold = 0.01, jitter = 0.0), read = 0.2, cap = 60.0);
           initial_hold = 0.5, final_hold = 0.5)
    rm(warm_up; force = true)
    println("warm-up: ", round(time() - started; digits = 1), " s")
    started = time()
    path = record(OUTPUT, OllamaLlm(context = 32768, seed = 1),
                  make_timeline(; typing = (hold = 0.15, jitter = 0.6), read = 3.0, cap = TURN_CAP);
                  initial_hold = 2.0, final_hold = 5.0)
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
