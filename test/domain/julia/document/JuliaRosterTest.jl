# Example X4 of the plan of views across the documents of a session: the calls of
# one function in the Julia files of the tabs of a window, each with its file, and
# how many there are in each file.

using ProjecturedJulia.JuliaModule: parse_julia, JuliaFile, JuliaCall

function test_julia_roster()
@testset "a roster of the calls of one function in the Julia files of a window" begin
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    editor = build_editor(JuliaFile("a.jl", parse_julia("f(1)\ng(2)\nf(3)\n")), natural;
                          backend = HeadlessBackend(), devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = true, appearance = false, settings = false)
    run_frame!(editor)
    frame!() = (drain_operations!(editor); run_frame!(editor))
    open_pane!(JuliaFile("b.jl", parse_julia("f(4)\n")); title = "b.jl", editor)
    frame!()
    rows = show_roster!(ItemsWithin(TabDocuments(FileDocument), JuliaCall); title = "Uses of f",
                        columns = ["callee", "within.name"],
                        filter = ["callee" => ==("f")], group = ["within.name"], aggregates = [:count], editor)
    frame!()
    text = string(describe_roster(rows))
    @test startswith(text, "Uses of f: 2 groups of 4 items: callee = \"f\", by within.name: count")
    @test occursin("within.name | count\na.jl | 2\nb.jl | 1", text)
end
end
