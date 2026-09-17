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
    tabs = [make_workbench_file_editor(path) for path in paths]
    folder = abspath(root)
    navigator = WorkbenchNavigator(Workspace([WorkspaceFolder(basename(folder), folder)]))
    window === :workbench ?
        _make_application_workbench(tabs, navigator, assistant) :
        _make_application_pane_tree(tabs, navigator, assistant)
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

# The workbench window: the same parts on the four fixed pages.
function _make_application_workbench(tabs, navigator, assistant)
    WorkbenchWorkbench(
        WorkbenchPage([navigator]),
        WorkbenchPage(Any[tabs...]),
        WorkbenchPage([WorkbenchConsole(), WorkbenchDescriptor(EmptyReference()),
                       WorkbenchOperator(), WorkbenchSearcher(), WorkbenchEvaluator()]),
        WorkbenchPage(assistant === nothing ? Any[] : Any[assistant]))
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
        JsonDocument      => ChainingProjection(RecursiveProjection(JsonToSyntax()),
                                                RecursiveProjection(SyntaxToText()), text_to_graphics),
        XmlDocument       => ChainingProjection(RecursiveProjection(XmlToSyntax()),
                                                RecursiveProjection(SyntaxToText()), text_to_graphics),
        JuliaDocument     => make_julia_projection_example(measure = measure),
        SqlDocument       => make_sql_syntax_projection_example(measure = measure),
        TextDocument      => text_to_graphics,
        WorkspaceDocument => ChainingProjection(
            RecursiveProjection(WorkspaceToFileSystem()),
            RecursiveProjection(FileSystemToWidget(open_file = OpenWorkspaceFileOperation)),
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
    make_command_palette_decorator_projection(
        GestureHelpDecoratorProjection(inner = base, state = GestureHelpState()))
end

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
