# The ProjecturEd application: a window that shows files, with a file navigator
# and the assistant beside them.
#
# Two windows show the same files, and `window` selects one:
#
# - `:pane`, the default: a pane tree. The navigator, the file tabs and the
#   assistant are the groups of a split, and the pane gestures rearrange them.
# - `:workbench`: the shell of four pages, with the navigator on the left, the
#   files in the middle, the information panels below and the assistant on the
#   right.
#
# Both windows hold the same file tab, `WorkbenchEditor`. So `Ctrl+S` saves and
# `Ctrl+O` reloads in both, and the navigator opens a file in both with
# `OpenWorkspaceFileOperation`.

"""
    APPLICATION_WINDOWS

The windows [`run_application`](@ref) can open: `:pane` and `:workbench`.
"""
const APPLICATION_WINDOWS = (:pane, :workbench)

"""
    APPLICATION_ASSISTANTS

The assistant backends [`run_application`](@ref) accepts: `:ollama`, `:anthropic`,
and `:none` for a window without the assistant pane.
"""
const APPLICATION_ASSISTANTS = (:ollama, :anthropic, :none)

"""
    get_application_greeting_text(backend::Symbol) -> String

What the assistant pane says before a person types anything: what the window
shows, the keys that open and save a file, and what the assistant needs to
answer.
"""
function get_application_greeting_text(backend::Symbol)
    body = """
        This window shows files. The navigator lists the working directory, and \
        each tab holds one open file.

        Press Enter on a file in the navigator, or double-click it, to open it in \
        a new tab. Ctrl+S saves the tab that has the focus, and Ctrl+O reads it \
        again from disk. F1 lists the keys that work where the focus is, and \
        Ctrl+Shift+P runs a command by its name.

        Ask me to read or change an open file, to explain its structure, or to \
        show a value in a new tab. I write Julia code and run it in this window.
        """
    requirement = backend === :anthropic ?
        "I use Claude. The environment variable ANTHROPIC_API_KEY must hold your key." :
        "I use a local model through Ollama. The Ollama server must run on this " *
        "machine, and the model must be pulled."
    body * "\n" * requirement
end

"""
    make_application_assistant(backend::Symbol; model = "") -> Assistant or nothing

The assistant pane of the application. `backend` is one of
[`APPLICATION_ASSISTANTS`](@ref); `:none` answers `nothing`, and the window then
has no assistant pane. An empty `model` means the default model of the backend.
"""
function make_application_assistant(backend::Symbol; model::AbstractString = "")
    backend in APPLICATION_ASSISTANTS ||
        error("make_application_assistant: the backend must be one of ",
              join(APPLICATION_ASSISTANTS, ", "), ", not ", repr(backend))
    backend === :none && return nothing
    greeting = ConversationConversation([
        ConversationTurn(:assistant, [ConversationPart(get_application_greeting_text(backend))])])
    Assistant(; conversation = greeting, backend = backend, model = String(model),
                api_key = get(ENV, "ANTHROPIC_API_KEY", ""))
end

"""
    make_application_document(paths; window = :pane, root = pwd(), assistant = nothing)

The document of the application window: one file tab for each path, a navigator
over `root`, and the assistant when it is not `nothing`. A path that does not
exist opens as the empty seed of its extension.
"""
function make_application_document(paths::AbstractVector; window::Symbol = :pane,
                                   root::AbstractString = pwd(), assistant = nothing)
    window in APPLICATION_WINDOWS ||
        error("make_application_document: the window must be one of ",
              join(APPLICATION_WINDOWS, ", "), ", not ", repr(window))
    tabs = [make_workbench_file_editor(path, UndoBuffer) for path in paths]
    folder = abspath(root)
    navigator = WorkbenchNavigator(Workspace([WorkspaceFolder(basename(folder), folder)]))
    content = window === :workbench ?
        _make_application_workbench(tabs, navigator, assistant) :
        _make_application_pane_tree(tabs, navigator, assistant)
    # Two levels of history, and the four rules of the undo slice make them one
    # story. Each file tab holds its own, so `Ctrl+Z` takes back an edit in the
    # file the person is looking at. The window holds one around all of them, so
    # a splitter that moves, a tab that opens and a chat draft can be taken back
    # too — none of those is inside a file.
    buffer = UndoBuffer(content)
    # The focus was seated on the content before the buffer held it, and a
    # selection is a chain every node on the path holds a piece of. Seat it again
    # from the buffer, so the first key goes where it was meant to go.
    inner = get_selection(content)
    inner === nothing || replace_selection!(buffer,
        concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                          strip_reference_types(inner)))
    buffer
end

# The pane window: the navigator, the files and the assistant side by side. The
# focus starts inside the first file, or inside the navigator when no file is
# open, so the first key reaches that document and not the tab strip.
function _make_application_pane_tree(tabs, navigator, assistant)
    files = PaneGroup(PaneTab[PaneTab(tab.title, tab) for tab in tabs])
    places = PaneGroup(PaneTab[PaneTab("Files", navigator)])
    groups = Any[places, files]
    weights = [0.2, 0.8]
    if assistant !== nothing
        push!(groups, PaneGroup(PaneTab[PaneTab("Assistant", assistant)]))
        weights = [0.18, 0.5, 0.32]
    end
    tree = PaneTree(PaneSplit(:vertical, groups; weights = weights))
    tab = get_pane_tab_reference(tree, isempty(tabs) ? places : files, 1)
    inner = isempty(tabs) ? "workspace" : "content"
    set_selection!(tree, extend_reference(tab, FieldReferenceStep("content"),
                                          FieldReferenceStep(inner)))
    tree
end

# The workbench window: the same parts on the four fixed pages. The focus starts
# inside the first file, or inside the navigator when no file is open, because a
# key goes where the selection points.
function _make_application_workbench(tabs, navigator, assistant)
    workbench = WorkbenchWorkbench(
        WorkbenchPage([navigator]),
        WorkbenchPage(Any[tabs...]),
        WorkbenchPage([WorkbenchConsole(), WorkbenchDescriptor(EmptyReference()),
                       WorkbenchOperator(), WorkbenchSearcher(), WorkbenchEvaluator()]),
        WorkbenchPage(assistant === nothing ? Any[] : Any[assistant]))
    set_selection!(workbench, isempty(tabs) ?
        @reference(workbench, navigation_page.elements[1].workspace) :
        @reference(workbench, editing_page.elements[1].content))
    workbench
end

"""
    make_application_content_projections(; measure = measure_truetype_text) -> Vector{Pair{Type,Any}}

How the application draws what a tab holds, in front of the defaults of
`NaturalToGraphics`: the domains with an editor projection of their own, the
navigator with its open gesture, the conversation, and plain text.
"""
function make_application_content_projections(; measure = measure_truetype_text)
    text_to_graphics = ChainingProjection(WordWrapping(measure = measure),
                                          TextToGraphics(measure = measure))
    Pair{Type,Any}[
        # A history around what a tab holds is invisible: it prints what it holds
        # and answers that output.
        UndoBuffer        => UndoBufferToAnyProjection(),
        JsonDocument      => ChainingProjection(RecursiveProjection(JsonToSyntax()),
                                                RecursiveProjection(SyntaxToText()), text_to_graphics),
        XmlDocument       => ChainingProjection(RecursiveProjection(XmlToSyntax()),
                                                RecursiveProjection(SyntaxToText()), text_to_graphics),
        JuliaDocument     => make_julia_projection_example(measure = measure),
        SqlDocument       => make_sql_syntax_projection_example(measure = measure),
        TextDocument      => text_to_graphics,
        WorkspaceDocument => ChainingProjection(
            RecursiveProjection(WorkspaceToFileSystem()),
            RecursiveProjection(FileSystemToWidget(
                open_file = path -> OpenWorkspaceFileOperation(path; wrap = UndoBuffer))),
            WidgetToGraphics(font_ubuntu_monospace_regular_20; measure = measure)),
        conversation_draft_entry(measure = measure),
        conversation_widget_entry(measure = measure),
        # A tab title and a plain text file are prose, not a quoted string.
        PrimitiveDocument => ChainingProjection(RecursiveProjection(PrimitiveToText()),
                                                text_to_graphics),
    ]
end

"""
    make_application_projection(; window = :pane, measure = measure_truetype_text)

How the application window is drawn. The window projection is wrapped in the
gesture help, which F1 opens, and in the command palette, which Ctrl+Shift+P
opens.
"""
function make_application_projection(; window::Symbol = :pane,
                                      measure = measure_truetype_text)
    window in APPLICATION_WINDOWS ||
        error("make_application_projection: the window must be one of ",
              join(APPLICATION_WINDOWS, ", "), ", not ", repr(window))
    content = make_application_content_projections(measure = measure)
    base = window === :workbench ?
        make_workbench_projection(measure = measure, content_projections = content) :
        _make_application_pane_projection(content, measure)
    _with_window_history(make_command_palette_decorator_projection(
        GestureHelpDecoratorProjection(inner = base, state = GestureHelpState())))
end

# The window content sits inside a history of its own, so a change that belongs
# to no file — a splitter that moves, a tab that opens — can be taken back too.
# The buffer is transparent, so everything below it is drawn exactly as before:
# the dispatcher answers the buffer, and hands every other document to the window
# projection unchanged.
#
# It is the OUTERMOST projection, because the document it is handed is the buffer,
# and because the operation it records must be the one the whole chain settled on.
_with_window_history(base) = RecursiveProjection(TypeDispatchingProjection(
    UndoBuffer => UndoBufferToAnyProjection(),
    Any        => base))

# The pane stage leaves what a tab holds as it is, and the renderer draws it. A
# file tab, the navigator and the assistant are workbench documents, so each one
# goes through the workbench stage first, and then through the same renderer.
function _make_application_pane_projection(content, measure)
    renderer(extra) = NaturalToGraphics(measure = measure, extra = extra)
    workbench = ChainingProjection(RecursiveProjection(WorkbenchToWidget()), renderer(content))
    parts = Pair{Type,Any}[WorkbenchEditor    => workbench,
                           WorkbenchNavigator => workbench,
                           Assistant          => workbench]
    WidgetHoverTrackingProjection(inner = ChainingProjection(
        RecursiveProjection(PaneToWidget()),
        renderer(vcat(parts, content))))
end

"""
    run_application(paths...; window = :pane, backend = nothing,
                    assistant = :ollama, model = "", mcp = false, root = pwd(),
                    width = nothing, height = nothing)

Open the ProjecturEd application with the files at `paths`, and run it until the
window closes.

- `window` is `:pane` or `:workbench`; see [`APPLICATION_WINDOWS`](@ref).
- `backend` is a constructed backend, for example `SdlBackend()` or
  `WebBackend()`. `nothing` takes the default backend.
- `assistant` is `:ollama`, `:anthropic` or `:none`, and `model` names the model
  of that backend; empty means its default.
- `mcp` starts an MCP server beside the window, so an external client drives the
  same editor with the same tools.
- `root` is the directory the navigator lists.

# Example

    run_application("data.json", "notes.md"; assistant = :none)
"""
function run_application(paths::AbstractString...; window::Symbol = :pane,
                         backend = nothing, assistant::Symbol = :ollama,
                         model::AbstractString = "", mcp::Bool = false,
                         root::AbstractString = pwd(),
                         width = nothing, height = nothing,
                         measure = measure_truetype_text)
    chat = make_application_assistant(assistant; model = model)
    document = make_application_document(collect(String, paths); window = window,
                                         root = root, assistant = chat)
    projection = make_application_projection(; window = window, measure = measure)
    backend === nothing && (backend = default_backend())
    run_window_editor(document, projection, "ProjecturEd";
                      backend = backend, width = width, height = height, mcp = mcp,
                      opened_window_projections = Pair{Type,Any}[_gesture_map_entry(measure)],
                      on_start = editor -> _start_application!(editor, mcp, assistant, model))
end

# ── The command line ─────────────────────────────────────────────────────────

"""
    parse_application_arguments(arguments) -> NamedTuple

The files and the options of a `projectured` command line, as the keywords of
[`run_application`](@ref) take them, plus `files` and the backend name. The
backend name is `nothing` when the command line gives none. An unknown option
or a wrong value raises an error that names it.

The `--help` text of a binary lists the same options: the builder writes it
from `PROJECTURED_OPTIONS`, and a test compares the two.
"""
function parse_application_arguments(arguments::AbstractVector{<:AbstractString})
    values = Dict{String,String}("window" => "pane", "backend" => "",
                                 "assistant" => "ollama", "model" => "",
                                 "root" => pwd())
    mcp = false
    files = String[]
    for argument in arguments
        if argument == "--mcp"
            mcp = true
        elseif startswith(argument, "--") && occursin('=', argument)
            key, value = split(argument[3:end], '='; limit = 2)
            haskey(values, key) || error("unknown option $(repr(argument))")
            values[key] = String(value)
        elseif startswith(argument, "-")
            error("unknown option $(repr(argument))")
        else
            push!(files, String(argument))
        end
    end
    window = Symbol(values["window"])
    window in APPLICATION_WINDOWS ||
        error("--window is one of ", join(APPLICATION_WINDOWS, ", "), ", not ", repr(values["window"]))
    assistant = Symbol(values["assistant"])
    assistant in APPLICATION_ASSISTANTS ||
        error("--assistant is one of ", join(APPLICATION_ASSISTANTS, ", "), ", not ",
              repr(values["assistant"]))
    backend = isempty(values["backend"]) ? nothing : Symbol(values["backend"])
    (; files, window, backend, assistant,
       model = values["model"], root = values["root"], mcp)
end

"""
    run_application_command(arguments; backends) -> Cint

What the `projectured` binary runs: read the command line, open the window, and
answer the exit code: 0 when the window closes, 1 for a wrong command line, and
2 when the program fails.

`backends` maps a backend name to the function that makes it, for example
`(sdl = SdlBackend, web = WebBackend)`. It names the backends that the build put
into the binary, and `--backend` accepts only those. Without `--backend`, the
first one opens the window.
"""
function run_application_command(arguments; backends)
    command = try
        parse_application_arguments(arguments)
    catch err
        println(stderr, "projectured: ", sprint(showerror, err))
        return Cint(1)
    end
    backend = something(command.backend, first(keys(backends)))
    if !haskey(backends, backend)
        println(stderr, "projectured: --backend is one of ", join(keys(backends), ", "),
                ", not ", repr(String(backend)))
        return Cint(1)
    end
    try
        run_application(command.files...; window = command.window,
                        backend = backends[backend](),
                        assistant = command.assistant, model = command.model,
                        mcp = command.mcp, root = command.root)
        Cint(0)
    catch err
        err isa InterruptException && return Cint(0)
        println(stderr, "projectured: ", sprint(showerror, err))
        Cint(2)
    end
end

# ── The warm-up of a build ───────────────────────────────────────────────────

"""
    warm_application() -> Nothing

Run the application once without a window, so that a build compiles what a
person does first: both windows, several file formats, a click in the
navigator, Enter on a file, a key in a file, and a save. It works in a
temporary directory. A failure is logged and does not stop the build.
"""
function warm_application()
    directory = mktempdir()
    try
        paths = String[]
        for (name, format, text) in [("a.json", :json, "{\"name\": \"Alice\"}"),
                                     ("b.md", :md, "# Title\n\nText.\n"),
                                     ("c.jl", :jl, "f(x) = x + 1\n")]
            path = joinpath(directory, name)
            write_document_file(parse_natural_text(format, text), path)
            push!(paths, path)
        end
        write(joinpath(directory, "d.txt"), "text")
        events = Any[KeyDown(:down, ModifierKeys()),
                     KeyPress('x'),
                     MousePress(:left, 100, 84, 1, ModifierKeys()),
                     KeyDown(:return, ModifierKeys()),
                     KeyDown(:s, ModifierKeys(ctrl = true))]
        for window in APPLICATION_WINDOWS
            document = make_application_document(paths; window = window, root = directory,
                assistant = make_application_assistant(:ollama))
            projection = make_application_projection(; window = window)
            scene = make_window_scene(document, "ProjecturEd"; width = 1280, height = 800)
            composed = make_window_scene_projection(projection; opened_window_projections =
                Pair{Type,Any}[_gesture_map_entry(measure_truetype_text)])
            editor = Editor(ConsoleBackend(), scene, composed,
                            Device[Display(), Keyboard(), Mouse()])
            editor.iomap = print_document(composed, scene)
            _force_reactive!(editor.iomap)
            for event in events
                change = read_intent(composed, nothing,
                                     Intent(WindowInput(:ProjecturEd, event)), editor.iomap)
                operation = change isa Intent ? change.operation : change
                operation isa Operation || continue
                editor.operation = operation
                evaluate_operation(editor, operation)
                editor.iomap = print_document(composed, editor.document)
                _force_reactive!(editor.iomap)
            end
        end
    catch err
        @warn "warm_application: the warm-up failed, and the build goes on" err
    finally
        rm(directory; recursive = true, force = true)
    end
    nothing
end

# What the application does once the editor exists. An MCP client runs no turn of
# the assistant, so the tools get the meaning model of the backend here, and a
# search by description ranks by meaning for the client too.
function _start_application!(editor, mcp::Bool, assistant::Symbol, model::AbstractString)
    (mcp && assistant !== :none && hasproperty(editor, :tools)) || return nothing
    try
        bind_meaning_model!(editor.tools, make_llm(assistant; model = String(model)))
    catch err
        @warn "The searches get no meaning model" reason =
            first(split(sprint(showerror, err), '\n'))
    end
    nothing
end
