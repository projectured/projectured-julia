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

using ProjecturedAll, ProjecturedExample, ProjecturedKernelExample, ProjecturedOllama,
      ProjecturedSDL, ProjecturedSDLExample
using Dates

const LlmModule = ProjecturedAll.LlmModule

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
    editor = Editor(scene, composed; backend = ConsoleBackend(),
                    devices = Device[Display(), Keyboard(), Mouse()])
    editor.iomap = print_document(composed, nothing, scene,
                                  PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                                 Dict{Symbol,Any}(), Clock()))
    start_application!(editor; assistant = :ollama)
    assistant_document = only(search_documents(document, node -> node isa Assistant))
    (editor, assistant_document)
end

# ── What the checks read ─────────────────────────────────────────────────────

get_people_tab(editor) = get_document(find_pane("people.json"; editor))

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

# ── What the model tells the person ──────────────────────────────────────────

# The last text that the model wrote in its answer to the last prompt: the text
# after its last call, which is what the person reads.
function find_final_message(assistant)
    turns = collect(assistant.conversation.turns)
    last_user = findlast(turn -> turn.role === :user, turns)
    last_user === nothing && return ""
    text = ""
    for turn in turns[(last_user + 1):end], part in turn.parts
        content = part.content
        content isa Union{EvaluatorForm, ConversationThinking} && continue
        candidate = strip(compute_node_text(content))
        isempty(candidate) || (text = candidate)
    end
    String(text)
end

const _NUMBER_WORDS = Dict("one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5,
                           "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10)

_read_count(word) = get(_NUMBER_WORDS, lowercase(word), tryparse(Int, word))

# Each count of people that the message states: "six people", "6 entries",
# "all five", "5 rows".
function find_stated_counts(text)
    number = "(\\d+|one|two|three|four|five|six|seven|eight|nine|ten)"
    counts = Int[]
    for m in eachmatch(Regex("\\b" * number * "\\s+(people|persons|records|entries|rows|elements|items)\\b", "i"), text)
        push!(counts, _read_count(m.captures[1]))
    end
    for m in eachmatch(Regex("\\ball\\s+" * number * "\\b", "i"), text)
        push!(counts, _read_count(m.captures[1]))
    end
    filter(!isnothing, counts)
end

function check_final_count(assistant, expected)
    text = find_final_message(assistant)
    counts = find_stated_counts(text)
    all(==(expected), counts) && return nothing
    "the last message says $(counts), not $(expected): $(repr(first(text, 200)))"
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
                          context = 32768, temperature = nothing, system = identity)
    directory = mktempdir()
    state = Dict{Symbol,Any}(:editor => nothing, :rounds_at_turn => 0,
                             :max_rounds => max_rounds, :max_seconds => max_seconds,
                             :started => time())
    inner = temperature === nothing ? OllamaLlm(context = context, seed = seed) :
                                      OllamaLlm(context = context, seed = seed, temperature = temperature)
    llm = WatchedLlm(inner; watch = make_watch(state))
    state[:llm] = llm
    editor, assistant = make_rehearsal_editor(directory, llm)
    assistant.system = system(assistant.system)
    state[:editor] = editor
    result = Dict{Symbol,Any}(:seed => seed)

    steps_before = length(get_file_history(editor).undo_entries)
    state[:rounds_at_turn] = llm.rounds
    result[:seconds_1] = run_turn!(editor, assistant, PROMPTS[1]; cap = max_seconds)
    result[:rounds_1] = llm.rounds - state[:rounds_at_turn]
    result[:turn_1] = llm.stopped === nothing ? check_frank_added(editor, steps_before) : "stopped: " * llm.stopped
    result[:turn_1] === nothing && (result[:turn_1] = check_final_count(assistant, 6))

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
        result[:turn_2] === nothing && (result[:turn_2] = check_final_count(assistant, 5))
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
const PROCESS_CAP_GB = 3
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

# The guides and the API are indexed once in a process. A guide or a docstring
# that changed since then is in the next search only after this.
function reset_documentation_indexes!()
    tool = ProjecturedAll.ToolModule
    lock(tool._INDEX_LOCK) do
        tool._GUIDE_INDEX[] = nothing
        tool._API_INDEX[] = nothing
        empty!(tool._DECLARED_INDEX)
    end
    nothing
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
    reset_documentation_indexes!()
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

# ── Tasks of one prompt ─────────────────────────────────────────────────────
#
# Other tasks on the same window, one prompt each, so a change of the
# documentation is measured on more than the steps of S2.

struct SingleTask
    name::String
    prompt::String
    check::Any          # (editor, steps_before) -> nothing, or what is wrong
end

# The field `field` of the record whose name is `name`, in the text of the file.
function find_record_field(text, name, field)
    for record in eachmatch(r"\{[^{}]*\}", text)
        occursin(Regex("\"name\"\\s*:\\s*\"$(name)\""), record.match) || continue
        found = match(Regex("\"$(field)\"\\s*:\\s*(\"[^\"]*\"|[^,}\\s]+)"), record.match)
        return found === nothing ? nothing : strip(found.captures[1], '"')
    end
    nothing
end

function check_file_edit(editor, steps_before)
    steps = length(get_file_history(editor).undo_entries) - steps_before
    steps >= 1 || return "the file history took no step: the change is not an edit"
    nothing
end

function check_city_changed(editor, steps_before)
    text = try compute_people_text(editor) catch e; return "the file does not print: " * first(sprint(showerror, e), 160) end
    find_names(text) == NAMES || return "the names are $(find_names(text))"
    city = find_record_field(text, "Ada", "city")
    city == "Berlin" || return "Ada's city is $(repr(city))"
    find_record_field(text, "Bob", "city") == "Oslo" || return "Bob's city changed"
    check_file_edit(editor, steps_before)
end

function check_record_removed(editor, steps_before)
    text = try compute_people_text(editor) catch e; return "the file does not print: " * first(sprint(showerror, e), 160) end
    names = find_names(text)
    names == filter(!=("Bob"), NAMES) || return "the names are $(names)"
    check_file_edit(editor, steps_before)
end

# Every text of the tabs other than the file, the assistant and the log.
function find_other_tab_texts(editor)
    texts = String[]
    for group in get_pane_groups(get_pane_tree(editor)), tab in group.tabs
        get_pane_tab_title_string(tab) in ("people.json", "Assistant", "Gestures") && continue
        for node in search_documents(tab, node -> node isa Union{WidgetLabel, TextString, PrimitiveString})
            push!(texts, compute_node_text(node isa WidgetLabel ? node.content : node))
        end
        push!(texts, compute_node_text(tab.content))
    end
    texts
end

function check_average_shown(editor, steps_before)
    texts = find_other_tab_texts(editor)
    isempty(texts) && return "no new tab"
    any(text -> occursin("32.8", text), texts) || return "no tab shows 32.8: $(first(join(texts, " | "), 300))"
    nothing
end

function check_pane_closed(editor, steps_before)
    titles = [get_pane_tab_title_string(tab) for group in get_pane_groups(get_pane_tree(editor)) for tab in group.tabs]
    "Gestures" in titles && return "the tabs are $(titles)"
    "people.json" in titles || return "people.json was closed too: $(titles)"
    nothing
end

const TASKS = [
    SingleTask("change", "Change the city of Ada to Berlin in people.json.", check_city_changed),
    SingleTask("remove", "Remove Bob from people.json.", check_record_removed),
    SingleTask("average", "Show the average age of the people in people.json in a new tab.", check_average_shown),
    SingleTask("close", "Close the Gestures pane.", check_pane_closed),
]

function run_task_rehearsal(task::SingleTask, seed; transcript, max_rounds = 8, max_seconds = 300.0,
                            context = 32768, system = identity)
    state = Dict{Symbol,Any}(:editor => nothing, :rounds_at_turn => 0,
                             :max_rounds => max_rounds, :max_seconds => max_seconds,
                             :started => time())
    llm = WatchedLlm(OllamaLlm(context = context, seed = seed); watch = make_watch(state))
    state[:llm] = llm
    editor, assistant = make_rehearsal_editor(mktempdir(), llm)
    assistant.system = system(assistant.system)
    state[:editor] = editor
    steps_before = length(get_file_history(editor).undo_entries)
    seconds = run_turn!(editor, assistant, task.prompt; cap = max_seconds)
    outcome = llm.stopped === nothing ? task.check(editor, steps_before) : "stopped: " * llm.stopped
    open(io -> write_conversation(io, assistant), transcript, "w")
    (outcome = outcome, rounds = llm.rounds, seconds = seconds, tools = find_tool_names(assistant))
end

"""
    run_task_rehearsals(seeds; directory, tasks = TASKS)

Run each task of one prompt once for each seed, and write `tasks.txt` and one
transcript for each run into `directory`. The models are unloaded at the end.
"""
function run_task_rehearsals(seeds; directory, tasks = TASKS, kwargs...)
    mkpath(directory)
    summary = joinpath(directory, "tasks.txt")
    open(io -> println(io, "tasks, ", Dates.now(), ", seeds ", collect(seeds)), summary, "w")
    reset_documentation_indexes!()
    passed = 0
    runs = 0
    try
        for task in tasks, seed in seeds
            available, needed = get_available_gb(), get_needed_available_gb()
            if available < needed
                open(io -> println(io, task.name, " seed ", seed, ": not run, ", available, " GB available"), summary, "a")
                continue
            end
            runs += 1
            result = try
                run_task_rehearsal(task, seed; transcript = joinpath(directory, "$(task.name)_$(seed).txt"), kwargs...)
            catch e
                (outcome = "the run failed: " * first(sprint(showerror, e), 300), rounds = 0, seconds = 0.0, tools = "")
            end
            result.outcome === nothing && (passed += 1)
            open(summary, "a") do io
                println(io, rpad(task.name, 8), " seed ", seed, ": ", _describe_check(result.outcome),
                        "  (", result.rounds, " rounds, ", result.seconds, " s)  ", result.tools)
            end
        end
    finally
        unload_models!()
    end
    open(io -> println(io, "passed ", passed, " of ", runs), summary, "a")
    read(summary, String)
end

# ── Documentation by name ────────────────────────────────────────────────────

# The docstring of each name of the flat namespace, as Markdown, under a heading
# with its name: what an oracle gives the model at the start.
function format_named_documentation(names)
    io = IOBuffer()
    for name in names
        value = getfield(ProjecturedAll, name)
        println(io, "### `", name, "`\n")
        println(io, strip(string(Base.Docs.doc(value))), "\n")
    end
    String(take!(io))
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
