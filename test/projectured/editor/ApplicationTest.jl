# Tests for the application window. Both windows draw a file of every format,
# a navigator gesture opens a file beside the other files, and Ctrl+S saves the
# file tab that has the focus. The events go through the same window scene that
# `run_application` runs, with no window on the screen.

using Test
using ProjecturedExample: _gesture_map_entry

# `evaluate_operation` reads `document` and `iomap` of an editor.
mutable struct _AppFakeEditor; document::Any; iomap::Any; end

function _app_fire(composed, iomap, event)
    change = read_intent(composed, nothing, Intent(WindowInput(:ProjecturEd, event)), iomap)
    change isa Intent ? change.operation : change
end

_app_count_tabs(tree::PaneTree) = sum(length(group.tabs) for group in get_pane_groups(tree))
_app_count_tabs(workbench::WorkbenchWorkbench) = length(workbench.editing_page.elements)

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
function _app_make_scene(paths, dir, window)
    document = make_application_document(paths; window = window, root = dir, assistant = nothing)
    projection = make_application_projection(; window = window)
    scene = make_window_scene(document, "ProjecturEd"; width = 1600, height = 1000)
    composed = make_window_scene_projection(projection; opened_window_projections =
        Pair{Type,Any}[_gesture_map_entry(measure_truetype_text)])
    iomap = print_document(composed, scene)
    (document, scene, composed, iomap)
end

# The first height at which a double click on the navigator opens a file, and
# the operation it makes. The navigator is the leftmost part of both windows.
function _app_find_file_row(composed, iomap)
    for y in 0:4:400
        operation = _app_fire(composed, iomap, MousePress(:left, 100, y, 2, ModifierKeys()))
        operation isa OpenWorkspaceFileOperation && return (y, operation)
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
            @test_throws ErrorException make_application_document(String[]; window = :unknown)
        end

        @testset "the command line" begin
            command = parse_application_arguments(String[])
            @test command.files == String[] && command.window === :pane
            @test command.backend === :sdl && command.assistant === :ollama
            @test command.model == "" && !command.mcp
            command = parse_application_arguments(
                ["a.json", "--window=workbench", "--backend=web", "--assistant=none",
                 "--model=small", "--root=/tmp", "--mcp", "b.md"])
            @test command.files == ["a.json", "b.md"]
            @test command.window === :workbench && command.backend === :web
            @test command.assistant === :none && command.model == "small"
            @test command.root == "/tmp" && command.mcp
            @test_throws ErrorException parse_application_arguments(["--colour=red"])
            @test_throws ErrorException parse_application_arguments(["-x"])
            @test_throws ErrorException parse_application_arguments(["--window=tiles"])
            @test_throws ErrorException parse_application_arguments(["--assistant=gpt"])
            # A wrong command line answers 1 and opens no window.
            quiet = devnull
            @test redirect_stderr(() -> run_application_command(["--window=tiles"];
                                                                backends = (sdl = () -> nothing,)),
                                  quiet) == 1
            @test redirect_stderr(() -> run_application_command(["--backend=web"];
                                                                backends = (sdl = () -> nothing,)),
                                  quiet) == 1
            # Every option of the list is one the parser takes.
            for (label, _) in APPLICATION_OPTIONS
                flag = first(split(label, '='))
                flag == "--mcp" && continue
                @test haskey(pairs(parse_application_arguments(String[])),
                             Symbol(flag[3:end]))
            end
        end

        @testset "the warm-up of a build" begin
            @test_logs min_level = Base.CoreLogging.Warn warm_application()
        end

        dir = mktempdir()
        paths = _app_write_files(dir)
        for window in APPLICATION_WINDOWS
            @testset "$window window" begin
                @testset "every format draws" begin
                    for path in vcat([String[]], [[p] for p in paths])
                        document = make_application_document(path; window = window, root = dir,
                            assistant = make_application_assistant(:ollama))
                        projection = make_application_projection(; window = window)
                        errors, _ = walk_printer_output(document, projection)
                        @test isempty(errors)
                    end
                end

                @testset "Ctrl+S saves the focused file" begin
                    json = joinpath(dir, "a.json")
                    document, scene, composed, iomap = _app_make_scene([json], dir, window)
                    editor = _AppFakeEditor(scene, iomap)
                    operation = _app_fire(composed, iomap, KeyDown(:s, ModifierKeys(ctrl = true)))
                    @test operation isa SaveWorkbenchEditorOperation
                    tab = operation.editor
                    @test tab.filename == json
                    tab.content.entries[1].value.value = "Bob"
                    evaluate_operation(editor, operation)
                    @test occursin("Bob", read(json, String))
                    write_document_file(parse_natural_text(:json, "{\"name\": \"Alice\", \"age\": 30}"), json)
                end

                @testset "the navigator opens a file beside the files" begin
                    document, scene, composed, iomap = _app_make_scene(paths[1:1], dir, window)
                    editor = _AppFakeEditor(scene, iomap)
                    y, operation = _app_find_file_row(composed, iomap)
                    @test operation isa OpenWorkspaceFileOperation
                    @test basename(operation.path) == "a.jl"    # the first file row
                    before = _app_count_tabs(document)
                    evaluate_operation(editor, operation)
                    @test _app_count_tabs(document) == before + 1
                    if window === :pane
                        groups = get_pane_groups(document)
                        @test length(groups[1].tabs) == 1       # the navigator stays alone
                        @test length(groups[2].tabs) == 2       # the file joins the files
                    end

                    # A single click selects the row, and Enter opens it.
                    selection = _app_fire(composed, iomap, MousePress(:left, 100, y, 1, ModifierKeys()))
                    @test selection isa CompoundOperation
                    evaluate_operation(editor, selection)
                    opened = _app_fire(composed, iomap, KeyDown(:return, ModifierKeys()))
                    @test opened isa OpenWorkspaceFileOperation
                    @test opened.path == operation.path
                end
            end
        end
        rm(dir; recursive = true)
    end
end
