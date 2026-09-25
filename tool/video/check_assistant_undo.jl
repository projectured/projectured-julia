# tool/video/check_assistant_undo.jl
#
# Run it as: julia --project=environment/all tool/video/check_assistant_undo.jl [<output>.mp4]
#
# The check of beat 4 of screenplay S2: does Ctrl+Z take back a change that the
# assistant made to the window? A scripted model stands in for the real one and
# makes the tool call that S2 needs, a card with a table in a tab of its own, so
# the check needs no model and no free memory for one. The take prints the number
# of tabs after the turn and after each Ctrl+Z.

using Projectured, ProjecturedExample, ProjecturedKernelExample, ProjecturedSdl,
      ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "assistant_undo.mp4") : ARGS[1]
const COMPOSER = (1000, 518)          # read off a frame of the window

const CODE = """
open_pane!(editor, WidgetCard(content = WidgetTable(["name", "age"],
    [["Cleo", "29"], ["Ada", "36"], ["Bob", "41"]])); title = "People")
"""

_key(key; hold = 0.35, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)

_find_assistant(editor) =
    let found = search_documents(editor.document, node -> node isa Assistant)
        isempty(found) ? nothing : found[1]
    end

_text(value) = value isa Cell ? _text(value[]) : hasproperty(value, :value) ? string(value.value) : string(value)

# The tabs of the window's pane tree. A search from the root of the document would
# also find the tabs that the undo buffer holds for a redo.
function _get_tab_titles(editor)
    buffer = only(search_documents(editor.document, node -> node isa UndoBuffer && node.content isa PaneTree))
    [_text(tab.title) for tab in search_documents(buffer.content, node -> node isa PaneTab)]
end

function turn_finished(turns::Integer)
    editor -> begin
        assistant = _find_assistant(editor)
        assistant === nothing && return false
        length(assistant.conversation.turns) >= turns && assistant.status === :idle
    end
end

# An entry that prints what the window holds now and lets the take go on: the
# title of each tab, and the size and the newest step of each undo buffer.
function say(label)
    editor -> begin
        assistant = _find_assistant(editor)
        turns = assistant === nothing ? 0 : length(assistant.conversation.turns)
        println(rpad(label, 22), "tabs ", _get_tab_titles(editor), ", turns ", turns)
        for buffer in search_documents(editor.document, node -> node isa UndoBuffer)
            entries = buffer.undo_entries
            newest = isempty(entries) ? "-" : first(entries[end].label, 90)
            println("    buffer over ", nameof(typeof(buffer.content)), ": ", length(entries), " steps, newest: ", newest)
        end
        true
    end
end

function make_timeline()
    [(event = MousePress(:left, COMPOSER[1], COMPOSER[2], ModifierKeys()), hold = 1.0),
     (await = say("before the prompt"), hold = 1.0),
     make_typein_gestures("Show the people as a table in a tab."; hold = 0.02, jitter = 0.0)...,
     _key(:return; hold = 1.0),
     (await = turn_finished(3), hold = 60.0),
     (await = say("after the turn"), hold = 1.5),
     _key(:z; ctrl = true, hold = 1.5),
     (await = say("after one Ctrl+Z"), hold = 1.5),
     _key(:z; ctrl = true, hold = 1.5),
     (await = say("after two Ctrl+Z"), hold = 1.5)]
end

function main()
    directory = mktempdir()
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}, {\"name\": \"Bob\", \"age\": 41}]")
    llm = ScriptedLlm([
        make_scripted_turn(make_scripted_say("I open a tab with a table."; delay = 0.0),
                           make_scripted_run(CODE; tool_id = "tu_people", delay = 0.0);
                           stop_reason = "tool_use"),
        make_scripted_turn(make_scripted_say("The table is in the tab People."; delay = 0.0)),
    ]; delay = 0.0)
    path = record_application_video([joinpath(directory, "people.json")], make_timeline(), OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :ollama, llm = llm, root = directory,
                                    initial_hold = 1.0, final_hold = 1.0)
    println("recorded: ", path)
end

main()
