# The workload of the application window: each step finds its target in what the
# window draws, through the loop of the window, and a step whose target the window
# never draws is an error that names the step.

# The tool of the toolbar whose label is `label`.
_toolbar_tool(label::AbstractString) =
    DrawnPart(input -> input isa WidgetToolbarItem && string(input.action.label) == label)

"""
    test_application_workload()

`run_application_workload` gives a menu, a popup, a tool of the toolbar, a row of
the Files pane, a tab, a context menu, keys and typed text to the application
window, and each step finds its target. A step whose target the window never
draws, and a step after the end of the loop, make it throw an error that names
the step.
"""
function test_application_workload()
    @testset "the workload of the application window" begin
        @testset "each step finds its target" begin
            files = ["a.txt" => "one two three\nfour\n", "b.txt" => "five\n"]
            steps = WorkloadStep[
                WorkloadClick(DrawnText("Help")),
                WorkloadClick(DrawnText("About")),
                WorkloadClick(_toolbar_tool("Files")),
                WorkloadClick(DrawnText("a.txt"; pick = :leftmost)),
                WorkloadKey(:return),
                WorkloadWait(DrawnText(r"four")),
                WorkloadClick(DrawnText(r"four")),
                WorkloadTyping("x"),
                WorkloadKey(:s; ctrl = true),
                WorkloadKey(:z; ctrl = true),
                WorkloadClick(DrawnText("Explorer"; pick = :topmost)),
                WorkloadClick(DrawnText("Files"; pick = :leftmost); button = :right),
                WorkloadClick(DrawnText("Open in a new tab")),
                WorkloadKey(:f1),
                WorkloadKey(:f1),
                WorkloadKey(:p; ctrl = true, shift = true),
                WorkloadTyping("ab"),
                WorkloadKey(:escape)]
            @test run_application_workload(files; steps) === nothing
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
