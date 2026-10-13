# A group and the first items placed at a collection: the rows of the groups and
# their aggregates, a sort and the first items after a group, the table of the
# groups in the natural renderer, the verbs that group and limit a collection and
# the words that answer, and a group of the rows of a roster.

function test_arrangement_group()
@testset "a group and the first items placed at a collection" begin
    vector(values) = CellVector(Cell[Cell(v) for v in values])
    make_runs() = vector([_ArrangementRun(1, "done", 0.31, vector(["a"])),
                          _ArrangementRun(2, "failed", 0.12, vector(["b"])),
                          _ArrangementRun(3, "done", 0.54, vector(["c"]))])
    key(name) = extend_reference(EmptyReference(), FieldReferenceStep(name))
    by_status() = ArrangementGroup(Any[key("status")],
                                   Any[ArrangementAggregate(EmptyReference(), :count),
                                       ArrangementAggregate(key("delay"), :mean)])

    @testset "the rows of the groups and their aggregates" begin
        rows = compute_group_rows(by_status(), make_runs())
        @test [row.values[1] for row in rows] == ["done", "failed"]
        @test [row.values[2] for row in rows] == [2, 1]
        @test rows[1].values[3] ≈ 0.425 && rows[2].values[3] ≈ 0.12
        @test rows[1].columns == ["status", "count", "mean of delay"]
        @test rows[1].members == [1, 3]
        @test find_arrangement_key_value(rows[1], key("count")) == 2
        @test compute_arrangement_aggregate(Val(:sum), Any[1, 2.5, "x", nothing]) == 3.5
        @test compute_arrangement_aggregate(Val(:minimum), Any["x"]) === nothing
        @test compute_arrangement_aggregate(Val(:maximum), Any[3, 7, 5]) == 7
    end

    @testset "a sort and the first items after a group, in the natural renderer" begin
        runs = make_runs()
        arranged = ArrangementDocument(runs, ArrangementEntry[])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        io = print_document(natural, nothing, arranged, PrinterContext())
        texts() = _arrangement_drawn_texts(io.output)
        push!(arranged.entries, ArrangementEntry(EmptyReference(),
            Any[by_status(), ArrangementSort(Any[ArrangementSortKey(key("count"), :ascending)])]))
        drawn = texts()
        @test all(text -> text in drawn, ["status", "count", "mean of delay"])
        @test filter(text -> text in ("done", "failed"), drawn) == ["failed", "done"]
        push!(arranged.entries[1].projections, ArrangementFirst(1))
        drawn = texts()
        @test filter(text -> text in ("done", "failed"), drawn) == ["failed"]
        # A change of an item reaches the groups.
        runs[2].status = "done"
        drawn = texts()
        @test filter(text -> text in ("done", "failed"), drawn) == ["done"]
        @test "3" in drawn
    end

    @testset "the verbs that group and limit a collection, and the words that answer" begin
        runs = make_runs()
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        editor = build_editor(runs, natural; backend = HeadlessBackend(),
                              devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        place = @reference(editor.document, root.tabs[1].content)
        frame!() = (drain_operations!(editor); run_frame!(editor))
        @test string(group_collection!(place, "status"; aggregates = [:count, "delay" => :mean], editor)) ==
              "2 groups of 3 items: by status: count, mean of delay"
        frame!()
        @test string(sort_collection!(place, "count" => :descending; editor)) ==
              "2 groups of 3 items: by status: count, mean of delay, ↓ count"
        frame!()
        @test string(limit_collection!(place, 1; editor)) ==
              "1 group of 3 items: by status: count, mean of delay, ↓ count, first 1"
        frame!()
        @test string(limit_collection!(place; editor)) ==
              "2 groups of 3 items: by status: count, mean of delay, ↓ count"
        frame!()
        @test string(group_collection!(place; editor)) == "3 of 3 items: ↓ count"
        frame!()
        @test string(limit_collection!(place, 2; editor)) == "2 of 3 items: ↓ count, first 2"
        frame!()
        @test_throws ArgumentError group_collection!(place, "status"; aggregates = ["delay" => :median], editor)
        @test_throws ArgumentError limit_collection!(place, "two"; editor)
    end

    @testset "a group of the rows of a roster" begin
        runs = make_runs()
        roster = link_roster!(Roster(CollectionItems(runs); columns = ["id", "status"]), runs)
        arranged = ArrangementDocument(roster, ArrangementEntry[ArrangementEntry(key("rows"),
            Any[ArrangementGroup(Any[key("status")], Any[ArrangementAggregate(EmptyReference(), :count)])])])
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        io = print_document(natural, nothing, arranged, PrinterContext())
        drawn = _arrangement_drawn_texts(io.output)
        @test all(text -> text in drawn, ["status", "count", "done", "failed"])
        @test filter(text -> text in ("1", "2"), drawn)[end - 1:end] == ["2", "1"]
    end
end
end

# Every text that the graphics draw, in the order of the drawing.
function _arrangement_drawn_texts(node, found = String[])
    if node isa GraphicsCanvas
        foreach(element -> _arrangement_drawn_texts(element isa Cell ? element[] : element, found), node.elements)
    elseif node isa GraphicsViewport
        _arrangement_drawn_texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, string(node.text))
    end
    found
end
