# Fragment of `ApplicationModule` — the ProjecturEd application: a window that
# shows what the editor holds, with the Explorer first, a tab for each file, and
# the assistant beside them.
#
# The main group and the assistant are the groups of a split, and the pane
# gestures rearrange them. Every file tab holds a `FileDocument`, so `Ctrl+S` saves
# and `F5` reloads it, and the Files tool, `Ctrl+O` and `Ctrl+P` open a file with
# `OpenFileOperation`.

"""
    APPLICATION_ASSISTANTS

The assistant backends [`run_application`](@ref) accepts: `:ollama`, `:anthropic`,
`:acp` for an external agent, and `:none` for a window without the assistant pane.
The backend `:acp` needs the package `ProjecturedACP`, which a person loads by
name.
"""
const APPLICATION_ASSISTANTS = (:ollama, :anthropic, :acp, :none)

"""
    get_application_greeting_text(backend::Symbol) -> String

What the assistant pane says before a person types anything, in Markdown: what
the window shows, the keys that open and save a file, and what the assistant
needs to answer. A key, an option of the command line and a name to type are
code spans.
"""
function get_application_greeting_text(backend::Symbol)
    body = """
        This window shows what the editor holds. The **Explorer** lists the working \
        directory, the open files, the tasks, the assistants and the tools of the \
        editor, and a press on a row shows its page beside the tree. Each other \
        tab holds one open file.

        `Ctrl+click` a row of the Explorer to open its page in a new tab. The **Files** \
        button of the toolbar lists the working directory, where `Enter` on a file \
        opens it in a new tab. `Ctrl+P` finds a file of the Explorer by its name, and \
        `Ctrl+O` opens a file with the Open dialog. `Ctrl+S` saves the tab that has the \
        focus, and `F5` reads it again from disk. `F1` lists the keys that work where the \
        focus is, and `Ctrl+Shift+P` runs a command by its name.

        `Alt+click` anything in a tab to select it, and `Alt` with an arrow to move \
        the selection. `Ctrl+C` copies what is selected, `Ctrl+X` cuts it, `Ctrl+N` \
        notes it, and `Ctrl+V` pastes it into a new tab from `Ctrl+T`.

        Ask me to read or change an open file, to explain its structure, or to \
        show a value in a new tab. I write Julia code and run it in this window: \
        I can open a path as a tab, save one back, arrange the panes, and build \
        a card, a table or a form to show you something.
        """
    requirement = backend === :none ?
        "No model backend is chosen, so I cannot answer yet. Choose one in the Start " *
        "settings of the Settings tab, or start the window with `--assistant=ollama`, " *
        "`--assistant=anthropic` or `--assistant=acp`." :
        backend === :anthropic ?
        "I use Claude. The environment variable `ANTHROPIC_API_KEY` must hold your key." :
        backend === :acp ?
        "I am an external agent that runs its own loop, through the Agent Client " *
        "Protocol (ACP). The package `ProjecturedACP` must be loaded. Without an agent " *
        "command I am Claude Code, which must be installed and signed in; with one, " *
        "that agent must be installed and signed in with its own sign-in. " *
        "`Escape` stops my turn." :
        "I use a local model through Ollama. The Ollama server must run on this " *
        "machine, and the model must be pulled."
    body * "\n" * requirement
end

"""
    make_application_assistant(backend::Symbol; model = "", context = 0, llm = nothing,
                               agent_command = DEFAULT_AGENT_COMMAND,
                               agent_session_meta = DEFAULT_AGENT_SESSION_META,
                               agent_mode = DEFAULT_AGENT_MODE,
                               system = make_application_system(; backend)) -> Assistant or nothing

The assistant pane of the application. `backend` is one of
[`APPLICATION_ASSISTANTS`](@ref). With `:none` the pane opens too: it says that no
model backend is chosen, and where to choose one, and a message that a person
sends there names the backends. An empty `model` means the default model of the backend,
and a `context` of `0` means its default token window. A given `llm` is the model
that the assistant asks, in place of the one it builds from `backend`, `model` and
`context`: a scripted model that stands in for the real one, or an `OllamaLlm`
with a `seed` and a `temperature`. `agent_command` is the command line of the
external agent of the backend `:acp`, `agent_session_meta` the JSON `_meta`
of its sessions, and `agent_mode` the mode of the tools that each of its sessions
starts in. `system` is the text of the window that the model reads, with
the index of the names for `backend` ([`make_application_system`](@ref)).
"""
function make_application_assistant(backend::Symbol; model::AbstractString = "",
                                    context::Integer = 0, llm = nothing,
                                    agent_command::AbstractString = DEFAULT_AGENT_COMMAND,
                                    agent_session_meta::AbstractString = DEFAULT_AGENT_SESSION_META,
                                    agent_mode::AbstractString = DEFAULT_AGENT_MODE,
                                    system::AbstractString = make_application_system(; backend))
    backend in APPLICATION_ASSISTANTS ||
        error("make_application_assistant: the backend must be one of ",
              join(APPLICATION_ASSISTANTS, ", "), ", not ", repr(backend))
    greeting = ConversationConversation([
        ConversationTurn(:assistant, [ConversationPart(make_prose_document(get_application_greeting_text(backend)))])])
    Assistant(; conversation = greeting, backend = backend, model = String(model),
                context = context, system = system,
                api_key = get(ENV, "ANTHROPIC_API_KEY", ""), llm = llm,
                agent_command = agent_command, agent_session_meta = agent_session_meta,
                agent_mode = agent_mode)
end

"""
    make_application_document(paths; root = pwd(), assistant = nothing,
                              settings = make_settings())

The document of the application window: an Explorer whose first entry is the
folder `root`, in front of its group, one file tab for each path behind it in the
same group, and the assistant when it is not `nothing`. The rest of the content of the Explorer comes
when the editor starts ([`start_application!`](@ref)). A path that does not
exist opens as the empty seed of its extension. Each history of the window keeps
as many steps as the `HistorySettings` of `settings` say.
"""
function make_application_document(paths::AbstractVector;
                                   root::AbstractString = pwd(), assistant = nothing,
                                   settings::Settings = make_settings())
    history = make_history_wrap(settings)
    tabs = [make_file_tab_content(path, history) for path in paths]
    # Each file tab holds a history of its own, so `Ctrl+Z` takes back an edit in
    # the file the person is looking at. The wrapper `undo` puts one around the
    # whole tree, so a splitter that moves, a tab that opens and a chat draft can
    # be taken back too.
    _make_application_pane_tree(tabs, root, assistant)
end

# The workspace of the folder the window lists.
function _make_application_folders(root::AbstractString)
    folder = abspath(root)
    Workspace([WorkspaceFolder(basename(folder), folder)])
end

# The file explorer of the folder the window lists, which the Files button of the
# toolbar opens.
_make_application_workspace(root::AbstractString) = WorkspaceExplorer(_make_application_folders(root))

# The main group, with the Explorer first and a tab for each file after it, and
# the assistant beside it. The focus starts on the root row of the tree of the
# Explorer, also when files are open, so the window opens on the Explorer and the
# assistant, and the first key reaches the tree and not the tab strip.
function _make_application_pane_tree(tabs, root::AbstractString, assistant)
    explorer = Explorer(ExplorerSection("Explorer", Any[_make_application_folders(root)]))
    main = PaneGroup(PaneTab[PaneTab("Explorer", explorer),
                             (PaneTab(get_document_title(tab), tab) for tab in tabs)...])
    groups = Any[main]
    weights = [1.0]
    if assistant !== nothing
        # The tab has no name of its own, so it shows the name of the assistant,
        # and the title that an external agent gives its session.
        push!(groups, PaneGroup(PaneTab[PaneTab("", assistant)]))
        weights = [0.68, 0.32]
    end
    tree = PaneTree(PaneSplit(:vertical, groups; weights = weights))
    tab = get_pane_tab_reference(tree, main, 1)
    set_selection!(tree, extend_reference(tab, FieldReferenceStep("content"), FieldReferenceStep("tree"),
                                          FieldReferenceStep("root")))
    tree
end

"""
    make_application_content_projections(; measure = FontFileMeasure(),
                                         appearance::Appearance = Appearance())
        -> Vector{Pair{Type,Any}}

How the application draws what a tab holds, in front of the defaults of
`NaturalToGraphics`: the Files pane, the assistant and its conversation, and
plain text. A document of a domain draws through the natural renderer, which
every loaded domain registers itself with, so the application names no domain.
A history around a file draws through the row that the undo slice registers.
"""
function make_application_content_projections(; measure = FontFileMeasure(),
                                               appearance::Appearance = Appearance())
    text_theme = get_scaled_theme!(appearance, TextTheme)
    text_to_graphics = ChainingProjection(WordWrapping(measure = measure),
                                          TextToGraphics(measure = measure, theme = text_theme))
    conversation_rows = Pair{Type,Any}[
        make_conversation_draft_row(measure = measure, appearance = appearance),
        make_conversation_row(measure = measure, appearance = appearance),
    ]
    Pair{Type,Any}[
        TextDocument      => text_to_graphics,
        # The file system slice registers a row for a workspace, and this one
        # overrides it for one reason: what a file opens WITH is the
        # application's choice, and a slice cannot know that this application
        # gives every file it opens a history.
        # The file system stage has no mark of its own, so a fault in it costs the
        # workspace, at the barrier of the renderer that draws it.
        # An explorer draws the folders of its workspace itself, with its own open
        # folders, so it comes before the row of any workspace document.
        WorkspaceExplorer => ChainingProjection(
            RecursiveProjection(FaultCatchingProjection(
                inner = FileSystemToWidget(),
                substitute = FaultToWidget())),
            RecursiveProjection(FaultCatchingProjection(
                inner = WidgetToGraphics(; measure = measure,
                                         theme = get_scaled_theme!(appearance, WidgetTheme),
                                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme),
                                         text_theme = get_scaled_theme!(appearance, TextTheme)),
                substitute = FaultToGraphics()))),
        WorkspaceDocument => ChainingProjection(
            RecursiveProjection(WorkspaceToFileSystem()),
            RecursiveProjection(FaultCatchingProjection(
                inner = FileSystemToWidget(),
                substitute = FaultToWidget())),
            RecursiveProjection(FaultCatchingProjection(
                inner = WidgetToGraphics(; measure = measure,
                                         theme = get_scaled_theme!(appearance, WidgetTheme),
                                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme),
                                         text_theme = get_scaled_theme!(appearance, TextTheme)),
                substitute = FaultToGraphics()))),
        # A tab of its own: the pane group hands the assistant's own split pane
        # to a fresh renderer, rather than re-entering the one already dispatching
        # on it — a tab's content is read through `print_child`, which does not
        # reduce a projection's own output to a fixpoint the way a top-level
        # print does, so a bare `Assistant => AssistantToWidgetSplitPane()` row
        # would hand the tab a widget, not the graphics it draws.
        Assistant         => ChainingProjection(RecursiveProjection(FaultCatchingProjection(
                                                    inner = AssistantToWidgetSplitPane(
                                                        get_scaled_theme!(appearance, ConversationTheme);
                                                        slot_padding = get_widget_style(
                                                            get_scaled_theme!(appearance, WidgetTheme),
                                                            :slot_padding),
                                                        button_gap = get_widget_style(
                                                            get_scaled_theme!(appearance, WidgetTheme),
                                                            :button_gap),
                                                        label_gap = get_widget_style(
                                                            get_scaled_theme!(appearance, WidgetTheme),
                                                            :label_gap)),
                                                    substitute = FaultToWidget())),
                                                NaturalToGraphics(measure = measure, extra = conversation_rows,
                                                                  appearance = appearance)),
        conversation_rows...,
        # A tab title and a plain text file are prose, not a quoted string.
        PrimitiveDocument => ChainingProjection(RecursiveProjection(FaultCatchingProjection(
                                                    inner = PrimitiveToText(; theme = text_theme),
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
                                     appearance::Appearance = Appearance())
    content = make_application_content_projections(; measure, appearance)
    _make_application_pane_projection(content, measure, appearance)
end

"""
    make_application_wrappers(; root = pwd(), assistant = nothing, status_bar = true,
                              measure = FontFileMeasure(),
                              appearance::Appearance = Appearance(),
                              document = nothing) -> NamedTuple

The wrappers of `build_editor` that the application window has, as keywords:
its undo, its chrome, the clipboard and the walk, F1 help, the command palette,
the gesture log, the message log, the statistics and the fault log, which fill
the tools of the toolbar, the list of the assistants of its tabs, which the
Assistants button of the toolbar opens, and the watch of the files that its tabs
show. **One place says which wrappers this binary has.** [`run_application`](@ref),
its workload [`run_application_workload`](@ref) and
[`make_application_window`](@ref) come here, so none of them holds a list of its
own.

The toolbar has the assistant when `assistant` is not `nothing`, a fresh one
with its backend, its model and its greeting, and its Files tool lists `root`.
`status_bar = false` leaves out the status bar, which a video that shows what
the window paints again uses, because the status bar changes with every move of
the caret. The clipboard offers all of its gestures: a person who edits a file
expects `Ctrl+X` to cut. A copy of an object writes its text to the system
clipboard, so another program and a paste at a caret get what was copied last.
`document` is the pane tree of the window: the gesture
log records into the first gesture log that its tabs show, which a file or a
take gave before the editor existed.
"""
make_application_wrappers(; root::AbstractString = pwd(), assistant = nothing,
                          status_bar::Bool = true, measure = FontFileMeasure(),
                          appearance::Appearance = Appearance(), document = nothing) =
    (; undo = true,
       shell = (; assistant = _make_assistant_factory(assistant),
                  files = _ -> _make_application_workspace(root),
                  status_bar, measure, appearance),
       clipboard = (; to_text = _make_clipboard_text),
       gesture_help = (; measure),
       command_palette = true,
       gesture_log = _make_gesture_log_option(document), message_log = true,
       frame_statistics = true, background_work = true, fault_log = true, assistant_list = true,
       file_change = true)

# The text that a copy of `document` writes to the system clipboard: the value of
# a primitive, the natural text of a document that has one, and an empty text for
# a document with none, so the system clipboard never keeps an older copy.
function _make_clipboard_text(document)
    document isa PrimitiveDocument && return string(something(document.value, ""))
    has_text = make_natural_projection(document, :string) !== nothing ||
               get_edited_field(document) !== nothing
    has_text ? print_natural_text(document) : ""
end

# The gesture log of a window records into the first gesture log that a tab of
# its pane tree shows, or into a new one.
function _make_gesture_log_option(document)
    logs = document isa PaneTree ? collect_pane_tab_contents(document, GestureLog) : GestureLog[]
    isempty(logs) ? true : (; log = first(logs))
end

"""
    make_application_window(paths; root = pwd(), assistant = nothing,
                            status_bar = true,
                            measure = FontFileMeasure(),
                            appearance::Appearance = Appearance())
        -> (document, projection)

The content of the application window with its wrappers, for a caller that
draws it in a window scene of its own, such as a test or a rehearsal: the document of [`make_application_document`](@ref) and the
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
    document = make_application_document(paths; root, assistant, settings)
    parts = make_editor_parts(document, make_application_projection(; measure, appearance);
                              appearance = false, settings = false,
                              make_application_wrappers(; root, assistant, status_bar, measure,
                                                          appearance, document)...)
    (parts.document, parts.projection)
end

_make_assistant_factory(::Nothing) = nothing
_make_assistant_factory(assistant::Assistant) =
    _ -> make_application_assistant(assistant.backend; model = assistant.model,
                                    context = assistant.context,
                                    agent_command = assistant.agent_command,
                                    agent_session_meta = assistant.agent_session_meta,
                                    agent_mode = assistant.agent_mode,
                                    system = assistant.system)

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
    make_editor_api() -> Vector{ApiEntry}

What the assistant of a window of the editor may write: every name of a loaded
module whose docstring has the mark `For the assistant.`
([`collect_marked_api`](@ref)), with every subtype of a marked type except the
placeholders that a domain makes for the editor ([`is_domain_placeholder`](@ref)),
and the names of the other packages that an
adapter registered with [`register_assistant_api!`](@ref), such as the verbs of
`DataFrames`, whose docstrings no mark can reach. Every name here is a name the
assistant reaches through `execute_julia_code`, and nothing else resolves.

The marks are read when it runs, so a window offers the verbs of every package
that it loads: the OMNeT++ IDE offers the verbs of its simulations beside those of
the editor, and the Projectured application offers those of each domain it loads.
"""
make_editor_api() =
    ApiEntry[collect_marked_api(; exclude = is_domain_placeholder)..., get_registered_assistant_api()...]

"""
    EDITOR_SYSTEM

The rules of every window of the editor, for its assistant: the tools, and how
to find, change and show a part. The text of a window holds it after what the
window is, and before its worked example ([`APPLICATION_SYSTEM`](@ref)). It names
the few verbs that the rules need; the index of the names, which
[`make_assistant_system`](@ref) adds, lists the rest.
"""
const EDITOR_SYSTEM =
    "HOW YOU WORK. You work in the window beside the person, with Julia code that " *
    "runs in the window.\n\n" *
    "Your tools:\n" *
    "- `execute_julia_code` runs Julia in the window. Put the whole source in its " *
    "`code` argument: a call with no code does nothing and costs the round. A " *
    "variable that one call binds at the top level is still bound in the next call. " *
    "The variable `editor` is the running editor, and a verb acts on it, so the code " *
    "does not pass it. Code that needs no document of the window, such as a long " *
    "computation, runs with `background` set to true, so the person can go on working.\n" *
    "- `search_api` finds the name to call: by words, by a pattern, or by a sentence " *
    "with the mode \"description\". One clear hit comes back with its whole documentation.\n" *
    "- `search_guides` finds a section of a guide: prose with worked examples. " *
    "`read_resource` reads a whole guide by the `resource://guide/…` name that a " *
    "search prints.\n" *
    "- `read_function_documentation` reads the documentation of one function.\n" *
    "- `undo` takes back the last change, as Ctrl+Z does, and `redo` puts it back. " *
    "`take_picture` shows you what the window draws.\n\n" *
    "The rules:\n" *
    "- NEVER guess a name or a signature: search for it, then act. When a signature " *
    "answers the request, call the verb; a keyword that you leave out takes its default.\n" *
    "- Find a part with a verb, and do not walk the tree of the window. " *
    "`find_pane(title)` answers a tab, `get_edited_document(tab)` the data that the tab " *
    "shows, `find_selected_part()` the part that the person selected, and " *
    "`search_documents(document, query; places = true)` the parts of a document that match. " *
    "A part acts like its data: index it, iterate it, read a field. " *
    "`print_natural_text(part)` answers its text.\n" *
    "- Change a document only with a verb, so the change is an edit that Ctrl+Z takes " *
    "back: `replace_referenced_value!`, `insert_elements!`, `delete_elements!` and " *
    "`run_command!`. Write a new value as the text of its domain, with " *
    "`parse_natural_text(format, text)`. `make_change` makes the change of a verb as a " *
    "value, and `apply_change!(combine_changes(changes...))` applies several changes as " *
    "one step of the undo.\n" *
    "- NEVER read files or run programs directly in code. Read a file with the verbs of " *
    "the editor, such as `open_file!` and `read_document_file`. Start a program as a task " *
    "with `run_tasks!`, so that the person sees it and can stop it.\n" *
    "- Show a result in a tab: `open_pane!(document; title)` puts a document in a tab " *
    "and answers the tab, and `show_pane!(tab)` brings that tab to the front when the " *
    "person must look at it. The focus of the person stays where it is: never call " *
    "`focus_pane!`. Only `select_part!` moves the selection of the person.\n" *
    "- Keep each object in its own numbered variable, such as items_1 and rows_1, " *
    "and use it again in a later call. The person edits the window between your turns, " *
    "so read a document again before you say what it holds.\n" *
    "- Call one tool per round. Answer the person in one or two short sentences: what " *
    "you did, or what you found."

"""
    APPLICATION_SYSTEM

The text of the application window for its assistant: what the window is, the
rules of every window ([`EDITOR_SYSTEM`](@ref)), and one worked example that
finds, reads, changes and shows. [`make_application_system`](@ref) adds the
domains and the index of the names.
"""
const APPLICATION_SYSTEM =
    "You are the assistant of ProjecturEd, a projectional editor built in Julia. Its " *
    "window shows the explorer of a folder, this conversation, and a tab for each file " *
    "or document that is open. A document is structured data, such as a JSON file, a " *
    "Markdown page, a table or a chart. The person edits it with keys and the mouse, " *
    "and you edit it with the same edits, from Julia code.\n\n" *
    EDITOR_SYSTEM * "\n\n" *
    "AN EXAMPLE: find, read, change, show. A tab shows items.json, a JSON array of " *
    "records with a name and a price. The first call finds the data and reads it:\n\n" *
    "    items_tab_1 = find_pane(\"items.json\")\n" *
    "    items_1 = get_edited_document(items_tab_1)\n" *
    "    println(print_natural_text(items_1))\n\n" *
    "The next call changes a price and adds a record at the end, as edits that Ctrl+Z " *
    "takes back, and shows the records in a table in a new tab:\n\n" *
    "    replace_referenced_value!(items_1[2][\"price\"], parse_natural_text(:json, \"12\"))\n" *
    "    item_1 = parse_natural_text(:json, \"\"\"{\"name\": \"lamp\", \"price\": 25}\"\"\")\n" *
    "    insert_elements!(items_1, length(items_1) + 1, [item_1])\n" *
    "    rows_1 = sort([[item[\"name\"].value, item[\"price\"].value] for item in items_1]; by = first)\n" *
    "    table_tab_1 = open_pane!(WidgetTable([\"name\", \"price\"], rows_1); title = \"Items by name\")\n" *
    "    show_pane!(table_tab_1)\n\n" *
    "A `JsonArray` acts as a vector and a `JsonObject` as a map from key to value; the " *
    "field value of a leaf is its plain value. The orientation guide, " *
    "resource://guide/guide/orientation, shows in code how to read what the person " *
    "does, draw in a tab, control the window, and work with files and tasks."

"""
    make_assistant_system(text, api; backend = :anthropic,
                          settings = AssistantIndexSettings()) -> String

The whole text that the assistant of a window reads: `text`, which says what the
window is, its rules and a worked example; the paragraph of the loaded domains
([`make_domain_system`](@ref)); and the index of the names that `api` declares,
in the size that the settings choose for `backend` ([`describe_api_index`](@ref)).
The built-in loop reads it as its system text, an external agent in its system
prompt after [`DEFAULT_AGENT_INSTRUCTIONS`](@ref), and an outside client of the
MCP server as the instructions of the server.
"""
make_assistant_system(text::AbstractString, api; backend::Symbol = :anthropic,
                      settings = AssistantIndexSettings()) =
    text * make_domain_system() *
    "\n\nTHE NAMES THAT YOU CAN WRITE, by module. `search_api` finds the documentation " *
    "of each.\n\n" * describe_api_index(api, backend; settings)

"""
    make_application_system(; backend = :anthropic, settings = AssistantIndexSettings()) -> String

The text that the assistant of this application reads:
[`APPLICATION_SYSTEM`](@ref), the loaded domains and the index of the names of
[`make_editor_api`](@ref), in the size for `backend`
([`make_assistant_system`](@ref)).
"""
make_application_system(; backend::Symbol = :anthropic, settings = AssistantIndexSettings()) =
    make_assistant_system(APPLICATION_SYSTEM, make_editor_api(); backend, settings)

"""
    make_domain_system() -> String

The paragraph of the system text that the loaded domains give: the sentence that
each domain registered with its names ([`describe_registered_assistant_api`](@ref)),
after a blank line, or an empty string when no loaded domain gave one. The system
text of every window holds it after [`EDITOR_SYSTEM`](@ref), so a window tells its
model about a domain exactly while the window loads that domain.
"""
function make_domain_system()
    domains = describe_registered_assistant_api()
    isempty(domains) ? "" : "\n\nTHE DOMAINS OF THIS WINDOW. " * domains
end

"""
    make_application_settings(file; fault_policy = nothing, assistant = nothing,
                              model = nothing, context = nothing, mcp = nothing,
                              agent_command = nothing)
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
                                   mcp::Union{Bool,Nothing} = nothing,
                                   agent_command::Union{AbstractString,Nothing} = nothing)
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
    agent_command === nothing || (start.agent_command = String(agent_command))
    settings
end

"""
    run_application(paths...; backend = nothing,
                    assistant = nothing, model = nothing, mcp = nothing,
                    mcp_host = nothing, mcp_port = nothing, root = pwd(),
                    context = nothing, agent_command = nothing,
                    width = nothing, height = nothing, fault_policy = nothing,
                    appearance = load_appearance!(Appearance()),
                    settings_file = get_settings_file())

Open the ProjecturEd application with the files at `paths`, and run it until the
window closes.

- `backend` is a constructed backend, for example `SdlBackend()` or
  `WebBackend()`. `nothing` takes the default backend.
- `assistant` is `:ollama`, `:anthropic`, `:acp` or `:none`, and `model` names
  the model of that backend; empty means its default. `:acp` is an external agent
  that `agent_command` starts, and it needs the package `ProjecturedACP`.
- `mcp` starts an MCP server beside the window, so an external client drives the
  same editor with the same tools. `mcp_host` and `mcp_port` say where it
  listens; each one that is `nothing` takes the default, `127.0.0.1` and `9876`.
- `root` is the directory the Files pane lists.
- `context` is how many tokens of the conversation the model may see; `0` leaves
  the backend's own answer. It matters for a local model, whose window costs
  memory on this machine.
- `assistant`, `model`, `mcp`, `context` and `agent_command` that are `nothing`
  take the `StartSettings` of the settings file, so a person sets them in the settings
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
                         agent_command::Union{AbstractString,Nothing} = nothing,
                         width = nothing, height = nothing,
                         fault_policy::Union{FaultPolicy,Nothing} = nothing,
                         measure = FontFileMeasure(),
                         appearance::Appearance = load_appearance!(Appearance()),
                         settings_file::Union{AbstractString,Nothing} = get_settings_file())
    settings = make_application_settings(settings_file; fault_policy, assistant, model,
                                         context, mcp, agent_command)
    backend === nothing && (backend = default_backend())
    editor = _make_application_editor(collect(String, paths), settings; backend, root,
                                      width, height, measure, appearance)
    # The Explorer shows what the last window of this folder showed, and keeps it
    # for the next start when the window closes. The first drain applies the load
    # after the acquire of the window, so a card of a file that a tab shows holds
    # the file document of that tab.
    file = get_explorer_content_file(root)
    post_operation!(editor, RestoreExplorerContentOperation(file; folder = root))
    mcp = get_settings_group!(settings, StartSettings).mcp
    # An outside client reads the text of the window as the instructions of the
    # server, with the full index.
    instructions = make_application_system(; backend = :mcp,
                                             settings = get_settings_group!(settings, AssistantIndexSettings))
    result = run_editor!(editor; mcp = mcp ? (; instructions, host = mcp_host, port = mcp_port) : false)
    save_explorer_content!(get_session_explorer_content(; editor), file; folder = root, editor)
    result
end

# The editor of the application window with the files at `paths` and the
# settings `settings`, built and started as `run_application` runs it. `llm`
# is the model of the assistant in place of the one that the settings name.
function _make_application_editor(paths::Vector{String}, settings; backend,
                                  root::AbstractString, width = nothing, height = nothing,
                                  measure = FontFileMeasure(), appearance::Appearance,
                                  llm = nothing)
    start = get_settings_group!(settings, StartSettings)
    index = get_settings_group!(settings, AssistantIndexSettings)
    chat = make_application_assistant(start.assistant; model = start.model,
                                      context = start.context, llm,
                                      agent_command = start.agent_command,
                                      agent_session_meta = start.agent_session_meta,
                                      agent_mode = start.agent_mode,
                                      system = make_application_system(; backend = start.assistant,
                                                                         settings = index))
    # The root is the application's own pane tree, so the tabs leave it as it is.
    # The settings carry the fault policy of the command line, and the first print
    # runs under it already.
    policy = make_fault_policy(get_settings_group!(settings, FaultSettings))
    document = make_application_document(paths; root, assistant = chat, settings)
    editor = build_editor(document,
                          make_application_projection(; measure, appearance);
                          backend, appearance, settings, fault_policy = policy,
                          # The natural projection draws what a tooltip holds. The
                          # other windows that a wrapper opens draw with the rows a
                          # pane draws with.
                          window = (; title = "ProjecturEd", width, height,
                                    opened_window_projections = vcat(
                                        Pair{Type,Any}[make_natural_tooltip_row(; measure, appearance)],
                                        make_application_content_projections(; measure, appearance))),
                          make_application_wrappers(; root, assistant = chat, measure, appearance,
                                                      document)...)
    start_application!(editor; mcp = start.mcp, assistant = start.assistant, model = start.model)
    editor
end

# ── The command line ─────────────────────────────────────────────────────────

"""
    parse_application_arguments(arguments) -> NamedTuple

The options of the command line of a window application, as the keywords of
[`run_application`](@ref) take them, plus `paths` and the backend name. `paths`
are the plain arguments, and the program says what they are: the files to open
for `projectured`. The backend name is `nothing` when the command line gives
none, and so are the assistant, the model, the context and `mcp`, so the
`StartSettings` of the settings file decide them. An unknown option or a wrong
value raises an error that names it.

`--mcp` starts the MCP server at its default address. `--mcp=PORT` and
`--mcp=HOST:PORT` start it too, and say where it listens: `mcp_host` and
`mcp_port` are then the values given, and `nothing` where the command line
gives none.

`--agent-command=COMMAND` is the command line of the external agent of
`--assistant=acp`, one argument that the shell quotes, as
`--agent-command="node /opt/claude-agent-acp/dist/index.js"`. Without it, the
built-in agent runs Claude Code.

The `--help` text of a binary lists the options that its build offers: the
builder writes it from `APPLICATION_OPTIONS`, and a test checks that this
function reads every option of that table. A binary refuses an option that its
help text does not list before this function reads the command line.
"""
function parse_application_arguments(arguments::AbstractVector{<:AbstractString})
    values = Dict{String,String}("root" => pwd())
    mcp = nothing
    mcp_host, mcp_port = nothing, nothing
    strict_fault_policy = false
    paths = String[]
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
            key in ("backend", "assistant", "model", "root", "context", "agent-command") ||
                error("unknown option $(repr(argument))")
            values[key] = String(value)
        elseif startswith(argument, "-")
            error("unknown option $(repr(argument))")
        else
            push!(paths, String(argument))
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
    (; paths, backend, assistant, model = get(values, "model", nothing),
       root = values["root"], mcp, mcp_host, mcp_port, context, strict_fault_policy,
       agent_command = get(values, "agent-command", nothing))
end

# The value of `--mcp=`: `PORT`, or `HOST:PORT`. The port follows the last colon.
function _parse_mcp_address(text::AbstractString)
    host, port_text = occursin(':', text) ? rsplit(text, ':'; limit = 2) : (nothing, text)
    port = tryparse(Int, port_text)
    (port === nothing || !(1 <= port <= 65535) || host == "") &&
        error("--mcp takes PORT or HOST:PORT, not ", repr(String(text)))
    (host === nothing ? nothing : String(host), port)
end

# Set for a binary that `restart_with_window_threads!` started, so it never
# starts itself again.
const _THREADS_RESTART_VARIABLE = "PROJECTURED_THREADS_RESTARTED"

"""
    restart_with_window_threads!(arguments) -> Union{Cint, Nothing}

Run the binary that runs now again, with `arguments` and the Julia option
`--threads=auto,2`, when the process has one interactive thread, and answer the
exit code of that run. The window of the new run gives each code unit an
interactive thread of its own, so a tool call never waits behind a long
computation ([`find_code_unit_thread_notice`](@ref)).

`nothing`, and nothing runs, when the process has a second interactive thread
already, when it is `julia` itself, as a script or a REPL is, which takes its
threads from its own command line, and in the run that this function started.
A `--julia-args` that the person gave the binary is not passed on.
"""
function restart_with_window_threads!(arguments)
    length(Threads.threadpooltids(:interactive)) >= 2 && return nothing
    haskey(ENV, _THREADS_RESTART_VARIABLE) && return nothing
    executable = unsafe_string(Base.JLOptions().julia_bin)
    startswith(basename(executable), "julia") && return nothing
    command = addenv(`$executable $arguments --julia-args --threads=auto,2`,
                     _THREADS_RESTART_VARIABLE => "1")
    process = run(ignorestatus(command))
    # A run that a signal ended answers as a shell does.
    Cint(process.termsignal == 0 ? process.exitcode : 128 + process.termsignal)
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

A built binary that runs with one interactive thread starts again with a second
one first ([`restart_with_window_threads!`](@ref)), and answers the exit code of
that run.
"""
function run_application_command(arguments; backends)
    restarted = restart_with_window_threads!(arguments)
    restarted === nothing || return restarted
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
        run_application(command.paths...;
                        backend = backends[backend](),
                        assistant = command.assistant, model = command.model,
                        mcp = command.mcp, mcp_host = command.mcp_host,
                        mcp_port = command.mcp_port, root = command.root,
                        context = command.context, agent_command = command.agent_command,
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

# ── The cells that a printed output reaches ──────────────────────────────────

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
    register_editor_tools!(set) -> set

Add to `set` the tools that every window of the editor gives its assistant beside
the default ones: `undo` and `redo`, which take back the last change and put it
back as Ctrl+Z and Ctrl+Shift+Z do, and `take_picture`, which shows the model
what the window draws. A host calls it on the tools of its editor when it
declares [`make_editor_api`](@ref) there.
"""
function register_editor_tools!(set)
    register_undo_tools!(set)
    register_picture_tools!(set)
    set
end

"""
    start_application!(editor; mcp = false, assistant = :none, model = "")

What the application does once the editor exists: it declares the API of
[`make_editor_api`](@ref) on the tools of the editor, adds the tools of
[`register_editor_tools!`](@ref), and posts the acquire of the documents of its tabs
(`AcquireDocumentOperation`), such as a sheet that computes its formulas. With `mcp`, the tools also get the meaning model of the
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
        declare_api!(editor.tools, make_editor_api())
        register_editor_tools!(editor.tools)
    end
    # The documents of the tabs enter the window: the acquire applies at the first
    # drain of the loop, so the start of the window runs no work of them.
    # The Explorer of the window shows the work of the session and the tools of the
    # editor after what the window brought, which exist once the editor does.
    editor isa Editor && _fill_explorer_content!(editor)
    editor isa Editor && post_operation!(editor, AcquireDocumentOperation(get_window_tree(editor.document)))
    # How to start Julia, when a tool call of this window has no thread of its own.
    # A build runs the window for its workload, and no person starts Julia there.
    if editor isa Editor && !Base.generating_output()
        notice = find_code_unit_thread_notice(editor.backend)
        notice === nothing || @warn notice
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
