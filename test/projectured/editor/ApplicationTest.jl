# Tests for the application window: it draws a file of every format that has a
# registered file document, a navigator gesture opens a file beside the other
# files, and Ctrl+S saves the file tab that has the focus. The events go
# through the same window scene that `run_application` runs, with no window on
# the screen.

using Test

# `evaluate_operation` reads `document` and `iomap` of an editor.
mutable struct _AppFakeEditor; document::Any; iomap::Any; end

function _app_fire(composed, iomap, event)
    change = read_intent(composed, nothing, Intent(WindowInput(:ProjecturEd, event)), iomap)
    change isa Intent ? change.operation : change
end

# The application gives the window a history and every file tab one of its own,
# so the document a test reaches for is inside a buffer and an operation a reader
# answers arrives recorded. Two helpers say so once, and the assertions below
# stay about what they were about.
_app_window(document) = get_wrapped_document(document)
_app_plain(operation) =
    operation isa WrappingOperation ? _app_plain(get_wrapped_operation(operation)) : operation

_app_count_tabs(tree::PaneTree) = sum(length(group.tabs) for group in get_pane_groups(tree))

# Every string a printed window draws, so a case asks what is on the screen and
# not what a document holds.
function _app_drawn_strings(node, found = String[])
    node === nothing && return found
    if hasproperty(node, :elements)
        foreach(element -> _app_drawn_strings(element, found), node.elements)
    elseif hasproperty(node, :text) && node.text isa AbstractString
        push!(found, String(node.text))
    elseif hasproperty(node, :content)
        _app_drawn_strings(node.content, found)
    end
    found
end

# One small file of each format in `dir`. `TestRun` is the `.pred` document of
# FileProjectTest.jl, in this module.
function _app_write_files(dir)
    register_pred_type!(TestRun)
    natural = [("a.json", :json, "{\"name\": \"Alice\", \"age\": 30}"),
               ("a.xml",  :xml,  "<a x=\"1\"><b/></a>"),
               ("a.yaml", :yaml, "name: Alice\nage: 30\n"),
               ("a.md",   :md,   "# Title\n\nSome text.\n"),
               ("a.rst",  :rst,  "Title\n=====\n\nSome text.\n"),
               ("a.math", :math, "a + b"),
               ("a.jl",   :jl,   "function f(x)\n    x + 1\nend\n"),
               ("a.sql",  :sql,  "SELECT a FROM t;")]
    paths = String[]
    for (name, format, text) in natural
        path = joinpath(dir, name)
        write_document_file(parse_natural_text(format, text), path)
        push!(paths, path)
    end
    for (name, document) in [("b.pdoc", parse_natural_text(:json, "[1, 2]")),
                             ("c.pred", TestRun(name = "run")),
                             ("notes.txt", PrimitiveString("one\ntwo"))]
        path = joinpath(dir, name)
        write_document_file(document, path)
        push!(paths, path)
    end
    paths
end

# The window scene and its reader state, as `run_application` builds them.
function _app_make_scene(paths, dir)
    document, projection = make_application_window(paths; root = dir, assistant = nothing)
    scene = make_window_scene(document, "ProjecturEd"; width = 1600, height = 1000)
    composed = make_window_scene_projection(projection;
        opened_window_projections = make_opened_window_projections(),
        screen_wrap = make_popup_screen_wrap())
    iomap = print_document(composed, scene)
    (document, scene, composed, iomap)
end

# Every string a printed window draws, at its position in the window. A cell is
# read for its value, because a printed tree holds cells.
_app_value(v) = v isa Cell ? _app_value(v[]) : v
function _app_drawn_at(node, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    node = _app_value(node)
    node === nothing && return found
    x = hasproperty(node, :x) ? ox + Int(_app_value(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_app_value(node.y)) : oy
    if hasproperty(node, :text) && _app_value(node.text) isa AbstractString
        push!(found, (String(_app_value(node.text)), x, y))
    elseif hasproperty(node, :elements)
        foreach(element -> _app_drawn_at(element, x, y, found), _app_value(node.elements))
    elseif hasproperty(node, :content)
        _app_drawn_at(node.content, x, y, found)
    end
    found
end

# The first height at which a double click on the navigator opens a file, and
# the operation it makes. The navigator is the leftmost part of the window.
function _app_find_file_row(composed, iomap)
    for y in 0:4:400
        operation = _app_fire(composed, iomap, MousePress(:left, 100, y, 2, ModifierKeys()))
        _app_plain(operation) isa OpenFileOperation && return (y, operation)
    end
    (nothing, nothing)
end

function test_application()
    @testset "application" begin
        @testset "the assistant pane" begin
            @test make_application_assistant(:none) === nothing
            assistant = make_application_assistant(:ollama; model = "small")
            @test assistant isa Assistant
            @test assistant.backend === :ollama && assistant.model == "small"
            @test_throws ErrorException make_application_assistant(:unknown)
            @test occursin("ANTHROPIC_API_KEY", get_application_greeting_text(:anthropic))
        end

        @testset "the assistant's verbs" begin
            api = make_application_api()
            names = Set{Symbol}()
            for entry in api
                entry isa Pair && union!(names, last(entry))
            end
            # One vocabulary from each of the four, so a missing concatenation
            # shows here and not in a window.
            @test :open_pane! in names          # the pane arranges the window
            @test :WidgetTable in names         # a widget shows a value
            @test :make_file_tab in names       # a path becomes a tab
            @test :Workspace in names           # the navigator lists a tree

            # A declared surface is what `search_api` answers. Without it the
            # search indexes the kernel's own modules and a person asking to open
            # a file is told about cells.
            set = declare_api!(ToolSet(), api)
            @test occursin("make_file_tab", search_api(set, "make_file_tab"))
            # And the declaration BOUNDS the surface. A kernel name the window
            # does not offer is refused, and the refusal lists what may be
            # written instead. Undeclared, the same search answers the kernel's
            # own modules, and a person asking how to open a file is told about
            # printers and cells.
            refusal = search_api(set, "print_document")
            @test occursin("No API matches", refusal)
            @test occursin("FileFormatModule: make_file_tab", refusal)
            @test !occursin("No API matches", search_api(ToolSet(), "print_document"))

            @test occursin("FileFormatModule", APPLICATION_SYSTEM)
            @test startswith(APPLICATION_SYSTEM, DEFAULT_ASSISTANT_SYSTEM)
        end

        @testset "the command line" begin
            command = parse_application_arguments(String[])
            @test command.files == String[]
            @test command.backend === nothing && command.assistant === :ollama
            @test command.model == "" && !command.mcp
            @test command.context == 0 && !command.strict_fault_policy
            command = parse_application_arguments(
                ["a.json", "--backend=web", "--assistant=none",
                 "--model=small", "--root=/tmp", "--mcp", "--context=8192",
                 "--strict-fault-policy", "b.md"])
            @test command.files == ["a.json", "b.md"]
            @test command.backend === :web
            @test command.assistant === :none && command.model == "small"
            @test command.root == "/tmp" && command.mcp
            @test command.context == 8192 && command.strict_fault_policy
            # The gesture log is read in a tab, which View opens, so no switch
            # turns it on.
            @test_throws ErrorException parse_application_arguments(["--gesture-log"])
            @test_throws ErrorException parse_application_arguments(["--context=many"])
            @test_throws ErrorException parse_application_arguments(["--context=-1"])
            @test_throws ErrorException parse_application_arguments(["--colour=red"])
            @test_throws ErrorException parse_application_arguments(["-x"])
            @test_throws ErrorException parse_application_arguments(["--assistant=gpt"])
            # A wrong command line answers 1 and opens no window.
            quiet = devnull
            @test redirect_stderr(() -> run_application_command(["--assistant=gpt"];
                                                                backends = (sdl = () -> nothing,)),
                                  quiet) == 1
            @test redirect_stderr(() -> run_application_command(["--backend=web"];
                                                                backends = (sdl = () -> nothing,)),
                                  quiet) == 1
            # A program that fails answers 2, and it prints the stack as well
            # as the message.
            report = mktemp() do path, io
                code = redirect_stderr(() -> run_application_command(String[];
                                           backends = (sdl = () -> error("no display"),)),
                                       io)
                close(io)
                (code, read(path, String))
            end
            @test first(report) == 2
            @test occursin("no display", last(report)) && occursin("Stacktrace", last(report))
            # The `--help` text of a binary names exactly the options the
            # parser takes.
            usage = make_projectured_usage([:sdl, :web])
            flags = Set(first(split(label, '=')) for (label, _) in usage.options)
            @test flags == Set(["--backend", "--assistant", "--model",
                                "--root", "--mcp", "--context",
                                "--strict-fault-policy"])
            # A flag and the keyword it sets spell the same words, a flag with
            # a hyphen and a keyword with an underscore, so
            # `--strict-fault-policy` is `strict_fault_policy`.
            for flag in flags
                @test haskey(pairs(parse_application_arguments(String[])),
                             Symbol(replace(flag[3:end], '-' => '_')))
            end
            @test !any(label -> startswith(first(label), "--backend"),
                       make_projectured_usage([:sdl]).options)
        end

        @testset "the warm-up of a build" begin
            document = @test_logs min_level = Base.CoreLogging.Warn warm_application()
            # The warm-up ends in the tab it made with the Insert key, and the tab
            # holds the document that the typed name commits. A warm-up that
            # stops short of it leaves the first key in the name buffer to compile.
            @test document !== nothing
            focus = get_pane_focus(_app_window(document))
            @test focus !== nothing && focus[1].tabs[focus[2]].content isa EvaluatorToplevel
        end

        dir = mktempdir()
        paths = _app_write_files(dir)
        @testset "the application window" begin
            @testset "every format draws" begin
                # `.pdoc` is the binary snapshot format, registered under no
                # `FileDocument` type — `make_file_tab` cannot open it as a
                # file tab, so the sweep skips what it cannot open.
                openable = [p for p in paths if has_file_document_type(p)]
                for path in vcat([String[]], [[p] for p in openable])
                    document, projection = make_application_window(path; root = dir,
                        assistant = make_application_assistant(:ollama))
                    errors, _ = walk_printer_output(document, projection)
                    @test isempty(errors)
                end
            end

            @testset "Ctrl+S saves the focused file" begin
                json = joinpath(dir, "a.json")
                document, scene, composed, iomap = _app_make_scene([json], dir)
                editor = _AppFakeEditor(scene, iomap)
                operation = _app_fire(composed, iomap, KeyDown(:s, ModifierKeys(ctrl = true)))
                @test _app_plain(operation) isa SaveFileOperation
                tab = _app_plain(operation).file
                @test tab.filename == json
                get_wrapped_document(tab.content).entries[1].value.value = "Bob"
                evaluate_operation(editor, operation)
                @test occursin("Bob", read(json, String))
                write_document_file(parse_natural_text(:json, "{\"name\": \"Alice\", \"age\": 30}"), json)
            end

            @testset "the window is filled by its chrome and its panes" begin
                # The shell has no size of its own and takes the window's, so the
                # panes share the whole window, every menu of the menu bar is
                # inside it, and the status line runs along the bottom edge.
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                drawn = _app_drawn_at(print_document(composed, scene).output.windows[1].content)
                at(name) = [(x, y) for (text, x, y) in drawn if text == name]
                (file_x, file_y), (view_x, view_y) = only(at("File")), only(at("View"))
                @test view_y == file_y
                @test file_x < view_x < 1600 - 40
                # The files take four fifths of the width: their tab starts past
                # the first fifth, where a pane tree that hugged its content
                # ended.
                @test maximum(x for (x, _) in at("a.json")) > 0.15 * 1600
                # The status line: something drawn in the last band of the window.
                @test any(((_, _, y),) -> 1000 - 40 <= y < 1000, drawn)
            end

            @testset "View opens the gesture log in a tab, and the window draws it" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = _AppFakeEditor(scene, iomap)
                drawn() = _app_drawn_strings(print_document(composed, scene).output.windows[1].content)
                @test !any(text -> occursin("Gestures", text), drawn())
                function walk(node)
                    if node isa WidgetMenuItem
                        string(node.action.label) == "Gesture log" && return node.action
                        node.submenu isa WidgetMenu && return walk(node.submenu)
                    elseif node isa WidgetMenu
                        for element in node.elements
                            found = walk(element)
                            found === nothing || return found
                        end
                    end
                    nothing
                end
                action = walk(make_window_menu_bar())
                @test action !== nothing
                evaluate_operation(editor, InvokeActionOperation(action))
                tabs = [tab for group in get_pane_groups(_app_window(document)) for tab in group.tabs]
                @test count(tab -> tab.content === get_session_gesture_log(), tabs) == 1
                @test any(text -> occursin("Gestures", text), drawn())
            end

            @testset "the toolbar holds the tools, and draws no word" begin
                document, scene, composed, _ = _app_make_scene(paths[1:1], dir)
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                # A window opened with no assistant has no assistant button.
                @test [string(item.action.label) for item in toolbar.elements] ==
                      ["Explorer", "Evaluator", "Message log", "Gesture log", "Fault log",
                       "Statistics", "Selection"]
                drawn = _app_drawn_strings(print_document(composed, scene).output.windows[1].content)
                for word in ("New tab", "Evaluator", "Message log", "Fault log", "Statistics")
                    @test !any(text -> occursin(word, text), drawn)
                end
            end

            @testset "a closed assistant and a closed navigator come back as they were" begin
                started = make_application_assistant(:ollama; model = "small", context = 4096)
                document, _ = make_application_window(paths[1:1]; root = dir,
                                                      assistant = started)
                tree = _app_window(document)
                editor = _AppFakeEditor(document, nothing)
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button(label) = only(item for item in toolbar.elements
                                     if string(item.action.label) == label)
                holding(type) = [(group, index) for group in get_pane_groups(tree)
                                 for (index, tab) in enumerate(group.tabs)
                                 if get_wrapped_document(tab.content) isa type]
                close!(type) = begin
                    (group, index) = only(holding(type))
                    apply_pane_operation!(tree, make_pane_close_tab_operation(tree, group, index))
                end
                @test [string(item.action.label) for item in toolbar.elements][2] == "Assistant"

                # While the assistant is open, the button reaches it and makes none.
                evaluate_operation(editor, InvokeActionOperation(button("Assistant").action))
                @test length(holding(Assistant)) == 1
                (group, index) = only(holding(Assistant))
                @test get_wrapped_document(group.tabs[index].content) === started

                # Closed, it comes back with the backend, the model, the window
                # of tokens and the greeting of the one the window opened with.
                close!(Assistant)
                @test isempty(holding(Assistant))
                evaluate_operation(editor, InvokeActionOperation(button("Assistant").action))
                (group, index) = only(holding(Assistant))
                again = get_wrapped_document(group.tabs[index].content)
                @test again !== started
                @test again.backend === :ollama
                @test again.model == "small"
                @test again.context == 4096
                @test get_pane_tab_title_string(group.tabs[index]) == "Assistant"
                greeting(assistant) = string(assistant.conversation.turns[1].parts[1].content)
                @test greeting(again) == greeting(started)
                @test occursin("Ollama", greeting(again))

                # The navigator comes back over the folder the window lists.
                close!(Workspace)
                evaluate_operation(editor, InvokeActionOperation(button("Explorer").action))
                (group, index) = only(holding(Workspace))
                @test get_wrapped_document(group.tabs[index].content).folders[1].pathname == abspath(dir)
            end

            @testset "the navigator opens a file beside the files" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = _AppFakeEditor(scene, iomap)
                y, operation = _app_find_file_row(composed, iomap)
                @test _app_plain(operation) isa OpenFileOperation
                @test basename(_app_plain(operation).path) == "a.jl"    # the first file row
                before = _app_count_tabs(_app_window(document))
                evaluate_operation(editor, operation)
                @test _app_count_tabs(_app_window(document)) == before + 1
                groups = get_pane_groups(_app_window(document))
                @test length(groups[1].tabs) == 1       # the navigator stays alone
                @test length(groups[2].tabs) == 2       # the file joins the files

                # A single click selects the row, and Enter opens it.
                selection = _app_fire(composed, iomap, MousePress(:left, 100, y, 1, ModifierKeys()))
                @test _app_plain(selection) isa CompoundOperation
                evaluate_operation(editor, selection)
                opened = _app_fire(composed, iomap, KeyDown(:return, ModifierKeys()))
                @test _app_plain(opened) isa OpenFileOperation
                @test _app_plain(opened).path == _app_plain(operation).path
            end
        end
        rm(dir; recursive = true)
    end
end
