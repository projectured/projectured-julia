"""
What `execute_julia_code!` answers: what the code printed, whole and also before
an error, the value of the last expression shown or described, "Done." for
nothing, and the nearest declared names for a name nobody defined. It also
verifies that each observer hears the value of each evaluation, that an
observer that throws stops neither the others nor the answer, and that a verb
with no editor takes the editor of the evaluation.
"""

using Test
using ProjecturedKernel.ToolModule

# A declared API with names a guess lands near.
module NearToy
export count_rows, draw_arrow, make_result_plot
"""Count the rows of a table."""
count_rows(table) = 0
"""Draw an arrow."""
draw_arrow(canvas) = nothing
"""A chart of a frame."""
make_result_plot(frame) = nothing
end

# A declared API with one verb that takes the editor of the evaluation when its
# caller names none.
module EditorToy
using ProjecturedKernel.ToolModule: get_evaluation_editor
export get_toy_editor
"""The editor that the verb acts on."""
get_toy_editor(; editor = get_evaluation_editor()) = editor
end

# A declared API with one verb whose value is a picture, as the file of a picture
# that a verb of the screen writes is.
module PictureToy
import ProjecturedKernel.ToolModule: get_model_image
using ProjecturedKernel.LlmModule: LlmImage
export make_toy_picture
struct ToyPicture
    bytes::Vector{UInt8}
end
"""A picture of three bytes."""
make_toy_picture() = ToyPicture(UInt8[1, 2, 3])
get_model_image(picture::ToyPicture) = LlmImage("image/png", picture.bytes)
end

function test_code_execution()
@testset "Code execution" begin
    set = ToolSet(; api = Module[NearToy])
    run = code -> execute_julia_code!(set, nothing, code)

    @testset "a short value is shown, a long one is described" begin
        @test run("1 + 1") == "2\n"
        @test run("\"a word\"") == "\"a word\"\n"
        # A long string is prose a verb answers to be read: whole, without quotes.
        @test run("repeat(\"word \", 100)") == repeat("word ", 100) * "\n"
        @test run("Text(\"one\\ntwo\\nthree\")") == "one\ntwo\nthree\n"
        # A string that has a line break is shown as its lines, without quotes.
        @test run("\"one\\ntwo\"") == "one\ntwo\n"
        # A long vector shows as Julia's own elided line, which is short.
        elided = run("collect(1:1000)")
        @test startswith(elided, "[1, 2, 3") && occursin("…", elided) && !occursin("500", elided)
        # A value whose form is long even limited — a tuple is never elided —
        # keeps its start and its end around one mark line, then a note.
        long = run("Tuple(1:1000)")
        @test startswith(long, "(1, 2, 3")
        @test occursin(r"⋯ \d+ characters left out ⋯", long)
        @test occursin("The value is trimmed: NTuple{1000, Int64}.", long)
        @test occursin("println(first(x, 10))", long)
        # What the code prints comes first, and is never cut.
        printed = run("for i in 1:300\n  println(i)\nend\nTuple(1:1000)")
        @test startswith(printed, join(string.(1:300), '\n') * "\n(1, 2, 3")
    end

    @testset "the sleep of model code sleeps outside a code unit" begin
        plain = ToolSet()
        started = time()
        @test strip(execute_julia_code!(plain, nothing, "sleep(0.05); 2")) == "2"
        @test time() - started >= 0.05
        @test strip(execute_julia_code!(plain, nothing, "sleep === Base.sleep")) == "false"
    end

    @testset "a loop at the top level assigns the global, as at the prompt" begin
        @test run("found = nothing\nfor i in 1:3\n    if i == 2\n        found = i\n        break\n    end\nend\nfound") == "2\n"
        @test run("total = 0\nfor i in 1:4\n    total += i\nend\ntotal") == "10\n"
        # A definition and a constant still work at the top level.
        @test run("const LIMIT = 3\nf(x) = x + LIMIT\nf(1)") == "4\n"
        @test run("struct Point\n    x::Int\nend\nPoint(5).x") == "5\n"
    end

    @testset "a short value is unchanged" begin
        @test run("1 + 1") == "2\n"
        @test run("\"a word\"") == "\"a word\"\n"
    end

    @testset "the person's description shows the value as the REPL does" begin
        @test describe_value_for_person(nothing) == ""
        @test describe_value_for_person(2) == "2\n"
        long = describe_value_for_person(collect(1:1000))
        @test occursin("1000-element Vector{Int64}:", long)
        @test occursin("⋮", long)
        @test !occursin("Print a part", long)
    end

    @testset "an Expr runs as its text does" begin
        # A second tool set, so the two ways run from the same empty state.
        other = ToolSet(; api = Module[NearToy])
        @test execute_julia_expression!(other, nothing, Meta.parseall("z = 40 + 2")) ==
              run("z = 40 + 2") == "42\n"
        # The binding stays in the scratch module, as a binding from text does.
        @test execute_julia_expression!(other, nothing, :(z + 1)) == "43\n"
        # An object in a QuoteNode is that very object.
        object = Ref(7)
        execute_julia_expression!(other, nothing, Expr(:toplevel, QuoteNode(object)))
        @test get_last_evaluated_value(other) === object
        # A failure is answered, not thrown.
        @test occursin("UndefVarError", execute_julia_expression!(other, nothing, :(no_such_name_q)))
    end

    @testset "the code tool answers a value that is a picture as the picture" begin
        # A name of its own: `set` is the set of the whole function, which `run` reads.
        picture_set = register_default_tools!(ToolSet(; api = Module[PictureToy]))
        run_code = code -> call_tool(picture_set, "execute_julia_code"; args = Dict{String,Any}("code" => code),
                                     target = nothing)
        picture = run_code("make_toy_picture()")
        @test picture isa PictureToy.LlmImage
        @test picture.media_type == "image/png" && picture.data == UInt8[1, 2, 3]
        # A value that is no picture answers its text.
        @test run_code("1 + 1") == "2\n"
        @test get_model_image(2) === nothing
    end

    @testset "a verb with no editor takes the editor of the evaluation" begin
        first_set = ToolSet(; api = Module[EditorToy])
        other_set = ToolSet(; api = Module[EditorToy])
        @test execute_julia_code!(first_set, :first_editor, "get_toy_editor()") == ":first_editor\n"
        @test execute_julia_code!(other_set, :other_editor, "get_toy_editor()") == ":other_editor\n"
        @test execute_julia_expression!(other_set, :other_editor, :(get_toy_editor())) ==
              ":other_editor\n"
        # A caller that names an editor gets that editor.
        @test execute_julia_code!(first_set, :first_editor, "get_toy_editor(; editor = :named)") ==
              ":named\n"
        # A task that the code starts gets the editor, also on another thread, and
        # also when it runs on after the call ends.
        @test execute_julia_code!(first_set, :first_editor, "fetch(@async get_toy_editor())") ==
              ":first_editor\n"
        @test execute_julia_code!(first_set, :first_editor,
                                  "fetch(Threads.@spawn get_toy_editor())") == ":first_editor\n"
        execute_julia_code!(first_set, :first_editor,
                            "late_task_1 = @async (sleep(0.05); get_toy_editor()); nothing")
        @test execute_julia_code!(first_set, :other_editor, "fetch(late_task_1)") ==
              ":first_editor\n"
        # Outside an evaluation no editor is there, and the message names the fix.
        @test_throws MissingEvaluationEditorException get_evaluation_editor()
        @test occursin("`editor = …`", sprint(showerror, MissingEvaluationEditorException()))
        # Code that runs with no editor answers the exception, as any error.
        @test startswith(execute_julia_code!(first_set, nothing, "get_toy_editor()"),
                         "MissingEvaluationEditorException")
    end

    @testset "nothing is Done., unless the code printed" begin
        @test run("nothing") == "Done."
        @test run("x = 3; nothing") == "Done."
        @test run("println(\"hi\"); nothing") == "hi\n"
    end

    @testset "a large print answers whole" begin
        answer = run("print(repeat('x', 200_000))")
        @test length(answer) == 200_000
        @test count(==('x'), answer) == 200_000
    end

    @testset "what the code prints goes to its own answer, and the process streams stay" begin
        @test run("x_shown = 3\n@show x_shown") == "x_shown = 3\n3\n"
        @test run("display(1:2); nothing") == "1:2\n"
        @test run("show(:a); println(stderr, \"!\"); nothing") == ":a!\n"
        @test run("fetch(@async println(\"from a task\")); nothing") == "from a task\n"
        execute_julia_code!(set, nothing, "Base.stdout")
        @test get_last_evaluated_value(set) === stdout
    end

    @testset "two evaluations at the same time keep their output and their result apart" begin
        both = ToolSet()
        code(name) = "for i in 1:3\n  println(\"$name\", i)\n  sleep(0.02)\nend\n:$name"
        calls = [Threads.@spawn begin
                     answer = execute_julia_code!(both, nothing, code(name))
                     (answer, get_last_evaluated_value(both))
                 end for name in ("first", "second")]
        (first_answer, first_value), (second_answer, second_value) = fetch.(calls)
        @test first_answer == "first1\nfirst2\nfirst3\n:first\n"
        @test second_answer == "second1\nsecond2\nsecond3\n:second\n"
        @test (first_value, second_value) == (:first, :second)
        # Each task reads its own; this task made no call on the set.
        @test find_last_evaluation_result(both) === nothing
        @test run_julia_code!(both, nothing, "40 + 2").value == 42
        @test find_last_evaluation_result(both).value == 42
    end

    @testset "what the code printed comes before the error" begin
        @test startswith(run("println(1)\nerror(\"stop here\")"), "1\nstop here")
        # The statements before a syntax error run, and what they print shows.
        @test startswith(run("println(1)\ny = ("), "1\nParseError")
    end

    @testset "the tool set keeps the exception that the code threw" begin
        run("error(\"stop here\")")
        @test get_last_evaluation_exception(set) isa ErrorException
        @test get_last_evaluation_exception(set).msg == "stop here"
        # An answer with no exception clears it.
        run("1 + 1")
        @test get_last_evaluation_exception(set) === nothing
    end

    @testset "the tool set counts each exception, also two equal ones" begin
        before = get_evaluation_exception_count(set)
        run("error(\"twice\")")
        first_exception = get_last_evaluation_exception(set)
        run("error(\"twice\")")
        @test get_last_evaluation_exception(set) === first_exception
        @test get_evaluation_exception_count(set) == before + 2
        run("1 + 1")
        @test get_evaluation_exception_count(set) == before + 2
    end

    @testset "a function is shown as the REPL shows it" begin
        @test run("phase_q() = 1") == "phase_q (generic function with 1 method)\n"
    end

    @testset "a value shows with the show method that the same call defined" begin
        code = "struct ShownBoxQ end\n" *
               "Base.show(io::IO, ::ShownBoxQ) = print(io, \"a shown box\")\n" *
               "ShownBoxQ()"
        @test run(code) == "a shown box\n"
    end

    @testset "a name nobody defined is answered with the nearest declared names" begin
        answer = run("count_row([1])")
        @test occursin("UndefVarError", answer)
        @test occursin("Did you mean: `count_rows`", answer)
        answer = run("plot_result(1)")
        @test occursin("Did you mean: `make_result_plot`", answer)
        @test !occursin("Did you mean", run("zzz_nothing_near(1)"))
        # A name that shares a word comes first; a name an edit or two away comes
        # too; a name that is neither does not.
        near = ProjecturedKernel.ToolModule._find_nearest_names(
            "draw_arrows", ["draw_arrow", "count_rows", "make_result_plot", "draw_arrowz"])
        @test near == ["draw_arrow", "draw_arrowz"]
        @test ProjecturedKernel.ToolModule._find_nearest_names("zzz", ["count_rows"]) == String[]
    end

    @testset "each observer hears the value of each evaluation, in order" begin
        watched = ToolSet()
        seen = Any[]
        observe_evaluations!(value -> push!(seen, (:first, value)), watched)
        observe_evaluations!(value -> push!(seen, (:second, value)), watched)
        execute_julia_code!(watched, nothing, "1 + 1")
        execute_julia_expression!(watched, nothing, :(3 * 3))
        # An evaluation that throws has no value.
        execute_julia_code!(watched, nothing, "error(\"no value\")")
        @test seen == [(:first, 2), (:second, 2), (:first, 9), (:second, 9),
                       (:first, nothing), (:second, nothing)]
    end

    @testset "an observer that throws stops neither the others nor the answer" begin
        watched = ToolSet()
        seen = Any[]
        observe_evaluations!(value -> error("the observer fails"), watched)
        observe_evaluations!(value -> push!(seen, value), watched)
        answer = @test_logs (:warn, r"observer failed") match_mode = :any begin
            execute_julia_code!(watched, nothing, "40 + 2")
        end
        @test answer == "42\n"
        @test seen == [42]
    end

    @testset "model code: an interrupt is the answer, a quit and a full heap pass" begin
        # As at the Julia REPL, an interrupt and a stack overflow end the call only.
        @test occursin("InterruptException", run("throw(InterruptException())"))
        @test occursin("StackOverflowError", run("throw(StackOverflowError())"))
        @test_throws OutOfMemoryError run("throw(OutOfMemoryError())")
        quit = ProjecturedKernel.OperationModule.QuitEditorException
        @test_throws quit execute_julia_expression!(set, nothing, :(throw($quit())))
    end

    @testset "a value kept under the id of a call is taken once" begin
        kept = ToolSet()
        @test keep_tool_call_value!(kept, "a", 1) == 1
        keep_tool_call_value!(kept, "a", 2)
        @test take_tool_call_value!(kept, "a") == 2
        @test take_tool_call_value!(kept, "a") === nothing
        # The oldest goes when the set keeps as many as it can.
        capacity = ProjecturedKernel.ToolModule.TOOL_CALL_VALUE_CAPACITY
        for index in 1:(capacity + 1)
            keep_tool_call_value!(kept, string(index), index)
        end
        @test take_tool_call_value!(kept, "1") === nothing
        @test take_tool_call_value!(kept, string(capacity + 1)) == capacity + 1
    end

    @testset "an observer that is interrupted stops the call" begin
        watched = ToolSet()
        observe_evaluations!(_ -> throw(InterruptException()), watched)
        @test_throws InterruptException execute_julia_code!(watched, nothing, "1")
    end

    @testset "the code of a model loads only the packages that its window offers" begin
        model = ToolSet(; api = Module[NearToy])
        load = code -> run_julia_code!(model, nothing, code)

        # A package that the window does not offer refuses the whole code, and
        # no statement of it runs.
        refused = load("x_1 = 1\nusing Plots")
        @test refused.exception isa PackageLoadRefusedException
        @test refused.exception.packages == ["Plots"]
        @test startswith(refused.output, "PackageLoadRefusedException: no statement of the code ran, because it loads Plots.")
        @test occursin("Dates, Statistics, Printf and Random", refused.output)
        @test !occursin("Stacktrace", refused.output)
        @test load("@isdefined(x_1)").value === false
        @test load("using Dates, Plots").exception.packages == ["Plots"]
        @test load("begin\n    import Plots: plot\nend").exception isa PackageLoadRefusedException
        # The packages of the editor are no packages that the code loads, and
        # neither is a module that the scratch module binds for its names.
        @test load("using ProjecturedKernel").exception.packages == ["ProjecturedKernel"]
        @test load("using .NearToy").exception.packages == [".NearToy"]
        @test load("import ..Main").exception.packages == ["..Main"]

        # Base and Core run as they are.
        @test load("import Base: show").exception === nothing
        @test load("using Base.Iterators: partition\ncollect(partition(1:4, 2))").value == [1:2, 3:4]

        # A standard library of the list loads when the code asks for it, and its
        # name stays bound for the next call.
        @test load("using Dates\nDates.format(Date(2026, 11, 24) + Day(8), \"yyyy-mm-dd\")").value == "2026-12-02"
        @test load("today() isa Date").value === true
        @test load("using Statistics: mean\nmean([1, 2, 6])").value == 3.0
        @test load("using Printf\n@sprintf(\"%.2f\", 1.5)").value == "1.50"
        @test load("import Random\nrand(Random.Xoshiro(1), 1:6) in 1:6").value === true
        @test load("using .Dates: Time\nTime(10, 15) isa Time").value === true

        # A name of a library of the list before its `using` gets the line that
        # says what to write.
        fresh = ToolSet(; api = Module[NearToy])
        early = run_julia_code!(fresh, nothing, "Dates.today()")
        @test early.exception isa UndefVarError
        @test occursin("`Dates` is a standard library of this window: write `using Dates` first.", early.output)
        @test occursin("`today` is a name of the standard library Dates of this window: write `using Dates` first.",
                       run_julia_code!(fresh, nothing, "today()").output)

        # The person types into a set that declares no API, where a `using`
        # resolves as it does at the Julia prompt.
        person = ToolSet()
        @test run_julia_code!(person, nothing, "using Dates\nDate(2026, 1, 1)").exception === nothing
    end

    @testset "a standard library loads with no @stdlib in the load path" begin
        # A process of its own, so that Statistics is not loaded yet, with the
        # load path of a window that has no `@stdlib`.
        code = """
            using ProjecturedKernel.ToolModule
            module Declared
            export noted
            \"\"\"A name.\"\"\"
            noted() = 1
            end
            set = ToolSet(; api = Module[Declared])
            print(execute_julia_code!(set, nothing, "using Statistics\\nmean([1, 2, 6])"))
            """
        command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`,
                         "JULIA_LOAD_PATH" => "@")
        @test strip(read(command, String)) == "3.0"
    end
end
end # test_code_execution
