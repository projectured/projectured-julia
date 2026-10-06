# Fragment of `ApplicationModule` — the ProjecturEd application: a window that
# shows files, with a Files pane and the assistant beside them.
#
# The Files pane, the file tabs and the assistant are the groups of a split, and
# the pane gestures rearrange them. Every file tab holds a `FileDocument`, so
# `Ctrl+S` saves and `Ctrl+O` reloads it, and the Files pane opens a file with
# `OpenFileOperation`.

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
        This window shows files. The Files pane lists the working directory, and \
        each tab holds one open file.

        Press Enter on a file in the Files pane, or double-click it, to open it in \
        a new tab. Ctrl+S saves the tab that has the focus, and Ctrl+O reads it \
        again from disk. F1 lists the keys that work where the focus is, and \
        Ctrl+Shift+P runs a command by its name.

        Alt+click anything in a tab to select it, and Alt with an arrow to move \
        the selection. Ctrl+C copies what is selected, Ctrl+X cuts it, Ctrl+N \
        notes it, and Ctrl+V pastes it into a new tab from Ctrl+T.

        Ask me to read or change an open file, to explain its structure, or to \
        show a value in a new tab. I write Julia code and run it in this window: \
        I can open a path as a tab, save one back, arrange the panes, and build \
        a card, a table or a form to show you something.
        """
    requirement = backend === :anthropic ?
        "I use Claude. The environment variable ANTHROPIC_API_KEY must hold your key." :
        "I use a local model through Ollama. The Ollama server must run on this " *
        "machine, and the model must be pulled."
    body * "\n" * requirement
end

"""
    make_application_assistant(backend::Symbol; model = "", context = 0, llm = nothing) -> Assistant or nothing

The assistant pane of the application. `backend` is one of
[`APPLICATION_ASSISTANTS`](@ref); `:none` answers `nothing`, and the window then
has no assistant pane. An empty `model` means the default model of the backend,
and a `context` of `0` means its default token window. A given `llm` is the model
that the assistant asks, in place of the one it builds from `backend`, `model` and
`context`: a scripted model that stands in for the real one, or an `OllamaLlm`
with a `seed` and a `temperature`.
"""
function make_application_assistant(backend::Symbol; model::AbstractString = "",
                                    context::Integer = 0, llm = nothing)
    backend in APPLICATION_ASSISTANTS ||
        error("make_application_assistant: the backend must be one of ",
              join(APPLICATION_ASSISTANTS, ", "), ", not ", repr(backend))
    backend === :none && return nothing
    greeting = ConversationConversation([
        ConversationTurn(:assistant, [ConversationPart(get_application_greeting_text(backend))])])
    Assistant(; conversation = greeting, backend = backend, model = String(model),
                context = context, system = make_application_system(),
                api_key = get(ENV, "ANTHROPIC_API_KEY", ""), llm = llm)
end

"""
    make_application_document(paths; root = pwd(), assistant = nothing,
                              settings = make_settings())

The document of the application window: one file tab for each path, a Files
pane over `root`, and the assistant when it is not `nothing`. A path that does not
exist opens as the empty seed of its extension. Each history of the window keeps
as many steps as the `HistorySettings` of `settings` say.
"""
function make_application_document(paths::AbstractVector;
                                   root::AbstractString = pwd(), assistant = nothing,
                                   settings::Settings = make_settings())
    history = make_history_wrap(settings)
    tabs = [make_file_tab_content(path, history) for path in paths]
    workspace = _make_application_workspace(root)
    # Each file tab holds a history of its own, so `Ctrl+Z` takes back an edit in
    # the file the person is looking at. The wrapper `undo` puts one around the
    # whole tree, so a splitter that moves, a tab that opens and a chat draft can
    # be taken back too.
    _make_application_pane_tree(tabs, workspace, assistant)
end

# The folder the window lists. The toolbar's explorer opens the same one, so a
# Files pane a person closed comes back as it was.
function _make_application_workspace(root::AbstractString)
    folder = abspath(root)
    Workspace([WorkspaceFolder(basename(folder), folder)])
end

# The Files pane, the files and the assistant side by side. The focus starts
# inside the first file, or on the root row of the Files pane when no file is
# open, so the first key reaches that document and not the tab strip. The root
# row is the first folder of the workspace as a whole; the workspace itself is
# not selected, so its page shows no ring.
function _make_application_pane_tree(tabs, workspace, assistant)
    files = PaneGroup(PaneTab[PaneTab(get_document_title(tab), tab) for tab in tabs])
    places = PaneGroup(PaneTab[PaneTab("Files", workspace)])
    groups = Any[places, files]
    weights = [0.2, 0.8]
    if assistant !== nothing
        push!(groups, PaneGroup(PaneTab[PaneTab("Assistant", assistant)]))
        weights = [0.18, 0.5, 0.32]
    end
    tree = PaneTree(PaneSplit(:vertical, groups; weights = weights))
    if isempty(tabs)
        tab = get_pane_tab_reference(tree, places, 1)
        set_selection!(tree, extend_reference(tab, FieldReferenceStep("content"),
                                              FieldReferenceStep("folders"),
                                              ElementReferenceStep(1)))
    else
        tab = get_pane_tab_reference(tree, files, 1)
        set_selection!(tree, extend_reference(tab, FieldReferenceStep("content"),
                                              FieldReferenceStep("content")))
    end
    tree
end

"""
    make_application_content_projections(; measure = FontFileMeasure(),
                                         appearance::Appearance = Appearance())
        -> Vector{Pair{Type,Any}}

How the application draws what a tab holds, in front of the defaults of
`NaturalToGraphics`: the history around a file, the Files pane, the assistant
and its conversation, and plain text. A document of a domain draws through the
natural renderer, which every loaded domain registers itself with, so the
application names no domain.
"""
function make_application_content_projections(; measure = FontFileMeasure(),
                                               appearance::Appearance = Appearance(),
                                               settings::Settings = make_settings())
    text_to_graphics = ChainingProjection(WordWrapping(measure = measure),
                                          TextToGraphics(measure = measure))
    conversation_rows = Pair{Type,Any}[
        make_conversation_draft_row(measure = measure, appearance = appearance),
        make_conversation_row(measure = measure, appearance = appearance),
    ]
    Pair{Type,Any}[
        # A history around what a tab holds is invisible: it prints what it holds
        # and answers that output.
        UndoBuffer        => UndoBufferToAnyProjection(),
        TextDocument      => text_to_graphics,
        # The file system slice registers a row for a workspace, and this one
        # overrides it for one reason: what a file opens WITH is the
        # application's choice, and a slice cannot know that this application
        # gives every file it opens a history.
        # The file system stage has no mark of its own, so a fault in it costs the
        # workspace, at the barrier of the renderer that draws it.
        WorkspaceDocument => ChainingProjection(
            RecursiveProjection(WorkspaceToFileSystem()),
            RecursiveProjection(FaultCatchingProjection(
                inner = FileSystemToWidget(
                    open_file = path -> OpenFileOperation(path; wrap = make_history_wrap(settings))),
                substitute = FaultToWidget())),
            RecursiveProjection(FaultCatchingProjection(
                inner = WidgetToGraphics(; measure = measure,
                                         theme = get_scaled_theme!(appearance, WidgetTheme),
                                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)),
                substitute = FaultToGraphics()))),
        # A tab of its own: the pane group hands the assistant's own split pane
        # to a fresh renderer, rather than re-entering the one already dispatching
        # on it — a tab's content is read through `print_child`, which does not
        # reduce a projection's own output to a fixpoint the way a top-level
        # print does, so a bare `Assistant => AssistantToWidgetSplitPane()` row
        # would hand the tab a widget, not the graphics it draws.
        Assistant         => ChainingProjection(RecursiveProjection(FaultCatchingProjection(
                                                    inner = AssistantToWidgetSplitPane(
                                                        get_scaled_theme!(appearance, ConversationTheme)),
                                                    substitute = FaultToWidget())),
                                                NaturalToGraphics(measure = measure, extra = conversation_rows,
                                                                  appearance = appearance)),
        conversation_rows...,
        # A tab title and a plain text file are prose, not a quoted string.
        PrimitiveDocument => ChainingProjection(RecursiveProjection(FaultCatchingProjection(
                                                    inner = PrimitiveToText(),
                                                    substitute = FaultToText())),
                                                text_to_graphics),
    ]
end

"""
    make_application_projection(; measure = FontFileMeasure(),
                                appearance::Appearance = Appearance())

How the content of the application window is drawn: the pane tree or the
workbench, and the domains inside it.

It is the **content** alone. The wrappers of `build_editor` that
[`make_application_wrappers`](@ref) names go over it.
"""
function make_application_projection(; measure = FontFileMeasure(),
                                     appearance::Appearance = Appearance(),
                                     settings::Settings = make_settings())
    content = make_application_content_projections(; measure, appearance, settings)
    _make_application_pane_projection(content, measure, appearance)
end

"""
    make_application_wrappers(; root = pwd(), assistant = nothing, status_bar = true,
                              measure = FontFileMeasure(),
                              appearance::Appearance = Appearance()) -> NamedTuple

The wrappers of `build_editor` that the application window has, as keywords:
its undo, its chrome, the clipboard and the walk, F1 help, the command palette,
and the gesture log, the message log, the statistics and the fault log, which
fill the tools of the toolbar. **One place says which wrappers this binary has.**
[`run_application`](@ref), [`make_application_window`](@ref) and the warm-up of
a build come here, so none of them holds a list of its own.

The toolbar has the assistant when `assistant` is not `nothing`, a fresh one
with its backend, its model and its greeting, and its explorer lists `root`.
`status_bar = false` leaves out the status bar, which a video that shows what
the window paints again uses, because the status bar changes with every move of
the caret. The clipboard offers all of its gestures: a person who edits a file
expects `Ctrl+X` to cut.
"""
make_application_wrappers(; root::AbstractString = pwd(), assistant = nothing,
                          status_bar::Bool = true, measure = FontFileMeasure(),
                          appearance::Appearance = Appearance()) =
    (; undo = true,
       shell = (; assistant = _make_assistant_factory(assistant),
                  explorer = _ -> _make_application_workspace(root),
                  status_bar, measure, appearance),
       clipboard = true,
       gesture_help = (; measure),
       command_palette = (; measure),
       gesture_log = true, message_log = true, frame_statistics = true, fault_log = true)

"""
    make_application_window(paths; root = pwd(), assistant = nothing,
                            status_bar = true,
                            measure = FontFileMeasure(),
                            appearance::Appearance = Appearance())
        -> (document, projection)

The content of the application window with its wrappers, for a caller that
draws it in a window scene of its own, such as a test, a rehearsal or the
warm-up of a build: the document of [`make_application_document`](@ref) and the
projection of [`make_application_projection`](@ref), wrapped by
`make_editor_parts` with the keywords of [`make_application_wrappers`](@ref),
with no backend and so no window. Nothing runs the start steps of the parts, so
no log capture is installed.
"""
function make_application_window(paths::AbstractVector;
                                 root::AbstractString = pwd(), assistant = nothing,
                                 status_bar::Bool = true,
                                 measure = FontFileMeasure(),
                                 appearance::Appearance = Appearance(),
                                 settings::Settings = make_settings())
    # The caller's `build_editor` adds the appearance and the settings wrappers.
    parts = make_editor_parts(make_application_document(paths; root, assistant, settings),
                              make_application_projection(; measure, appearance, settings);
                              appearance = false, settings = false,
                              make_application_wrappers(; root, assistant, status_bar, measure,
                                                          appearance)...)
    (parts.document, parts.projection)
end

_make_assistant_factory(::Nothing) = nothing
_make_assistant_factory(assistant::Assistant) =
    _ -> make_application_assistant(assistant.backend; model = assistant.model,
                                    context = assistant.context)

# The pane stage leaves what a tab holds as it is, and the renderer draws it. A
# file tab, the Files pane and the assistant each register their own natural
# row, so the renderer draws them without this application naming them.
function _make_application_pane_projection(content, measure, appearance::Appearance)
    renderer = NaturalToGraphics(measure = measure, extra = content, appearance = appearance)
    ChainingProjection(RecursiveProjection(FaultCatchingProjection(inner = PaneToWidget(),
                                                                   substitute = FaultToWidget())),
                       renderer)
end

"""
    make_application_api() -> Vector

What the assistant of this window may write, and the whole of it.

Five vocabularies: the pane verbs that arrange the window, the widget names that
build what a pane shows, the file verbs that open and save one, the workspace
this application lists, and what each loaded domain registered with
`register_assistant_api!`. Every exported name here is a verb the assistant reaches
through `execute_julia_code`, and nothing else resolves.

Each vocabulary is declared where its verbs are, so a second host that offers the
same verbs states it once and this function only names which it wants.
"""
make_application_api() = Any[
    make_pane_api()...,
    make_interface_api()...,
    make_file_api()...,
    # What this application holds and the file slice does not name: the tree the
    # Files pane lists, and the operation that opens a row of it.
    FileSystemModule => (:OpenFileOperation, :Workspace, :WorkspaceFolder),
    # How a model reads what a tab holds, which is what a window of files is
    # asked about: find a document in the window, see through the history a file
    # carries, take the content of a file document, and read or write a document
    # of any domain as its own text.
    DocumentModule => (:search_documents, :get_wrapped_document),
    FileFormatModule => (:get_file_content,),
    NaturalModule => (:print_natural_text, :parse_natural_text),
    # The verbs that edit a collection of a document, as edits of the editor.
    EditorModule => (:insert_elements!, :delete_elements!),
    # What each loaded domain offers for its own documents, such as the shape of
    # a JSON file, which a model reads to find the fields of a record.
    get_registered_assistant_api()...,
]

"""
    APPLICATION_SYSTEM

What the assistant of this application is told about itself.

It is the editor's own instructions with one paragraph added: which verbs this
window offers. The greeting, this text and [`make_application_api`](@ref) are
three descriptions of one thing, so all three change together.
"""
const APPLICATION_SYSTEM = DEFAULT_ASSISTANT_SYSTEM * "\n\n" *
    "THIS WINDOW SHOWS FILES. Its verbs are the functions of the modules " *
    "PaneModule, WidgetModule, LayoutModule, FileFormatModule and " *
    "FileSystemModule, and the names that search_api lists. Read the guide " *
    "resource://guide/guide/orientation first: it shows each step below in code. " *
    "find_pane(editor, title) answers a tab by its title, and " *
    "get_edited_document(tab) answers the document that the tab shows, which acts " *
    "like the data: index it, iterate it, read a field. print_natural_text(document) " *
    "answers its text. To change a document, use a verb, so the change is an edit " *
    "that Ctrl+Z takes back: replace_referenced_value!(editor, part, new_value), " *
    "insert_elements!(editor, collection, index, values) and " *
    "delete_elements!(editor, collection, index). open_pane!(editor, document; " *
    "title, target, side) puts a document in a tab, beside or under another tab, " *
    "and get_parent(editor, tab) answers the group that holds a tab; focus_pane!, " *
    "move_pane! and close_pane! bring a pane forward, move it and close it, and " *
    "show_layout prints what is where. WidgetModule and LayoutModule build what a " *
    "pane shows — a card, a button, a table, a row or a column of them. " *
    "FileFormatModule opens a path as a tab with make_file_tab_content and writes a " *
    "document back with write_document_file. FileSystemModule names the workspace " *
    "the Files pane lists. search_documents finds a document in the window when no " *
    "tab names it. " *
    "Call one tool per round, and put the whole Julia source " *
    "in the code argument of execute_julia_code: a call with no code does " *
    "nothing and costs the round."

"""
    make_application_system() -> String

The system text of the assistant of this application: [`APPLICATION_SYSTEM`](@ref),
then the section "Reach what a tab holds" of the orientation guide, which shows in
code how to read what a tab holds, change a part of it with a verb, add a record and
open a table beside a tab.

The section is in the text from the first round, because a model that is only told
to read the guide sometimes starts without it, guesses how to make a value, and
fails. Measured with the rehearsal of the assistant (`tool/assistant/rehearsal.jl`):
with the section, S2 passed 10 of 10 seeds and the tasks of one prompt 12 of 12;
without it, 4 of 5 and 4 of 6. The guide stays the one place of the section.
"""
make_application_system() =
    APPLICATION_SYSTEM * "\n\nHOW TO WORK IN THIS WINDOW, from the orientation guide:\n\n" *
    read_guide_section("guide/orientation", "Reach what a tab holds")

"""
    make_application_settings(file; fault_policy = nothing, assistant = nothing,
                              model = nothing, context = nothing, mcp = nothing)
        -> Settings

The settings of the application window, from the weakest source: the defaults,
the file `file`, the environment variables, and the command line: `fault_policy`
and the values of the `StartSettings` that the keywords give. A keyword that is
`nothing` gives nothing. `file` is also where Save and Load of the settings tab
write and read; `nothing` reads and names no file.
"""
function make_application_settings(file::Union{AbstractString,Nothing};
                                   fault_policy::Union{FaultPolicy,Nothing} = nothing,
                                   assistant::Union{Symbol,Nothing} = nothing,
                                   model::Union{AbstractString,Nothing} = nothing,
                                   context::Union{Integer,Nothing} = nothing,
                                   mcp::Union{Bool,Nothing} = nothing)
    settings = make_settings()
    if file !== nothing
        settings.file = String(file)
        read_settings_file!(settings, file)
    end
    read_settings_environment!(settings)
    if fault_policy !== nothing
        fault = get_settings_group!(settings, FaultSettings)
        fault.is_barrier_enabled = fault_policy.is_barrier_enabled
        fault.is_console_enabled = fault_policy.is_console_enabled
        fault.is_sound_enabled = fault_policy.is_sound_enabled
    end
    start = get_settings_group!(settings, StartSettings)
    assistant === nothing || (start.assistant = assistant)
    model === nothing || (start.model = String(model))
    context === nothing || (start.context = Int(context))
    mcp === nothing || (start.mcp = mcp)
    settings
end

"""
    make_history_wrap(settings) -> Function

The function that puts a document into an `UndoBuffer` whose capacity is the cell
of `undo_capacity` of the `HistorySettings` of `settings`, so the history follows
a change of the setting.
"""
make_history_wrap(settings::Settings) =
    content -> UndoBuffer(content; capacity = get_setting_cell(
        get_settings_group!(settings, HistorySettings), :undo_capacity))

"""
    run_application(paths...; backend = nothing,
                    assistant = nothing, model = nothing, mcp = nothing,
                    mcp_host = nothing, mcp_port = nothing, root = pwd(),
                    context = nothing,
                    width = nothing, height = nothing, fault_policy = nothing,
                    appearance = load_appearance!(Appearance()),
                    settings_file = get_settings_file())

Open the ProjecturEd application with the files at `paths`, and run it until the
window closes.

- `backend` is a constructed backend, for example `SdlBackend()` or
  `WebBackend()`. `nothing` takes the default backend.
- `assistant` is `:ollama`, `:anthropic` or `:none`, and `model` names the model
  of that backend; empty means its default.
- `mcp` starts an MCP server beside the window, so an external client drives the
  same editor with the same tools. `mcp_host` and `mcp_port` say where it
  listens; each one that is `nothing` takes the default, `127.0.0.1` and `9876`.
- `root` is the directory the Files pane lists.
- `context` is how many tokens of the conversation the model may see; `0` leaves
  the backend's own answer. It matters for a local model, whose window costs
  memory on this machine.
- `assistant`, `model`, `mcp` and `context` that are `nothing` take the
  `StartSettings` of the settings file, so a person sets them in the settings
  tab for the next start; a value given here wins for this run.
- `fault_policy` is what the editor does with a fault, for this run. `nothing`
  leaves it to the settings; `make_strict_fault_policy()` stops at the first one.
- `settings_file` is the settings file of the window, `settings.toml` in the
  configuration folder by default. The settings start from their defaults, then
  the file, then the environment variables, then `fault_policy`; a later source
  wins for this run. `nothing` reads and names no file.
- `appearance` is the `Appearance` of the window: every widget of the window and
  of the windows it opens draws with its scaled widget theme. The default is the
  appearance that the file of `get_appearance_file` saved, or the default one when
  there is no file.

# Example

    run_application("data.json", "notes.md"; assistant = :none)
"""
function run_application(paths::AbstractString...;
                         backend = nothing, assistant::Union{Symbol,Nothing} = nothing,
                         model::Union{AbstractString,Nothing} = nothing,
                         mcp::Union{Bool,Nothing} = nothing,
                         mcp_host::Union{AbstractString,Nothing} = nothing,
                         mcp_port::Union{Integer,Nothing} = nothing,
                         root::AbstractString = pwd(),
                         context::Union{Integer,Nothing} = nothing,
                         width = nothing, height = nothing,
                         fault_policy::Union{FaultPolicy,Nothing} = nothing,
                         measure = FontFileMeasure(),
                         appearance::Appearance = load_appearance!(Appearance()),
                         settings_file::Union{AbstractString,Nothing} = get_settings_file())
    settings = make_application_settings(settings_file; fault_policy, assistant, model,
                                         context, mcp)
    start = get_settings_group!(settings, StartSettings)
    assistant, model, mcp = start.assistant, start.model, start.mcp
    chat = make_application_assistant(assistant; model, context = start.context)
    backend === nothing && (backend = default_backend())
    # The root is the application's own pane tree, so the tabs leave it as it is.
    # The settings carry the fault policy of the command line, and the first print
    # runs under it already.
    fault = get_settings_group!(settings, FaultSettings)
    policy = FaultPolicy(; is_barrier_enabled = fault.is_barrier_enabled,
                         is_console_enabled = fault.is_console_enabled,
                         is_sound_enabled = fault.is_sound_enabled)
    editor = build_editor(make_application_document(collect(String, paths); root,
                                                    assistant = chat, settings),
                          make_application_projection(; measure, appearance, settings);
                          backend, appearance, settings, fault_policy = policy,
                          # The natural projection draws what a tooltip holds. The
                          # other windows that a wrapper opens draw with the rows a
                          # pane draws with.
                          window = (; title = "ProjecturEd", width, height,
                                    opened_window_projections = vcat(
                                        Pair{Type,Any}[make_natural_tooltip_row(; measure, appearance)],
                                        make_application_content_projections(; measure, appearance,
                                                                             settings))),
                          make_application_wrappers(; root, assistant = chat, measure, appearance)...)
    start_application!(editor; mcp, assistant, model)
    run_editor!(editor; mcp = mcp ? (; host = mcp_host, port = mcp_port) : false)
end

# ── The command line ─────────────────────────────────────────────────────────

"""
    parse_application_arguments(arguments) -> NamedTuple

The files and the options of a `projectured` command line, as the keywords of
[`run_application`](@ref) take them, plus `files` and the backend name. The
backend name is `nothing` when the command line gives none, and so are the
assistant, the model, the context and `mcp`, so the `StartSettings` of the
settings file decide them. An unknown option or a wrong value raises an error
that names it.

`--mcp` starts the MCP server at its default address. `--mcp=PORT` and
`--mcp=HOST:PORT` start it too, and say where it listens: `mcp_host` and
`mcp_port` are then the values given, and `nothing` where the command line
gives none.

The `--help` text of a binary lists the same options: the builder writes it
from `PROJECTURED_OPTIONS`, and a test compares the two.
"""
function parse_application_arguments(arguments::AbstractVector{<:AbstractString})
    values = Dict{String,String}("root" => pwd())
    mcp = nothing
    mcp_host, mcp_port = nothing, nothing
    strict_fault_policy = false
    files = String[]
    for argument in arguments
        if argument == "--mcp"
            mcp = true
        elseif startswith(argument, "--mcp=")
            mcp = true
            mcp_host, mcp_port = _parse_mcp_address(argument[length("--mcp=")+1:end])
        elseif argument == "--strict-fault-policy"
            strict_fault_policy = true
        elseif startswith(argument, "--") && occursin('=', argument)
            key, value = split(argument[3:end], '='; limit = 2)
            key in ("backend", "assistant", "model", "root", "context") ||
                error("unknown option $(repr(argument))")
            values[key] = String(value)
        elseif startswith(argument, "-")
            error("unknown option $(repr(argument))")
        else
            push!(files, String(argument))
        end
    end
    assistant = haskey(values, "assistant") ? Symbol(values["assistant"]) : nothing
    assistant === nothing || assistant in APPLICATION_ASSISTANTS ||
        error("--assistant is one of ", join(APPLICATION_ASSISTANTS, ", "), ", not ",
              repr(values["assistant"]))
    backend = isempty(get(values, "backend", "")) ? nothing : Symbol(values["backend"])
    context = haskey(values, "context") ? tryparse(Int, values["context"]) : nothing
    haskey(values, "context") && (context === nothing || context < 0) &&
        error("--context is a count of tokens, not ", repr(values["context"]))
    (; files, backend, assistant, model = get(values, "model", nothing),
       root = values["root"], mcp, mcp_host, mcp_port, context, strict_fault_policy)
end

# The value of `--mcp=`: `PORT`, or `HOST:PORT`. The port follows the last colon.
function _parse_mcp_address(text::AbstractString)
    host, port_text = occursin(':', text) ? rsplit(text, ':'; limit = 2) : (nothing, text)
    port = tryparse(Int, port_text)
    (port === nothing || !(1 <= port <= 65535) || host == "") &&
        error("--mcp takes PORT or HOST:PORT, not ", repr(String(text)))
    (host === nothing ? nothing : String(host), port)
end

"""
    run_application_command(arguments; backends) -> Cint

What the `projectured` binary runs: read the command line, open the window, and
answer the exit code: 0 when the window closes, 1 for a wrong command line, and
2 when the program fails. A failure prints its stack.

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
        run_application(command.files...;
                        backend = backends[backend](),
                        assistant = command.assistant, model = command.model,
                        mcp = command.mcp, mcp_host = command.mcp_host,
                        mcp_port = command.mcp_port, root = command.root,
                        context = command.context,
                        fault_policy = command.strict_fault_policy ?
                            make_strict_fault_policy() : nothing)
        Cint(0)
    catch err
        err isa InterruptException && return Cint(0)
        print(stderr, "projectured: ")
        showerror(stderr, err, catch_backtrace())
        println(stderr)
        Cint(2)
    end
end

# ── The warm-up of a build ───────────────────────────────────────────────────

const _WARMUP_WALK_MAX_DEPTH = 200
const _WARMUP_WALK_MAX_NODES = 20_000

"""
    evaluate_reachable_cells!(value) -> nothing

Read every reactive `Cell` that `value` reaches, so that a warm-up compiles the
bodies of the cells, the closures of a printer, and not only the graph that
holds them. A cap on the depth and on the count of the nodes keeps a lazy or a
large document from a walk without end.
"""
evaluate_reachable_cells!(value) = (_walk_cells!(value, _CellWalk(Set{UInt64}(), 0), 0); nothing)

# The objects that the walk has read, and how many.
mutable struct _CellWalk
    visited::Set{UInt64}
    count::Int
end

function _walk_cells!(x, walk::_CellWalk, depth::Int)
    (x === nothing || x isa Bool || x isa Number || x isa AbstractString ||
     x isa Symbol || x isa Function || x isa DataType || x isa Module) && return
    (depth >= _WARMUP_WALK_MAX_DEPTH || walk.count >= _WARMUP_WALK_MAX_NODES) && return
    id = objectid(x)
    id in walk.visited && return
    push!(walk.visited, id)
    walk.count += 1
    if x isa Cell
        v = try x[] catch; return end
        _walk_cells!(v, walk, depth + 1)
    elseif x isa Vector
        for el in x
            _walk_cells!(el, walk, depth + 1)
        end
    else
        for fn in fieldnames(typeof(x))
            f = try getfield(x, fn) catch; continue end
            _walk_cells!(f, walk, depth + 1)
        end
    end
    return
end

"""
    warm_application() -> document or nothing

Run the application once without a window, so that a build compiles what a
person does first: several file formats, a click in the Files pane, Enter on a
file, a key in a file, a save, and a new tab made with the Insert key. It works
in a temporary directory. Answers the application document, or `nothing` when
the warm-up failed. A failure is logged and does not stop the build.

The new tab gets its name one key at a time, as a person types it, with a
Backspace and a Delete on the way. The first key lists every document type that
the name buffer can make, and that list compiles a method for each type. Without
the warm-up, the first key waits for all of them.

It needs what a build of the binary loads: the console backend, which it finds
by the name of its type, and the JSON, Markdown and Julia formats of its files.
"""
function warm_application()
    directory = mktempdir()
    warmed = nothing
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
        document, projection = make_application_window(paths; root = directory,
            assistant = make_application_assistant(:ollama))
        scene = make_window_scene(document, "ProjecturEd"; width = 1280, height = 800)
        composed = make_window_scene_projection(projection;
            opened_window_projections = make_opened_window_projections(;
                content = make_application_content_projections()))
        editor = Editor(scene, composed; backend = default_backend((:ConsoleBackend,)),
                        devices = Device[Display(), Keyboard(), Mouse()])
        editor.iomap = print_document(composed, scene)
        evaluate_reachable_cells!(editor.iomap)
        # The press lands on the row of `b.md` in the Files pane, found by its
        # drawn name, so it follows the sizes of the theme; Enter opens that file.
        row = _find_drawn_text_point(get_iomap_output(editor.iomap).windows[1].content, "b.md")
        press = row === nothing ? Any[] : Any[MouseClick(:left, row[1], row[2], 1, ModifierKeys(); time = time())]
        events = Any[KeyDown(:down, ModifierKeys(); time = time()),
                     KeyPress('x'; time = time()),
                     press...,
                     KeyDown(:return, ModifierKeys(); time = time()),
                     KeyDown(:s, ModifierKeys(ctrl = true); time = time()),
                     # Ctrl+T opens a tab on an empty placeholder, Insert turns
                     # the placeholder into the name buffer, and Enter commits
                     # the typed name. Backspace takes the "y" back, and Left
                     # and Delete the "x", so "evaluator" is what commits.
                     KeyDown(:t, ModifierKeys(ctrl = true); time = time()),
                     KeyDown(:insert, ModifierKeys(); time = time()),
                     (KeyPress(c; time = time()) for c in "evaluatorxy")...,
                     KeyDown(:backspace, ModifierKeys(); time = time()),
                     KeyDown(:left, ModifierKeys(); time = time()),
                     KeyDown(:delete, ModifierKeys(); time = time()),
                     KeyDown(:return, ModifierKeys(); time = time())]
        for event in events
            change = read_intent(composed, nothing,
                                 Intent(WindowInput(:ProjecturEd, event)), editor.iomap)
            operation = change isa Intent ? change.operation : change
            operation isa Operation || continue
            editor.operation = operation
            evaluate_operation(editor, operation)
            # A command, such as the one of Ctrl+T, posts its operation, and a
            # frame of the editor applies what was posted.
            drain_operations!(editor)
            editor.iomap = print_document(composed, editor.document)
            evaluate_reachable_cells!(editor.iomap)
        end
        warmed = document
    catch err
        @warn "warm_application: the warm-up failed, and the build goes on" err
    finally
        rm(directory; recursive = true, force = true)
    end
    warmed
end

# A point inside the first drawn text `text` of a canvas tree, in the frame of
# `node`, or `nothing` when no element draws it.
function _find_drawn_text_point(node, text::AbstractString, x0::Int = 0, y0::Int = 0)
    node = unwrap_cell(node)
    node === nothing && return nothing
    x = hasproperty(node, :x) ? x0 + Int(unwrap_cell(node.x)) : x0
    y = hasproperty(node, :y) ? y0 + Int(unwrap_cell(node.y)) : y0
    if node isa GraphicsText
        return unwrap_cell(node.text) == text ? (x + 2, y + 2) : nothing
    elseif hasproperty(node, :elements)
        for element in unwrap_cell(node.elements)
            point = _find_drawn_text_point(element, text, x, y)
            point === nothing || return point
        end
    elseif hasproperty(node, :content)
        return _find_drawn_text_point(node.content, text, x, y)
    end
    nothing
end

"""
    start_application!(editor; mcp = false, assistant = :none, model = "")

What the application does once the editor exists: it declares the API of
[`make_application_api`](@ref) on the tools of the editor, and adds the `undo`
and `redo` tools. With `mcp`, the tools also get the meaning model of the
backend `assistant` names, with `model` (empty for its default), because an MCP
client runs no turn of the assistant and its searches by description rank by
meaning too.

[`run_application`](@ref) calls it between `build_editor` and `run_editor!`. A
host that opens the same window another way calls it too, so its assistant is
the one of the application.
"""
function start_application!(editor; mcp::Bool = false, assistant::Symbol = :none,
                            model::AbstractString = "")
    if hasproperty(editor, :tools)
        # What the assistant may write, and the whole of it. The verbs are
        # functions a model finds with `search_api` and calls through
        # `execute_julia_code`; they are not tools, so their descriptions cost
        # nothing until it asks.
        declare_api!(editor.tools, make_application_api())
        register_undo_tools!(editor.tools)
    end
    (mcp && assistant !== :none && hasproperty(editor, :tools)) || return nothing
    try
        bind_meaning_model!(editor.tools, make_llm(assistant; model = String(model)))
    catch err
        @warn "The searches get no meaning model" reason =
            first(split(sprint(showerror, err), '\n'))
    end
    nothing
end
