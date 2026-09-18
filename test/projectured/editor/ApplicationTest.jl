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

        @testset "the command line" begin
            command = parse_application_arguments(String[])
            @test command.files == String[]
            @test command.backend === nothing && command.assistant === :ollama
            @test command.model == "" && !command.mcp
            @test command.context == 0 && !command.gesture_log
            command = parse_application_arguments(
                ["a.json", "--backend=web", "--assistant=none",
                 "--model=small", "--root=/tmp", "--mcp", "--context=8192",
                 "--gesture-log", "b.md"])
            @test command.files == ["a.json", "b.md"]
            @test command.backend === :web
            @test command.assistant === :none && command.model == "small"
            @test command.root == "/tmp" && command.mcp
            @test command.context == 8192 && command.gesture_log
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
            # The `--help` text of a binary names exactly the options the
            # parser takes.
            usage = make_projectured_usage([:sdl, :web])
            flags = Set(first(split(label, '=')) for (label, _) in usage.options)
            @test flags == Set(["--backend", "--assistant", "--model",
                                "--root", "--mcp", "--context", "--gesture-log"])
            # A flag spells a word with a hyphen and a keyword with an
            # underscore, so `--gesture-log` is `gesture_log`.
            for flag in flags
                @test haskey(pairs(parse_application_arguments(String[])),
                             Symbol(replace(flag[3:end], '-' => '_')))
            end
            @test !any(label -> startswith(first(label), "--backend"),
                       make_projectured_usage([:sdl]).options)
        end

        @testset "the warm-up of a build" begin
            @test_logs min_level = Base.CoreLogging.Warn warm_application()
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
