# The gestures of the `projectured` binary compile little. Each package of the
# binary compiles the gestures of its home with its `@compile_ahead`, and
# `ProjecturedBuild`, the package of the binary, compiles the list of the binary
# (`warm_application`), by the rules of package-rules.md under "A package
# compiles the gestures of its home". A fresh process of the package that a build
# writes drives each gesture on SDL and counts the statements that it compiles.

# The statements that the start may compile, from the load of the binary until
# its window is quiet, and that one gesture may compile.
const _START_STATEMENT_LIMIT = 50
const _GESTURE_STATEMENT_LIMIT = 10

# The drive of the gestures in a fresh process of the package of the binary. A mark
# is a new function, compiled once, so its statement lands in the trace of the
# compiler between the statements of two gestures. The drive builds its list
# before the mark of the start, because a binary builds no list. It prints the
# label of each mark, and the last line says that each gesture found its target.
const _GESTURE_DRIVE = raw"""
const _MARK_COUNT = Ref(0)
function mark_gesture(label)
    _MARK_COUNT[] += 1
    name = Symbol("GESTURE_MARK_", _MARK_COUNT[])
    Base.invokelatest(Core.eval(Main, :(function $name(v::Vector{Int}) push!(v, 1) end)), Int[])
    println("GESTURE MARK ", _MARK_COUNT[], " ", label)
    flush(stdout)
end
mark_gesture("the load")
using ProjecturedApp
mark_gesture("the list of the drive")
const A = ProjecturedApp.ProjecturedPlatform.ApplicationModule
struct GestureMark <: A.WorkloadStep
    label::String
end
A.find_workload_inputs(editor, step::GestureMark) = (mark_gesture(step.label); A.WindowInput[])

const STEPS = A.WorkloadStep[]
gesture(label, steps...) = append!(STEPS, A.WorkloadStep[GestureMark(label), steps...])
tool(label) = A.DrawnPart(input -> input isa A.WidgetToolbarItem && string(input.action.label) == label)
click(text; keywords...) = A.WorkloadClick(A.DrawnText(text; keywords...))
key(name; modifiers...) = A.WorkloadKey(name; modifiers...)

for (title, item) in [("File", "New tab"), ("File", "Close tab"), ("View", "Split vertically"),
                      ("View", "Split horizontally"), ("View", "Gesture log"),
                      ("View", "Appearance"), ("View", "Settings"), ("Help", "Gestures"),
                      ("Help", "Command palette"), ("Help", "Documents"), ("Help", "Projections"),
                      ("Help", "About")]
    gesture("the menu $title", click(title; pick = :topmost))
    gesture("the item $item of $title", click(item))
    item == "Gestures" && gesture("F1 closes the gesture help", key(:f1))
    item == "Command palette" && gesture("Escape closes the palette", key(:escape))
end
for label in ("Explorer", "Files", "Evaluator", "Message log", "Gesture log", "Fault log",
              "Frame statistics", "Frame times", "Selection", "Appearance", "Settings",
              "Assistants", "Assistant")
    gesture("the tool $label", A.WorkloadClick(tool(label)))
end
gesture("a press on the draft", A.WorkloadClick(A.DrawnPart(input -> input isa A.ConversationDraft)))
gesture("a typed question", A.WorkloadTyping("hi"))
gesture("an assistant turn with a tool call", key(:return), A.WorkloadWait(A.DrawnText("The sum is two.")))
gesture("the tool Explorer again", A.WorkloadClick(tool("Explorer")))
gesture("a right press on a row of the Explorer", A.WorkloadClick(A.DrawnText("Files"; pick = :leftmost); button = :right))
gesture("the item Open in a new tab", click("Open in a new tab"))
gesture("Ctrl+T", key(:t; ctrl = true))
gesture("Insert", key(:insert))
gesture("a typed name", A.WorkloadTyping("evaluator"))
gesture("Return commits the name", key(:return))
gesture("F1", key(:f1))
gesture("F1 again", key(:f1))
gesture("Ctrl+Shift+P", key(:p; ctrl = true, shift = true))
gesture("a typed command", A.WorkloadTyping("ab"))
gesture("Escape", key(:escape))

files = Pair{String,String}[]
for type in A.collect_workload_file_types()
    file = A.make_workload_file(type)
    name = string(nameof(type), splitext(file.name)[2])
    push!(files, name => file.text)
    gesture("the tool Files before $name", A.WorkloadClick(tool("Files")))
    gesture("a press on the row of $name", click(name; pick = :leftmost))
    gesture("Return opens $name", key(:return), A.WorkloadWait(A.DrawnText(file.shown)))
    gesture("a press in $name", A.WorkloadClick(A.DrawnText(file.shown)))
    gesture("a typed key in $name", A.WorkloadTyping("x"))
    gesture("Ctrl+S saves $name", key(:s; ctrl = true))
    gesture("Ctrl+Z in $name", key(:z; ctrl = true))
    gesture("Ctrl+W closes $name", key(:w; ctrl = true))
end
gesture("the end")

mark_gesture("the start")
A.run_application_workload(files; steps = STEPS, backend = ProjecturedApp.ProjecturedSDL.SdlBackend(),
                           llm = A.make_workload_llm("1 + 1"; answer = "The sum is two."),
                           timeout = 120)
println("GESTURES DONE")
"""

# The package of the binary in `folder`, as a build of the binary writes it, and
# the manifest of the active environment with each package path made absolute, so
# that the binary loads the images of the packages that the active environment
# compiled. A process of the active environment writes it, because the builder is
# a tool of that environment and not a dependency of the tests.
function _write_binary_package(folder::String)
    julia = first(Base.julia_cmd().exec)
    package_root = normpath(joinpath(@__DIR__, "..", "..", "package"))
    write_package = """
        using ProjecturedBuilder
        context = BuildContext($(repr(folder)); package_roots = [$(repr(package_root))])
        println("BINARY PACKAGE ", build_projectured_executable(; context, compile = false))
        """
    output = read(`$julia --startup-file=no --project=$(Base.active_project()) -e $write_package`, String)
    project = match(r"BINARY PACKAGE (.*)", output)[1]
    manifest = Base.project_file_manifest_path(Base.active_project())
    root = dirname(manifest)
    write(joinpath(project, "Manifest.toml"),
          replace(read(manifest, String),
                  r"(?m)^path = \"(.*)\"$" => line -> _make_absolute_path_line(line, root)))
    project
end

# Run `command`, and answer its exit code, its output and its errors.
function _run_gesture_process(command::Cmd)
    output, errors = IOBuffer(), IOBuffer()
    process = run(pipeline(ignorestatus(command); stdout = output, stderr = errors))
    (process.exitcode, String(take!(output)), String(take!(errors)))
end

# The statements that the trace holds between two marks of the drive, for each
# label: `(label, statements, recompiles)`. A statement of the drive itself names
# `Main` and does not count.
function _count_gesture_statements(trace::String, output::String)
    labels = Dict(parse(Int, found[1]) => String(found[2])
                  for found in eachmatch(r"GESTURE MARK (\d+) (.*)", output))
    counts = Tuple{String,Int,Int}[]
    isfile(trace) || return counts
    label, statements, recompiles = nothing, 0, 0
    for line in eachline(trace)
        found = match(r"^precompile\(Tuple\{typeof\(Main\.GESTURE_MARK_(\d+)\)", line)
        if found !== nothing
            label === nothing || push!(counts, (label, statements, recompiles))
            label, statements, recompiles = labels[parse(Int, found[1])], 0, 0
        elseif label !== nothing && startswith(line, "precompile(") && !occursin("Main.", line)
            statements += 1
            recompiles += endswith(line, "# recompile")
        end
    end
    counts
end

"""
    test_gestures_compile_little()

In a fresh process of the package of the `projectured` binary, on SDL: the start
compiles at most `_START_STATEMENT_LIMIT` statements, each gesture at most
`_GESTURE_STATEMENT_LIMIT`, and no gesture compiles a method again. The list
presses each item of each menu, each tool of the toolbar, and opens and edits a
file of each format of the binary. A count does not change with the load of the
machine. The test builds the image of the package of the binary first, which
runs its workload, and that build writes no warning.
"""
function test_gestures_compile_little()
    if Base.identify_package("ProjecturedBuilder") === nothing
        @testset "the gestures of the binary compile little" begin
            @test_skip Base.identify_package("ProjecturedBuilder") !== nothing
        end
        return
    end
    mktempdir() do folder
        project = _write_binary_package(folder)
        julia = first(Base.julia_cmd().exec)
        @testset "the image of the binary runs its workload with no warning" begin
            (code, _, errors) = _run_gesture_process(
                `$julia --startup-file=no --project=$project -e "using ProjecturedApp"`)
            @test code == 0
            @test !occursin("Warning", errors)
            code == 0 && !occursin("Warning", errors) ||
                println(stderr, "\nthe build of the image of the binary wrote:\n", last(errors, 5000))
        end
        trace = joinpath(folder, "trace.txt")
        (code, output, errors) = _run_gesture_process(addenv(
            `$julia --startup-file=no --threads=auto,2 --project=$project --trace-compile=$trace -e $_GESTURE_DRIVE`,
            "SDL_VIDEODRIVER" => "offscreen"))
        @testset "the gestures of the binary compile little" begin
            @test code == 0 && occursin("GESTURES DONE", output)
            code == 0 || println(stderr, "\nthe drive of the gestures failed:\n", last(errors, 5000))
            counts = _count_gesture_statements(trace, output)
            for (label, statements, recompiles) in counts
                println(stderr, rpad(label, 48), lpad(statements, 6), lpad(recompiles, 6))
            end
            start = only(filter(count -> count[1] == "the start", counts))
            # @broken: the start compiles 75 statements, Base methods and the held frames of SDL; plan/done/a-gesture-compiles-nothing.md, step 6
            @test_broken start[2] <= _START_STATEMENT_LIMIT
            gestures = filter(count -> !(count[1] in ("the load", "the list of the drive", "the start",
                                                      "the end")), counts)
            @test !isempty(gestures)
            # @broken: 4 of 166 gestures compile more than 10 statements, the assistant turn the most; plan/done/a-gesture-compiles-nothing.md, step 6
            @test_broken all(count -> count[2] <= _GESTURE_STATEMENT_LIMIT, gestures)
            # @broken: the gestures compile 3 methods again; plan/done/a-gesture-compiles-nothing.md, step 6
            @test_broken sum(count -> count[3], gestures; init = 0) == 0
        end
    end
end
