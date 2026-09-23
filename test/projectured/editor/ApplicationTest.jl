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

# Every live caret a printed window draws, at its position in the window. A text
# layer draws its caret as a black rectangle two pixels wide, and a caret the
# keyboard is not on in a muted color.
function _app_drawn_carets(node, ox = 0, oy = 0, found = Tuple{Int,Int}[])
    node = _app_value(node)
    node === nothing && return found
    x = hasproperty(node, :x) ? ox + Int(_app_value(node.x)) : ox
    y = hasproperty(node, :y) ? oy + Int(_app_value(node.y)) : oy
    if node isa GraphicsRect
        _app_value(node.w) == 2 && _app_value(node.h) > 0 &&
            _app_value(node.color) == color_black && push!(found, (x, y))
    elseif hasproperty(node, :elements)
        foreach(element -> _app_drawn_carets(element, x, y, found), _app_value(node.elements))
    elseif hasproperty(node, :content)
        _app_drawn_carets(node.content, x, y, found)
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
            @test command.mcp_host === nothing && command.mcp_port === nothing
            @test command.context == 8192 && command.strict_fault_policy
            # `--mcp=PORT` and `--mcp=HOST:PORT` start the server as `--mcp`
            # does, at the address they give.
            command = parse_application_arguments(["--mcp=9000"])
            @test command.mcp && command.mcp_host === nothing && command.mcp_port == 9000
            command = parse_application_arguments(["--mcp=0.0.0.0:9001"])
            @test command.mcp && command.mcp_host == "0.0.0.0" && command.mcp_port == 9001
            @test !parse_application_arguments(String[]).mcp
            for wrong in ("--mcp=", "--mcp=port", "--mcp=:9000", "--mcp=host:",
                          "--mcp=70000", "--mcp=0")
                @test_throws ErrorException parse_application_arguments([wrong])
            end
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
            # The binary takes both forms of `--mcp`: the flag alone, and the
            # flag with the address.
            @test "--mcp" in collect_option_flags(usage)
            @test "--mcp=" in collect_option_flags(usage)
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
            @testset "a verb focuses a pane through the readers, and every level holds its part" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:2], dir)
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                files = find_pane_reference(editor, "Files")
                @test evaluate_reference(scene, files) isa PaneTab
                @test get_pane_tab_title_string(evaluate_reference(scene, files)) == "Files"
                @test find_pane_reference(editor, "no such pane") === nothing
                @test_throws ArgumentError focus_pane!(editor, nothing)
                # The verb's operation is the one a press on the title of the tab makes.
                (_, x, y) = only(item for item in _app_drawn_at(get_iomap_output(iomap).windows[1].content)
                                 if item[1] == "Files")
                pressed = _app_fire(composed, iomap, MousePress(:left, x + 4, y + 4, 1, ModifierKeys()))
                @test repr(_app_plain(make_focus_pane_operation(editor, files))) == repr(_app_plain(pressed))
                focus_pane!(editor, files)
                # Each level from the root down holds its suffix of one path.
                tab = "root.elements[1].tabs[1]"
                level(node) = repr(strip_reference_types(get_selection(node)))
                @test level(document) == ".content.content.content." * tab
                @test level(document.content) == ".content.content." * tab
                @test level(document.content.content) == ".content." * tab
                @test level(_app_window(document)) == "." * tab
                # So Ctrl+C copies the pane that has the focus.
                copy = _app_fire(composed, editor.iomap, KeyDown(:c, ModifierKeys(ctrl = true)))
                copy isa Operation && evaluate_operation(editor, copy)
                @test document.slice isa Workspace
            end

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

            @testset "the Evaluator button opens an evaluator, and Enter evaluates what is typed" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                # A real editor, because an evaluation reads the tools of the editor.
                # The iomap stands, as it does in a live editor, so what is drawn
                # is what the cells follow and not what a fresh print shows.
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && evaluate_operation(editor, operation)
                    operation
                end
                drawn() = _app_drawn_strings(get_iomap_output(editor.iomap).windows[1].content)
                drawn_at() = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                carets() = _app_drawn_carets(get_iomap_output(editor.iomap).windows[1].content)
                y_of(word) = only(y for (text, _, y) in drawn_at() if text == word)
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button = only(item for item in toolbar.elements
                              if string(item.action.label) == "Evaluator")
                evaluate_operation(editor, InvokeActionOperation(button.action))
                (group, index) = get_pane_focus(_app_window(document))
                evaluator = get_wrapped_document(group.tabs[index].content)
                @test evaluator isa EvaluatorToplevel
                # The tab draws the prompt of the form, and not the canvas of the
                # form as a tree of its fields.
                @test ">" in drawn() && !("=" in drawn())
                @test !any(text -> occursin("GraphicsCanvas", text), drawn())
                # The keys reach the form, and Enter reaches the editor.
                for character in "1 + 41"
                    press!(KeyPress(character))
                end
                @test evaluator.elements[1].form.value == "1 + 41"
                @test !any(text -> occursin("42", text), drawn())
                @test _app_plain(press!(KeyDown(:return, ModifierKeys()))) isa
                      EvaluateSelectedFormOperation
                @test length(evaluator.elements) == 2
                # One caret, and it is in the fresh form below the result: the
                # form that was evaluated shows none.
                @test "42" in drawn()
                @test length(carets()) == 1
                @test only(carets())[2] > y_of("42")
                # Shift+Enter breaks the line, and Enter evaluates both lines.
                for character in "x = 1"
                    press!(KeyPress(character))
                end
                press!(KeyDown(:return, ModifierKeys(shift = true)))
                for character in "x + 1"
                    press!(KeyPress(character))
                end
                @test evaluator.elements[2].form.value == "x = 1\nx + 1"
                @test length(evaluator.elements) == 2
                @test y_of("x + 1") > y_of("x = 1")
                press!(KeyDown(:return, ModifierKeys()))
                @test length(evaluator.elements) == 3
                @test "2" in drawn()
                @test length(carets()) == 1
                @test only(carets())[2] > y_of("2")
                # The prompts stand in one column. The second line of the code and
                # the result stand right of it, where the code starts.
                x_of(word) = only(x for (text, x, _) in drawn_at() if text == word)
                prompts_x = unique(x for (text, x, _) in drawn_at() if text in (">", "="))
                @test length(prompts_x) == 1
                @test x_of("x + 1") == x_of("x = 1") == x_of("2") > only(prompts_x)
            end

            @testset "Up and Down in the evaluator recall its history through the window" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && evaluate_operation(editor, operation)
                    operation
                end
                key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...))
                type!(text) = foreach(character -> press!(KeyPress(character)), text)
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button = only(item for item in toolbar.elements
                              if string(item.action.label) == "Evaluator")
                evaluate_operation(editor, InvokeActionOperation(button.action))
                (group, index) = get_pane_focus(_app_window(document))
                evaluator = get_wrapped_document(group.tabs[index].content)
                shown() = evaluator.elements[length(evaluator.elements)].form.value
                caret() = last(get_reference_steps(strip_reference_types(evaluator.selection)))
                type!("a = 1")
                press!(key(:return))
                type!("b = 2")
                press!(key(:return; shift = true))
                type!("b + 1")
                press!(key(:return))
                @test length(evaluator.elements) == 3
                # Up recalls the newest form, with the caret at the end of its
                # second line.
                press!(key(:up))
                @test shown() == "b = 2\nb + 1"
                @test caret() == RangeReferenceStep(11, 11)
                # On the second line, Up moves the caret to the first line.
                press!(key(:up))
                @test shown() == "b = 2\nb + 1"
                @test caret().start < 6
                # On the first line, Up goes further back.
                press!(key(:up))
                @test shown() == "a = 1"
                press!(key(:down))
                @test shown() == "b = 2\nb + 1"
                press!(key(:down))
                @test shown() == ""
                # The forms above keep their code.
                @test [print_natural_text(evaluator.elements[1].form),
                       evaluator.elements[2].form.value] == ["a = 1", "b = 2\nb + 1"]
            end

            @testset "a structured form takes keys through the window, and Enter evaluates it" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && evaluate_operation(editor, operation)
                    operation
                end
                type!(text) = foreach(character -> press!(KeyPress(character)), text)
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button = only(item for item in toolbar.elements
                              if string(item.action.label) == "Evaluator")
                evaluate_operation(editor, InvokeActionOperation(button.action))
                (group, index) = get_pane_focus(_app_window(document))
                evaluator = get_wrapped_document(group.tabs[index].content)
                # A press on the box before "Structured forms" turns the option on,
                # and the form the caret is in becomes a hole.
                (x, y) = only((x, y) for (text, x, y) in
                              _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                              if text == "Structured forms")
                @test _app_plain(press!(MousePress(:left, x - 17, y + 12, 1, ModifierKeys()))) isa
                      ToggleEvaluatorOptionOperation
                @test evaluator.type_structured_forms
                @test evaluator.elements[1].form isa JuliaInsertion
                type!("1+1")
                @test evaluator.elements[1].form.value == "1+1"
                # Enter evaluates the form. The hole's own Enter, which commits in
                # place, does not win.
                @test _app_plain(press!(KeyDown(:return, ModifierKeys()))) isa
                      EvaluateSelectedFormOperation
                @test length(evaluator.elements) == 2
                @test evaluator.elements[1].form isa JuliaBinaryOperation
                @test evaluator.elements[2].form isa JuliaInsertion
                content = get_iomap_output(editor.iomap).windows[1].content
                drawn_at = _app_drawn_at(content)
                twos = [y for (text, _, y) in drawn_at if text == "2"]
                @test !isempty(twos)
                # One caret, in the fresh hole, below the result.
                carets = _app_drawn_carets(content)
                @test length(carets) == 1
                @test only(carets)[2] > maximum(twos)
            end

            @testset "a noted object pasted into a form runs as itself, and its tab draws the change" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && evaluate_operation(editor, operation)
                    operation
                end
                type!(text) = foreach(character -> press!(KeyPress(character)), text)
                drawn() = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                at(word) = [(x, y) for (text, x, y) in drawn() if text == word]
                # Alt+click on the JSON of the file tab selects the file, and Ctrl+N
                # notes it: the clipboard holds the file itself.
                (ax, ay) = first((x, y) for (text, x, y) in drawn() if occursin("Alice", text))
                press!(MousePress(:left, ax + 5, ay + 5, 1, ModifierKeys(alt = true)))
                press!(KeyDown(:n, ModifierKeys(ctrl = true)))
                noted = only(search_documents(document, node -> node isa ClipboardSlice)).slice
                @test noted isa JsonFile
                # The evaluator, with structured forms, takes code that names `x`.
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button = only(item for item in toolbar.elements
                              if string(item.action.label) == "Evaluator")
                evaluate_operation(editor, InvokeActionOperation(button.action))
                (group, index) = get_pane_focus(_app_window(document))
                evaluator = get_wrapped_document(group.tabs[index].content)
                (sx, sy) = only(at("Structured forms"))
                press!(MousePress(:left, sx - 17, sy + 12, 1, ModifierKeys()))
                # The application keeps the content of a file in its undo buffer.
                type!("x.content.content.entries[1].value.value = \"Bob\"")
                # Tab commits the hole into a tree of the code.
                press!(KeyDown(:tab, ModifierKeys()))
                # Alt+click on `x` selects it whole, and Ctrl+V puts the noted file
                # there, which the code draws as its label.
                (xx, xy) = only(at("x"))
                press!(MousePress(:left, xx + 3, xy + 5, 1, ModifierKeys(alt = true)))
                press!(KeyDown(:v, ModifierKeys(ctrl = true)))
                @test "⟨a.json⟩" in [text for (text, _, _) in drawn()]
                @test _app_plain(press!(KeyDown(:return, ModifierKeys()))) isa
                      EvaluateSelectedFormOperation
                @test !evaluator.elements[1].is_error
                # The evaluation changed the file itself, so its tab, brought to the
                # front again, draws the new value and not the old one.
                @test occursin("Bob", print_natural_text(noted.content.content))
                (tx, ty) = last(sort(at("a.json")))
                press!(MousePress(:left, tx + 5, ty + 5, 1, ModifierKeys()))
                texts = [text for (text, _, _) in drawn()]
                @test any(text -> occursin("Bob", text), texts)
                @test !any(text -> occursin("Alice", text), texts)
            end

            @testset "Copy reference pastes code into a form that gives the selected object" begin
                # The system clipboard of the machine is left alone.
                buffer = Ref("")
                set_os_clipboard_backend!(read = () -> buffer[], write = text -> (buffer[] = text; true))
                try
                    document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                    editor = Editor(ConsoleBackend(), scene, composed,
                                    Device[Display(), Keyboard(), Mouse()])
                    editor.iomap = iomap
                    press!(event) = begin
                        operation = _app_fire(composed, editor.iomap, event)
                        operation isa Operation && evaluate_operation(editor, operation)
                        operation
                    end
                    drawn() = _app_drawn_at(get_iomap_output(editor.iomap).windows[1].content)
                    selected() = try_evaluate_reference(scene, getfield(scene, :selection)[], missing)
                    copy_reference!() = _app_plain(press!(KeyDown(:c, ModifierKeys(ctrl = true, shift = true))))
                    (ax, ay) = first((x, y) for (text, x, y) in drawn() if occursin("Alice", text))
                    # Alt+click selects the file whole, and Ctrl+Shift+C copies its
                    # reference as code.
                    press!(MousePress(:left, ax + 5, ay + 5, 1, ModifierKeys(alt = true)))
                    file = selected()
                    @test file isa JsonFile
                    @test copy_reference!() isa CopyReferenceOperation
                    @test startswith(buffer[], "evaluate_reference(editor.document, @reference(editor.document, ")
                    code = buffer[]
                    # Ctrl+V at the caret of a form types the code, and Enter gives the
                    # file itself.
                    toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                    button = only(item for item in toolbar.elements
                                  if string(item.action.label) == "Evaluator")
                    evaluate_operation(editor, InvokeActionOperation(button.action))
                    (group, index) = get_pane_focus(_app_window(document))
                    evaluator = get_wrapped_document(group.tabs[index].content)
                    # A tool that the toolbar opens leaves the complete selection
                    # unwritten from the root, and the clipboard reads that selection.
                    # A click on typed text writes it: type a character, click after
                    # it, and delete it again.
                    press!(KeyPress('q'))
                    (qx, qy) = only((x, y) for (text, x, y) in drawn() if text == "q")
                    press!(MousePress(:left, qx + 8, qy + 5, 1, ModifierKeys()))
                    press!(KeyDown(:backspace, ModifierKeys()))
                    @test evaluator.elements[1].form.value == ""
                    press!(KeyDown(:v, ModifierKeys(ctrl = true)))
                    @test evaluator.elements[1].form.value == code
                    press!(KeyDown(:return, ModifierKeys()))
                    @test !evaluator.elements[1].is_error
                    @test evaluator.elements[1].result === file
                finally
                    reset_os_clipboard_backend!()
                end
            end

            @testset "an evaluated form draws as Julia, and a form with a comment as typed" begin
                document, scene, composed, iomap = _app_make_scene(paths[1:1], dir)
                editor = Editor(ConsoleBackend(), scene, composed,
                                Device[Display(), Keyboard(), Mouse()])
                editor.iomap = iomap
                press!(event) = begin
                    operation = _app_fire(composed, editor.iomap, event)
                    operation isa Operation && evaluate_operation(editor, operation)
                    operation
                end
                toolbar = only(search_documents(document, node -> node isa WidgetToolbar))
                button = only(item for item in toolbar.elements
                              if string(item.action.label) == "Evaluator")
                evaluate_operation(editor, InvokeActionOperation(button.action))
                (group, index) = get_pane_focus(_app_window(document))
                evaluator = get_wrapped_document(group.tabs[index].content)
                for code in ("GraphicsCircle(10, 10, 10)", "x = 1  # why")
                    foreach(character -> press!(KeyPress(character)), code)
                    press!(KeyDown(:return, ModifierKeys()))
                end
                @test evaluator.elements[1].form isa JuliaCall
                @test evaluator.elements[2].form isa PrimitiveString
                content = get_iomap_output(editor.iomap).windows[1].content
                drawn_at = _app_drawn_at(content)
                texts = [text for (text, _, _) in drawn_at]
                x_of(word) = only(x for (text, x, _) in drawn_at if text == word)
                y_of(word) = only(y for (text, _, y) in drawn_at if text == word)
                function colors(node, found = Dict{String,Any}())
                    node = _app_value(node)
                    node === nothing && return found
                    if node isa GraphicsText
                        found[String(_app_value(node.text))] = _app_value(node.color)
                    elseif hasproperty(node, :elements)
                        foreach(element -> colors(element, found), _app_value(node.elements))
                    elseif hasproperty(node, :content)
                        colors(node.content, found)
                    end
                    found
                end
                # The Julia form draws the words of its call apart, each in the
                # color of its kind. The string form draws what was typed, the
                # comment too, as one text.
                @test "GraphicsCircle" in texts
                @test !any(text -> occursin("GraphicsCircle(", text), texts)
                @test colors(content)["GraphicsCircle"] != colors(content)["10"]
                @test "x = 1  # why" in texts
                # The prompts stand in one column, and both codes start right of it.
                prompts_x = unique(x for (text, x, _) in drawn_at if text in (">", "="))
                @test length(prompts_x) == 1
                @test x_of("GraphicsCircle") == x_of("x = 1  # why") > only(prompts_x)
                # The one caret is in the fresh form, below both.
                carets = _app_drawn_carets(content)
                @test length(carets) == 1
                @test only(carets)[2] > y_of("x = 1  # why") > y_of("GraphicsCircle")
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

            @testset "a press on the picture opens the tool, and the pointer at rest names it" begin
                document, projection = make_application_window(paths[1:1]; root = dir,
                                                               assistant = nothing,
                                                               pointer = () -> (300, 400),
                                                               tooltip_feed = make_tooltip_feed())
                scene = make_window_scene(document, "ProjecturEd"; width = 1600, height = 1000)
                composed = make_window_scene_projection(projection;
                    opened_window_projections = make_opened_window_projections(;
                        content = make_application_content_projections()),
                    screen_wrap = make_popup_screen_wrap())
                iomap = print_document(composed, scene)
                # The pixel of the button, found the way a hand finds it: by
                # pressing. The toolbar is a band near the top of the window.
                action_at(x, y) = begin
                    operation = _app_plain(_app_fire(composed, iomap,
                                                     MousePress(:left, x, y, ModifierKeys())))
                    operation isa InvokeActionOperation ? string(operation.action.label) : nothing
                end
                row = findfirst(y -> action_at(12, y) == "Explorer", 0:2:120)
                @test row !== nothing
                y = (0:2:120)[row]
                column = findfirst(x -> action_at(x, y) == "Message log", 0:3:600)
                @test column !== nothing
                x = (0:3:600)[column]

                operation = _app_fire(composed, iomap, MousePress(:left, x, y, ModifierKeys()))
                evaluate_operation(_AppFakeEditor(scene, iomap), operation)
                tree = _app_window(document)
                @test count(tab -> get_wrapped_document(tab.content) === get_session_message_log(),
                            [tab for group in get_pane_groups(tree) for tab in group.tabs]) == 1

                # The pointer at rest on the picture opens a window of its own
                # that says the name of the tool and what it shows. A move only
                # says where the pointer is; the rest is what the window's feed
                # reads once the delay has passed.
                before = length(scene.windows)
                read_intent(composed, nothing,
                            Intent(WindowInput(:ProjecturEd, MouseMove(x, y))),
                            print_document(composed, scene))
                @test length(scene.windows) == before
                read_intent(composed, nothing,
                            Intent(WindowInput(:ProjecturEd, PointerRest(x, y))),
                            print_document(composed, scene))
                @test length(scene.windows) == before + 1
                tip = last(scene.windows)
                @test tip.style === :tooltip
                output = print_document(composed, scene).output
                @test any(text -> startswith(text, "Message log:"),
                          _app_drawn_strings(output.windows[end].content))
                # The window says its bounds and is printed at its maximum, so
                # what it holds fits: a name of one line needs neither the whole
                # width nor the whole height a tooltip may take.
                @test tip.maximum_size == (560, 400)
                @test tip.minimum_size == (120, 32)
                canvas = output.windows[end].content
                canvas = canvas isa Cell ? canvas[] : canvas
                @test 0 < Int(canvas.w[]) < tip.maximum_size[1]
                @test 0 < Int(canvas.h[]) < tip.maximum_size[2]
            end

            @testset "with the tooltip on, the pointer drags, lights, and leaves no history" begin
                # The window as the binary opens it: a pointer and a feed, so the
                # tooltip's probe sits over everything and must pass the pointer on.
                document, projection = make_application_window(paths[1:1]; root = dir,
                    assistant = nothing, pointer = () -> (0, 0),
                    tooltip_feed = make_tooltip_feed())
                scene = make_window_scene(document, "ProjecturEd"; width = 1600, height = 1000)
                composed = make_window_scene_projection(projection;
                    opened_window_projections = make_opened_window_projections(),
                    screen_wrap = make_popup_screen_wrap())
                # One print, kept, as the editor keeps it: a divider holds its drag
                # on the widget the print made, and a second print makes another.
                io = print_document(composed, scene)
                editor = _AppFakeEditor(scene, io)
                fire(event) = _app_fire(composed, io, event)
                apply(operation) = operation isa Operation && evaluate_operation(editor, operation)
                holds(operation, T) = operation isa T ||
                    (operation isa CompoundOperation && any(o -> holds(o, T), operation.operations)) ||
                    (operation isa WrappingOperation && holds(get_wrapped_operation(operation), T))
                history = document
                while !(history isa UndoBuffer) && hasproperty(history, :content)
                    history = history.content
                end
                steps() = length(history.undo_entries)
                tree = _app_window(document)
                held(x, y) = MouseMove(x, y, :left, ModifierKeys())

                # A row of the navigator lights up, and the history does not grow.
                y, _ = _app_find_file_row(composed, io)
                before = steps()
                lit = fire(MouseMove(100, y))
                @test holds(lit, ReplaceViewStateOperation)
                apply(lit)
                apply(fire(MouseMove(100, y + 40)))
                @test steps() == before

                # The divider between the navigator and the files follows the
                # pointer, and the history does not grow: a drag is view state.
                weights() = [Float64(w) for w in tree.root.weights]
                grab = findfirst(x -> holds(fire(MouseDown(:left, x, 500)),
                                            StartSplitterDragOperation), 280:360)
                @test grab !== nothing
                x = (280:360)[grab]
                recorded = steps()
                apply(fire(MouseDown(:left, x, 500)))
                before = weights()
                apply(fire(held(x + 80, 500)))
                apply(fire(held(x + 40, 500)))
                apply(fire(MouseUp(:left, x + 40, 500)))
                @test weights() != before
                @test steps() == recorded

                # The file's tab — the one the window opened on — drags into the
                # navigator's group.
                groups = get_pane_groups(tree)
                files = groups[end]
                (tx, ty) = last(sort([(x, y) for (text, x, y) in
                                      _app_drawn_at(io.output.windows[1].content)
                                      if text == "a.json"]))
                apply(fire(MouseDown(:left, tx + 4, ty + 4)))
                for (mx, my) in ((tx - 100, 500), (400, 500), (160, 500))
                    apply(fire(held(mx, my)))
                end
                apply(fire(MouseUp(:left, 160, 500)))
                title(tab) = get_pane_tab_title_string(tab)
                @test !any(tab -> title(tab) == "a.json", files.tabs)
                @test any(tab -> title(tab) == "a.json", groups[1].tabs)
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
