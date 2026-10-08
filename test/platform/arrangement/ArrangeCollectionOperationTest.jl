# The operation that arranges a collection from a part inside it: the edits that
# an arrangement makes of it, the first arrangement of a document, and the
# readers that carry it out of a part in an editor, to the tab that holds a
# document that nobody arranged and then to the arrangement that holds it.

function test_arrange_collection_operation()
@testset "an operation arranges a collection from a part inside it" begin
    names = ["pear", "apple", "fig", "grape"]
    make_fruits() = CellVector(Cell[Cell(PrimitiveString(name)) for name in names])
    by_value(direction) = ArrangementSort(Any[ArrangementSortKey(EmptyReference(), direction)])
    keep_with(text) = ArrangementFilter(Any[ArrangementCondition(EmptyReference(), :contains, text)])
    arrange(description; at = EmptyReference()) = ArrangeCollectionOperation(at, description)
    is_removal(edit, document) = edit isa ReplaceReferencedValueOperation && edit.document === document &&
                                 edit.value == Any[]

    @testset "the edits of an arrangement" begin
        arranged = ArrangementDocument(make_fruits(), ArrangementEntry[])
        change!(description) = evaluate_operation(nothing, make_arrangement_change_edit(arranged, arrange(description)))
        change!(by_value(:ascending))
        entry = only(arranged.entries)
        @test entry.at == EmptyReference()
        sort = only(entry.projections)
        # A sort gives way to a sort, and keeps its identity, so its chain stays.
        change!(by_value(:descending))
        @test only(entry.projections) === sort
        @test only(sort.keys).direction === :descending
        # A filter goes before the sort.
        change!(keep_with("p"))
        @test entry.projections[1] isa ArrangementFilter && entry.projections[2] === sort
        # An empty sort takes the sort away, and then an empty filter the entry.
        change!(ArrangementSort(Any[]))
        @test only(entry.projections) isa ArrangementFilter
        @test is_removal(make_arrangement_change_edit(arranged, arrange(ArrangementFilter(Any[]))), arranged)
        # `nothing` takes the entry away, and changes nothing where there is none.
        @test is_removal(make_arrangement_change_edit(arranged, arrange(nothing)), arranged)
        runs = extend_reference(EmptyReference(), FieldReferenceStep("runs"))
        @test make_arrangement_change_edit(arranged, arrange(nothing; at = runs)) === nothing
        @test make_arrangement_change_edit(arranged, arrange(ArrangementSort(Any[]); at = runs)) === nothing
    end

    @testset "the first arrangement of a document" begin
        fruits = make_fruits()
        first = make_first_arrangement(fruits, arrange(by_value(:ascending)))
        @test first isa ArrangementDocument && first.document === fruits
        @test only(only(first.entries).projections) isa ArrangementSort
        @test make_first_arrangement(fruits, arrange(nothing)) === nothing
        @test make_first_arrangement(fruits, arrange(ArrangementFilter(Any[]))) === nothing
    end

    @testset "in an editor, the tab and then the arrangement answer it" begin
        fruits = make_fruits()
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        backend = HeadlessBackend()
        editor = build_editor(fruits, natural; backend, devices = Device[Keyboard(), Mouse(), Display()],
                              window = false, tabs = true, appearance = false, settings = false)
        run_frame!(editor)
        tab = only(editor.document.root.tabs)
        shown() = filter(in(names), _arrangement_texts(backend))
        # The operation at a place, lifted through the readers around it.
        function arrange_at!(place, description)
            operation = read_rooted_operation(editor, place, arrange(description))
            evaluate_operation(editor, operation)
            drain_operations!(editor)
            run_frame!(editor)
            operation
        end
        # A content that nobody arranged: the tab puts the first arrangement in
        # its place.
        operation = arrange_at!(@reference(editor.document, root.tabs[1].content), by_value(:descending))
        @test operation isa ReplaceReferencedValueOperation && operation.document === tab
        @test tab.content isa ArrangementDocument && tab.content.document === fruits
        @test shown() == ["pear", "grape", "fig", "apple"]
        # An arranged content: its arrangement makes the edit.
        inside = @reference(editor.document, root.tabs[1].content.document)
        arrange_at!(inside, keep_with("p"))
        @test length(only(tab.content.entries).projections) == 2
        @test shown() == ["pear", "grape", "apple"] && "3 of 4" in _arrangement_texts(backend)
        # Show all takes the last entry away, and the arrangement with it.
        arrange_at!(inside, nothing)
        @test tab.content === fruits
        @test shown() == names
    end
end
end
