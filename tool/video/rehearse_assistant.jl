# tool/video/rehearse_assistant.jl
#
# Run it as: julia --project=environment/all tool/video/rehearse_assistant.jl ["<prompt>"]
#
# Rehearsal for S2: run one turn of the real model against the application, with
# no recording, and print what it did. The take is recorded only after a
# rehearsal that works (D9).

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const WIDTH, HEIGHT = 1280, 720
const PROMPT = length(ARGS) >= 1 ? ARGS[1] :
    "Open people.json sorted by name in a second tab, beside the first one."
const CAP = 420.0

function make_editor(directory)
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}, {\"name\": \"Bob\", \"age\": 41}]")
    assistant = make_application_assistant(:ollama)
    document, projection = make_application_window([joinpath(directory, "people.json")];
                                                   root = directory, assistant = assistant)
    scene = make_window_scene(document, "ProjecturEd"; width = WIDTH, height = HEIGHT)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections())
    editor = Editor(ConsoleBackend(), scene, composed, Device[Display(), Keyboard(), Mouse()])
    editor.iomap = print_document(composed, nothing, scene,
                                  PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                                 Dict{Symbol,Any}(), Clock()))
    declare_api!(editor.tools, make_application_api())
    register_undo_tools!(editor.tools)
    (editor, document, composed, assistant)
end

_value(v) = v isa Cell ? _value(v[]) : v
function strings_of(node, found = String[])
    node = _value(node)
    node === nothing && return found
    if hasproperty(node, :text) && _value(node.text) isa AbstractString
        push!(found, String(_value(node.text)))
    elseif hasproperty(node, :elements)
        foreach(element -> strings_of(element, found), _value(node.elements))
    elseif hasproperty(node, :content)
        strings_of(node.content, found)
    end
    found
end

# Every part of every turn, as text, so a rehearsal says what the model asked
# for and what came back.
function say_conversation(assistant)
    for (index, turn) in enumerate(assistant.conversation.turns)
        println("  turn ", index, "  role ", turn.role, "  stop ", turn.stop_reason)
        for part in turn.parts
            content = part.content
            text = try
                print_natural_text(content)
            catch
                strip(join(strings_of(content), " "))
            end
            text = strip(string(text))
            label = string(nameof(typeof(content)))
            if content isa EvaluatorForm
                code = try strip(print_natural_text(content.form)) catch; "(no text)" end
                answer = try strip(print_natural_text(content.result)) catch; "(no text)" end
                println("    ", rpad(content.tool_name, 26), content.is_error ? "ERROR " : "", first(code, 260))
                println("      -> ", first(replace(answer, "\n" => " ⏎ "), 260))
            else
                println("    ", rpad(label, 26), isempty(text) ? repr(content)[1:min(end, 160)] : first(text, 300))
            end
        end
    end
end

function main()
    directory = mktempdir()
    editor, document, composed, assistant = make_editor(directory)
    tabs_before = length(search_documents(document, node -> node isa PaneTab))
    println("the prompt: ", PROMPT)
    println("tabs before: ", tabs_before)

    assistant.input = PrimitiveString(PROMPT)
    started = time()
    evaluate_operation(editor, SubmitProseOperation(assistant))
    while assistant.status !== :idle && time() - started < CAP
        sleep(0.5)
        yield()
    end
    seconds = round(time() - started; digits = 1)
    tabs_after = length(search_documents(document, node -> node isa PaneTab))
    println("the turn took ", seconds, " s, status ", assistant.status)
    println("tabs after: ", tabs_after, tabs_after > tabs_before ? "  (a tab opened)" : "  (no new tab)")
    println("the conversation:")
    say_conversation(assistant)
end

main()
