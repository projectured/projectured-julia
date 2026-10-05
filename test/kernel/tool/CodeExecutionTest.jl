"""
What `execute_julia_code!` answers: what the code printed, whole and also before
an error, the value of the last expression shown or described, "Done." for
nothing, and the nearest declared names for a name nobody defined. It also
verifies that each observer hears the value of each evaluation, and that an
observer that throws stops neither the others nor the answer.
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

    @testset "nothing is Done., unless the code printed" begin
        @test run("nothing") == "Done."
        @test run("x = 3; nothing") == "Done."
        @test run("println(\"hi\"); nothing") == "hi\n"
    end

    @testset "a print larger than a pipe answers whole" begin
        # A pipe holds 64 KiB. The call runs on its own task with a bounded wait,
        # so a print that waits for a reader fails here and the suite goes on.
        console_stdout = stdout
        console_stderr = stderr
        call = @async run("print(repeat('x', 200_000))")
        finished = timedwait(() -> istaskdone(call), 60) === :ok
        if !finished
            # The blocked call holds the process streams, and a failed test prints.
            redirect_stdout(console_stdout)
            redirect_stderr(console_stderr)
        end
        @test finished
        if finished
            answer = fetch(call)
            @test length(answer) == 200_000
            @test count(==('x'), answer) == 200_000
        end
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

    @testset "an observer that is interrupted stops the call" begin
        watched = ToolSet()
        observe_evaluations!(_ -> throw(InterruptException()), watched)
        @test_throws InterruptException execute_julia_code!(watched, nothing, "1")
    end
end
end # test_code_execution
