# The verbs that filter and sort a collection from code: the conditions and the
# keys as code writes them, the words that answer how the collection shows, the
# same reference before and after the first call, the empty calls that take the
# filter and the sort away, and the arrangement as a transparent wrapper.

function test_arrangement_program()
@testset "code filters and sorts a collection" begin
    vector(values) = CellVector(Cell[Cell(v) for v in values])
    make_runs() = vector([_ArrangementRun(1, "done", 0.31, vector(["a"])),
                          _ArrangementRun(2, "failed", 0.12, vector(["b"])),
                          _ArrangementRun(3, "done", 0.54, vector(["c"]))])
    runs = make_runs()
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    editor = build_editor(runs, natural; backend = HeadlessBackend(), devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = true, appearance = false, settings = false)
    run_frame!(editor)
    tab = only(editor.document.root.tabs)
    place = @reference(editor.document, root.tabs[1].content)
    frame!() = (drain_operations!(editor); run_frame!(editor))

    @testset "a filter and a sort, and the words that answer" begin
        text = filter_collection!(place, "status" => !=("failed"); editor)
        frame!()
        @test text isa Text && string(text) == "2 of 3 items: status ≠ \"failed\""
        @test tab.content isa ArrangementDocument && get_wrapped_document(tab.content) === runs
        # The same reference, now below an arrangement.
        @test string(sort_collection!(place, "delay" => :descending; editor)) ==
              "2 of 3 items: status ≠ \"failed\", ↓ delay"
        frame!()
        # A second filter replaces the conditions of the first.
        @test string(filter_collection!(place, "delay" => >(0.2), "id" => <=(3); editor)) ==
              "2 of 3 items: delay > 0.2, id ≤ 3, ↓ delay"
        frame!()
        @test occursin("2 of 3 items", describe_document(tab.content))
        @test_throws ArgumentError filter_collection!(place, "status" => (value -> true); editor)
        @test_throws ArgumentError sort_collection!(place, "delay" => :down; editor)
    end

    @testset "the empty calls take the filter and the sort away" begin
        @test string(filter_collection!(place; editor)) == "3 of 3 items: ↓ delay"
        frame!()
        @test string(sort_collection!(place; editor)) == "3 items, all in their own order"
        frame!()
        @test tab.content === runs
    end

    @testset "an arrangement is a transparent wrapper" begin
        study = _ArrangementStudy(Any[])
        arranged = ArrangementDocument(study, ArrangementEntry[])
        @test get_wrapped_document(arranged) === study
        @test get_edited_field(arranged) === :document
        other = _ArrangementStudy(Any[])
        @test replace_wrapped_document!(arranged, other) === arranged && arranged.document === other
    end
end
end
