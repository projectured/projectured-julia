# tool/video/record_assistant_window.jl
#
# Run it as: julia --project=environment/all tool/video/record_assistant_window.jl [<output>.mp4]
#
# Screenplay S2: the assistant arranges the window.
# The model is the real qwen3.8:27b through Ollama, on the CPU of this machine.
# The user side is scripted: the pointer clicks the composer, the prompt is
# typed, and the take then waits for the real turn, however long it takes.

using Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedSdlExample, ProjecturedVideo

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "assistant_window.mp4") : ARGS[1]
const COMPOSER = (1000, 518)          # read off a frame of the window
const TURN_CAP = 420.0                # seconds a turn may take before the take goes on

_key(key; hold = 0.35, kwargs...) = (event = KeyDown(key, ModifierKeys(; kwargs...)), hold = hold)
_type(text) = make_typein_gestures(text; hold = 0.15, jitter = 0.6)

_find_assistant(editor) =
    let found = search_documents(editor.document, node -> node isa Assistant)
        isempty(found) ? nothing : found[1]
    end

# True when the conversation holds `turns` turns and the assistant is idle
# again, which is what the end of a real turn looks like.
function turn_finished(turns::Integer)
    editor -> begin
        assistant = _find_assistant(editor)
        assistant === nothing && return false
        length(assistant.conversation.turns) >= turns && assistant.status === :idle
    end
end

const PROMPTS = [
    "Open people.json sorted by name in a second tab, beside the first one.",
    "Add a card with a table of the names and the ages under the tabs.",
]

function make_timeline()
    timeline = Any[(event = MousePress(:left, COMPOSER[1], COMPOSER[2], ModifierKeys()), hold = 1.0)]
    turns = 1                                        # the greeting
    for prompt in PROMPTS
        append!(timeline, _type(prompt))
        push!(timeline, _key(:return; hold = 1.0))
        turns += 2                                   # the prompt, and the answer
        push!(timeline, (await = turn_finished(turns), hold = TURN_CAP))
        push!(timeline, _key(:f1; hold = 0.1))       # a no-op key, so the wait has a beat after it
        push!(timeline, _key(:escape; hold = 2.5))
    end
    timeline
end

function main()
    directory = mktempdir()
    write(joinpath(directory, "people.json"),
          "[{\"name\": \"Cleo\", \"age\": 29}, {\"name\": \"Ada\", \"age\": 36}, {\"name\": \"Bob\", \"age\": 41}]")
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([joinpath(directory, "people.json")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30,
                                    assistant = :ollama, root = directory,
                                    initial_hold = 2.0, final_hold = 4.0)
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
