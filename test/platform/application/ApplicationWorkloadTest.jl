# The workload of the application window: each step finds its target in what the
# window draws, through the loop of the window, and a step whose target the window
# never draws is an error that names the step.

# The tool of the toolbar whose label is `label`.
_toolbar_tool(label::AbstractString) =
    DrawnPart(input -> input isa WidgetToolbarItem && string(input.action.label) == label)

"""
    test_application_workload()

`run_application_workload` gives a menu, a popup, a tool of the toolbar, a row of
the Files pane, keys, typed text and an assistant turn to the application window,
and each step finds its target. The model of
`make_workload_llm` asks for the tool in the first round of a turn and answers in
the second. A step whose target the window never
draws, and a step after the end of the loop, make it throw an error that names
the step.
"""
function test_application_workload()
    @testset "the workload of the application window" begin
        @testset "each step finds its target" begin
            files = ["a.txt" => "one two three\nfour\n", "b.txt" => "five\n"]
            steps = WorkloadStep[
                WorkloadClick(DrawnText("Help"; pick = :topmost)),
                WorkloadClick(DrawnText("About")),
                WorkloadClick(_toolbar_tool("Files")),
                WorkloadClick(DrawnText("a.txt"; pick = :leftmost)),
                WorkloadKey(:return),
                WorkloadWait(DrawnText(r"four")),
                WorkloadClick(DrawnText(r"four")),
                WorkloadTyping("x"),
                WorkloadClick(_toolbar_tool("Assistant")),
                WorkloadClick(DrawnPart(input -> input isa ConversationDraft)),
                WorkloadTyping("hi"),
                WorkloadKey(:return),
                WorkloadWait(DrawnText("The sum is two."))]
            llm = make_workload_llm("1 + 1"; answer = "The sum is two.")
            @test run_application_workload(files; steps, llm) === nothing
        end

        @testset "the model of a workload asks for the tool, then answers" begin
            model = make_workload_llm("1 + 1"; answer = "Two.")
            rounds = [LlmEvent[], LlmEvent[], LlmEvent[]]
            for events in rounds
                stream_turn(model, LlmRequest(); on_event = event -> push!(events, event))
            end
            calls = [event.tool_use for event in rounds[1] if event isa LlmToolUseStop]
            @test length(calls) == 1
            @test calls[1].name == "execute_julia_code"
            @test calls[1].input == Dict{String,Any}("code" => "1 + 1")
            @test any(event -> event isa LlmThinkingDelta, rounds[1])
            @test last(rounds[1]) == LlmTurnEnd(:tool_use)
            @test [event.text for event in rounds[2] if event isa LlmTextDelta] == ["Two."]
            @test last(rounds[2]) == LlmTurnEnd(:end_turn)
            # A second turn asks for the tool again.
            @test any(event -> event isa LlmToolUseStop, rounds[3])
        end

        @testset "a target that the window never draws is an error" begin
            message = try
                run_application_workload(Pair{String,String}[];
                                         steps = WorkloadStep[WorkloadClick(DrawnText("no such text"))],
                                         timeout = 2)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("The window did not draw the target of", message)
            @test occursin("DrawnText(\"no such text\", :first)", message)
        end

        @testset "a step after the end of the loop is an error" begin
            message = try
                run_application_workload(Pair{String,String}[];
                                         steps = WorkloadStep[WorkloadKey(:q; ctrl = true),
                                                              WorkloadWait(DrawnText("never drawn"))],
                                         timeout = 30)
                ""
            catch exception
                sprint(showerror, exception)
            end
            @test occursin("The loop of the window ended before", message)
            @test occursin("DrawnText(\"never drawn\", :first)", message)
        end

        @testset "a pick that is not a place is refused" begin
            @test_throws ArgumentError DrawnText("a"; pick = :middle)
        end
    end
end

"""
    test_window_workload()

The gestures of the window that the package of the platform compiles in its
workload each find their target, and no barrier of the editor catches a fault.
"""
function test_window_workload()
    @testset "the gestures of the window workload" begin
        @test run_window_workload() === nothing
    end
end

"""
    test_file_workload()

The gestures of a file, on the text file of the platform, each find their target:
the open from the Files pane, a click, a key, a save, an undo and the name
buffer.
"""
function test_file_workload()
    @testset "the gestures of a file" begin
        file = make_workload_file(TextFile)
        @test endswith(file.name, ".txt")
        @test occursin(file.shown, file.text)
        @test run_file_workload(TextFile) === nothing
    end
end
