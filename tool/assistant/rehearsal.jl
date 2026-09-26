# tool/assistant/rehearsal.jl
#
# Include it in a command of the warm session (`warm_session.jl`), then:
#
#     Rehearsal.run_s2_rehearsals(1:5; directory = "/var/tmp/s2/loop/out/baseline")
#
# The rehearsal of screenplay S2 with the real model and no video. The window of
# the application is built headless, with the layout of the take, and the side
# of the person is done by operations: the first prompt is submitted, the
# history of people.json takes one undo, the second prompt is submitted. After
# each step a check says whether the step did what the screenplay needs. The
# model is watched before each of its rounds, and a run stops at the first
# watch that fails, so a run that goes wrong costs seconds, not minutes.

module Rehearsal

using Projectured, ProjecturedExample, ProjecturedKernelExample, ProjecturedOllama,
      ProjecturedSdl, ProjecturedSdlExample
using Dates

const LlmModule = Projectured.LlmModule

const WIDTH, HEIGHT = 1506, 847

const PEOPLE = """
[{"name": "Cleo", "age": 29, "city": "Lyon"}, {"name": "Ada", "age": 36, "city": "London"},
 {"name": "Bob", "age": 41, "city": "Oslo"}, {"name": "Eve", "age": 25, "city": "Rome"},
 {"name": "Dan", "age": 33, "city": "Madrid"}]"""

const NAMES = ["Cleo", "Ada", "Bob", "Eve", "Dan"]

const PROMPTS = ["Add Frank, 30, from Paris to people.json.",
                 "Open a second tab beside the first one with a table of the people in people.json, sorted by name."]

# ── The watched model ────────────────────────────────────────────────────────

# The model of a rehearsal: the real one, with a watch before each round. The
# watch answers `nothing` to go on, or the reason to stop, and a stop ends the
# turn with an error, as a model that fails does.
mutable struct WatchedLlm <: LlmModule.Llm
    inner::LlmModule.Llm
    watch::Any
    rounds::Int
    stopped::Union{String,Nothing}
end

WatchedLlm(inner; watch = () -> nothing) = WatchedLlm(inner, watch, 0, nothing)

function LlmModule.stream_turn(llm::WatchedLlm, request; on_event)
    reason = llm.watch()
    if reason !== nothing
        llm.stopped = reason
        error("rehearsal stopped: " * reason)
    end
    llm.rounds += 1
    LlmModule.stream_turn(llm.inner, request; on_event)
end
LlmModule.render_tool_schema(llm::WatchedLlm, tools) = LlmModule.render_tool_schema(llm.inner, tools)
LlmModule.has_meaning_model(llm::WatchedLlm) = LlmModule.has_meaning_model(llm.inner)
LlmModule.get_meaning_model_name(llm::WatchedLlm) = LlmModule.get_meaning_model_name(llm.inner)
LlmModule.compute_meaning_vectors(llm::WatchedLlm, texts; kwargs...) =
    LlmModule.compute_meaning_vectors(llm.inner, texts; kwargs...)

# ── The window ───────────────────────────────────────────────────────────────

# The window of the take: people.json, the Files tab closed, the session's
# gesture log in a pane below the file, the assistant a little wider.
function prepare_window!(document)
    for assistant in search_documents(document, node -> node isa Assistant)
        assistant.collapse_thinking = false
    end
    # The selection is a path through the tree, so it is set again after the
    # split moves the group of the file one level down.
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
    tree.root.weights = [0.55, 0.45]
    apply_pane_operation!(tree, make_pane_focus_operation(tree, group, 1))
    selected === nothing ||
        set_selection!(document, annotate_reference_types(document,
                                    first(search_references(document, node -> node === selected))))
    nothing
end

# The editor of a rehearsal: the window of the application over one file,
# printed once and started as the application starts, with no loop and no
# frames. A call of a tool then runs at once on the task that makes it.
function make_rehearsal_editor(directory, llm)
    path = joinpath(directory, "people.json")
    write(path, PEOPLE)
    assistant = make_application_assistant(:ollama; llm = llm)
    document, projection = make_application_window([path]; root = directory, assistant = assistant)
    prepare_window!(document)
    scene = make_window_scene(document, "ProjecturEd"; width = WIDTH, height = HEIGHT)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections())
    editor = Editor(ConsoleBackend(), scene, composed, Device[Display(), Keyboard(), Mouse()])
    editor.iomap = print_document(composed, nothing, scene,
                                  PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                                 Dict{Symbol,Any}(), Clock()))
    start_application!(editor, false, :ollama, "")
    assistant_document = only(search_documents(document, node -> node isa Assistant))
    (editor, assistant_document)
end

# ── What the checks read ─────────────────────────────────────────────────────

get_people_tab(editor) = get_document(find_pane(editor, "people.json"))

# The text of people.json as it would be saved; it throws when a record can not
# be printed, which is what a broken paint of the file is.
compute_people_text(editor) = print_natural_text(get_document(get_edited_document(get_people_tab(editor))))

find_names(text) = [m.captures[1] for m in eachmatch(r"\"name\"\s*:\s*\"([^\"]*)\"", text)]

get_file_history(editor) = first(search_documents(get_people_tab(editor), node -> node isa UndoBuffer))

get_pane_tree(editor) =
    only(search_documents(editor.document, node -> node isa UndoBuffer && node.content isa PaneTree)).content

function compute_node_text(node)
    node isa Cell && return compute_node_text(node[])
    node isa AbstractString && return String(node)
    try
        String(strip(print_natural_text(node)))
    catch
        string(node)
    end
end

# The texts of the labels of each table in the tabs of the window, in the order
# of the document: the header first, then the rows.
function find_table_texts(editor)
    tables = Vector{String}[]
    for group in get_pane_groups(get_pane_tree(editor)), tab in group.tabs
        for table in search_documents(tab, node -> node isa WidgetTable)
            labels = search_documents(table, node -> node isa WidgetLabel)
            push!(tables, [compute_node_text(label.content) for label in labels])
        end
    end
    tables
end

# ── The checks of the three steps ────────────────────────────────────────────

function check_frank_added(editor, steps_before)
    text = try compute_people_text(editor) catch e; return "the file does not print: " * first(sprint(showerror, e), 160) end
    names = find_names(text)
    names == [NAMES; "Frank"] || return "the names are $(names)"
    last_record = text[findlast('{', text):end]
    occursin(r"\"age\"\s*:\s*30\b", last_record) || return "Frank has no age 30"
    occursin(r"\"city\"\s*:\s*\"Paris\"", last_record) || return "Frank has no city Paris"
    steps = length(get_file_history(editor).undo_entries) - steps_before
    steps == 1 || return "the file history took $(steps) steps"
    nothing
end

function check_frank_undone(editor)
    text = try compute_people_text(editor) catch e; return "the file does not print: " * first(sprint(showerror, e), 160) end
    names = find_names(text)
    names == NAMES || return "after one undo the names are $(names)"
    nothing
end

function check_table(editor)
    tables = find_table_texts(editor)
    isempty(tables) && return "no table in any tab"
    for texts in tables
        found = filter(in(Set([NAMES; "Frank"])), texts)
        found == sort(NAMES) && return nothing
    end
    "no table with the five names sorted: $(tables)"
end

# ── A run ────────────────────────────────────────────────────────────────────

# The watch of a run: the file prints, the turn is under its rounds, and the run
# is under its time.
function make_watch(state)
    () -> begin
        editor = state[:editor]
        editor === nothing && return nothing
        try
            compute_people_text(editor)
        catch e
            return "the file does not print: " * first(sprint(showerror, e), 160)
        end
        state[:llm].rounds - state[:rounds_at_turn] >= state[:max_rounds] &&
            return "more than $(state[:max_rounds]) rounds in a turn"
        time() - state[:started] > state[:max_seconds] && return "over $(state[:max_seconds]) s"
        nothing
    end
end

function run_turn!(editor, assistant, prompt; cap)
    assistant.input = PrimitiveString(prompt)
    evaluate_operation(editor, SubmitProseOperation(assistant))
    started = time()
    sleep(0.2)
    while assistant.status === :streaming && time() - started < cap
        sleep(0.25)
    end
    round(time() - started; digits = 1)
end

# One rehearsal with `seed`: the three steps and their checks. Answers a named
# tuple of what each step did, and writes the conversation to `transcript`.
function run_s2_rehearsal(seed; transcript, max_rounds = 8, max_seconds = 600.0,
                          context = 32768, temperature = nothing)
    directory = mktempdir()
    state = Dict{Symbol,Any}(:editor => nothing, :rounds_at_turn => 0,
                             :max_rounds => max_rounds, :max_seconds => max_seconds,
                             :started => time())
    inner = temperature === nothing ? OllamaLlm(context = context, seed = seed) :
                                      OllamaLlm(context = context, seed = seed, temperature = temperature)
    llm = WatchedLlm(inner; watch = make_watch(state))
    state[:llm] = llm
    editor, assistant = make_rehearsal_editor(directory, llm)
    state[:editor] = editor
    result = Dict{Symbol,Any}(:seed => seed)

    steps_before = length(get_file_history(editor).undo_entries)
    state[:rounds_at_turn] = llm.rounds
    result[:seconds_1] = run_turn!(editor, assistant, PROMPTS[1]; cap = max_seconds)
    result[:rounds_1] = llm.rounds - state[:rounds_at_turn]
    result[:turn_1] = llm.stopped === nothing ? check_frank_added(editor, steps_before) : "stopped: " * llm.stopped

    if result[:turn_1] === nothing
        evaluate_operation(editor, UndoOperation(get_file_history(editor)))
        result[:undo] = check_frank_undone(editor)
    else
        result[:undo] = "not run"
    end

    if result[:undo] === nothing
        state[:rounds_at_turn] = llm.rounds
        result[:seconds_2] = run_turn!(editor, assistant, PROMPTS[2]; cap = max_seconds)
        result[:rounds_2] = llm.rounds - state[:rounds_at_turn]
        result[:turn_2] = llm.stopped === nothing ? check_table(editor) : "stopped: " * llm.stopped
    else
        result[:turn_2] = "not run"
    end
    result[:seconds] = round(time() - state[:started]; digits = 1)
    result[:tools] = find_tool_names(assistant)
    open(io -> write_conversation(io, assistant), transcript, "w")
    result
end

# The tools that the model called, in order, with a run of one tool counted:
# "read_resource, execute_julia_code×3".
function find_tool_names(assistant)
    names = String[]
    for turn in assistant.conversation.turns, part in turn.parts
        content = part.content
        content isa EvaluatorForm || continue
        name = String(content.tool_name) * (content.is_error ? "!" : "")
        push!(names, name)
    end
    runs = Tuple{String,Int}[]
    for name in names
        if !isempty(runs) && runs[end][1] == name
            runs[end] = (name, runs[end][2] + 1)
        else
            push!(runs, (name, 1))
        end
    end
    join([count == 1 ? name : "$(name)×$(count)" for (name, count) in runs], ", ")
end

_describe_check(outcome) = outcome === nothing ? "PASS" : outcome

function format_result(result)
    string("seed ", result[:seed], "  ", result[:seconds], " s\n",
           "  turn 1: ", _describe_check(result[:turn_1]),
           haskey(result, :rounds_1) ? "  ($(result[:rounds_1]) rounds, $(result[:seconds_1]) s)" : "", "\n",
           "  undo:   ", _describe_check(result[:undo]), "\n",
           "  turn 2: ", _describe_check(result[:turn_2]),
           haskey(result, :rounds_2) ? "  ($(result[:rounds_2]) rounds, $(result[:seconds_2]) s)" : "", "\n",
           "  tools:  ", get(result, :tools, ""), "  (! = an error)\n")
end

# The memory that a run of the model needs: the cap of this process, the model
# when it is not loaded yet, and a margin (see the note on the crashes of the
# machine). A model that the run before loaded is already counted as used.
const PROCESS_CAP_GB = 8
const MODEL_GB = 17
const MARGIN_GB = 10

function get_loaded_models()
    text = try read(`curl -s localhost:11434/api/ps`, String) catch; "" end
    [m.captures[1] for m in eachmatch(r"\"name\":\"([^\"]+)\"", text)]
end

get_needed_available_gb() =
    PROCESS_CAP_GB + MARGIN_GB + ("qwen3.8:27b" in get_loaded_models() ? 0 : MODEL_GB)

function get_available_gb()
    for line in eachline("/proc/meminfo")
        startswith(line, "MemAvailable:") && return parse(Int, split(line)[2]) ÷ 1024^2
    end
    0
end

function unload_models!()
    for model in ("qwen3.8:27b", "nomic-embed-text")
        try
            run(pipeline(`curl -s localhost:11434/api/generate -d "{\"model\":\"$model\",\"keep_alive\":0}"`;
                         stdout = devnull, stderr = devnull))
        catch
        end
    end
end

"""
    run_s2_rehearsals(seeds; directory, kwargs...)

Run the rehearsal once for each seed, one after another, and write
`summary.txt` and one transcript for each seed into `directory`. The models are
unloaded at the end.
"""
function run_s2_rehearsals(seeds; directory, kwargs...)
    mkpath(directory)
    summary = joinpath(directory, "summary.txt")
    open(summary, "w") do io
        println(io, "S2 rehearsal, ", Dates.now(), ", seeds ", collect(seeds))
    end
    passed = 0
    try
        for seed in seeds
            available, needed = get_available_gb(), get_needed_available_gb()
            others = filter(!in(("qwen3.8:27b", "nomic-embed-text:latest", "nomic-embed-text")),
                            get_loaded_models())
            if available < needed || !isempty(others)
                open(io -> println(io, "seed ", seed, ": not run, ", available, " GB available of ",
                                   needed, ", other models loaded: ", others), summary, "a")
                continue
            end
            result = try
                run_s2_rehearsal(seed; transcript = joinpath(directory, "seed_$(seed).txt"), kwargs...)
            catch e
                Dict{Symbol,Any}(:seed => seed, :seconds => 0.0,
                                 :turn_1 => "the run failed: " * first(sprint(showerror, e), 300),
                                 :undo => "not run", :turn_2 => "not run")
            end
            all(result[key] === nothing for key in (:turn_1, :undo, :turn_2)) && (passed += 1)
            open(io -> print(io, format_result(result)), summary, "a")
        end
    finally
        unload_models!()
    end
    open(io -> println(io, "passed ", passed, " of ", length(seeds)), summary, "a")
    read(summary, String)
end

# ── The transcript ───────────────────────────────────────────────────────────

function write_conversation(io, assistant)
    for (index, turn) in enumerate(assistant.conversation.turns)
        println(io, "── turn ", index, "  ", turn.role, "  ", turn.stop_reason)
        for part in turn.parts
            content = part.content
            if content isa EvaluatorForm
                code = try strip(print_natural_text(content.form)) catch; content.source end
                answer = try strip(print_natural_text(content.result)) catch; "(no text)" end
                println(io, "  [", content.tool_name, content.is_error ? " ERROR" : "", "]")
                println(io, "    ", replace(code, "\n" => "\n    "))
                println(io, "    → ", replace(first(answer, 1500), "\n" => "\n      "))
            elseif content isa ConversationThinking
                println(io, "  [thinking] ", replace(first(compute_node_text(content.text), 3000), "\n" => "\n    "))
            else
                text = compute_node_text(content)
                println(io, "  [", nameof(typeof(content)), "] ", first(text, 3000))
            end
        end
    end
end

end # module Rehearsal
